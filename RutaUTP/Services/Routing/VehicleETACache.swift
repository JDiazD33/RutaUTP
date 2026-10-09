import CoreLocation

/// Caché local al mapa, limitada al catálogo instalado y a un solo destino.
/// Se usa desde el actor principal del ViewModel; no crea tareas ni timers.
struct VehicleETACache {
    private var catalog: [String: RutaGTFS] = [:]
    private var routes: [String: VehicleETAEstimator.PreparedRoute] = [:]
    private var targets: [String: VehicleETAEstimator.PreparedTarget] = [:]
    private var targetKey: TargetKey?

    /// Cada instalación es una revisión nueva, aunque conserve los route_id.
    /// No se compara ni recorre el shape para validar la caché en cada snapshot.
    mutating func install(catalog: [String: RutaGTFS]) {
        self.catalog = catalog
        routes.removeAll()
        targets.removeAll()
        targetKey = nil
    }

    mutating func minutes(position: VehiclePosition, target: CLLocationCoordinate2D) -> Int? {
        let key = TargetKey(target)
        if targetKey != key {
            targetKey = key
            targets.removeAll(keepingCapacity: true)
        }

        guard let route = catalog[position.routeId] else { return nil }
        let preparedRoute: VehicleETAEstimator.PreparedRoute
        if let cached = routes[route.id] {
            preparedRoute = cached
        } else {
            guard let prepared = VehicleETAEstimator.PreparedRoute(route: route) else { return nil }
            routes[route.id] = prepared
            preparedRoute = prepared
        }

        let preparedTarget: VehicleETAEstimator.PreparedTarget
        if let cached = targets[route.id] {
            preparedTarget = cached
        } else {
            let prepared = VehicleETAEstimator.PreparedTarget(route: preparedRoute, target: target)
            targets[route.id] = prepared
            preparedTarget = prepared
        }

        return VehicleETAEstimator.minutes(position: position, prepared: preparedTarget)
    }

    /// Coordenadas exactas, sin redondeo ni tolerancia que alteren la proyección.
    private struct TargetKey: Equatable {
        let latitude: UInt64
        let longitude: UInt64

        init(_ coordinate: CLLocationCoordinate2D) {
            latitude = coordinate.latitude.bitPattern
            longitude = coordinate.longitude.bitPattern
        }
    }
}
