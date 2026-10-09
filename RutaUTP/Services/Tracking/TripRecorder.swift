import Foundation
import CoreLocation

/// Dueño del historial mutable del viaje; no publica el array a la interfaz.
@MainActor
final class TripRecorder {
    private var sesion: TripSession

    init(sesion: TripSession) {
        self.sesion = sesion
    }

    /// Snapshot de valor bajo demanda. Retenerlo conserva sus puntos anteriores.
    var snapshot: TripSession { sesion }
    var estado: TripState { sesion.estado }
    var startedAt: TimeInterval? { sesion.startedAt }
    var cantidadPuntos: Int { sesion.puntosRecorridos.count }

    @discardableResult
    func registrarPunto(_ coord: CLLocationCoordinate2D, rumbo: Double) -> Bool {
        // Muestreo con separación mínima de 3 m para no inundar el historial.
        if let ultimo = sesion.puntosRecorridos.last,
           PolylineMatching.distanceMeters(ultimo.coordinate, coord) < 3 { return false }
        sesion.puntosRecorridos.append(
            TrackingPoint(lat: coord.latitude, lon: coord.longitude,
                          heading: max(0, rumbo))
        )
        return true
    }

    func actualizarEstado(_ nuevo: TripState) {
        sesion.estado = nuevo
    }

    func finalizar(estado nuevo: TripState) {
        sesion.estado = nuevo
        sesion.endedAt = Date().timeIntervalSince1970
    }
}
