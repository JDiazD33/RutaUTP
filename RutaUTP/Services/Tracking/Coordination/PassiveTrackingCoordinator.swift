import Foundation
import CoreLocation
import Combine
import UIKit

@MainActor
final class PassiveTrackingCoordinator: ObservableObject {

    @Published private(set) var isEnabled: Bool
    @Published private(set) var isRunning = false
    @Published private(set) var errorCargaRutas: FalloCargaGTFS?

    @Published private(set) var detectionState:
        PassengerDetectionState = .idle

    @Published private(set) var motionActivity:
        DetectedMotionActivity = .unknown

    @Published private(set) var candidateLine: String?
    @Published private(set) var confirmedLine: String?
    @Published private(set) var distanceToRoute: Double?
    @Published private(set) var shouldPublish = false

    /// Estado actual del canal utilizado para publicar observaciones.
    ///
    /// Esta propiedad permite que SwiftUI muestre si MQTT está conectando,
    /// conectado, inactivo o si ocurrió algún error.
    @Published private(set) var observationPublisherState:
        ObservationPublisherState = .inactive

    @Published private(set) var statusMessage =
        "Contribución desactivada"

    /// Indica si esta instalación tiene un canal MQTT utilizable.
    /// Sin publicador no se deben encender GPS ni Core Motion, porque ninguna
    /// observación podría salir del dispositivo.
    var isPublisherConfigured: Bool {
        observationPublisher != nil
    }

    @Published private(set) var selectedTripRoute: DetectionRouteGeometry?
    @Published private(set) var tripStartedAt: Date?
    @Published private(set) var boardingPlace: String?
    @Published private(set) var boardingPoint: BoardingPoint?
    @Published private(set) var latestLocation: CLLocation?
    let tripOccupancy: OccupancyService
    private var waitingForNewTrip = false

    /// La declaración orienta el detector; nunca salta sus comprobaciones.
    func beginTrip(route: DetectionRouteGeometry, occupancy: BusOccupancyState?, boardingPlace: String = "", boardingPoint: BoardingPoint? = nil) {
        guard isEnabled, isPublisherConfigured else { return }
        stopObservationSession()
        tripOccupancy.clearTripReport()
        detectionEngine.reset()
        detectionState = .idle
        confirmedLine = nil
        shouldPublish = false
        selectedTripRoute = route
        tripStartedAt = Date()
        self.boardingPlace = BoardingPlaceStore.normalized(boardingPlace)
        self.boardingPoint = boardingPoint
        BoardingPlaceStore.save(routeID: route.id, line: route.linea,
                                place: self.boardingPlace ?? "", point: boardingPoint)
        waitingForNewTrip = false
        statusMessage = "Esperando detectar el viaje en la línea \(route.linea)"
        if let occupancy { updateTripOccupancy(occupancy) }
    }

    func updateTripOccupancy(_ state: BusOccupancyState) {
        guard isEnabled, let route = selectedTripRoute else { return }
        tripOccupancy.prepareTripReport(routeID: route.id, state: state)
    }

    func endTrip() {
        stopObservationSession()
        tripOccupancy.clearTripReport()
        selectedTripRoute = nil
        tripStartedAt = nil
        boardingPlace = nil
        boardingPoint = nil
        detectionEngine.reset()
        detectionState = .idle
        confirmedLine = nil
        candidateLine = nil
        shouldPublish = false
        waitingForNewTrip = true
        statusMessage = "Viaje terminado. Indica tu próximo micro para volver a ayudar."
    }

    private let locationService:
        LocationServiceProtocol

    private let motionService:
        MotionActivityProviding

    private let repository:
        GTFSRepository

    /// Componente encargado de transmitir observaciones autorizadas.
    ///
    /// Sin configuración la contribución permanece deshabilitada. Durante
    /// las pruebas puede sustituirse por un publicador simulado.
    private let observationPublisher:
        ObservationPublishing?


