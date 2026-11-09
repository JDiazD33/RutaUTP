import Foundation
import CoreLocation
import Combine
import UIKit

@MainActor
final class PassiveTrackingCoordinator: ObservableObject {

    @Published private(set) var isEnabled: Bool
    @Published private(set) var isRunning = false
    @Published private(set) var errorCargaRutas: FalloCargaGTFS?

    @Published var detectionState:
        PassengerDetectionState = .idle

    @Published private(set) var motionActivity:
        DetectedMotionActivity = .unknown

    @Published var confirmedLine: String?
    @Published var shouldPublish = false

    /// Estado actual del canal utilizado para publicar observaciones.
    ///
    /// Esta propiedad permite que SwiftUI muestre si MQTT está conectando,
    /// conectado, inactivo o si ocurrió algún error.
    @Published private(set) var observationPublisherState:
        ObservationPublisherState = .inactive

    @Published var contributionStatus: ContributionStatus = .disabled

    /// Traducir al leer registra el idioma actual sin recrear el viaje.
    var statusMessage: String { contributionStatus.message }

    /// Indica si esta instalación tiene un canal MQTT utilizable.
    /// Sin publicador no se deben encender GPS ni Core Motion, porque ninguna
    /// observación podría salir del dispositivo.
    var isPublisherConfigured: Bool {
        observationPublisher != nil
    }

    @Published private(set) var selectedTripRoute: DetectionRouteGeometry?
    @Published private(set) var tripStartedAt: Date?
    @Published private(set) var boardingPlace: String?
    @Published private(set) var falloAlGuardarSubida = false
    @Published private(set) var boardingPoint: BoardingPoint?
    @Published var latestLocation: CLLocation?
    let tripOccupancy: OccupancyService
    var waitingForNewTrip = false

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
        falloAlGuardarSubida = !BoardingPlaceStore.save(routeID: route.id, line: route.linea,
                                place: self.boardingPlace ?? "", point: boardingPoint)
        waitingForNewTrip = false
        contributionStatus = .waitingForLine(route.linea)
        if let occupancy { updateTripOccupancy(occupancy) }
    }

    /// Reintenta únicamente la referencia pendiente; no reinicia el viaje ni GPS/MQTT.
    func reintentarGuardarSubida() {
        guard falloAlGuardarSubida, let route = selectedTripRoute else { return }
        falloAlGuardarSubida = !BoardingPlaceStore.save(routeID: route.id, line: route.linea,
            place: boardingPlace ?? "", point: boardingPoint)
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
        falloAlGuardarSubida = false
        boardingPoint = nil
        detectionEngine.reset()
        detectionState = .idle
        confirmedLine = nil
        shouldPublish = false
        waitingForNewTrip = true
        contributionStatus = .tripEnded
    }

    private let locationService:
        LocationServiceProtocol

    private let motionService:
        MotionActivityProviding

    private var repository:
        GTFSRepository

    /// Componente encargado de transmitir observaciones autorizadas.
    ///
    /// Sin configuración la contribución permanece deshabilitada. Durante
    /// las pruebas puede sustituirse por un publicador simulado.
    let observationPublisher:
        ObservationPublishing?

    var detectionEngine: PassengerDetectionEngine

    var routes:
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
    var backgroundObserver: NSObjectProtocol?

    var foregroundObserver: NSObjectProtocol?
    var appEnSegundoPlano = false
    /// La sesión sigue siendo del mismo viaje, pero el canal fue detenido.
    /// Si foreground llega durante un posible descenso, una muestra posterior
    /// puede volver a autorizar el envío sin confirmar otro abordaje.
    var sesionPausadaPorBackground = false

    /// UUID temporal de la sesión de viaje.
    ///
    /// Se crea al confirmar el abordaje y se descarta del estado local al terminar
    /// la sesión. MQTT lo vincula a la cuenta autenticada; rotarlo no impide
    /// correlacionar viajes ni elimina las observaciones ya enviadas al backend.
    var observationSessionID: String?

    /// Identificador GTFS fijado al confirmar el abordaje.
    ///
    /// Debe conservarse porque la ruta geométricamente más cercana puede
    /// cambiar entre muestras. Todas las observaciones de una sesión deben
    /// seguir utilizando la ruta con la que se confirmó el viaje.
    var confirmedRouteID: String?

