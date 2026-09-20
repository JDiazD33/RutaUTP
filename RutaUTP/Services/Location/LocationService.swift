//
//  LocationService.swift
//  RutaUTP
//
//  Implementación real de LocationServiceProtocol sobre CLLocationManager.
//
//  Diseño:
//   - NSObject + ObservableObject para usar @Published y CLLocationManagerDelegate.
//   - distanceFilter = 5m (suficiente para tracking de bus a velocidad urbana).
//   - desiredAccuracy = kCLLocationAccuracyBest.
//   - NO fuerza unwrap ni crashea si el permiso es denegado: solo actualiza
//     `authorizationStatus` y deja de emitir ubicación.
//   - El AsyncStream se crea perezosamente por llamada a currentLocation():
//     si alguien pide el stream antes de startUpdating, queda esperando sin
//     emitir nada hasta que llegue la primera fix.
//   - TODO (cuando se defina rol conductor): añadir startMonitoringSignificantLocationChanges()
//     y permitir background updates (ver Info.plist UIBackModes).
//
//  IMPORTANTE — este servicio es COMPARTIDO y ahora tiene varios consumidores:
//  el mapa y el rastreo pasivo (`PassiveTrackingCoordinator`) piden ubicación a
//  la vez. De ahí dos reglas que no se pueden relajar:
//
//   1. `stopUpdating()` **no** apaga el gestor si queda algún consumidor. Una
//      pantalla que se cierra no puede dejar sin GPS al rastreo pasivo, que
//      sigue aportando observaciones.
//   2. Quien deja de consumir libera **su propia** continuación (cancelando la
//      tarea que recorre el stream). El gestor se apaga solo cuando se va el
//      último, y ese apagado ocurre en `onTermination`.
//
//  La sincronización se hace con un candado y no confiando en el hilo del
//  llamador: `AsyncStream` puede ejecutar `onTermination` desde un contexto
//  distinto y los callbacks de `CLLocationManager` llegan por el run loop.
//

import Foundation
import CoreLocation
import Combine

/// `@unchecked Sendable`: todo el estado mutable (`continuations`,
/// `lastKnownLocation`, `isUpdating`, `updatesRequested`) se toca desde la cola
/// principal —los métodos públicos se llaman desde `MainActor` y los callbacks
/// del gestor y `onTermination` saltan a main antes de modificar nada—, y el
/// diccionario de continuaciones además queda bajo `continuationsLock`. El
/// compilador no puede comprobarlo, así que se declara aquí de forma explícita.
final class LocationService: NSObject, LocationServiceProtocol, ObservableObject,
                             CLLocationManagerDelegate, @unchecked Sendable {

    // MARK: - Estado observable (para que la UI reaccione)
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    var authorizationPublisher: AnyPublisher<CLAuthorizationStatus, Never> {
        $authorizationStatus.eraseToAnyPublisher()
    }

    // MARK: - Internos
    private let manager: CLLocationManager
    /// Protege `continuations`: se lee desde el run loop y se escribe desde
    /// `onTermination`, que puede llegar de otro contexto.
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
                // AsyncStream puede ejecutar esta clausura desde un contexto
                // distinto. El gestor y el registro de consumidores se
                // administran en la cola principal para evitar modificaciones
                // concurrentes, y el diccionario va bajo el candado.
                DispatchQueue.main.async {
                    guard let self else {
                        return
                    }

                    self.continuationsLock.lock()
                    self.continuations.removeValue(forKey: id)
                    self.continuationsLock.unlock()

                    // El GPS solo se apaga cuando terminó el último consumidor.
                    // Si el coordinador pasivo todavía escucha ubicaciones,
                    // continúa.
                    self.stopManagerIfUnused()
                }
            }
        }
    }

    func startUpdating() {
        updatesRequested = true
        guard authorizationStatus.isAuthorized else { return }

        // Emitir ubicación previa a los consumidores existentes si la tenemos
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

    /// Solicita detener las actualizaciones de ubicación.
    ///
    /// El servicio es compartido: **no** apaga el gestor si otro consumidor
    /// sigue escuchando. Ver la nota de diseño al principio del archivo.
    func stopUpdating() {
        updatesRequested = false
        stopManagerIfUnused()
    }

    /// Instantánea de las continuaciones vivas, tomada bajo el candado.
    private var activeContinuations: [AsyncStream<CLLocation>.Continuation] {
        continuationsLock.lock()
        defer { continuationsLock.unlock() }
        return Array(continuations.values)
    }

    /// Detiene CLLocationManager únicamente cuando ningún componente mantiene
    /// un stream activo de ubicación.
    ///
    /// Esto evita que una pantalla apague el GPS utilizado simultáneamente por
    /// `PassiveTrackingCoordinator` u otra pantalla.
    private func stopManagerIfUnused() {
        guard activeContinuations.isEmpty else {
            #if DEBUG
            print(
                "[LocationService] El GPS continúa activo: " +
                "\(activeContinuations.count) consumidor(es)"
            )
            #endif

            return
        }

        guard isUpdating else {
            return
        }

        manager.stopUpdatingLocation()
        isUpdating = false

        #if DEBUG
        print(
            "[LocationService] GPS detenido: " +
            "no quedan consumidores"
        )
        #endif
    }

    /// Detiene obligatoriamente el GPS y finaliza todos los streams.
    ///
    /// Solo debe utilizarse cuando iOS deniega o restringe el permiso. En ese
    /// escenario ningún consumidor tiene autorización para seguir recibiendo
    /// ubicaciones.
    private func forceStopUpdating() {
        updatesRequested = false
        manager.stopUpdatingLocation()
        isUpdating = false

        continuationsLock.lock()
        let activos = Array(continuations.values)
        continuations.removeAll()
        continuationsLock.unlock()

        // `finish()` puede disparar `onTermination`; se llama fuera del candado
        // para no mutar el diccionario mientras se itera.
        activos.forEach { $0.finish() }

        #if DEBUG
        print(
            "[LocationService] GPS detenido por falta de permiso"
        )
        #endif
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            // Se reanuda solo si alguien lo pidió **y** queda un consumidor.
            // Antes bastaba con que el permiso pasara a concedido, así que
            // otorgarlo desde Ajustes —con la app abierta y sin ninguna
            // pantalla pidiendo ubicación— encendía el GPS sin que nadie lo
            // hubiera solicitado.
            if updatesRequested, !isUpdating, !activeContinuations.isEmpty {
                startUpdating()
            }
        case .denied, .restricted:
            // La ausencia de autorización prevalece sobre cualquier consumidor.
            forceStopUpdating()
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
