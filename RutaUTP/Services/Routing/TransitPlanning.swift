import Foundation
import CoreLocation
import MapKit

struct TransitRouteOptions {
    let candidates: [TransitItinerary]
    let alternatives: [TransitItinerary]
    let highlights: [TransitRouteHighlight]
    static let empty = TransitRouteOptions(candidates: [], alternatives: [], highlights: [])
}

enum TransitRouteCategory: CaseIterable {
    case recommended, fastest, closestBoarding
}

struct TransitRouteHighlight {
    var plan: TransitItinerary
    var categories: [TransitRouteCategory]
}

/// Un viaje directo o con un transbordo, usando paraderos y shapes del GTFS.
/// Los radios se verifican primero en línea recta y después sobre la caminata disponible.
struct TransitItinerary {
    let route: RutaGTFS
    let board: ParaderoGTFS
    let firstAlight: ParaderoGTFS
    var transfer: TransitTransfer?
    var alight: ParaderoGTFS { transfer?.alight ?? firstAlight }
    var walkToBoard: [CLLocationCoordinate2D]
    let bus: [CLLocationCoordinate2D]
    var walkToDestination: [CLLocationCoordinate2D]
    var walkingApproximate = true
    var walkToBoardMeters: Double { PolylineMatching.totalLengthMeters(walkToBoard) }
    let firstBusMeters: Double
    var busMeters: Double { firstBusMeters + (transfer?.busMeters ?? 0) }
    var walkToDestinationMeters: Double { PolylineMatching.totalLengthMeters(walkToDestination) }
    var coordinates: [CLLocationCoordinate2D] { walkToBoard + bus + (transfer?.walk ?? []) + (transfer?.bus ?? []) + walkToDestination }
    let busSpeed: Double

    /// Geometría del tramo en bus lista para DIBUJAR, decimada una sola vez.
    ///
    /// `bus` conserva todas las esquinas porque de él salen `busMeters` y el
    /// avance del viaje, pero para dibujar MapKit no gana nada con 500 puntos
    /// donde 250 se ven igual — y este tramo se pinta DOS veces (contorno claro
    /// + color de línea) en cada mapa que lo muestra.
    let busDibujo: [CLLocationCoordinate2D]

    init(route: RutaGTFS, board: ParaderoGTFS, alight: ParaderoGTFS,
         walkToBoard: [CLLocationCoordinate2D], bus: [CLLocationCoordinate2D],
         walkToDestination: [CLLocationCoordinate2D]) {
        self.route = route
        self.board = board
        self.firstAlight = alight
        self.walkToBoard = walkToBoard
        self.bus = bus
        self.walkToDestination = walkToDestination
        self.firstBusMeters = PolylineMatching.totalLengthMeters(bus)
        self.busSpeed = min(14, max(3, route.distanciaKm * 1000 / Double(max(1, route.duracionMin) * 60)))
        self.busDibujo = PolylineMatching.decimate(bus, maxPoints: 250)
    }

    var lineDescription: String {
        route.linea + (transfer.map { " → " + $0.route.linea } ?? "")
    }
    /// Una alternativa representa una combinación de líneas, no cada pareja de paraderos.
    var routeIDs: [String] { [route.id] + (transfer.map { [$0.route.id] } ?? []) }
    /// Distingue paraderos y vueltas de una misma línea. Resolver las caminatas
    /// no cambia esta identidad ni convierte la opción cercana en otra subida.
    var optionID: [String] {
        routeIDs + [board.id, firstAlight.id, transfer?.board.id ?? "", alight.id,
                    String(firstBusMeters), String(transfer?.busMeters ?? 0)]
    }
    var boardingWaitSeconds: Double { Double(max(0, route.headwayMin)) * 30 }
    var estimatedJourneySeconds: Double { totalSeconds + boardingWaitSeconds }
    static let maximumTransferWalk: Double = 350
    /// En la comparación del mapa un transbordo debe aportar dos tramos útiles.
    static let minimumTransferRideMeters: Double = 800
    var transferWalkMeters: Double { transfer?.walkMeters ?? 0 }
    var walkingWithinTransferLimit: Bool { transferWalkMeters <= Self.maximumTransferWalk }
    // Frecuencia del feed: espera media estimada, no una predicción en vivo.
    var transferWaitSeconds: Double {
        transfer.map { Double(max(0, $0.route.headwayMin)) * 30 + 120 } ?? 0
    }
    var totalSeconds: Double {
        (walkToBoardMeters + walkToDestinationMeters + transferWalkMeters) / 1.4
        + firstBusMeters / busSpeed + (transfer.map { $0.busMeters / $0.busSpeed } ?? 0)
        + transferWaitSeconds
    }

