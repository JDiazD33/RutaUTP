//
//  RejillaEspacial.swift
//  RutaUTP
//
//  Rejilla espacial para la consulta «qué puntos hay a menos de X metros de
//  este otro». Sustituye el barrido lineal por celda + vecindario.
//
//  El lado de la celda se deriva del radio con el que se construye, de modo que
//  mirar las 3×3 celdas vecinas cubre SIEMPRE el radio completo. El resultado
//  es EXACTO, no una aproximación: es lo que permite cambiar el barrido por
//  esto sin que cambie la lista de resultados (lo fija una prueba contra la
//  versión por fuerza bruta).
//
//  Nota sobre la latitud: el grado de longitud se acorta al alejarse del
//  ecuador. El lado en longitud se calcula con la latitud MÁS ALEJADA del
//  conjunto, que es donde el grado es más corto; así la celda sigue cubriendo
//  el radio en cualquier punto del mapa, no solo en el centro.
//

import Foundation
import CoreLocation

struct RejillaEspacial<Elemento> {

    /// Índice de celda. Se calcula con `floor`, así que es correcto también
    /// para latitudes y longitudes negativas (todo el Perú lo es).
    private struct Celda: Hashable {
        let fila: Int
        let columna: Int
    }

    private let ladoLat: Double
    private let ladoLon: Double
    private let celdas: [Celda: [Elemento]]
    private let coordenada: (Elemento) -> CLLocationCoordinate2D

    init(_ elementos: [Elemento],
         radioMetros: Double,
         coordenada: @escaping (Elemento) -> CLLocationCoordinate2D) {
        self.coordenada = coordenada

        let latExtrema = elementos.map { abs(coordenada($0).latitude) }.max() ?? 0
        let metrosPorGradoLat = 111_320.0
        let metrosPorGradoLon = 111_320.0 * max(0.01, cos(latExtrema * .pi / 180))
        self.ladoLat = max(radioMetros / metrosPorGradoLat, 1e-9)
        self.ladoLon = max(radioMetros / metrosPorGradoLon, 1e-9)

        var acumuladas: [Celda: [Elemento]] = [:]
        for elemento in elementos {
            let c = coordenada(elemento)
            let clave = Celda(fila: Int(floor(c.latitude / ladoLat)),
                              columna: Int(floor(c.longitude / ladoLon)))
            acumuladas[clave, default: []].append(elemento)
        }
        self.celdas = acumuladas
    }

    /// Elementos a `radioMetros` o menos de `punto`.
    ///
    /// Es exacto siempre que `radioMetros` no supere el radio con el que se
    /// construyó la rejilla (si se pide más, el vecindario 3×3 se queda corto).
    func cerca(de punto: CLLocationCoordinate2D, radioMetros: Double) -> [Elemento] {
        let fila = Int(floor(punto.latitude / ladoLat))
        let columna = Int(floor(punto.longitude / ladoLon))

        var resultado: [Elemento] = []
        for f in (fila - 1)...(fila + 1) {
            for c in (columna - 1)...(columna + 1) {
                guard let enCelda = celdas[Celda(fila: f, columna: c)] else { continue }
                for elemento in enCelda
                where Self.distanciaMetros(punto, coordenada(elemento)) <= radioMetros {
                    resultado.append(elemento)
                }
            }
        }
        return resultado
    }

    /// Haversine. Se replica aquí en vez de usar `CLLocation.distance` para que
    /// la rejilla no dependa de un objeto por comparación.
    private static func distanciaMetros(_ a: CLLocationCoordinate2D,
                                        _ b: CLLocationCoordinate2D) -> Double {
        let radioTierra = 6_371_000.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let latA = a.latitude * .pi / 180
        let latB = b.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
              + cos(latA) * cos(latB) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * radioTierra * asin(min(1, sqrt(h)))
    }
}
