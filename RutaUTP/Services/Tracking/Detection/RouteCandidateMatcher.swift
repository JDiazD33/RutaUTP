import Foundation
import CoreLocation

struct DetectionRouteGeometry {
    let id: String
    let linea: String
    let shape: [CLLocationCoordinate2D]
    let stops: [CLLocationCoordinate2D]

    /// Caja envolvente del recorrido, para descartar rutas lejanas sin recorrer
    /// sus vértices. Ver `RouteCandidateMatcher.closestMatch`.
    let boundingBox: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)?

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
        self.boundingBox = Self.makeBoundingBox(shape)
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

        boundingBox = Self.makeBoundingBox(shape)
    }

    /// Caja envolvente en grados. `nil` si no hay geometría.
    private static func makeBoundingBox(
        _ shape: [CLLocationCoordinate2D]
    ) -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)? {
        guard let first = shape.first else {
            return nil
        }

        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude

        for coordinate in shape.dropFirst() {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }

        return (minLat, maxLat, minLon, maxLon)
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

    /// Devuelve la ruta geométricamente más cercana a `location`.
    ///
    /// **No filtra por distancia.** Devuelve la más próxima aunque esté a
    /// kilómetros y deja cuánto se aleja en `distanceToRoute`; quien decide si
    /// esa distancia es aceptable es `PassengerDetectionEngine`, con
    /// `PassengerDetectionThresholds.maximumDistanceToRoute`.
    ///
    /// Antes se pasaba aquí un `thresholdMeters: 40` que `PolylineMatching.match`
    /// solo usaba para rellenar su campo `isOnRoute`, que este matcher descarta.
    /// El umbral no filtraba nada y, al estar también en los umbrales del motor,
    /// había dos copias del mismo número listas para divergir en silencio.
    /// Se retiró en lugar de dejar una que pareciera hacer algo.
    ///
    /// **Coste.** Recorrer los ~250 vértices de las ~103 rutas del feed son
    /// ~25 000 proyecciones por muestra de GPS, y todo ocurre en el hilo
    /// principal. Para evitarlo se descarta primero cada ruta cuya caja
    /// envolvente ya esté más lejos que la mejor candidata encontrada: la
    /// distancia a la caja es una **cota inferior** de la distancia al
    /// recorrido (el recorrido está dentro de su caja), así que saltarla no
    /// puede cambiar el resultado. La optimización es exacta, no aproximada.
    static func closestMatch(
        for location: CLLocation,
        routes: [DetectionRouteGeometry]
    ) -> RouteCandidateMatch? {
        var best: (
            route: DetectionRouteGeometry,
            match: PolylineMatching.MatchResult,
            headingDifference: Double
        )?

        for route in routes {
            // Descarte barato: si ni siquiera su caja envolvente puede ganar,
            // no hace falta proyectar punto por punto.
            if let best,
               let box = route.boundingBox,
               distanceToBoundingBox(
                   from: location.coordinate,
                   box: box
               ) >= best.match.distanceToRoute {
                continue
            }

            guard let match = PolylineMatching.match(
                point: location.coordinate,
                on: route.shape
            ) else {
                continue
            }

            let routeBearing = bearing(
                forSegment: match.segmentIndex,
                shape: route.shape
            )

            let candidate = (
                route: route,
                match: match,
                headingDifference: difference(
                    between: location.course,
                    and: routeBearing
                )
            )

            if best == nil ||
                candidate.match.distanceToRoute <
                best!.match.distanceToRoute {
                best = candidate
            }
        }

        guard let best else {
            return nil
        }

        return RouteCandidateMatch(
            routeID: best.route.id,
            linea: best.route.linea,
            distanceToRoute: best.match.distanceToRoute,
            headingDifference: best.headingDifference,
            // Solo se calcula para la ganadora. Calcularlo para cada ruta
            // recorría todos sus paraderos en cada muestra de GPS y el
            // resultado de las perdedoras se descartaba.
            distanceToNearestStop: nearestStopDistance(
                from: location.coordinate,
                stops: best.route.stops
            ),
            segmentIndex: best.match.segmentIndex,
            progressFraction: best.match.progressFraction
        )
    }

    private static func nearestStopDistance(
        from origin: CLLocationCoordinate2D,
        stops: [CLLocationCoordinate2D]
    ) -> Double {
        stops
            .map {
                distance(
                    from: origin,
                    to: $0
                )
            }
            .min() ?? .greatestFiniteMagnitude
    }

    /// Cota inferior de la distancia de `origin` al recorrido, en metros.
    ///
    /// Se mide al punto más cercano de la caja envolvente. Como el recorrido
    /// está contenido en su propia caja, la distancia a la caja nunca supera la
    /// distancia al recorrido: es una cota inferior válida, así que descartar
    /// con ella no puede cambiar el resultado.
    private static func distanceToBoundingBox(
        from origin: CLLocationCoordinate2D,
        box: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)
    ) -> Double {
        let nearest = CLLocationCoordinate2D(
            latitude: min(max(origin.latitude, box.minLat), box.maxLat),
            longitude: min(max(origin.longitude, box.minLon), box.maxLon)
        )

        return distance(from: origin, to: nearest)
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
