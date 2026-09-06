import Foundation
import CoreLocation
import Combine

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

    @Published private(set) var statusMessage =
        "Contribución desactivada"

    private let locationService:
        LocationServiceProtocol

    private let motionService:
        MotionActivityProviding

    private let repository:
        GTFSRepository

    private var detectionEngine =
        PassengerDetectionEngine()

    private var routes:
        [DetectionRouteGeometry] = []

    private var locationTask:
        Task<Void, Never>?

    private var motionTask:
        Task<Void, Never>?

    private let consentStorageKey =
        "rutautp.passive-tracking-consent"

    init(
        locationService: LocationServiceProtocol,
        motionService: MotionActivityProviding =
            CoreMotionActivityService(),
        repository: GTFSRepository = .shared
    ) {
        self.locationService = locationService
        self.motionService = motionService
        self.repository = repository

        isEnabled = UserDefaults.standard.bool(
            forKey: consentStorageKey
        )
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

        let gtfsRoutes = await repository.rutas()

        routes = gtfsRoutes.map {
            DetectionRouteGeometry(route: $0)
        }

        guard !routes.isEmpty else {
            statusMessage =
                "No se pudieron cargar las rutas GTFS"
            return
        }

        isRunning = true
        statusMessage = "Analizando movilidad"

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

                self.process(location)
            }
        }
    }

    private func process(
        _ location: CLLocation
    ) {
        guard let candidate =
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

        candidateLine = candidate.linea
        distanceToRoute =
            candidate.distanceToRoute

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
                motionActivity
        )

        let decision =
            detectionEngine.process(sample)

        detectionState = decision.state
        shouldPublish = decision.shouldPublish

        if decision.didConfirmBoarding {
            confirmedLine = candidate.linea

            statusMessage =
                "Abordaje probable: línea " +
                candidate.linea
        } else if decision.didConfirmAlighting {
            confirmedLine = nil

            statusMessage =
                "Descenso detectado"
        } else {
            statusMessage = message(
                for: decision.state,
                candidateLine: candidate.linea
            )
        }

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
