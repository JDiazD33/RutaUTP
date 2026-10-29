//
//  ExpandedRouteIncidentMap.swift
//  RutaUTP
//
//  Mapa ampliado para elegir el punto afectado.
//

import SwiftUI
import MapKit
import UIKit

struct ExpandedRouteIncidentMap: View {
    let route: RutaGTFS
    let locationService: LocationServiceProtocol
    let markerTint: Color
    let onConfirm: (CLLocationCoordinate2D, MapCameraPosition) -> Void
    private let regionInicial: MKCoordinateRegion
    private let trazado: [CLLocationCoordinate2D]
    private let coordenadasRecorrido: [CLLocationCoordinate2D]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var mapaScope
    @State private var point: CLLocationCoordinate2D?
    @State private var camera: MapCameraPosition
    @State private var camaraVisible: MapCamera?
    @State private var solicitudUbicacion = 0
    @State private var buscandoUbicacion = false
    @State private var mensajeUbicacion: String?
    @State private var mostrarAjustesUbicacion = false

    init(route: RutaGTFS, initialPoint: CLLocationCoordinate2D?, locationService: LocationServiceProtocol,
         markerTint: Color = .orange,
         onConfirm: @escaping (CLLocationCoordinate2D, MapCameraPosition) -> Void) {
        self.route = route
        self.locationService = locationService
        self.markerTint = markerTint
        self.onConfirm = onConfirm
        _point = State(initialValue: initialPoint)
        let shape = route.shape.filter { CLLocationCoordinate2DIsValid($0) }
        trazado = shape
        let recorrido = shape.isEmpty
            ? route.paraderos.map(\.coordinate).filter { CLLocationCoordinate2DIsValid($0) }
            : shape
        coordenadasRecorrido = recorrido
        let cache = (locationService as? LocationService)?.lastKnownLocation
        let lectura = cache.flatMap { location in
            locationService.authorizationStatus.isAuthorized
                && UbicacionPuntual.esValida(location, ahora: Date(),
                    antiguedadMaxima: 30, precisionMaxima: 3_000) ? location : nil
        }
        let centro = lectura?.coordinate ?? initialPoint ?? recorrido.first ?? TransporteApp.referenciaInicio
        let distancia = max(500, (lectura?.horizontalAccuracy ?? 0) * 2)
        let region = MKCoordinateRegion(center: centro, latitudinalMeters: distancia, longitudinalMeters: distancia)
        regionInicial = region
        // Mismo patrón que BoardingPointMap: el respaldo ya está cerca y
        // MapKit sigue el punto azul cuando obtiene la ubicación actual.
        _camera = State(initialValue: .userLocation(followsHeading: false, fallback: .region(region)))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                MapReader { proxy in
                    Map(position: $camera, scope: mapaScope) {
                        UserAnnotation()
                        MapPolyline(coordinates: trazado).stroke(route.color, lineWidth: 4)
                        if let point {
                            Marker(L.t("Lugar afectado", "Affected location"), coordinate: point)
                                .tint(markerTint)
                        }
                    }
                    .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                    .mapControlVisibility(.hidden)
                    .onMapCameraChange(frequency: .onEnd) { contexto in
                        camaraVisible = contexto.camera
                    }
                    .onTapGesture { posicion in
                        guard let coordenada = proxy.convert(posicion, from: .local) else { return }
                        // El seguimiento termina al marcar, conservando el zoom.
                        // Una lectura tardía del GPS nunca sustituye este borrador.
                        camera = camaraVisible.map { .camera($0) } ?? .region(regionInicial)
                        point = coordenada
                        AppHaptics.selection()
                    }
                    .overlay(alignment: .top) {
                        HStack(alignment: .top, spacing: 12) {
                            Label(L.t("Zona válida de la ruta", "Route's valid area"), systemImage: "circle.dashed")
                                .font(.caption.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(10)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .allowsHitTesting(false)
                            Spacer(minLength: 0)
                            controlesMapa
                        }
                        .padding(16)
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        pieMapa(alturaDisponible: geometry.size.height)
                    }
                }
            }
                .background(Color.appBackground)
                .navigationTitle(L.t("Línea ", "Line ") + route.lineaConLetra)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L.t("Cancelar", "Cancel")) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L.t("Usar punto", "Use point")) {
                            guard let point, coherenciaValida else { return }
                            // El mapa pequeño recibe una cámara fija, sin heredar
                            // el seguimiento ni el ámbito del mapa ampliado.
                            let posicion = camera.followsUserLocation
                                ? camaraVisible.map { MapCameraPosition.camera($0) } ?? .region(regionInicial)
                                : camera
                            onConfirm(point, posicion)
                            dismiss()
                        }
                        .disabled(point == nil || !coherenciaValida)
                    }
                }
                .task(id: solicitudUbicacion) {
                    guard scenePhase != .background else { return }
                    await comprobarUbicacion()
                }
                .onChange(of: scenePhase) { _, fase in
                    if fase == .background {
                        buscandoUbicacion = false
                        solicitudUbicacion &+= 1
                    } else if fase == .active {
                        solicitudUbicacion &+= 1
                    }
                }
        }
        .mapScope(mapaScope)
        .tint(Color.appAccent)
    }

    private var controlesMapa: some View {
        let layout = verticalSizeClass == .compact
            ? AnyLayout(HStackLayout(spacing: 12))
            : AnyLayout(VStackLayout(spacing: 12))
        return layout {
            // El control nativo pertenece solo a este mapa. No espera al lector
            // puntual ni modifica el punto afectado.
            MapUserLocationButton(scope: mapaScope)
                .mapControlVisibility(.visible)
                .tint(Color.appAccent)
                .buttonBorderShape(.circle)
                .frame(minWidth: 48, minHeight: 48)
                .accessibilityLabel(L.t("Mi ubicación", "My location"))
                .accessibilityHint(L.t("Centra el mapa sin cambiar el lugar marcado", "Centers the map without changing the marked place"))
            Button(action: verRecorrido) {
                Image(systemName: "map")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.appAccent)
                    .frame(minWidth: 48, minHeight: 48)
                    .background(.regularMaterial, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(coordenadasRecorrido.isEmpty)
            .accessibilityLabel(L.t("Ver ruta completa", "Show full route"))
        }
    }

    private func pieMapa(alturaDisponible: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(L.t("Amplía con dos dedos y toca el lugar afectado.",
                         "Pinch to zoom and tap the affected location."))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                // Mismo veredicto que el formulario: ampliar el mapa no
                // puede ser una puerta para saltarse el filtro.
                AvisoCoherencia(evaluacion: coherencia, route: route)
                SelectorParaderoAccesible(paraderos: route.paraderos, seleccion: point) {
                    point = $0
                    moverCamara(.region(Self.regionCercana($0)))
                }
                if coordenadasRecorrido.isEmpty {
                    Text(L.t("Recorrido no disponible", "Route unavailable"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if buscandoUbicacion {
                    Label(L.t("Buscando tu ubicación…", "Finding your location…"), systemImage: "location")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let mensajeUbicacion {
                    Text(L.aviso(mensajeUbicacion))
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if mostrarAjustesUbicacion {
                        Button(L.t("Abrir Ajustes de ubicación", "Open location settings")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .frame(minHeight: 44)
                    } else {
                        Button(L.t("Reintentar", "Retry")) { solicitudUbicacion &+= 1 }
                            .frame(minHeight: 44)
                            .disabled(buscandoUbicacion)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: max(100, alturaDisponible * (dynamicTypeSize.isAccessibilitySize ? 0.45 : 0.25)))
        .background(.regularMaterial)
    }

    private func moverCamara(_ posicion: MapCameraPosition) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { camera = posicion }
    }

    private static func regionCercana(_ centro: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(center: centro, latitudinalMeters: 500, longitudinalMeters: 500)
    }

    private func verRecorrido() {
        guard let primero = coordenadasRecorrido.first else { return }
        var rect = MKMapRect.null
        for coordenada in coordenadasRecorrido {
            let puntoMapa = MKMapPoint(coordenada)
            rect = rect.union(MKMapRect(origin: puntoMapa, size: MKMapSize(width: 0, height: 0)))
        }
        if rect.size.width < 1, rect.size.height < 1 {
            moverCamara(.region(Self.regionCercana(primero)))
        } else {
            moverCamara(.rect(rect.insetBy(dx: -max(rect.size.width * 0.12, 100),
                                          dy: -max(rect.size.height * 0.12, 100))))
        }
    }

    private func comprobarUbicacion() async {
        let revision = solicitudUbicacion
        buscandoUbicacion = true
        mensajeUbicacion = nil
        defer {
            if revision == solicitudUbicacion { buscandoUbicacion = false }
        }
        let lectura = await UbicacionPuntual.obtener(desde: locationService, timeout: 8,
            antiguedadMaxima: 30, precisionMaxima: 3_000)
        guard !Task.isCancelled, revision == solicitudUbicacion else { return }
        mostrarAjustesUbicacion = locationService.authorizationStatus == .denied
        guard lectura == nil else { return }
        // La lectura solo comprueba disponibilidad; MapKit maneja el centrado.
        // Nunca vuelve a encuadrar después de tocar el mapa o ver toda la ruta.
        switch locationService.authorizationStatus {
        case .denied:
            mensajeUbicacion = L.t("La ubicación está desactivada para esta app. Actívala en Ajustes o marca el lugar manualmente.",
                                   "Location is turned off for this app. Enable it in Settings or mark the spot manually.")
        case .restricted:
            mensajeUbicacion = L.t("El dispositivo restringe el acceso a la ubicación. Puedes marcar el lugar manualmente.",
                                   "This device restricts location access. You can mark the spot manually.")
        default:
            mensajeUbicacion = L.t("No pudimos obtener una ubicación reciente y precisa. Vuelve a intentarlo o marca el lugar manualmente.",
                                   "Couldn't get a recent, accurate location. Try again or mark the spot manually.")
        }
    }

    private var coherencia: CoherenciaPunto? {
        guard let point else { return nil }
        return VerificadorCoherencia.evaluar(point: point, ruta: route)
    }

    private var coherenciaValida: Bool { coherencia?.esValido ?? true }
}
