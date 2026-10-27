//
//  GeocodificacionComunidadModel.swift
//  RutaUTP
//
//  Geocodificación inversa de la ubicación de un aporte.
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

    func buscar(_ coordenada: CLLocationCoordinate2D) {
        cancelar(limpiar: true)
        guard CLLocationCoordinate2DIsValid(coordenada) else { return }
        let token = solicitud.begin()
        buscando = true
        let location = CLLocation(latitude: coordenada.latitude, longitude: coordenada.longitude)
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            Task { @MainActor [weak self] in
                guard let self, self.solicitud.isCurrent(token) else { return }
                let partes = [placemarks?.first?.thoroughfare,
                              placemarks?.first?.subThoroughfare,
                              placemarks?.first?.locality].compactMap { $0 }
                self.direccion = partes.isEmpty ? nil : partes.joined(separator: " ")
                self.buscando = false
            }
        }
    }

    func cancelar(limpiar: Bool = false) {
        solicitud.invalidate()
        geocoder.cancelGeocode()
        buscando = false
        if limpiar { direccion = nil }
    }
}