    func remainingSeconds(after meters: Double) -> Double {
        var traveled = max(0, meters)
        var seconds = 0.0
        var segments = [(walkToBoardMeters, 1.4), (firstBusMeters, busSpeed)]
        if let transfer {
            segments += [(transfer.walkMeters, 1.4), (transfer.busMeters, transfer.busSpeed)]
            if meters < walkToBoardMeters + firstBusMeters + transfer.walkMeters {
                seconds += transferWaitSeconds
            }
        }
        segments.append((walkToDestinationMeters, 1.4))
        for (distance, speed) in segments {
            seconds += max(0, distance - traveled) / speed
            traveled = max(0, traveled - distance)
        }
        return seconds
    }

    /// Conserva los mejores candidatos sin construir miles de polylines descartadas.
    static func candidates(in routes: [RutaGTFS], origin: CLLocationCoordinate2D,
                           destination: CLLocationCoordinate2D, radius: Double) -> [TransitItinerary] {
        var geometry: [TransitGeometryKey: TransitRouteGeometry] = [:]
        return search(in: routes, origin: origin, destination: destination, radius: radius, geometry: &geometry).candidates
    }

    fileprivate static func search(in routes: [RutaGTFS], origin: CLLocationCoordinate2D,
                                  destination: CLLocationCoordinate2D, radius: Double,
                                  geometry: inout [TransitGeometryKey: TransitRouteGeometry],
                                  trustedCatalog: Bool = false,
                                  includeLineAlternatives: Bool = false,
                                  requiredRouteIDs: [String]? = nil) -> TransitRouteOptions {
        guard radius.isFinite, radius > 0, CLLocationCoordinate2DIsValid(origin),
              CLLocationCoordinate2DIsValid(destination) else { return .empty }
        var prepared: [PreparedTransitRoute] = []
        for (routeIndex, route) in routes.enumerated()
        where route.shape.count >= 2 && route.paraderos.count >= 2 {
            if Task.isCancelled { return .empty }
            if let requiredRouteIDs, !requiredRouteIDs.contains(route.id) { continue }
            let start = route.paraderos.map { PolylineMatching.distanceMeters(origin, $0.coordinate) }
            let end = route.paraderos.map { PolylineMatching.distanceMeters(destination, $0.coordinate) }
            guard start.contains(where: { $0 <= radius }) || end.contains(where: { $0 <= radius }) else { continue }
            let cached: TransitRouteGeometry
            let key: TransitGeometryKey = trustedCatalog ? .catalogIndex(routeIndex) : .routeID(route.id)
            if let entry = geometry[key], trustedCatalog || entry.matches(route) {
                cached = entry
            } else {
                cached = TransitRouteGeometry(route: route)
                geometry[key] = cached
            }
            prepared.append(PreparedTransitRoute(route: route, geometry: cached,
                                                 startWalk: start, endWalk: end, radius: radius))
        }
        let maximumLatitude = prepared.flatMap { $0.route.paraderos }.map { abs($0.lat) }.max() ?? 0
        let cellSize = maximumTransferWalk * MKMapPointsPerMeterAtLatitude(min(85, maximumLatitude)) * 1.02
        // Cada mejor subida/bajada y cada rejilla se calculan una sola vez por línea.
        let minimumRide = includeLineAlternatives ? minimumTransferRideMeters : 50
        let departures = prepared.map { $0.bestDepartures(minimumRideMeters: minimumRide) }
        let closestDepartures = includeLineAlternatives
            ? prepared.map { $0.bestDepartures(closestBoarding: true, minimumRideMeters: minimumRide) } : []
        let arrivals = prepared.map { route in
            Dictionary(grouping: route.bestArrivals(minimumRideMeters: minimumRide)) {
                TransitGridCell(point: route.stopPoints[$0.0], size: cellSize)
            }
        }
        var choices: [TransitChoice] = []
        var closestTransferChoices: [TransitChoice] = []
        for (firstIndex, first) in prepared.enumerated() {
            if Task.isCancelled { return .empty }
            for board in first.boarding {
                for alight in first.arriving where first.validRide(board, alight) {
                    let score = first.startCost(board, alight) + first.endWalk[alight] / 1.4
                    choices.append(TransitChoice(first: firstIndex, board: board, exit: alight,
                        second: nil, enter: 0, alight: alight, score: score,
                        order: first.route.id, tie: "\(board):\(alight)"))
                }
            }
            guard !departures[firstIndex].isEmpty else { continue }
            for (secondIndex, second) in prepared.enumerated()
            where second.route.id != first.route.id && !second.arriving.isEmpty {
                func bestConnection(closestBoarding: Bool) -> TransitChoice? {
                    var best: (score: Double, walk: Double, board: Int, exit: Int, enter: Int, alight: Int)?
                    let nearby = arrivals[secondIndex]
                    let stops = closestBoarding ? closestDepartures[firstIndex] : departures[firstIndex]
                    for (board, exit) in stops {
                        if Task.isCancelled { return nil }
                        let boardWalk = first.startWalk[board] + first.connectorMeters[board]
                        if closestBoarding, let best, boardWalk > best.walk { continue }
                        let firstCost = first.startCost(board, exit)
                        let cell = TransitGridCell(point: first.stopPoints[exit], size: cellSize)
                        for dx in -1...1 {
                            for dy in -1...1 {
                                for (enter, alight) in nearby[TransitGridCell(x: cell.x + dx, y: cell.y + dy)] ?? [] {
                                    let lowerBound = firstCost + second.endCost(enter, alight)
                                    if let best, (!closestBoarding || boardWalk == best.walk),
                                       lowerBound >= best.score { continue }
                                    let walking = PolylineMatching.distanceMeters(first.route.paraderos[exit].coordinate,
                                                                                  second.route.paraderos[enter].coordinate)
                                    guard walking + first.connectorMeters[exit] + second.connectorMeters[enter] <= maximumTransferWalk else { continue }
                                    let score = lowerBound + walking / 1.4
                                    if best == nil || (closestBoarding && boardWalk < best!.walk)
                                        || score < best!.score {
                                        best = (score, boardWalk, board, exit, enter, alight)
                                    }
                                }
                            }
                        }
                    }
                    if let best {
                        let waiting = Double(max(0, second.route.headwayMin)) * 30 + 120
                        return TransitChoice(first: firstIndex, board: best.board, exit: best.exit,
                            second: secondIndex, enter: best.enter, alight: best.alight,
                            score: best.score + waiting + 180, order: first.route.id + second.route.id,
                            tie: "\(best.board):\(best.exit):\(best.enter):\(best.alight)")
                    }
                    return nil
                }
                if let best = bestConnection(closestBoarding: false) { choices.append(best) }
                if includeLineAlternatives, let nearest = bestConnection(closestBoarding: true) {
                    closestTransferChoices.append(nearest)
                }
            }
        }
        func precedes(_ lhs: TransitChoice, _ rhs: TransitChoice) -> Bool {
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.tie < rhs.tie
        }
        func routeIDs(_ choice: TransitChoice) -> [String] {
            [prepared[choice.first].route.id]
                + (choice.second.map { [prepared[$0].route.id] } ?? [])
        }
        func boardWalk(_ choice: TransitChoice) -> Double {
            let first = prepared[choice.first]
            return first.startWalk[choice.board] + first.connectorMeters[choice.board]
        }
        func journeyTime(_ choice: TransitChoice) -> Double {
            choice.score - (choice.second == nil ? 0 : 180)
                + Double(max(0, prepared[choice.first].route.headwayMin)) * 30
        }
        let fastestDirectTime = choices.lazy.filter { $0.second == nil }.map(journeyTime).min()
        func usefulForComparison(_ choice: TransitChoice) -> Bool {
            guard includeLineAlternatives, choice.second != nil,
                  let directTime = fastestDirectTime else { return true }
            // Tener que cambiar de micro no compensa pequeños ahorros del
            // modelo. Solo ofrecerlo frente a un directo en un viaje largo,
            // ahorrando como mínimo quince minutos y una cuarta parte del viaje.
            let saving = directTime - journeyTime(choice)
            return directTime >= 45 * 60 && saving >= max(15 * 60, directTime * 0.25)
        }
        let eligible = requiredRouteIDs.map { required in
            choices.filter { routeIDs($0) == required }
        } ?? choices.filter(usefulForComparison)
        let ranked = eligible.sorted(by: precedes)
        let selected: [TransitChoice]
        if includeLineAlternatives {
            var seen = Set<[String]>()
            var direct: [TransitChoice] = []
            var transfers: [TransitChoice] = []
            for choice in ranked {
                let ids = routeIDs(choice)
                guard seen.insert(ids).inserted else { continue }
                if choice.second == nil {
                    // Conservar todas las líneas directas: los transbordos y
                    // otras paradas de una línea no deben expulsar a otra línea.
                    direct.append(choice)
                } else if transfers.count < 32 {
                    transfers.append(choice)
                }
            }
            selected = (direct + transfers).sorted(by: precedes)
        } else {
            selected = []
        }
        func makePlan(_ choice: TransitChoice) -> TransitItinerary {
            let first = prepared[choice.first]
            var plan = first.plan(choice.board, choice.exit, origin: origin, destination: destination)
            if let secondIndex = choice.second {
                let next = prepared[secondIndex].plan(choice.enter, choice.alight, origin: origin, destination: destination)
                plan.transfer = TransitTransfer(route: next.route, board: next.board, alight: next.alight,
                    walk: [plan.bus.last!, plan.firstAlight.coordinate, next.board.coordinate, next.bus[0]],
                    bus: next.bus, busDibujo: next.busDibujo, busMeters: next.firstBusMeters, busSpeed: next.busSpeed)
                plan.walkToDestination = next.walkToDestination
            }
            return plan
        }
        func recommendationScore(_ choice: TransitChoice) -> Double {
            let first = prepared[choice.first]
            var walk = boardWalk(choice) + first.connectorMeters[choice.exit]
            if let secondIndex = choice.second {
                let second = prepared[secondIndex]
                walk += PolylineMatching.distanceMeters(first.route.paraderos[choice.exit].coordinate,
                                                        second.route.paraderos[choice.enter].coordinate)
                    + second.connectorMeters[choice.enter] + second.connectorMeters[choice.alight]
                    + second.endWalk[choice.alight]
            } else {
                walk += first.endWalk[choice.exit]
            }
            // Prima el tiempo; una caminata adicional sigue compensando cuando
            // ahorra bastante viaje. Tres minutos ponderan el transbordo.
            return journeyTime(choice) + 0.35 * walk / 1.4 + (choice.second == nil ? 0 : 180)
        }
        func minimum(in pool: [TransitChoice], score: (TransitChoice) -> Double) -> TransitChoice? {
            pool.min { lhs, rhs in
                let a = score(lhs), b = score(rhs)
                return a == b ? precedes(lhs, rhs) : a < b
            }
        }
        var highlights: [TransitRouteHighlight] = []
        if includeLineAlternatives {
            let winners: [(TransitRouteCategory, TransitChoice?)] = [
                (.recommended, minimum(in: eligible, score: recommendationScore)),
                (.fastest, minimum(in: eligible, score: journeyTime)),
                (.closestBoarding, (eligible + closestTransferChoices.filter(usefulForComparison)).min { lhs, rhs in
                    let a = boardWalk(lhs), b = boardWalk(rhs)
                    if a != b { return a < b }
                    let t1 = journeyTime(lhs), t2 = journeyTime(rhs)
                    return t1 == t2 ? precedes(lhs, rhs) : t1 < t2
                })
            ]
            for (category, winner) in winners {
                guard let winner else { continue }
                let plan = makePlan(winner)
                if let index = highlights.firstIndex(where: { $0.plan.optionID == plan.optionID }) {
                    highlights[index].categories.append(category)
                } else {
                    highlights.append(TransitRouteHighlight(plan: plan, categories: [category]))
                }
            }
        }
        var alternatives = selected.map(makePlan)
        for highlight in highlights where !alternatives.contains(where: { $0.optionID == highlight.plan.optionID }) {
            alternatives.append(highlight.plan)
        }
        // La vía anterior conserva su orden y límite para tracking y consumidores.
        return TransitRouteOptions(candidates: ranked.prefix(32).map(makePlan),
                                   alternatives: alternatives, highlights: highlights)
    }

