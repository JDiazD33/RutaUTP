//
//  BoardingPlaceStore.swift
//  RutaUTP
//
//  Notas de lugares de subida declarados por el usuario.
//

import Foundation
import CoreLocation

/// Referencias declaradas, no paraderos verificados. No se infiere que la
/// ubicación actual del teléfono sea donde el pasajero subió anteriormente.
struct BoardingPoint: Codable, Equatable {
    let latitude: Double
    let longitude: Double

    init?(coordinate: CLLocationCoordinate2D) {
        guard coordinate.latitude.isFinite, coordinate.longitude.isFinite,
              CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct BoardingPlaceNote: Codable, Identifiable {
    let id: UUID
    let routeID: String
    let line: String
    let place: String
    // Opcional para poder seguir leyendo las referencias anteriores sin mapa.
    let point: BoardingPoint?
    let recordedAt: Date
}

@MainActor
enum BoardingPlaceStore {
    static let key = "rutautp.boarding-place-notes.v1"

    nonisolated static func normalized(_ text: String) -> String? {
        let value = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        return value.isEmpty ? nil : value
    }

    static func notes(defaults: UserDefaults = .standard) -> [BoardingPlaceNote] {
        readableNotes(defaults: defaults) ?? []
    }

    static func datosInvalidos(defaults: UserDefaults = .standard) -> Bool {
        readableNotes(defaults: defaults) == nil
    }

    @MainActor
    static func respaldarYReiniciar(defaults: UserDefaults = .standard,
                                    crearRespaldo: ((Data) throws -> URL)? = nil) throws -> URL? {
        guard datosInvalidos(defaults: defaults) else { return nil }
        let vacias = try JSONEncoder().encode([BoardingPlaceNote]())
        return try RecuperacionPreferencias.reiniciar(claves: [key],
            valoresNuevos: [key: vacias], nombre: "subidas", defaults: defaults,
            crearRespaldo: crearRespaldo)
    }

    /// nil indica almacenamiento ilegible; [] indica ausencia o lista vacía válida.
    private static func readableNotes(defaults: UserDefaults) -> [BoardingPlaceNote]? {
        guard let original = defaults.object(forKey: key) else { return [] }
        guard let data = original as? Data else { return nil }
        return try? JSONDecoder().decode([BoardingPlaceNote].self, from: data)
    }

    @discardableResult
    static func save(routeID: String, line: String, place: String, point: BoardingPoint? = nil,
                     defaults: UserDefaults = .standard) -> Bool {
        let place = normalized(place)
        guard place != nil || point != nil else { return true }
        guard var records = readableNotes(defaults: defaults) else { return false }
        records.append(BoardingPlaceNote(id: UUID(), routeID: routeID, line: line,
                                         place: place ?? "", point: point, recordedAt: Date()))
        // Historial local acotado para preparar el futuro catálogo de paraderos.
        guard let data = try? JSONEncoder().encode(Array(records.suffix(200))) else { return false }
        defaults.set(data, forKey: key)
        return true
    }
}
