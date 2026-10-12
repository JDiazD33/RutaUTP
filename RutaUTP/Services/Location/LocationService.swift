//
//  LocationService.swift
//  RutaUTP
//
//  Implementación real de LocationServiceProtocol sobre CLLocationManager.
//
//  Diseño:
//   - NSObject + ObservableObject para usar @Published y CLLocationManagerDelegate.
//   - Best/5m si hay navegación, detección o un consumidor sin requisito explícito.
//   - NearestTenMeters/15m solo cuando todos los lectores son de mapa.
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
//  El contrato está aislado en MainActor. `onTermination` puede ejecutarse
//  desde otro contexto y salta a ese actor antes de retirar el consumidor.
//

import Foundation
import CoreLocation
import Combine

/// La creación del gestor, sus consumidores y el estado observable pertenecen
/// a MainActor; el compilador exige el mismo contrato a proveedores alternativos.
@MainActor
final class LocationService: NSObject, LocationServiceProtocol, ObservableObject,
                             CLLocationManagerDelegate {

    // MARK: - Estado observable (para que la UI reaccione)
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    var authorizationPublisher: AnyPublisher<CLAuthorizationStatus, Never> {
        $authorizationStatus.eraseToAnyPublisher()
    }

    // MARK: - Internos
    private let manager: CLLocationManager
    private let esperasPermiso = EsperasPermisoUbicacion()
    private struct Consumer {
        let continuation: AsyncStream<CLLocation>.Continuation
        let requirement: LocationRequirement
    }
    private var continuations: [UUID: Consumer] = [:]
    private(set) var lastKnownLocation: CLLocation?

    private var appliedRequirement: LocationRequirement = .navigation

    // Avoid duplicate start
    private var isUpdating: Bool = false
    /// Un cambio de permiso no debe reactivar un servicio que ya se detuvo.
    private var updatesRequested = false

    override init() {
        self.manager = CLLocationManager()
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = appliedRequirement.desiredAccuracy
        manager.distanceFilter = appliedRequirement.distanceFilter
        manager.activityType = .automotiveNavigation

        // Cargar ubicación almacenada en el manager si está disponible
        if let loc = manager.location {
            self.lastKnownLocation = loc
        }
    }

    // MARK: - LocationServiceProtocol

    func requestPermission() async -> CLAuthorizationStatus {
        await esperasPermiso.esperar(estado: authorizationStatus) {
            manager.requestWhenInUseAuthorization()
        }
    }

    func currentLocation() -> AsyncStream<CLLocation> {
        currentLocation(requirement: .navigation)
    }

    func currentLocation(requirement: LocationRequirement) -> AsyncStream<CLLocation> {
        let id = UUID()
        return AsyncStream { continuation in
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }

                    self.continuations.removeValue(forKey: id)
                    self.applyActiveRequirements()

                    // El GPS solo se apaga cuando terminó el último consumidor.
                    // Si el coordinador pasivo todavía escucha ubicaciones,
                    // continúa.
                    self.stopManagerIfUnused()
                }
            }

            // El registro es inmediato en MainActor: no puede quedar encolado
            // después de que onTermination haya retirado este mismo consumidor.
            self.register(continuation, id: id, requirement: requirement)
        }
    }

    private func register(_ continuation: AsyncStream<CLLocation>.Continuation,
                          id: UUID, requirement: LocationRequirement) {
        continuations[id] = Consumer(continuation: continuation, requirement: requirement)
        applyActiveRequirements()

        // Conservar el replay de la última lectura, sin esperar un nuevo fix.
        if let loc = lastKnownLocation ?? manager.location {
            lastKnownLocation = loc
            continuation.yield(loc)
        }
    }

    /// Solo los lectores de mapa pueden bajar la exigencia. La API anterior
    /// y cualquier consumidor de navegación mantienen Best/5m.
    private func applyActiveRequirements() {
        let requirement: LocationRequirement = continuations.isEmpty
            || continuations.values.contains { $0.requirement == .navigation }
            ? .navigation : .mapDisplay

        guard requirement != appliedRequirement else { return }
        manager.desiredAccuracy = requirement.desiredAccuracy
        manager.distanceFilter = requirement.distanceFilter
        appliedRequirement = requirement
    }

    func startUpdating() {
        updatesRequested = true
        guard authorizationStatus.isAuthorized else { return }
        applyActiveRequirements()

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

    /// Instantánea de las continuaciones vivas en MainActor.
    private var activeContinuations: [AsyncStream<CLLocation>.Continuation] {
        return continuations.values.map(\.continuation)
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

        updatesRequested = false
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

        let activos = continuations.values.map(\.continuation)
        continuations.removeAll()
        applyActiveRequirements()

        // finish puede disparar onTermination, que vuelve al actor por una tarea.
        activos.forEach { $0.finish() }

        #if DEBUG
        print(
            "[LocationService] GPS detenido por falta de permiso"
        )
        #endif
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let estado = manager.authorizationStatus
        Task { @MainActor [weak self] in self?.recibirAutorizacion(estado) }
    }

    private func recibirAutorizacion(_ estado: CLAuthorizationStatus) {
        // Un aviso que esperó el salto al actor no debe restaurar un permiso
        // anterior ni cerrar lectores creados después de otro cambio.
        guard estado == manager.authorizationStatus else { return }
        authorizationStatus = estado
        esperasPermiso.resolver(estado)
        switch estado {
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

    nonisolated func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor [weak self] in self?.recibirUbicaciones(locations) }
    }

    private func recibirUbicaciones(_ locations: [CLLocation]) {
        guard isUpdating, let location = locations.last else { return }
        lastKnownLocation = location
        for continuation in activeContinuations {
            continuation.yield(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                         didFailWithError error: Error) {
        #if DEBUG
        print("[LocationService] didFailWithError: \(error.localizedDescription)")
        #endif
    }
}

/// Se puede comprobar sin CLLocationManager ni una solicitud de permiso real.
@MainActor
final class EsperasPermisoUbicacion {
    private var estado: CLAuthorizationStatus = .notDetermined
    private var pendientes: [UUID: CheckedContinuation<CLAuthorizationStatus, Never>] = [:]
    var cantidadPendiente: Int { pendientes.count }

    func esperar(estado: CLAuthorizationStatus, solicitar: () -> Void) async -> CLAuthorizationStatus {
        self.estado = estado
        guard estado == .notDetermined, !Task.isCancelled else { return estado }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: self.estado)
                    return
                }
                pendientes[id] = continuation
                // Registrar antes de solicitar también admite respuestas síncronas.
                if pendientes.count == 1 { solicitar() }
            }
        } onCancel: {
            Task { @MainActor in self.cancelar(id) }
        }
    }

    func resolver(_ estado: CLAuthorizationStatus) {
        self.estado = estado
        guard estado != .notDetermined else { return }
        let anteriores = pendientes.values
        pendientes.removeAll()
        anteriores.forEach { $0.resume(returning: estado) }
    }

    private func cancelar(_ id: UUID) {
        pendientes.removeValue(forKey: id)?.resume(returning: estado)
    }
}
