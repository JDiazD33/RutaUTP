//
//  Typography.swift
//  RutaUTP
//
//  Tokens tipográficos del Design System.
//
//  DECISIÓN: la app usa la FUENTE DEL SISTEMA. No incluye fuentes propias.
//
//  Antes había tres familias declaradas (Hanken Grotesk, Be Vietnam Pro y
//  JetBrains Mono) con sus .ttf en UIAppFonts, pero los archivos nunca
//  estuvieron en el repositorio: no había un solo .ttf en el bundle
//  compilado. Como `Font.custom` con una familia ausente cae al sistema,
//  la app se veía con la fuente del sistema de todos modos — solo que el
//  código decía otra cosa y el Info.plist declaraba ocho fuentes inexistentes.
//
//  Estos tokens conservan EXACTAMENTE los tamaños y pesos que se veían, así
//  que la adopción de la fuente del sistema no cambia nada visualmente.
//
//  NOTA sobre accesibilidad: los tokens son de tamaño fijo. La implementación
//  anterior pasaba `relativeTo:` a `Font.custom`, lo que sí escalaba con
//  Dynamic Type. Para recuperar ese comportamiento hay que migrar los tokens
//  a `@ScaledMetric` en los sitios de uso (afecta a ~50 llamadas). Queda como
//  mejora pendiente, no como decisión tomada.
//

import SwiftUI

// MARK: - Extensión de Font: tokens tipográficos del Design System
extension Font {

    // Display & Headlines — titulares y hero
    static let displayLg        = Font.system(size: 32, weight: .heavy)
    static let displayLgPhone   = Font.system(size: 28, weight: .heavy)
    static let headlineLgMobile = Font.system(size: 28, weight: .heavy)
    static let headlineMd       = Font.system(size: 24, weight: .bold)
    static let headlineSm       = Font.system(size: 20, weight: .bold)
    static let headlineXs       = Font.system(size: 18, weight: .bold)
    static let headlineBody     = Font.system(size: 16, weight: .bold)

    // Display numéricos (e.g. "3 min", "20 min", "47")
    static let displayNumberLg  = Font.system(size: 42, weight: .heavy)
    static let displayNumberMd  = Font.system(size: 24, weight: .bold)

    // Body — texto corriente
    static let bodyLg           = Font.system(size: 18)
    static let bodyMd           = Font.system(size: 16)
    static let bodySm           = Font.system(size: 14)
    static let bodyXs           = Font.system(size: 13)
    static let bodyMdMedium     = Font.system(size: 16, weight: .medium)
    static let bodySmMedium     = Font.system(size: 15, weight: .medium)
    static let bodyXsMedium     = Font.system(size: 13, weight: .medium)

    // Labels UPPERCASE — se combinan con appTracking() para el aire espaciado
    static let labelCapsLg      = Font.system(size: 14, weight: .semibold)
    static let labelCapsMd      = Font.system(size: 12, weight: .semibold)
    static let labelCapsSm      = Font.system(size: 11, weight: .semibold)
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
