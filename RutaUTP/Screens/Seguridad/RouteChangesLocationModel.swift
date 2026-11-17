// RouteChangesLocationModel.swift
// Separado por responsabilidad; conserva el comportamiento existente.

import Foundation
import Combine
import CoreLocation

/// La lectura tardía solo ofrece una ubicación: colocar el pin sigue sujeto
/// a la selección actual y nunca sustituye un pin ni un borrador del mapa ampliado.
@MainActor
final class RouteChangesLocationModel: ObservableObject {
    @Published private(set) var coordenada: CLLocationCoordinate2D?
    private var revision = 0

    func cargar(desde service: LocationServiceProtocol, timeout: TimeInterval = 12,
                ahora: @escaping () -> Date = Date.init) async {
        revision &+= 1
        let solicitud = revision
        let location = await UbicacionPuntual.obtener(desde: service, timeout: timeout, ahora: ahora)
        guard !Task.isCancelled, revision == solicitud else { return }
        coordenada = location?.coordinate
    }

    /// Última posición conocida de los últimos minutos, solo para centrar el
    /// mapa al abrir: quien está quieto no genera lecturas nuevas del GPS y la
    /// lectura fresca puede no llegar.
    static func aproximada(de service: LocationServiceProtocol,
                           ahora: Date = Date()) -> CLLocationCoordinate2D? {
        guard service.authorizationStatus.isAuthorized,
              let ultima = (service as? LocationService)?.lastKnownLocation,
              UbicacionPuntual.esValida(ultima, ahora: ahora, antiguedadMaxima: 15 * 60,
                                        precisionMaxima: 3_000) else { return nil }
        return ultima.coordinate
    }

    func puntoAutomatico(para ruta: RutaGTFS?, puntoActual: CLLocationCoordinate2D?,
                         editadoAMano: Bool, mapaAmpliadoAbierto: Bool) -> CLLocationCoordinate2D? {
        guard !editadoAMano, !mapaAmpliadoAbierto, puntoActual == nil,
              let ruta, let aqui = coordenada,
              let veredicto = VerificadorCoherencia.evaluar(point: aqui, ruta: ruta),
              veredicto.esValido else { return nil }
        return aqui
    }
}
