//
//  SimulatedTrackingProvider.swift
//  RutaUTP
//
//  Implementación de VehicleTrackingProviding que genera posiciones de
//  vehículos de forma LOCAL usando un Timer. Reemplaza conceptualmente
//  a la lógica que antes vivía dentro de MapaViewModel.spawnBuses/iniciarAnimacion.
//
//  - NO usa red ni CLLocationManager.
//  - Genera 6 vehículos en círculo alrededor de un "centro" configurable,
//    los mueve con velocidad y rumbo aleatorios igual que el código original.
//  - Permite reutilizar MapaViewModel sin borrar su Timer interno todavía
//    (ver regla #3 del plan: fallback en paralelo).
//

import Foundation
import Combine

final class SimulatedTrackingProvider: NSObject, VehicleTrackingProviding {

    let source: VehicleTrackingSource = .simulated

    /// Centro de la simulación (UTP Trujillo por defecto).
    private(set) var centerLat: Double
    private(set) var centerLon: Double
    private let vehicleCount: Int
    private let tickInterval: TimeInterval  // segundos

    private var vehicles: [VehiclePosition] = []
    private var tickTimer: Timer?
    private var continuation: AsyncStream<[VehiclePosition]>.Continuation?
    private var stream: AsyncStream<[VehiclePosition]>?

    /// Estado interno mutable (rumbo/velocidad por vehículo).
    private struct Dynamics {
        var heading: Double   // grados
        var speed: Double      // grados-lat/lon por tick (escala approximate del código original)
    }
    private var dynamics: [String: Dynamics] = [:]

    init(centerLat: Double = -8.1116,
         centerLon: Double = -79.0287,
         vehicleCount: Int = 6,
         tickInterval: TimeInterval = 0.05) {
        self.centerLat = centerLat
        self.centerLon = centerLon
        self.vehicleCount = vehicleCount
        self.tickInterval = tickInterval
        super.init()
        spawnVehicles()
    }

    // MARK: - VehicleTrackingProviding

    func start() {
        guard tickTimer == nil else { return }
        // (Re)crear stream para que un nuevo consumidor reciba datos frescos.
        var localContinuation: AsyncStream<[VehiclePosition]>.Continuation?
        stream = AsyncStream { continuation in
            localContinuation = continuation
            // Entrega snapshot inmediato.
            continuation.yield(self.vehicles)
        }
        self.continuation = localContinuation

        tickTimer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.tick()
        }
    }

    func stop() {
        tickTimer?.invalidate()
        tickTimer = nil
        continuation?.finish()
        continuation = nil
        stream = nil
    }

    func positions() -> AsyncStream<[VehiclePosition]> {
        if let stream = stream { return stream }
        // Si aún no se ha llamado a start(), crea un stream vacío pero válido
        // para que el consumidor pueda colgarse y esperar.
        let s = AsyncStream<[VehiclePosition]> { continuation in
            self.continuation = continuation
            continuation.yield(self.vehicles)
        }
        self.stream = s
        return s
    }

    private(set) var currentPositions: [VehiclePosition] = []

    // MARK: - Public API

    /// Recentra la simulación (ej. cuando el usuario elige un destino distinto).
    func setCenter(lat: Double, lon: Double) {
        centerLat = lat
        centerLon = lon
        spawnVehicles()
    }

    // MARK: - Internos

    private func spawnVehicles() {
        let lineas = ["B", "10", "4", "C", "7", "A"]
        vehicles.removeAll()
        dynamics.removeAll()
        for i in 0..<vehicleCount {
            let angulo = Double(i) * 60.0
            let radio = 0.008 + Double.random(in: 0...0.004)
            let rad = angulo * .pi / 180
            let id = "SIM-\(i)"                       // id estable para identificarlo en UI
            let v = VehiclePosition(
                id: id,
                linea: lineas[i % lineas.count],
                lat: centerLat + sin(rad) * radio,
                lon: centerLon + cos(rad) * radio,
                heading: angulo,
                timestamp: Date().timeIntervalSince1970
            )
            vehicles.append(v)
            dynamics[id] = Dynamics(
                heading: angulo,
                speed: 0.0001 + Double.random(in: 0...0.00005)
            )
        }
        currentPositions = vehicles
        continuation?.yield(vehicles)
    }

    private func tick() {
        for i in vehicles.indices {
            let id = vehicles[i].id
            guard var d = dynamics[id] else { continue }
            let rad = d.heading * .pi / 180
            vehicles[i].lat += sin(rad) * d.speed
            vehicles[i].lon += cos(rad) * d.speed
            if Double.random(in: 0...1) < 0.002 {
                d.heading = Double.random(in: 0...360)
                dynamics[id] = d
            }
            vehicles[i].heading = d.heading
            vehicles[i].timestamp = Date().timeIntervalSince1970
        }
        currentPositions = vehicles
        continuation?.yield(vehicles)
    }
}
