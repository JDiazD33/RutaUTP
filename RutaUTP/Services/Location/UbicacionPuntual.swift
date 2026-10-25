// UbicacionPuntual.swift
// Separado por responsabilidad; conserva el comportamiento existente.

import Foundation
import Combine
import CoreLocation

/// Obtiene una posición puntual sin apropiarse del ciclo del GPS compartido.
/// El fin del lector libera su stream; `LocationService.onTermination` apaga
/// el gestor únicamente si no quedan consumidores. No se llama stopUpdating,
/// porque también cambiaría la demanda global de los demás consumidores.
@MainActor
enum UbicacionPuntual {
    static func obtener(
        desde service: LocationServiceProtocol,
        timeout: TimeInterval = 12,
        antiguedadMaxima: TimeInterval = 45,
        precisionMaxima: CLLocationAccuracy = 50,
        ahora: @escaping () -> Date = Date.init
    ) async -> CLLocation? {
        guard !Task.isCancelled, timeout.isFinite, timeout > 0,
              antiguedadMaxima.isFinite, antiguedadMaxima > 0,
              precisionMaxima.isFinite, precisionMaxima >= 0 else { return nil }
        // El plazo incluye el diálogo de permiso. Antes solo empezaba después
        // de aceptarlo, por lo que una pantalla podía seguir cargando sin límite.
        let resultado = await withTaskGroup(of: CLLocation?.self) { grupo in
            grupo.addTask { @MainActor in
                await obtenerConPermiso(desde: service, antiguedadMaxima: antiguedadMaxima,
                                        precisionMaxima: precisionMaxima, ahora: ahora)
            }
            grupo.addTask {
                let nanosegundos = UInt64(min(timeout, 60) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanosegundos)
                return nil
            }
            let resultado = await grupo.next() ?? nil
            grupo.cancelAll()
            return resultado
        }
        guard !Task.isCancelled, service.authorizationStatus.isAuthorized else { return nil }
        return resultado
    }

    private static func obtenerConPermiso(
        desde service: LocationServiceProtocol,
        antiguedadMaxima: TimeInterval,
        precisionMaxima: CLLocationAccuracy,
        ahora: @escaping () -> Date
    ) async -> CLLocation? {
        guard !Task.isCancelled else { return nil }
        // iOS conserva su diálogo; el servicio real permite cancelar nuestra
        // espera. Comprobarlo al volver también protege proveedores alternativos.
        let permiso = await service.requestPermission()
        guard !Task.isCancelled, permiso.isAuthorized,
              service.authorizationStatus.isAuthorized else { return nil }

        var suscripcion: AnyCancellable?
        let permisos = AsyncStream<CLAuthorizationStatus> { continuation in
            suscripcion = service.authorizationPublisher.sink { continuation.yield($0) }
        }
        defer { suscripcion?.cancel() }

        let resultado = await withTaskGroup(of: CLLocation?.self) { grupo in
            grupo.addTask { @MainActor in
                guard !Task.isCancelled, service.authorizationStatus.isAuthorized else { return nil }
                // El stream existe antes de startUpdating: el primer fix puede
                // llegar inmediatamente, incluida la caché del servicio.
                let lecturas = service.currentLocation()
                guard !Task.isCancelled else { return nil }
                service.startUpdating()
                for await lectura in lecturas {
                    guard !Task.isCancelled, service.authorizationStatus.isAuthorized else { return nil }
                    if esValida(lectura, ahora: ahora(), antiguedadMaxima: antiguedadMaxima,
                                precisionMaxima: precisionMaxima) {
                        return lectura
                    }
                }
                return nil
            }
            grupo.addTask { @MainActor in
                for await estado in permisos {
                    if !estado.isAuthorized { return nil }
                }
                return nil
            }
            let resultado = await grupo.next() ?? nil
            grupo.cancelAll()
            return Task.isCancelled ? nil : resultado
        }
        // El grupo drena sus hijos antes de volver. La autorización puede
        // revocarse durante esa suspensión, después de aceptar el primer fix.
        guard !Task.isCancelled, service.authorizationStatus.isAuthorized else { return nil }
        return resultado
    }

    static func esValida(_ location: CLLocation, ahora: Date,
                         antiguedadMaxima: TimeInterval = 45,
                         precisionMaxima: CLLocationAccuracy = 50) -> Bool {
        let edad = ahora.timeIntervalSince(location.timestamp)
        return antiguedadMaxima.isFinite && antiguedadMaxima > 0
            && edad.isFinite && edad >= -10 && edad <= antiguedadMaxima
            && precisionMaxima.isFinite && precisionMaxima >= 0
            && location.horizontalAccuracy.isFinite
            && location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= precisionMaxima
            && CLLocationCoordinate2DIsValid(location.coordinate)
    }
}
