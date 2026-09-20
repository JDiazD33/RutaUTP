import Foundation

struct PassengerDetectionEngine {

    private(set) var state:
        PassengerDetectionState = .idle

    private let thresholds:
        PassengerDetectionThresholds

    private var boardingEvidenceCount = 0
    private var alightingEvidenceCount = 0

    init(
        thresholds: PassengerDetectionThresholds = .default
    ) {
        self.thresholds = thresholds
    }

    mutating func process(
        _ sample: PassengerDetectionSample
    ) -> PassengerDetectionDecision {
        guard
            sample.horizontalAccuracy >= 0,
            sample.horizontalAccuracy <=
                thresholds.maximumAccuracy
        else {
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
                state = .boardingCandidate
            } else if isApproachingStop {
                state = .approachingStop
            }

        case .approachingStop:
            if hasVehicleEvidence {
                boardingEvidenceCount = 1
                state = .boardingCandidate
            } else if !isNearStop {
                state = .idle
            }

        case .boardingCandidate:
            if hasVehicleEvidence {
                boardingEvidenceCount += 1

                if boardingEvidenceCount >=
                    thresholds.boardingEvidenceRequired {
                    state = .onboard
                    boardingEvidenceCount = 0
                    confirmedBoarding = true
                }
            } else {
                boardingEvidenceCount = 0
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