    func withWalkingDirections(using service: RouteCalculationService) async -> TransitItinerary {
        var result = self
        guard let origin = walkToBoard.first, let destination = walkToDestination.last else { return result }
        // Como máximo tres peticiones simultáneas, solo para el candidato actual.
        async let firstRequest = service.calculateRoute(from: origin, to: board.coordinate, transportType: .walking)
        async let lastRequest = service.calculateRoute(from: alight.coordinate, to: destination, transportType: .walking)
        async let transferRequest: CalculatedRoute? = walkingTransfer(using: service)
        let first = try? await firstRequest
        let last = try? await lastRequest
        let connectionDirections = await transferRequest
        if Task.isCancelled { return result }
        if let first {
            let points = PolylineMatching.coordinates(from: first.polyline)
            if points.count >= 2 { result.walkToBoard = [origin] + points + [board.coordinate, bus[0]] }
        }
        if let last {
            let points = PolylineMatching.coordinates(from: last.polyline)
            if points.count >= 2 { result.walkToDestination = [(transfer?.bus.last ?? bus.last)!, alight.coordinate] + points + [destination] }
        }
        result.walkingApproximate = first == nil || last == nil || (first?.polyline.pointCount ?? 0) < 2 || (last?.polyline.pointCount ?? 0) < 2
        if Task.isCancelled { return result }
        if let connection = transfer {
            if let directions = connectionDirections, directions.polyline.pointCount >= 2 {
                result.transfer?.walk = [bus.last!, firstAlight.coordinate]
                    + PolylineMatching.coordinates(from: directions.polyline)
                    + [connection.board.coordinate, connection.bus[0]]
            } else {
                result.walkingApproximate = true
            }
        }
        return result
    }
    private func walkingTransfer(using service: RouteCalculationService) async -> CalculatedRoute? {
        guard let transfer else { return nil }
        return try? await service.calculateRoute(from: firstAlight.coordinate,
                                                to: transfer.board.coordinate, transportType: .walking)
    }

}

