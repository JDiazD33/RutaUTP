//
//  Colors.swift
//  RutaUTP
//
//  Paleta de colores oficial del Design System RutaUTP.
//  Fuente de verdad: NO modificar hexes CLAROS — heredados del prototipo HTML.
//  Los tokens de superficie/texto son adaptativos claro/oscuro: el toggle
//  de Ajustes (.preferredColorScheme en RootView) los voltea solos.
//  Los colores de marca (rojo UTP, azul, teal) se mantienen en ambos modos.
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

    // MARK: - Superficie (adaptativas)
    static let appBackground             = Color(light: "#f7f9fb", dark: "#101314")
    static let appSurface                = Color(light: "#f7f9fb", dark: "#141719")
    static let surfaceContainer          = Color(light: "#eceef0", dark: "#1e2225")
    static let surfaceContainerLow       = Color(light: "#f2f4f6", dark: "#1a1d20")
    static let surfaceContainerHigh      = Color(light: "#e6e8ea", dark: "#26292c")
    static let surfaceContainerHighest   = Color(light: "#e0e3e5", dark: "#313537")
    static let surfaceContainerLowest    = Color(light: "#ffffff", dark: "#0b0d0e")
    static let surfaceDim                = Color(light: "#d8dadc", dark: "#3c4143")
    static let surfaceBright             = Color(light: "#f7f9fb", dark: "#2a2e30")
    static let surfaceVariant            = Color(light: "#e4bdbf", dark: "#4a3537")

    // MARK: - On-Surface (adaptativos)
    static let onSurface           = Color(light: "#191c1e", dark: "#e4e8ea")
    static let onSurfaceVariant    = Color(light: "#5c3f41", dark: "#c9adaf")
    static let inverseSurface      = Color(light: "#2d3133", dark: "#e3e6e8")
    static let inverseOnSurface    = Color(light: "#eff1f3", dark: "#1c2022")

    // MARK: - Outline (adaptativos)
    static let outline             = Color(light: "#906f70", dark: "#a98b8c")
    static let outlineVariant      = Color(light: "#e4bdbf", dark: "#4a3f40")

    // MARK: - Error
    static let appError            = Color(light: "#ba1a1a", dark: "#ff6b6b")
    static let errorContainer      = Color(light: "#ffdad6", dark: "#5c2224")
    static let onErrorContainer    = Color(light: "#93000a", dark: "#ffd7d3")
}

// MARK: - Helpers: inicializadores desde hex
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

    /// Color adaptativo: usa el hex claro u oscuro según el esquema activo.
    /// Recalcula solo cuando cambia el colorScheme — costo cero en render.
    init(light: String, dark: String) {
        self.init(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light))
        })
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
