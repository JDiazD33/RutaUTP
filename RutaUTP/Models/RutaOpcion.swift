import SwiftUI
import CoreLocation

// MARK: - Modelo
struct RutaOpcion: Identifiable, Equatable {
    let id: String              // route_id del feed GTFS
    let linea: String           // "C-01"
    let empresa: String         // agencia GTFS
    let recorrido: String       // "Av. Grau → Av. Libertad"
    let frecuenciaMin: Int      // headway GTFS (sale uno cada N min)
    let duracionMin: Int        // duración del viaje según stop_times
    let costo: String           // tarifa fare_attributes
    let numParaderos: Int
    let distanciaKm: Double
    let colorLinea: Color       // route_color del feed
    let shape: [CLLocationCoordinate2D]   // recorrido real (shapes.txt)
    let paraderos: [ParaderoGTFS]         // paraderos en orden (stops + stop_times)
    let paradaInicio: String
    let paradaFin: String
    var variante: String = ""

    var frecuenciaTexto: String {
        frecuenciaMin > 0 ? L.t("cada \(frecuenciaMin) min", "every \(frecuenciaMin) min") : "—"
    }

    var tiempoTexto: String {
        duracionMin > 0 ? "\(duracionMin) min" : "—"
    }

    // Identidad por route_id: el shape no participa en la comparación.
    static func == (lhs: RutaOpcion, rhs: RutaOpcion) -> Bool {
        lhs.id == rhs.id
    }
}

