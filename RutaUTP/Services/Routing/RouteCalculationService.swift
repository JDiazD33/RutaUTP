//
//  RouteCalculationService.swift
//  RutaUTP
//
//  Servicio que calcula rutas entre dos puntos usando MKDirections
//  (los directions de Apple, gratis, sin API key, sin dependencias).
//
//  API async/await moderna. Internamente puentea el API basada en
//  completion handlers de MKDirections usando withCheckedContinuation.
//
//  Importante:
//   - MKDirections requiere transporte .automobile por defecto. Pedimos
//     .transit cuando esté disponible (iOS.getServer-side), y dejamos
//     .automobile como fallback. MKDirections no soporta un modo
//     específicamente "bus urbano"机电 → usaremos .transit y dejaremos que
//     el servidor de Apple devuelva pasos de transporte público.
//   - Si Apple no tiene datos de tránsito en Trujillo, MKDirections devuelve
//     error (o rutas vacías). En producción se needs fallback manual;
//     por ahora el consumidor debe manejar `RouteResult.failure`.
//   -今回はusamos MKDirections con un único MKDirections.Request.
//

import Foundation
import MapKit

enum RouteCalculationError: Error, Equatable {
    case noRoutesAvailable
    case appleDirectionsFailed(String)
    case invalidRequest
}

struct CalculatedRoute: Equatable {
    let polyline: MKPolyline
    /// Tiempo estimado en segundos.
    let expectedTravelTime: TimeInterval
    /// Distancia en metros.
    let distance: Double
    /// Pasos (instrucciones) de la ruta.
    let steps: [MKRoute.Step]

    static func == (lhs: CalculatedRoute, rhs: CalculatedRoute) -> Bool {
        lhs.expectedTravelTime == rhs.expectedTravelTime &&
        lhs.distance == rhs.distance &&
        lhs.polyline.pointCount == rhs.polyline.pointCount
    }
}

final class RouteCalculationService {

    /// Calcula una ruta entre `origin` y `destination`.
    /// Lanza `RouteCalculationError` si Apple Directions no responde bien.
    func calculateRoute(from origin: CLLocationCoordinate2D,
                        to destination: CLLocationCoordinate2D,
                        transportType: MKDirectionsTransportType = .transit) async throws -> CalculatedRoute {

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = transportType
        request.requestsAlternateRoutes = false

        guard !origin.latitude.isNaN, !origin.longitude.isNaN,
              !destination.latitude.isNaN, !destination.longitude.isNaN else {
            throw RouteCalculationError.invalidRequest
        }

        let directions = MKDirections(request: request)
        return try await withCheckedThrowingContinuation { continuation in
            directions.calculate { response, error in
                if let error = error {
                    continuation.resume(throwing: RouteCalculationError.appleDirectionsFailed(error.localizedDescription))
                    return
                }
                guard let route = response?.routes.first else {
                    continuation.resume(throwing: RouteCalculationError.noRoutesAvailable)
                    return
                }
                let calculated = CalculatedRoute(
                    polyline: route.polyline,
                    expectedTravelTime: route.expectedTravelTime,
                    distance: route.distance,
                    steps: route.steps
                )
                continuation.resume(returning: calculated)
            }
        }
    }

    /// Cancela cualquier cálculo en curso (placeholder por si se quiere
    /// cancelar recálculos en cascade Detectó-desvío).
    func cancel() {
        // MKDirections no soporta cancel() oficial, ignorar por ahora.
    }
}