    private var detectionEngine: PassengerDetectionEngine

    private var routes:
        [DetectionRouteGeometry] = []

    private var locationTask:
        Task<Void, Never>?

    private var motionTask:
        Task<Void, Never>?

    /// Arranque en curso, para poder cancelarlo.
    ///
    /// Antes, `setContributionEnabled(true)` lanzaba una `Task` sin conservarla:
    /// si el usuario revocaba el consentimiento mientras se pedía el permiso o
    /// se cargaba el feed, la continuación seguía adelante y dejaba la
    /// detección y la publicación activas sin consentimiento.
    private var startTask:
        Task<Void, Never>?

    /// Testigo del arranque vigente. Ver `StartGuard`.
    private var startGuard = StartGuard()

    /// Observadores del ciclo de vida de la app.
    ///
    /// iOS suspende el proceso poco después de pasar a segundo plano:
    /// el socket MQTT y el GPS mueren sin despedida. Detectar la
    /// transición permite cerrar la publicación de forma limpia y
    /// reanudarla cuando el usuario vuelve a la app.
    private var backgroundObserver: NSObjectProtocol?

    private var foregroundObserver: NSObjectProtocol?
    private var appEnSegundoPlano = false
    /// La sesión sigue siendo del mismo viaje, pero el canal fue detenido.
    /// Si foreground llega durante un posible descenso, una muestra posterior
    /// puede volver a autorizar el envío sin confirmar otro abordaje.
    private var sesionPausadaPorBackground = false

    /// UUID temporal de la sesión de viaje.
    ///
    /// Se crea al confirmar el abordaje y se descarta del estado local al terminar
    /// la sesión. MQTT lo vincula a la cuenta autenticada; rotarlo no impide
    /// correlacionar viajes ni elimina las observaciones ya enviadas al backend.
    private var observationSessionID: String?

    /// Identificador GTFS fijado al confirmar el abordaje.
    ///
    /// Debe conservarse porque la ruta geométricamente más cercana puede
    /// cambiar entre muestras. Todas las observaciones de una sesión deben
    /// seguir utilizando la ruta con la que se confirmó el viaje.
    private var confirmedRouteID: String?

#if DEBUG
/// Permite probar el transporte MQTT sin esperar un viaje real.
///
/// Solo existe en compilaciones DEBUG y requiere explícitamente la variable
/// `MQTT_FORCE_ONBOARD=1` en el Scheme de Xcode. No puede utilizarse en una
/// compilación Release y no elimina la necesidad del consentimiento visible.
private let isForcedOnboardForMQTTTest =
    ProcessInfo.processInfo.environment[
        "MQTT_FORCE_ONBOARD"
    ] == "1"
#endif

    private let consentStorageKey =
        "rutautp.passive-tracking-consent"

