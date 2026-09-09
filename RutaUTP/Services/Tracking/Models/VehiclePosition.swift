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

/// Filtro de entrada para posiciones que llegan por el canal MQTT.
///
/// Cualquier cliente puede publicar en el broker, así que el consumidor
/// no debe asumir que el JSON es razonable: un valor NaN, una latitud
/// de 9999 o un timestamp del futuro terminarían dibujados en el mapa
/// o rompiendo cálculos de distancia. Todo lo que no pase el filtro se
/// descarta; nada se "repara" silenciosamente excepto speed y heading,
/// que tienen un valor de "desconocido" definido por el contrato.
enum VehiclePositionSanitizer {

    /// Edad máxima (en segundos) de una posición antes de considerarla
    /// obsoleta. Con un ritmo de baliza de 5 s, 45 s significa que un
    /// vehículo dejó de transmitir hace al menos nueve ciclos.
    static let stalenessLimit: TimeInterval = 45

    /// Tolerancia a desfase de reloj entre emisor y receptor.
    static let clockSkewTolerance: TimeInterval = 10

    /// Devuelve la posición lista para usarse, o `nil` si debe ignorarse.
    static func sanitize(
        _ position: VehiclePosition,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> VehiclePosition? {
        guard
            position.lat.isFinite,
            abs(position.lat) <= 90,
            position.lon.isFinite,
            abs(position.lon) <= 180
        else {
            return nil
        }

        guard position.timestamp.isFinite else {
            return nil
        }

        // Un timestamp del futuro sobrado indica reloj mal ajustado o
        // un mensaje manipulado; en ambos casos no se usa.
        guard
            position.timestamp <=
                now + clockSkewTolerance
        else {
            return nil
        }

        guard
            now - position.timestamp <= stalenessLimit
        else {
            return nil
        }

        var sanitized = position
        sanitized.speed = sanitizedSpeed(position.speed)
        sanitized.heading = sanitizedHeading(position.heading)
        return sanitized
    }

    private static func sanitizedSpeed(
        _ value: Double
    ) -> Double {
        guard value.isFinite else {
            return -1
        }

        // 100 m/s = 360 km/h, techo generoso para transporte urbano.
        return min(max(value, -1), 100)
    }

    private static func sanitizedHeading(
        _ value: Double
    ) -> Double {
        guard value.isFinite, value >= 0 else {
            return -1
        }

        return value.truncatingRemainder(dividingBy: 360)
    }
}
