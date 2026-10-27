//
//  MapaViewModel+SimulacionBuses.swift
//  RutaUTP
//
//  Geometría y reparto de la flota simulada sobre los shapes del feed.
//  Solo construye la flota; el avance por tick vive en MapaViewModel.swift.
//

import MapKit

extension MapaViewModel {
    /// Construye un bus animado por ruta del feed.
    static func busesDesde(_ feed: [RutaGTFS],
                                   ancla: CLLocationCoordinate2D) -> [BusAnimado] {
        let n = max(feed.count, 1)
        return feed.enumerated().compactMap { index, ruta in
            // Sin geometría suficiente no hay nada que animar. Antes se caía a
            // un trazado de demostración, así que el mapa mostraba un bus
            // recorriendo una línea que no era la suya.
            let waypoints = decimarCoordenadas(ruta.shape, maximoPuntos: 240)
            guard waypoints.count >= 2 else { return nil }
            let acumulados = distanciasAcumuladas(waypoints)

            var bus = BusAnimado(
                id: "simulated-\(ruta.id)",
                linea: ruta.linea,
                rutaId: ruta.id,
                empresa: ruta.empresa,
                tipo: "Bus",
                variante: ruta.variante,
                minutosLlegada: max(1, 2 + index * max(1, ruta.headwayMin / n)),
                colorDeRuta: ruta.color,
                lat: waypoints[0].latitude,
                lon: waypoints[0].longitude,
                heading: 0,
                rutaCoordenadas: waypoints,
                acumulados: acumulados
            )

            // Nacimiento REPARTIDO por el corredor: se toma el tramo del
            // shape más cercano al punto consultado y cada vehículo arranca
            // de un punto distinto a su alrededor (±1.8 km), con dirección y
            // velocidad propias. Si varias líneas comparten avenida, quedan
            // escalonadas a lo largo de ella y no amontonadas en un punto.
            let idxAncla = waypointMasCercano(waypoints, a: ancla)
            let distanciaAnclaM = acumulados.isEmpty ? 0 : acumulados[idxAncla]
            // Fracciones de Fibonacci (0.618) escalonan los arranques de
            // forma determinista (~38% del rango entre vecinos); el jitter
            // aleatorio evita que dos recargas se vean idénticas.
            let fraccion = fmod(Double(index) * 0.6180339887, 1.0)
            let offsetM = fraccion * 3600 - 1800 + Double.random(in: -120...120)
            // Se envuelve módulo la longitud del recorrido (un vehículo en
            // otro ciclo de la línea) en vez de amontonar en los extremos.
            var d = distanciaAnclaM + offsetM
            let total = bus.longitudRutaM
            if total > 0 {
                d = d.truncatingRemainder(dividingBy: total)
                if d < 0 { d += total }
            }
            bus.distanciaM = d
            bus.velocidadMS = Double.random(in: 7...12)   // 25–43 km/h
            bus.isMovingForward = Bool.random()
            bus.actualizarPosicion()
            return bus
        }
    }

    /// Distancia acumulada (metros) de cada waypoint respecto al inicio.
    private static func distanciasAcumuladas(_ pts: [CLLocationCoordinate2D]) -> [Double] {
        guard !pts.isEmpty else { return [] }
        var acc: [Double] = [0]
        acc.reserveCapacity(pts.count)
        for j in 1..<pts.count {
            acc.append(acc[j - 1] + PolylineMatching.distanceMeters(pts[j - 1], pts[j]))
        }
        return acc
    }

    /// Índice del waypoint más cercano a un punto (distancia planar:
    /// solo sirve para elegir un índice, no para medir).
    private static func waypointMasCercano(_ puntos: [CLLocationCoordinate2D],
                                           a destino: CLLocationCoordinate2D) -> Int {
        var mejor = 0
        var mejorD = Double.greatestFiniteMagnitude
        for (i, p) in puntos.enumerated() {
            let d = (p.latitude - destino.latitude) * (p.latitude - destino.latitude)
                  + (p.longitude - destino.longitude) * (p.longitude - destino.longitude)
            if d < mejorD { mejorD = d; mejor = i }
        }
        return mejor
    }

    /// Reduce la densidad de un shape conservando el orden (perf del timer).
    private static func decimarCoordenadas(_ puntos: [CLLocationCoordinate2D],
                                           maximoPuntos: Int) -> [CLLocationCoordinate2D] {
        guard puntos.count > maximoPuntos else { return puntos }
        let paso = Double(puntos.count) / Double(maximoPuntos)
        var resultado: [CLLocationCoordinate2D] = []
        resultado.reserveCapacity(maximoPuntos)
        for j in 0..<maximoPuntos {
            resultado.append(puntos[min(Int(Double(j) * paso), puntos.count - 1)])
        }
        if let ultima = puntos.last, resultado.last?.latitude != ultima.latitude
                                                || resultado.last?.longitude != ultima.longitude {
            resultado.append(ultima)
        }
        return resultado
    }
}
