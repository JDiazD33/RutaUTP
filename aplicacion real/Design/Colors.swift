//
//  Colors.swift
//  RutaUTP
//
//  Paleta de colores oficial del Design System RutaUTP.
//  Fuente de verdad: NO modificar hexes — heredados del prototipo HTML.
//

import SwiftUI

extension Color {

    // MARK: - Primarios (Rojo UTP)
    static let appPrimary          = Color(hex: "#a80033")
    static let primaryContainer    = Color(hex: "#d31245")
    static let onPrimary           = Color.white
    static let onPrimaryContainer  = Color(hex: "#ffe8e8")
    static let primaryFixed        = Color(hex: "#ffdadb")
    static let primaryFixedDim     = Color(hex: "#ffb2b7")
    static let inversePrimary      = Color(hex: "#ffb2b7")

    // MARK: - Secundarios (Azul)
    static let secondary           = Color(hex: "#3c5d9c")
    static let secondaryContainer  = Color(hex: "#99b8fe")
    static let onSecondary         = Color.white
    static let onSecondaryContainer = Color(hex: "#244885")

    // MARK: - Terciarios (Teal)
    static let tertiary            = Color(hex: "#005b6e")
    static let tertiaryContainer   = Color(hex: "#00758d")
    static let onTertiary          = Color.white
    static let onTertiaryContainer = Color(hex: "#d1f2ff")
    static let tertiaryFixed       = Color(hex: "#b3ebff")
    static let tertiaryFixedDim    = Color(hex: "#4cd6fb")

    // MARK: - Superficie
    static let appBackground             = Color(hex: "#f7f9fb")
    static let appSurface                = Color(hex: "#f7f9fb")
    static let surfaceContainer          = Color(hex: "#eceef0")
    static let surfaceContainerLow       = Color(hex: "#f2f4f6")
    static let surfaceContainerHigh      = Color(hex: "#e6e8ea")
    static let surfaceContainerHighest   = Color(hex: "#e0e3e5")
    static let surfaceContainerLowest    = Color.white
    static let surfaceDim                = Color(hex: "#d8dadc")
    static let surfaceBright             = Color(hex: "#f7f9fb")
    static let surfaceVariant            = Color(hex: "#e4bdbf")

    // MARK: - On-Surface
    static let onSurface           = Color(hex: "#191c1e")
    static let onSurfaceVariant    = Color(hex: "#5c3f41")
    static let inverseSurface      = Color(hex: "#2d3133")
    static let inverseOnSurface    = Color(hex: "#eff1f3")

    // MARK: - Outline
    static let outline             = Color(hex: "#906f70")
    static let outlineVariant      = Color(hex: "#e4bdbf")

    // MARK: - Error
    static let appError            = Color(hex: "#ba1a1a")
    static let errorContainer      = Color(hex: "#ffdad6")
    static let onErrorContainer    = Color(hex: "#93000a")
}

// MARK: - Helper: inicializador desde hex
extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
