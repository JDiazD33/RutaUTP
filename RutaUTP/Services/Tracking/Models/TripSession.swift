//
//  TripSession.swift
//  RutaUTP
//
//  Representa una sesión de viaje (un "trip") en curso o histórico.
//  Es un modelo de DATOS (Codable, sin Color). La capa de UI puede
//  derivar Color a partir del `linea` o `empresa` usando el Design System.
//

import Foundation

enum TripState: String, Codable, Equatable {
    case pending       // creado, no iniciado
    case inProgress    // tracking activo
    case paused        // pausado por el usuario
    case completed     // llegó a destino
    case cancelled     // abortado
    case recalculating // detectó desvío, recalculando ruta
}

struct TripSession: Codable, Equatable, Identifiable {
    let id: UUID
    let linea: String          // ej. "10", "B", "4"
    let empresa: String         // ej. "El Cortijo"
    let origen: TrackingPoint
    let destino: TrackingPoint
    var estado: TripState
    /// Puntos recorridos hasta ahora (orden cronológico).
    var puntosRecorridos: [TrackingPoint]
    /// Timestamp UNIX início del viaje (nil si aún no arranca).
    var startedAt: TimeInterval?
    /// Timestamp UNIX fin del viaje (nil si en curso).
    var endedAt: TimeInterval?

    init(id: UUID = UUID(),
         linea: String,
         empresa: String,
         origen: TrackingPoint,
         destino: TrackingPoint,
         estado: TripState = .pending,
         puntosRecorridos: [TrackingPoint] = [],
         startedAt: TimeInterval? = nil,
         endedAt: TimeInterval? = nil) {
        self.id = id
        self.linea = linea
        self.empresa = empresa
        self.origen = origen
        self.destino = destino
        self.estado = estado
        self.puntosRecorridos = puntosRecorridos
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}
