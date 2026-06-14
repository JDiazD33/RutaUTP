//
//  MapaView.swift
//  RutaUTP
//
//  Pantalla principal con mapa, búsqueda, marcadores y cards de micros.
//

import SwiftUI

struct MapaView: View {
    @EnvironmentObject private var router: AppRouter
    @State private var drawerOpen = false
    @State private var destination: Destino = .utp
    @State private var searchText: String = ""

    enum Destino: String, CaseIterable, Identifiable {
        case casa, utp, trabajo
        var id: String { rawValue }
        var label: String {
            switch self {
            case .casa:    return "Casa"
            case .utp:     return "UTP"
            case .trabajo: return "Trabajo"
            }
        }
        var icon: String {
            switch self {
            case .casa:    return "house.fill"
            case .utp:     return "graduationcap.fill"
            case .trabajo: return "briefcase.fill"
            }
        }
    }

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
            mapBackground
            VStack(spacing: 0) {
                TopAppBar(leading: .menu, title: "Mapa", titleColor: .appPrimary)
                ZStack(alignment: .bottom) {
                    Color.clear
                    mapOverlays
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Drawer overlay
            SideDrawer(isOpen: $drawerOpen)
                .environmentObject(router)

            // Bottom nav
            VStack {
                Spacer()
                BottomNavBar()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSideDrawer)) { _ in
            drawerOpen = true
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    // MARK: - Map background (placeholder con gradiente + textura)
    private var mapBackground: some View {
        ZStack {
            // Fondo base
            Color.surfaceContainerLow

            // "Calles" decorativas
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                // Diagonal principal
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.75))
                    p.addLine(to: CGPoint(x: w * 0.35, y: h * 0.45))
                    p.addLine(to: CGPoint(x: w * 0.7, y: h * 0.30))
                    p.addLine(to: CGPoint(x: w, y: h * 0.10))
                }
                .stroke(Color.outlineVariant.opacity(0.45), style: StrokeStyle(lineWidth: 8, lineCap: .round))

                Path { p in
                    p.move(to: CGPoint(x: w * 0.05, y: h * 0.15))
                    p.addLine(to: CGPoint(x: w * 0.55, y: h * 0.55))
                    p.addLine(to: CGPoint(x: w * 0.95, y: h * 0.75))
                }
                .stroke(Color.outlineVariant.opacity(0.35), style: StrokeStyle(lineWidth: 6, lineCap: .round))

                Path { p in
                    p.move(to: CGPoint(x: w * 0.20, y: h))
                    p.addLine(to: CGPoint(x: w * 0.30, y: h * 0.70))
                    p.addLine(to: CGPoint(x: w * 0.40, y: h * 0.40))
                    p.addLine(to: CGPoint(x: w * 0.55, y: 0))
                }
                .stroke(Color.outlineVariant.opacity(0.30), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }

            // Gradientes superior e inferior (fog)
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.appBackground.opacity(0.95), Color.appBackground.opacity(0.0)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 120)
                Spacer()
                LinearGradient(
                    colors: [Color.appBackground.opacity(0.0), Color.appBackground.opacity(0.90)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 220)
            }
            .allowsHitTesting(false)

            // Marcadores
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                userMarker
                    .position(x: w * 0.33, y: h * 0.50)
                utpMarker
                    .position(x: w * 0.60, y: h * 0.40)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Overlays flotantes
    private var mapOverlays: some View {
        VStack(spacing: 16) {
            searchPanel
                .padding(.horizontal, 20)
            Spacer()
            reportarPill
                .padding(.leading, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            bottomPanel
        }
        .padding(.bottom, 80) // espacio para la navbar
    }

    private var searchPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.onSurfaceVariant)
                TextField("¿A dónde vas hoy?", text: $searchText)
                    .font(.bodyMd)
                    .foregroundStyle(.onSurface)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.surfaceContainerLow)
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Destino.allCases) { d in
                        chip(d)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.outlineVariant.opacity(0.5), lineWidth: 0.5)
        )
    }

    private func chip(_ d: Destino) -> some View {
        let isActive = (d == destination)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { destination = d }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: d.icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(d.label)
                    .font(.bodySm)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .foregroundStyle(isActive ? Color.onPrimaryContainer : Color.onSurfaceVariant)
            .background(
                Capsule().fill(isActive ? Color.primaryContainer : Color.surfaceContainerHighest)
            )
        }
        .buttonStyle(.plain)
    }

    private var reportarPill: some View {
        Button {} label: {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                Text("REPORTAR")
                    .font(.labelCapsMd)
                    .appTracking(AppTracking.wideLabel)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.appPrimary)
                    .shadow(color: .appPrimary.opacity(0.35), radius: 10, x: 0, y: 4)
            )
        }
        .buttonStyle(.plain)
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Transportes cercanos")
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
                Text("En vivo")
                    .font(.labelCapsMd)
                    .foregroundStyle(.appPrimary)
                    .appTracking(AppTracking.wideLabel)
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
                        RouteCard(ruta: ruta) {
                            router.navigate(to: .detalleRuta)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Markers
    private var userMarker: some View {
        ZStack {
            Circle()
                .fill(Color.secondaryContainer.opacity(0.4))
                .frame(width: 32, height: 32)
                .scaleEffect(pulseScale)
                .opacity(pulseOpacity)
                .onAppear { startPulse() }
            Circle()
                .fill(Color.secondaryContainer)
                .frame(width: 24, height: 24)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.20), radius: 4, x: 0, y: 2)
            Image(systemName: "figure.walk.circle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.onSecondaryContainer)
        }
    }

    private var utpMarker: some View {
        VStack(spacing: 4) {
            Text("UTP Trujillo")
                .font(.labelCapsMd)
                .foregroundStyle(.white)
                .appTracking(AppTracking.wideLabel)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.appPrimary))
            ZStack {
                Circle()
                    .fill(Color.appPrimary)
                    .frame(width: 40, height: 40)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: - Pulse animation
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 1.0

    private func startPulse() {
        withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
            pulseScale = 1.6
            pulseOpacity = 0
        }
    }
}

#Preview {
    MapaView().environmentObject(AppRouter())
}
