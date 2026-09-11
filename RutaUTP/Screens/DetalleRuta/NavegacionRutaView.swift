//
//  NavegacionRutaView.swift
//  RutaUTP
//
//  Navegación ACTIVA sobre el recorrido real de la ruta (shape GTFS):
//   - GPS real del usuario proyectado sobre la polyline (PolylineMatching)
//   - Progreso del viaje (0...1), próximo paradero y paraderos restantes
//   - Minutos y metros restantes proporcionales al avance
//   - Aviso "baja aquí" al acercarse al final del recorrido
//   - Modo demo: simula el viaje completo a lo largo del shape (para
//     probar en simulador o sin moverse del sitio)
//
//  Lo que NO hay (aún): GPS de las unidades — las posiciones del bus son
//  del feed estático, por eso navegamos siguiendo al USUARIO en la ruta.
//

import SwiftUI
import MapKit
import CoreLocation

// MARK: - ViewModel
@MainActor
final class NavegacionRutaViewModel: ObservableObject {

    enum Estado: Equatable {
        case esperandoGPS
        case sinRecorrido
        case sinPermiso
        case enRuta
        case fueraDeRuta(metros: Double)
        case cercaDestino
        case finalizado
    }

    // Publicados para la UI
    @Published private(set) var estado: Estado = .esperandoGPS
    @Published private(set) var progreso: Double = 0
    @Published private(set) var distanciaRestanteM: Double = 0
    @Published private(set) var paraderoSiguiente: ParaderoGTFS?
    @Published private(set) var paraderosRestantes: Int = 0
    @Published private(set) var posicion: CLLocationCoordinate2D?
    @Published private(set) var heading: Double = 0
    @Published private(set) var paraderoCercano: ParaderoGTFS?
    @Published private(set) var distanciaParaderoM: Double?
    @Published private(set) var haEntradoEnRuta = false
    @Published var modoDemo: Bool = false {
        didSet {
            guard modoDemo != oldValue else { return }
            reiniciarProgreso()
            if modoDemo { iniciarDemo() } else { detenerDemo(); iniciar() }
        }
    }

    let ruta: RutaOpcion
    let shape: [CLLocationCoordinate2D]          // decimada para matching
    let distanciaTotalM: Double

    private let locationService: LocationServiceProtocol
    private var locationTask: Task<Void, Never>?
    private var demoTimer: Timer?
    private var demoProgreso: Double = 0
    private var fraccionesParaderos: [(paradero: ParaderoGTFS, fraccion: Double)] = []
    private var distanciasAcumuladas: [Double] = []

    init(ruta: RutaOpcion, locationService: LocationServiceProtocol = LocationService()) {
        self.ruta = ruta
        self.locationService = locationService
        let decimada = PolylineMatching.decimate(ruta.shape, maxPoints: 240)
        self.shape = decimada.count >= 2 ? decimada : ruta.shape
        self.distanciaTotalM = PolylineMatching.totalLengthMeters(self.shape)

        precomputarParaderos()
        self.paraderosRestantes = fraccionesParaderos.count
        self.paraderoSiguiente = fraccionesParaderos.first?.paradero
        self.distanciaRestanteM = distanciaTotalM
    }

    /// Proyección de cada paradero sobre el shape (fracción 0...1), una vez.
    private func precomputarParaderos() {
        distanciasAcumuladas = [0]
        guard shape.count >= 2 else { return }
        for i in 1..<shape.count {
            distanciasAcumuladas.append(
                distanciasAcumuladas[i - 1] + PolylineMatching.distanceMeters(shape[i - 1], shape[i])
            )
        }
        fraccionesParaderos = ruta.paraderos.compactMap { paradero in
            guard let m = PolylineMatching.match(point: paradero.coordinate,
                                                 on: shape, thresholdMeters: 80) else { return nil }
            return (paradero, m.progressFraction)
        }
        .sorted { $0.fraccion < $1.fraccion }
    }

