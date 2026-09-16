import Foundation
import CoreLocation

/// Flota demo sobre los vértices originales del GTFS, en el sentido publicado.
final class SimulatedTrackingProvider: VehicleTrackingProviding {
    let source: VehicleTrackingSource = .simulated
    private(set) var currentPositions: [VehiclePosition] = []
    private var continuation: AsyncStream<[VehiclePosition]>.Continuation?
    private var stream: AsyncStream<[VehiclePosition]>?
    private var tickTask: Task<Void, Never>?
    private var loading: Task<Void, Never>?
    private var rebuildTask: Task<Void, Never>?
    private var rebuildWorker: Task<[Motion], Never>?
    private var rebuildGeneration = UUID()
    private var generation = UUID()
    private var previousTick: Date?
    private var center = GTFSRepository.coordenadaUTP
    private var routes: [RutaGTFS] = []
    private var preferredRouteID: String?

    private struct Motion {
        let route: RutaGTFS
        let cumulative: [Double]
        let speed: Double
        var distance: Double
        var segment: Int = 0
        /// Sentido de avance sobre el recorrido. Al llegar a un extremo el
        /// vehículo regresa por el mismo corredor en vez de quedarse parado.
        var haciaAdelante: Bool = true
    }
    private var fleet: [Motion] = []

    func start() {
        guard tickTask == nil, loading == nil else { return }
        let token = UUID()
        generation = token
        loading = Task { @MainActor [weak self] in
            let feed = await GTFSRepository.shared.rutas()
            guard let self, !Task.isCancelled, self.generation == token else { return }
            self.routes = feed.filter { $0.shape.count >= 2 }
            self.rebuild()
            self.previousTick = Date()
            self.iniciarTicks()
            self.loading = nil
        }
    }

