//
//  LugarGuardado.swift
//

import Foundation
import SwiftUI
import CoreLocation

enum CategoriaLugar: String, CaseIterable, Identifiable, Codable {
    case universidad = "Universidad"
    case hogar        = "Hogar"
    case tienda       = "Tienda"
    case restaurante  = "Restaurante"
    case plaza        = "Plaza"
    case playa        = "Playa"
    case otro         = "Otro"

    var id: String { rawValue }

    var icono: String {
        switch self {
        case .universidad: return "graduationcap.fill"
        case .hogar:       return "house.fill"
        case .tienda:      return "storefront.fill"
        case .restaurante: return "fork.knife"
        case .plaza:       return "building.columns.fill"
        case .playa:       return "water.waves"
        case .otro:        return "mappin.circle.fill"
        }
    }
}

struct LugarGuardado: Identifiable, Equatable, Codable {
    let id: UUID
    var nombre: String
    var direccion: String
    var categoria: CategoriaLugar
    var esFrecuente: Bool
    var lat: Double?
    var lon: Double?

    // No se persiste: los badges siempre usan el color primario.
    var colorBadge: Color { .appPrimary }

    /// Lugares fijos de la app (ej. campus UTP): no se pueden eliminar.
    var esFijo: Bool { nombre.caseInsensitiveCompare("UTP") == .orderedSame }

    var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    init(id: UUID = UUID(),
         nombre: String,
         direccion: String,
         categoria: CategoriaLugar,
         esFrecuente: Bool = false,
         lat: Double? = nil,
         lon: Double? = nil) {
        self.id = id
        self.nombre = nombre
        self.direccion = direccion
        self.categoria = categoria
        self.esFrecuente = esFrecuente
        self.lat = lat
        self.lon = lon
    }

    // MARK: - Codable (colorBadge fuera de la persistencia)
    private enum CodingKeys: String, CodingKey {
        case id, nombre, direccion, categoria, esFrecuente, lat, lon
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(UUID.self, forKey: .id)
        nombre      = try c.decode(String.self, forKey: .nombre)
        direccion   = try c.decode(String.self, forKey: .direccion)
        categoria   = try c.decode(CategoriaLugar.self, forKey: .categoria)
        esFrecuente = try c.decodeIfPresent(Bool.self, forKey: .esFrecuente) ?? false
        lat         = try c.decodeIfPresent(Double.self, forKey: .lat)
        lon         = try c.decodeIfPresent(Double.self, forKey: .lon)
    }
}

/// Referencia persistida a una línea del feed GTFS (solo el route_id;
/// el resto se resuelve desde GTFSRepository al mostrar).
struct LineaGuardadaRef: Identifiable, Codable, Equatable {
    let routeId: String
    var id: String { routeId }
}

/// Fuente única de lugares guardados (UserDefaults). La usan GuardadoView
/// y SeguridadView para leer/escribir los mismos datos.
enum LugaresStore {
    static let key = "lugares.guardados.v2"

    static func cargar() -> [LugarGuardado] {
        var resultado: [LugarGuardado]
        if let data = UserDefaults.standard.data(forKey: key),
           let decodificados = try? JSONDecoder().decode([LugarGuardado].self, from: data),
           !decodificados.isEmpty {
            resultado = decodificados
        } else {
            // Seed: UTP (fijo) + Plaza de Armas; el resto los agrega el usuario.
            resultado = [lugarUTP(),
                         LugarGuardado(nombre: "Plaza de Armas",
                                       direccion: "Centro Histórico de Trujillo",
                                       categoria: .plaza,
                                       lat: -8.1096, lon: -79.0287)]
            guardar(resultado)
            return resultado
        }

        // El campus UTP es un lugar fijo de la app: siempre presente y primero.
        if let indiceUTP = resultado.firstIndex(where: { $0.esFijo }) {
            if indiceUTP != 0 {
                let utp = resultado.remove(at: indiceUTP)
                resultado.insert(utp, at: 0)
                guardar(resultado)
            }
        } else {
            resultado.insert(lugarUTP(), at: 0)
            guardar(resultado)
        }
        return resultado
    }

    static func guardar(_ lugares: [LugarGuardado]) {
        if let data = try? JSONEncoder().encode(lugares) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func eliminar(_ lugar: LugarGuardado) {
        var actuales = cargar()
        actuales.removeAll { $0.id == lugar.id }
        guardar(actuales)
    }

    static func lugarUTP() -> LugarGuardado {
        LugarGuardado(nombre: "UTP",
                      direccion: "Av. Nicolás de Piérola 1221, Trujillo",
                      categoria: .universidad, esFrecuente: true,
                      lat: -8.098247879173792, lon: -79.03818104755645)
    }
}
