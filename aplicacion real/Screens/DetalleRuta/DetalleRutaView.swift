//
//  DetalleRutaView.swift
//  RutaUTP
//
//  Vista de "Rutas":
//  - El mapa (MapKit) es el fondo de toda la pantalla.
//  - En la parte inferior se muestra una LISTA de rutas disponibles.
//  - Al tocar una ruta, la lista se reemplaza condicionalmente por el
//    DETAIL CARD (mapa hero, stats, pasos, CTA). El card tiene un
//    boton de cerrar para volver a la lista.
//

import SwiftUI
import MapKit

struct DetalleRutaView: View {
    @EnvironmentObject private var router: AppRouter
    @State private var selectedRuta: Ruta? = nil

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -8.1116, longitude: -79.0289),
            span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
        )
    )

    private let utpCoord  = CLLocationCoordinate2D(latitude: -8.1120, longitude: -79.0300)
    private let userCoord = CLLocationCoordinate2D(latitude: -8.1110, longitude: -79.0270)
    private let routeCoords: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: -8.1110, longitude: -79.0270),
        CLLocationCoordinate2D(latitude: -8.1114, longitude: -79.0280),
        CLLocationCoordinate2D(latitude: -8.1117, longitude: -79.0290),
        CLLocationCoordinate2D(latitude: -8.1120, longitude: -79.0300)
    ]

    private let rutas: [Ruta] = [
        Ruta(id: "1", linea: "LÍNEA 10", nombre: "El Cortijo",
             empresa: "Salaverry", tipo: .micro, placa: "T1B-721",
             minutosLlegada: 4, colorIdentificador: .appPrimary),
        Ruta(id: "2", linea: "LÍNEA 4", nombre: "Salaverry",
             empresa: "Salaverry", tipo: .combi, placa: "A6N-450",
             minutosLlegada: 12, colorIdentificador: .secondary),
        Ruta(id: "3", linea: "LÍNEA 7", nombre: "Huanchaco",
             empresa: "El Esfuerzo", tipo: .combi, placa: "B7H-201",
             minutosLlegada: 18, colorIdentificador: .tertiary)
    ]

    var body: some View {
        ZStack(alignment: .top) {
            // 1. Mapa de fondo (siempre visible)
            mapaFondo

            // 2. Header
            VStack(spacing: 0) {
                header
                Spacer()
            }

            // 3. Contenido inferior condicional
            VStack {
                Spacer()
                if let ruta = selectedRuta {
                    detailCard(ruta: ruta)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    rutasListPanel
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selectedRuta)
        .safeAreaInset(edge: .bottom) {
            BottomNavBar()
        }
    }

    // MARK: - Mapa de fondo
    private var mapaFondo: some View {
        Map(position: $cameraPosition) {
            Annotation("UTP Trujillo", coordinate: utpCoord) {
                VStack(spacing: 4) {
                    Text("UTP Trujillo")
                        .font(.labelCapsMd)
                        .foregroundStyle(.white)
                        .appTracking(AppTracking.wideLabel)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.appPrimary))
                        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
                    ZStack {
                        Circle()
                            .fill(Color.appPrimary)
                            .frame(width: 40, height: 40)
                            .overlay(Circle().stroke(Color.white, lineWidth: 3))
                            .shadow(color: .black.opacity(0.30), radius: 6, x: 0, y: 3)
                        Image(systemName: "graduationcap.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            Annotation("Yo", coordinate: userCoord) {
                UserMarker()
            }
            MapPolyline(coordinates: routeCoords)
                .stroke(Color.appPrimary, style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [10, 6]))
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .ignoresSafeArea()
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 12) {
            Button {
                if selectedRuta != nil {
                    withAnimation { selectedRuta = nil }
                } else {
                    router.navigate(to: .mapaPrincipal)
                }
            } label: {
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
            Text("Rutas")
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

    // MARK: - Panel de lista de rutas
    private var rutasListPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Rutas disponibles")
                    .font(.headlineSm)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.appSurface.opacity(0.65))
                    )
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.tertiary)
                        .frame(width: 6, height: 6)
                    Text("En vivo")
                        .font(.labelCapsMd)
                        .foregroundStyle(.appPrimary)
                        .appTracking(AppTracking.wideLabel)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primaryFixed)
                )
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(rutas) { ruta in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                selectedRuta = ruta
                            }
                        } label: {
                            RouteCard(ruta: ruta)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }

            HStack {
                Image(systemName: "hand.tap.fill")
                    .foregroundStyle(.appPrimary)
                Text("Selecciona una ruta para ver el detalle")
                    .font(.bodySm)
                    .foregroundStyle(.onSurfaceVariant)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .padding(.top, 12)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.appSurface)
                .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: -6)
        )
    }

    // MARK: - Detail card (condicional)
    private func detailCard(ruta: Ruta) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                // Handle + cerrar
                HStack {
                    Capsule()
                        .fill(Color.outlineVariant)
                        .frame(width: 40, height: 4)
                    Spacer()
                    Button {
                        withAnimation { selectedRuta = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.onSurfaceVariant)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cerrar detalle")
                }
                .padding(.top, 8)
                .padding(.horizontal, 20)

                // Hero ruta
                mapHero(ruta: ruta)

                // Card de info
                detailInfoCard(ruta: ruta)

                // Stats
                statsGrid

                // Pasos
                stepsSection

                // CTA
                ctaButton
            }
            .padding(.bottom, 120)
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.appBackground)
                .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: -6)
        )
    }

    private func mapHero(ruta: Ruta) -> some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                LinearGradient(
                    colors: [Color.tertiary.opacity(0.6), Color.secondary.opacity(0.4)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    Path { p in
                        p.move(to: CGPoint(x: w * 0.10, y: h * 0.85))
                        p.addCurve(
                            to: CGPoint(x: w * 0.55, y: h * 0.55),
                            control1: CGPoint(x: w * 0.25, y: h * 0.75),
                            control2: CGPoint(x: w * 0.40, y: h * 0.65)
                        )
                        p.addCurve(
                            to: CGPoint(x: w * 0.90, y: h * 0.25),
                            control1: CGPoint(x: w * 0.70, y: h * 0.45),
                            control2: CGPoint(x: w * 0.80, y: h * 0.35)
                        )
                    }
                    .stroke(Color.appPrimary, style: StrokeStyle(lineWidth: 6, lineCap: .round, dash: [12, 6]))
                }
            }
            .frame(height: 200)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(Color.appPrimary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(spacing: 6) {
                Image(systemName: "heart.shield.fill")
                    .font(.system(size: 16, weight: .bold))
                Text("RUTA SEGURA")
                    .font(.labelCapsMd)
                    .appTracking(AppTracking.wideLabel)
            }
            .foregroundStyle(.onTertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(Color.tertiary.opacity(0.85)))
            )
            .shadow(color: .black.opacity(0.20), radius: 8, x: 0, y: 4)
            .padding(12)
        }
        .padding(.horizontal, 20)
    }

    private func detailInfoCard(ruta: Ruta) -> some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 3)
                .fill(ruta.colorIdentificador)
                .frame(width: 6, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(ruta.linea) - \(ruta.empresa)")
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
                Text("\(ruta.minutosLlegada) min")
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
        .padding(.horizontal, 20)
    }

    // MARK: - Stats grid
    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                  spacing: 12) {
            StatTile(icon: "clock.fill", iconColor: .appPrimary, label: "TIEMPO", value: "20 min")
            StatTile(icon: "creditcard.fill", iconColor: .appPrimary, label: "COSTO", value: "S/ 1.50")
            StatTile(icon: "arrow.triangle.2.circlepath", iconColor: .appPrimary, label: "TRANSBORDOS", value: "0")
            StatTile(icon: "chart.bar.fill", iconColor: .secondary, label: "CONGESTIÓN", value: "Media")
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Steps
    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Guía paso a paso")
                .font(.headlineXs)
                .foregroundStyle(.onSurface)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                stepRow(number: "1", title: "Camina al paradero Av. España",
                        subtitle: "250 metros • 3 min aprox.",
                        icon: "figure.walk", color: .surfaceContainerHighest,
                        foreground: .onSurface, isLast: false)
                stepRow(number: "2", title: "Sube a la línea seleccionada",
                        subtitle: "Empresa \(selectedRuta?.empresa ?? "Salaverry") • 15 min de viaje",
                        icon: "bus.fill", color: .appPrimary,
                        foreground: .white, isLast: false)
                stepRow(number: "3", title: "Baja en frontis UTP",
                        subtitle: "Llegada a destino final",
                        icon: "graduationcap.fill", color: .tertiary,
                        foreground: .white, isLast: true)
            }
            .padding(.horizontal, 20)
        }
    }

    private func stepRow(number: String, title: String, subtitle: String,
                          icon: String, color: Color, foreground: Color, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(color)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().stroke(color, lineWidth: 2))
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(foreground)
                }
                if !isLast {
                    Rectangle()
                        .fill(Color.surfaceContainerHighest)
                        .frame(width: 2, height: 36)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(number). \(title)")
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

    // MARK: - CTA
    private var ctaButton: some View {
        Button {} label: {
            HStack(spacing: 10) {
                Image(systemName: "location.fill")
                    .font(.system(size: 22, weight: .bold))
                Text("Iniciar Navegación")
                    .font(.headlineSm)
            }
            .foregroundStyle(.onPrimaryContainer)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primaryContainer)
                    .shadow(color: .primaryContainer.opacity(0.35), radius: 12, x: 0, y: 6)
            )
        }
        .buttonStyle(PressableStyle())
        .padding(.horizontal, 20)
        .accessibilityLabel("Iniciar navegación")
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
                Circle().fill(iconColor.opacity(0.12))
                    .frame(width: 36, height: 36)
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

// MARK: - User marker (compartido con MapaView)
private struct UserMarker: View {
    @State private var pulse: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.secondaryContainer.opacity(0.4))
                .frame(width: 32, height: 32)
                .scaleEffect(pulse ? 1.8 : 1.0)
                .opacity(pulse ? 0 : 1)
                .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: pulse)
            Circle()
                .fill(Color.secondaryContainer)
                .frame(width: 24, height: 24)
                .overlay(Circle().stroke(Color.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
            Image(systemName: "figure.walk.circle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.onSecondaryContainer)
        }
        .onAppear { pulse = true }
    }
}

private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

#Preview {
    DetalleRutaView().environmentObject(AppRouter())
}
