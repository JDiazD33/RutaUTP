// Tracking Demo: itinerarios directos de transporte público sobre GTFS.
// Separa caminata de subida, recorrido del micro y caminata final.
// La ubicación puede ser GPS o simulación; la flota es siempre demo hasta
// conectar un VehicleTrackingProviding real. No requiere un backend para el feed.

import Foundation
import Combine
import CoreLocation
import MapKit

@MainActor
final class RouteTrackingViewModel: ObservableObject {

    // MARK: - Destinos del demo (mismos chips fijos del Mapa)

    struct DestinoDemo: Identifiable, Equatable {
        let id: Int
        let label: String
        let icon: String
        let coordinate: CLLocationCoordinate2D

        static func == (lhs: DestinoDemo, rhs: DestinoDemo) -> Bool { lhs.id == rhs.id }
    }

    /// Propiedad CALCULADA, no almacenada: el label sale en el idioma activo
    /// en cada lectura. Antes era un `let` evaluado al crear el VM y dependía
    /// de que RootView reconstruyera el árbol al cambiar de idioma; al quitar
    /// ese `.id()`, un `let` habría quedado congelado en el idioma de arranque.
    /// Los tres puntos y sus claves señables viven en `DestinosFijos`,
    /// compartido con el Mapa: antes estaban escritos literales en los dos.
    var destinos: [DestinoDemo] {
        DestinosFijos.todos.map {
            DestinoDemo(id: $0.id, label: $0.label, icon: $0.icono,
                        coordinate: $0.coordinate)
        }
    }

    // MARK: - Estado de navegación (igual a NavegacionRutaView)

    enum Estado: Equatable {
        case esperandoGPS
        case sinPermiso
        case listo                    // GPS OK, sin viaje iniciado
        case enRuta
        case fueraDeRuta(metros: Double)
        case cercaDestino
        case finalizado
    }

    // MARK: - Salida expuesta a la vista

    @Published private(set) var estado: Estado = .esperandoGPS
    @Published private(set) var posicion: CLLocationCoordinate2D?
    /// Se incrementa en cada fix; la vista lo observa para seguir la cámara
    /// (CLLocationCoordinate2D no conforma Equatable para .onChange).
    @Published private(set) var posicionTick: Int = 0
    @Published private(set) var progreso: Double = 0
    @Published private(set) var distanciaRestanteM: Double = 0
    @Published private(set) var etaTotalSeg: TimeInterval?      // de la ruta calculada
    @Published private(set) var recalculando: Bool = false
    @Published private(set) var tripInProgress: Bool = false
    @Published private(set) var destinoSeleccionado: DestinoDemo? = nil
    @Published private(set) var errorMessage: String? = nil
    @Published var authStatus: CLAuthorizationStatus = .notDetermined

    /// Modo demo: simula el avance por la ruta calculada (ignora el GPS real).
    @Published var modoDemo: Bool = false {
        didSet { modoDemo ? iniciarDemoSimulado() : detenerDemoSimulado() }
    }

    // Vehículos en el mapa vía provider (badge DEMO / EN VIVO en la UI).
    @Published private(set) var vehiculos: [VehiclePosition] = []
    @Published private(set) var fuenteVehiculos: VehicleTrackingSource = .simulated

    /// Color de cada línea según el `route_color` del feed GTFS, en hex.
    ///
    /// La UI lo consulta por nombre de línea: los `VehiclePosition` solo traen
    /// la línea, no el route_id. Antes el demo pintaba los vehículos con un
    /// color derivado de un hash del nombre, así que la misma línea salía de
    /// un color en Rutas/Mapa y de otro aquí.
    ///
    /// Se guarda el hex y no un `Color` para que el ViewModel no dependa de
    /// SwiftUI: la vista lo resuelve con `Color.colorRuta(hex:)`, el mismo
    /// ajuste de presentación que usan las otras pantallas.
    @Published private(set) var coloresPorLinea: [String: String] = [:]

    // Sesión del viaje en curso (modelo de datos del módulo, listo para backend).
    @Published private(set) var sesion: TripSession?

    @Published private(set) var routePolyline: MKPolyline?
    /// Ruta dividida por el avance: tramo recorrido (tenue) y restante (vivo).
    @Published private(set) var rutaRecorrida: MKPolyline? = nil
    @Published private(set) var rutaRestante: MKPolyline? = nil
    /// True cuando MKDirections no respondió y la ruta es un trazo directo.
    @Published private(set) var rutaAproximada: Bool = false
    /// Línea REAL del feed GTFS usada para el viaje (nil = MapKit/respaldo).
    /// El shape del tramo y el ritmo de simulación salen de esta línea.
    @Published private(set) var rutaGTFS: RutaGTFS?
    /// True mientras corre el pipeline de ruteo (spinner del botón Iniciar).
    @Published private(set) var calculandoRuta: Bool = false
    /// Rumbo actual en grados (-1 desconocido): orienta la cámara y el marcador.
    @Published private(set) var rumbo: Double = -1
    /// Preferencias del modo demo que sobreviven a salir de la pantalla.
    ///
    /// El router propio destruye y recrea esta pantalla al cambiar de pestaña,
    /// y el ViewModel vive en un `@StateObject`: sin persistir, el radio volvía
    /// a 500 m y la velocidad a 1× cada vez que el usuario salía y volvía.
    enum Preferencia: String {
        case radio = "tracking.radioParadero"
        case velocidad = "tracking.velocidadDemo"

