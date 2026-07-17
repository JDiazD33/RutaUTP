//
//  TrackingPoint.swift
//  RutaUTP
//
//  Modelo de un punto de tracking (muestra de ubicación en un instante).
//  Es un modelo de DATOS (no de UI): sin Color, sin SwiftUI. Codable para
//  poder serializarlo/enviarlo a un backend en el futuro.
//

import Foundation
import CoreLocation

struct TrackingPoint: Codable, Equatable {
    let lat: Double
    let lon: Double
    /// Rumbo en grados (0 = norte, 180 = sur). Puede ser negativo si el device no lo tiene.
    let heading: Double
    /// Velocidad en m/s. -1 si no disponible.
    let speed: Double
    /// Timestamp UNIX (segundos desde 1970).
    let timestamp: TimeInterval

    init(lat: Double,
         lon: Double,
         heading: Double = -1,
         speed: Double = -1,
         timestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.lat = lat
        self.lon = lon
        self.heading = heading
        self.speed = speed
        self.timestamp = timestamp
    }

    /// Convenience para construir desde un CLLocation del sistema.
    init(from location: CLLocation) {
        self.init(
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude,
            heading: max(0, location.course),   // course = -1 si inválido
            speed: max(-1, location.speed),      // speed = -1 si inválido
            timestamp: location.timestamp.timeIntervalSince1970
        )
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
