import SwiftUI
import UIKit

// MARK: - Detalle de la ruta
struct DetalleRutaView: View {
    let ruta: RutaOpcion
    let locationService: LocationServiceProtocol
    let onBack: () -> Void

    @State private var showCarPlay: Bool = false
    @State private var showExplorador: Bool = false
    @Environment(\.bottomNavBarHeight) private var tabBarHeight
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.self) private var entorno
    @ScaledMetric(relativeTo: .title) private var tamanoInsignia = 76

    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }
    private var superficie: Color { Color(uiColor: .secondarySystemGroupedBackground) }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    resumen
                    datosDelViaje
                    recorrido

                    IdentificacionRuta3DView(identificacion: IdentificacionRuta3D(ruta: ruta),
                                            activo: !showExplorador && !showCarPlay)

                    guia
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }

            ctaButton
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .background(Color.appSurface)
        }
        .padding(.bottom, tabBarHeight)
        .background(Color.appBackground.ignoresSafeArea())
        // Explorador del recorrido (se abre tocando el mapa)
        .fullScreenCover(isPresented: $showExplorador) {
            ExploradorRutaView(ruta: ruta)
        }
        // Navegación activa sobre el recorrido GTFS
        .fullScreenCover(isPresented: $showCarPlay) {
            NavegacionRutaView(
                ruta: ruta,
                locationService: locationService,
                onFinish: { showCarPlay = false }
            )
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.onSurface)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(Color.surfaceContainerLow, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Volver", "Back"))

            Text(L.t("Ruta ", "Route ") + ruta.linea)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.onSurface)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            Image(systemName: "bus")
                .font(.title3)
                .foregroundStyle(acento)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(minHeight: 60)
        .background(Color.appSurface)
    }

    private var resumen: some View {
        VStack(alignment: .leading, spacing: 16) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
            layout {
                insignia
                VStack(alignment: .leading, spacing: 5) {
                    Text(ruta.empresa)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.onSurface)
                    Text(L.t("Línea ", "Line ") + ruta.lineaConLetra)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(ruta.recorridoLocalizado)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    tituloFrecuencia
                    Spacer(minLength: 8)
                    valorFrecuencia
                }
                VStack(alignment: .leading, spacing: 6) {
                    tituloFrecuencia
                    valorFrecuencia
                }
            }
            .seniable("rutas.frecuencia")
        }
        .padding(20)
        .background(superficie, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var insignia: some View {
        VStack(spacing: 2) {
            if ruta.letraTransporte.isEmpty {
                Image(systemName: "bus.fill")
                    .font(.title)
            } else {
                Text(L.t("Letra", "Letter"))
                    .font(.caption2.weight(.medium))
                Text(ruta.letraTransporte)
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .foregroundStyle(colorTextoLetra)
        .padding(8)
        .frame(width: tamanoInsignia, height: tamanoInsignia)
        .background(ruta.colorLinea, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityHidden(true)
    }

    private var colorTextoLetra: Color {
        let color = ruta.colorLinea.resolve(in: entorno)
        let luminancia = 0.2126 * color.linearRed + 0.7152 * color.linearGreen + 0.0722 * color.linearBlue
        let contrasteNegro = (luminancia + 0.05) / 0.05
        let contrasteBlanco = 1.05 / (luminancia + 0.05)
        return contrasteNegro >= contrasteBlanco ? .black : .white
    }

    private var tituloFrecuencia: some View {
        Label(L.signable("rutas.frecuencia", "Frecuencia", "Frequency"), systemImage: "clock")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var valorFrecuencia: some View {
        Text(ruta.frecuenciaTexto)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.onSurface)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var datosDelViaje: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading),
                                 count: dynamicTypeSize.isAccessibilitySize ? 1 : 2),
                  alignment: .leading, spacing: 20) {
            StatTile(icon: "clock", label: L.signable("rutas.tiempo", "Tiempo de viaje", "Travel time"), value: ruta.tiempoTexto)
                .seniable("rutas.tiempo")
            StatTile(icon: "banknote", label: L.signable("rutas.costo", "Pasaje", "Fare"), value: ruta.costo)
                .seniable("rutas.costo")
            StatTile(icon: "mappin", label: L.signable("rutas.paraderos", "Paraderos", "Stops"), value: "\(ruta.numParaderos)")
                .seniable("rutas.paraderos")
            StatTile(icon: "point.topleft.down.curvedto.point.bottomright.up",
                     label: L.signable("rutas.recorrido", "Distancia", "Distance"),
                     value: FormatoNumero.decimal(ruta.distanciaKm) + " km")
                .seniable("rutas.recorrido")
        }
        .padding(20)
        .background(superficie, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var recorrido: some View {
        Button { showExplorador = true } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text(L.t("Ver el recorrido", "Show route"))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.onSurface)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.body.weight(.medium))
                        .foregroundStyle(acento)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(superficie, in: Circle())
                }

                RutaMapKitView(ruta: ruta)
                    .frame(height: 240)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.t("Explorar recorrido de la línea ", "Explore route for line ") + ruta.lineaConLetra)
    }

    private var guia: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.signable("rutas.guia", "Guía paso a paso", "Step-by-step guide"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.onSurface)
                .accessibilityAddTraits(.isHeader)
                .seniable("rutas.guia", distintivoDx: 10)

            VStack(spacing: 0) {
                pasoRow("1", L.f("Ve al paradero {0}", "Go to {0} stop", ["\(ruta.paradaInicioVisible)"]),
                        L.f("Sale uno {0}", "One departs {0}", ["\(ruta.frecuenciaTexto)"]),
                        "figure.walk", Color.surfaceContainerLow, Color.onSurface, isLast: false)
                pasoRow("2", L.f("Sube a la línea {0}", "Board line {0}", ["\(ruta.lineaConLetra)"]),
                        L.f("{0} • {1} de viaje", "{0} • {1} trip", ["\(ruta.empresa)", "\(ruta.tiempoTexto)"]),
                        "bus", ruta.colorLinea, colorTextoLetra, isLast: false)
                pasoRow("3", L.f("Baja en {0}", "Get off at {0}", ["\(ruta.paradaFinVisible)"]),
                        L.t("Fin del recorrido", "End of the route"),
                        "flag.checkered", Color.surfaceContainerLow, Color.onSurface, isLast: true)
            }
            .background(superficie, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var ctaButton: some View {
        Button {
            // Modo Señas: deja ver el videito antes de que el cover tape el miniplayer.
            SeniasPresenter.shared.ejecutarTrasVerSenia(clave: "nav.iniciar") { showCarPlay = true }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "location")
                Text(L.signable("nav.iniciar", "Iniciar navegación", "Start navigation"))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }
            .font(.headline)
            .foregroundStyle(Color.onPrimaryFill)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Color.primaryFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.t("Iniciar navegación", "Start navigation"))
        .seniable("nav.iniciar", conGesto: false)
    }

    private func pasoRow(_ n: String, _ title: String, _ subtitle: String,
                         _ icon: String, _ bg: Color, _ fg: Color, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.body.weight(.medium))
                    .foregroundStyle(fg)
                    .frame(minWidth: 40, minHeight: 40)
                    .background(bg, in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text("\(n). \(title)")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.onSurface)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .accessibilityElement(children: .combine)

            if !isLast {
                Divider().padding(.leading, 68)
            }
        }
    }
}

// MARK: - Datos del viaje
private struct StatTile: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.onSurface)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}
