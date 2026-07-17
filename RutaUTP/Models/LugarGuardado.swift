//
//  LugarGuardado.swift
//  RutaUTP
//

import Foundation
import SwiftUI

enum CategoriaLugar: String, CaseIterable, Identifiable {
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

struct LugarGuardado: Identifiable, Equatable {
    let id: UUID
    var nombre: String
    var direccion: String
    var categoria: CategoriaLugar
    var esFrecuente: Bool
    var colorBadge: Color

    init(id: UUID = UUID(),
         nombre: String,
         direccion: String,
         categoria: CategoriaLugar,
         esFrecuente: Bool = false,
         colorBadge: Color = .appPrimary) {
        self.id = id
        self.nombre = nombre
        self.direccion = direccion
        self.categoria = categoria
        self.esFrecuente = esFrecuente
        self.colorBadge = colorBadge
    }
}

struct LineaGuardada: Identifiable, Equatable {
    let id: String          // "B", "7", "C"
    let letra: String
    let nombre: String
    let recorrido: String
    let tiempoEstimado: String
    let color: Color
}
