//
//  Typography.swift
//  RutaUTP
//
//  Tres familias tipográficas:
//   • Hanken Grotesk  → titulares / hero
//   • Be Vietnam Pro  → cuerpo / párrafos
//   • JetBrains Mono  → etiquetas (UPPERCASE) / tracking amplio
//
//  Las fuentes deben estar registradas en Info.plist bajo UIAppFonts.
//  Si no están disponibles, caen a system con el peso más cercano.
//

import SwiftUI

// MARK: - Familias de fuente (con fallback seguro)
enum AppFontFamily {
    static let hankenGrotesk  = "HankenGrotesk"
    static let beVietnam      = "BeVietnamPro"
    static let jetBrainsMono  = "JetBrainsMono"

    static func registered(_ name: String) -> Font {
        UIFont(name: name, size: 12) != nil
            ? .custom(name, size: 12)
            : .system(size: 12, weight: .regular)
    }
}

// MARK: - Extensión de Font: tokens tipográficos del Design System
extension Font {

    // Display & Headlines — Hanken Grotesk (800 ExtraBold / 700 Bold)
    static let displayLg        = Font.custom(AppFontFamily.hankenGrotesk, size: 32, relativeTo: .largeTitle).weight(.heavy)
    static let displayLgPhone   = Font.custom(AppFontFamily.hankenGrotesk, size: 28, relativeTo: .title).weight(.heavy)
    static let headlineLgMobile = Font.custom(AppFontFamily.hankenGrotesk, size: 28, relativeTo: .title).weight(.heavy)
    static let headlineMd       = Font.custom(AppFontFamily.hankenGrotesk, size: 24, relativeTo: .title2).weight(.bold)
    static let headlineSm       = Font.custom(AppFontFamily.hankenGrotesk, size: 20, relativeTo: .title3).weight(.bold)
    static let headlineXs       = Font.custom(AppFontFamily.hankenGrotesk, size: 18, relativeTo: .headline).weight(.bold)
    static let headlineBody     = Font.custom(AppFontFamily.hankenGrotesk, size: 16, relativeTo: .body).weight(.bold)

    // Display numéricos (e.g. "3 min", "20 min", "47")
    static let displayNumberLg  = Font.custom(AppFontFamily.hankenGrotesk, size: 42, relativeTo: .largeTitle).weight(.heavy)
    static let displayNumberMd  = Font.custom(AppFontFamily.hankenGrotesk, size: 24, relativeTo: .title).weight(.bold)

    // Body — Be Vietnam Pro (400 / 500)
    static let bodyLg           = Font.custom(AppFontFamily.beVietnam, size: 18, relativeTo: .body)
    static let bodyMd           = Font.custom(AppFontFamily.beVietnam, size: 16, relativeTo: .body)
    static let bodySm           = Font.custom(AppFontFamily.beVietnam, size: 14, relativeTo: .caption)
    static let bodyXs           = Font.custom(AppFontFamily.beVietnam, size: 13, relativeTo: .caption2)
    static let bodyMdMedium     = Font.custom(AppFontFamily.beVietnam, size: 16, relativeTo: .body).weight(.medium)
    static let bodySmMedium     = Font.custom(AppFontFamily.beVietnam, size: 15, relativeTo: .callout).weight(.medium)
    static let bodyXsMedium     = Font.custom(AppFontFamily.beVietnam, size: 13, relativeTo: .footnote).weight(.medium)

    // Labels UPPERCASE — JetBrains Mono (600 SemiBold, tracking ancho)
    static let labelCapsLg      = Font.custom(AppFontFamily.jetBrainsMono, size: 14, relativeTo: .footnote).weight(.semibold)
    static let labelCapsMd      = Font.custom(AppFontFamily.jetBrainsMono, size: 12, relativeTo: .caption).weight(.semibold)
    static let labelCapsSm      = Font.custom(AppFontFamily.jetBrainsMono, size: 11, relativeTo: .caption2).weight(.semibold)
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