    // MARK: - Ciclo de vida
    func iniciar() {
        locationTask?.cancel()
        guard shape.count >= 2, distanciaTotalM > 0 else {
            estado = .sinRecorrido
            return
        }
        estado = .esperandoGPS
        locationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let status = await self.locationService.requestPermission()
            guard !Task.isCancelled else { return }
            if status.isDenied {
                self.estado = .sinPermiso
                return
            }
            if status.isAuthorized {
                self.locationService.startUpdating()
                for await location in self.locationService.currentLocation() {
                    guard !Task.isCancelled else { break }
                    if self.modoDemo { continue }   // el demo toma el control
                    guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 65,
                          abs(location.timestamp.timeIntervalSinceNow) < 30 else { continue }
                    self.procesar(coordenada: location.coordinate, rumbo: location.course)
                }
            }
        }
    }

    func terminar() {
        locationTask?.cancel()
        locationService.stopUpdating()
        detenerDemo()
    }

    // MARK: - Procesamiento de fixes
    private func procesar(coordenada: CLLocationCoordinate2D, rumbo: Double, progresoDemo: Double? = nil) {
        guard estado != .finalizado else { return }
        guard let match = PolylineMatching.match(point: coordenada, on: shape,
                                                 thresholdMeters: 60) else { return }

        posicion = coordenada
        heading = rumbo
        if let cercano = ruta.paraderos.min(by: {
            PolylineMatching.distanceMeters(coordenada, $0.coordinate) <
            PolylineMatching.distanceMeters(coordenada, $1.coordinate)
        }) {
            paraderoCercano = cercano
            distanciaParaderoM = PolylineMatching.distanceMeters(coordenada, cercano.coordinate)
        }
        // Una proyección lejana no representa avance ni llegada.
        guard match.isOnRoute else {
            estado = .fueraDeRuta(metros: match.distanceToRoute)
            return
        }
        haEntradoEnRuta = true

        // Anti-jitter: el progreso no retrocede por pequeños saltos de GPS;
        // sí se recalcula si el usuario "re-embarca" mucho más atrás.
        let nuevo = progresoDemo ?? match.progressFraction
        if nuevo >= progreso || (progreso - nuevo) > 0.03 {
            progreso = nuevo
        }

        distanciaRestanteM = max(0, distanciaTotalM * (1 - progreso))
        paraderosRestantes = fraccionesParaderos.filter { $0.fraccion > progreso + 0.001 }.count
        paraderoSiguiente = fraccionesParaderos
            .first { $0.fraccion > progreso + 0.001 }?.paradero
            ?? fraccionesParaderos.last?.paradero

        let distanciaFinal = shape.last.map {
            PolylineMatching.distanceMeters(coordenada, $0)
        } ?? .infinity
        if distanciaRestanteM <= 25 && distanciaFinal <= 35 {
            estado = .finalizado
            detenerDemo()
        } else if distanciaRestanteM < 180 {
            estado = .cercaDestino
        } else {
            estado = .enRuta
        }
    }

    var minutosRestantes: Int {
        estado == .finalizado ? 0 : max(1, Int(ceil(Double(ruta.duracionMin) * (1 - progreso))))
    }

    var distanciaRestanteTexto: String {
        distanciaRestanteM >= 1000
            ? String(format: "%.1f km", distanciaRestanteM / 1000)
            : "\(Int(distanciaRestanteM)) m"
    }

    var distanciaProximoParaderoTexto: String? {
        guard let proximo = fraccionesParaderos.first(where: { $0.fraccion > progreso + 0.001 }) else { return nil }
        let metros = max(0, (proximo.fraccion - progreso) * distanciaTotalM)
        return metros >= 1000 ? String(format: "%.1f km", metros / 1000) : "\(Int(metros)) m"
    }

    private func reiniciarProgreso() {
        progreso = 0
        posicion = nil
        haEntradoEnRuta = false
        distanciaRestanteM = distanciaTotalM
        paraderosRestantes = fraccionesParaderos.count
        paraderoSiguiente = fraccionesParaderos.first?.paradero
        paraderoCercano = nil
        distanciaParaderoM = nil
        estado = shape.count >= 2 ? .esperandoGPS : .sinRecorrido
    }

    // MARK: - Modo demo
    private func iniciarDemo() {
        detenerDemo()
        guard shape.count >= 2, distanciaTotalM > 0 else { return }
        demoProgreso = 0
        demoTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.demoProgreso = min(1.0, self.demoProgreso + 1.0 / 900.0)  // ~72 s todo el viaje
                let coord = self.coordenadaEnFraccion(self.demoProgreso)
                let siguiente = self.coordenadaEnFraccion(min(1.0, self.demoProgreso + 0.002))
                let rumbo = atan2(siguiente.longitude - coord.longitude,
                                  siguiente.latitude - coord.latitude) * 180 / .pi
                self.procesar(coordenada: coord, rumbo: rumbo, progresoDemo: self.demoProgreso)
            }
        }
    }

    private func detenerDemo() {
        demoTimer?.invalidate()
        demoTimer = nil
    }

    private func coordenadaEnFraccion(_ fraccion: Double) -> CLLocationCoordinate2D {
        guard shape.count >= 2 else { return ruta.shape.first ?? CLLocationCoordinate2D() }
        let objetivo = max(0, min(1, fraccion)) * (distanciasAcumuladas.last ?? 0)
        // Búsqueda binaria del segmento que contiene la distancia objetivo
        var bajo = 0, alto = distanciasAcumuladas.count - 1
        while bajo < alto - 1 {
            let medio = (bajo + alto) / 2
            if distanciasAcumuladas[medio] <= objetivo { bajo = medio } else { alto = medio }
        }
        let longitudSeg = distanciasAcumuladas[alto] - distanciasAcumuladas[bajo]
        let t = longitudSeg > 0 ? (objetivo - distanciasAcumuladas[bajo]) / longitudSeg : 0
        let a = shape[bajo], b = shape[alto]
        return CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * t,
            longitude: a.longitude + (b.longitude - a.longitude) * t
        )
    }
}