    /// Bucle de simulación.
    ///
    /// Antes era un `Timer` cuya closure no estaba aislada al hilo principal:
    /// el compilador no podía verificar que `tick()` tocara estado de UI. Ahora
    /// es una única `Task` con `Task.sleep` entre ticks: aislada a
    /// `@MainActor`, cancelable de verdad y sin crear una tarea nueva por tick.
    private func iniciarTicks() {
        tickTask?.cancel()
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled, let self else { return }
                self.tick()
            }
        }
    }

    func stop() {
        generation = UUID()
        loading?.cancel()
        loading = nil
        rebuildGeneration = UUID()
        rebuildTask?.cancel()
        rebuildTask = nil
        rebuildWorker?.cancel()
        rebuildWorker = nil
        tickTask?.cancel()
        tickTask = nil
        previousTick = nil
        continuation?.finish()
        continuation = nil
        stream = nil
    }

    func positions() -> AsyncStream<[VehiclePosition]> {
        if let stream { return stream }
        let result = AsyncStream<[VehiclePosition]>(bufferingPolicy: .bufferingNewest(1)) { continuation in
            self.continuation = continuation
            continuation.yield(self.currentPositions)
        }
        stream = result
        return result
    }

    func setCenter(lat: Double, lon: Double) {
        center = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        rebuild()
    }

    func follow(routeID: String, near coordinate: CLLocationCoordinate2D) {
        preferredRouteID = routeID
        center = coordinate
        rebuild()
    }

    private func rebuild() {
        rebuildTask?.cancel()
        rebuildWorker?.cancel()
        let token = UUID()
        rebuildGeneration = token
        let routes = routes
        let center = center
        let preferredRouteID = preferredRouteID
        guard !routes.isEmpty else { return }
        // El matching de todo el feed no debe bloquear MapKit ni los toques.
        let worker = Task.detached(priority: .userInitiated) {
            Self.makeFleet(routes: routes, center: center, preferredRouteID: preferredRouteID)
        }
        rebuildWorker = worker
        rebuildTask = Task { @MainActor [weak self] in
            let result = await worker.value
            guard let self, !Task.isCancelled, self.rebuildGeneration == token else { return }
            self.fleet = result
            self.previousTick = Date()
            self.publish()
            self.rebuildTask = nil
            self.rebuildWorker = nil
        }
    }

    private static func makeFleet(routes: [RutaGTFS], center: CLLocationCoordinate2D,
                                  preferredRouteID: String?) -> [Motion] {
        var matches: [(RutaGTFS, PolylineMatching.MatchResult?)] = []
        for route in routes {
            guard !Task.isCancelled else { return [] }
            matches.append((route, PolylineMatching.match(point: center, on: route.shape)))
        }
        let ranked = matches.sorted {
            if ($0.0.id == preferredRouteID) != ($1.0.id == preferredRouteID) {
                return $0.0.id == preferredRouteID
            }
            return ($0.1?.distanceToRoute ?? .infinity) < ($1.1?.distanceToRoute ?? .infinity)
        }
        return ranked.prefix(12).enumerated().compactMap { index, entry in
            guard !Task.isCancelled else { return nil }
            let route = entry.0
            var cumulative = [0.0]
            for i in 1..<route.shape.count {
                cumulative.append(cumulative[i - 1] + PolylineMatching.distanceMeters(route.shape[i - 1], route.shape[i]))
            }
            guard let total = cumulative.last, total > 10 else { return nil }
            let anchor = (entry.1?.progressFraction ?? 0.5) * total
            let offset = Double(index % 4 + 1) * 130
            return Motion(route: route, cumulative: cumulative,
                          speed: min(12, max(4, total / Double(max(1, route.duracionMin) * 60))),
                          distance: max(0, anchor - offset))
        }
    }

    private func tick() {
        let now = Date()
        let dt = min(1, max(0, now.timeIntervalSince(previousTick ?? now)))
        previousTick = now
        for i in fleet.indices {
            let end = fleet[i].cumulative.last ?? 0
            guard end > 0 else { continue }
            let avance = fleet[i].speed * dt
            var d = fleet[i].distance + (fleet[i].haciaAdelante ? avance : -avance)
            // Extremo del recorrido: regresa por el mismo corredor, sin saltos.
            // Antes el vehículo se quedaba clavado en el extremo (ver publish).
            if d >= end {
                d = end
                fleet[i].haciaAdelante = false
            } else if d <= 0 {
                d = 0
                fleet[i].haciaAdelante = true
            }
            fleet[i].distance = d
        }
        publish()
    }

    private func publish() {
        var positions: [VehiclePosition] = []
        for i in fleet.indices {
            var motion = fleet[i]
            let points = motion.route.shape
            guard points.count >= 2 else { continue }

            // El tramo se ajusta incrementalmente en los dos sentidos: al
            // volver, el índice tiene que retroceder, no solo avanzar.
            if motion.haciaAdelante {
                while motion.segment < points.count - 2
                        && motion.distance > motion.cumulative[motion.segment + 1] {
                    motion.segment += 1
                }
            } else {
                while motion.segment > 0
                        && motion.distance < motion.cumulative[motion.segment] {
                    motion.segment -= 1
                }
            }

            let j = motion.segment
            let a = points[j], b = points[j + 1]
            let length = motion.cumulative[j + 1] - motion.cumulative[j]
            let fraction = length > 0 ? min(1, max(0, (motion.distance - motion.cumulative[j]) / length)) : 0

            var heading = atan2((b.longitude - a.longitude) * cos(a.latitude * .pi / 180),
                                b.latitude - a.latitude) * 180 / .pi
            if !motion.haciaAdelante { heading += 180 }   // de vuelta, mira al revés

            positions.append(VehiclePosition(id: "SIM-\(motion.route.id)", linea: motion.route.linea,
                lat: a.latitude + (b.latitude - a.latitude) * fraction,
                lon: a.longitude + (b.longitude - a.longitude) * fraction,
                heading: (heading + 360).truncatingRemainder(dividingBy: 360),
                // La velocidad es la crucero del vehículo. Antes se ponía a 0
                // al alcanzar el final y el vehículo no volvía a moverse: con
                // los minutos la flota entera se quedaba congelada.
                speed: motion.speed))
            fleet[i] = motion
        }
        currentPositions = positions
        continuation?.yield(positions)
    }
}