        /// Opciones compartidas por la validación y los controles de la vista.
        var valoresPermitidos: [Double] {
            switch self {
            case .radio: return [200, 500, 800]
            case .velocidad: return [1, 3, 10]
            }
        }

        var porDefecto: Double {
            switch self {
            case .radio: return 500
            case .velocidad: return 1
            }
        }
    }

    private static func leer(_ preferencia: Preferencia) -> Double {
        // No reescribe el original si está dañado. Solo admite valores finitos
        // presentes en el selector, antes de usarlos en cálculos o convertir a Int.
        guard let valor = UserDefaults.standard.object(forKey: preferencia.rawValue) as? Double,
              valor.isFinite, preferencia.valoresPermitidos.contains(valor) else {
            return preferencia.porDefecto
        }
        return valor
    }

    /// Multiplicador del modo demo (1× / 3× / 10×). Persistido.
    @Published var velocidadDemo: Double = RouteTrackingViewModel.leer(.velocidad) {
        didSet { UserDefaults.standard.set(velocidadDemo, forKey: Preferencia.velocidad.rawValue) }
    }
    /// Velocidad estimada por vehículo (m/s), calculada entre snapshots del
    /// provider para el popup en vivo.
    @Published private(set) var velocidadesVehiculos: [String: Double] = [:]

    /// Métricas del viaje terminado (las muestra la card de llegada).
    struct ResumenViaje: Equatable {
        let duracionS: TimeInterval
        let distanciaM: Double
        let puntos: Int
        let velocidadKmh: Double
    }
    @Published private(set) var resumen: ResumenViaje?

    /// Radio de búsqueda de paraderos, en metros. Persistido (ver `Preferencia`).
    @Published var radioParadero: Double = RouteTrackingViewModel.leer(.radio) {
        didSet { UserDefaults.standard.set(radioParadero, forKey: Preferencia.radio.rawValue) }
    }
    @Published private(set) var itinerary: TransitItinerary?
    @Published private(set) var nearestStop: ParaderoGTFS?
    @Published private(set) var nearestStopMeters: Double?
    @Published var buscandoDestino = false
    private var routeRevision = UUID()
    private var lastRecalculation = Date.distantPast
    private var allStops: [ParaderoGTFS] = []
    private var nearestAnchor: CLLocationCoordinate2D?

    enum JourneyLeg { case walkingToBoard, riding, walkingToDestination }
    var journeyLeg: JourneyLeg {
        guard let plan = itinerary else { return .walkingToBoard }
        let meters = progreso * distanciaTotalM
        if meters < plan.walkToBoardMeters { return .walkingToBoard }
        if meters < plan.walkToBoardMeters + plan.busMeters { return .riding }
        return .walkingToDestination
    }

    var remainingSeconds: Double {
        guard let plan = itinerary else { return (etaTotalSeg ?? 0) * (1 - progreso) }
        let traveled = progreso * distanciaTotalM
        let first = max(0, plan.walkToBoardMeters - traveled) / 1.4
        let bus = max(0, plan.busMeters - max(0, traveled - plan.walkToBoardMeters)) / plan.busSpeed
        let last = max(0, plan.walkToDestinationMeters - max(0, traveled - plan.walkToBoardMeters - plan.busMeters)) / 1.4
        return first + bus + last
    }