// MARK: - Mapa de navegación
private struct MapaNavegacionRepresentable: UIViewRepresentable {
    let shape: [CLLocationCoordinate2D]
    let paraderos: [ParaderoGTFS]
    let colorLinea: UIColor
    let posicion: CLLocationCoordinate2D?
    @Binding var seguir: Bool
    let modoDemo: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(color: colorLinea)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsUserLocation = !modoDemo
        mapView.userTrackingMode = .none
        mapView.isRotateEnabled = false

        if shape.count >= 2 {
            let polyline = MKPolyline(coordinates: shape, count: shape.count)
            mapView.addOverlay(polyline)
            mapView.setVisibleMapRect(polyline.boundingMapRect,
                                      edgePadding: UIEdgeInsets(top: 60, left: 30, bottom: 280, right: 30),
                                      animated: false)
        }

        // Solo paraderos destacados: siguiente no se sabe aquí (cambia),
        // marcamos inicio y fin.
        let visibles = MapaExploradorRepresentable.paraderosVisibles(paraderos)
        for (i, p) in visibles.enumerated() {
            mapView.addAnnotation(ParaderoExploraAnnotation(
                coordinate: p.coordinate, nombre: p.nombre,
                esInicio: i == 0, esFin: i == visibles.count - 1
            ))
        }
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onPan = { seguir = false }
        mapView.showsUserLocation = !modoDemo
        if modoDemo, let posicion {
            if !mapView.annotations.contains(where: { $0 === coordinator.demoPin }) {
                coordinator.demoPin.title = L.t("Tu posición · demo", "Your position · demo")
                mapView.addAnnotation(coordinator.demoPin)
            }
            coordinator.demoPin.coordinate = posicion
        } else {
            mapView.removeAnnotation(coordinator.demoPin)
        }
        if !seguir {
            if coordinator.wasFollowing, let overlay = mapView.overlays.first {
                mapView.setVisibleMapRect(overlay.boundingMapRect,
                    edgePadding: UIEdgeInsets(top: 110, left: 40, bottom: 360, right: 40), animated: true)
            }
            coordinator.wasFollowing = false
            return
        }
        let changedMode = !coordinator.wasFollowing
        coordinator.wasFollowing = true
        guard let posicion else { return }
        if !changedMode, let previous = coordinator.lastCenter,
           PolylineMatching.distanceMeters(previous, posicion) < 8 { return }
        coordinator.lastCenter = posicion
        let region = MKCoordinateRegion(center: posicion,
            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008))
        mapView.setRegion(region, animated: true)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        let color: UIColor
        let demoPin = MKPointAnnotation()
        var wasFollowing = true
        var lastCenter: CLLocationCoordinate2D?
        var onPan: (() -> Void)?

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            let gestures = mapView.subviews.flatMap { $0.gestureRecognizers ?? [] }
            if gestures.contains(where: { $0.state == .began || $0.state == .changed }) {
                // Evita que la siguiente actualización de GPS interrumpa la exploración.
                wasFollowing = false
                onPan?()
            }
        }

        init(color: UIColor) { self.color = color }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = color
                renderer.lineWidth = 6
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            if annotation === demoPin {
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: "demo") as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "demo")
                view.annotation = annotation
                view.markerTintColor = .systemBlue
                view.glyphImage = UIImage(systemName: "location.fill")
                view.displayPriority = .required
                return view
            }
            guard let paradero = annotation as? ParaderoExploraAnnotation else { return nil }
            if paradero.esFin {
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: "fin")
                            as? MKMarkerAnnotationView)
                            ?? MKMarkerAnnotationView(annotation: nil, reuseIdentifier: "fin")
                view.annotation = paradero
                view.markerTintColor = .systemRed
                view.glyphImage = UIImage(systemName: "flag.fill")
                view.glyphTintColor = .white
                view.titleVisibility = .visible
                return view
            }
            let id = "paradero"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKAnnotationView)
                        ?? MKAnnotationView(annotation: nil, reuseIdentifier: id)
            view.annotation = paradero
            let config = UIImage.SymbolConfiguration(pointSize: 8, weight: .bold)
            view.image = UIImage(systemName: "circle.fill", withConfiguration: config)?
                .withTintColor(.darkGray, renderingMode: .alwaysOriginal)
            view.displayPriority = .defaultLow
            return view
        }
    }
}

