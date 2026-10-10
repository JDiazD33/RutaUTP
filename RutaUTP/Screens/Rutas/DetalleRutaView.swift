import SwiftUI
import UIKit

// MARK: - Detalle de la ruta (sub-vista con back)
struct DetalleRutaView: View {
    let ruta: RutaOpcion
    let onBack: () -> Void

    @State private var showCarPlay: Bool = false
    @State private var showExplorador: Bool = false
    private let tabBarHeight: CGFloat = 64

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Mapa con el recorrido real: tocable → explorador fullscreen
                    RutaMapKitView(ruta: ruta)
                        .overlay(alignment: .bottom) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 11, weight: .bold))
                                Text(L.t("Toca para ver el recorrido completo", "Tap to see the full route"))
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.black.opacity(0.55)))
                            .padding(.bottom, 10)
                        }
                        .frame(height: 280)
                        .contentShape(Rectangle())
                        .onTapGesture { showExplorador = true }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(L.t("Explorar recorrido de la línea ", "Explore route for line ") + ruta.lineaConLetra)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { showExplorador = true }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    VStack(spacing: 20) {
                        // Info card
                        HStack(alignment: .top, spacing: 14) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(ruta.colorLinea)
                                .frame(width: 6, height: 48)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ruta.empresa)
                                    .font(.headlineSm)
                                    .foregroundStyle(.onSurface)
                                if !ruta.letraTransporte.isEmpty {
                                    Text(L.t("Letra del transporte: ", "Transport letter: ") + ruta.letraTransporte)
                                        .font(.bodySm.weight(.semibold))
                                        .foregroundStyle(.onSurface)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Text(ruta.recorrido)
                                    .font(.bodySm)
                                    .foregroundStyle(.onSurfaceVariant)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(L.signable("rutas.frecuencia", "FRECUENCIA", "FREQUENCY"))
                                    .font(.labelCapsMd)
                                    .foregroundStyle(.onPrimaryContainer)
                                    .appTracking(AppTracking.wideLabel)
                                Text(ruta.frecuenciaTexto)
                                    .font(.displayNumberMd)
                                    .foregroundStyle(.onPrimaryContainer)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primaryContainer))
                            // La manita va en el CARD rojo, no en la palabra:
                            // anclada al texto quedaba metida dentro del card.
                            .seniable("rutas.frecuencia")
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.surfaceContainerLowest)
                                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.outlineVariant.opacity(0.30), lineWidth: 0.5)
                        )

                        // Stats grid (datos del feed GTFS)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                                  spacing: 12) {
                            StatTile(icon: "clock.fill", iconColor: .appPrimary,
                                     label: L.signable("rutas.tiempo", "TIEMPO VIAJE", "TRIP TIME"), value: ruta.tiempoTexto)
                                .seniable("rutas.tiempo")
                            StatTile(icon: "creditcard.fill", iconColor: .appPrimary,
                                     label: L.signable("rutas.costo", "COSTO", "FARE"), value: ruta.costo)
                                .seniable("rutas.costo")
                            StatTile(icon: "mappin.and.ellipse", iconColor: .appPrimary,
                                     label: L.signable("rutas.paraderos", "PARADEROS", "STOPS"), value: "\(ruta.numParaderos)")
                                .seniable("rutas.paraderos")
                            StatTile(icon: "point.topleft.down.curvedto.point.bottomright.up",
                                     iconColor: .secondary,
                                     label: L.signable("rutas.recorrido", "RECORRIDO", "DISTANCE"), value: String(format: "%.1f km", ruta.distanciaKm))
                                .seniable("rutas.recorrido")
                        }

                        // Pasos
                        VStack(alignment: .leading, spacing: 18) {
                            Text(L.signable("rutas.guia", "Guía paso a paso", "Step-by-step guide"))
                                .font(.headlineXs)
                                .foregroundStyle(.onSurface)
                                .seniable("rutas.guia", distintivoDx: 10)

                            VStack(spacing: 0) {
                                pasoRow("1", L.t("Ve al paradero \(ruta.paradaInicio)", "Go to \(ruta.paradaInicio) stop"),
                                        L.t("Sale uno \(ruta.frecuenciaTexto)", "One departs \(ruta.frecuenciaTexto)"),
                                        "figure.walk", .surfaceContainerHighest, .onSurface, isLast: false)
                                pasoRow("2", L.t("Sube a la línea \(ruta.lineaConLetra)", "Board line \(ruta.lineaConLetra)"),
                                        L.t("\(ruta.empresa) • \(ruta.tiempoTexto) de viaje", "\(ruta.empresa) • \(ruta.tiempoTexto) trip"),
                                        "bus.fill", ruta.colorLinea, .white, isLast: false)
                                pasoRow("3", L.t("Baja en \(ruta.paradaFin)", "Get off at \(ruta.paradaFin)"),
                                        L.t("Fin del recorrido", "End of the route"),
                                        "flag.checkered.fill", .tertiary, .white, isLast: true)
                            }
                        }

                        // Botón de iniciar navegación integrado al final del scroll
                        ctaButton
                            .padding(.top, 12)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                }
            }
            .padding(.bottom, bottomSafeArea() > 0 ? bottomSafeArea() + 64 : 68)
        }
        .background(Color.appBackground.ignoresSafeArea())
        // Explorador del recorrido (se abre tocando el mapa)
        .fullScreenCover(isPresented: $showExplorador) {
            ExploradorRutaView(ruta: ruta)
        }
        // Navegación activa sobre el recorrido GTFS
        .fullScreenCover(isPresented: $showCarPlay) {
            NavegacionRutaView(
                ruta: ruta,
                onFinish: { showCarPlay = false }
            )
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.onSurface)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.surfaceContainerLow))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Volver", "Back"))

            Image(systemName: "bus.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.appPrimary)
            Text(L.t("Ruta ", "Route ") + ruta.linea)
                .font(.headlineLgMobile)
                .foregroundStyle(.appPrimary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(Color.appSurface)
        .overlay(
            Rectangle()
                .fill(Color.outlineVariant.opacity(0.25))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - CTA (dentro del ScrollView)
    private var ctaButton: some View {
        Button {
            // Modo Señas: deja ver el videito antes de que el cover tape el miniplayer.
            SeniasPresenter.shared.ejecutarTrasVerSenia(clave: "nav.iniciar") { showCarPlay = true }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "location.fill")
                    .font(.system(size: 22, weight: .bold))
                Text(L.signable("nav.iniciar", "Iniciar Navegación", "Start Navigation"))
                    .font(.headlineSm)
            }
            .foregroundStyle(.onPrimaryContainer)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primaryContainer)
                    .shadow(color: .primaryContainer.opacity(0.35), radius: 12, x: 0, y: 6)
            )
            .contentShape(Rectangle()) // ✅ CORREGIDO V3
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.t("Iniciar navegación", "Start navigation"))
        .seniable("nav.iniciar", conGesto: false)
    }

    private func bottomSafeArea() -> CGFloat {
        guard let window = UIApplication.shared
            .connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first
        else { return 0 }
        return window.safeAreaInsets.bottom
    }

    private func pasoRow(_ n: String, _ title: String, _ subtitle: String,
                          _ icon: String, _ bg: Color, _ fg: Color, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(bg).frame(width: 24, height: 24)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(fg)
                }
                if !isLast {
                    Rectangle().fill(Color.surfaceContainerHighest)
                        .frame(width: 2, height: 36)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(n). \(title)")
                    .font(.bodyMd)
                    .foregroundStyle(.onSurface)
                Text(subtitle)
                    .font(.bodySm)
                    .foregroundStyle(.onSurfaceVariant)
            }
            .padding(.top, 1)
            Spacer()
        }
    }
}

// MARK: - Stat tile
private struct StatTile: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(iconColor.opacity(0.12)).frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(iconColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.labelCapsMd)
                    .foregroundStyle(.onSurfaceVariant)
                    .appTracking(AppTracking.wideLabel)
                Text(value)
                    .font(.headlineXs)
                    .foregroundStyle(iconColor == .secondary ? Color.secondary : Color.onSurface)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.surfaceContainerLow)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}
