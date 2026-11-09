//
//  PassiveTrackingCoordinator+Deteccion.swift
//  RutaUTP
//
//  Procesamiento de muestras GPS y de actividad del coordinador pasivo.
//

import Foundation
import CoreLocation

extension PassiveTrackingCoordinator {

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
                shouldPublish = false
            contributionStatus =
                .noNearbyRoutes
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

            contributionStatus =
                .probableBoarding(candidate.linea)

        } else if decision.didConfirmAlighting {
            if selectedTripRoute != nil {
                endTrip()
                contributionStatus = .alightingTripEnded
                return
            }
            // El descenso confirmado finaliza inmediatamente la conexión
            // correspondiente al viaje y descarta sus identificadores locales.
            stopObservationSession()

            confirmedLine = nil

            contributionStatus =
                .alighting

        } else {
            contributionStatus = message(
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

    contributionStatus =
        .mqttTest(candidate.linea)

    print(
        "[PassiveTracking][DEBUG] " +
        "Observación entregada al publicador"
    )
}
#endif
}