    /// Construye el coordinador y sus dependencias.
    ///
    /// - Parameters:
    ///   - locationService: Servicio GPS compartido por toda la aplicación.
    ///   - motionService: Fuente de actividades físicas detectadas.
    ///   - repository: Repositorio que proporciona las rutas GTFS.
    ///   - observationPublisher: Publicador opcional inyectado, principalmente
    ///     utilizado por pruebas. Si no se proporciona, se intenta construir
    ///     uno MQTT usando las variables locales del Scheme de Xcode.
    ///
    /// Las credenciales nunca se encuentran escritas directamente en el código.
    init(
        locationService: LocationServiceProtocol,
        motionService: MotionActivityProviding =
            CoreMotionActivityService(),
        repository: GTFSRepository = .shared,
        initialRoutes: [DetectionRouteGeometry] = [],
        observationPublisher: ObservationPublishing? = nil,
        tripOccupancy: OccupancyService = OccupancyService(),
        detectionClock: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 },
        configurationProvider: () -> MQTTConfiguration? = MQTTConfiguration.fromEnvironment
    ) {
        self.locationService = locationService
        self.motionService = motionService
        self.repository = repository
        self.tripOccupancy = tripOccupancy
        self.detectionEngine = PassengerDetectionEngine(now: detectionClock)

        // En producción permanece vacío y las rutas se cargan desde GTFS.
        // Las pruebas pueden proporcionar geometrías pequeñas y deterministas.
        self.routes = initialRoutes

        if let observationPublisher {
            // Conserva el mock o implementación proporcionada externamente.
            self.observationPublisher = observationPublisher
        } else if let configuration = configurationProvider() {
            // Crea el publicador real solamente cuando están disponibles
            // MQTT_HOST, MQTT_PORT, MQTT_USERNAME y MQTT_PASSWORD.
            self.observationPublisher =
                MQTTObservationPublisher(
                    configuration: configuration
                )
        } else {
            // Sin canal configurado, la contribución queda deshabilitada.
            self.observationPublisher = nil
        }

        let storedConsent = UserDefaults.standard.bool(
            forKey: consentStorageKey
        )
        // Consultar el publicador resuelto, no el parámetro opcional: en el
        // arranque normal ese parámetro es nil aunque se haya creado MQTT.
        isEnabled = storedConsent && self.observationPublisher != nil

        if storedConsent && self.observationPublisher == nil {
            UserDefaults.standard.set(false, forKey: consentStorageKey)
            statusMessage = "Canal MQTT no configurado"
        }

        // El estado del canal se propaga en el momento en que cambia,
        // no cuando la siguiente muestra lo consulta.
        self.observationPublisher?.onStateChange =
            { [weak self] newState in
                self?.observationPublisherState = newState
            }
        refreshObservationPublisherState()
    }



    func startIfConsented() async {
        guard isEnabled else {
            return
        }

        await start(token: startGuard.begin())
    }

    func setContributionEnabled(
        _ enabled: Bool
    ) {
        guard !enabled || observationPublisher != nil else {
            UserDefaults.standard.set(false, forKey: consentStorageKey)
            isEnabled = false
            statusMessage = "Canal MQTT no configurado"
            return
        }

        UserDefaults.standard.set(
            enabled,
            forKey: consentStorageKey
        )

        isEnabled = enabled

        if enabled {
            beginStart(reintentarGTFS: true)
        } else {
            stop()
        }
    }

    /// Abre un arranque nuevo, cancelando el anterior si seguía pendiente.
    ///
    /// Iniciar dos veces no debe dejar dos observadores de ubicación ni dos de
    /// movimiento: el arranque previo se cancela y su testigo queda invalidado,
    /// así que aunque reanude no completará el trabajo.
    private func beginStart(reintentarGTFS: Bool = false) {
        startTask?.cancel()

        let token = startGuard.begin()

        startTask = Task { @MainActor [weak self] in
            await self?.start(token: token, reintentarGTFS: reintentarGTFS)
        }
    }

    /// Arranca la detección. `token` acredita que este arranque sigue vigente.
    ///
    /// El método suspende dos veces (permiso de ubicación y carga del feed), y
    /// en cada una hay que volver a comprobar el testigo y el consentimiento:
    /// es justo la ventana en la que el usuario puede desactivar la
    /// contribución y quedar, sin estas comprobaciones, con la detección viva.
    private func start(token: Int, reintentarGTFS: Bool = false) async {
        guard startGuard.isCurrent(token), isEnabled else {
            return
        }

        guard !isRunning else {
            return
        }

        // El intento explícito ya está en curso; no ofrecer otro botón
        // mientras el permiso o el catálogo siguen pendientes.
        errorCargaRutas = nil
        statusMessage = "Preparando detección pasiva"

        let authorization =
            await locationService.requestPermission()

        guard startGuard.isCurrent(token), isEnabled else {
            return
        }

        guard authorization.isAuthorized else {
            isEnabled = false

            UserDefaults.standard.set(
                false,
                forKey: consentStorageKey
            )

            statusMessage =
                "Se necesita permiso de ubicación"

            return
        }

        // En producción las rutas se cargan desde GTFS. Si una prueba ya
        // proporcionó geometrías controladas, se conservan sin reemplazarlas.
        if routes.isEmpty {
            let gtfsRoutes: [RutaGTFS]
            do {
                gtfsRoutes = try await repository.cargarRutas(reintentar: reintentarGTFS)
                guard !Task.isCancelled, startGuard.isCurrent(token), isEnabled else { return }
                errorCargaRutas = nil
            } catch {
                guard !Task.isCancelled, startGuard.isCurrent(token), isEnabled else { return }
                errorCargaRutas = error as? FalloCargaGTFS
                statusMessage = errorCargaRutas?.mensajeUsuario
                    ?? L.t("No se pudieron cargar las rutas. Vuelve a intentarlo.", "Couldn't load routes. Try again.")
                return
            }

            routes = gtfsRoutes.map {
                DetectionRouteGeometry(route: $0)
            }
        }

        guard startGuard.isCurrent(token), isEnabled else {
            return
        }

        guard !routes.isEmpty else {
            statusMessage =
                L.t("El catálogo GTFS no contiene rutas", "The GTFS catalog contains no routes")
            return
        }

        isRunning = true
        appEnSegundoPlano = UIApplication.shared.applicationState == .background
        statusMessage = "Analizando movilidad"

        observeAppLifecycle()
        startMotionObservation()
        startLocationObservation()

        #if DEBUG
        print(
            "[PassiveTracking] Iniciado con " +
            "\(routes.count) rutas GTFS"
        )
        #endif
    }

    private func startMotionObservation() {
        motionTask?.cancel()

        let activityStream =
            motionService.activities()

        motionService.start()

        motionTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            for await activity in activityStream {
                guard !Task.isCancelled else {
                    break
                }

                self.motionActivity = activity

                #if DEBUG
                print(
                    "[PassiveTracking] Movimiento: " +
                    activity.rawValue
                )
                #endif
            }
        }
    }

    private func startLocationObservation() {
        locationTask?.cancel()

        let locationStream =
            locationService.currentLocation()

        locationService.startUpdating()

        locationTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            for await location in locationStream {
                guard !Task.isCancelled else {
                    break
                }

                self.process(
                    location,
                    activity: self.motionActivity
                )
            }
        }
    }

    /// Procesa conjuntamente una lectura GPS y una actividad física.
    ///
    /// Este método tiene visibilidad interna para que XCTest pueda verificar
    /// la orquestación completa con muestras controladas. En producción solo
    /// es invocado por el stream de ubicación del coordinador.
    ///
    /// - Parameters:
    ///   - location: Lectura GPS con coordenadas, velocidad en m/s, rumbo en
    ///     grados, precisión horizontal en metros y timestamp.
    ///   - activity: Actividad detectada por Core Motion para esa muestra.
    func process(
        _ location: CLLocation,
        activity: DetectedMotionActivity
    ) {
        latestLocation = location
        guard isEnabled else { return }
        guard !waitingForNewTrip else { return }
        let candidateRoutes = selectedTripRoute.map { [$0] } ?? routes
        guard let candidate =
            RouteCandidateMatcher.closestMatch(
                for: location,
                routes: candidateRoutes
            )
        else {
            candidateLine = nil
            distanceToRoute = nil
            shouldPublish = false
            statusMessage =
                "Sin rutas próximas"
            return
        }

#if DEBUG
// Este bypass verifica únicamente conexión, serialización y publicación.
// Las reglas reales de detección ya están cubiertas por XCTest.
if isForcedOnboardForMQTTTest {
    processForcedOnboardForMQTTTest(
        location: location,
        candidate: candidate,
        activity: activity
    )

    return
}
#endif

        let sample = PassengerDetectionSample(
            timestamp:
                location.timestamp.timeIntervalSince1970,

            speed:
                max(0, location.speed),

            horizontalAccuracy:
                location.horizontalAccuracy,

            distanceToRoute:
                candidate.distanceToRoute,

            headingDifference:
                candidate.headingDifference,

            distanceToNearestStop:
                candidate.distanceToNearestStop,

            motionActivity:
                activity
        )

        let decision =
            detectionEngine.process(sample, routeID: candidate.routeID)

        detectionState = decision.state
        shouldPublish = decision.shouldPublish && !appEnSegundoPlano

        if decision.didConfirmBoarding {
            confirmedLine = candidate.linea
            confirmedRouteID = candidate.routeID

            // Cada abordaje confirmado recibe un UUID de sesión nuevo.
            // lowercased() solo normaliza el formato enviado al backend.
            let sessionID =
                UUID().uuidString.lowercased()

            observationSessionID = sessionID
            sesionPausadaPorBackground = appEnSegundoPlano
            if !appEnSegundoPlano {
                observationPublisher?.start(sessionID: sessionID, linea: candidate.linea)
            }

            statusMessage =
                "Abordaje probable: línea " +
                candidate.linea

        } else if decision.didConfirmAlighting {
            if selectedTripRoute != nil {
                endTrip()
                statusMessage = "Descenso detectado. Viaje terminado."
                return
            }
            // El descenso confirmado finaliza inmediatamente la conexión
            // correspondiente al viaje y descarta sus identificadores locales.
            stopObservationSession()

            confirmedLine = nil

            statusMessage =
                "Descenso detectado"

        } else {
            statusMessage = message(
                for: decision.state,
                candidateLine: candidate.linea
            )
        }

        // Solo PassengerDetectionEngine puede autorizar una transmisión.
        // Se utiliza el routeID confirmado al abordar, no la ruta candidata
        // de la muestra actual, para conservar la identidad del viaje.
        if
            decision.shouldPublish,
            !appEnSegundoPlano,
            observationSessionID != nil,
            let confirmedRouteID
        {
            reanudarSesionPausadaSiSePuede()
            observationPublisher?.publish(
                location: location,
                routeID: confirmedRouteID,
                activity: activity
            )
            if selectedTripRoute != nil, tripOccupancy.hasPendingTripReport { tripOccupancy.start() }
        }

        // Copia el estado actualizado del publicador a la propiedad observable.
        refreshObservationPublisherState()


        #if DEBUG
        print(
            "[PassiveTracking] Estado: " +
            "\(decision.state.rawValue), " +
            "línea: \(candidate.linea), " +
            "distancia: " +
            "\(Int(candidate.distanceToRoute)) m, " +
            "publicar: \(decision.shouldPublish)"
        )
        #endif
    }

    func stop() {
        // Invalida cualquier arranque pendiente antes de nada: si se revocó el
        // consentimiento, la continuación del arranque no debe reanudar nada al
        // terminar su espera.
        startTask?.cancel()
        startTask = nil
        startGuard.invalidate()

        locationTask?.cancel()
        locationTask = nil

        motionTask?.cancel()
        motionTask = nil

        motionService.stop()
        detectionEngine.reset()

        removeAppLifecycleObservers()

        // Revocar el consentimiento o detener el coordinador también debe
        // finalizar cualquier sesión MQTT que todavía permanezca activa.
        stopObservationSession()

        isRunning = false
        detectionState = .idle
        motionActivity = .unknown
        candidateLine = nil
        confirmedLine = nil
        distanceToRoute = nil
        shouldPublish = false
        selectedTripRoute = nil
        tripStartedAt = nil
        boardingPlace = nil
        boardingPoint = nil
        tripOccupancy.clearTripReport()
        waitingForNewTrip = false
        statusMessage =
            "Contribución desactivada"

        #if DEBUG
        print("[PassiveTracking] Detenido")
        #endif
    }


