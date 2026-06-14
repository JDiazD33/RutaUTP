//
//  MapaView.swift
//  RutaUTP
//
//  Pantalla principal con mapa real (MapKit), búsqueda, marcadores y cards de micros.
//

import SwiftUI
import MapKit

struct MapaView: View {
    @EnvironmentObject private var router: AppRouter
    @State private var drawerOpen = false
    @State private var destination: Destino = .utp
    @State private var searchText: String = ""
    @State private var showReportarSheet = false
    @State private var showReportSuccess = false

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -8.1116, longitude: -79.0289),
            span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
        )
    )

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

    // Coordenadas aproximadas: Trujillo - UTP sede
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
            // Mapa real MapKit
            Map(position: $cameraPosition) {
                Annotation("UTP Trujillo", coordinate: utpCoord) {
                    UTPMarker()
                }
                Annotation("Yo", coordinate: userCoord) {
                    UserMarker()
                }
                MapPolyline(coordinates: routeCoords)
                    .stroke(Color.appPrimary, style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [10, 6]))
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .ignoresSafeArea()

            // Header
            VStack(spacing: 0) {
                TopAppBar(leading: .menu, title: "Mapa", titleColor: .appPrimary)
                searchPanel
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                Spacer()
            }

            // Panel inferior
            VStack {
                Spacer()
                reportarPill
                    .padding(.leading, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                bottomPanel
            }
            .padding(.bottom, 12)

            // Drawer overlay
            SideDrawer(isOpen: $drawerOpen)
                .environmentObject(router)
        }
        .safeAreaInset(edge: .bottom) {
            BottomNavBar()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSideDrawer)) { _ in
            drawerOpen = true
        }
        .sheet(isPresented: $showReportarSheet) {
            ReportarSheet()
                .presentationDetents([.medium, .large])
        }
        .alert("Reporte enviado", isPresented: $showReportSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Tu reporte fue enviado a la comunidad. Gracias por colaborar.")
        }
    }

    // MARK: - Search panel
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

    // MARK: - Reportar pill
    private var reportarPill: some View {
        Button {
            showReportarSheet = true
        } label: {
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
        .accessibilityLabel("Reportar incidente")
    }

    // MARK: - Bottom panel (transportes)
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
                        RouteCard(ruta: ruta) {
                            router.navigate(to: .detalleRuta)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

// MARK: - Marcadores personalizados
private struct UTPMarker: View {
    var body: some View {
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
}

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

// MARK: - Reportar Sheet
private struct ReportarSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tipo: TipoReporte = .alerta
    @State private var descripcion: String = ""
    @State private var showSuccess = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Reportar incidente")
                    .font(.headlineMd)

                VStack(alignment: .leading, spacing: 8) {
                    Text("TIPO DE REPORTE")
                        .font(.labelCapsMd)
                        .foregroundStyle(.onSurfaceVariant)
                        .appTracking(AppTracking.wideLabel)
                    Picker("Tipo", selection: $tipo) {
                        Text("Alerta").tag(TipoReporte.alerta)
                        Text("Tráfico").tag(TipoReporte.trafico)
                        Text("Sugerencia").tag(TipoReporte.sugerencia)
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("DESCRIPCIÓN")
                        .font(.labelCapsMd)
                        .foregroundStyle(.onSurfaceVariant)
                        .appTracking(AppTracking.wideLabel)
                    TextField("¿Qué sucede en tu ruta?", text: $descripcion, axis: .vertical)
                        .lineLimit(3...6)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceContainerLow))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("UBICACIÓN")
                        .font(.labelCapsMd)
                        .foregroundStyle(.onSurfaceVariant)
                        .appTracking(AppTracking.wideLabel)
                    HStack {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(.appPrimary)
                        Text("Av. España 1234, Trujillo")
                            .font(.bodySm)
                            .foregroundStyle(.onSurface)
                        Spacer()
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceContainerLow))
                }

                Spacer()

                Button {
                    showSuccess = true
                } label: {
                    Text("Enviar reporte")
                        .font(.headlineSm)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.appPrimary))
                }
                .buttonStyle(.plain)
                .disabled(descripcion.isEmpty)
                .opacity(descripcion.isEmpty ? 0.5 : 1.0)
            }
            .padding(20)
        }
        .alert("Reporte enviado", isPresented: $showSuccess) {
            Button("OK") { dismiss() }
        } message: {
            Text("Gracias por colaborar con la comunidad.")
        }
    }
}

#Preview {
    MapaView().environmentObject(AppRouter())
}
