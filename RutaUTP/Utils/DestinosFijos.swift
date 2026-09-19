//
//  DestinosFijos.swift
//  RutaUTP
//
//  Puntos de referencia fijos de la app: UTP, Centro y Huanchaco.
//
//  Fuente ÚNICA. Antes estaban escritos dos veces, con las mismas coordenadas
//  y las mismas claves señables repetidas literalmente:
//    - `MapaViewModel.destinosFijos`, como `DestinoChip`
//    - `RouteTrackingViewModel.destinos`, como `DestinoDemo`
//  Dos copias de la misma coordenada acaban divergiendo: mover el punto de
//  «Centro» obligaba a acordarse de los dos sitios.
//
//  Cada pantalla conserva su propio tipo de vista; aquí solo vive el dato.
//

import Foundation
import CoreLocation

enum DestinosFijos {

    struct Fijo {
        let id: Int
        /// Clave estable de la seña. Nunca el texto: ver `L.signable`.
        let claveSenia: String
        let es: String
        let en: String
        let icono: String
        let lat: Double
        let lon: Double

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }

        /// Etiqueta en el idioma activo. Calculada, no almacenada: el texto se
        /// resuelve en cada lectura, así que cambiar de idioma la actualiza.
        var label: String { L.signable(claveSenia, es, en) }
    }

    static let todos: [Fijo] = [
        Fijo(id: 1, claveSenia: "mapa.destino.utp", es: "UTP", en: "UTP",
             icono: "graduationcap.fill",
             lat: -8.098247879173792, lon: -79.03818104755645),
        Fijo(id: 2, claveSenia: "mapa.destino.centro", es: "Centro", en: "Downtown",
             icono: "building.2.fill",
             lat: -8.1090, lon: -79.0270),
        Fijo(id: 3, claveSenia: "mapa.destino.huanchaco", es: "Huanchaco", en: "Huanchaco",
             icono: "water.waves",
             lat: -8.0825, lon: -79.1197)
    ]

    /// Nombres en ESPAÑOL, en minúsculas, de los chips fijos.
    ///
    /// Se usan solo para no duplicar un lugar guardado que ya es un chip fijo.
    /// Dependen del texto español y **no** del idioma activo, a propósito: un
    /// lugar guardado llamado «Centro» debe seguir filtrándose aunque la app
    /// esté en inglés. Se derivan de `todos` para no repetir la lista.
    static let nombresEstables: Set<String> = Set(todos.map { $0.es.lowercased() })
}
