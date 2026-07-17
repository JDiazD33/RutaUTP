//
//  RouteTrackingViewModel.swift
//  RutaUTP
//
//  ViewModel de la pantalla de prueba de tracking de ruta en tiempo real.
//
//  Responsabilidad:
//   - Pedir permiso de ubicación.
//   - Mantener `userLocation` observable.
//   - Cuando el usuario lanza un viaje (startTripUTP), calcular la ruta con
//     RouteCalculationService → polyline + ETA.
//   - En cada update de ubicación, hacer snap-to-road contra la polyline
//     activa y detectar desvíos ≥ 20m durante N muestras consecutivas,
//     en cuyo caso marcar `recalculating = true` y recalcular.
//
//  Recibe el `LocationServiceProtocol` por init para poder testear con un
//  mock location service y para desacoplar del singleton implícito.
//

import Foundation
import Combine
import CoreLocation
import MapKit

@MainActor
final class RouteTrackingViewModel: ObservableObject {

    // MARK: - Salida expuesta a la vista (estado observable)
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var routePolyline: MKPolyline?
    @Published var eta: TimeInterval?           // segundos
    @Published var distance: Double?            // metros
    @Published var recalculating: Bool = false
    @Published var tripInProgress: Bool = false
    @Published var errorMessage: String? = nil
    /// Estado del permiso bindingable desde la UI.
    @Published var authStatus: CLAuthorizationStatus = .notDetermined

    // MARK: - Dependencias
    private let locationService: LocationServiceProtocol
    private let routeService: RouteCalculationService
    /// Destino del viaje actual (si lo hay).
    private var destination: CLLocationCoordinate2D? = nil

    // MARK: - Panadero interno del matching
    private var consecutiveOffRoute: Int = 0
    private var lastMatch: PolylineMatching.MatchResult? = nil
    private var polyCoords: [CLLocationCoordinate2D] = []

    // Task para cancelar el bucle de consumo del stream de ubicación.
    private var locationTask: Task<Void, Never>?

    // Cancellable del publisher de permiso (se mantiene vivo lo que dura el VM).
    private var authCancellable: AnyCancellable?

    // MARK: - Init
    init(locationService: LocationServiceProtocol,
         routeService: RouteCalculationService = RouteCalculationService()) {
        self.locationService = locationService
        self.routeService = routeService

        // Bind del estado de permiso del servicio al nuestro @Published.
        // Mantenemos el cancellable vivo en self para que no se cancelar sink.
        authCancellable = locationService.authorizationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.authStatus = status
            }
    }

    deinit {
        locationTask?.cancel()
    }

    // MARK: - Permisos

    func requestPermissionAndStart() async {
        let status = await locationService.requestPermission()
        await MainActor.run { self.authStatus = status }
        if status.isAuthorized {
            startObservingLocation()
            locationService.startUpdating()
        } else {
            await MainActor.run {
                self.errorMessage = "Permiso de ubicación denegado. Actívalo en Ajustes para usar el tracking."
            }
        }
    }

    // MARK: - Observación de ubicación

    private func startObservingLocation() {
        locationTask?.cancel()
        locationTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            let stream = self.locationService.currentLocation()
            for await location in stream {
                self.handleNewLocation(location)
            }
        }
    }

    private func handleNewLocation(_ location: CLLocation) {
        userLocation = location.coordinate

        guard tripInProgress, let _ = destination, !polyCoords.isEmpty else { return }

        // 1. Evitar muestras redundantes (si el vehicular/usuario está parado).
        // 2. Snap-to-road y detección de desvío.
        let match = PolylineMatching.match(
            point: location.coordinate,
            on: polyCoords,
            thresholdMeters: 20.0
        )
        lastMatch = match

        if let match = match {
            if match.isOnRoute {
                consecutiveOffRoute = 0
            } else {
                consecutiveOffRoute += 1
            }

            // Si经过了muchas muestras off-route, marcar para recálculo.
            if PolylineMatching.shouldRecalculate(
                lastMatch: match,
                consecutiveOffRouteCount: consecutiveOffRoute,
                thresholdCount: 3
            ) {
                Task { @MainActor in await self.recalculate(from: location.coordinate) }
            }

            // Actualizar ETA basado en progreso (estimación muy naive):
            // ETA_restante = ETA_total * (1 - progreso).
            if let totalETA = eta {
                let remaining = totalETA * (1 - match.progressFraction)
                eta = max(0, remaining)
            }
        }
    }

    // MARK: - Inicio de viaje (caso de prueba: UTP)

    /// Lanza un viaje desde la posición actual至 el destino de la "línea" indicada.
    /// Usa `RutaCoordenadas.para(linea:)` existente para no inventar coords.
    func startTripUTP(linea: String = "10") async {
        let status = authStatus
        guard status.isAuthorized else {
            errorMessage = "Sin permiso de ubicación. Concedelo en Ajustes."
            return
        }
        guard let userLoc = userLocation else {
            errorMessage = "Aún no tenemos tu ubicación. Espera unos segundos."
            return
        }
        let coords = RutaCoordenadas.para(linea: linea)
        guard let dest = coords.last else {
            errorMessage = "No hay destino para la línea \(linea)."
            return
        }
        destination = dest
        tripInProgress = true
        errorMessage = nil
        await calculate(from: userLoc, to: dest)
    }

    /// Recalcular ruta desde la posición actual al destination almacenado.
    @MainActor
    private func recalculate(from currentOrigin: CLLocationCoordinate2D) async {
        guard let dst = destination else { return }
        recalculating = true
        await calculate(from: currentOrigin, to: dst)
        recalculating = false
        consecutiveOffRoute = 0
    }

    @MainActor
    private func calculate(from origin: CLLocationCoordinate2D,
                           to destination: CLLocationCoordinate2D) async {
        do {
            // Probamos .transit; si no hay, cae en .automobile (better than nada).
            let route: CalculatedRoute
            do {
                route = try await routeService.calculateRoute(from: origin,
                                                              to: destination,
                                                              transportType: .transit)
            } catch {
                // Fallback:automovil.
                route = try await routeService.calculateRoute(from: origin,
                                                              to: destination,
                                                              transportType: .automobile)
            }
            self.routePolyline = route.polyline
            self.eta = route.expectedTravelTime
            self.distance = route.distance
            self.polyCoords = PolylineMatching.coordinates(from: route.polyline)
        } catch {
            self.errorMessage = "No se pudo calcular la ruta: \(error.localizedDescription)"
            self.tripInProgress = false
        }
    }

    // MARK: - Cancelación

    func cancelTrip() {
        tripInProgress = false
        destination = nil
        routePolyline = nil
        eta = nil
        distance = nil
        polyCoords.removeAll()
        lastMatch = nil
        consecutiveOffRoute = 0
        recalculating = false
    }

    func stop() {
        cancelTrip()
        locationTask?.cancel()
        locationService.stopUpdating()
    }
}
