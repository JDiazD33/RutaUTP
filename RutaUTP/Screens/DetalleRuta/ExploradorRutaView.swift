//
//  ExploradorRutaView.swift
//  RutaUTP
//
//  Mapa a pantalla completa para explorar el recorrido REAL de una ruta
//  (shape GTFS): pan/zoom libres, paraderos sobre el trazado y leyenda
//  con los datos oficiales del feed.
//
//  Se abre desde DetalleRutaView al tocar el mapa de la ruta.
//

import SwiftUI
import MapKit
import UIKit

// MARK: - Anotaciones
final class ParaderoExploraAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let nombre: String
    let esInicio: Bool
    let esFin: Bool

    var title: String? {
        if esInicio { return L.t("Inicio del recorrido", "Route start") }
        if esFin { return L.t("Fin del recorrido", "Route end") }
        return nombre
    }
    var subtitle: String? { esInicio || esFin ? nombre : nil }

    init(coordinate: CLLocationCoordinate2D, nombre: String,
         esInicio: Bool = false, esFin: Bool = false) {
        self.coordinate = coordinate
        self.nombre = nombre
        self.esInicio = esInicio
        self.esFin = esFin
    }
}

/// Conserva el punto pequeño y amplía su área táctil sin tapar el trazado.
private final class PuntoParaderoExploradorView: MKAnnotationView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -max(0, (44 - bounds.width) / 2),
                       dy: -max(0, (44 - bounds.height) / 2)).contains(point)
    }
}

// MARK: - Mapa interactivo
struct MapaExploradorRepresentable: UIViewRepresentable {
    let coordenadas: [CLLocationCoordinate2D]
    let colorLinea: UIColor
    let colorSimbolo: UIColor
    let paraderos: [ParaderoGTFS]
    let nombreInicio: String
    var margenes: UIEdgeInsets
    var ubicacionAutorizada: Bool
    var reducirMovimiento: Bool
    /// Cambia este valor para re-encuadrar el mapa al recorrido completo.
    var ajustarTrigger: Int = 0
    var ubicacionTrigger: Int = 0
    var alCambiarSeguimiento: (Bool) -> Void
    var alFallarUbicacion: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsUserLocation = ubicacionAutorizada
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.layoutMargins = margenes

        // Trazo del recorrido
        if coordenadas.count >= 2 {
            let polyline = MKPolyline(coordinates: coordenadas, count: coordenadas.count)
            mapView.addOverlay(polyline)
            context.coordinator.encuadrar(mapView, polyline: polyline, animated: false)
        }

