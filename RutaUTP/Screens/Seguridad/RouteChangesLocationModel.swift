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

    func puntoAutomatico(para ruta: RutaGTFS?, puntoActual: CLLocationCoordinate2D?,
                         editadoAMano: Bool, mapaAmpliadoAbierto: Bool) -> CLLocationCoordinate2D? {
        guard !editadoAMano, !mapaAmpliadoAbierto, puntoActual == nil,
              let ruta, let aqui = coordenada,
              let veredicto = VerificadorCoherencia.evaluar(point: aqui, ruta: ruta),
              veredicto.esValido else { return nil }
        return aqui
    }
}