    func buscarDestino(_ text: String) async -> DestinoDemo? {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !buscandoDestino else { return nil }
        buscandoDestino = true
        defer { buscandoDestino = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query + ", Trujillo, Perú"
        request.region = MKCoordinateRegion(center: GTFSRepository.coordenadaUTP,
                                            span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3))
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let item = response.mapItems.first else {
                errorMessage = L.t("No encontramos ese lugar en Trujillo.", "No matching place found in Trujillo.")
                return nil
            }
            errorMessage = nil
            return DestinoDemo(id: 999, label: item.name ?? query, icon: "mappin.circle.fill",
                               coordinate: item.placemark.coordinate)
        } catch {
            errorMessage = L.t("No pudimos buscar ese destino. Comprueba tu conexión.",
                               "Could not search for that destination. Check your connection.")
            return nil
        }
    }

    private func refreshNearestStop(at coordinate: CLLocationCoordinate2D) {
        guard !allStops.isEmpty else { return }
        if let anchor = nearestAnchor, PolylineMatching.distanceMeters(anchor, coordinate) < 25 { return }
        if nearestAnchor == nil {
            (vehicleProvider as? SimulatedTrackingProvider)?.setCenter(lat: coordinate.latitude, lon: coordinate.longitude)
        }
        nearestAnchor = coordinate
        let nearest = allStops.map { ($0, PolylineMatching.distanceMeters(coordinate, $0.coordinate)) }
            .min { $0.1 < $1.1 }
        nearestStop = nearest?.0
        nearestStopMeters = nearest?.1
    }

    // MARK: - Dependencias

    private let locationService: LocationServiceProtocol
    private let routeService: RouteCalculationService
    private let vehicleProvider: VehicleTrackingProviding

    // Shape completo: conserva todas las esquinas de la calle para matching y simulación.
    private var polyCoords: [CLLocationCoordinate2D] = []
    private var distanciasAcumuladas: [Double] = []
    private var distanciaTotalM: Double = 0

    private var consecutiveOffRoute: Int = 0
    private var locationTask: Task<Void, Never>?
    private var vehiculoTask: Task<Void, Never>?
    private var demoTask: Task<Void, Never>?
    private var demoProgreso: Double = 0
    private var ultimoFraccionPolyline: Double = 0
    /// Ritmo real de simulación en m/s (de la línea GTFS o del ETA de MapKit).
    private var velocidadSimMs: Double = 6.0
    private var snapshotVehiculosAnterior: [String: (coord: CLLocationCoordinate2D, t: TimeInterval)] = [:]

    private var authCancellable: AnyCancellable?

    // MARK: - Init

    init(locationService: LocationServiceProtocol = LocationService(),
         routeService: RouteCalculationService = RouteCalculationService(),
         vehicleProvider: VehicleTrackingProviding = SimulatedTrackingProvider()) {
        self.locationService = locationService
        self.routeService = routeService
        self.vehicleProvider = vehicleProvider
        self.fuenteVehiculos = vehicleProvider.source

        authCancellable = locationService.authorizationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.authStatus = status
            }
    }

    deinit {
        locationTask?.cancel()
        vehiculoTask?.cancel()
        demoTask?.cancel()
        vehicleProvider.stop()
        locationService.stopUpdating()
    }

    // MARK: - Permisos y arranque

    func requestPermissionAndStart() async {
        let status = await locationService.requestPermission()
        guard !Task.isCancelled else { return }
        authStatus = status
        if status.isAuthorized {
            startObservingLocation()
            locationService.startUpdating()
        } else {
            estado = .sinPermiso
            errorMessage = L.t("Permiso de ubicación denegado. Actívalo en Ajustes para usar el tracking.",
                               "Location permission denied. Enable it in Settings to use tracking.")
        }
        iniciarVehiculos()
        let feed = await GTFSRepository.shared.rutas()
        guard !Task.isCancelled else { return }
        var seen = Set<String>()
        allStops = feed.flatMap(\.paraderos).filter { seen.insert($0.id).inserted }
        // Varias rutas pueden compartir `linea`: en este feed 12 de los 90
        // nombres son variantes de la misma línea. Como `VehiclePosition` solo
        // trae la línea y no el route_id, el mapa no puede distinguirlas, así
        // que se queda un color por línea. Se resuelve de forma DETERMINISTA
        // (la ruta de id menor) para que no dependa del orden en que llegue el
        // feed, que va ordenado por cercanía al campus.
        coloresPorLinea = feed
            .sorted { $0.id < $1.id }
            .reduce(into: [String: String]()) { mapa, ruta in
                if mapa[ruta.linea] == nil { mapa[ruta.linea] = ruta.colorHex }
            }
        if let posicion { refreshNearestStop(at: posicion) }
    }

    private func startObservingLocation() {
        locationTask?.cancel()
        locationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await location in self.locationService.currentLocation() {
                guard !Task.isCancelled else { break }
                if self.modoDemo { continue }   // el demo simulado toma el control
                self.procesar(coordenada: location.coordinate, rumbo: location.course)
            }
        }
    }

    // MARK: - Procesamiento de fixes (mismos umbrales de NavegacionRutaView)

    private func procesar(coordenada: CLLocationCoordinate2D, rumbo: Double) {
        posicion = coordenada
        refreshNearestStop(at: coordenada)
        posicionTick += 1
        self.rumbo = rumbo

        // Sin viaje en curso: GPS listo, a la espera de destino.
        guard tripInProgress, estado != .finalizado, !polyCoords.isEmpty else {
            if estado == .esperandoGPS || estado == .sinPermiso { estado = .listo }
            return
        }

        guard let match = PolylineMatching.match(point: coordenada, on: polyCoords,
                                                 thresholdMeters: 60) else { return }

        // Anti-jitter: el progreso no retrocede por saltos pequeños de GPS.
        let nuevo = match.progressFraction
        if nuevo >= progreso || (progreso - nuevo) > 0.03 {
            progreso = nuevo
        }

        distanciaRestanteM = max(0, distanciaTotalM * (1 - progreso))
        refrescarPolylinesProgreso()

        // Recalculo por desvío sostenido (misma política del módulo).
        if match.isOnRoute {
            consecutiveOffRoute = 0
        } else {
            consecutiveOffRoute += 1
        }
        if PolylineMatching.shouldRecalculate(lastMatch: match,
                                              consecutiveOffRouteCount: consecutiveOffRoute,
                                              thresholdCount: 3),
           !recalculando {
            Task { await recalcular(desde: coordenada) }
        }

        let destinationDistance = destinoSeleccionado.map {
            PolylineMatching.distanceMeters(coordenada, $0.coordinate)
        } ?? .infinity
        if match.isOnRoute && distanciaRestanteM < 20 && destinationDistance < 25 {
            estado = .finalizado
        } else if match.isOnRoute && distanciaRestanteM < 120 {
            estado = .cercaDestino
        } else if !match.isOnRoute {
            estado = .fueraDeRuta(metros: match.distanceToRoute)
        } else {
            estado = .enRuta
        }

        registrarPunto(coordenada, rumbo: rumbo)

        // Llegó: cerrar la sesión (una sola vez) y frenar la simulación demo
        // para no seguir tick-eando sobre el destino.
        if estado == .finalizado {
            if sesion?.estado != .completed {
                finalizarSesion(estado: .completed)
            }
            if modoDemo { modoDemo = false }
        }

    }

    // MARK: - Inicio de viaje

    func iniciar(destino: DestinoDemo) async {
        guard !calculandoRuta else { return }
        guard authStatus.isAuthorized else {
            errorMessage = L.t("Sin permiso de ubicación. Concédelo en Ajustes.",
                               "No location permission. Grant it in Settings.")
            return
        }
        guard let origen = posicion else {
            errorMessage = L.t("Aún no tenemos tu ubicación. Espera unos segundos.",
                               "We don't have your location yet. Wait a few seconds.")
            return
        }

        errorMessage = nil
        destinoSeleccionado = destino
        tripInProgress = false
        itinerary = nil
        routePolyline = nil
        progreso = 0
        consecutiveOffRoute = 0
        resumen = nil

        calculandoRuta = true
        defer { calculandoRuta = false }
        await calcularRuta(desde: origen, hacia: destino.coordinate)

        if let plan = itinerary, routePolyline != nil {
            sesion = TripSession(linea: plan.route.linea, empresa: plan.route.empresa,
                origen: TrackingPoint(lat: origen.latitude, lon: origen.longitude),
                destino: TrackingPoint(lat: destino.coordinate.latitude, lon: destino.coordinate.longitude),
                estado: .inProgress, startedAt: Date().timeIntervalSince1970)
            tripInProgress = true
            estado = .enRuta
            distanciaRestanteM = distanciaTotalM
        } else {
            tripInProgress = false
            destinoSeleccionado = nil
            estado = .listo
        }
    }

    /// Recalcular desde la posición actual hacia el destino guardado.
    private func recalcular(desde origen: CLLocationCoordinate2D) async {
        guard let destino = destinoSeleccionado else { return }
        guard !recalculando, !calculandoRuta,
              Date().timeIntervalSince(lastRecalculation) >= 20 else { return }
        lastRecalculation = Date()
        recalculando = true
        sesion?.estado = .recalculating

        await calcularRuta(desde: origen, hacia: destino.coordinate)

        recalculando = false
        consecutiveOffRoute = 0
        if sesion?.estado == .recalculating { sesion?.estado = .inProgress }
    }

    /// Solo itinerarios de transporte del feed: nunca sustituye un micro por una ruta de auto.
    private func calcularRuta(desde origen: CLLocationCoordinate2D,
                              hacia destino: CLLocationCoordinate2D) async {
        let revision = UUID()
        routeRevision = revision
        let radio = radioParadero
        let feed = await GTFSRepository.shared.rutas()
        guard revision == routeRevision, !Task.isCancelled else { return }
        let candidates = await TransitPlanner.shared.candidates(in: feed, origin: origen,
                                                     destination: destino, radius: radio)
        var selected: TransitItinerary?
        // Limita peticiones a MapKit; cada candidato conserva paraderos y sentido GTFS.
        for candidate in candidates.prefix(4) {
            guard !Task.isCancelled, revision == routeRevision else { return }
            let resolved = await candidate.withWalkingDirections(using: routeService)
            guard !Task.isCancelled, revision == routeRevision else { return }
            if resolved.walkToBoardMeters <= radio && resolved.walkToDestinationMeters <= radio {
                selected = resolved
                break
            }
        }
        guard revision == routeRevision, !Task.isCancelled else { return }
        guard let plan = selected else {
            let sugerencia = radio < 800
                ? L.t("Prueba un radio mayor u otro destino.", "Try a larger radius or another destination.")
                : L.t("Prueba otro destino.", "Try another destination.")
            errorMessage = L.t("No encontramos una línea directa con paraderos a menos de \(Int(radio)) m de ambos extremos. ",
                               "No direct line has stops within \(Int(radio)) m of both ends. ") + sugerencia
            return
        }
        errorMessage = nil
        itinerary = plan
        rutaGTFS = plan.route
        rutaAproximada = plan.walkingApproximate
        routePolyline = MKPolyline(coordinates: plan.coordinates, count: plan.coordinates.count)
        etaTotalSeg = plan.totalSeconds
        progreso = 0
        instalarShape(plan.coordinates)
        distanciaRestanteM = distanciaTotalM
        (vehicleProvider as? SimulatedTrackingProvider)?.follow(routeID: plan.route.id, near: plan.board.coordinate)
        sesion?.estado = .inProgress
    }

    private func instalarShape(_ coords: [CLLocationCoordinate2D]) {
        polyCoords = coords // conservar esquinas: no atravesar manzanas
        distanciaTotalM = PolylineMatching.totalLengthMeters(polyCoords)

        distanciasAcumuladas = [0]
        for i in 1..<polyCoords.count {
            distanciasAcumuladas.append(
                distanciasAcumuladas[i - 1] + PolylineMatching.distanceMeters(polyCoords[i - 1], polyCoords[i])
            )
        }
        demoProgreso = progreso
        ultimoFraccionPolyline = 0
        rutaRecorrida = nil
        rutaRestante = routePolyline
        // Ritmo real de simulación: distancia total / ETA de la ruta
        // (línea GTFS o MapKit). Es "a como vamos": micro urbano ≈ 20-25 km/h.
        if let eta = etaTotalSeg, eta > 10 {
            velocidadSimMs = max(1.2, distanciaTotalM / eta)
        } else {
            velocidadSimMs = 6.0
        }
    }

    /// Divide la polyline en tramo recorrido / restante según `progreso`.
    /// Se refresca cada ~0.5% de avance (o al 100%) para no reconstruir
    /// MKPolylines en cada tick del GPS/demo.
    private func refrescarPolylinesProgreso() {
        guard polyCoords.count >= 2,
              let total = distanciasAcumuladas.last, total > 0 else { return }
        guard progreso >= 0.999 || abs(progreso - ultimoFraccionPolyline) >= 0.005 else { return }
        ultimoFraccionPolyline = progreso

        let objetivo = total * min(max(progreso, 0), 1)
        var bajo = 0, alto = distanciasAcumuladas.count - 1
        while bajo < alto - 1 {
            let medio = (bajo + alto) / 2
            if distanciasAcumuladas[medio] <= objetivo { bajo = medio } else { alto = medio }
        }
        let longSeg = distanciasAcumuladas[alto] - distanciasAcumuladas[bajo]
        let t = longSeg > 0 ? (objetivo - distanciasAcumuladas[bajo]) / longSeg : 0
        let a = polyCoords[bajo], b = polyCoords[alto]
        let punto = CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                           longitude: a.longitude + (b.longitude - a.longitude) * t)

        var recorridas = Array(polyCoords[0...bajo])
        recorridas.append(punto)
        rutaRecorrida = recorridas.count >= 2
            ? MKPolyline(coordinates: recorridas, count: recorridas.count) : nil

        var restantes = [punto]
        restantes.append(contentsOf: polyCoords[alto...])
        rutaRestante = restantes.count >= 2
            ? MKPolyline(coordinates: restantes, count: restantes.count) : nil
    }

    // MARK: - Salidas formateadas (mismo estilo de NavegacionRutaView)

    var minutosRestantes: Int {
        guard etaTotalSeg != nil else { return 0 }
        return max(0, Int(ceil(remainingSeconds / 60)))
    }

    var distanciaRestanteTexto: String {
        distanciaRestanteM >= 1000
            ? String(format: "%.1f km", distanciaRestanteM / 1000)
            : "\(Int(distanciaRestanteM)) m"
    }

    /// Ritmo real de la ruta activa, para el caption del selector 1×/3×/10×.
    var velocidadSimKmh: Int {
        Int((velocidadSimMs * 3.6).rounded())
    }

    // MARK: - Modo demo (simulación de avance sobre la ruta calculada)

    private func iniciarDemoSimulado() {
        guard tripInProgress, polyCoords.count >= 2 else {
            modoDemo = false
            return
        }
        detenerDemoSimulado()
        demoProgreso = progreso
        // Una sola tarea que duerme entre pasos. Antes era un `Timer` que
        // creaba un `Task` nuevo por tick — doce por segundo — solo para saltar
        // al hilo principal.
        demoTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 80_000_000)
                guard !Task.isCancelled, let self else { return }
                guard let total = self.distanciasAcumuladas.last, total > 1 else { continue }
                // Avance por METROS reales: velocidad real de la ruta (m/s)
                // × multiplicador elegido. 1× = ritmo real de la línea.
                let speed = self.journeyLeg == .riding ? (self.itinerary?.busSpeed ?? 6) : 1.4
                let deltaMetros = speed * self.velocidadDemo * 0.08
                self.demoProgreso = min(1.0, self.demoProgreso + deltaMetros / total)
                let coord = self.coordenadaEnFraccion(self.demoProgreso)
                let siguiente = self.coordenadaEnFraccion(min(1.0, self.demoProgreso + 0.002))
                let degrees = atan2((siguiente.longitude - coord.longitude) * cos(coord.latitude * .pi / 180),
                                    siguiente.latitude - coord.latitude) * 180 / .pi
                let rumbo = (degrees + 360).truncatingRemainder(dividingBy: 360)
                self.procesar(coordenada: coord, rumbo: rumbo)
            }
        }
    }

    private func detenerDemoSimulado() {
        demoTask?.cancel()
        demoTask = nil
    }

    /// Coordenada sobre el shape a una fracción 0...1 (búsqueda binaria).
    private func coordenadaEnFraccion(_ fraccion: Double) -> CLLocationCoordinate2D {
        guard polyCoords.count >= 2,
              let ultima = distanciasAcumuladas.last else {
            return posicion ?? CLLocationCoordinate2D()
        }
        let objetivo = max(0, min(1, fraccion)) * ultima
        var bajo = 0, alto = distanciasAcumuladas.count - 1
        while bajo < alto - 1 {
            let medio = (bajo + alto) / 2
            if distanciasAcumuladas[medio] <= objetivo { bajo = medio } else { alto = medio }
        }
        let longitudSeg = distanciasAcumuladas[alto] - distanciasAcumuladas[bajo]
        let t = longitudSeg > 0 ? (objetivo - distanciasAcumuladas[bajo]) / longitudSeg : 0
        let a = polyCoords[bajo], b = polyCoords[alto]
        return CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * t,
            longitude: a.longitude + (b.longitude - a.longitude) * t
        )
    }

    // MARK: - Vehículos (VehicleTrackingProviding)

    private func iniciarVehiculos() {
        vehicleProvider.start()
        vehiculoTask?.cancel()
        vehiculoTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var ultimaActualizacion = 0.0
            for await positions in self.vehicleProvider.positions() {
                guard !Task.isCancelled else { break }
                // El provider ticka a 20 Hz: la UI se refresca a 4 Hz, de sobra
                // para que los buses se muevan fluidos sin re-renderizar el
                // mapa a cada instante.
                let ahora = Date().timeIntervalSince1970
                guard ahora - ultimaActualizacion >= 0.25 else { continue }
                ultimaActualizacion = ahora

                var velocidades = self.velocidadesVehiculos
                for vehiculo in positions {
                    if let previa = self.snapshotVehiculosAnterior[vehiculo.id] {
                        let dt = vehiculo.timestamp - previa.t
                        if dt > 0.2 {
                            velocidades[vehiculo.id] = max(0,
                                PolylineMatching.distanceMeters(previa.coord, vehiculo.coordinate) / dt)
                        }
                    }
                    self.snapshotVehiculosAnterior[vehiculo.id] = (vehiculo.coordinate, vehiculo.timestamp)
                }
                self.velocidadesVehiculos = velocidades
                self.vehiculos = positions
            }
        }
    }

    // MARK: - Negocios en ruta

    /// Burbujas visibles: los negocios más cercanos al centro visible del mapa.
    /// Se refrescan solo cuando el mapa se movió lo suficiente.
    @Published private(set) var negociosCerca: [Negocio] = []

    /// Negocio cuya card está abierta. El usuario ya mostró interés: se
    /// mantiene aunque salga del top cercano y se cierra solo con su botón.
    @Published var negocioSeleccionado: Negocio?

    /// Cambia cuando el viewport se movió lo bastante como para reprocesar las
    /// burbujas; la vista lo observa para agrupar movimientos rápidos.
    @Published private(set) var businessViewportRevision = 0

    private var businessMapCenter: CLLocationCoordinate2D?
    private var businessMapRadius: Double = 1800
    private var ultimoRefreshNegocios: CLLocationCoordinate2D?

    /// Registra el centro y el radio visibles del mapa. Solo cuenta como
    /// cambio si se desplazó ≥120 m o si el zoom varió lo suficiente: así un
    /// gesto pequeño no dispara una consulta.
    func actualizarViewport(center: CLLocationCoordinate2D, radius: Double) {
        let moved = businessMapCenter.map {
            NegociosService.distanciaMetros($0, center) >= 120
        } ?? true
        let zoomChanged = abs(radius - businessMapRadius) >= max(50, businessMapRadius * 0.1)
        guard moved || zoomChanged else { return }
        businessMapCenter = center
        businessMapRadius = radius
        businessViewportRevision += 1
    }

    /// Recalcula las burbujas visibles alrededor del viewport actual.
    ///
    /// `force` salta el filtro de distancia (lo usa el refresco con retardo
    /// que agrupa movimientos rápidos del mapa).
    func refrescarNegocios(force: Bool = false) {
        let pos = businessMapCenter ?? posicion ?? GTFSRepository.coordenadaUTP
        if !force, let ultimo = ultimoRefreshNegocios,
           NegociosService.distanciaMetros(ultimo, pos) < 120 { return }
        ultimoRefreshNegocios = pos
        let nuevos = NegociosService.shared.distribuidos(cercaDe: pos,
                                                        radioMetros: businessMapRadius,
                                                        limite: 14)
        if nuevos.map(\.id) != negociosCerca.map(\.id) {
            negociosCerca = nuevos
        }
    }

    // MARK: - Registro de la sesión (TripSession)

    private func registrarPunto(_ coord: CLLocationCoordinate2D, rumbo: Double) {
        guard var sesion else { return }
        // Muestreo con separación mínima de 3 m para no inundar el historial.
        if let ultimo = sesion.puntosRecorridos.last,
           PolylineMatching.distanceMeters(ultimo.coordinate, coord) < 3 { return }
        sesion.puntosRecorridos.append(
            TrackingPoint(lat: coord.latitude, lon: coord.longitude,
                          heading: max(0, rumbo))
        )
        self.sesion = sesion
    }

    private func finalizarSesion(estado nuevo: TripState) {
        // Resumen con las métricas del viaje para la card de llegada.
        let inicio = sesion?.startedAt ?? Date().timeIntervalSince1970
        let duracion = max(0, Date().timeIntervalSince1970 - inicio)
        let distancia = distanciaTotalM * progreso
        let puntos = sesion?.puntosRecorridos.count ?? 0
        resumen = ResumenViaje(
            duracionS: duracion,
            distanciaM: distancia,
            puntos: puntos,
            velocidadKmh: duracion > 0 ? (distancia / duracion) * 3.6 : 0
        )
        sesion?.estado = nuevo
        sesion?.endedAt = Date().timeIntervalSince1970
    }

    // MARK: - Cancelación

    func cancelTrip() {
        if tripInProgress { finalizarSesion(estado: .cancelled) }
        routeRevision = UUID()
        lastRecalculation = .distantPast
        itinerary = nil
        tripInProgress = false
        modoDemo = false
        destinoSeleccionado = nil
        routePolyline = nil
        etaTotalSeg = nil
        sesion = nil
        polyCoords.removeAll()
        distanciasAcumuladas.removeAll()
        distanciaTotalM = 0
        progreso = 0
        distanciaRestanteM = 0
        consecutiveOffRoute = 0
        recalculando = false
        resumen = nil
        rutaRecorrida = nil
        rutaRestante = nil
        rutaAproximada = false
        rutaGTFS = nil
        velocidadSimMs = 6.0
        ultimoFraccionPolyline = 0
        estado = posicion != nil ? .listo : .esperandoGPS
    }

    func stop() {
        cancelTrip()
        locationTask?.cancel()
        vehiculoTask?.cancel()
        vehicleProvider.stop()
        locationService.stopUpdating()
    }
}


