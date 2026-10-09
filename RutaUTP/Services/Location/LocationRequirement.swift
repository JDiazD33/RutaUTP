import CoreLocation

/// Cada stream conserva su requisito hasta terminar. La navegación también
/// cubre detección pasiva y lecturas puntuales que necesitan precisión alta.
enum LocationRequirement: Sendable {
    case mapDisplay
    case navigation

    var desiredAccuracy: CLLocationAccuracy {
        switch self {
        case .mapDisplay: return kCLLocationAccuracyNearestTenMeters
        case .navigation: return kCLLocationAccuracyBest
        }
    }

    var distanceFilter: CLLocationDistance {
        switch self {
        case .mapDisplay: return 15
        case .navigation: return 5
        }
    }
}
