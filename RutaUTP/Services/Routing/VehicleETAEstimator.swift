import Foundation
import CoreLocation

// MARK: - ETA aproximada de vehículos reales

/// Estima la llegada de una posición MQTT al punto consultado en el mapa.
///
/// El cálculo sigue el shape GTFS, respeta el sentido indicado por el rumbo y
/// usa la velocidad observada, incluso en tráfico lento. Solo si la velocidad
/// es desconocida usa la media programada. Sin rumbo o con el bus detenido no
/// puede anticipar la llegada; tampoco cuando está fuera de ruta o se aleja.
enum VehicleETAEstimator {

    static func minutes(
        position: VehiclePosition,
        route: RutaGTFS,
        target: CLLocationCoordinate2D
    ) -> Int? {
        guard let preparedRoute = PreparedRoute(route: route) else { return nil }
        return minutes(position: position, prepared: PreparedTarget(route: preparedRoute, target: target))
    }

    /// Reutiliza solo la geometría fija; cada posición conserva su propio ETA.
    static func minutes(position: VehiclePosition, prepared: PreparedTarget) -> Int? {
        let route = prepared.route

        guard
            let vehicleMatch = PolylineMatching.match(
                point: position.coordinate,
                on: route.shape,
                thresholdMeters: 120
            ),
            vehicleMatch.isOnRoute,
            let targetMatch = prepared.match,
            targetMatch.isOnRoute
        else {
            return nil
        }

        let routeLength = route.lengthMeters
        guard routeLength > 0 else { return nil }

        var progressDelta = targetMatch.progressFraction
            - vehicleMatch.progressFraction

        let segmentIndex = min(
            vehicleMatch.segmentIndex,
            route.shape.count - 2
        )
        let forwardHeading = PolylineMatching.headingDegrees(
            from: route.shape[segmentIndex],
            to: route.shape[segmentIndex + 1],
            movingForward: true
        )

        let movingForward: Bool?
        if position.heading.isFinite, position.heading >= 0, forwardHeading >= 0 {
            movingForward = angularDifference(
                position.heading,
                forwardHeading
            ) <= 90
        } else {
            movingForward = nil
        }

        let isCircular = route.isCircular

        guard let movingForward else { return nil }
        if isCircular {
            if movingForward, progressDelta < 0 { progressDelta += 1 }
            if !movingForward, progressDelta > 0 { progressDelta -= 1 }
        } else {
            guard movingForward ? progressDelta >= 0 : progressDelta <= 0 else {
                return nil
            }
        }

        let remainingMeters = abs(progressDelta) * routeLength
        guard remainingMeters.isFinite else { return nil }

        let scheduledSpeed = route.scheduledSpeed
        // Estar detenido no equivale a circular a la velocidad programada.
        // El umbral de 0.5 m/s evita extrapolar el ruido de un GPS inmóvil.
        guard position.speed.isFinite else { return nil }
        if position.speed >= 0, position.speed < 0.5 { return nil }
        let effectiveSpeed = position.speed >= 0.5
            ? min(position.speed, 15)
            : min(max(scheduledSpeed, 0.5), 15)

        let estimate = ceil(remainingMeters / effectiveSpeed / 60)
        // No convertir una espera superior a dos horas en exactamente 120 min.
        guard estimate.isFinite, estimate <= 120 else { return nil }
        return max(Int(estimate), 1)
    }

    /// Una representación inmutable del shape original del catálogo instalado.
    /// La longitud conserva la métrica de CLLocation; el matching sigue usando
    /// su proyección local. Sus longitudes no son intercambiables.
    struct PreparedRoute {
        let shape: [CLLocationCoordinate2D]
        let lengthMeters: Double
        let isCircular: Bool
        let scheduledSpeed: Double

        init?(route: RutaGTFS) {
            guard route.shape.count >= 2 else { return nil }
            shape = route.shape
            let routeLength = PolylineMatching.totalLengthMeters(route.shape)
            lengthMeters = routeLength
            isCircular = PolylineMatching.distanceMeters(
                route.shape[0],
                route.shape[route.shape.count - 1]
            ) <= 200
            scheduledSpeed = route.duracionMin > 0
                ? routeLength / (Double(route.duracionMin) * 60)
                : 7
        }
    }

    /// También conserva una proyección ausente o fuera de ruta: repetirla
    /// para otro bus no cambiaría el resultado con el mismo shape y destino.
    struct PreparedTarget {
        let route: PreparedRoute
        let match: PolylineMatching.MatchResult?

        init(route: PreparedRoute, target: CLLocationCoordinate2D) {
            self.route = route
            // El destino puede quedar hasta 1 600 m del corredor, igual que
            // la política de bajada del planificador del mapa.
            match = PolylineMatching.match(
                point: target,
                on: route.shape,
                thresholdMeters: MapaViewModel.radioBusquedaRuta
            )
        }
    }

    private static func angularDifference(_ lhs: Double, _ rhs: Double) -> Double {
        let difference = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }
}