        // Paraderos (decimados para no saturar; inicio y fin siempre)
        let visibles = Self.paraderosVisibles(paraderos)
        let terminalesCercanos = Self.terminalesCercanos(visibles)
        for (i, p) in visibles.enumerated() {
            mapView.addAnnotation(ParaderoExploraAnnotation(
                coordinate: p.coordinate,
                nombre: p.nombreVisible,
                esInicio: i == 0,
                // En recorridos circulares el marcador final no tapa el inicio.
                esFin: i == visibles.count - 1 && i > 0 && !terminalesCercanos
            ))
        }
        // Algunos feeds traen geometría sin paraderos. Su primer punto sigue
        // identificando el inicio; no se inventa una ubicación de transporte.
        if visibles.isEmpty, let inicio = coordenadas.first {
            mapView.addAnnotation(ParaderoExploraAnnotation(
                coordinate: inicio, nombre: nombreInicio, esInicio: true
            ))
        }

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self
        let cambiaronMargenes = mapView.layoutMargins != margenes
        mapView.layoutMargins = margenes
        mapView.showsUserLocation = ubicacionAutorizada
        if !ubicacionAutorizada {
            mapView.setUserTrackingMode(.none, animated: false)
        }
        if context.coordinator.ultimoAjuste != ajustarTrigger {
            context.coordinator.ultimoAjuste = ajustarTrigger
            context.coordinator.muestraRecorrido = true
            mapView.setUserTrackingMode(.none, animated: false)
            if coordenadas.count >= 2 {
                let polyline = MKPolyline(coordinates: coordenadas, count: coordenadas.count)
                context.coordinator.encuadrar(mapView, polyline: polyline, animated: !reducirMovimiento)
            }
        } else if cambiaronMargenes, context.coordinator.muestraRecorrido, coordenadas.count >= 2 {
            let polyline = MKPolyline(coordinates: coordenadas, count: coordenadas.count)
            context.coordinator.encuadrar(mapView, polyline: polyline, animated: false)
        }
        if context.coordinator.ultimaUbicacion != ubicacionTrigger {
            context.coordinator.ultimaUbicacion = ubicacionTrigger
            guard ubicacionAutorizada else { return }
            context.coordinator.muestraRecorrido = false
            mapView.setUserTrackingMode(.follow, animated: !reducirMovimiento)
        }
    }

    static func dismantleUIView(_ mapView: MKMapView, coordinator: Coordinator) {
        mapView.delegate = nil
        mapView.setUserTrackingMode(.none, animated: false)
        mapView.showsUserLocation = false
    }

    private static func terminalesCercanos(_ paraderos: [ParaderoGTFS]) -> Bool {
        guard let primero = paraderos.first, let ultimo = paraderos.last else { return false }
        return CLLocation(latitude: primero.lat, longitude: primero.lon)
            .distance(from: CLLocation(latitude: ultimo.lat, longitude: ultimo.lon)) < 40
    }

    /// Máximo ~70 paraderos en el mapa para que sea legible.
    static func paraderosVisibles(_ paraderos: [ParaderoGTFS]) -> [ParaderoGTFS] {
        guard paraderos.count > 70 else { return paraderos }
        let paso = Double(paraderos.count) / 70.0
        var visibles = (0..<70).map { paraderos[min(Int(Double($0) * paso), paraderos.count - 1)] }
        if let primero = paraderos.first, visibles.first?.id != primero.id {
            visibles.insert(primero, at: 0)
        }
        if let ultimo = paraderos.last, visibles.last?.id != ultimo.id {
            visibles.append(ultimo)
        }
        return visibles
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapaExploradorRepresentable
        var ultimoAjuste: Int = 0
        var ultimaUbicacion: Int = 0
        var muestraRecorrido = true

        init(_ parent: MapaExploradorRepresentable) {
            self.parent = parent
        }

        func encuadrar(_ mapView: MKMapView, polyline: MKPolyline, animated: Bool) {
            mapView.setVisibleMapRect(
                polyline.boundingMapRect,
                edgePadding: parent.margenes,
                animated: animated
            )
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            let gestos = mapView.gestureRecognizers ?? []
            let gestosInternos = mapView.subviews.flatMap { $0.gestureRecognizers ?? [] }
            if (gestos + gestosInternos).contains(where: { $0.state == .began || $0.state == .changed }) {
                muestraRecorrido = false
            }
        }

        func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
            let notificar = parent.alCambiarSeguimiento
            DispatchQueue.main.async { notificar(mode != .none) }
        }

        func mapView(_ mapView: MKMapView, didFailToLocateUserWithError error: Error) {
            guard mapView.userTrackingMode != .none else { return }
            mapView.setUserTrackingMode(.none, animated: false)
            let notificar = parent.alFallarUbicacion
            DispatchQueue.main.async { notificar() }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = parent.colorLinea
                renderer.lineWidth = 5
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            guard let paradero = annotation as? ParaderoExploraAnnotation else { return nil }

            // Inicio / fin con marcador grande
            if paradero.esInicio || paradero.esFin {
                let id = paradero.esInicio ? "inicio" : "fin"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id)
                            as? MKMarkerAnnotationView)
                            ?? MKMarkerAnnotationView(annotation: nil, reuseIdentifier: id)
                view.annotation = paradero
                view.markerTintColor = paradero.esInicio ? parent.colorLinea : .systemRed
                view.glyphTintColor = paradero.esInicio ? parent.colorSimbolo : .white
                view.glyphImage = UIImage(systemName: paradero.esInicio ? "bus.fill" : "flag.fill")
                view.titleVisibility = .visible
                view.subtitleVisibility = .hidden
                view.canShowCallout = true
                view.displayPriority = paradero.esInicio ? .required : .defaultHigh
                view.zPriority = paradero.esInicio ? .max : .defaultUnselected
                view.selectedZPriority = .max
                view.animatesWhenAdded = false
                view.isAccessibilityElement = true
                view.accessibilityLabel = (paradero.esInicio ? L.t("Paradero inicial: ", "First stop: ") : L.t("Paradero final: ", "Last stop: ")) + paradero.nombre
                return view
            }

            // Paraderos intermedios: punto pequeño
            let id = "paradero"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                        ?? PuntoParaderoExploradorView(annotation: nil, reuseIdentifier: id)
            view.annotation = paradero
            let config = UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
            view.image = UIImage(systemName: "circle.fill", withConfiguration: config)?
                .withTintColor(.black, renderingMode: .alwaysOriginal)
            view.layer.shadowColor = UIColor.white.cgColor
            view.layer.shadowOpacity = 1
            view.layer.shadowRadius = 1
            view.layer.shadowOffset = .zero
            view.canShowCallout = true
            view.displayPriority = .defaultLow
            view.isAccessibilityElement = true
            view.accessibilityLabel = L.t("Paradero: ", "Stop: ") + paradero.nombre
            return view
        }
    }
}

