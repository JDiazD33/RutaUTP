import Foundation
import MapKit

enum RouteCalculationError: Error, Equatable {
    case noRoutesAvailable
    case appleDirectionsFailed(String)
    case invalidRequest
    case timedOut
}

struct CalculatedRoute: Equatable {
    let polyline: MKPolyline
    /// Tiempo estimado en segundos.
    let expectedTravelTime: TimeInterval
    /// Distancia en metros.
    let distance: Double
    /// Pasos (instrucciones) de la ruta.
    let steps: [MKRoute.Step]

    static func == (lhs: CalculatedRoute, rhs: CalculatedRoute) -> Bool {
        lhs.expectedTravelTime == rhs.expectedTravelTime &&
        lhs.distance == rhs.distance &&
        lhs.polyline.pointCount == rhs.polyline.pointCount
    }
}

/// Caché y peticiones compartidas por extremos exactos y modo, por instancia.
/// Cancelar un consumidor no interrumpe una caminata que otro sigue esperando.
actor RouteCalculationService {
    typealias Loader = @Sendable (MKDirections.Request) async throws -> CalculatedRoute
    private struct Key: Hashable {
        let lat1: Double
        let lon1: Double
        let lat2: Double
        let lon2: Double
        let transport: UInt
    }
    private struct Entry {
        let route: CalculatedRoute
        let date: Date
    }
    private struct InFlightRequest {
        let generation: UUID
        let task: Task<Void, Never>
        let startedAt: Date
        var consumers: [UUID: CheckedContinuation<CalculatedRoute, Error>]
    }
    private let loader: Loader
    private let now: @Sendable () -> Date
    private var cache: [Key: Entry] = [:]
    private var inFlight: [Key: InFlightRequest] = [:]

    init(loader: @escaping Loader = { request in
        try await PendingDirections(request: request).run()
    }, now: @escaping @Sendable () -> Date = { Date() }) {
        self.loader = loader
        self.now = now
    }

    func calculateRoute(from origin: CLLocationCoordinate2D,
                        to destination: CLLocationCoordinate2D,
                        transportType: MKDirectionsTransportType = .transit) async throws -> CalculatedRoute {
        try Task.checkCancellation()
        guard CLLocationCoordinate2DIsValid(origin), CLLocationCoordinate2DIsValid(destination) else {
            throw RouteCalculationError.invalidRequest
        }
        let key = Key(lat1: origin.latitude, lon1: origin.longitude,
                      lat2: destination.latitude, lon2: destination.longitude, transport: transportType.rawValue)
        let date = now()
        if let entry = cache[key], date.timeIntervalSince(entry.date) < 300 { return entry.route }
        let consumerID = UUID()
        let route: CalculatedRoute = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // onCancel también se invoca si la tarea ya estaba cancelada.
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                register(continuation, consumerID: consumerID, key: key, date: date,
                         origin: origin, destination: destination, transportType: transportType)
            }
        } onCancel: {
            Task { await self.cancelConsumer(consumerID, key: key) }
        }
        try Task.checkCancellation()
        return route
    }

    private func register(_ continuation: CheckedContinuation<CalculatedRoute, Error>,
                          consumerID: UUID, key: Key, date: Date,
                          origin: CLLocationCoordinate2D, destination: CLLocationCoordinate2D,
                          transportType: MKDirectionsTransportType) {
        if var request = inFlight[key] {
            request.consumers[consumerID] = continuation
            inFlight[key] = request
            return
        }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = transportType
        request.requestsAlternateRoutes = false
        let generation = UUID()
        let task = Task {
            let result: Result<CalculatedRoute, Error>
            do {
                try Task.checkCancellation()
                let route = try await loader(request)
                try Task.checkCancellation()
                result = .success(route)
            } catch {
                result = .failure(error)
            }
            finishRequest(key: key, generation: generation, result: result)
        }
        inFlight[key] = InFlightRequest(generation: generation, task: task, startedAt: date,
                                       consumers: [consumerID: continuation])
    }

    private func finishRequest(key: Key, generation: UUID, result: Result<CalculatedRoute, Error>) {
        // Una respuesta antigua no puede retirar ni completar un reintento.
        guard let request = inFlight[key], request.generation == generation else { return }
        inFlight[key] = nil
        if case .success(let route) = result {
            cache = cache.filter { request.startedAt.timeIntervalSince($0.value.date) < 300 }
            if cache.count >= 128, let oldest = cache.min(by: { $0.value.date < $1.value.date })?.key {
                cache[oldest] = nil
            }
            cache[key] = Entry(route: route, date: now())
        }
        for continuation in request.consumers.values { continuation.resume(with: result) }
    }

    private func cancelConsumer(_ consumerID: UUID, key: Key) {
        guard var request = inFlight[key],
              let continuation = request.consumers.removeValue(forKey: consumerID) else { return }
        if request.consumers.isEmpty {
            inFlight[key] = nil
            request.task.cancel()
        } else {
            inFlight[key] = request
        }
        continuation.resume(throwing: CancellationError())
    }

    /// Cancela todas las esperas de esta instancia; conserva las rutas cacheadas.
    func cancel() {
        let requests = inFlight
        inFlight.removeAll()
        for request in requests.values {
            request.task.cancel()
            for continuation in request.consumers.values {
                continuation.resume(throwing: CancellationError())
            }
        }
    }
}

/// Una sola finalización: respuesta, cancelación o plazo máximo. MKDirections
/// se cancela de verdad y un callback tardío nunca reanuda dos veces la espera.
@MainActor
final class PendingDirections {
    typealias Completion = @Sendable (Result<CalculatedRoute, Error>) -> Void
    private let startRequest: (@escaping Completion) -> Void
    private let cancelRequest: () -> Void
    private var continuation: CheckedContinuation<CalculatedRoute, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var finished = false

    convenience init(request: MKDirections.Request) {
        let directions = MKDirections(request: request)
        self.init(start: { completion in
            directions.calculate { response, error in
                if let error {
                    completion(.failure(RouteCalculationError.appleDirectionsFailed(error.localizedDescription)))
                } else if let route = response?.routes.first {
                    completion(.success(CalculatedRoute(polyline: route.polyline,
                        expectedTravelTime: route.expectedTravelTime, distance: route.distance, steps: route.steps)))
                } else {
                    completion(.failure(RouteCalculationError.noRoutesAvailable))
                }
            }
        }, cancel: { directions.cancel() })
    }

    /// Transporte inyectable para probar el plazo y callbacks tardíos sin red.
    init(start: @escaping (@escaping Completion) -> Void, cancel: @escaping () -> Void) {
        startRequest = start
        cancelRequest = cancel
    }

    func run(timeout: TimeInterval = 4) async throws -> CalculatedRoute {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                startRequest { result in
                    Task { @MainActor in self.finish(result) }
                }
                timeoutTask = Task { @MainActor in
                    do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
                    finish(.failure(RouteCalculationError.timedOut))
                }
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError())) }
        }
    }

    private func finish(_ result: Result<CalculatedRoute, Error>) {
        guard !finished else { return }
        finished = true
        timeoutTask?.cancel()
        timeoutTask = nil
        cancelRequest()
        continuation?.resume(with: result)
        continuation = nil
    }
}
