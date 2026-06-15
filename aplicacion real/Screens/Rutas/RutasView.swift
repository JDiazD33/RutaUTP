//
//  RutasView.swift
//  RutaUTP
//
//  Vista de Rutas (tab "Rutas" del BottomNavBar).
//  - Estado 1 (sin ruta seleccionada): mapa no interactivo + lista de rutas.
//  - Estado 2 (con ruta seleccionada): DetalleRutaView con transición slide.
//

import SwiftUI
import MapKit

// MARK: - Modelo
struct RutaOpcion: Identifiable, Equatable {
    let id: Int
    let linea: String
    let empresa: String
    let recorrido: String
    let llegaEn: String
    let tiempo: String
    let costo: String
    let congestion: String
    let colorLinea: Color
}

// MARK: - Vista principal
struct RutasView: View {
    @EnvironmentObject var router: AppRouter
    @State private var rutaSeleccionada: RutaOpcion? = nil

    private let tabBarHeight: CGFloat = 64

    let rutas: [RutaOpcion] = [
        RutaOpcion(id: 1, linea: "B",  empresa: "Empresa Salaverry",
                   recorrido: "Salaverry → UTP → Centro",
                   llegaEn: "4 min",   tiempo: "20 min", costo: "S/ 1.50",
                   congestion: "Media", colorLinea: .appPrimary),
        RutaOpcion(id: 2, linea: "10", empresa: "El Cortijo",
                   recorrido: "El Cortijo → Av. España → UTP",
                   llegaEn: "7 min",   tiempo: "25 min", costo: "S/ 1.00",
                   congestion: "Baja",  colorLinea: .secondary),
        RutaOpcion(id: 3, linea: "4",  empresa: "Trans Salaverry",
                   recorrido: "Huanchaco → Centro → UTP",
                   llegaEn: "12 min",  tiempo: "30 min", costo: "S/ 1.50",
                   congestion: "Alta",  colorLinea: .tertiary),
        RutaOpcion(id: 4, linea: "C",  empresa: "Trans Moche",
                   recorrido: "Moche → Av. España → Plaza Mayor",
                   llegaEn: "18 min",  tiempo: "35 min", costo: "S/ 1.00",
                   congestion: "Media", colorLinea: Color(hex: "#6750a4"))
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            if let ruta = rutaSeleccionada {
                DetalleRutaView(ruta: ruta, onBack: {
                    withAnimation(.spring(response: 0.3)) { rutaSeleccionada = nil }
                })
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal:   .move(edge: .trailing)
                ))
            } else {
                listaScreen
                    .transition(.opacity)
            }
            BottomNavBar()
        }
        .ignoresSafeArea(edges: .bottom)
        .animation(.spring(response: 0.3), value: rutaSeleccionada == nil)
    }

    // MARK: - Lista screen
    private var listaScreen: some View {
        VStack(spacing: 0) {
            // Header
            header
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    RutasMapView()
                        .frame(height: 280)

                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Elige tu ruta")
                                    .font(.headlineSm)
                                    .foregroundStyle(.onSurface)
                                Text("Toca una ruta para ver el detalle")
                                    .font(.bodySm)
                                    .foregroundStyle(.onSurfaceVariant)
                            }
                            Spacer()
                        }
                        .padding(.top, 20)

                        ForEach(rutas) { ruta in
                            RutaOpcionCard(ruta: ruta)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3)) {
                                        rutaSeleccionada = ruta
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, tabBarHeight + 30)
                }
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "bus.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.appPrimary)
            Text("Rutas")
                .font(.headlineLgMobile)
                .foregroundStyle(.appPrimary)
            Spacer()
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.appPrimary)
                    .frame(width: 7, height: 7)
                Text("EN VIVO")
                    .font(.labelCapsSm)
                    .foregroundStyle(.appPrimary)
                    .appTracking(AppTracking.wideLabel)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.primaryFixed))
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .background(Color.appSurface)
        .overlay(
            Rectangle()
                .fill(Color.outlineVariant.opacity(0.25))
                .frame(height: 1),
            alignment: .bottom
        )
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Ruta Opcion Card
private struct RutaOpcionCard: View {
    let ruta: RutaOpcion

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 3)
                .fill(ruta.colorLinea)
                .frame(width: 4, height: 56)

            ZStack {
                Circle()
                    .fill(ruta.colorLinea.opacity(0.12))
                    .frame(width: 44, height: 44)
                Text(ruta.linea)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(ruta.colorLinea)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(ruta.empresa)
                    .font(.bodyMdMedium)
                    .foregroundStyle(.onSurface)
                Text(ruta.recorrido)
                    .font(.bodySm)
                    .foregroundStyle(.onSurfaceVariant)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(ruta.llegaEn)
                    .font(.bodyMdMedium)
                    .foregroundStyle(ruta.colorLinea)
                Text("llegada")
                    .font(.labelCapsSm)
                    .foregroundStyle(.onSurfaceVariant)
                    .appTracking(AppTracking.wideLabel)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.onSurfaceVariant.opacity(0.4))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.surfaceContainerLowest)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.outlineVariant.opacity(0.40), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Mapa no interactivo para RutasView
