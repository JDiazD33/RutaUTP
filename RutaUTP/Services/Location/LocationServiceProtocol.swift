//
//  LocationServiceProtocol.swift
//  RutaUTP
//
//  Abstracción sobre CLLocationManager para inyectar en ViewModels y
//  poder testear/swappear la fuente de ubicación.
//
//  Decisión de diseño:
//   - `currentLocation` es un AsyncStream<CLLocation> (consumo moderno
//     async/await, alineado con el resto del módulo nuevo de tracking).
//   - `authorizationStatus` es @Published vía la implementación concreta
//     (CLLocationManagerDelegate automaticamente en ObservableObject),
//     porque los flujos de "el usuario niega/acecha el permiso" reaccionan
//     mejor a un ObservableObject suelto que a un stream de permisos.
//

import Foundation
import CoreLocation
import Combine

protocol LocationServiceProtocol: AnyObject {
    /// Estado de permiso observable para que la UI reaccione.
    var authorizationStatus: CLAuthorizationStatus { get }

    /// Publisher del estado de permiso (la impl real expone @Published).
    var authorizationPublisher: AnyPublisher<CLAuthorizationStatus, Never> { get }

    /// Stream async de ubicaciones a medida que llegan del CLLocationManager.
    func currentLocation() -> AsyncStream<CLLocation>

    /// Solicita permiso al usuario (solo si el status es .notDetermined).
    func requestPermission() async -> CLAuthorizationStatus

    /// Comienza a recibir updates. Idempotente.
    func startUpdating()

    /// Detiene los updates y cierra el stream activo.
    func stopUpdating()
}

// MARK: - Helpers de permiso (libres de UIColor/UIKit)

extension CLAuthorizationStatus {
    /// True si el permiso está concedido (When In Use o Always).
    var isAuthorized: Bool {
        switch self {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }

    /// True si el permiso fue denegado o restringido (no hay nada que hacer
    /// salvo mandar al usuario a Ajustes).
    var isDenied: Bool {
        switch self {
        case .denied, .restricted:
            return true
        default:
            return false
        }
    }
}