/// Un viaje directo: caminata → paradero de subida → shape GTFS → bajada → caminata.
/// Los radios se verifican primero en línea recta y después sobre la caminata disponible.
struct TransitItinerary {
    let route: RutaGTFS
    let board: ParaderoGTFS
    let alight: ParaderoGTFS
    var walkToBoard: [CLLocationCoordinate2D]
    let bus: [CLLocationCoordinate2D]
    var walkToDestination: [CLLocationCoordinate2D]
    var walkingApproximate = true
    var walkToBoardMeters: Double { PolylineMatching.totalLengthMeters(walkToBoard) }
    let busMeters: Double
    var walkToDestinationMeters: Double { PolylineMatching.totalLengthMeters(walkToDestination) }
    var coordinates: [CLLocationCoordinate2D] { walkToBoard + bus + walkToDestination }
    let busSpeed: Double

    /// Geometría del tramo en bus lista para DIBUJAR, decimada una sola vez.
    ///
    /// `bus` conserva todas las esquinas porque de él salen `busMeters` y el
    /// avance del viaje, pero para dibujar MapKit no gana nada con 500 puntos
    /// donde 250 se ven igual — y este tramo se pinta DOS veces (contorno claro
    /// + color de línea) en cada mapa que lo muestra.
    let busDibujo: [CLLocationCoordinate2D]

