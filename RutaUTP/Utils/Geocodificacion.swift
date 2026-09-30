//
//  Geocodificacion.swift
//  RutaUTP
//
//  Geocodificación INVERSA: coordenada -> nombre de calle.
//
//  Vive aquí y no en una vista porque la necesitan tres pantallas distintas
//  (elegir destino en el mapa, marcar el punto de subida, guardar un lugar).
//  Cada una con su propio `CLGeocoder` habría significado tres copias de este
//  bloque y tres listas de campos a mantener sincronizadas.
//

import CoreLocation

enum Geocodificacion {

    /// Devuelve la calle de una coordenada, con degradación en cascada.
    ///
    /// El orden importa: `name` es la calle con número y es lo que el usuario
    /// reconoce; `subLocality` es el barrio; `locality` la ciudad. Se baja de
    /// nivel solo cuando el anterior falta o viene vacío, porque devolver
    /// "Trujillo" cuando sí hay "Av. España 123" sería un dato inútil.
    ///
    /// Devuelve un texto genérico en vez de fallar: quien llama lo pinta en un
    /// campo de texto, y un `nil` obligaría a cada pantalla a inventar su
    /// propio respaldo.
    static func nombreDelLugar(_ coord: CLLocationCoordinate2D) async -> String {
        let geocoder = CLGeocoder()
        let lugar = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        if let marcas = try? await geocoder.reverseGeocodeLocation(lugar),
           let marca = marcas.first {
            if let calle = marca.name, !calle.isEmpty { return calle }
            if let distrito = marca.subLocality, !distrito.isEmpty { return distrito }
            if let ciudad = marca.locality, !ciudad.isEmpty { return ciudad }
        }
        return L.t("Punto en el mapa", "Picked spot")
    }
}
