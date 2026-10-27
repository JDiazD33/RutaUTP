//
//  ParaderosIluminados.swift
//  RutaUTP
//
//  Selección estable de paraderos a partir del feed GTFS. El feed no informa
//  sobre iluminación ni vigilancia: solo se eligen puntos cercanos y una
//  muestra repartida por la red.
//

import CoreLocation

/// Muestra estable del feed. GTFS no informa sobre iluminación ni vigilancia.
enum ParaderosIluminados {
    static func seleccionar(_ feed: [RutaGTFS], cantidad: Int = 24,
                            cercaDe referencia: CLLocationCoordinate2D = DestinosFijos.centroTrujillo) -> [ParaderoGTFS] {
        guard cantidad > 0 else { return [] }
        var seen = Set<String>()
        let stops = feed.flatMap(\.paraderos).sorted { $0.id < $1.id }.filter {
            let key = "\(Int(($0.lat * 1e6).rounded())):\(Int(($0.lon * 1e6).rounded()))"
            return seen.insert(key).inserted
        }
        guard !stops.isEmpty else { return [] }
        // La distancia se mide una sola vez por paradero, no por cada
        // comparación del ordenamiento de los miles de puntos del feed.
        var distancias: [(paradero: ParaderoGTFS, distancia: Double)] = stops.map { stop in
            let distancia = PolylineMatching.distanceMeters(stop.coordinate, referencia)
            return (paradero: stop, distancia: distancia)
        }
        distancias.sort { izquierda, derecha in
            if izquierda.distancia == derecha.distancia {
                return izquierda.paradero.id < derecha.paradero.id
            }
            return izquierda.distancia < derecha.distancia
        }
        let cercanos: [ParaderoGTFS] = distancias.map { $0.paradero }
        // Incluye opciones próximas a la referencia y una muestra repartida por la red.
        var result = Array(cercanos.prefix(min(8, cantidad)))
        let remaining = stops.filter { stop in !result.contains { $0.id == stop.id } }
        let slots = min(cantidad - result.count, remaining.count)
        if slots > 0 {
            for i in 0..<slots { result.append(remaining[i * remaining.count / slots]) }
        }
        return result
    }
}
