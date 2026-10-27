//
//  ColorTransporteReferencia.swift
//  RutaUTP
//
//  Colores de referencia del transporte público.
//

import SwiftUI

enum ColorTransporteReferencia: String {
    case verde, verdeAgua, verdeClaro, verdeOscuro, turquesa, blanco, negro, azul, azulOscuro, azulRey, amarillo, rojo, rosado, fucsia, guinda, naranja, marron, marronOscuro, crema, marfil, gris, plomo, verdeLima, celeste, morado

    var color: Color {
        switch self {
        case .verde: return Color(hex: "#27B579")
        case .verdeAgua: return Color(hex: "#5AAFA0")
        case .verdeClaro: return Color(hex: "#91CB7C")
        case .verdeOscuro: return Color(hex: "#195A52")
        case .verdeLima: return Color(hex: "#86BE39")
        case .turquesa: return Color(hex: "#4DB5B0")
        case .blanco: return Color(hex: "#F4F4F4")
        case .negro: return Color(hex: "#1C1F21")
        case .azul: return Color(hex: "#187FB8")
        case .celeste: return Color(hex: "#6DC9E0")
        case .azulOscuro: return Color(hex: "#1E304D")
        case .azulRey: return Color(hex: "#2D4FAA")
        case .amarillo: return Color(hex: "#F5C928")
        case .rojo: return Color(hex: "#DE3039")
        case .rosado: return Color(hex: "#E6A0B8")
        case .fucsia: return Color(hex: "#C13E83")
        case .guinda: return Color(hex: "#7E304A")
        case .morado: return Color(hex: "#884680")
        case .naranja: return Color(hex: "#D3913E")
        case .marron: return Color(hex: "#956B4B")
        case .marronOscuro: return Color(hex: "#4D322F")
        case .crema: return Color(hex: "#EADDBB")
        case .marfil: return Color(hex: "#F0E4C2")
        case .gris: return Color(hex: "#979795")
        case .plomo: return Color(hex: "#6F7477")
        }
    }

    var nombre: String {
        switch self {
        case .verde: return L.t("Verde", "Green")
        case .verdeAgua: return L.t("Verde agua", "Mint green")
        case .verdeClaro: return L.t("Verde claro", "Light green")
        case .verdeOscuro: return L.t("Verde oscuro", "Dark green")
        case .verdeLima: return L.t("Verde lima", "Lime green")
        case .turquesa: return L.t("Turquesa", "Turquoise")
        case .blanco: return L.t("Blanco", "White")
        case .negro: return L.t("Negro", "Black")
        case .azul: return L.t("Azul", "Blue")
        case .celeste: return L.t("Celeste", "Light blue")
        case .azulOscuro: return L.t("Azul oscuro", "Dark blue")
        case .azulRey: return L.t("Azul rey", "Royal blue")
        case .amarillo: return L.t("Amarillo", "Yellow")
        case .rojo: return L.t("Rojo", "Red")
        case .rosado: return L.t("Rosado", "Pink")
        case .fucsia: return L.t("Fucsia", "Fuchsia")
        case .guinda: return L.t("Guinda", "Burgundy")
        case .morado: return L.t("Morado", "Purple")
        case .naranja: return L.t("Naranja", "Orange")
        case .marron: return L.t("Marrón", "Brown")
        case .marronOscuro: return L.t("Marrón oscuro", "Dark brown")
        case .crema: return L.t("Crema", "Cream")
        case .marfil: return L.t("Marfil", "Ivory")
        case .gris: return L.t("Gris", "Gray")
        case .plomo: return L.t("Plomo", "Lead gray")
        }
    }
}