private struct RutasMapView: View {
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: -8.1116, longitude: -79.0287),
        span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035)
    )
    private let marcadores: [MapaAnotacion] = [
        MapaAnotacion(id: 1, lat: -8.1116, lon: -79.0287, tipo: .utp),
        MapaAnotacion(id: 2, lat: -8.1180, lon: -79.0350, tipo: .usuario)
    ]

    var body: some View {
        Map(coordinateRegion: $region, annotationItems: marcadores) { m in
            MapAnnotation(coordinate: m.coordinate) {
                switch m.tipo {
                case .utp:     MarcadorUTP()
                case .usuario: PulsingUserMarker()
                case .bus:     EmptyView()
                }
            }
        }
        .disabled(true)
        .overlay(
            // Gradient fade al bottom
            VStack {
                Spacer()
                LinearGradient(
                    colors: [Color.clear, Color.appBackground.opacity(0.6)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 60)
                .allowsHitTesting(false)
            }
        )
    }
}

// MARK: - Detalle de la ruta (sub-vista con back)
private struct DetalleRutaView: View {
    let ruta: RutaOpcion
    let onBack: () -> Void

    @State private var showCarPlay: Bool = false
    private let tabBarHeight: CGFloat = 64
    private let ctaHeight: CGFloat = 88

    var body: some View {
        VStack(spacing: 0) {
            header
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // CORREGIDO V4: mapa real con MapKit (reemplaza contenedor azul decorativo)
                    RutaMapKitView(ruta: ruta)
                        .frame(height: 280)
                        .disabled(true)            // no captura gestos de scroll
                        .allowsHitTesting(false)   // tampoco los de toque
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    VStack(spacing: 20) {
                        // Info card
                        HStack(alignment: .top, spacing: 14) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(ruta.colorLinea)
                                .frame(width: 6, height: 48)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(ruta.empresa)")
                                    .font(.headlineSm)
                                    .foregroundStyle(.onSurface)
                                Text("Destino: UTP Trujillo")
                                    .font(.bodySm)
                                    .foregroundStyle(.onSurfaceVariant)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("LLEGA EN")
                                    .font(.labelCapsMd)
                                    .foregroundStyle(.onPrimaryContainer)
                                    .appTracking(AppTracking.wideLabel)
                                Text(ruta.llegaEn)
                                    .font(.displayNumberMd)
                                    .foregroundStyle(.onPrimaryContainer)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primaryContainer))
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

                        // Stats grid
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                                  spacing: 12) {
                            StatTile(icon: "clock.fill", iconColor: .appPrimary,
                                     label: "TIEMPO", value: ruta.tiempo)
                            StatTile(icon: "creditcard.fill", iconColor: .appPrimary,
                                     label: "COSTO", value: ruta.costo)
                            StatTile(icon: "arrow.triangle.2.circlepath", iconColor: .appPrimary,
                                     label: "TRANSBORDOS", value: "0")
                            StatTile(icon: "chart.bar.fill", iconColor: .secondary,
                                     label: "CONGESTIÓN", value: ruta.congestion)
                        }

                        // Pasos
                        VStack(alignment: .leading, spacing: 18) {
                            Text("Guía paso a paso")
                                .font(.headlineXs)
                                .foregroundStyle(.onSurface)

                            VStack(spacing: 0) {
                                pasoRow("1", "Camina al paradero Av. España",
                                        "250 metros • 3 min aprox.",
                                        "figure.walk", .surfaceContainerHighest, .onSurface, isLast: false)
                                pasoRow("2", "Sube a la línea \(ruta.linea)",
                                        "\(ruta.empresa) • 15 min de viaje",
                                        "bus.fill", .appPrimary, .white, isLast: false)
                                pasoRow("3", "Baja en frontis UTP",
                                        "Llegada a destino final",
                                        "graduationcap.fill", .tertiary, .white, isLast: true)
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
        // CORREGIDO V3: fullScreenCover para modo CarPlay
        .fullScreenCover(isPresented: $showCarPlay) {
            CarPlayNavegacionView(
                rutaNombre: "Ruta \(ruta.linea) - \(ruta.empresa)",
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
            .accessibilityLabel("Volver")

            Image(systemName: "bus.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.appPrimary)
            Text("Ruta \(ruta.linea)")
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
            showCarPlay = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "location.fill")
                    .font(.system(size: 22, weight: .bold))
                Text("Iniciar Navegación")
                    .font(.headlineSm)
            }
            .foregroundStyle(.onPrimaryContainer)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primaryContainer)
                    .shadow(color: .primaryContainer.opacity(0.35), radius: 12, x: 0, y: 6)
            )
            .contentShape(Rectangle()) // CORREGIDO V3
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Iniciar navegación")
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
    }
}

#Preview {
    RutasView().environmentObject(AppRouter())
}