#if DEBUG
/// Permite probar el transporte MQTT sin esperar un viaje real.
///
/// Solo existe en compilaciones DEBUG y requiere explícitamente la variable
/// `MQTT_FORCE_ONBOARD=1` en el Scheme de Xcode. No puede utilizarse en una
/// compilación Release y no elimina la necesidad del consentimiento visible.
let isForcedOnboardForMQTTTest =
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
        motionService: MotionActivityProviding? = nil,
        repository: GTFSRepository = TransporteApp.repositorio,
        initialRoutes: [DetectionRouteGeometry] = [],
        observationPublisher: ObservationPublishing? = nil,
        tripOccupancy: OccupancyService? = nil,
        detectionClock: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 },
        configurationProvider: () -> MQTTConfiguration? = MQTTConfiguration.contributionFromEnvironment,
        preserveStoredConsentWhenUnconfigured: Bool = MQTTConfiguration.isReadOnlyTrial
            || MQTTConfiguration.fromEnvironment()?.isReadOnly == true
    ) {
        self.locationService = locationService
        self.motionService = motionService ?? CoreMotionActivityService()
        self.repository = repository
        self.tripOccupancy = tripOccupancy ?? OccupancyService()
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

        let storedConsent = PreferenciasApp.boolGuardado(para: consentStorageKey) ?? false
        // Consultar el publicador resuelto, no el parámetro opcional: en el
        // arranque normal ese parámetro es nil aunque se haya creado MQTT.
        isEnabled = storedConsent && self.observationPublisher != nil

        if storedConsent && self.observationPublisher == nil {
            if !preserveStoredConsentWhenUnconfigured {
                UserDefaults.standard.set(false, forKey: consentStorageKey)
            }
            contributionStatus = .mqttNotConfigured
        }

        // El estado del canal se propaga en el momento en que cambia,
        // no cuando la siguiente muestra lo consulta.
        self.observationPublisher?.onStateChange =
            { [weak self] newState in
                self?.observationPublisherState = newState
            }
        refreshObservationPublisherState()
        MQTTConfiguration.trialLog("contributionConfiguration", [
            "configured": isPublisherConfigured ? 1 : 0, "enabled": isEnabled ? 1 : 0
        ])
    }

    func startIfConsented() async {
        guard isEnabled else {
            return
        }

        await start(token: startGuard.begin())
    }

    /// Conserva el consentimiento; invalida tareas y sesiones del catálogo anterior.
    func actualizarModoTransporte() {
        stop()
        repository = TransporteApp.repositorio
        routes = []
        errorCargaRutas = nil
        if TransporteApp.rutasUTPPendientes {
            contributionStatus = .feedPending
        } else if isEnabled {
            beginStart()
        }
    }

    func setContributionEnabled(
        _ enabled: Bool
    ) {
        guard !enabled || observationPublisher != nil else {
            UserDefaults.standard.set(false, forKey: consentStorageKey)
            isEnabled = false
            contributionStatus = .mqttNotConfigured
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

        guard !TransporteApp.rutasUTPPendientes else {
            contributionStatus = .feedPending
            return
        }

        guard !isRunning else {
            return
        }

        // El intento explícito ya está en curso; no ofrecer otro botón
        // mientras el permiso o el catálogo siguen pendientes.
        errorCargaRutas = nil
        contributionStatus = .preparing

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

            contributionStatus =
                .needsPermission

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
                contributionStatus = .catalogFailure(errorCargaRutas)
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
            contributionStatus =
                .emptyCatalog
            return
        }

        isRunning = true
        appEnSegundoPlano = UIApplication.shared.applicationState == .background
        contributionStatus = .analyzing

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
            locationService.currentLocation(requirement: .navigation)

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
        confirmedLine = nil
        shouldPublish = false
        selectedTripRoute = nil
        tripStartedAt = nil
        boardingPlace = nil
        falloAlGuardarSubida = false
        boardingPoint = nil
        tripOccupancy.clearTripReport()
        waitingForNewTrip = false
        contributionStatus =
            .disabled

        #if DEBUG
        print("[PassiveTracking] Detenido")
        #endif
    }

    /// Finaliza el envío y descarta los identificadores locales del viaje.
    /// No solicita el borrado de observaciones ya recibidas por el backend.
    ///
    /// Se llama al confirmar el descenso, desactivar la contribución o detener
    /// completamente el coordinador. Ningún UUID se reutiliza entre viajes.
    func stopObservationSession() {
        sesionPausadaPorBackground = false
        tripOccupancy.stop()
        observationPublisher?.stop()

        observationSessionID = nil
        confirmedRouteID = nil

        refreshObservationPublisherState()
    }

    /// Actualiza la propiedad observable con el estado real del publicador.
    ///
    /// CocoaMQTT cambia su estado mediante callbacks asíncronos. El coordinador
    /// lo consulta después de cada operación o muestra procesada para que la
    /// interfaz pueda presentar el resultado más reciente.
    func refreshObservationPublisherState() {
        observationPublisherState =
            observationPublisher?.state ?? .inactive
    }

    func message(
        for state: PassengerDetectionState,
        candidateLine: String
    ) -> ContributionStatus {
        switch state {
        case .idle: return .noTrip
        case .approachingStop: return .approachingStop
        case .boardingCandidate: return .possibleBoarding(candidateLine)
        case .onboard: return .detected(candidateLine)
        case .alightingCandidate: return .possibleAlighting
        }
    }
}
