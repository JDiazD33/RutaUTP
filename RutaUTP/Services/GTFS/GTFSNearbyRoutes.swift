//
//  GTFSNearbyRoutes.swift
//  RutaUTP
//
//  Selección de líneas cercanas sobre un catálogo ya cargado.
//

import CoreLocation

extension GTFSRepository {
    /// La misma selección por radio para los consumidores existentes.
    static func rutasQuePasanPor(_ punto: CLLocationCoordinate2D,
                                en rutas: [RutaGTFS],
                                radioMetros: Double = 400) -> [RutaGTFS] {
        rutasConDistancia(punto, en: rutas)
            .filter { $0.1.isFinite && $0.1 <= radioMetros }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    /// Primero 400 m; solo sin coincidencias se amplía a 800 m.
    /// Las distancias pertenecen a esta consulta y no se guardan entre anclas.
    static func rutasQuePasanPorConAmpliacion(_ punto: CLLocationCoordinate2D,
                                             en rutas: [RutaGTFS]) -> [RutaGTFS] {
        let candidatas = rutasConDistancia(punto, en: rutas)
            .filter { $0.1.isFinite && $0.1 <= 800 }
        let cercanas = candidatas.filter { $0.1 <= 400 }
        // Filtrar antes de ordenar conserva el subconjunto y el comparador
        // anterior, también cuando varias rutas tienen la misma distancia.
        return (cercanas.isEmpty ? candidatas : cercanas)
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    private static func rutasConDistancia(_ punto: CLLocationCoordinate2D,
                                         en rutas: [RutaGTFS]) -> [(RutaGTFS, Double)] {
        rutas
            .filter { $0.shape.count >= 2 }
            .map { ($0, Self.distanciaMinima($0.shape, a: punto)) }
    }
}
