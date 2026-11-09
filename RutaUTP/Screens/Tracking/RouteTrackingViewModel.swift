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

    // MARK: - Salida expuesta a la vista

    var estado: Estado = .esperandoGPS
    private(set) var posicion: CLLocationCoordinate2D?
    /// Se incrementa en cada fix; la vista lo observa para seguir la cámara
    /// (CLLocationCoordinate2D no conforma Equatable para .onChange).
    private(set) var posicionTick: Int = 0
    var progreso: Double = 0
    var distanciaRestanteM: Double = 0
    var etaTotalSeg: TimeInterval?      // de la ruta calculada
    var recalculando: Bool = false
    var tripInProgress: Bool = false
    var destinoSeleccionado: DestinoDemo? = nil
    var errorMessage: String? = nil
    var authStatus: CLAuthorizationStatus = .notDetermined

    /// Modo demo: simula el avance por la ruta calculada (ignora el GPS real).
    var modoDemo: Bool = false {
        didSet { modoDemo ? iniciarDemoSimulado() : detenerDemoSimulado() }
    }

    // Vehículos del proveedor; transporte y procedencia se conservan separados.
    var vehiculos: [VehiclePosition] = []
    private(set) var fuenteVehiculos: VehicleTrackingSource = .simulated
    var vehiculoSeleccionadoID: String?
    var vehiculoSeleccionado: VehiclePosition? {
        vehiculos.first { $0.id == vehiculoSeleccionadoID }
    }
    var vehiculosEnMapa: [VehiclePosition] {
        mapVehiclePreferences.limit.displayed(vehiculos, selectedID: vehiculoSeleccionadoID)
    }

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
    private(set) var coloresPorRuta: [String: String] = [:]

    @ObservationIgnored var tripRecorder: TripRecorder? {
        didSet { actualizarConteoPuntos() }
    }
    /// Sesión de valor para consulta/exportación; no se obtiene en cada fix.
    var sesion: TripSession? { tripRecorder?.snapshot }
    var puntosGPSRegistrados = 0

    var routePolyline: MKPolyline?
    /// Ruta dividida por el avance: tramo recorrido (tenue) y restante (vivo).
    var rutaRecorrida: MKPolyline? = nil
    var rutaRestante: MKPolyline? = nil
    /// True cuando MKDirections no respondió y la ruta es un trazo directo.
    var rutaAproximada: Bool = false
    /// Línea REAL del feed GTFS usada para el viaje (nil = MapKit/respaldo).
    /// El shape del tramo y el ritmo de simulación salen de esta línea.
    var rutaGTFS: RutaGTFS?
    /// True mientras corre el pipeline de ruteo (spinner del botón Iniciar).
    var calculandoRuta: Bool = false
    /// Rumbo actual en grados (-1 desconocido): orienta la cámara y el marcador.
    private(set) var rumbo: Double = -1
    private static func leer(_ preferencia: Preferencia, defaults: UserDefaults) -> Double {
        // No reescribe el original si está dañado. Solo admite valores finitos
        // presentes en el selector, antes de usarlos en cálculos o convertir a Int.
        guard let numero = defaults.object(forKey: preferencia.rawValue) as? NSNumber,
              CFGetTypeID(numero) != CFBooleanGetTypeID() else { return preferencia.porDefecto }
        let valor = numero.doubleValue
        guard
              valor.isFinite, preferencia.valoresPermitidos.contains(valor) else {
            return preferencia.porDefecto
        }
        return valor
    }

    private func guardar(_ valor: Double, para preferencia: Preferencia) {
        let clave = preferencia.rawValue
        // UserDefaults puede considerar iguales true y 1 al comparar NSNumber.
        // Retirar el booleano evita conservar su tipo al confirmar un número.
        if PreferenciasApp.boolGuardado(para: clave, defaults: defaults) != nil {
            defaults.removeObject(forKey: clave)
        }
        defaults.set(valor, forKey: clave)
    }

    /// Multiplicador del modo demo (1× / 3× / 10×). Persistido.
    private var velocidadPreferida: Double
    var velocidadDemo: Double {
        get { velocidadPreferida }
        set {
            guard newValue.isFinite, Preferencia.velocidad.valoresPermitidos.contains(newValue) else { return }
            guardar(newValue, para: .velocidad)
            velocidadPreferida = newValue
        }
    }
    /// Velocidad estimada por vehículo (m/s), calculada entre snapshots del
    /// provider para el popup en vivo.
    var velocidadesVehiculos: [String: Double] = [:]

    var resumen: ResumenViaje?

    /// Radio de búsqueda de paraderos, en metros. Persistido (ver `Preferencia`).
    private var radioPreferido: Double
    var radioParadero: Double {
        get { radioPreferido }
        set {
            guard newValue.isFinite, Preferencia.radio.valoresPermitidos.contains(newValue) else { return }
            guardar(newValue, para: .radio)
            radioPreferido = newValue
        }
    }
    var installedItinerary: InstalledTransitItinerary?
    var itinerary: TransitItinerary? { installedItinerary?.plan }
    private(set) var nearestStop: ParaderoGTFS?
    private(set) var nearestStopMeters: Double?
    var buscandoDestino = false
    @ObservationIgnored var routeRevision = UUID()
    @ObservationIgnored var lastRecalculation = Date.distantPast
    private var allStops: [ParaderoGTFS] = []
    var idsRutasDisponibles: Set<String> = []
    var catalogoPendientePorFallo = false
    var mensajeErrorCatalogo: String?
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
    let routeService: RouteCalculationService
    let vehicleProvider: VehicleTrackingProviding
    let repositorioGTFS: RutasGTFSProviding
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let mapVehiclePreferences: MapVehiclePreferences

    // Shape completo: conserva todas las esquinas de la calle para matching y simulación.
    var polyCoords: [CLLocationCoordinate2D] = []
    var distanciasAcumuladas: [Double] = []
    var distanciaTotalM: Double = 0

    @ObservationIgnored var consecutiveOffRoute: Int = 0
    @ObservationIgnored private var locationTask: Task<Void, Never>?
    @ObservationIgnored var vehiculoTask: Task<Void, Never>?
    @ObservationIgnored var demoTask: Task<Void, Never>?
    @ObservationIgnored var actividadVisual = true
    @ObservationIgnored var demoProgreso: Double = 0
    @ObservationIgnored var ultimoFraccionPolyline: Double = 0
    /// Ritmo real de simulación en m/s (de la línea GTFS o del ETA de MapKit).
    var velocidadSimMs: Double = 6.0
    @ObservationIgnored var presentacionFlota = PresentacionFlotaTracking()

    @ObservationIgnored private var authCancellable: AnyCancellable?
    /// Cerrar o volver a entrar invalida permisos y catálogos todavía pendientes.
    @ObservationIgnored var startGuard = StartGuard()

    // MARK: - Init

    init(locationService: LocationServiceProtocol,
         routeService: RouteCalculationService = RouteCalculationService(),
         vehicleProvider: VehicleTrackingProviding? = nil,
         repositorioGTFS: RutasGTFSProviding = TransporteApp.repositorio,
         defaults: UserDefaults = .standard,
         mapVehiclePreferences: MapVehiclePreferences? = nil) {
        self.defaults = defaults
        self.mapVehiclePreferences = mapVehiclePreferences ?? .shared
        self.velocidadPreferida = Self.leer(.velocidad, defaults: defaults)
        self.radioPreferido = Self.leer(.radio, defaults: defaults)
        self.locationService = locationService
        self.routeService = routeService
        let provider = vehicleProvider ?? SimulatedTrackingProvider()
        self.vehicleProvider = provider
        self.repositorioGTFS = repositorioGTFS
        self.fuenteVehiculos = provider.source

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
        let provider = vehicleProvider
        Task { @MainActor in provider.stop() }
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

    func aplicarCatalogo(_ feed: [RutaGTFS]) {
        catalogoPendientePorFallo = false
        if let mensajeErrorCatalogo, errorMessage == mensajeErrorCatalogo { errorMessage = nil }
        mensajeErrorCatalogo = nil
        var seen = Set<String>()
        allStops = feed.flatMap(\.paraderos).filter { seen.insert($0.id).inserted }
        idsRutasDisponibles = Set(feed.map(\.id))
        // El route_id distingue ramales que comparten nombre y distinto color.
        coloresPorRuta = feed.reduce(into: [String: String]()) { mapa, ruta in
            mapa[ruta.id] = ruta.colorHex
        }
        // Solo los proveedores antiguos sin route_id necesitan este fallback.
        // Elegir el id menor mantiene su resultado independiente del orden.
        coloresPorLinea = feed
            .sorted { $0.id < $1.id }
            .reduce(into: [String: String]()) { mapa, ruta in
                if mapa[ruta.linea] == nil { mapa[ruta.linea] = ruta.colorHex }
            }
        if let posicion { refreshNearestStop(at: posicion) }
        if fuenteVehiculos == .real { aplicarSnapshotVehiculos(force: true) }
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
                guard UbicacionPuntual.esValida(location, ahora: Date(),
                                               antiguedadMaxima: 30, precisionMaxima: 65) else { continue }
                self.procesar(coordenada: location.coordinate, rumbo: location.course)
            }
        }
        locationService.startUpdating()
    }

    // MARK: - Procesamiento de fixes (mismos umbrales de NavegacionRutaView)

    func procesar(coordenada: CLLocationCoordinate2D, rumbo: Double) {
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
            // El fix pertenece a esta revisión aunque la tarea empiece después
            // de cancelar el viaje o de instalar un destino nuevo.
            let revisionEsperada = routeRevision
            Task { await recalcular(desde: coordenada, revisionEsperada: revisionEsperada) }
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

    // MARK: - Negocios en ruta

    /// Burbujas visibles: los negocios más cercanos al centro visible del mapa.
    /// Se refrescan solo cuando el mapa se movió lo suficiente.
    var negociosCerca: [Negocio] = []

    /// Negocio cuya card está abierta. El usuario ya mostró interés: se
    /// mantiene aunque salga del top cercano y se cierra solo con su botón.
    var negocioSeleccionado: Negocio?

    /// Cambia cuando el viewport se movió lo bastante como para reprocesar las
    /// burbujas; la vista lo observa para agrupar movimientos rápidos.
    var businessViewportRevision = 0

    var businessMapCenter: CLLocationCoordinate2D?
    var businessMapRadius: Double = 1800
    @ObservationIgnored var ultimoRefreshNegocios: CLLocationCoordinate2D?

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
        calculandoRuta = false
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
        vehiculos = []
        velocidadesVehiculos = [:]
        presentacionFlota.limpiarHistorial()
        vehiculoSeleccionadoID = nil
        presentacionFlota.reiniciarPublicacion()
    }
}
