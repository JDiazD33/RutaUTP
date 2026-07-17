//
//  VehiclePosition.swift
//  RutaUTP
//
//  Posición actual de un vehículo (micro/combi/bus) que se está trackeando.
//  Reemplaza conceptualmente a `BusSimulado` (que vive solo en el ViewModel
//  del mapa con datos sintéticos). Aquí están los datos crudos, sin Color,
//  listos para venir de un backend / WebSocket.
//

import Foundation
import CoreLocation

struct VehiclePosition: Codable, Equatable, Identifiable {
    let id: String           // identificador único del vehículo (placa o backend id)
    let linea: String        // "10", "B", ...
    var lat: Double
    var lon: Double
    var heading: Double      // grados, -1 si desconocido
    var speed: Double        // m/s, -1 si desconocido
    var timestamp: TimeInterval

    init(id: String,
         linea: String,
         lat: Double,
         lon: Double,
         heading: Double = -1,
         speed: Double = -1,
         timestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.id = id
        self.linea = linea
        self.lat = lat
        self.lon = lon
        self.heading = heading
        self.speed = speed
        self.timestamp = timestamp
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

/// Cómo obtuvimos la posición de un vehículo. Sirve para distinguir
/// la fuente en logs y en la UI (badge "En vivo" real vs "Demo").
enum VehicleTrackingSource: String, Codable, Equatable {
    case simulated   // SimulatedTrackingProvider (Timer local)
    case real        // RealTrackingProvider (backend / WS futuro)
}
