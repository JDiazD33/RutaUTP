import Foundation

enum PassengerDetectionState: String, Codable, Equatable {
    case idle
    case approachingStop
    case boardingCandidate
    case onboard
    case alightingCandidate
}

enum DetectedMotionActivity: String, Codable, Equatable {
    case stationary
    case walking
    case running
    case automotive
    case cycling
    case unknown
}

struct PassengerDetectionSample: Equatable {
    let timestamp: TimeInterval
    let speed: Double
    let horizontalAccuracy: Double
    let distanceToRoute: Double
    let headingDifference: Double
    let distanceToNearestStop: Double
    let motionActivity: DetectedMotionActivity
}

struct PassengerDetectionDecision: Equatable {
    let state: PassengerDetectionState
    let shouldPublish: Bool
    let didConfirmBoarding: Bool
    let didConfirmAlighting: Bool
}

struct PassengerDetectionThresholds {
    let maximumAccuracy: Double
    let maximumDistanceToRoute: Double
    let maximumHeadingDifference: Double
    let maximumDistanceToStop: Double
    let minimumVehicleSpeed: Double
    let maximumVehicleSpeed: Double
    let boardingEvidenceRequired: Int
    let alightingEvidenceRequired: Int

    static let `default` = PassengerDetectionThresholds(
        maximumAccuracy: 50,
        maximumDistanceToRoute: 40,
        maximumHeadingDifference: 45,
        maximumDistanceToStop: 80,
        minimumVehicleSpeed: 4, // se esta expresando en metros por segundo 4 m/s = 14.4 km/h
        maximumVehicleSpeed: 30,// se esta expresando en metros por segundo 30 m/s = 180 km/h
        boardingEvidenceRequired: 3,
        alightingEvidenceRequired: 4
    )
}
