//
//  RouteTrackingDemoView.swift
//  RutaUTP
//
//  Vista de PRUEBA aislada del módulo de tracking real.
//  NO está conectada al AppRouter por defecto (ver notas abajo).
//
//  Cómo abrirla manualmente para probar:
//   → Se añadió un botón temporal "Tracking Demo" en SideDrawer (MapaView).
//     Al tocarlo, AppRouter.navigate(to: .trackingDemo) muestra esta vista
//     en pantalla completa (sin BottomNavBar, sin drawer).
//
//  Qué prueba:
//   1. Pedir permiso de ubicación al aparecer.
//   2. Mostrar tu ubicación real en el mapa.
//   3. Botón "Simular viaje UTP (Línea 10)" → calcula ruta con MKDirections
//      desde tu pos actual hasta UTP (-8.1116, -79.0287), reutilizando
//      RutaCoordenadas.linea10.last.
//   4. Dibuja la polyline calculada.
//   5. Muestra ETA y distancia.
//
//  Usa `Map(position:)` con `MapCameraPosition` (iOS 17+), mismo estilo que
//  CarPlayNavegacionView.swift para consistencia dentro del módulo nuevo.
//

import SwiftUI
import MapKit
import CoreLocation

struct RouteTrackingDemoView: View {
    @EnvironmentObject private var router: AppRouter
    @StateObject private var vm: RouteTrackingViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var cameraPosition: MapCameraPosition = .automatic

    init(locationService: LocationServiceProtocol = LocationService()) {
        _vm = StateObject(wrappedValue: RouteTrackingViewModel(locationService: locationService))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.appBackground.ignoresSafeArea()

            // Mapa iOS 17+ con MapCameraPosition
            Map(position: $cameraPosition) {
                if let userLoc = vm.userLocation {
                    UserAnnotation()
                        .foregroundStyle(.secondary)
                }
                if let polyline = vm.routePolyline {
                    MapPolyline(polyline)
                        .stroke(Color.appPrimary, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                // Marcador de destino (UTP) si hay un viaje en curso.
                if vm.tripInProgress {
                    let utpCoord = CLLocationCoordinate2D(latitude: -8.098247879173792, longitude: -79.03818104755645)
                    Annotation("UTP Trujillo", coordinate: utpCoord) {
                        MarcadorUTP()        // reutilizamos el marker existente de MapMarkers.swift
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .all))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .ignoresSafeArea(edges: [.bottom, .trailing, .leading])

            // Overlay con la info mínima y controls.
            overlayUI
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await vm.requestPermissionAndStart()
        }
        .onDisappear {
            vm.stop()
        }
    }

    // MARK: - Overlay UI

    private var overlayUI: some View {
        VStack(spacing: 0) {
            // Top bar con back
            topBar

            Spacer()

            // Status + ETA card
            statusCard
                .padding(.horizontal, 16)
                .padding(.bottom, 24)

            // CTA buttons row
            ctaRow
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                vm.stop()
                router.navigate(to: .mapaPrincipal)
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.appPrimary)
                    .background(Circle().fill(Color.white).frame(width: 28, height: 28))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cerrar demo")

            Text("Tracking Demo")
                .font(.headlineLgMobile)
                .foregroundStyle(.appPrimary)

            Spacer()

            // Estado de permiso
            permissionBadge
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var permissionBadge: some View {
        let status = vm.authStatus
        let (text, color): (String, Color) = {
            switch status {
            case .authorizedAlways, .authorizedWhenInUse: return ("UBICACIÓN ON", .tertiary)
            case .denied, .restricted:                    return ("PERMISO OFF", .appError)
            case .notDetermined:                           return ("SIN PERMISO", .onSurfaceVariant)
            @unknown default:                              return ("DESCONOCIDO", .onSurfaceVariant)
            }
        }()
        return Text(text)
            .font(.labelCapsSm)
            .foregroundStyle(.white)
            .appTracking(AppTracking.wideLabel)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(color))
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("UBICACIÓN")
                        .font(.labelCapsSm)
                        .foregroundStyle(.onSurfaceVariant)
                        .appTracking(AppTracking.wideLabel)
                    Text(vm.userLocation.map { String(format: "%.4f, %.4f", $0.latitude, $0.longitude) } ?? "Esperando fix…")
                        .font(.bodyMd)
                        .foregroundStyle(.onSurface)
                }
                Spacer()
            }

            if vm.tripInProgress {
                Divider()
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ETA")
                            .font(.labelCapsSm)
                            .foregroundStyle(.onSurfaceVariant)
                            .appTracking(AppTracking.wideLabel)
                        Text(formattedETA(vm.eta))
                            .font(.headlineSm)
                            .foregroundStyle(.appPrimary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DISTANCIA")
                            .font(.labelCapsSm)
                            .foregroundStyle(.onSurfaceVariant)
                            .appTracking(AppTracking.wideLabel)
                        Text(vm.distance.map { "\(Int($0/1000)) km" } ?? "—")
                            .font(.headlineSm)
                            .foregroundStyle(.onSurface)
                    }
                    if vm.recalculating {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ESTADO")
                                .font(.labelCapsSm)
                                .foregroundStyle(.onSurfaceVariant)
                                .appTracking(AppTracking.wideLabel)
                            HStack(spacing: 4) {
                                ProgressView().scaleEffect(0.6)
                                Text("Recalculando")
                                    .font(.bodySm)
                                    .foregroundStyle(.appPrimary)
                            }
                        }
                    }
                }
            }

            if let err = vm.errorMessage {
                Text(err)
                    .font(.bodySm)
                    .foregroundStyle(.appError)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.errorContainer))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.outlineVariant.opacity(0.3), lineWidth: 0.5)
                )
        )
    }

    private var ctaRow: some View {
        HStack(spacing: 12) {
            if !vm.tripInProgress {
                Button {
                    Task { await vm.startTripUTP(linea: "10") }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text("Simular viaje UTP (Línea 10)")
                            .font(.headlineSm)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.appPrimary))
                }
                .buttonStyle(.plain)
                .disabled(vm.userLocation == nil)
                .opacity(vm.userLocation == nil ? 0.5 : 1)
            } else {
                Button {
                    vm.cancelTrip()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "stop.fill")
                        Text("Detener viaje")
                            .font(.headlineSm)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.appError))
                }
                .buttonStyle(.plain)
            }

            Button {
                if let loc = vm.userLocation {
                    withAnimation(.spring(response: 0.4)) {
                        cameraPosition = .camera(
                            MapCamera(
                                centerCoordinate: loc,
                                distance: 800,
                                heading: 0,
                                pitch: 45
                            )
                        )
                    }
                }
            } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.primaryContainer))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Centrar en mi ubicación")
            .disabled(vm.userLocation == nil)
            .opacity(vm.userLocation == nil ? 0.5 : 1)
        }
    }

    // MARK: - Helpers

    private func formattedETA(_ seconds: TimeInterval?) -> String {
        guard let s = seconds, s > 0 else { return "—" }
        let m = Int(s / 60)
        if m < 60 {
            return "\(m) min"
        }
        let h = Int(m / 60)
        let rem = m % 60
        return "\(h)h \(rem)m"
    }
}

#Preview {
    RouteTrackingDemoView()
}
