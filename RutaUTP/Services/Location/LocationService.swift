//
//  LocationService.swift
//  RutaUTP
//
//  Implementación real de LocationServiceProtocol sobre CLLocationManager.
//
//  Diseño:
//   - NSObject + ObservableObject para usar @Published y CLLocationManagerDelegate.
//   - distanceFilter = 10m (suficiente para tracking de bus a velocidad urbana).
//   - desiredAccuracy = kCLLocationAccuracyBest.
//   - NO fuerza unwrap ni crashea si el permiso es denegado: solo actualiza
//     `authorizationStatus` y deja de emitir ubicación.
//   - El AsyncStream se crea perezosamente por llamada a currentLocation():
//     si alguien pide el stream antes de startUpdating, queda esperando sin
//     emitir nada hasta que llegue la primera fix.
//   - TODO (cuando se defina rol conductor): añadir startMonitoringSignificantLocationChanges()
//     y permitir background updates (ver Info.plist UIBackModes).
//

import Foundation
import CoreLocation
import Combine

final class LocationService: NSObject, LocationServiceProtocol, ObservableObject, CLLocationManagerDelegate {

    // MARK: - Estado observable (para que la UI reaccione)
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    var authorizationPublisher: AnyPublisher<CLAuthorizationStatus, Never> {
        $authorizationStatus.eraseToAnyPublisher()
    }

    // MARK: - Internos
    private let manager: CLLocationManager
    private var continuation: AsyncStream<CLLocation>.Continuation?
    private(set) var lastKnownLocation: CLLocation?

    // Tunables
    private let distanceFilter: CLLocationDistance = 10   // metros
    private let desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest

    // Avoid duplicate start
    private var isUpdating: Bool = false

    override init() {
        self.manager = CLLocationManager()
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = desiredAccuracy
        manager.distanceFilter = distanceFilter
        // activityType específico para transporte públicopeatonal. Mejora la
        //Kalman interna de iOS en vehículos que paran/arrancan.
        manager.activityType = .automotiveNavigation
    }

    // MARK: - LocationServiceProtocol

    func requestPermission() async -> CLAuthorizationStatus {
        // Volver a pedir solo tiene sentido si estado es .notDetermined.
        guard authorizationStatus == .notDetermined else {
            return authorizationStatus
        }
        // CuandoInUso y luego pedir Always (pixel-perfect futuro).
        if Bundle.main.object(forInfoDictionaryKey: "NSLocationAlwaysAndWhenInUseUsageDescription") != nil {
            manager.requestAlwaysAuthorization()
        } else {
            manager.requestWhenInUseAuthorization()
        }
        // Para evitar anti-patrón "async shell", esperamos con un pequeño
        // publisher: primer cambio de estado distinto a .notDetermined.
        return await withCheckedContinuation { continuation in
            var cancellable: AnyCancellable?
            cancellable = self.$authorizationStatus
                .dropFirst()
                .filter { $0 != .notDetermined }
                .first()
                .sink { status in
                    continuation.resume(returning: status)
                    cancellable?.cancel()
                }
        }
    }

    func currentLocation() -> AsyncStream<CLLocation> {
        // Cada consumidor obtiene su propio stream. heartbreaking power: ok
        // si el stream ya está activo se yielda también a este nuevo.
        // Simplificación: un único continuation que alimenta TODOS los
        // streams pedidos. Aquí devolvemos un stream que se bridgea al último.
        let last = self.lastKnownLocation
        return AsyncStream { continuation in
            if let last = last {
                continuation.yield(last)
            }
            // Bridge: mantenemos solo el último continuation.
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in
                self?.continuation = nil
            }
        }
    }

    func startUpdating() {
        guard !isUpdating else { return }
        guard authorizationStatus.isAuthorized else {
            // No podemos arrancar sin permiso. El consumidor debe pedirlo.
            return
        }
        manager.startUpdatingLocation()
        isUpdating = true
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
        isUpdating = false
        continuation?.finish()
        continuation = nil
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            // Si ya estábamos pidiendo updates, arrancar ahora.
            if !isUpdating { startUpdating() }
        case .denied, .restricted:
            // Detener updates si los había, no crashear.
            stopUpdating()
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastKnownLocation = location
        continuation?.yield(location)
    }

    func locationManager(_ manager: CLLocationManager,
                         didFailWithError error: Error) {
        // Errores comunes: CLError.denied, CLError.network, CLError.headingFailure.
        // No queremos crashear la UI. El consumidor puede observer
        // `lastKnownLocation == nil` para mostrar un mensaje.
        #if DEBUG
        print("[LocationService] didFailWithError: \(error.localizedDescription)")
        #endif
    }
}
