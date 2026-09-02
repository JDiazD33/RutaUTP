//
//  SimulatedTrackingProvider.swift
//  RutaUTP
//
//  Proveedor de posiciones vehiculares simuladas sobre recorridos GTFS.
//
//  Responsabilidades:
//  - Cargar las rutas GTFS más cercanas a UTP.
//  - Crear un vehículo simulado por ruta.
//  - Mover los vehículos siguiendo los shapes reales.
//  - Emitir las posiciones mediante AsyncStream.
//
//  No utiliza red, MQTT ni CLLocationManager.
//

import Foundation
import CoreLocation

final class SimulatedTrackingProvider: VehicleTrackingProviding {

    let source: VehicleTrackingSource = .simulated

    private let vehicleCount: Int
    private let tickInterval: TimeInterval
    private let progressPerTick: Double

    private var routeStates: [SimulatedRouteState] = []

    private var tickTimer: Timer?
    private var loadTask: Task<Void, Never>?

    private var continuation:
        AsyncStream<[VehiclePosition]>.Continuation?

    private var stream:
        AsyncStream<[VehiclePosition]>?

    private(set) var currentPositions: [VehiclePosition] = []

    // MARK: - Estado interno por vehículo

    private struct SimulatedRouteState {
        let vehicleId: String
        let linea: String
        let coordinates: [CLLocationCoordinate2D]

        var currentSegmentIndex: Int
        var segmentProgress: Double
        var isMovingForward: Bool
    }

    // MARK: - Inicialización

    init(
        vehicleCount: Int = 4,
        tickInterval: TimeInterval = 0.05,
        progressPerTick: Double = 0.012
    ) {
        self.vehicleCount = vehicleCount
        self.tickInterval = tickInterval
        self.progressPerTick = progressPerTick
    }

    // MARK: - VehicleTrackingProviding

    func start() {
        guard tickTimer == nil, loadTask == nil else {
            return
        }

        prepareStreamIfNeeded()

        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let routes = await GTFSRepository.shared.rutasCercaDeUTP(
                n: self.vehicleCount
            )

            guard !Task.isCancelled else { return }

            self.configureVehicles(with: routes)
            self.startTimerIfNeeded()
            self.loadTask = nil
        }
    }

    func stop() {
        loadTask?.cancel()
        loadTask = nil

        tickTimer?.invalidate()
        tickTimer = nil

        continuation?.finish()
        continuation = nil
        stream = nil
    }

    func positions() -> AsyncStream<[VehiclePosition]> {
        if let stream {
            return stream
        }

        let newStream = makeStream()
        stream = newStream
        return newStream
    }

    // MARK: - Configuración del stream

    private func prepareStreamIfNeeded() {
        guard stream == nil else { return }

        stream = makeStream()
    }

    private func makeStream() -> AsyncStream<[VehiclePosition]> {
        AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }

            self.continuation = continuation

            if !self.currentPositions.isEmpty {
                continuation.yield(self.currentPositions)
            }
        }
    }

    // MARK: - Configuración GTFS

    @MainActor
    private func configureVehicles(with routes: [RutaGTFS]) {
        guard !routes.isEmpty else {
            currentPositions = []
            routeStates = []

            #if DEBUG
            print("[SimulatedTrackingProvider] No se encontraron rutas GTFS")
            #endif

            continuation?.yield([])
            return
        }

        let routeCount = routes.count

        routeStates = routes.enumerated().compactMap { index, route in
            var coordinates = PolylineMatching.decimate(
                route.shape,
                maxPoints: 240
            )

            if coordinates.count < 2 {
                coordinates = RutaCoordenadas.linea10
            }

            guard coordinates.count >= 2 else {
                return nil
            }

            // Repartimos los vehículos a lo largo de sus recorridos para
            // evitar que todos aparezcan en el primer punto del shape.
            let initialSegment = min(
                index * max(1, coordinates.count / (routeCount + 1)),
                max(0, coordinates.count - 2)
            )

            return SimulatedRouteState(
                vehicleId: "SIM-\(route.id)",
                linea: route.linea,
                coordinates: coordinates,
                currentSegmentIndex: initialSegment,
                segmentProgress: 0,
                isMovingForward: true
            )
        }

        currentPositions = routeStates.map { state in
            makeVehiclePosition(from: state)
        }

        continuation?.yield(currentPositions)

        #if DEBUG
        print(
            "[SimulatedTrackingProvider] Configurados " +
            "\(currentPositions.count) vehículos sobre rutas GTFS"
        )
        #endif
    }

    // MARK: - Timer

    @MainActor
    private func startTimerIfNeeded() {
        guard tickTimer == nil else { return }
        guard !routeStates.isEmpty else { return }

        tickTimer = Timer.scheduledTimer(
            withTimeInterval: tickInterval,
            repeats: true
        ) { [weak self] _ in
            self?.tick()
        }
    }

    // MARK: - Movimiento

    private func tick() {
        guard !routeStates.isEmpty else { return }

        for index in routeStates.indices {
            advanceVehicle(at: index)
        }

        currentPositions = routeStates.map { state in
            makeVehiclePosition(from: state)
        }

        continuation?.yield(currentPositions)
    }

    private func advanceVehicle(at index: Int) {
        var state = routeStates[index]
        let coordinates = state.coordinates

        guard coordinates.count >= 2 else { return }

        state.segmentProgress += progressPerTick

        if state.segmentProgress >= 1 {
            state.segmentProgress = 0

            if state.isMovingForward {
                if state.currentSegmentIndex + 1 <
                    coordinates.count - 1 {

                    state.currentSegmentIndex += 1
                } else {
                    state.isMovingForward = false
                }
            } else {
                if state.currentSegmentIndex > 0 {
                    state.currentSegmentIndex -= 1
                } else {
                    state.isMovingForward = true
                }
            }
        }

        routeStates[index] = state
    }

    // MARK: - Conversión a VehiclePosition

    private func makeVehiclePosition(
        from state: SimulatedRouteState
    ) -> VehiclePosition {
        let coordinates = state.coordinates

        let firstIndex = min(
            state.currentSegmentIndex,
            coordinates.count - 2
        )

        let secondIndex = firstIndex + 1

        let pointA = coordinates[firstIndex]
        let pointB = coordinates[secondIndex]

        let origin = state.isMovingForward ? pointA : pointB
        let destination = state.isMovingForward ? pointB : pointA

        let latitude =
            origin.latitude +
            (destination.latitude - origin.latitude) *
            state.segmentProgress

        let longitude =
            origin.longitude +
            (destination.longitude - origin.longitude) *
            state.segmentProgress

        let heading = calculateHeading(
            from: origin,
            to: destination
        )

        let segmentDistance = PolylineMatching.distanceMeters(
            origin,
            destination
        )

        let estimatedSpeed =
            segmentDistance *
            progressPerTick /
            tickInterval

        return VehiclePosition(
            id: state.vehicleId,
            linea: state.linea,
            lat: latitude,
            lon: longitude,
            heading: heading,
            speed: estimatedSpeed,
            timestamp: Date().timeIntervalSince1970
        )
    }

    private func calculateHeading(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) -> Double {
        let deltaLatitude =
            destination.latitude - origin.latitude

        let deltaLongitude =
            destination.longitude - origin.longitude

        let degrees =
            atan2(deltaLongitude, deltaLatitude) *
            180 /
            .pi

        return degrees >= 0 ? degrees : degrees + 360
    }
}
