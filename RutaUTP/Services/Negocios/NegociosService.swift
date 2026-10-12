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
    private let defaults: UserDefaults

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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

    /// Selección espaciada según el zoom, para explorar toda la ciudad sin amontonar pins.
    func distribuidos(cercaDe center: CLLocationCoordinate2D, radioMetros: Double,
                      limite: Int) -> [Negocio] {
        let candidates = cerca(de: center, radioMetros: radioMetros, limite: cantidad)
        let separation = max(110, radioMetros / 5)
        var result: [Negocio] = []
        for business in candidates {
            guard result.allSatisfy({ Self.distanciaMetros($0.coordinate, business.coordinate) >= separation }) else { continue }
            result.append(business)
            if result.count >= limite { break }
        }
        return result
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
    static let cuponesActualizados = Notification.Name("negocios.cupones.actualizados")

    private static let llaveCupones = "negocios.cupones.guardados"

    enum ErrorCupones: Error {
        case datosGuardadosInvalidos
    }

    private func idsGuardados() -> Set<String>? {
        guard let original = defaults.object(forKey: Self.llaveCupones) else { return [] }
        guard let ids = original as? [String] else { return nil }
        return Set(ids)
    }

    var datosCuponesInvalidos: Bool { idsGuardados() == nil }

    /// true si el usuario ya guardó el cupón de este negocio.
    func cuponGuardado(_ negocio: Negocio) -> Bool {
        idsGuardados()?.contains(negocio.id) ?? false
    }

    /// Comparte con Perfil los cupones guardados desde cualquier mapa.
    func cuponesGuardados() -> [Negocio] {
        guard let ids = idsGuardados() else { return [] }
        return todos().filter { ids.contains($0.id) && $0.cupon != nil }
            .sorted { $0.nombre.localizedStandardCompare($1.nombre) == .orderedAscending }
    }

    @MainActor
    func quitarCupon(_ negocio: Negocio) throws {
        guard var ids = idsGuardados() else { throw ErrorCupones.datosGuardadosInvalidos }
        ids.remove(negocio.id)
        guardarCupones(ids)
    }

    @MainActor
    private func guardarCupones(_ ids: Set<String>) {
        defaults.set(Array(ids).sorted(), forKey: Self.llaveCupones)
        NotificationCenter.default.post(name: Self.cuponesActualizados, object: nil)
    }

    /// Alterna el cupón (guardar / quitar) y devuelve el nuevo estado.
    @discardableResult
    @MainActor
    func alternarCupon(_ negocio: Negocio) throws -> Bool {
        guard var ids = idsGuardados() else { throw ErrorCupones.datosGuardadosInvalidos }
        if ids.contains(negocio.id) {
            ids.remove(negocio.id)
        } else {
            ids.insert(negocio.id)
        }
        guardarCupones(ids)
        return ids.contains(negocio.id)
    }

    /// Solo reinicia originales ilegibles y después de conservar una copia.
    @MainActor
    func respaldarYReiniciarCupones(crearRespaldo: ((Data) throws -> URL)? = nil) throws -> URL? {
        guard datosCuponesInvalidos else { return nil }
        let archivo = try RecuperacionPreferencias.reiniciar(claves: [Self.llaveCupones],
            valoresNuevos: [Self.llaveCupones: [String]()], nombre: "cupones",
            defaults: defaults, crearRespaldo: crearRespaldo)
        NotificationCenter.default.post(name: Self.cuponesActualizados, object: nil)
        return archivo
    }
}