struct TransitTransfer {
    let route: RutaGTFS
    let board: ParaderoGTFS
    let alight: ParaderoGTFS
    var walk: [CLLocationCoordinate2D]
    let bus: [CLLocationCoordinate2D]
    let busDibujo: [CLLocationCoordinate2D]
    let busMeters: Double
    let busSpeed: Double
    var walkMeters: Double { PolylineMatching.totalLengthMeters(walk) }
}

private struct TransitGridCell: Hashable {
    let x: Int
    let y: Int
    init(x: Int, y: Int) { self.x = x; self.y = y }
    init(point: MKMapPoint, size: Double) {
        x = Int(floor(point.x / size))
        y = Int(floor(point.y / size))
    }
}

private struct TransitChoice {
    let first: Int
    let board: Int
    let exit: Int
    let second: Int?
    let enter: Int
    let alight: Int
    let score: Double
    let order: String
    let tie: String
}

/// Los arrays sin identidad siguen usando ID y comparación de geometría.
/// Un catálogo inmutable distingue también entradas con el mismo route_id.
fileprivate enum TransitGeometryKey: Hashable {
    case routeID(String)
    case catalogIndex(Int)
}

/// Geometría inmutable reutilizable entre búsquedas, invalidada si cambia el feed.
fileprivate struct TransitRouteGeometry {
    let route: RutaGTFS
    let indices: [Int]
    let distances: [Double]
    let connectorMeters: [Double]
    let stopPoints: [MKMapPoint]

    func matches(_ other: RutaGTFS) -> Bool {
        route.paraderos == other.paraderos && route.shape.elementsEqual(other.shape) {
            $0.latitude == $1.latitude && $0.longitude == $1.longitude
        }
    }
    init(route: RutaGTFS) {
        self.route = route
        stopPoints = route.paraderos.map { MKMapPoint($0.coordinate) }
        let shapePoints = route.shape.map { MKMapPoint($0) }
        var indices: [Int] = []
        var lower = 0
        for stop in route.paraderos {
            let point = MKMapPoint(stop.coordinate)
            var nearest = lower
            var bestDistance = Double.infinity
            for index in lower..<shapePoints.count {
                let dx = point.x - shapePoints[index].x
                let dy = point.y - shapePoints[index].y
                let distance = dx * dx + dy * dy
                if distance < bestDistance {
                    bestDistance = distance
                    nearest = index
                }
            }
            lower = nearest
            indices.append(lower)
        }
        self.indices = indices
        let connectorMeters = route.paraderos.indices.map {
            PolylineMatching.distanceMeters(route.paraderos[$0].coordinate, route.shape[indices[$0]])
        }
        self.connectorMeters = connectorMeters
        var distances = [0.0]
        for i in 1..<route.shape.count {
            distances.append(distances.last! + PolylineMatching.distanceMeters(route.shape[i-1], route.shape[i]))
        }
        self.distances = distances
    }
}