    init(route: RutaGTFS, board: ParaderoGTFS, alight: ParaderoGTFS,
         walkToBoard: [CLLocationCoordinate2D], bus: [CLLocationCoordinate2D],
         walkToDestination: [CLLocationCoordinate2D]) {
        self.route = route
        self.board = board
        self.alight = alight
        self.walkToBoard = walkToBoard
        self.bus = bus
        self.walkToDestination = walkToDestination
        self.busMeters = PolylineMatching.totalLengthMeters(bus)
        self.busSpeed = min(14, max(3, route.distanciaKm * 1000 / Double(max(1, route.duracionMin) * 60)))
        self.busDibujo = PolylineMatching.decimate(bus, maxPoints: 250)
    }

    var totalSeconds: Double { (walkToBoardMeters + walkToDestinationMeters) / 1.4 + busMeters / busSpeed }

    static func candidates(in routes: [RutaGTFS], origin: CLLocationCoordinate2D,
                           destination: CLLocationCoordinate2D, radius: Double) -> [TransitItinerary] {
        var result: [TransitItinerary] = []
        for route in routes where route.shape.count >= 2 {
            let boarding = route.paraderos.enumerated().filter {
                PolylineMatching.distanceMeters(origin, $0.element.coordinate) <= radius
            }
            let arriving = route.paraderos.enumerated().filter {
                PolylineMatching.distanceMeters(destination, $0.element.coordinate) <= radius
            }
            guard !boarding.isEmpty, !arriving.isEmpty else { continue }
            // Mapear en orden evita invertir un recorrido o elegir el inicio de un bucle.
            var shapeIndices: [Int] = []
            var lower = 0
            for stop in route.paraderos {
                let best = (lower..<route.shape.count).min {
                    PolylineMatching.distanceMeters(stop.coordinate, route.shape[$0]) <
                    PolylineMatching.distanceMeters(stop.coordinate, route.shape[$1])
                } ?? lower
                shapeIndices.append(best)
                lower = best
            }
            for board in boarding {
                for alight in arriving where alight.offset > board.offset {
                    let first = shapeIndices[board.offset], last = shapeIndices[alight.offset]
                    guard last > first else { continue }
                    let segment = Array(route.shape[first...last])
                    guard PolylineMatching.distanceMeters(board.element.coordinate, segment[0]) < 80,
                          PolylineMatching.distanceMeters(alight.element.coordinate, segment[segment.count - 1]) < 80 else { continue }
                    // Conectores peatonales hasta el shape; el trazo continuo es siempre el GTFS.
                    let plan = TransitItinerary(route: route, board: board.element, alight: alight.element,
                        walkToBoard: [origin, board.element.coordinate, segment[0]], bus: segment,
                        walkToDestination: [segment[segment.count - 1], alight.element.coordinate, destination])
                    if plan.busMeters > 50 { result.append(plan) }
                }
            }
        }
        return result.sorted {
            if abs($0.totalSeconds - $1.totalSeconds) > 0.01 { return $0.totalSeconds < $1.totalSeconds }
            return $0.route.id < $1.route.id
        }
    }

