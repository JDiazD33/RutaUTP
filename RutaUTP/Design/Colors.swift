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

// MARK: - ShapeStyle: permite usar los colores en .foregroundStyle(.appPrimary) etc.
//
// SwiftUI recibe un `ShapeStyle` (protocolo) en `.foregroundStyle()`,
// `.fill()` y similares. Como nuestros colores son extension de `Color`
// y no de `ShapeStyle`, el compilador no los encuentra en contexto
// generico. Esta extension los re-exporta para que el shorthand funcione.
//
// IMPORTANTE: NO exportamos `secondary` ni `tertiary` porque colisionan
// con los colores jerarquicos del sistema (iOS 16+). Para esos casos usa
// `Color.secondary` y `Color.tertiary` explicitamente (que apuntan a
// NUESTROS colores gracias a la extension de `Color` de arriba).
extension ShapeStyle where Self == Color {

    // Primarios
    static var appPrimary:           Color { .appPrimary }
    static var primaryContainer:     Color { .primaryContainer }
    static var onPrimary:            Color { .onPrimary }
    static var onPrimaryContainer:   Color { .onPrimaryContainer }
    static var primaryFixed:         Color { .primaryFixed }
    static var primaryFixedDim:      Color { .primaryFixedDim }
    static var inversePrimary:       Color { .inversePrimary }

    // Terciarios (los "container" no colisionan con el sistema)
    static var tertiaryContainer:    Color { .tertiaryContainer }
    static var onTertiary:           Color { .onTertiary }
    static var onTertiaryContainer:  Color { .onTertiaryContainer }
    static var tertiaryFixed:        Color { .tertiaryFixed }
    static var tertiaryFixedDim:     Color { .tertiaryFixedDim }

    // Secundarios container
    static var secondaryContainer:   Color { .secondaryContainer }
    static var onSecondary:          Color { .onSecondary }
    static var onSecondaryContainer: Color { .onSecondaryContainer }

    // Superficie
    static var appBackground:             Color { .appBackground }
    static var appSurface:                Color { .appSurface }
    static var surfaceContainer:          Color { .surfaceContainer }
    static var surfaceContainerLow:       Color { .surfaceContainerLow }
    static var surfaceContainerHigh:      Color { .surfaceContainerHigh }
    static var surfaceContainerHighest:   Color { .surfaceContainerHighest }
    static var surfaceContainerLowest:    Color { .surfaceContainerLowest }
    static var surfaceDim:                Color { .surfaceDim }
    static var surfaceBright:             Color { .surfaceBright }
    static var surfaceVariant:            Color { .surfaceVariant }

    // On-Surface
    static var onSurface:          Color { .onSurface }
    static var onSurfaceVariant:   Color { .onSurfaceVariant }
    static var inverseSurface:     Color { .inverseSurface }
    static var inverseOnSurface:   Color { .inverseOnSurface }

    // Outline
    static var outline:            Color { .outline }
    static var outlineVariant:     Color { .outlineVariant }

    // Error
    static var appError:           Color { .appError }
    static var errorContainer:     Color { .errorContainer }
    static var onErrorContainer:   Color { .onErrorContainer }
}