private struct PreparedTransitRoute {
    let route: RutaGTFS
    let indices: [Int]
    let distances: [Double]
    let connectorMeters: [Double]
    let stopPoints: [MKMapPoint]
    let startWalk: [Double]
    let endWalk: [Double]
    let boarding: [Int]
    let arriving: [Int]
    let speed: Double

    init(route: RutaGTFS, geometry: TransitRouteGeometry, startWalk: [Double], endWalk: [Double], radius: Double) {
        self.route = route
        indices = geometry.indices
        distances = geometry.distances
        connectorMeters = geometry.connectorMeters
        stopPoints = geometry.stopPoints
        self.startWalk = startWalk
        self.endWalk = endWalk
        speed = min(14, max(3, route.distanciaKm * 1000 / Double(max(1, route.duracionMin) * 60)))
        boarding = route.paraderos.indices.filter { startWalk[$0] + geometry.connectorMeters[$0] <= radius }
        arriving = route.paraderos.indices.filter { endWalk[$0] + geometry.connectorMeters[$0] <= radius }
    }
    /// Barrido ordenado: mantener la mejor subida anterior evita volver a
    /// comparar todas las subidas en cada paradero y en cada pareja de líneas.
    func bestDepartures(closestBoarding: Bool = false, minimumRideMeters: Double = 50) -> [(Int, Int)] {
        let eligible = boarding.filter { connectorMeters[$0] < 80 }
        var cursor = 0
        var best: (stop: Int, cost: Double)?
        var result: [(Int, Int)] = []
        for exit in route.paraderos.indices {
            while cursor < eligible.count {
                let board = eligible[cursor]
                guard board < exit, distances[indices[exit]] - distances[indices[board]] > minimumRideMeters else { break }
                let cost = (startWalk[board] + connectorMeters[board]) / 1.4 - distances[indices[board]] / speed
                let walk = startWalk[board] + connectorMeters[board]
                let bestWalk = best.map { startWalk[$0.stop] + connectorMeters[$0.stop] } ?? .infinity
                if best == nil || (closestBoarding && walk < bestWalk)
                    || ((!closestBoarding || walk == bestWalk) && cost < best!.cost) {
                    best = (board, cost)
                }
                cursor += 1
            }
            if connectorMeters[exit] < 80, let best { result.append((best.stop, exit)) }
        }
        return result
    }

