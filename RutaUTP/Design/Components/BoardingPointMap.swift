//
//  BoardingPointMap.swift
//  RutaUTP
//
//  Mapa para elegir el paradero de subida.
//

import SwiftUI
import CoreLocation
import MapKit
import UIKit

/// La cámara se acerca al usuario al abrir; cada selección explícita guarda el pin.
struct BoardingPointMap: View {
    let route: RutaGTFS
    let locationService: LocationServiceProtocol
    let onSelect: (BoardingPoint) -> Void
    private let regionInicial: MKCoordinateRegion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var mapaScope
    @State private var point: BoardingPoint?
    @State private var camera: MapCameraPosition
    @State private var regionVisible: MKCoordinateRegion?
    @State private var ubicacionActual: CLLocation?
    @State private var ultimoPermiso: CLAuthorizationStatus
    @State private var solicitudUbicacion = 0
    @State private var revisionPunto = 0
    @State private var revisionPuntoSolicitado = 0
    @State private var buscandoUbicacion = false
    @State private var mensajeUbicacion: String?
    @State private var marcarUbicacionSolicitada = false
    @State private var mostrarAjustesUbicacion = false
    @State private var reanudarUbicacion = false
    private static let antiguedadMaximaUbicacion: TimeInterval = 30
    // Centrar un mapa admite la ubicación aproximada de iOS; no cambia la
    // precisión exigida por navegación, detección ni los demás consumidores.
    private static let precisionMaximaUbicacion: CLLocationAccuracy = 3_000

