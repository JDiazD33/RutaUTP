// RoutePointValidation.swift
// Separado por responsabilidad; conserva el comportamiento existente.

import CoreLocation

// MARK: - Coherencia del punto con la ruta

/// Resultado de comprobar si un punto pertenece al recorrido de una ruta.
///
/// El reporte de un cambio de vía es un dato PÚBLICO y se cruza por dos cuentas
/// para darlo por bueno. Por eso no basta con que el pin se pueda mover a
/// cualquier sitio: un punto a tres manzanas de la ruta haría que dos personas
/// en ciudades distintas confirmaran un cierre de una vía que no tienen.
enum CoherenciaPunto {
    case coherente(distanciaM: Double)
    /// El punto está en la ruta (o a menos de `margenMetro`).
    case limite(distanciaM: Double)
    /// El punto NO pertenece a esta ruta. `distanciaM` es al del shape.
    case fueraDeRuta(distanciaM: Double)

    var esValido: Bool {
        if case .fueraDeRuta = self { return false }
        return true
    }

    var distanciaM: Double {
        switch self {
        case .coherente(let d), .limite(let d), .fueraDeRuta(let d): return d
        }
    }
}

enum VerificadorCoherencia {
    /// Distancia al shape a la que el punto todavía se considera de esta ruta.
    ///
    /// 60 m, no 10: los shapes del feed no siguen el trazo exacto de la calzada
    /// y los puntos GPS en un túnel o entre edificios se desvían más de lo que
    /// parece. Con 10 m se rechazarían reportes legítimos.
    static let margenMetro: Double = 60
    /// Por encima de esto ya no es "estaba cerca": es otro sitio.
    static let maximoMetro: Double = 400

    static func evaluar(point: CLLocationCoordinate2D, ruta: RutaGTFS) -> CoherenciaPunto? {
        guard ruta.shape.count >= 2 else { return nil }
        // `match` es nil si no pudo proyectar el punto sobre el shape.
        guard let m = PolylineMatching.match(point: point, on: ruta.shape,
                                             thresholdMeters: margenMetro) else {
            return nil
        }
        if m.distanceToRoute <= margenMetro { return .coherente(distanciaM: m.distanceToRoute) }
        if m.distanceToRoute <= maximoMetro { return .limite(distanciaM: m.distanceToRoute) }
        return .fueraDeRuta(distanciaM: m.distanceToRoute)
    }
}
