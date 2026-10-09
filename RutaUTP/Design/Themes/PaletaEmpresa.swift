import SwiftUI

/// Colores preparados una vez por temática. Superficies neutras, errores,
/// colores GTFS y marcas de pago conservan sus responsabilidades originales.
struct PaletaEmpresa {
    let colorMarca: Color
    let appPrimary: Color
    let primaryContainer: Color
    let onPrimaryContainer: Color
    let primaryFixed: Color
    let inversePrimary: Color
    let secondary: Color
    let secondaryContainer: Color
    let onSecondary: Color
    let onSecondaryContainer: Color
    let tertiary: Color
    let tertiaryContainer: Color
    let onTertiary: Color
    let onTertiaryContainer: Color
    let onSurfaceVariant: Color
    let outline: Color
    let outlineVariant: Color
}

enum PaletasEmpresa {
    static var actual: PaletaEmpresa {
        paleta(para: TematicaEmpresaStore.shared.seleccion)
    }

    static func paleta(para tematica: TematicaEmpresa) -> PaletaEmpresa {
        switch tematica {
        case .utp: return utp
        case .interbank: return interbank
        case .popeyes: return popeyes
        case .plazaVea: return plazaVea
        }
    }

    // UTP reproduce literalmente los tokens anteriores de Colors.swift.
    private static let utp = PaletaEmpresa(
        colorMarca: Color(hex: "#a80033"),
        appPrimary: Color(hex: "#a80033"),
        primaryContainer: Color(hex: "#d31245"),
        onPrimaryContainer: Color(hex: "#ffe8e8"),
        primaryFixed: Color(hex: "#ffdadb"),
        inversePrimary: Color(hex: "#ffb2b7"),
        secondary: Color(hex: "#3c5d9c"),
        secondaryContainer: Color(hex: "#99b8fe"),
        onSecondary: .white,
        onSecondaryContainer: Color(hex: "#244885"),
        tertiary: Color(hex: "#005b6e"),
        tertiaryContainer: Color(hex: "#00758d"),
        onTertiary: .white,
        onTertiaryContainer: Color(hex: "#d1f2ff"),
        onSurfaceVariant: Color(light: "#5c3f41", dark: "#c9adaf"),
        outline: Color(light: "#906f70", dark: "#a98b8c"),
        outlineVariant: Color(light: "#e4bdbf", dark: "#4a3f40")
    )

    // Referencia: icono oficial Interbank APP (#05BE50 / #0039A6).
    // Los acentos verdes de botones se oscurecen para conservar texto blanco.
    private static let interbank = PaletaEmpresa(
        colorMarca: Color(hex: "#05BE50"),
        appPrimary: Color(hex: "#007D36"),
        primaryContainer: Color(hex: "#00853A"),
        onPrimaryContainer: Color(hex: "#E5FFEF"),
        primaryFixed: Color(hex: "#D7F8E3"),
        inversePrimary: Color(hex: "#007D36"),
        secondary: Color(hex: "#0039A6"),
        secondaryContainer: Color(light: "#DAE6FF", dark: "#193660"),
        onSecondary: .white,
        onSecondaryContainer: Color(light: "#002C80", dark: "#DAE6FF"),
        tertiary: Color(hex: "#006D35"),
        tertiaryContainer: Color(hex: "#007D36"),
        onTertiary: .white,
        onTertiaryContainer: Color(hex: "#DAFFE8"),
        onSurfaceVariant: Color(light: "#43534A", dark: "#B8CAC0"),
        outline: Color(light: "#6E8777", dark: "#9AB4A4"),
        outlineVariant: Color(light: "#CCDCD1", dark: "#344A3D")
    )

    // Referencia: SVG oficial #FF7D00 y CSS #B54000 / #3E342F.
    private static let popeyes = PaletaEmpresa(
        colorMarca: Color(hex: "#FF7D00"),
        appPrimary: Color(hex: "#B54000"),
        primaryContainer: Color(hex: "#B54000"),
        onPrimaryContainer: Color(hex: "#FFF0E3"),
        primaryFixed: Color(hex: "#FFE6CD"),
        inversePrimary: Color(hex: "#B54000"),
        secondary: Color(hex: "#3E342F"),
        secondaryContainer: Color(light: "#F5E6D8", dark: "#46392F"),
        onSecondary: .white,
        onSecondaryContainer: Color(light: "#3E342F", dark: "#F5E6D8"),
        tertiary: Color(hex: "#8A3100"),
        tertiaryContainer: Color(hex: "#B54000"),
        onTertiary: .white,
        onTertiaryContainer: Color(hex: "#FFE6CD"),
        onSurfaceVariant: Color(light: "#594B40", dark: "#D2C3B4"),
        outline: Color(light: "#987F6A", dark: "#BFA78F"),
        outlineVariant: Color(light: "#E8D3C0", dark: "#514032")
    )

    // Referencia: SVG oficial #CC292E / #FEC600; CSS #9D1E23.
    private static let plazaVea = PaletaEmpresa(
        colorMarca: Color(hex: "#CC292E"),
        appPrimary: Color(hex: "#CC292E"),
        primaryContainer: Color(hex: "#9D1E23"),
        onPrimaryContainer: Color(hex: "#FFF0F1"),
        primaryFixed: Color(hex: "#FFF0F1"),
        inversePrimary: Color(hex: "#B22227"),
        secondary: Color(hex: "#7D6100"),
        secondaryContainer: Color(light: "#FEC600", dark: "#594700"),
        onSecondary: .white,
        onSecondaryContainer: Color(light: "#332800", dark: "#FFE99A"),
        tertiary: Color(hex: "#9D1E23"),
        tertiaryContainer: Color(hex: "#9D1E23"),
        onTertiary: .white,
        onTertiaryContainer: Color(hex: "#FFE6E6"),
        onSurfaceVariant: Color(light: "#5B4849", dark: "#D2BCBD"),
        outline: Color(light: "#937A7B", dark: "#BCA4A5"),
        outlineVariant: Color(light: "#DFCBCB", dark: "#513E3F")
    )
}