// MARK: - Vista
private struct AlturaExploradorKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, nueva in nueva })
    }
}

struct ExploradorRutaView: View {
    let ruta: RutaOpcion
    let locationService: LocationServiceProtocol

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.self) private var entorno
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reducirMovimiento
    @Environment(\.scenePhase) private var scenePhase
    @State private var ajustarTrigger = 0
    @State private var ubicacionTrigger = 0
    @State private var solicitudUbicacion = 0
    @State private var solicitandoUbicacion = false
    @State private var siguiendoUsuario = false
    @State private var ubicacionAutorizada = false
    @State private var mostrarErrorUbicacion = false
    @State private var mostrarListaParaderos = false
    @State private var alturas: [String: CGFloat] = [:]

    /// Trazado para DIBUJAR, decimado.
    ///
    /// Esta pantalla permite pan y zoom libres, así que MapKit re-renderiza el
    /// overlay en cada gesto: con 500 puntos el resultado se ve igual que con
    /// 300 y cuesta menos. `ruta.shape` conserva el trazado completo para el
    /// matching y las medidas.
    private var trazado: [CLLocationCoordinate2D] {
        PolylineMatching.decimate(ruta.shape, maxPoints: 300)
    }

    private var identificacion: (codigo: String, letra: String) {
        GTFSNombreParser.identificacionTransporte(linea: ruta.linea, variante: ruta.variante)
    }

    private var colorTextoLetra: Color {
        let color = ruta.colorLinea.resolve(in: entorno)
        let luminancia = 0.2126 * color.linearRed + 0.7152 * color.linearGreen + 0.0722 * color.linearBlue
        return (luminancia + 0.05) / 0.05 >= 1.05 / (luminancia + 0.05) ? .black : .white
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MapaExploradorRepresentable(
                    coordenadas: trazado,
                    colorLinea: UIColor(ruta.colorLinea),
                    colorSimbolo: UIColor(colorTextoLetra),
                    paraderos: ruta.paraderos,
                    nombreInicio: ruta.paradaInicioVisible,
                    margenes: UIEdgeInsets(
                        top: geometry.safeAreaInsets.top + (alturas["cabecera"] ?? 76) + 24,
                        left: 40,
                        bottom: geometry.safeAreaInsets.bottom + (alturas["panel"] ?? 240) + 28,
                        right: 76
                    ),
                    ubicacionAutorizada: ubicacionAutorizada,
                    reducirMovimiento: reducirMovimiento,
                    ajustarTrigger: ajustarTrigger,
                    ubicacionTrigger: ubicacionTrigger,
                    alCambiarSeguimiento: { siguiendoUsuario = $0 },
                    alFallarUbicacion: { mostrarErrorUbicacion = true }
                )
                .ignoresSafeArea()

                VStack(spacing: 12) {
                    cabecera
                        .background(medirAltura("cabecera"))
                    Spacer(minLength: 0)
                    controlesMapa
                    ViewThatFits(in: .vertical) {
                        leyenda
                        ScrollView { leyenda }
                            .scrollBounceBehavior(.basedOnSize)
                    }
                    .frame(maxHeight: geometry.size.height * 0.46)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .background(medirAltura("panel"))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onPreferenceChange(AlturaExploradorKey.self) { alturas = $0 }
        }
        .accessibilityAction(.escape) { dismiss() }
        .onReceive(locationService.authorizationPublisher) { estado in
            ubicacionAutorizada = estado.isAuthorized
            if !estado.isAuthorized { siguiendoUsuario = false }
        }
        .task(id: solicitudUbicacion) {
            guard solicitandoUbicacion else { return }
            let solicitud = solicitudUbicacion
            let permiso = await locationService.requestPermission()
            guard !Task.isCancelled, solicitud == solicitudUbicacion else { return }
            solicitandoUbicacion = false
            ubicacionAutorizada = permiso.isAuthorized
            if permiso.isAuthorized {
                ubicacionTrigger += 1
            } else {
                mostrarErrorUbicacion = true
            }
        }
        .onChange(of: scenePhase) { _, fase in
            if fase == .background { cancelarSolicitudUbicacion() }
        }
        .alert(L.t("Tu ubicación", "Your location"), isPresented: $mostrarErrorUbicacion) {
            if locationService.authorizationStatus == .denied {
                Button(L.t("Abrir Ajustes", "Open Settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            Button(L.t("Aceptar", "OK"), role: .cancel) {}
        } message: {
            Text(mensajeErrorUbicacion)
        }
        .sheet(isPresented: $mostrarListaParaderos) {
            NavigationStack {
                List(Array(ruta.paraderos.enumerated()), id: \.offset) { indice, paradero in
                    VStack(alignment: .leading, spacing: 4) {
                        if indice == 0 {
                            Label(L.t("Inicio del recorrido", "Route start"), systemImage: "bus.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(paradero.nombreVisible)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(L.f("Paradero {0}: ", "Stop {0}: ", ["\(indice + 1)"]) + paradero.nombreVisible
                                        + (indice == 0 ? L.t(". Inicio del recorrido", ". Route start") : ""))
                }
                .navigationTitle(L.t("Paraderos de ", "Stops for ") + ruta.linea)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L.t("Cerrar", "Close")) { mostrarListaParaderos = false }
                    }
                }
            }
            .seguirTemaForzado()
        }
    }

    private var cabecera: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                cancelarSolicitudUbicacion()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.onSurface)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Cerrar recorrido", "Close route"))

            HStack(spacing: 10) {
                if !identificacion.letra.isEmpty {
                    Text(identificacion.letra)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(colorTextoLetra)
                        .padding(.horizontal, 10)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(ruta.colorLinea, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.t("Línea ", "Line ") + identificacion.codigo)
                        .font(.headline)
                        .foregroundStyle(Color.onSurface)
                    Text(ruta.empresa)
                        .font(.subheadline)
                        .foregroundStyle(Color.onSurfaceVariant)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L.t("Línea ", "Line ") + ruta.lineaConLetra + ". " + ruta.empresa)
        }
    }

    private var controlesMapa: some View {
        HStack {
            Spacer()
            VStack(spacing: 0) {
                Button {
                    solicitandoUbicacion = true
                    solicitudUbicacion += 1
                } label: {
                    Image(systemName: siguiendoUsuario ? "location.fill" : "location")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.onSurface)
                        .frame(minWidth: 48, minHeight: 48)
                        .overlay {
                            if solicitandoUbicacion {
                                ProgressView()
                                    .padding(10)
                                    .background(.regularMaterial, in: Circle())
                            }
                        }
                }
                .disabled(solicitandoUbicacion)
                .accessibilityLabel(L.t("Ir a mi ubicación", "Go to my location"))
                .accessibilityValue(solicitandoUbicacion ? L.t("Buscando ubicación", "Finding location")
                                    : siguiendoUsuario ? L.t("Siguiendo tu ubicación", "Following your location") : "")

                Divider().frame(width: 28)

                Button {
                    cancelarSolicitudUbicacion()
                    ajustarTrigger += 1
                } label: {
                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.onSurface)
                        .frame(minWidth: 48, minHeight: 48)
                }
                .accessibilityLabel(L.t("Ver recorrido completo", "Show entire route"))
            }
            .buttonStyle(.plain)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    // MARK: - Leyenda con datos del feed
    private var leyenda: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    tituloRecorrido
                    Spacer(minLength: 12)
                    frecuencia
                }
                VStack(alignment: .leading, spacing: 6) {
                    tituloRecorrido
                    frecuencia
                }
            }

            Text(ruta.recorridoLocalizado)
                .font(.subheadline)
                .foregroundStyle(Color.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading),
                                     count: dynamicTypeSize.isAccessibilitySize ? 2 : 4),
                      alignment: .leading, spacing: 16) {
                datoLeyenda(icono: "clock", valor: ruta.tiempoTexto, etiqueta: L.t("Viaje", "Trip"))
                datoLeyenda(icono: "creditcard", valor: ruta.costo, etiqueta: L.t("Tarifa", "Fare"))
                datoLeyenda(icono: "mappin.and.ellipse", valor: "\(ruta.numParaderos)", etiqueta: L.t("Paraderos", "Stops"))
                datoLeyenda(icono: "point.topleft.down.curvedto.point.bottomright.up",
                            valor: FormatoNumero.decimal(ruta.distanciaKm) + " km", etiqueta: L.t("Longitud", "Length"))
            }

            Divider()

            Button { mostrarListaParaderos = true } label: {
                HStack(spacing: 10) {
                    Label(L.t("Ver lista de paraderos", "View stop list"), systemImage: "list.bullet")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.onSurfaceVariant)
                        .accessibilityHidden(true)
                }
                .font(.body)
                .foregroundStyle(Color.onSurface)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }

    private var tituloRecorrido: some View {
        Text(L.t("Recorrido", "Route"))
            .font(.headline)
            .foregroundStyle(Color.onSurface)
    }

    private var frecuencia: some View {
        Text(ruta.frecuenciaTexto)
            .font(.subheadline)
            .foregroundStyle(Color.onSurfaceVariant)
            .fixedSize()
    }

    private func datoLeyenda(icono: String, valor: String, etiqueta: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icono)
                .font(.subheadline)
                .foregroundStyle(Color.onSurfaceVariant)
                .accessibilityHidden(true)
            Text(valor)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.onSurface)
            Text(etiqueta)
                .font(.caption)
                .foregroundStyle(Color.onSurfaceVariant)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(etiqueta + ": " + valor)
    }

    private func medirAltura(_ clave: String) -> some View {
        GeometryReader { geometry in
            Color.clear.preference(key: AlturaExploradorKey.self, value: [clave: geometry.size.height])
        }
    }

    private func cancelarSolicitudUbicacion() {
        solicitandoUbicacion = false
        solicitudUbicacion += 1
    }

    private var mensajeErrorUbicacion: String {
        switch locationService.authorizationStatus {
        case .denied:
            return L.t("Activa la ubicación para RutaUTP en Ajustes para centrar el mapa en tu posición.",
                       "Enable location for RutaUTP in Settings to center the map on your position.")
        case .restricted:
            return L.t("Este dispositivo restringe el acceso a la ubicación.",
                       "This device restricts location access.")
        default:
            return L.t("No pudimos obtener tu ubicación. Vuelve a intentarlo.",
                       "Couldn't get your location. Try again.")
        }
    }
}

#Preview {
    ExploradorRutaView(ruta: RutaOpcion(
        id: "17350695", linea: "C-01", empresa: "Nuevos Girasoles",
        recorrido: "Av. Miguel Grau (ramal circular)",
        frecuenciaMin: 4, duracionMin: 77, costo: "S/ 2.50",
        numParaderos: 247, distanciaKm: 21.3, colorLinea: Color(hex: "#00CC00"),
        shape: [], paraderos: [],
        paradaInicio: "Av. Miguel Grau", paradaFin: "Av. Miguel Grau", variante: "B"
    ), locationService: LocationService())
}
