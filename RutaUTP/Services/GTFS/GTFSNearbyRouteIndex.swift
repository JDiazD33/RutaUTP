//
//  GTFSNearbyRouteIndex.swift
//  RutaUTP
//
//  Prefiltro conservador de recorridos para el panel de líneas cercanas.
//

import Foundation
import CoreLocation

struct GTFSNearbyRouteIndex {
    private struct Entrada {
        let ruta: RutaGTFS
        let limites: LimitesRecorrido?
    }

    private let entradas: [Entrada]

    init(rutas: [RutaGTFS]) {
        entradas = rutas.map { Entrada(ruta: $0, limites: LimitesRecorrido(shape: $0.shape)) }
    }

    /// Mantiene el orden y los duplicados del catálogo. La selección final
    /// sigue usando distanciaMinima y la política de 400/800 m de O09.
    func rutasCandidatas(cercaDe punto: CLLocationCoordinate2D,
                         radioMetros: Double) -> [RutaGTFS] {
        guard let zona = LimitesRecorrido(punto: punto, radioMetros: radioMetros) else {
            return entradas.map(\.ruta)
        }
        return entradas.compactMap { entrada in
            if let limites = entrada.limites, !limites.intersectan(zona) { return nil }
            return entrada.ruta
        }
    }

    private struct LimitesRecorrido {
        let latMin: Double
        let latMax: Double
        let lonMin: Double
        let lonMax: Double

        init?(shape: [CLLocationCoordinate2D]) {
            guard let primero = shape.first else { return nil }
            var latMin = primero.latitude
            var latMax = primero.latitude
            var lonMin = primero.longitude
            var lonMax = primero.longitude
            for punto in shape {
                // Ante datos inválidos o latitudes próximas a polos se mide
                // el recorrido original, sin intentar descartar sus tramos.
                guard CLLocationCoordinate2DIsValid(punto), abs(punto.latitude) < 80 else { return nil }
                latMin = min(latMin, punto.latitude)
                latMax = max(latMax, punto.latitude)
                lonMin = min(lonMin, punto.longitude)
                lonMax = max(lonMax, punto.longitude)
            }
            guard lonMax - lonMin <= 180 else { return nil }
            // projectedPoint limita t a [0, 1]: su latitud/longitud queda
            // entre los extremos, incluso con segmentos largos o repetidos.
            // Ampliar el rectángulo tolera el redondeo de esa proyección.
            let margenGrados = 1e-7
            self.latMin = latMin - margenGrados
            self.latMax = latMax + margenGrados
            self.lonMin = lonMin - margenGrados
            self.lonMax = lonMax + margenGrados
        }

        init?(punto: CLLocationCoordinate2D, radioMetros: Double) {
            guard CLLocationCoordinate2DIsValid(punto),
                  radioMetros.isFinite, radioMetros >= 0 else { return nil }
            // La misma esfera de distanciaMetros; el metro adicional solo
            // amplía candidatas. El radio final se conserva sin ese margen.
            let radioAngular = (radioMetros + 1) / 6_371_000
            let deltaLat = radioAngular * 180 / .pi
            let latExtrema = abs(punto.latitude) + deltaLat
            guard latExtrema < 80 else { return nil }
            // En haversine, h >= cos(latExtrema)^2 * sin(dLon/2)^2.
            // Este límite cubre todas las longitudes a distancia <= radio,
            // usando la latitud más extrema permitida por el mismo círculo.
            let terminoLon = sin(radioAngular / 2) / cos(latExtrema * .pi / 180)
            guard terminoLon.isFinite, terminoLon >= 0, terminoLon < 1 else { return nil }
            let deltaLon = 2 * asin(terminoLon) * 180 / .pi
            let lonMin = punto.longitude - deltaLon
            let lonMax = punto.longitude + deltaLon
            // Si la ventana cruza el antimeridiano, conservar todas las rutas
            // evita imponer una interpretación distinta a la proyección.
            guard lonMin > -180, lonMax < 180 else { return nil }
            self.latMin = punto.latitude - deltaLat
            self.latMax = punto.latitude + deltaLat
            self.lonMin = lonMin
            self.lonMax = lonMax
        }

        func intersectan(_ otro: LimitesRecorrido) -> Bool {
            latMin <= otro.latMax && otro.latMin <= latMax
                && lonMin <= otro.lonMax && otro.lonMin <= lonMax
        }
    }
}