#if DEBUG
/// Fuerza temporalmente una sesión `onboard` para una prueba MQTT local.
///
/// El método continúa necesitando:
/// - Consentimiento activado.
/// - Permiso de ubicación.
/// - Una ruta GTFS próxima.
/// - Configuración MQTT en el Scheme.
///
/// No modifica el algoritmo Release ni se incluye en el binario final.
private func processForcedOnboardForMQTTTest(
    location: CLLocation,
    candidate: RouteCandidateMatch,
    activity: DetectedMotionActivity
) {
    guard !appEnSegundoPlano else { return }
    if observationSessionID == nil {
        let sessionID =
            UUID().uuidString.lowercased()

        observationSessionID = sessionID
        confirmedRouteID = candidate.routeID
        confirmedLine = candidate.linea

        observationPublisher?.start(
            sessionID: sessionID,
            linea: candidate.linea
        )

        print(
            "[PassiveTracking][DEBUG] " +
            "Abordaje forzado para probar MQTT. " +
            "Sesión: \(sessionID), " +
            "línea: \(candidate.linea)"
        )
    }

    detectionState = .onboard
    shouldPublish = true
    reanudarSesionPausadaSiSePuede()

    observationPublisher?.publish(
        location: location,
        routeID: confirmedRouteID ?? candidate.routeID,
        activity: activity
    )

    refreshObservationPublisherState()

    statusMessage =
        "Prueba MQTT activa: línea " +
        candidate.linea

    print(
        "[PassiveTracking][DEBUG] " +
        "Observación entregada al publicador"
    )
}
#endif



    /// Finaliza el envío y descarta los identificadores locales del viaje.
    /// No solicita el borrado de observaciones ya recibidas por el backend.
    ///
    /// Se llama al confirmar el descenso, desactivar la contribución o detener
    /// completamente el coordinador. Ningún UUID se reutiliza entre viajes.
    private func stopObservationSession() {
        sesionPausadaPorBackground = false
        tripOccupancy.stop()
        observationPublisher?.stop()

        observationSessionID = nil
        confirmedRouteID = nil

        refreshObservationPublisherState()
    }

    // MARK: - Ciclo de vida de la app

    /// Registra los observadores de segundo plano/foreground.
    private func observeAppLifecycle() {
        guard backgroundObserver == nil else {
            return
        }

        backgroundObserver = NotificationCenter
            .default
            .addObserver(
                forName:
                    UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.pauseObservationSessionForBackground()
                }
            }

        foregroundObserver = NotificationCenter
            .default
            .addObserver(
                forName:
                    UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.resumeObservationSessionIfNeeded()
                }
            }
    }

    private func removeAppLifecycleObservers() {
        if let backgroundObserver {
            NotificationCenter
                .default
                .removeObserver(backgroundObserver)

            self.backgroundObserver = nil
        }

        if let foregroundObserver {
            NotificationCenter
                .default
                .removeObserver(foregroundObserver)

            self.foregroundObserver = nil
        }
    }

    /// Corta la publicación al pasar a segundo plano.
    ///
    /// iOS suspende el proceso pocos segundos después: el socket MQTT
    /// moriría sin desconexión limpia y el GPS se detendría. Se cierra
    /// la conexión conservando el `sessionID` y la ruta confirmada,
    /// porque el viaje sigue vigente y debe poder reanudarse.
    ///
    /// La existencia de la sesión es la condición suficiente: si no hay
    /// viaje en curso no hay nada que pausar, con o sin coordinador vivo.
    ///
    /// Visibilidad interna para que XCTest verifique la pausa/reanudación
    /// sin simular el ciclo de vida real de la app.
    func pauseObservationSessionForBackground() {
        appEnSegundoPlano = true
        shouldPublish = false
        tripOccupancy.stop()
        guard observationSessionID != nil, !sesionPausadaPorBackground else {
            return
        }

        sesionPausadaPorBackground = true
        observationPublisher?.stop()

        refreshObservationPublisherState()

        statusMessage =
            "Publicación pausada: app en segundo plano"
    }

    /// Reanuda la publicación si el viaje detectado sigue vigente.
    ///
    /// Se reutiliza el mismo `sessionID`: la reanudación pertenece al
    /// mismo viaje y cuenta MQTT. La siguiente muestra GPS que apruebe el
    /// detector vuelve a transmitirse sin esperar un nuevo abordaje.
    ///
    /// Un posible descenso no autoriza envío todavía. Se conserva la pausa
    /// hasta que `process` reciba una decisión que vuelva a autorizarlo.
    func resumeObservationSessionIfNeeded() {
        appEnSegundoPlano = false
        reanudarSesionPausadaSiSePuede()
    }

    private func reanudarSesionPausadaSiSePuede() {
        guard
            isEnabled, !appEnSegundoPlano, sesionPausadaPorBackground,
            detectionState == .onboard,
            let sessionID = observationSessionID,
            let linea = confirmedLine, confirmedRouteID != nil
        else {
            return
        }

        // Consumir la pausa antes de start: ni foreground repetido ni las
        // siguientes muestras deben duplicar conexiones o forzar un reenvío.
        sesionPausadaPorBackground = false
        observationPublisher?.start(
            sessionID: sessionID,
            linea: linea
        )

        refreshObservationPublisherState()

        statusMessage =
            "Viaje detectado en \(linea)"
    }

    /// Actualiza la propiedad observable con el estado real del publicador.
    ///
    /// CocoaMQTT cambia su estado mediante callbacks asíncronos. El coordinador
    /// lo consulta después de cada operación o muestra procesada para que la
    /// interfaz pueda presentar el resultado más reciente.
    private func refreshObservationPublisherState() {
        observationPublisherState =
            observationPublisher?.state ?? .inactive
    }


    private func message(
        for state: PassengerDetectionState,
        candidateLine: String
    ) -> String {
        switch state {
        case .idle:
            return "Sin viaje detectado"

        case .approachingStop:
            return "Cerca de un paradero"

        case .boardingCandidate:
            return "Posible abordaje en \(candidateLine)"

        case .onboard:
            return "Viaje detectado en \(candidateLine)"

        case .alightingCandidate:
            return "Comprobando posible descenso"
        }
    }
}


