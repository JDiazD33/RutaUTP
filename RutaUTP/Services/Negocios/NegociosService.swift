//
//  NegociosService.swift
//  RutaUTP
//
//  Carga y consulta de los locales promocionados ("negocios en ruta").
//
//  Fase 1: JSON local en el bundle (offline-first, como GTFS y señas).
//  La única consulta que necesita la UI es `cerca(de:)`: devuelve los
//  negocios dentro del radio, ordenados por distancia y con tope, para
//  que el mapa nunca se llene de burbujas.
//

import Foundation
import CoreLocation

final class NegociosService {

    static let shared = NegociosService()

    private let catalogo: CatalogoNegocios?

    // MARK: - Init

    private init() {
        // servicios/negocios/negocios_promocionados.json
        if let url = Bundle.main.url(forResource: "negocios_promocionados", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            catalogo = try? JSONDecoder().decode(CatalogoNegocios.self, from: data)
        } else {
            catalogo = nil
        }
    }

    // MARK: - Estado

    /// false si el JSON no está en el bundle o no decodificó. La UI debe
    /// degradar en silencio: sin catálogo no hay burbujas, sin error visible.
    var cargado: Bool { catalogo != nil }

    var cantidad: Int { catalogo?.negocios.count ?? 0 }

    /// Catálogo completo. Para depurar y para el futuro listado de negocios.
    func todos() -> [Negocio] {
        catalogo?.negocios ?? []
    }

    // MARK: - Consulta principal

    /// Negocios a menos de `radioMetros` de `origen`, ordenados de más cerca
    /// a más lejos y limitados a `limite` (3-5: más burbujas = ruido).
    ///
    /// `origen` será la posición del usuario durante el viaje o el destino
    /// de la ruta; quien llama decide el ancla, el servicio solo filtra.
    func cerca(de origen: CLLocationCoordinate2D,
               radioMetros: Double = 600,
               limite: Int = 5) -> [Negocio] {
        guard let catalogo else { return [] }
        return catalogo.negocios
            .map { ($0, Self.distanciaMetros(origen, $0.coordinate)) }
            .filter { $0.1 <= radioMetros }
            .sorted { $0.1 < $1.1 }
            .prefix(limite)
            .map(\.0)
    }

    /// Distancia en metros entre dos coordenadas (Haversine). Suficiente para
    /// filtrar por radio; no hace falta precisión de navegación peatonal.
    static func distanciaMetros(_ a: CLLocationCoordinate2D,
                                _ b: CLLocationCoordinate2D) -> Double {
        let radioTierra = 6_371_000.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let latA = a.latitude * .pi / 180
        let latB = b.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
              + cos(latA) * cos(latB) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * radioTierra * asin(min(1, sqrt(h)))
    }

    // MARK: - Cupones guardados

    /// Llave de UserDefaults con los ids de negocios cuyo cupón se guardó.
    /// Fase 1: "wallet" mínimo sin pantalla propia; el estado se refleja en
    /// la card. La métrica de negocio (canjes) llegará con el backend.
    private static let llaveCupones = "negocios.cupones.guardados"

    private static func idsGuardados() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: llaveCupones) ?? [])
    }

    /// true si el usuario ya guardó el cupón de este negocio.
    func cuponGuardado(_ negocio: Negocio) -> Bool {
        Self.idsGuardados().contains(negocio.id)
    }

    /// Alterna el cupón (guardar / quitar) y devuelve el nuevo estado.
    @discardableResult
    func alternarCupon(_ negocio: Negocio) -> Bool {
        var ids = Self.idsGuardados()
        if ids.contains(negocio.id) {
            ids.remove(negocio.id)
        } else {
            ids.insert(negocio.id)
        }
        UserDefaults.standard.set(Array(ids).sorted(), forKey: Self.llaveCupones)
        return ids.contains(negocio.id)
    }
}
