//
//  GeocodificacionComunidadModel.swift
//  RutaUTP
//
//  Geocodificación inversa de aportes y puntos de cambios de ruta.
//

import SwiftUI
import CoreLocation

/// Mantiene una sola identidad de consulta aunque SwiftUI reconstruya la hoja.
@MainActor
final class GeocodificacionComunidadModel: ObservableObject {
    @Published private(set) var direccion: String?
    @Published private(set) var buscando = false
    private let geocoder = CLGeocoder()
    private var solicitud = StartGuard()
    private var espera: Task<Void, Never>?
    private var vencimiento: Task<Void, Never>?

    /// - Parameter soloCalle: devuelve solo el nombre de la vía, sin número ni
    ///   ciudad. Sirve para sugerir por dónde va ahora una línea desviada.
    func buscar(_ coordenada: CLLocationCoordinate2D, demora: Duration = .zero, soloCalle: Bool = false,
                alCompletar: (@MainActor @Sendable (String?) -> Void)? = nil) {
        cancelar(limpiar: true)
        guard CLLocationCoordinate2DIsValid(coordenada) else { return }
        let token = solicitud.begin()
        buscando = true
        let location = CLLocation(latitude: coordenada.latitude, longitude: coordenada.longitude)
        espera = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: demora) } catch { return }
            guard let self, self.solicitud.isCurrent(token), !Task.isCancelled else { return }
            self.geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.solicitud.isCurrent(token) else { return }
                    self.direccion = Self.texto(de: placemarks?.first, soloCalle: soloCalle)
                    self.buscando = false
                    self.vencimiento?.cancel()
                    self.vencimiento = nil
                    self.espera = nil
                    alCompletar?(self.direccion)
                }
            }
        }
        vencimiento = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(12)) } catch { return }
            guard let self, !Task.isCancelled, self.solicitud.isCurrent(token), self.buscando else { return }
            self.cancelar(limpiar: true)
            alCompletar?(nil)
        }
    }

    /// Calle y número, o el nombre del lugar si no hay calle (un parque, un
    /// campus: «Estadio UNT»), seguido de la ciudad. Antes, sin calle quedaba
    /// solo «Trujillo», que no sirve como referencia.
    static func texto(de lugar: CLPlacemark?, soloCalle: Bool) -> String? {
        guard let lugar else { return nil }
        if soloCalle { return lugar.thoroughfare }
        let sitio = lugar.thoroughfare.map { [$0, lugar.subThoroughfare].compactMap { $0 }.joined(separator: " ") }
            ?? lugar.areasOfInterest?.first ?? lugar.subLocality
        var partes: [String] = []
        for parte in [sitio, lugar.locality].compactMap({ $0 }) where !partes.contains(parte) {
            partes.append(parte)
        }
        return partes.isEmpty ? nil : partes.joined(separator: ", ")
    }

    func cancelar(limpiar: Bool = false) {
        solicitud.invalidate()
        espera?.cancel()
        espera = nil
        vencimiento?.cancel()
        vencimiento = nil
        geocoder.cancelGeocode()
        buscando = false
        if limpiar { direccion = nil }
    }
}