    init(route: RutaGTFS, initialPoint: BoardingPoint?, currentLocation: CLLocation?,
         locationService: LocationServiceProtocol,
         onSelect: @escaping (BoardingPoint) -> Void) {
        self.route = route
        self.locationService = locationService
        self.onSelect = onSelect
        _ultimoPermiso = State(initialValue: locationService.authorizationStatus)
        _point = State(initialValue: initialPoint)
        let lecturas = [currentLocation, (locationService as? LocationService)?.lastKnownLocation]
            .compactMap { $0 }
            .filter { locationService.authorizationStatus.isAuthorized
                && UbicacionPuntual.esValida($0, ahora: Date(),
                    antiguedadMaxima: Self.antiguedadMaximaUbicacion,
                    precisionMaxima: Self.precisionMaximaUbicacion) }
        let lectura = lecturas.max { $0.timestamp < $1.timestamp }
        let center = lectura?.coordinate ?? initialPoint?.coordinate ?? TransporteApp.referenciaInicio
        regionInicial = lectura.map(Self.regionUbicacion) ?? Self.regionCercana(center)
        _ubicacionActual = State(initialValue: lectura)
        // Con una lectura validada la cámara se fija en esa coordenada. Si se
        // usa `.userLocation`, MapKit puede resolverla con su propia caché (otra
        // ubicación) y no volver a centrar cuando llega el fix real; la flecha
        // sí funciona porque vuelve a pedir la posición.
        _camera = State(initialValue: lectura.map { MapCameraPosition.region(Self.regionUbicacion($0)) }
            ?? .userLocation(followsHeading: false, fallback: .region(regionInicial)))
    }

    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }

    private var puedeConfirmar: Bool {
        point != nil && !(buscandoUbicacion && marcarUbicacionSolicitada
                         && revisionPunto == revisionPuntoSolicitado)
    }

    private static func regionCercana(_ center: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(center: center, latitudinalMeters: 500, longitudinalMeters: 500)
    }

    private static func regionUbicacion(_ location: CLLocation) -> MKCoordinateRegion {
        let distancia = max(500, location.horizontalAccuracy * 2)
        return MKCoordinateRegion(center: location.coordinate,
                                  latitudinalMeters: distancia, longitudinalMeters: distancia)
    }

    private var lecturaDisponible: CLLocation? {
        [ubicacionActual, (locationService as? LocationService)?.lastKnownLocation]
            .compactMap { $0 }
            .filter { locationService.authorizationStatus.isAuthorized
                && UbicacionPuntual.esValida($0, ahora: Date(),
                    antiguedadMaxima: Self.antiguedadMaximaUbicacion,
                    precisionMaxima: Self.precisionMaximaUbicacion) }
            .max { $0.timestamp < $1.timestamp }
    }

    @MainActor
    private func moverCamara(_ position: MapCameraPosition) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            camera = position
        }
    }

    @MainActor
    private func seleccionar(_ coordinate: CLLocationCoordinate2D) {
        guard let nuevoPunto = BoardingPoint(coordinate: coordinate) else { return }
        revisionPunto &+= 1
        point = nuevoPunto
        onSelect(nuevoPunto)
    }

    @MainActor
    private func solicitarUbicacion(marcarPunto: Bool) {
        // El centrado no depende de que el lector puntual consiga otro fix.
        // La búsqueda de coordenadas solo sirve para guardar el punto de subida.
        centrarEnUsuario()
        revisionPuntoSolicitado = revisionPunto
        marcarUbicacionSolicitada = marcarPunto
        mensajeUbicacion = nil
        mostrarAjustesUbicacion = false
        if let lectura = lecturaDisponible {
            // La nueva orden invalida cualquier respuesta puntual anterior.
            solicitudUbicacion &+= 1
            buscandoUbicacion = false
            marcarUbicacionSolicitada = false
            ubicacionActual = lectura
            if marcarPunto { seleccionar(lectura.coordinate) }
            return
        }
        buscandoUbicacion = true
        solicitudUbicacion &+= 1
    }

    @MainActor
    private func centrarEnUsuario() {
        // Centrar en la misma lectura que se marcaría: `.userLocation` puede
        // quedarse en una caché de MapKit distinta a la del servicio.
        if let lectura = lecturaDisponible {
            moverCamara(.region(Self.regionUbicacion(lectura)))
        } else {
            moverCamara(.userLocation(followsHeading: false,
                                      fallback: .region(regionVisible ?? regionInicial)))
        }
    }

    @MainActor
    private func prepararUbicacion() async {
        let revisionAlAbrir = revisionPunto
        let permiso = await locationService.requestPermission()
        guard !Task.isCancelled else { return }
        guard permiso.isAuthorized else {
            if permiso.isDenied { informarFalloUbicacion() }
            return
        }
        if let lectura = lecturaDisponible {
            ubicacionActual = lectura
            centrarAlAbrir(lectura, revisionAlAbrir: revisionAlAbrir)
            return
        }
        // La caché puede faltar cuando la lámina se abre después de varios
        // pasos. Pedir un fix evita quedarse en el respaldo (punto anterior o
        // referencia de la universidad) hasta que alguien pulse la flecha.
        let location = await UbicacionPuntual.obtener(desde: locationService, timeout: 8,
            antiguedadMaxima: Self.antiguedadMaximaUbicacion,
            precisionMaxima: Self.precisionMaximaUbicacion)
        guard !Task.isCancelled, let location else { return }
        ubicacionActual = location
        centrarAlAbrir(location, revisionAlAbrir: revisionAlAbrir)
    }

    /// Un solo centrado automático al abrir: si la persona ya eligió un punto
    /// (o lo hizo mientras llegaba el fix), su cámara no se mueve.
    @MainActor
    private func centrarAlAbrir(_ location: CLLocation, revisionAlAbrir: Int) {
        guard revisionPunto == revisionAlAbrir else { return }
        moverCamara(.region(Self.regionUbicacion(location)))
    }

    private func informarFalloUbicacion() {
        switch locationService.authorizationStatus {
        case .denied:
            mostrarAjustesUbicacion = true
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

    @MainActor
    private func actualizarUbicacionActual() async {
        guard buscandoUbicacion else { return }
        guard scenePhase != .background else {
            reanudarUbicacion = true
            buscandoUbicacion = false
            return
        }
        let solicitud = solicitudUbicacion
        defer {
            // Una cancelación de SwiftUI tampoco puede dejar el indicador activo.
            if solicitud == solicitudUbicacion {
                buscandoUbicacion = false
                marcarUbicacionSolicitada = false
            }
        }
        // Una respuesta tardía solo puede guardar el punto aún solicitado;
        // nunca cambia la cámara que maneja el usuario o el control nativo.
        let puntoAlSolicitar = revisionPuntoSolicitado
        let marcarPunto = marcarUbicacionSolicitada
        let location = await UbicacionPuntual.obtener(desde: locationService, timeout: 8,
            antiguedadMaxima: Self.antiguedadMaximaUbicacion,
            precisionMaxima: Self.precisionMaximaUbicacion)
        guard !Task.isCancelled, solicitud == solicitudUbicacion else { return }
        buscandoUbicacion = false
        marcarUbicacionSolicitada = false
        guard let location else {
            informarFalloUbicacion()
            return
        }
        ubicacionActual = location
        if marcarPunto, revisionPunto == puntoAlSolicitar {
            seleccionar(location.coordinate)
        }
    }

    @MainActor
    private func verRecorrido() {
        let coordinates = (route.shape.isEmpty ? route.paraderos.map(\.coordinate) : route.shape)
            .filter { CLLocationCoordinate2DIsValid($0) }
        guard let first = coordinates.first else {
            moverCamara(.region(regionInicial))
            return
        }
        var rect = MKMapRect.null
        for coordinate in coordinates {
            let mapPoint = MKMapPoint(coordinate)
            rect = rect.union(MKMapRect(origin: mapPoint, size: MKMapSize(width: 0, height: 0)))
        }
        if rect.size.width < 1, rect.size.height < 1 {
            moverCamara(.region(Self.regionCercana(first)))
        } else {
            moverCamara(.rect(rect.insetBy(dx: -max(rect.size.width * 0.12, 100),
                                          dy: -max(rect.size.height * 0.12, 100))))
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                MapReader { proxy in
                    Map(position: $camera, scope: mapaScope) {
                        UserAnnotation()
                        MapPolyline(coordinates: route.shape).stroke(route.color, lineWidth: 4)
                        if let point {
                            Marker(L.t("Aquí subí", "I boarded here"), coordinate: point.coordinate)
                                .tint(acento)
                        }
                    }
                    // Sin límites de distancia: se conserva todo el zoom y los
                    // gestos nativos. Tocar el mapa solo cambia la selección.
                    .onTapGesture { location in
                        if let coordinate = proxy.convert(location, from: .local) {
                            // Fijar la cámara al marcar: el seguimiento no debe
                            // desplazar el mapa mientras se elige una subida.
                            camera = .region(regionVisible ?? regionInicial)
                            seleccionar(coordinate)
                        }
                    }
                    .onMapCameraChange(frequency: .onEnd) { contexto in
                        regionVisible = contexto.region
                    }
                    .mapControlVisibility(.hidden)
                    .overlay(alignment: .topTrailing) {
                        controlesMapa.padding(16)
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        pieMapa(alturaDisponible: geometry.size.height)
                    }
                }
            }
            .background(Color.appBackground)
            .navigationTitle(L.t("¿Dónde subiste?", "Where did you board?"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appSurface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .task { await prepararUbicacion() }
            .task(id: solicitudUbicacion) { await actualizarUbicacionActual() }
            .onReceive(locationService.authorizationPublisher) { estado in
                // El publisher puede volver a emitir su valor al reconstruir
                // la vista. Solo un cambio real de permiso permite reintentar.
                guard estado != ultimoPermiso else { return }
                ultimoPermiso = estado
                if estado.isAuthorized {
                    if mostrarAjustesUbicacion { centrarEnUsuario() }
                    mostrarAjustesUbicacion = false
                    mensajeUbicacion = nil
                } else if estado.isDenied {
                    informarFalloUbicacion()
                }
            }
            .onChange(of: scenePhase) { _, fase in
                if fase == .background, buscandoUbicacion {
                    reanudarUbicacion = true
                    buscandoUbicacion = false
                    solicitudUbicacion &+= 1
                } else if fase == .active, reanudarUbicacion {
                    reanudarUbicacion = false
                    buscandoUbicacion = true
                    solicitudUbicacion &+= 1
                } else if fase == .active, mostrarAjustesUbicacion,
                          locationService.authorizationStatus.isAuthorized, !buscandoUbicacion {
                    solicitarUbicacion(marcarPunto: false)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("Listo", "Done")) { dismiss() }
                        .frame(minHeight: 44)
                }
            }
        }
        .mapScope(mapaScope)
        .tint(acento)
    }

    private var controlesMapa: some View {
        let layout = verticalSizeClass == .compact
            ? AnyLayout(HStackLayout(spacing: 12))
            : AnyLayout(VStackLayout(spacing: 12))
        return layout {
            // Asociado explícitamente a ESTE mapa, no al mapa principal que
            // sigue debajo de la presentación. No espera ni desactiva la flecha
            // por el estado del lector usado para «Marcar mi ubicación».
            MapUserLocationButton(scope: mapaScope)
                .mapControlVisibility(.visible)
                .tint(acento)
                .buttonBorderShape(.circle)
                .frame(minWidth: 48, minHeight: 48)
                .accessibilityLabel(L.t("Mi ubicación", "My location"))
                .accessibilityHint(L.t("Centra el mapa sin cambiar el lugar marcado", "Centers the map without changing the marked place"))

            Button { verRecorrido() } label: {
                Image(systemName: "map")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(acento)
                    .frame(minWidth: 48, minHeight: 48)
                    .background(.regularMaterial, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Ver el recorrido", "Show route"))
        }
    }

    private func pieMapa(alturaDisponible: CGFloat) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L.t("Punto de subida", "Boarding point"))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.onSurface)
                        .accessibilityAddTraits(.isHeader)
                    Text(point == nil
                         ? L.t("Toca el mapa donde subiste o marca tu ubicación actual.",
                               "Tap where you boarded on the map or mark your current location.")
                         : L.t("Punto guardado. Toca otro lugar del mapa para cambiarlo.",
                               "Point saved. Tap another place on the map to change it."))
                        .font(.subheadline)
                        .foregroundStyle(Color.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)

                    if buscandoUbicacion {
                        Label(L.t("Buscando tu ubicación…", "Finding your location…"), systemImage: "location")
                            .font(.subheadline)
                            .foregroundStyle(Color.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let ubicacionActual, ubicacionActual.horizontalAccuracy > 50 {
                        Text(L.t("Tu ubicación es aproximada. Ajusta el punto en el mapa si hace falta.",
                                 "Your location is approximate. Adjust the point on the map if needed."))
                            .font(.subheadline)
                            .foregroundStyle(Color.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let mensajeUbicacion {
                        Text(L.aviso(mensajeUbicacion))
                            .font(.subheadline)
                            .foregroundStyle(Color.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                        if mostrarAjustesUbicacion {
                            Button(L.t("Abrir Ajustes de ubicación", "Open location settings")) {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                            .frame(minHeight: 44)
                        } else {
                            Button(L.t("Reintentar ubicación", "Retry location")) {
                                solicitarUbicacion(marcarPunto: false)
                            }
                            .frame(minHeight: 44)
                        }
                    }
                    Button { solicitarUbicacion(marcarPunto: true) } label: {
                        Label(L.t("Marcar mi ubicación", "Mark my location"), systemImage: "mappin.and.ellipse")
                            .font(.body.weight(.medium))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(buscandoUbicacion)
                    .foregroundStyle(acento)
                    .accessibilityHint(L.t("Guarda tu ubicación actual como punto de subida.",
                                          "Saves your current location as the boarding point."))
                    SelectorParaderoAccesible(paraderos: route.paraderos, seleccion: point?.coordinate) {
                        seleccionar($0)
                        moverCamara(.region(Self.regionCercana($0)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)
            }
            // El pie puede desplazarse con texto grande o en horizontal; la
            // confirmación sigue visible y el mapa conserva espacio útil.
            .frame(maxHeight: max(100, alturaDisponible * (dynamicTypeSize.isAccessibilitySize ? 0.45 : 0.32)))

            Button {
                guard puedeConfirmar else { return }
                dismiss()
            } label: {
                Text(L.t("Listo", "Done"))
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(Color.onPrimaryFill)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.primaryFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!puedeConfirmar)
            .opacity(puedeConfirmar ? 1 : 0.5)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(Color.appSurface)
        .overlay(alignment: .top) { Divider() }
    }
}