    func bestArrivals(minimumRideMeters: Double = 50) -> [(Int, Int)] {
        let eligible = Array(arriving.filter { connectorMeters[$0] < 80 }.reversed())
        var cursor = 0
        var best: (stop: Int, cost: Double)?
        var result: [(Int, Int)] = []
        for enter in route.paraderos.indices.reversed() {
            while cursor < eligible.count {
                let alight = eligible[cursor]
                guard alight > enter, distances[indices[alight]] - distances[indices[enter]] > minimumRideMeters else { break }
                let cost = (endWalk[alight] + connectorMeters[alight]) / 1.4 + distances[indices[alight]] / speed
                if best == nil || cost <= best!.cost { best = (alight, cost) }
                cursor += 1
            }
            if connectorMeters[enter] < 80, let best { result.append((enter, best.stop)) }
        }
        return result.reversed()
    }

    func validRide(_ board: Int, _ alight: Int) -> Bool {
        alight > board && distances[indices[alight]] - distances[indices[board]] > 50
        && connectorMeters[board] < 80 && connectorMeters[alight] < 80
    }
    func startCost(_ board: Int, _ alight: Int) -> Double {
        (startWalk[board] + connectorMeters[board] + connectorMeters[alight]) / 1.4
        + (distances[indices[alight]] - distances[indices[board]]) / speed
    }
    func endCost(_ board: Int, _ alight: Int) -> Double {
        (endWalk[alight] + connectorMeters[board] + connectorMeters[alight]) / 1.4
        + (distances[indices[alight]] - distances[indices[board]]) / speed
    }
    func plan(_ board: Int, _ alight: Int, origin: CLLocationCoordinate2D,
              destination: CLLocationCoordinate2D) -> TransitItinerary {
        let segment = Array(route.shape[indices[board]...indices[alight]])
        return TransitItinerary(route: route, board: route.paraderos[board], alight: route.paraderos[alight],
            walkToBoard: [origin, route.paraderos[board].coordinate, segment[0]], bus: segment,
            walkToDestination: [segment.last!, route.paraderos[alight].coordinate, destination])
    }
}

