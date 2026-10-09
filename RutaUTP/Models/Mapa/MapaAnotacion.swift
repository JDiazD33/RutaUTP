import CoreLocation

// MARK: - Anotación unificada para el mapa (usada por RutasView)
enum TipoAnotacion: Equatable {
    case utp
    case usuario
}

struct MapaAnotacion: Identifiable, Equatable {
    let id: Int
    let lat: Double
    let lon: Double
    let tipo: TipoAnotacion

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

