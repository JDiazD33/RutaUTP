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
