//
//  VehiclePosition.swift
//  RutaUTP
//
//  Posición actual de un vehículo (micro/combi/bus) que se está trackeando.
//  Son los datos crudos, sin Color, listos para venir de un backend o del
//  canal MQTT.
//

import Foundation
import CoreLocation
import Observation

enum MapVehicleLimit: Int, CaseIterable, Identifiable, Hashable {
    case all = 0, five = 5, ten = 10, fifteen = 15, twenty = 20
    var id: Int { rawValue }
    var title: String {
        self == .all ? L.t("Todos", "All") : String(rawValue)
    }

    func displayed<T: Identifiable>(_ vehicles: [T], selectedID: T.ID? = nil) -> [T] {
        guard self != .all, vehicles.count > rawValue else { return vehicles }
        var visible = Array(vehicles.prefix(rawValue))
        if let selectedID, !visible.contains(where: { $0.id == selectedID }),
           let selected = vehicles.first(where: { $0.id == selectedID }) {
            visible[visible.count - 1] = selected
        }
        return visible
    }
}

@MainActor
@Observable
final class MapVehiclePreferences {
    static let shared = MapVehiclePreferences()
    static let storageKey = "mapa.micros-visibles.v1"
    @ObservationIgnored private let defaults: UserDefaults
    private(set) var limit: MapVehicleLimit

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.object(forKey: Self.storageKey) as? Int
        limit = stored.flatMap(MapVehicleLimit.init(rawValue:)) ?? .all
    }

    func setLimit(_ value: MapVehicleLimit) {
        limit = value
        defaults.set(value.rawValue, forKey: Self.storageKey)
    }
}

struct VehiclePosition: Codable, Equatable, Identifiable {
    let id: String           // identificador único del vehículo (placa o backend id)
    let linea: String        // "10", "B", ...

    /// Identificador de la ruta GTFS (`route_id`) a la que pertenece el vehículo.
    ///
    /// Se usa para resolver empresa, color y recorrido. Antes se deducía de
    /// `linea`, que es el nombre público: dos ramales de la misma línea
    /// comparten `linea` y quedaban indistinguibles, y cualquier línea fuera
    /// del pequeño catálogo precargado se quedaba sin metadatos.
    ///
    /// Vacío significa "no informado" (proveedores antiguos o simulaciones sin
    /// catálogo): en ese caso se cae a `linea`, como antes.
    let routeId: String

    var lat: Double
    var lon: Double
    var heading: Double      // grados, -1 si desconocido
    var speed: Double        // m/s, -1 si desconocido
    var timestamp: TimeInterval

    /// Procedencia del dato, independiente del transporte/localización de UI.
    let dataOrigin: VehicleDataOrigin
    let simulationRunId: String?
    let controlRevision: UInt64?
    let scenarioOccupancy: VehicleScenarioOccupancy?

    init(id: String,
         linea: String,
         routeId: String = "",
         lat: Double,
         lon: Double,
         heading: Double = -1,
         speed: Double = -1,
         timestamp: TimeInterval = Date().timeIntervalSince1970,
         dataOrigin: VehicleDataOrigin = .unknown,
         simulationRunId: String? = nil,
         controlRevision: UInt64? = nil,
         scenarioOccupancy: VehicleScenarioOccupancy? = nil) {
        self.id = id
        self.linea = linea
        self.routeId = routeId
        self.lat = lat
        self.lon = lon
        self.heading = heading
        self.speed = speed
        self.timestamp = timestamp
        self.dataOrigin = dataOrigin
        self.simulationRunId = simulationRunId
        self.controlRevision = controlRevision
        self.scenarioOccupancy = dataOrigin == .simulated ? scenarioOccupancy : nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, linea, routeId, lat, lon, heading, speed, timestamp
        case dataOrigin, simulationRunId, controlRevision
        case scenarioOccupancy
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        linea = try values.decode(String.self, forKey: .linea)
        routeId = try values.decodeIfPresent(String.self, forKey: .routeId) ?? ""
        lat = try values.decode(Double.self, forKey: .lat)
        lon = try values.decode(Double.self, forKey: .lon)
        heading = try values.decode(Double.self, forKey: .heading)
        speed = try values.decode(Double.self, forKey: .speed)
        timestamp = try values.decode(Double.self, forKey: .timestamp)
        dataOrigin = try values.decodeIfPresent(VehicleDataOrigin.self, forKey: .dataOrigin) ?? .legacyUnknown
        simulationRunId = try values.decodeIfPresent(String.self, forKey: .simulationRunId)
        controlRevision = try values.decodeIfPresent(UInt64.self, forKey: .controlRevision)
        let occupancy = try values.decodeIfPresent(VehicleScenarioOccupancy.self, forKey: .scenarioOccupancy)
        scenarioOccupancy = dataOrigin == .simulated ? occupancy : nil
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

/// Transporte del proveedor. MQTT sigue siendo `.real` aunque un dato sea sintético.
enum VehicleTrackingSource: String, Codable, Equatable {
    case simulated   // SimulatedTrackingProvider (Timer local)
    case real        // MQTTTrackingProvider (posiciones del backend por el broker)
}

enum VehicleDataOrigin: String, Codable, Equatable, Hashable {
    case observed
    case simulated
    case legacyUnknown = "legacy_unknown"
    case unknown
}

/// Guion de ocupación del backend. No abre el servicio de votos comunitarios.
enum VehicleScenarioOccupancy: String, Codable, Equatable {
    case empty, space, full
}

/// Identidad de presentación: reutilizar un ID no conserva selección ni velocidad
/// entre rutas, orígenes o generaciones de control diferentes.
struct VehiclePresentationIdentity: Equatable, Hashable {
    let id: String
    let routeId: String
    let dataOrigin: VehicleDataOrigin
    let simulationRunId: String?
    let controlRevision: UInt64?
}

extension VehiclePosition {
    var presentationIdentity: VehiclePresentationIdentity {
        VehiclePresentationIdentity(id: id, routeId: routeId, dataOrigin: dataOrigin,
            simulationRunId: simulationRunId, controlRevision: controlRevision)
    }

    /// Un transporte MQTT no demuestra procedencia observada. El legado y los
    /// datos sintéticos nunca abren el canal comunitario desde su detalle.
    var communityVehicleID: String? {
        dataOrigin == .observed && !id.lowercased().hasPrefix("sim:") ? id : nil
    }

    var reportedSpeedForPresentation: Double? {
        speed.isFinite && (0...100).contains(speed) ? speed : nil
    }
}

/// Limita movimiento visual a 4 Hz; las retiradas y cambios de procedencia,
/// ruta o revisión se publican inmediatamente aunque lleguen en el mismo tick.
struct VehiclePresentationUpdateGate {
    private var identities: [String: VehiclePresentationIdentity] = [:]
    private var lastUpdate: TimeInterval?

    mutating func shouldPublish(_ positions: [VehiclePosition], at uptime: TimeInterval) -> Bool {
        let next = Dictionary(positions.map { ($0.id, $0.presentationIdentity) },
                              uniquingKeysWith: { _, last in last })
        if next == identities, let lastUpdate, uptime >= lastUpdate, uptime - lastUpdate < 0.25 {
            return false
        }
        identities = next
        lastUpdate = uptime
        return true
    }
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
