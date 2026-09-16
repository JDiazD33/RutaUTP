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

    /// Texto visible. El `rawValue` se persiste dentro de `LugarGuardado`, así
    /// que se mantiene como clave estable y NO se traduce: cambiarlo
    /// invalidaría los lugares ya guardados.
    var label: String {
        switch self {
        case .universidad: return L.t("Universidad", "University")
        case .hogar:       return L.t("Hogar", "Home")
        case .tienda:      return L.t("Tienda", "Store")
        case .restaurante: return L.t("Restaurante", "Restaurant")
        case .plaza:       return L.t("Plaza", "Square")
        case .playa:       return L.t("Playa", "Beach")
        case .otro:        return L.t("Otro", "Other")
        }
    }

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

    /// Lugares fijos de la app (ej. campus UTP): no se pueden eliminar.
    ///
    /// Es un campo PERSISTIDO, no derivado del nombre. Antes se calculaba con
    /// `nombre == "UTP"`, lo que ataba la invariante al texto visible: cambiar
    /// el nombre del lugar —o traducirlo— lo convertía en borrable. Además el
    /// nombre es un dato del prototipo y va a cambiar.
    var esFijo: Bool

    // No se persiste: los badges siempre usan el color primario.
    var colorBadge: Color { .appPrimary }

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
         lon: Double? = nil,
         esFijo: Bool = false) {
        self.id = id
        self.nombre = nombre
        self.direccion = direccion
        self.categoria = categoria
        self.esFrecuente = esFrecuente
        self.lat = lat
        self.lon = lon
        self.esFijo = esFijo
    }

    // MARK: - Codable (colorBadge fuera de la persistencia)
    private enum CodingKeys: String, CodingKey {
        case id, nombre, direccion, categoria, esFrecuente, lat, lon, esFijo
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
        // Ausente en datos guardados por versiones anteriores: `LugaresStore`
        // los migra al cargar.
        esFijo      = try c.decodeIfPresent(Bool.self, forKey: .esFijo) ?? false
    }
}

/// Referencia persistida a una línea del feed GTFS (solo el route_id;
/// el resto se resuelve desde GTFSRepository al mostrar).
struct LineaGuardadaRef: Identifiable, Codable, Equatable {
    let routeId: String
    var id: String { routeId }
}
