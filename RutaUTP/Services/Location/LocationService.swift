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
    private let continuationsLock = NSLock()
    private var continuations: [UUID: AsyncStream<CLLocation>.Continuation] = [:]
    private(set) var lastKnownLocation: CLLocation?

    // Tunables
    private let distanceFilter: CLLocationDistance = 5    // metros para respuesta rápida
    private let desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest

    // Avoid duplicate start
    private var isUpdating: Bool = false
    /// Un cambio de permiso no debe reactivar un servicio que ya se detuvo.
    private var updatesRequested = false

    override init() {
        self.manager = CLLocationManager()
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = desiredAccuracy
        manager.distanceFilter = distanceFilter
        manager.activityType = .automotiveNavigation
        
        // Cargar ubicación almacenada en el manager si está disponible
        if let loc = manager.location {
            self.lastKnownLocation = loc
        }
    }

    // MARK: - LocationServiceProtocol

    func requestPermission() async -> CLAuthorizationStatus {
        guard authorizationStatus == .notDetermined else {
            return authorizationStatus
        }
        
        manager.requestWhenInUseAuthorization()

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
        let id = UUID()
        return AsyncStream { continuation in
            self.continuationsLock.lock()
            self.continuations[id] = continuation
            self.continuationsLock.unlock()

            // Emitir la última ubicación conocida o la actual del manager de inmediato
            if let loc = self.lastKnownLocation ?? self.manager.location {
                self.lastKnownLocation = loc
                continuation.yield(loc)
            }

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.continuationsLock.lock()
                self.continuations.removeValue(forKey: id)
                self.continuationsLock.unlock()
            }
        }
    }

    func startUpdating() {
        updatesRequested = true
        guard authorizationStatus.isAuthorized else { return }
        
        // Emitir ubicación previa a los continuations existentes si la tenemos
        if let loc = manager.location ?? lastKnownLocation {
            lastKnownLocation = loc
            for continuation in activeContinuations {
                continuation.yield(loc)
            }
        }
        
        guard !isUpdating else { return }
        manager.startUpdatingLocation()
        isUpdating = true
    }

    func stopUpdating() {
        updatesRequested = false
        manager.stopUpdatingLocation()
        isUpdating = false
        // finish() puede ejecutar onTermination: vaciar bajo el candado y
        // finalizar fuera de él evita mutaciones durante la iteración.
        continuationsLock.lock()
        let pendientes = Array(continuations.values)
        continuations.removeAll()
        continuationsLock.unlock()
        pendientes.forEach { $0.finish() }
    }

    private var activeContinuations: [AsyncStream<CLLocation>.Continuation] {
        continuationsLock.lock()
        defer { continuationsLock.unlock() }
        return Array(continuations.values)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if updatesRequested && !isUpdating { startUpdating() }
        case .denied, .restricted:
            stopUpdating()
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        guard isUpdating, let location = locations.last else { return }
        lastKnownLocation = location
        for continuation in activeContinuations {
            continuation.yield(location)
        }
    }

    func locationManager(_ manager: CLLocationManager,
                         didFailWithError error: Error) {
        #if DEBUG
        print("[LocationService] didFailWithError: \(error.localizedDescription)")
        #endif
    }
}
