import Foundation
import CoreLocation

struct DetectionRouteGeometry {
    let id: String
    let linea: String
    let shape: [CLLocationCoordinate2D]
    let stops: [CLLocationCoordinate2D]

    init(
        id: String,
        linea: String,
        shape: [CLLocationCoordinate2D],
        stops: [CLLocationCoordinate2D]
    ) {
        self.id = id
        self.linea = linea
        self.shape = shape
        self.stops = stops
    }

    init(
        route: RutaGTFS,
        maximumShapePoints: Int = 250
    ) {
        id = route.id
        linea = route.linea

        shape = PolylineMatching.decimate(
            route.shape,
            maxPoints: maximumShapePoints
        )

        stops = route.paraderos.map {
            $0.coordinate
        }
    }
}

struct RouteCandidateMatch: Equatable {
    let routeID: String
    let linea: String
    let distanceToRoute: Double
    let headingDifference: Double
    let distanceToNearestStop: Double
    let segmentIndex: Int
    let progressFraction: Double
}

enum RouteCandidateMatcher {

    static func closestMatch(
        for location: CLLocation,
        routes: [DetectionRouteGeometry]
    ) -> RouteCandidateMatch? {
        var bestCandidate: RouteCandidateMatch?

        for route in routes {
            guard let match = PolylineMatching.match(
                point: location.coordinate,
                on: route.shape,
                thresholdMeters: 40
            ) else {
                continue
            }

            let routeBearing = bearing(
                forSegment: match.segmentIndex,
                shape: route.shape
            )

            let headingDifference = difference(
                between: location.course,
                and: routeBearing
            )

            let nearestStopDistance = route.stops
                .map {
                    distance(
                        from: location.coordinate,
                        to: $0
                    )
                }
                .min() ?? .greatestFiniteMagnitude

            let candidate = RouteCandidateMatch(
                routeID: route.id,
                linea: route.linea,
                distanceToRoute: match.distanceToRoute,
                headingDifference: headingDifference,
                distanceToNearestStop: nearestStopDistance,
                segmentIndex: match.segmentIndex,
                progressFraction: match.progressFraction
            )

            if bestCandidate == nil ||
                candidate.distanceToRoute <
                bestCandidate!.distanceToRoute {
                bestCandidate = candidate
            }
        }

        return bestCandidate
    }

    private static func bearing(
        forSegment index: Int,
        shape: [CLLocationCoordinate2D]
    ) -> Double {
        guard
            index >= 0,
            index + 1 < shape.count
        else {
            return 0
        }

        let start = shape[index]
        let end = shape[index + 1]

        let startLatitude =
            start.latitude * .pi / 180

        let endLatitude =
            end.latitude * .pi / 180

        let longitudeDifference =
            (end.longitude - start.longitude) *
            .pi / 180

        let y =
            sin(longitudeDifference) *
            cos(endLatitude)

        let x =
            cos(startLatitude) *
            sin(endLatitude) -
            sin(startLatitude) *
            cos(endLatitude) *
            cos(longitudeDifference)

        let degrees =
            atan2(y, x) * 180 / .pi

        return (degrees + 360)
            .truncatingRemainder(dividingBy: 360)
    }

    private static func difference(
        between deviceHeading: Double,
        and routeHeading: Double
    ) -> Double {
        guard
            deviceHeading >= 0,
            deviceHeading <= 360
        else {
            // Un rumbo desconocido no debe contar como alineado.
            return 180
        }

        let rawDifference =
            abs(deviceHeading - routeHeading)

        return min(
            rawDifference,
            360 - rawDifference
        )
    }

    private static func distance(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) -> Double {
        let originLocation = CLLocation(
            latitude: origin.latitude,
            longitude: origin.longitude
        )

        let destinationLocation = CLLocation(
            latitude: destination.latitude,
            longitude: destination.longitude
        )

        return originLocation.distance(
            from: destinationLocation
        )
    }
}
