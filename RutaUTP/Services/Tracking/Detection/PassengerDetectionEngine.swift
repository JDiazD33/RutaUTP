import Foundation

struct PassengerDetectionEngine {

    private(set) var state:
        PassengerDetectionState = .idle

    private let thresholds:
        PassengerDetectionThresholds
    private let now: () -> TimeInterval

    private var boardingEvidenceCount = 0
    private var alightingEvidenceCount = 0
    private var ultimaFechaProcesada: TimeInterval?
    private var rutaDeLaEvidencia: String?

    init(
        thresholds: PassengerDetectionThresholds = .default,
        now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }
    ) {
        self.thresholds = thresholds
        self.now = now
    }

    mutating func process(
        _ sample: PassengerDetectionSample,
        routeID: String? = nil
    ) -> PassengerDetectionDecision {
        guard sample.timestamp.isFinite else {
            return decision(shouldPublish: false)
        }

        // Una entrega repetida o atrasada no es evidencia nueva, aunque haya
        // cambiado Core Motion o la ruta candidata. Tampoco rompe la secuencia.
        if let ultimaFechaProcesada, sample.timestamp <= ultimaFechaProcesada {
            return decision(shouldPublish: false)
        }

        let ahora = now()
        guard ahora.isFinite,
              ahora - sample.timestamp <= thresholds.maximumSampleAge,
              sample.timestamp - ahora <= thresholds.maximumFutureSkew else {
            // Una fecha corrupta no mueve la referencia ni altera evidencia
            // reciente. El siguiente fix válido todavía comprueba el hueco.
            return decision(shouldPublish: false)
        }

        if let ultimaFechaProcesada,
           sample.timestamp - ultimaFechaProcesada > thresholds.maximumEvidenceInterval {
            descartarEvidenciaCandidata()
        }
        // Una lectura nueva imprecisa interrumpe continuidad y queda consumida:
        // otra entrega del mismo fix con distinta actividad no puede recuperarla.
        ultimaFechaProcesada = sample.timestamp
        guard
            sample.horizontalAccuracy >= 0,
            sample.horizontalAccuracy <=
                thresholds.maximumAccuracy
        else {
            descartarEvidenciaCandidata()
            return decision(shouldPublish: false)
        }

        let isNearRoute =
            sample.distanceToRoute <=
            thresholds.maximumDistanceToRoute

        let isHeadingAligned =
            sample.headingDifference <=
            thresholds.maximumHeadingDifference

        let isNearStop =
            sample.distanceToNearestStop <=
            thresholds.maximumDistanceToStop

        let hasVehicleSpeed =
            sample.speed >=
                thresholds.minimumVehicleSpeed &&
            sample.speed <=
                thresholds.maximumVehicleSpeed

        let hasCompatibleVehicleActivity =
            sample.motionActivity == .automotive ||
            sample.motionActivity == .unknown

        let hasVehicleEvidence =
            isNearRoute &&
            isHeadingAligned &&
            hasVehicleSpeed &&
            hasCompatibleVehicleActivity

        let hasWalkingEvidence =
            sample.motionActivity == .walking ||
            sample.motionActivity == .running

        let isApproachingStop =
            isNearStop &&
            (
                sample.motionActivity == .walking ||
                sample.motionActivity == .stationary
            )

        var confirmedBoarding = false
        var confirmedAlighting = false

        switch state {
        case .idle:
            if hasVehicleEvidence {
                boardingEvidenceCount = 1
                rutaDeLaEvidencia = routeID
                state = .boardingCandidate
            } else if isApproachingStop {
                state = .approachingStop
            }

        case .approachingStop:
            if hasVehicleEvidence {
                boardingEvidenceCount = 1
                rutaDeLaEvidencia = routeID
                state = .boardingCandidate
            } else if !isNearStop {
                state = .idle
            }

        case .boardingCandidate:
            if hasVehicleEvidence {
                // La identidad se comprueba después de aceptar el timestamp.
                // Cambiar ruta no debe borrar la barrera contra lecturas viejas.
                if rutaDeLaEvidencia == routeID {
                    boardingEvidenceCount += 1
                } else {
                    boardingEvidenceCount = 1
                    rutaDeLaEvidencia = routeID
                }

                if boardingEvidenceCount >=
                    thresholds.boardingEvidenceRequired {
                    state = .onboard
                    boardingEvidenceCount = 0
                    rutaDeLaEvidencia = nil
                    confirmedBoarding = true
                }
            } else {
                boardingEvidenceCount = 0
                rutaDeLaEvidencia = nil
                state = isApproachingStop
                    ? .approachingStop
                    : .idle
            }

        case .onboard:
            if hasWalkingEvidence {
                alightingEvidenceCount = 1
                state = .alightingCandidate
            }

        case .alightingCandidate:
            if hasVehicleEvidence {
                alightingEvidenceCount = 0
                state = .onboard
            } else if hasWalkingEvidence {
                alightingEvidenceCount += 1

                if alightingEvidenceCount >=
                    thresholds.alightingEvidenceRequired {
                    state = .idle
                    alightingEvidenceCount = 0
                    confirmedAlighting = true
                }
            } else {
                alightingEvidenceCount = 0
                state = .onboard
            }
        }

        return PassengerDetectionDecision(
            state: state,
            shouldPublish: state == .onboard,
            didConfirmBoarding: confirmedBoarding,
            didConfirmAlighting: confirmedAlighting
        )
    }

    mutating func reset() {
        state = .idle
        boardingEvidenceCount = 0
        alightingEvidenceCount = 0
        ultimaFechaProcesada = nil
        rutaDeLaEvidencia = nil
    }

    /// La falta de continuidad invalida contadores, sin inferir un descenso
    /// ni perder el viaje confirmado. Un posible descenso sigue esperando
    /// evidencia nueva antes de autorizar otra publicación.
    private mutating func descartarEvidenciaCandidata() {
        boardingEvidenceCount = 0
        alightingEvidenceCount = 0
        rutaDeLaEvidencia = nil
        if state == .boardingCandidate {
            state = .idle
        }
    }

    private func decision(
        shouldPublish: Bool
    ) -> PassengerDetectionDecision {
        PassengerDetectionDecision(
            state: state,
            shouldPublish: shouldPublish,
            didConfirmBoarding: false,
            didConfirmAlighting: false
        )
    }
}