/// Referencias declaradas, no paraderos verificados. No se infiere que la
/// ubicación actual del teléfono sea donde el pasajero subió anteriormente.
struct BoardingPoint: Codable, Equatable {
    let latitude: Double
    let longitude: Double

    init?(coordinate: CLLocationCoordinate2D) {
        guard coordinate.latitude.isFinite, coordinate.longitude.isFinite,
              CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct BoardingPlaceNote: Codable, Identifiable {
    let id: UUID
    let routeID: String
    let line: String
    let place: String
    // Opcional para poder seguir leyendo las referencias anteriores sin mapa.
    let point: BoardingPoint?
    let recordedAt: Date
}

enum BoardingPlaceStore {
    static let key = "rutautp.boarding-place-notes.v1"

    static func normalized(_ text: String) -> String? {
        let value = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        return value.isEmpty ? nil : value
    }

    static func notes(defaults: UserDefaults = .standard) -> [BoardingPlaceNote] {
        guard let data = defaults.data(forKey: key),
              let notes = try? JSONDecoder().decode([BoardingPlaceNote].self, from: data) else { return [] }
        return notes
    }

    static func save(routeID: String, line: String, place: String, point: BoardingPoint? = nil,
                     defaults: UserDefaults = .standard) {
        let place = normalized(place)
        guard place != nil || point != nil else { return }
        var records = notes(defaults: defaults)
        records.append(BoardingPlaceNote(id: UUID(), routeID: routeID, line: line,
                                         place: place ?? "", point: point, recordedAt: Date()))
        // Historial local acotado para preparar el futuro catálogo de paraderos.
        if let data = try? JSONEncoder().encode(Array(records.suffix(200))) {
            defaults.set(data, forKey: key)
        }
    }
}