// MARK: - Vista
struct NavegacionRutaView: View {
    let ruta: RutaOpcion
    let onFinish: () -> Void

    @StateObject private var viewModel: NavegacionRutaViewModel
    @State private var seguir: Bool = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    init(ruta: RutaOpcion, onFinish: @escaping () -> Void) {
        self.ruta = ruta
        self.onFinish = onFinish
        _viewModel = StateObject(wrappedValue: NavegacionRutaViewModel(ruta: ruta))
    }

    var body: some View {
        ZStack {
            Color(hex: "#0a0a0a").ignoresSafeArea()

            MapaNavegacionRepresentable(
                shape: viewModel.shape,
                paraderos: ruta.paraderos,
                colorLinea: UIColor(ruta.colorLinea),
                posicion: viewModel.posicion,
                seguir: $seguir,
                modoDemo: viewModel.modoDemo
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                panelInferior
            }

            if viewModel.estado == .finalizado {
                alertaLlegada
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { viewModel.iniciar() }
        .onDisappear { viewModel.terminar() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !viewModel.modoDemo && viewModel.estado != .finalizado {
                viewModel.iniciar()
            }
        }
    }

    // MARK: - Top bar
    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.modoDemo ? L.t("SIMULACIÓN", "SIMULATION") : L.t("TU VIAJE", "YOUR TRIP"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .appTracking(AppTracking.wideLabel)
                Text("Línea \(ruta.linea) · \(ruta.empresa)")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer()

            Button {
                viewModel.modoDemo.toggle()
            } label: {
                Label(viewModel.modoDemo ? "Demo ON" : "Demo",
                      systemImage: viewModel.modoDemo ? "stop.fill" : "play.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(viewModel.modoDemo ? .black : .white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(viewModel.modoDemo ? Color(hex: "#8affc1") : Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Simular recorrido", "Simulate route"))
            .disabled(viewModel.shape.count < 2)

            Button {
                onFinish()
            } label: {
                Text("Finalizar")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.red))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            LinearGradient(colors: [Color(hex: "#0a0a0a").opacity(0.92), .clear],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: - Panel inferior
    private var panelInferior: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Instrucción principal según estado
            HStack(spacing: 12) {
                Image(systemName: iconoEstado)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(colorEstado)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12).fill(colorEstado.opacity(0.15)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(instruccion)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(subtitulo)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(3)
                }
                Spacer()
            }

            if viewModel.estado == .sinPermiso {
                Button(L.t("Abrir Ajustes", "Open Settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }

            HStack(spacing: 8) {
                Image(systemName: "flag.fill").foregroundStyle(ruta.colorLinea)
                Text(L.t("Hasta ", "To ") + ruta.paradaFin)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Text(ruta.costo).fontWeight(.semibold)
            }
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.8))

            // Barra de progreso del recorrido
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule()
                            .fill(ruta.colorLinea)
                            .frame(width: max(8, geo.size.width * viewModel.progreso))
                    }
                }
                .frame(height: 6)

                HStack {
                    Text(L.t("Avance de la línea · tiempos estimados", "Route progress · estimated times"))
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Text("\(Int(viewModel.progreso * 100))%")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(ruta.colorLinea)
                }
            }

            // Stats
            HStack(spacing: 0) {
                stat(icono: "clock.fill", valor: viewModel.posicion == nil || ruta.duracionMin <= 0 ? "—" : "~\(viewModel.minutosRestantes) min", etiqueta: L.t("Restante", "Remaining"))
                    .frame(maxWidth: .infinity)
                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 34)
                stat(icono: "point.topleft.down.curvedto.point.bottomright.up",
                     valor: viewModel.distanciaRestanteTexto, etiqueta: "Por recorrer")
                    .frame(maxWidth: .infinity)
                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 34)
                stat(icono: "mappin.and.ellipse",
                     valor: "\(viewModel.paraderosRestantes)", etiqueta: "Paraderos")
                    .frame(maxWidth: .infinity)
            }

