//
//  Negocio.swift
//  RutaUTP
//
//  Modelo de los locales promocionados ("negocios en ruta").
//
//  Fase 1: los datos viven en negocios_promocionados.json dentro del bundle
//  (mismo enfoque offline que el feed GTFS y las señas). El modelo ya está
//  pensado para migrar a backend sin cambios: el JSON es la única fuente.
//

import Foundation
import CoreLocation
import SwiftUI

// MARK: - Modelo

/// Un local comercial que aparece como burbuja en el mapa durante el viaje.
struct Negocio: Codable, Identifiable {
    /// Identificador estable para el futuro backend (ej. "menu-dona-teo").
    let id: String
    let nombre: String
    let categoria: CategoriaNegocio
    let latitud: Double
    let longitud: Double
    let direccion: String
    /// Distrito ("Trujillo", "Huanchaco", "La Esperanza"...). Útil para
    /// mostrar "a X km · Huanchaco" en la burbuja y la card.
    let distrito: String
    /// Texto corto para la burbuja del mapa, con emoji incluido.
    let promoCorta: String
    /// Texto completo para la card de detalle.
    let promoDetalle: String
    let cupon: CuponNegocio?
    /// Horario de atención (texto libre, formato "Lun-Sáb 11:00-22:00").
    let horario: String
    let telefono: String?
    /// Los patrocinados llevan la marca visual "Promocionado".
    let patrocinado: Bool
    /// 0 a 5, tal como se mostrará (opcional mientras no haya reseñas reales).
    let calificacion: Double?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitud, longitude: longitud)
    }
}

/// Cupón canjeable mostrando la app. Es la métrica de negocio real:
/// canjes > impresiones.
struct CuponNegocio: Codable {
    let codigo: String
    let detalle: String
    let condiciones: String
    /// Fecha límite ISO "YYYY-MM-DD". Nil = sin vencimiento.
    let vence: String?

    /// Fecha límite parseada, si existe y es válida.
    var fechaVencimiento: Date? {
        guard let vence else { return nil }
        let formato = DateFormatter()
        formato.dateFormat = "yyyy-MM-dd"
        formato.locale = Locale(identifier: "en_US_POSIX")
        return formato.date(from: vence)
    }

    /// false si el cupón ya venció (no se ofrece, pero se sigue mostrando
    /// el local sin el botón de canje).
    var vigente: Bool {
        guard let limite = fechaVencimiento else { return true }
        return Date() <= limite
    }
}

// MARK: - Categorías

/// Categoría del local: define ícono, color y etiqueta en la UI.
enum CategoriaNegocio: String, Codable, CaseIterable {
    case polleria
    case menu
    case cafeteria
    case chifa
    case salchipapas
    case panaderia
    case heladeria
    case jugueria
    case pizza
    case burger
    case cevicheria
    case empanadas

    var etiqueta: String {
        switch self {
        case .polleria:    return L.t("Pollería", "Grill chicken")
        case .menu:        return L.t("Menú criollo", "Set menu")
        case .cafeteria:   return L.t("Cafetería", "Coffee shop")
        case .chifa:       return L.t("Chifa", "Chinese-Peruvian")
        case .salchipapas: return L.t("Salchipapas", "Salchipapas")
        case .panaderia:   return L.t("Panadería", "Bakery")
        case .heladeria:   return L.t("Heladería", "Ice cream")
        case .jugueria:    return L.t("Juguería", "Juice bar")
        case .pizza:       return L.t("Pizza", "Pizza")
        case .burger:      return L.t("Burgers", "Burgers")
        case .cevicheria:  return L.t("Cevichería", "Cevichería")
        case .empanadas:   return L.t("Empanadas", "Empanadas")
        }
    }

    /// SF Symbol para la card de detalle y el filtro por categoría.
    var icono: String {
        switch self {
        case .polleria:    return "flame.fill"
        case .menu:        return "fork.knife"
        case .cafeteria:   return "cup.and.saucer.fill"
        case .chifa:       return "frying.pan.fill"
        case .salchipapas: return "takeoutbag.and.cup.and.straw.fill"
        case .panaderia:   return "croissant"
        case .heladeria:   return "snowflake"
        case .jugueria:    return "cup.and.straw.fill"
        case .pizza:       return "fork.knife.circle.fill"
        case .burger:      return "takeoutbag.and.cup.and.straw.fill"
        case .cevicheria:  return "water.waves"
        case .empanadas:   return "birthday.cake.fill"
        }
    }

    /// Color de acento por categoría. Se apoya en la paleta Material del app
    /// (contenedores secundarios) para no romper el tema claro/oscuro.
    var color: Color {
        switch self {
        case .polleria, .burger, .pizza:   return .orange
        case .menu, .cevicheria:           return .red
        case .cafeteria, .panaderia:       return .brown
        case .chifa:                       return .yellow
        case .salchipapas, .empanadas:     return .indigo
        case .heladeria:                   return .cyan
        case .jugueria:                    return .green
        }
    }
}

// MARK: - Contenedor del JSON

/// Raíz de negocios_promocionados.json.
struct CatalogoNegocios: Codable {
    let version: Int
    let actualizado: String
    /// Nota editorial del archivo (procedencia de los datos).
    let nota: String?
    let negocios: [Negocio]
}
