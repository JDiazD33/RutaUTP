import SwiftUI

enum ColorMicroReferencia: String {
    case verde, blanco, azul, amarillo, rojo

    var color: Color {
        switch self {
        case .verde: return Color(hex: "#27B579")
        case .blanco: return Color(hex: "#F4F4F4")
        case .azul: return Color(hex: "#187FB8")
        case .amarillo: return Color(hex: "#F5C928")
        case .rojo: return Color(hex: "#DE3039")
        }
    }

    var nombre: String {
        switch self {
        case .verde: return L.t("Verde", "Green")
        case .blanco: return L.t("Blanco", "White")
        case .azul: return L.t("Azul", "Blue")
        case .amarillo: return L.t("Amarillo", "Yellow")
        case .rojo: return L.t("Rojo", "Red")
        }
    }
}

/// Colores observados en una referencia; no certifican toda la flota actual.
struct ColoresMicroReferencia {
    let linea: String
    let letra: String
    let empresa: String
    let colores: [ColorMicroReferencia]
    let fuente: URL?
}

struct IdentificacionRuta3D {
    let routeID: String
    let codigo: String
    let letra: String
    let empresa: String
    let colores: ColoresMicroReferencia?

    init(ruta: RutaOpcion) {
        let identificacion = GTFSNombreParser.identificacionTransporte(linea: ruta.linea, variante: ruta.variante)
        routeID = ruta.id
        codigo = identificacion.codigo
        letra = identificacion.letra
        empresa = ruta.empresa
        let referencia = Self.referencias[ruta.id]
        // El mismo "A" existe en varias empresas. Nunca enlazar solo por letra.
        if let referencia, referencia.linea == identificacion.codigo,
           referencia.letra == identificacion.letra, referencia.empresa == ruta.empresa {
            colores = referencia
        } else {
            colores = nil
        }
    }

    /// Alcance inicial: codigos M del catalogo urbano, no un route_type inferido.
    var esMicro: Bool { !routeID.hasPrefix("utp:") && codigo.hasPrefix("M-") }
    var claveModelo: String { [routeID, codigo, letra, empresa].joined(separator: "|") }

    // Fotografias aportadas por el usuario y publicacion original de Salaverry.
    // Los tonos son aproximaciones visuales. No se reutilizan fotos ni graficos.
    // Las variantes con corazon quedan separadas y no heredan una foto de la base.
    private static let referencias: [String: ColoresMicroReferencia] = [
        "17434299": .init(linea: "M-07", letra: "V", empresa: "Nuevo California",
                           colores: [.verde, .blanco],
                           fuente: URL(string: "https://onibusbrasil.com/MiguelBusologoTrujillo/14432887")),
        "17522721": .init(linea: "M-05", letra: "H", empresa: "Huanchaco",
                           colores: [.amarillo, .rojo, .blanco],
                           fuente: URL(string: "https://onibusbrasil.com/MiguelBusologoTrujillo/14487628")),
        "17554572": .init(linea: "M-12", letra: "C", empresa: "Nuevo California",
                           colores: [.verde, .blanco], fuente: nil),
        // La publicacion describe expresamente los buses azules A, C y F.
        "17434314": .init(linea: "M-21", letra: "A", empresa: "Salaverry Express",
                           colores: [.azul, .blanco], fuente: fuenteSalaverry),
        "17434472": .init(linea: "M-20", letra: "C", empresa: "Salaverry Express",
                           colores: [.azul], fuente: fuenteSalaverry),
        "17434330": .init(linea: "M-22", letra: "F", empresa: "Salaverry Express",
                           colores: [.azul], fuente: fuenteSalaverry)
    ]

    private static let fuenteSalaverry = URL(string: "https://trujilloexperiencefreewt.blogspot.com/p/como-llegar-puerto-salaverry.html")
}

/// Se muestra en todas las lineas; el modelo por linea empieza por los micros.
struct IdentificacionRuta3DView: View {
    let identificacion: IdentificacionRuta3D
    var activo = true
    @State private var ampliar = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L.t("Reconoce tu transporte", "Recognize your vehicle"))
                    .font(.headlineSm)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                if identificacion.esMicro {
                    Button { ampliar = true } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.appPrimary)
                    .accessibilityLabel(L.t("Ampliar modelo 3D", "Expand 3D model"))
                }
            }
            datos
            if identificacion.esMicro {
                PanelTransporte3D(tipo: .micro, identificacion: identificacion, activo: activo && !ampliar)
                    .id(identificacion.claveModelo)
            } else {
                Label(L.t("Modelo de esta categoría próximamente", "Model for this category coming soon"), systemImage: "cube.transparent")
                    .font(.bodySm)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .padding(.vertical, 12)
            }
        }
        .foregroundStyle(Color.onSurface)
        .padding(16)
        .background(Color.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityIdentifier("ruta.identificacion3d")
        .sheet(isPresented: $ampliar) {
            Transportes3DView(identificacion: identificacion)
        }
    }

    private var datos: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                VStack(spacing: 2) {
                    Text(L.t("Letra", "Letter"))
                        .font(.caption)
                    Text(identificacion.letra.isEmpty ? "—" : identificacion.letra)
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                .foregroundStyle(Color.onPrimaryContainer)
                .frame(width: 88, height: 78)
                .background(Color.primaryContainer, in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 4) {
                    Text(identificacion.codigo).font(.headlineSm)
                    Text(identificacion.empresa)
                        .font(.bodySm)
                        .foregroundStyle(Color.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)

            ColoresReferenciaRutaView(referencia: identificacion.colores)
        }
    }
}

struct ColoresReferenciaRutaView: View {
    let referencia: ColoresMicroReferencia?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let referencia {
                Text(L.t("Colores de referencia", "Reference colors"))
                    .font(.bodySm.weight(.semibold))
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { muestras(referencia) }
                    VStack(alignment: .leading, spacing: 8) { muestras(referencia) }
                }
                Text(L.t("Los colores pueden variar entre unidades.", "Colors may vary between vehicles."))
                    .font(.caption)
                    .foregroundStyle(Color.onSurfaceVariant)
                if let fuente = referencia.fuente {
                    Link(L.t("Ver fuente", "View source"), destination: fuente)
                        .font(.bodySm)
                        .foregroundStyle(Color.appPrimary)
                        .frame(minHeight: 44)
                }
            } else {
                Label(L.t("Color por confirmar", "Color to be confirmed"), systemImage: "paintpalette")
                    .font(.bodySm)
                    .foregroundStyle(Color.onSurfaceVariant)
            }
        }
    }

    @ViewBuilder
    private func muestras(_ referencia: ColoresMicroReferencia) -> some View {
        ForEach(referencia.colores, id: \.rawValue) { color in
            HStack(spacing: 6) {
                Circle()
                    .fill(color.color)
                    .overlay(Circle().stroke(Color.outline, lineWidth: 1))
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                Text(color.nombre).font(.bodySm)
            }
        }
    }
}