/// El cálculo geométrico del feed no bloquea los gestos ni las animaciones.
actor TransitPlanner {
    static let shared = TransitPlanner()
    private var geometry: [TransitGeometryKey: TransitRouteGeometry] = [:]
    private var catalog: GTFSRouteCatalog?

    /// Vía de compatibilidad para arrays sin una identidad de catálogo.
    func candidates(in routes: [RutaGTFS], origin: CLLocationCoordinate2D,
                    destination: CLLocationCoordinate2D, radius: Double) -> [TransitItinerary] {
        catalog = nil
        let ids = Set(routes.map(\.id))
        geometry = geometry.filter {
            guard case .routeID(let id) = $0.key else { return false }
            return ids.contains(id)
        }
        return TransitItinerary.search(in: routes, origin: origin, destination: destination,
                                       radius: radius, geometry: &geometry).candidates
    }

    /// La revisión pertenece al snapshot completo; cambiarlo invalida todo,
    /// aunque se repitan IDs. La posición distingue las entradas duplicadas.
    func candidates(in catalog: GTFSRouteCatalog, origin: CLLocationCoordinate2D,
                    destination: CLLocationCoordinate2D, radius: Double) -> [TransitItinerary] {
        if self.catalog?.sharesRevision(with: catalog) != true {
            geometry.removeAll(keepingCapacity: true)
            self.catalog = catalog
        }
        return TransitItinerary.search(in: catalog.routes, origin: origin, destination: destination,
                                       radius: radius, geometry: &geometry, trustedCatalog: true).candidates
    }

    /// Todas las líneas directas, hasta 32 transbordos y los tres criterios destacados.
    /// Solo resuelve geometría local; las caminatas se consultan al elegir.
    func options(in catalog: GTFSRouteCatalog, origin: CLLocationCoordinate2D,
                 destination: CLLocationCoordinate2D, radius: Double) -> TransitRouteOptions {
        if self.catalog?.sharesRevision(with: catalog) != true {
            geometry.removeAll(keepingCapacity: true)
            self.catalog = catalog
        }
        return TransitItinerary.search(in: catalog.routes, origin: origin, destination: destination,
                                       radius: radius, geometry: &geometry, trustedCatalog: true,
                                       includeLineAlternatives: true)
    }

    /// Reintentos de paraderos de la combinación elegida, sin sustituir sus líneas.
    func candidates(for routeIDs: [String], in catalog: GTFSRouteCatalog,
                    origin: CLLocationCoordinate2D, destination: CLLocationCoordinate2D,
                    radius: Double) -> [TransitItinerary] {
        if self.catalog?.sharesRevision(with: catalog) != true {
            geometry.removeAll(keepingCapacity: true)
            self.catalog = catalog
        }
        return TransitItinerary.search(in: catalog.routes, origin: origin, destination: destination,
                                       radius: radius, geometry: &geometry, trustedCatalog: true,
                                       requiredRouteIDs: routeIDs).candidates
    }
}
