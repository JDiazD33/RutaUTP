import Foundation

/// Métricas inmutables de un plan ya resuelto, incluido el respaldo de caminata.
/// Conserva las fórmulas y el orden de los tramos del itinerario original.
struct ItineraryMetrics {
    enum JourneyLeg { case walkingToBoard, riding, transferring, ridingSecond, walkingToDestination }

    let walkToBoardMeters: Double
    let walkToDestinationMeters: Double
    let transferWalkMeters: Double
    let busMeters: Double
    let totalSeconds: Double
    private let firstBusEndMeters: Double
    private let transferWalkEndMeters: Double?
    private let secondBusEndMeters: Double?
    private let transferWaitSeconds: Double
    private let segments: [(distance: Double, speed: Double)]

    init(plan: TransitItinerary) {
        let walkToBoardMeters = plan.walkToBoardMeters
        let walkToDestinationMeters = plan.walkToDestinationMeters
        let transferWalkMeters = plan.transferWalkMeters
        self.walkToBoardMeters = walkToBoardMeters
        self.walkToDestinationMeters = walkToDestinationMeters
        self.transferWalkMeters = transferWalkMeters
        busMeters = plan.busMeters
        transferWaitSeconds = plan.transferWaitSeconds
        totalSeconds = (walkToBoardMeters + walkToDestinationMeters + transferWalkMeters) / 1.4
            + plan.firstBusMeters / plan.busSpeed + (plan.transfer.map { $0.busMeters / $0.busSpeed } ?? 0)
            + plan.transferWaitSeconds

        let firstEnd = walkToBoardMeters + plan.firstBusMeters
        firstBusEndMeters = firstEnd
        var segments: [(distance: Double, speed: Double)] = [
            (walkToBoardMeters, 1.4), (plan.firstBusMeters, plan.busSpeed)
        ]
        if let transfer = plan.transfer {
            transferWalkEndMeters = firstEnd + transferWalkMeters
            secondBusEndMeters = firstEnd + transferWalkMeters + transfer.busMeters
            segments += [(transferWalkMeters, 1.4), (transfer.busMeters, transfer.busSpeed)]
        } else {
            transferWalkEndMeters = nil
            secondBusEndMeters = nil
        }
        segments.append((walkToDestinationMeters, 1.4))
        self.segments = segments
    }

    var walkingWithinTransferLimit: Bool {
        transferWalkMeters <= TransitItinerary.maximumTransferWalk
    }

    func journeyLeg(after meters: Double) -> JourneyLeg {
        if meters < walkToBoardMeters { return .walkingToBoard }
        if meters < firstBusEndMeters { return .riding }
        if let end = transferWalkEndMeters, meters < end { return .transferring }
        if let end = secondBusEndMeters, meters < end { return .ridingSecond }
        return .walkingToDestination
    }

    func remainingSeconds(after meters: Double) -> Double {
        var traveled = max(0, meters)
        var seconds = 0.0
        if let end = transferWalkEndMeters, meters < end {
            seconds += transferWaitSeconds
        }
        for (distance, speed) in segments {
            seconds += max(0, distance - traveled) / speed
            traveled = max(0, traveled - distance)
        }
        return seconds
    }
}

/// Una sola fuente de estado para el plan aceptado y las métricas de sus arrays.
/// Cada instalación nueva prepara sus propias métricas; el plan de búsqueda
/// mantiene sus caminatas mutables hasta resolver Directions y validarlas.
struct InstalledTransitItinerary {
    let plan: TransitItinerary
    let metrics: ItineraryMetrics

    init(plan: TransitItinerary) {
        self.plan = plan
        metrics = ItineraryMetrics(plan: plan)
    }
}