    func withWalkingDirections(using service: RouteCalculationService) async -> TransitItinerary {
        var result = self
        guard let origin = walkToBoard.first, let destination = walkToDestination.last else { return result }
        // Secuencial para no saturar MKDirections; el respaldo se identifica en pantalla.
        let first = try? await service.calculateRoute(from: origin, to: board.coordinate, transportType: .walking)
        if Task.isCancelled { return result }
        let last = try? await service.calculateRoute(from: alight.coordinate, to: destination, transportType: .walking)
        if let first {
            let points = PolylineMatching.coordinates(from: first.polyline)
            if points.count >= 2 { result.walkToBoard = [origin] + points + [board.coordinate, bus[0]] }
        }
        if let last {
            let points = PolylineMatching.coordinates(from: last.polyline)
            if points.count >= 2 { result.walkToDestination = [bus[bus.count - 1], alight.coordinate] + points + [destination] }
        }
        result.walkingApproximate = first == nil || last == nil || (first?.polyline.pointCount ?? 0) < 2 || (last?.polyline.pointCount ?? 0) < 2
        return result
    }
}


/// El cálculo geométrico del feed no bloquea los gestos ni las animaciones.
actor TransitPlanner {
    static let shared = TransitPlanner()
    func candidates(in routes: [RutaGTFS], origin: CLLocationCoordinate2D,
                    destination: CLLocationCoordinate2D, radius: Double) -> [TransitItinerary] {
        TransitItinerary.candidates(in: routes, origin: origin, destination: destination, radius: radius)
    }
}
