import SwiftUI
import CoreLocation

// MARK: - Bus animado sobre ruta real
// Se conserva la flota propia del mapa: usa shapes reducidos y publicación
// por desplazamiento visible. Tracking usa los vértices originales y su
// protocolo de posiciones. Unificarlos cambiaría esos ciclos; compartimos
// la geometría del rumbo en PolylineMatching para evitar fórmulas divergentes.
struct BusAnimado: Identifiable, Equatable {
    let id: String
    let linea: String        // "10", "4"
    let rutaId: String       // route_id GTFS: enlaza con el detalle de RutasView
    let empresa: String      // "El Cortijo", "Salaverry"
    let tipo: String          // "Micro", "Combi"
    /// Variante original del feed, sin traducir ni confundirla con una matrícula.
    let variante: String

    /// Se resuelve al mostrar: cambiar ES/EN no requiere reconstruir la flota.
    var ramalTexto: String {
        variante.isEmpty ? L.t("S/D", "N/A") : L.t("Ramal \(variante)", "Branch \(variante)")
    }
    let minutosLlegada: Int?   // 4, 12 — o nil si no hay estimación
    /// Identidad de la línea cuando el feed la conoce; nil usa el tema en UI.
    let colorDeRuta: Color?
    var color: Color { colorDeRuta ?? .appPrimary }
    var lat: Double           // posición actual (animada)
    var lon: Double
    var heading: Double       // ángulo de dirección
    let rutaCoordenadas: [CLLocationCoordinate2D]  // waypoints

    // Simulación tipo flota real: la posición se lleva por DISTANCIA
    // recorrida sobre el shape, no por fracción de segmento.
    /// Distancia acumulada (m) de cada waypoint desde el inicio del shape.
    let acumulados: [Double]
    /// Metros recorridos a lo largo del shape (0...longitudRutaM).
    var distanciaM: Double = 0
    /// Velocidad crucero propia del vehículo (m/s).
    var velocidadMS: Double = 8
    var isMovingForward: Bool = true
    /// Tramo [i, i+1] donde cayó la última interpolación (cache).
    var tramoActual: Int = 0

    /// De dónde procede la posición de este vehículo.
    ///
    /// `.simulated` es la flota que el mapa anima sobre los shapes del feed,
    /// que es lo que se ve cuando no hay broker configurado. `.real` es una
    /// posición publicada por el backend por el canal MQTT a partir de las
    /// observaciones de los pasajeros a bordo.
    ///
    /// Un vehículo real no trae geometría propia: `rutaCoordenadas` y
    /// `acumulados` van vacíos, así que `actualizarPosicion()` no hace nada y
    /// la posición la fija cada mensaje del broker, no la animación local.
    var fuente: VehicleTrackingSource = .simulated

    /// Texto de la llegada para la interfaz.
    ///
    /// Las posiciones reales muestran `~` porque su llegada se estima con la
    /// posición, rumbo y velocidad disponibles sobre el recorrido GTFS. Si el
    /// vehículo se aleja del punto consultado o faltan datos fiables, se evita
    /// inventar un valor y se muestra "SIN ETA".
    var etiquetaLlegada: String {
        guard let minutosLlegada else {
            return L.t("SIN ETA", "NO ETA")
        }

        return fuente == .real
            ? "~\(minutosLlegada) MIN"
            : "\(minutosLlegada) MIN"
    }

    var longitudRutaM: Double { acumulados.last ?? 0 }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Coloca lat/lon/heading en el punto del shape que corresponde a
    /// `distanciaM` metros del inicio. Los buses avanzan pocos metros por
    /// tick, así que el índice de tramo se ajusta incrementalmente en vez
    /// de buscar desde cero.
    mutating func actualizarPosicion() {
        guard acumulados.count == rutaCoordenadas.count,
              rutaCoordenadas.count >= 2 else { return }

        var i = min(max(tramoActual, 0), rutaCoordenadas.count - 2)
        while i > 0 && distanciaM < acumulados[i] { i -= 1 }
        while i < rutaCoordenadas.count - 2 && distanciaM > acumulados[i + 1] { i += 1 }

        let a = rutaCoordenadas[i]
        let b = rutaCoordenadas[i + 1]
        let largo = acumulados[i + 1] - acumulados[i]
        let f = largo > 0.5 ? min(1, max(0, (distanciaM - acumulados[i]) / largo)) : 0

        lat = a.latitude + (b.latitude - a.latitude) * f
        lon = a.longitude + (b.longitude - a.longitude) * f
        heading = PolylineMatching.headingDegrees(from: a, to: b,
                                                   movingForward: isMovingForward)
        tramoActual = i
    }

    static func == (lhs: BusAnimado, rhs: BusAnimado) -> Bool {
        lhs.id == rhs.id &&
        lhs.lat == rhs.lat &&
        lhs.lon == rhs.lon &&
        lhs.heading == rhs.heading
    }
}
