// Tracking Demo: itinerarios directos de transporte público sobre GTFS.
// Separa caminata de subida, recorrido del micro y caminata final.
// La ubicación puede ser GPS o simulación; la flota es siempre demo hasta
// conectar un VehicleTrackingProviding real. No requiere un backend para el feed.

import Foundation
import Combine
import Observation
import CoreLocation
import MapKit

@MainActor
@Observable
final class RouteTrackingViewModel {

    // MARK: - Destinos del demo (sede y referencias del Mapa)

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
    /// Las referencias y sus claves señables viven en `DestinosFijos`,
    /// compartido con el Mapa: antes estaban escritos literales en los dos.
    var destinos: [DestinoDemo] {
        let referencias = DestinosFijos.todos.filter { TransporteApp.busesUTPActivos || $0.id != 1 }.map {
            DestinoDemo(id: $0.id, label: $0.label, icon: $0.icono,
                        coordinate: $0.coordinate)
        }
        guard let sede = TransporteApp.sedeVisible else { return referencias }
        return [DestinoDemo(id: CatalogoSedesTrabajo.idChipSede, label: sede.nombre,
                            icon: "building.2.fill", coordinate: sede.coordinate)] + referencias
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

    private(set) var estado: Estado = .esperandoGPS
    private(set) var posicion: CLLocationCoordinate2D?
    /// Se incrementa en cada fix; la vista lo observa para seguir la cámara
    /// (CLLocationCoordinate2D no conforma Equatable para .onChange).
    private(set) var posicionTick: Int = 0
    private(set) var progreso: Double = 0
    private(set) var distanciaRestanteM: Double = 0
    private(set) var etaTotalSeg: TimeInterval?      // de la ruta calculada
    private(set) var recalculando: Bool = false
    private(set) var tripInProgress: Bool = false
    private(set) var destinoSeleccionado: DestinoDemo? = nil
    private(set) var errorMessage: String? = nil
    var authStatus: CLAuthorizationStatus = .notDetermined

    /// Modo demo: simula el avance por la ruta calculada (ignora el GPS real).
    var modoDemo: Bool = false {
        didSet { modoDemo ? iniciarDemoSimulado() : detenerDemoSimulado() }
    }

    // Vehículos en el mapa vía provider (badge DEMO / EN VIVO en la UI).
    private(set) var vehiculos: [VehiclePosition] = []
    private(set) var fuenteVehiculos: VehicleTrackingSource = .simulated

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
    private(set) var coloresPorLinea: [String: String] = [:]

    @ObservationIgnored private var tripRecorder: TripRecorder? {
        didSet { actualizarConteoPuntos() }
    }
    /// Sesión de valor para consulta/exportación; no se obtiene en cada fix.
    var sesion: TripSession? { tripRecorder?.snapshot }
    private(set) var puntosGPSRegistrados = 0

    private(set) var routePolyline: MKPolyline?
    /// Ruta dividida por el avance: tramo recorrido (tenue) y restante (vivo).
    private(set) var rutaRecorrida: MKPolyline? = nil
    private(set) var rutaRestante: MKPolyline? = nil
    /// True cuando MKDirections no respondió y la ruta es un trazo directo.
    private(set) var rutaAproximada: Bool = false
    /// Línea REAL del feed GTFS usada para el viaje (nil = MapKit/respaldo).
    /// El shape del tramo y el ritmo de simulación salen de esta línea.
    private(set) var rutaGTFS: RutaGTFS?
    /// True mientras corre el pipeline de ruteo (spinner del botón Iniciar).
    private(set) var calculandoRuta: Bool = false
    /// Rumbo actual en grados (-1 desconocido): orienta la cámara y el marcador.
    private(set) var rumbo: Double = -1
    /// Preferencias del modo demo que sobreviven a salir de la pantalla.
    ///
    /// RootView conserva este modelo al cambiar de pantalla. UserDefaults
    /// mantiene radio y velocidad también al reiniciar la app o crear un modelo
    /// nuevo; la sesión del viaje permanece solo en memoria.
    enum Preferencia: String {
        case radio = "tracking.radioParadero"
        case velocidad = "tracking.velocidadDemo"

        /// Opciones compartidas por la validación y los controles de la vista.
        var valoresPermitidos: [Double] {
            switch self {
            // 1 600 m llega donde el mapa principal ya llega por defecto
            // (`MapaViewModel.radioBusquedaRuta`). Con el tope en 800 el
            // Tracking no encontraba rutas que el mapa sí mostraba, y parecía
            // un fallo del modo de demostración en lugar de un radio corto.
            case .radio: return [200, 500, 800, 1600]
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
    var velocidadDemo: Double = RouteTrackingViewModel.leer(.velocidad) {
        didSet { UserDefaults.standard.set(velocidadDemo, forKey: Preferencia.velocidad.rawValue) }
    }
    /// Velocidad estimada por vehículo (m/s), calculada entre snapshots del
    /// provider para el popup en vivo.
    private(set) var velocidadesVehiculos: [String: Double] = [:]

    /// Métricas del viaje terminado (las muestra la card de llegada).
    struct ResumenViaje: Equatable {
        let duracionS: TimeInterval
        let distanciaM: Double
        let puntos: Int
        let velocidadKmh: Double
    }
    private(set) var resumen: ResumenViaje?

    /// Radio de búsqueda de paraderos, en metros. Persistido (ver `Preferencia`).
    var radioParadero: Double = RouteTrackingViewModel.leer(.radio) {
        didSet { UserDefaults.standard.set(radioParadero, forKey: Preferencia.radio.rawValue) }
    }
    private(set) var installedItinerary: InstalledTransitItinerary?
    var itinerary: TransitItinerary? { installedItinerary?.plan }
    private(set) var nearestStop: ParaderoGTFS?
    private(set) var nearestStopMeters: Double?
    var buscandoDestino = false
    @ObservationIgnored private var routeRevision = UUID()
    @ObservationIgnored private var lastRecalculation = Date.distantPast
    private var allStops: [ParaderoGTFS] = []
    private var idsRutasDisponibles: Set<String> = []
    private var catalogoPendientePorFallo = false
    private var mensajeErrorCatalogo: String?
    @ObservationIgnored private var nearestAnchor: CLLocationCoordinate2D?

    typealias JourneyLeg = ItineraryMetrics.JourneyLeg
    var journeyLeg: JourneyLeg {
        guard let metrics = installedItinerary?.metrics else { return .walkingToBoard }
        return metrics.journeyLeg(after: progreso * distanciaTotalM)
    }

    var remainingSeconds: Double {
        guard let metrics = installedItinerary?.metrics else { return (etaTotalSeg ?? 0) * (1 - progreso) }
        return metrics.remainingSeconds(after: progreso * distanciaTotalM)
    }

    func buscarDestino(_ text: String) async -> DestinoDemo? {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !buscandoDestino else { return nil }
        buscandoDestino = true
        defer { buscandoDestino = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query + ", Trujillo, Perú"
        request.region = MKCoordinateRegion(center: TransporteApp.referenciaInicio,
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
        var nearest: (ParaderoGTFS, Double)?
        for stop in allStops {
            let distance = PolylineMatching.distanceMeters(coordinate, stop.coordinate)
            // El comparador estricto conserva el primero en un empate, como min.
            if let current = nearest, !(distance < current.1) { continue }
            nearest = (stop, distance)
        }
        nearestStop = nearest?.0
        nearestStopMeters = nearest?.1
    }

    // MARK: - Dependencias

    private let locationService: LocationServiceProtocol
    private let routeService: RouteCalculationService
    private let vehicleProvider: VehicleTrackingProviding
    private let repositorioGTFS: RutasGTFSProviding

    // Shape completo: conserva todas las esquinas de la calle para matching y simulación.
    private var polyCoords: [CLLocationCoordinate2D] = []
    private var distanciasAcumuladas: [Double] = []
    private var distanciaTotalM: Double = 0

    @ObservationIgnored private var consecutiveOffRoute: Int = 0
    @ObservationIgnored private var locationTask: Task<Void, Never>?
    @ObservationIgnored private var vehiculoTask: Task<Void, Never>?
    @ObservationIgnored private var demoTask: Task<Void, Never>?
    @ObservationIgnored private var actividadVisual = true
    @ObservationIgnored private var demoProgreso: Double = 0
    @ObservationIgnored private var ultimoFraccionPolyline: Double = 0
    /// Ritmo real de simulación en m/s (de la línea GTFS o del ETA de MapKit).
    private var velocidadSimMs: Double = 6.0
    @ObservationIgnored private var snapshotVehiculosAnterior: [String: (coord: CLLocationCoordinate2D, t: TimeInterval)] = [:]

    @ObservationIgnored private var authCancellable: AnyCancellable?
    /// Cerrar o volver a entrar invalida permisos y catálogos todavía pendientes.
    @ObservationIgnored private var startGuard = StartGuard()

    // MARK: - Init

    init(locationService: LocationServiceProtocol,
         routeService: RouteCalculationService = RouteCalculationService(),
         vehicleProvider: VehicleTrackingProviding = SimulatedTrackingProvider(),
         repositorioGTFS: RutasGTFSProviding = TransporteApp.repositorio) {
        self.locationService = locationService
        self.routeService = routeService
        self.vehicleProvider = vehicleProvider
        self.repositorioGTFS = repositorioGTFS
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
        // Cancelar nuestro stream deja que onTermination libere solo este
        // consumidor. No cambia la demanda global de Mapa o del rastreo.
    }

    // MARK: - Permisos y arranque

    func requestPermissionAndStart() async {
        guard !Task.isCancelled else { return }
        let token = startGuard.begin()
        // Los proveedores conservan su stream hasta stop(). Una reentrada
        // renueva nuestros lectores sin cancelar el viaje ni el GPS global.
        liberarLectores()
        guard !TransporteApp.rutasUTPPendientes else {
            estado = .listo
            errorMessage = TransporteApp.mensajePendiente
            return
        }
        defer {
            // Cancelar la tarea de una entrada aún vigente también libera lo
            // que ya arrancó antes de esperar el catálogo. Una entrada nueva
            // conserva sus recursos aunque la tarea anterior termine después.
            if Task.isCancelled, startGuard.isCurrent(token) { suspenderPantalla() }
        }
        let status = await locationService.requestPermission()
        guard !Task.isCancelled, startGuard.isCurrent(token) else { return }
        authStatus = status
        if status.isAuthorized, locationService.authorizationStatus.isAuthorized {
            startObservingLocation(token: token)
        } else {
            locationTask?.cancel()
            locationTask = nil
            estado = .sinPermiso
            errorMessage = L.t("Permiso de ubicación denegado. Actívalo en Ajustes para usar el tracking.",
                               "Location permission denied. Enable it in Settings to use tracking.")
        }
        iniciarVehiculos(token: token)
        let feed: [RutaGTFS]
        do {
            feed = try await repositorioGTFS.cargarRutas(reintentar: false)
            guard !Task.isCancelled, startGuard.isCurrent(token) else { return }
        } catch {
            guard !Task.isCancelled, startGuard.isCurrent(token) else { return }
            catalogoPendientePorFallo = true
            errorMessage = (error as? FalloCargaGTFS)?.mensajeUsuario
                ?? L.t("No se pudieron cargar las rutas. Vuelve a intentarlo.", "Couldn't load routes. Try again.")
            mensajeErrorCatalogo = errorMessage
            return
        }
        aplicarCatalogo(feed)
    }

    private func aplicarCatalogo(_ feed: [RutaGTFS]) {
        catalogoPendientePorFallo = false
        if let mensajeErrorCatalogo, errorMessage == mensajeErrorCatalogo { errorMessage = nil }
        mensajeErrorCatalogo = nil
        var seen = Set<String>()
        allStops = feed.flatMap(\.paraderos).filter { seen.insert($0.id).inserted }
        idsRutasDisponibles = Set(feed.map(\.id))
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

    private func startObservingLocation(token: Int) {
        locationTask?.cancel()
        // Registrar antes de iniciar evita perder una lectura inmediata.
        let stream = locationService.currentLocation(requirement: .navigation)
        locationTask = Task { @MainActor [weak self] in
            for await location in stream {
                // No retener el modelo mientras el GPS espera otra lectura:
                // así deinit también puede cancelar y liberar el consumidor.
                guard !Task.isCancelled, let self, self.startGuard.isCurrent(token) else { break }
                if self.modoDemo { continue }   // el demo simulado toma el control
                self.procesar(coordenada: location.coordinate, rumbo: location.course)
            }
        }
        locationService.startUpdating()
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
            if tripRecorder?.estado != .completed {
                finalizarSesion(estado: .completed)
            }
            if modoDemo { modoDemo = false }
        }

    }

    // MARK: - Inicio de viaje

    func iniciar(destino: DestinoDemo) async {
        guard !calculandoRuta else { return }
        guard !TransporteApp.rutasUTPPendientes else {
            errorMessage = TransporteApp.mensajePendiente
            return
        }
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
        installedItinerary = nil
        routePolyline = nil
        progreso = 0
        consecutiveOffRoute = 0
        resumen = nil

        calculandoRuta = true
        defer { calculandoRuta = false }
        await calcularRuta(desde: origen, hacia: destino.coordinate)

        if let plan = itinerary, routePolyline != nil {
            tripRecorder = TripRecorder(sesion: TripSession(linea: plan.lineDescription, empresa: plan.route.empresa,
                origen: TrackingPoint(lat: origen.latitude, lon: origen.longitude),
                destino: TrackingPoint(lat: destino.coordinate.latitude, lon: destino.coordinate.longitude),
                estado: .inProgress, startedAt: Date().timeIntervalSince1970))
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
        tripRecorder?.actualizarEstado(.recalculating)

        await calcularRuta(desde: origen, hacia: destino.coordinate)

        recalculando = false
        consecutiveOffRoute = 0
        if tripRecorder?.estado == .recalculating { tripRecorder?.actualizarEstado(.inProgress) }
    }

    /// Solo itinerarios de transporte del feed: nunca sustituye un micro por una ruta de auto.
    private func calcularRuta(desde origen: CLLocationCoordinate2D,
                              hacia destino: CLLocationCoordinate2D) async {
        guard !TransporteApp.rutasUTPPendientes else {
            errorMessage = TransporteApp.mensajePendiente
            return
        }
        let revision = UUID()
        routeRevision = revision
        let radio = radioParadero
        let catalog: GTFSRouteCatalog
        do {
            // Iniciar/recalcular es una acción concreta; no tratar el fallo
            // de lectura como ausencia de paraderos dentro del radio.
            catalog = try await TransporteApp.repositorio.cargarCatalogo(reintentar: true)
            guard revision == routeRevision, !Task.isCancelled else { return }
        } catch {
            guard revision == routeRevision, !Task.isCancelled else { return }
            catalogoPendientePorFallo = true
            errorMessage = (error as? FalloCargaGTFS)?.mensajeUsuario
                ?? L.t("No se pudieron cargar las rutas. Vuelve a intentarlo.", "Couldn't load routes. Try again.")
            mensajeErrorCatalogo = errorMessage
            return
        }
        if catalogoPendientePorFallo {
            // Recuperar también las dependencias del inicio, conservando el
            // lector de vehículos y su stream registrados en E07.
            aplicarCatalogo(catalog.routes)
            (vehicleProvider as? SimulatedTrackingProvider)?.restaurarCatalogoTrasFallo(catalog.routes)
        }
        let candidates = await TransitPlanner.shared.candidates(in: catalog, origin: origen,
                                                     destination: destino, radius: radio)
        var selected: InstalledTransitItinerary?
        // Limita peticiones a MapKit; cada candidato conserva paraderos y sentido GTFS.
        for candidate in candidates.prefix(4) {
            guard !Task.isCancelled, revision == routeRevision else { return }
            let resolved = await candidate.withWalkingDirections(using: routeService)
            guard !Task.isCancelled, revision == routeRevision else { return }
            let installed = InstalledTransitItinerary(plan: resolved)
            let metrics = installed.metrics
            if metrics.walkToBoardMeters <= radio && metrics.walkToDestinationMeters <= radio && metrics.walkingWithinTransferLimit {
                selected = installed
                break
            }
        }
        guard revision == routeRevision, !Task.isCancelled else { return }
        guard let installed = selected else {
            // Compara contra el MAYOR radio que ofrece el selector, no contra
            // un número fijo: con el tope en 800, un usuario que ya estaba en
            // 800 veía "prueba otro destino" sin ninguna opción que probar.
            let maximo = Preferencia.radio.valoresPermitidos.max() ?? radio
            let sugerencia = radio < maximo
                ? L.t("Prueba un radio mayor u otro destino.", "Try a larger radius or another destination.")
                : L.t("Prueba otro destino.", "Try another destination.")
            errorMessage = L.t("No encontramos una ruta directa ni con un transbordo con paraderos a menos de \(Int(radio)) m de ambos extremos. ",
                               "No direct or one-transfer route has stops within \(Int(radio)) m of both ends. ") + sugerencia
            return
        }
        errorMessage = nil
        installedItinerary = installed
        let plan = installed.plan
        let coordinates = plan.coordinates
        rutaGTFS = plan.route
        rutaAproximada = plan.walkingApproximate
        routePolyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        etaTotalSeg = installed.metrics.totalSeconds
        progreso = 0
        instalarShape(coordinates)
        distanciaRestanteM = distanciaTotalM
        (vehicleProvider as? SimulatedTrackingProvider)?.follow(routeID: plan.route.id, near: plan.board.coordinate)
        tripRecorder?.actualizarEstado(.inProgress)
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
        reanudarDemoSimulado()
    }

    /// La pausa visual conserva sesión, progreso y modo demo.
    func actualizarActividadVisual(_ activa: Bool) {
        actividadVisual = activa
        (vehicleProvider as? SimulatedTrackingProvider)?.actualizarActividadVisual(activa)
        if activa { reanudarDemoSimulado() } else { detenerDemoSimulado() }
    }

    private func reanudarDemoSimulado() {
        guard actividadVisual, modoDemo, tripInProgress, estado != .finalizado,
              polyCoords.count >= 2, demoTask == nil else { return }
        // Una sola tarea que duerme entre pasos. Antes era un `Timer` que
        // creaba un `Task` nuevo por tick — doce por segundo — solo para saltar
        // al hilo principal.
        demoTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 80_000_000)
                guard !Task.isCancelled, let self, self.actividadVisual else { return }
                guard let total = self.distanciasAcumuladas.last, total > 1 else { continue }
                // Avance por METROS reales: velocidad real de la ruta (m/s)
                // × multiplicador elegido. 1× = ritmo real de la línea.
                let speed: Double
                switch self.journeyLeg {
                case .riding: speed = self.itinerary?.busSpeed ?? 6
                case .ridingSecond: speed = self.itinerary?.transfer?.busSpeed ?? 6
                default: speed = 1.4
                }
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

    private func iniciarVehiculos(token: Int) {
        vehiculoTask?.cancel()
        let stream = vehicleProvider.positions()
        vehiculoTask = Task { @MainActor [weak self] in
            var ultimaActualizacion = 0.0
            for await positions in stream {
                guard !Task.isCancelled, let self, self.startGuard.isCurrent(token) else { break }
                // El provider ticka a 20 Hz: la UI se refresca a 4 Hz, de sobra
                // para que los buses se muevan fluidos sin re-renderizar el
                // mapa a cada instante.
                let ahora = Date().timeIntervalSince1970
                guard ahora - ultimaActualizacion >= 0.25 else { continue }
                ultimaActualizacion = ahora

                let visibles = TransporteApp.busesUTPActivos
                    ? positions.filter { self.idsRutasDisponibles.contains($0.routeId) } : positions

                var velocidades = self.velocidadesVehiculos
                for vehiculo in visibles {
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
                self.vehiculos = visibles
            }
        }
        vehicleProvider.start()
    }

    // MARK: - Negocios en ruta

    /// Burbujas visibles: los negocios más cercanos al centro visible del mapa.
    /// Se refrescan solo cuando el mapa se movió lo suficiente.
    private(set) var negociosCerca: [Negocio] = []

    /// Negocio cuya card está abierta. El usuario ya mostró interés: se
    /// mantiene aunque salga del top cercano y se cierra solo con su botón.
    var negocioSeleccionado: Negocio?

    /// Cambia cuando el viewport se movió lo bastante como para reprocesar las
    /// burbujas; la vista lo observa para agrupar movimientos rápidos.
    private(set) var businessViewportRevision = 0

    private var businessMapCenter: CLLocationCoordinate2D?
    private var businessMapRadius: Double = 1800
    @ObservationIgnored private var ultimoRefreshNegocios: CLLocationCoordinate2D?

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
        let pos = businessMapCenter ?? posicion ?? TransporteApp.referenciaInicio
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
        guard tripRecorder?.registrarPunto(coord, rumbo: rumbo) == true else { return }
        actualizarConteoPuntos()
    }

    private func actualizarConteoPuntos() {
        let count = tripRecorder?.cantidadPuntos ?? 0
        if puntosGPSRegistrados != count { puntosGPSRegistrados = count }
    }

    private func finalizarSesion(estado nuevo: TripState) {
        // Resumen con las métricas del viaje para la card de llegada.
        let inicio = tripRecorder?.startedAt ?? Date().timeIntervalSince1970
        let duracion = max(0, Date().timeIntervalSince1970 - inicio)
        let distancia = distanciaTotalM * progreso
        let puntos = tripRecorder?.cantidadPuntos ?? 0
        resumen = ResumenViaje(
            duracionS: duracion,
            distanciaM: distancia,
            puntos: puntos,
            velocidadKmh: duracion > 0 ? (distancia / duracion) * 3.6 : 0
        )
        tripRecorder?.finalizar(estado: nuevo)
    }

    // MARK: - Cancelación

    func cancelTrip() {
        if tripInProgress { finalizarSesion(estado: .cancelled) }
        routeRevision = UUID()
        lastRecalculation = .distantPast
        installedItinerary = nil
        tripInProgress = false
        modoDemo = false
        destinoSeleccionado = nil
        routePolyline = nil
        etaTotalSeg = nil
        tripRecorder = nil
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

    /// Libera esta pantalla sin finalizar el viaje guardado en su modelo.
    func suspenderPantalla() {
        actualizarActividadVisual(false)
        startGuard.invalidate()
        liberarLectores()
    }

    func stop() {
        startGuard.invalidate()
        cancelTrip()
        liberarLectores()
        // El GPS compartido sigue activo si otro consumidor mantiene su stream.
    }

    private func liberarLectores() {
        locationTask?.cancel()
        locationTask = nil
        vehiculoTask?.cancel()
        vehiculoTask = nil
        vehicleProvider.stop()
    }
}
