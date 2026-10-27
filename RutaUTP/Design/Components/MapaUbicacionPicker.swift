//
//  MapaUbicacionPicker.swift
//  RutaUTP
//
//  Selector de ubicación a pantalla completa con Apple Maps.
//

import SwiftUI
import MapKit
import CoreLocation

// MARK: - Selector de ubicación a pantalla completa (Apple Maps)

/// Mapa de Apple Maps (MapKit) con pin fijo al centro: el usuario mueve el
/// mapa debajo del pin para señalar el lugar y confirma. Centra en la
/// ubicación actual del GPS (botón blanco circular para volver a ella, igual
/// al de la pestaña Mapa); si el GPS no responde, en el campus UTP.
struct MapaUbicacionPicker: View {
    @Environment(\.dismiss) private var dismiss
    let onConfirmar: (CLLocationCoordinate2D) -> Void
    /// Si el usuario venía a editar un pin ya marcado, el primer fix del GPS
    /// NO mueve la cámara (no le quitamos la vista de su lugar elegido).
    private let teniaUbicacionPrevia: Bool

    /// Campus UTP (Trujillo) como centro por defecto.
    private static let centroDefault = CLLocationCoordinate2D(latitude: -8.1116, longitude: -79.0287)
    @State private var centro: CLLocationCoordinate2D
    @State private var posicion: MapCameraPosition

    // GPS real (mismo servicio que la pestaña Mapa)
    @State private var userRealCoordinate: CLLocationCoordinate2D?
    @State private var locationTask: Task<Void, Never>?
    private let locationService: LocationServiceProtocol

    init(inicial: CLLocationCoordinate2D?, locationService: LocationServiceProtocol,
         onConfirmar: @escaping (CLLocationCoordinate2D) -> Void) {
        self.onConfirmar = onConfirmar
        self.locationService = locationService
        self.teniaUbicacionPrevia = (inicial != nil)
        let centroInicial = inicial ?? Self.centroDefault
        _centro = State(initialValue: centroInicial)
        _posicion = State(initialValue: .camera(MapCamera(centerCoordinate: centroInicial, distance: 900)))
    }

    var body: some View {
        GeometryReader { geometry in
            let punto = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            MapReader { proxy in
                Map(position: $posicion)
                    .overlay {
                        // El anillo es el mismo punto que se convierte a coordenada.
                        PinEnColocacion().position(punto)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        botonMiUbicacion.padding(16)
                    }
                    .onMapCameraChange(frequency: .continuous) { _ in
                        if let coordenada = proxy.convert(punto, from: .local) {
                            centro = coordenada
                        }
                    }
                    .onChange(of: geometry.size) { _, _ in
                        if let coordenada = proxy.convert(punto, from: .local) {
                            centro = coordenada
                        }
                    }
            }
        }
        .ignoresSafeArea()
        .safeAreaInset(edge: .top, spacing: 0) { barraSuperior }
        .safeAreaInset(edge: .bottom, spacing: 0) { panelConfirmar }
        .task { iniciarGPS(autoCentrar: !teniaUbicacionPrevia) }
        .onDisappear {
            locationTask?.cancel()
            locationTask = nil
        }
    }

    // MARK: - Botón Mi Ubicación (idéntico al de la pestaña Mapa)
    private var botonMiUbicacion: some View {
        BotonMiUbicacion(tieneUbicacion: userRealCoordinate != nil) {
            if let userCoord = userRealCoordinate {
                withAnimation(.spring(response: 0.5)) {
                    posicion = .region(MKCoordinateRegion(
                        center: userCoord,
                        span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
                    ))
                }
                centro = userCoord
            } else {
                iniciarGPS(autoCentrar: true)
            }
        }
    }

    // MARK: - GPS (mismo flujo que MapaViewModel.iniciarGPS)
    private func iniciarGPS(autoCentrar: Bool) {
        locationTask?.cancel()
        locationTask = Task { @MainActor in
            let status = await locationService.requestPermission()
            guard !Task.isCancelled, status.isAuthorized else { return }
            let lecturas = locationService.currentLocation()
            locationService.startUpdating()
            for await location in lecturas {
                guard !Task.isCancelled else { return }
                guard UbicacionPuntual.esValida(location, ahora: Date()) else { continue }
                let esPrimerFix = (userRealCoordinate == nil)
                userRealCoordinate = location.coordinate
                if esPrimerFix && autoCentrar {
                    withAnimation(.spring(response: 0.5)) {
                        posicion = .region(MKCoordinateRegion(
                            center: location.coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
                        ))
                    }
                    centro = location.coordinate
                }
            }
        }
    }

    private var barraSuperior: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.onSurface)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.regularMaterial))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Cerrar", "Close"))

            Text(L.t("Arrastra el mapa para marcar el lugar", "Drag the map to mark the location"))
                .font(.bodySmMedium)
                .foregroundStyle(.onSurface)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var panelConfirmar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "location.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityHidden(true)
                Text(String(format: "%.4f, %.4f", centro.latitude, centro.longitude))
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .foregroundStyle(.onSurfaceVariant)

            Button {
                AppHaptics.success()
                onConfirmar(centro)
                dismiss()
            } label: {
                Text(L.t("Confirmar ubicación", "Confirm location"))
                    .font(.headlineSm)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.onPrimaryFill)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primaryFill))
            }
            .buttonStyle(PressableCapsuleStyle())
        }
        .padding(16)
        .padding(.bottom, 8)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.appBackground)
                .shadow(color: .black.opacity(0.18), radius: 14, y: -4)
        )
    }
}
