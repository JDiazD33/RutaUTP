import Foundation
import CoreLocation
import Combine
import UIKit

@MainActor
final class PassiveTrackingCoordinator: ObservableObject {

    @Published private(set) var isEnabled: Bool
    @Published private(set) var isRunning = false

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

    private let locationService:
        LocationServiceProtocol

    private let motionService:
        MotionActivityProviding

    private let repository:
        GTFSRepository
    
    /// Componente encargado de transmitir observaciones autorizadas.
    ///
    /// Es opcional para que la detección pasiva pueda funcionar aunque las
    /// variables MQTT todavía no estén configuradas. Durante las pruebas
    /// unitarias también podrá sustituirse por un publicador simulado.
    private let observationPublisher:
        ObservationPublishing?
    
    
    private var detectionEngine =
        PassengerDetectionEngine()

    private var routes:
        [DetectionRouteGeometry] = []

    private var locationTask:
        Task<Void, Never>?

    private var motionTask:
        Task<Void, Never>?

    /// Observadores del ciclo de vida de la app.
    ///
    /// iOS suspende el proceso poco después de pasar a segundo plano:
    /// el socket MQTT y el GPS mueren sin despedida. Detectar la
    /// transición permite cerrar la publicación de forma limpia y
    /// reanudarla cuando el usuario vuelve a la app.
    private var backgroundObserver: NSObjectProtocol?

    private var foregroundObserver: NSObjectProtocol?

    /// Identificador anónimo y temporal de la sesión de viaje.
    ///
    /// Se crea al confirmar el abordaje y se elimina al confirmar el descenso.
    /// No identifica permanentemente al usuario ni al dispositivo.
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
        observationPublisher: ObservationPublishing? = nil
    ) {
        self.locationService = locationService
        self.motionService = motionService
        self.repository = repository
        
        // En producción permanece vacío y las rutas se cargan desde GTFS.
        // Las pruebas pueden proporcionar geometrías pequeñas y deterministas.
        self.routes = initialRoutes

        if let observationPublisher {
            // Conserva el mock o implementación proporcionada externamente.
            self.observationPublisher = observationPublisher
        } else if let configuration =
            MQTTConfiguration.fromEnvironment() {
            // Crea el publicador real solamente cuando están disponibles
            // MQTT_HOST, MQTT_PORT, MQTT_USERNAME y MQTT_PASSWORD.
            self.observationPublisher =
                MQTTObservationPublisher(
                    configuration: configuration
                )
        } else {
            // La detección seguirá funcionando localmente, pero no transmitirá
            // ubicaciones mientras la configuración MQTT esté ausente.
            self.observationPublisher = nil
        }

        isEnabled = UserDefaults.standard.bool(
            forKey: consentStorageKey
        )

        // El estado del canal se propaga en el momento en que cambia,
        // no cuando la siguiente muestra lo consulta.
        observationPublisher?.onStateChange =
            { [weak self] newState in
                self?.observationPublisherState = newState
            }
    }
    
    

    func startIfConsented() async {
        guard isEnabled else {
            return
        }

        await start()
    }

    func setContributionEnabled(
        _ enabled: Bool
    ) {
        UserDefaults.standard.set(
            enabled,
            forKey: consentStorageKey
        )

        isEnabled = enabled

        if enabled {
            Task {
                await start()
            }
        } else {
            stop()
        }
    }

    private func start() async {
        guard !isRunning else {
            return
        }

        statusMessage = "Preparando detección pasiva"

        let authorization =
            await locationService.requestPermission()

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
            let gtfsRoutes = await repository.rutas()

            routes = gtfsRoutes.map {
                DetectionRouteGeometry(route: $0)
            }
        }
        
        
        guard !routes.isEmpty else {
            statusMessage =
                "No se pudieron cargar las rutas GTFS"
            return
        }

        isRunning = true
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
    ) {        guard let candidate =
            RouteCandidateMatcher.closestMatch(
                for: location,
                routes: routes
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
            detectionEngine.process(sample)

        detectionState = decision.state
        shouldPublish = decision.shouldPublish

        if decision.didConfirmBoarding {
            confirmedLine = candidate.linea
            confirmedRouteID = candidate.routeID

            // Cada abordaje confirmado recibe una sesión nueva y anónima.
            // lowercased() solo normaliza el formato enviado al backend.
            let sessionID =
                UUID().uuidString.lowercased()

            observationSessionID = sessionID

            observationPublisher?.start(
                sessionID: sessionID,
                linea: candidate.linea
            )

            statusMessage =
                "Abordaje probable: línea " +
                candidate.linea

        } else if decision.didConfirmAlighting {
            // El descenso confirmado finaliza inmediatamente la conexión
            // correspondiente al viaje y elimina sus identificadores.
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
            observationSessionID != nil,
            let confirmedRouteID
        {
            observationPublisher?.publish(
                location: location,
                routeID: confirmedRouteID,
                activity: activity
            )
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
    
    

    /// Finaliza el envío del viaje actual y elimina sus identificadores.
    ///
    /// Se llama al confirmar el descenso, desactivar la contribución o detener
    /// completamente el coordinador. Ningún UUID se reutiliza entre viajes.
    private func stopObservationSession() {
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
        guard observationSessionID != nil else {
            return
        }

        observationPublisher?.stop()

        refreshObservationPublisherState()

        statusMessage =
            "Publicación pausada: app en segundo plano"
    }

    /// Reanuda la publicación si el viaje detectado sigue vigente.
    ///
    /// Se reutiliza el mismo `sessionID`: la reanudación pertenece al
    /// mismo viaje anónimo. La siguiente muestra GPS que apruebe el
    /// detector vuelve a transmitirse sin esperar un nuevo abordaje.
    ///
    /// Tras `stop()` todo queda limpio (`idle`, sin sesión), así que
    /// las condiciones de viaje bastan para decidir si corresponde
    /// reanudar.
    func resumeObservationSessionIfNeeded() {
        guard
            detectionState == .onboard,
            let sessionID = observationSessionID,
            let linea = confirmedLine
        else {
            return
        }

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
