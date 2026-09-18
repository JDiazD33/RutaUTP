// Estilos semánticos del sistema: responden a Dynamic Type, incluidos
// los tamaños de accesibilidad. Los tamaños base son los definidos por iOS.

import SwiftUI

// MARK: - Extensión de Font: tokens tipográficos del Design System
extension Font {

    // Display & Headlines — titulares y hero
    static let displayLg        = Font.system(.largeTitle, weight: .heavy)
    static let displayLgPhone   = Font.system(.title, weight: .heavy)
    static let headlineLgMobile = Font.system(.title, weight: .heavy)
    static let headlineMd       = Font.system(.title2, weight: .bold)
    static let headlineSm       = Font.system(.title3, weight: .bold)
    static let headlineXs       = Font.system(.headline, weight: .bold)
    static let headlineBody     = Font.system(.subheadline, weight: .bold)

    // Display numéricos (e.g. "3 min", "20 min", "47")
    static let displayNumberLg  = Font.system(.largeTitle, weight: .heavy)
    static let displayNumberMd  = Font.system(.title2, weight: .bold)

    // Body — texto corriente
    static let bodyLg           = Font.system(.body)
    static let bodyMd           = Font.system(.body)
    static let bodySm           = Font.system(.subheadline)
    static let bodyXs           = Font.system(.footnote)
    static let bodyMdMedium     = Font.system(.body, weight: .medium)
    static let bodySmMedium     = Font.system(.subheadline, weight: .medium)
    static let bodyXsMedium     = Font.system(.footnote, weight: .medium)

    // Labels UPPERCASE — se combinan con appTracking() para el aire espaciado
    static let labelCapsLg      = Font.system(.subheadline, weight: .semibold)
    static let labelCapsMd      = Font.system(.caption, weight: .semibold)
    static let labelCapsSm      = Font.system(.caption2, weight: .semibold)
}

// MARK: - Tracking presets
enum AppTracking {
    static let wideLabel: CGFloat = 1.5      // 0.1em aprox sobre 14px
    static let wideLabelMd: CGFloat = 1.8    // 0.15em aprox sobre 12px
    static let wideLabelCaps: CGFloat = 2.4  // 0.2em aprox sobre 11px
    static let displayTight: CGFloat = -0.6  // -0.02em aprox sobre 32px
}

// MARK: - ViewModifier: tracking rápido
struct Tracking: ViewModifier {
    let value: CGFloat
    func body(content: Content) -> some View {
        content.tracking(value)
    }
}

extension View {
    func appTracking(_ value: CGFloat) -> some View { modifier(Tracking(value: value)) }
}
