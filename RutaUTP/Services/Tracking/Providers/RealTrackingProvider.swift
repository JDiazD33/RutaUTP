//
//  RealTrackingProvider.swift
//  RutaUTP
//
//  STUB — implementación placeholder de VehicleTrackingProviding para
//  cuando integremos backend / WebSocket real y recibamos posiciones de
//  vehículos del servidor.
//
//  Hoy NO hace nada útil: start() es no-op, positions() emite un array
//  vacío y termina. Permite que el código compile y que MapaViewModel
//  cambie de simulado→real sin tocar su lógica.
//
//  TODO (integración backend):
//    1. Definir endpoint REST de "posiciones cercanas" o conectar WS.
//    2. Parsear `[VehiclePositionDTO]` (Codable) — ya tenemos el modelo.
//    3. Reemitir vía AsyncStream cada N ms o en cada mensaje WS.
//    4. Manejar reconexión, heartbeat y decode errors sin crashear.
//    5. Implementar `currentPositions` con la última snapshot recibida.
//

import Foundation

final class RealTrackingProvider: VehicleTrackingProviding {

    let source: VehicleTrackingSource = .real

    private var continuation: AsyncStream<[VehiclePosition]>.Continuation?
    private var stream: AsyncStream<[VehiclePosition]>?
    private(set) var currentPositions: [VehiclePosition] = []

    // baseURL pendiente de definir cuando exista el backend.
    // private let baseURL: URL = URL(string: "https://api.rutautp.example.com")!

    func start() {
        // TODO: abrir URLSessionWebSocketTask o comenzar polling.
        // Por ahora, asegurar que el stream exista y emita [] inmediatamente.
        if stream == nil {
            stream = AsyncStream { continuation in
                self.continuation = continuation
                continuation.yield([])
            }
        }
    }

    func stop() {
        // TODO: cerrar web socket / cancelar tarea URLSession.
        continuation?.finish()
        continuation = nil
        stream = nil
    }

    func positions() -> AsyncStream<[VehiclePosition]> {
        if let stream = stream { return stream }
        let s = AsyncStream<[VehiclePosition]> { continuation in
            self.continuation = continuation
            continuation.yield([])
        }
        self.stream = s
        return s
    }
}