            // Botón seguir/no seguir
            Button {
                seguir.toggle()
            } label: {
                Label(seguir ? L.t("Ver toda la ruta", "Show full route") : L.t("Seguir mi ubicación", "Follow my location"),
                      systemImage: seguir ? "arrow.up.left.and.arrow.down.right" : "location.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(hex: "#141414").opacity(0.96))
                .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: -4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func stat(icono: String, valor: String, etiqueta: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icono)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            Text(valor)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(.white)
            Text(etiqueta.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .appTracking(AppTracking.wideLabel)
        }
    }

    // MARK: - Estado → UI
    private var iconoEstado: String {
        switch viewModel.estado {
        case .sinRecorrido: return "map.fill"
        case .esperandoGPS:  return "antenna.radiowaves.left.and.right"
        case .sinPermiso:    return "location.slash.fill"
        case .enRuta:        return "bus.fill"
        case .fueraDeRuta:   return "exclamationmark.triangle.fill"
        case .cercaDestino:  return "bell.badge.fill"
        case .finalizado:    return "checkmark.circle.fill"
        }
    }

    private var colorEstado: Color {
        switch viewModel.estado {
        case .sinRecorrido: return .orange
        case .esperandoGPS:  return .white
        case .sinPermiso:    return .red
        case .enRuta:        return ruta.colorLinea
        case .fueraDeRuta:   return .orange
        case .cercaDestino:  return .yellow
        case .finalizado:    return .green
        }
    }

    private var instruccion: String {
        switch viewModel.estado {
        case .sinRecorrido:
            return L.t("Recorrido no disponible", "Route unavailable")
        case .esperandoGPS:
            return L.t("Buscando señal GPS…", "Finding GPS signal…")
        case .sinPermiso:
            return L.t("Activa la ubicación para navegar", "Enable location to navigate")
        case .enRuta:
            return viewModel.paraderoSiguiente != nil
                ? L.t("Próximo paradero", "Next stop")
                : L.t("Continúa por el recorrido", "Continue along the route")
        case .fueraDeRuta(let metros):
            return viewModel.haEntradoEnRuta
                ? L.t("Fuera del recorrido · \(Int(metros)) m", "Off route · \(Int(metros)) m")
                : L.t("Acércate a un paradero", "Head to a stop")
        case .cercaDestino:
            return L.t("Prepárate para bajar", "Get ready to get off")
        case .finalizado:
            return L.t("Llegaste al final de la línea", "You reached the end of the line")
        }
    }

    private var subtitulo: String {
        switch viewModel.estado {
        case .sinRecorrido:
            return L.t("Esta línea no tiene un trazado válido para navegar.", "This line has no valid route geometry.")
        case .esperandoGPS:
            return L.t("Usaremos tu ubicación para mostrar tu avance.", "Your location will show your progress.")
        case .sinPermiso:
            return L.t("Permite el acceso a tu ubicación en Ajustes.", "Allow location access in Settings.")
        case .enRuta:
            let nombre = viewModel.paraderoSiguiente?.nombre ?? ruta.paradaFin
            return nombre + (viewModel.distanciaProximoParaderoTexto.map { " · " + $0 } ?? "")
        case .fueraDeRuta:
            guard let paradero = viewModel.paraderoCercano, let metros = viewModel.distanciaParaderoM else {
                return L.t("Busca un paradero de la línea ", "Look for a stop on line ") + ruta.linea
            }
            let distancia = metros >= 1000 ? String(format: "%.1f km", metros / 1000) : "\(Int(metros)) m"
            return paradero.nombre + " · " + distancia + L.t(" en línea recta", " straight-line distance")
        case .cercaDestino, .finalizado:
            return ruta.paradaFin
        }
    }

    // MARK: - Alerta de llegada
    private var alertaLlegada: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
            Text("Fin del recorrido")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(.white)
            Text("Llegaste a \(ruta.paradaFin)")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            Button {
                onFinish()
            } label: {
                Text("Terminar")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(Color(hex: "#8affc1")))
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: 320)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(hex: "#141414"))
                .shadow(color: .black.opacity(0.5), radius: 24)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

#Preview {
    NavegacionRutaView(
        ruta: RutaOpcion(
            id: "17350695", linea: "C-01", empresa: "Nuevos Girasoles",
            recorrido: "Av. Miguel Grau (ramal circular)",
            frecuenciaMin: 4, duracionMin: 77, costo: "S/ 2.50",
            numParaderos: 247, distanciaKm: 21.3, colorLinea: Color(hex: "#00CC00"),
            shape: [], paraderos: [],
            paradaInicio: "Av. Miguel Grau", paradaFin: "Av. Miguel Grau"
        ),
        onFinish: {}
    )
}
