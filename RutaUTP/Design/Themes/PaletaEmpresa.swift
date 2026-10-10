import SwiftUI

/// Colores preparados una vez por temática. Superficies neutras, errores,
/// colores GTFS y marcas de pago conservan sus responsabilidades originales.
struct PaletaEmpresa {
    let colorMarca: Color
    let appPrimary: Color
    let primaryFill: Color
    let onPrimaryFill: Color
    let primaryGradientEnd: Color
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
        case .cineplanet: return cineplanet
        case .innovaSchools: return innovaSchools
        case .inkafarma: return inkafarma
        case .mifarma: return mifarma
        case .bembos: return bembos
        case .donBelisario: return donBelisario
        }
    }

    // Valores de marca publicados en sus recursos web. Los tonos de interfaz
    // son derivados para que los botones sigan admitiendo texto blanco.
    private static let cineplanet = corporativa(
        marca: "#004A8C", primaria: "#004A8C", secundaria: "#C5003B",
        claro: "#E2EEFF", oscuro: "#203B58")
    // El símbolo publicado en el favicon oficial contiene azul #0069AD,
    // verde #6BC62A y naranja #FF9700. Los acentos pequeños se oscurecen.
    private static let innovaSchools = PaletaEmpresa(
        colorMarca: Color(hex: "#0069AD"),
        appPrimary: Color(light: "#0069AD", dark: "#8BCBFA"),
        primaryFill: Color(hex: "#0069AD"),
        onPrimaryFill: .white,
        primaryGradientEnd: Color(hex: "#A85400"),
        primaryContainer: Color(hex: "#0069AD"),
        onPrimaryContainer: .white,
        primaryFixed: Color(hex: "#DDF0FF"),
        inversePrimary: Color(hex: "#0069AD"),
        secondary: Color(hex: "#317B13"),
        secondaryContainer: Color(light: "#6BC62A", dark: "#294E1D"),
        onSecondary: .white,
        onSecondaryContainer: Color(light: "#17360B", dark: "#D4F3B7"),
        tertiary: Color(hex: "#A85400"),
        tertiaryContainer: Color(hex: "#A85400"),
        onTertiary: .white,
        onTertiaryContainer: .white,
        onSurfaceVariant: Color(light: "#40535D", dark: "#BFD2DF"),
        outline: Color(light: "#728C99", dark: "#9CBCCB"),
        outlineVariant: Color(light: "#CCDDE3", dark: "#354E5B")
    )
    // Amarillo dominante en superficies de acción; verde para enlaces,
    // iconos y detalles. La tinta sobre amarillo nunca depende de .white.
    private static let inkafarma = PaletaEmpresa(
        colorMarca: Color(hex: "#FFF200"),
        appPrimary: Color(light: "#167538", dark: "#8FDC9C"),
        primaryFill: Color(hex: "#FFF200"),
        onPrimaryFill: Color(hex: "#193D23"),
        primaryGradientEnd: Color(hex: "#FFFAD1"),
        primaryContainer: Color(hex: "#FFF200"),
        onPrimaryContainer: Color(hex: "#193D23"),
        primaryFixed: Color(hex: "#FFFAD1"),
        inversePrimary: Color(hex: "#FFF200"),
        secondary: Color(hex: "#167538"),
        secondaryContainer: Color(light: "#DEF3CB", dark: "#274A2A"),
        onSecondary: .white,
        onSecondaryContainer: Color(light: "#255A2A", dark: "#DDF5C3"),
        tertiary: Color(hex: "#167538"),
        tertiaryContainer: Color(hex: "#167538"),
        onTertiary: .white,
        onTertiaryContainer: .white,
        onSurfaceVariant: Color(light: "#4C5139", dark: "#CFD3B6"),
        outline: Color(light: "#887D40", dark: "#BDB56B"),
        outlineVariant: Color(light: "#E3DEB8", dark: "#4A482C")
    )
    private static let mifarma = corporativa(
        marca: "#FF7929", primaria: "#AD4C00", secundaria: "#167538",
        claro: "#FFF0DE", oscuro: "#54371D")
    private static let bembos = corporativa(
        marca: "#1100CF", primaria: "#1100CF", secundaria: "#7D5800",
        claro: "#EAE7FF", oscuro: "#302764")
    private static let donBelisario = corporativa(
        marca: "#E5133A", primaria: "#B70F2E", secundaria: "#121212",
        claro: "#FFE8ED", oscuro: "#542A35")

    /// Construida una sola vez por marca; las vistas consumen los mismos tokens.
    /// Contenedores claros/oscuros, texto y contornos mantienen roles separados.
    private static func corporativa(marca: String, primaria: String,
                                    secundaria: String, claro: String,
                                    oscuro: String) -> PaletaEmpresa {
        PaletaEmpresa(
            colorMarca: Color(hex: marca),
            appPrimary: Color(hex: primaria),
            primaryFill: Color(hex: primaria),
            onPrimaryFill: .white,
            primaryGradientEnd: Color(hex: primaria),
            primaryContainer: Color(hex: primaria),
            onPrimaryContainer: .white,
            primaryFixed: Color(hex: claro),
            inversePrimary: Color(light: primaria, dark: claro),
            secondary: Color(hex: secundaria),
            secondaryContainer: Color(light: claro, dark: oscuro),
            onSecondary: .white,
            onSecondaryContainer: Color(light: secundaria, dark: claro),
            tertiary: Color(hex: primaria),
            tertiaryContainer: Color(hex: primaria),
            onTertiary: .white,
            onTertiaryContainer: .white,
            onSurfaceVariant: Color(light: "#48505A", dark: "#C2CBD6"),
            outline: Color(light: "#77808D", dark: "#A5AFBD"),
            outlineVariant: Color(light: "#D5DCE5", dark: "#3B4655")
        )
    }

    // UTP reproduce literalmente los tokens anteriores de Colors.swift.
    private static let utp = PaletaEmpresa(
        colorMarca: Color(hex: "#a80033"),
        appPrimary: Color(hex: "#a80033"),
        primaryFill: Color(hex: "#a80033"),
        onPrimaryFill: .white,
        primaryGradientEnd: Color(hex: "#005b6e"),
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
        primaryFill: Color(hex: "#007D36"),
        onPrimaryFill: .white,
        primaryGradientEnd: Color(hex: "#006D35"),
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
        primaryFill: Color(hex: "#B54000"),
        onPrimaryFill: .white,
        primaryGradientEnd: Color(hex: "#8A3100"),
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
        primaryFill: Color(hex: "#CC292E"),
        onPrimaryFill: .white,
        primaryGradientEnd: Color(hex: "#9D1E23"),
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
