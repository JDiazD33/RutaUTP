import Foundation
import CoreLocation
import OSLog

/// Sede de referencia: campus UTP o local de la empresa elegida.
struct SedeTrabajo: Identifiable, Equatable, Decodable {
    let id: String
    let empresa: TematicaEmpresa
    let nombre: String
    let direccion: String
    let lat: Double
    let lon: Double
    let googlePlaceID: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var googleMapsURL: URL? {
        var url = URLComponents(string: "https://www.google.com/maps/search/")
        url?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: googlePlaceID.isEmpty
                         ? "\(lat),\(lon)" : "\(nombre), \(direccion)")
        ]
        if !googlePlaceID.isEmpty {
            url?.queryItems?.append(URLQueryItem(name: "query_place_id", value: googlePlaceID))
        }
        return url?.url
    }
}

enum CatalogoSedesTrabajo {
    /// Reservado para la sede en los chips; los guardados empiezan en 100.
    static let idChipSede = 4

    /// Reutiliza la referencia institucional de la app, sin inventar un Place ID.
    static let campusUTP = SedeTrabajo(
        id: "utp-trujillo", empresa: .utp,
        nombre: "Campus UTP Trujillo", direccion: "Av. Nicolás de Piérola 1221, Trujillo",
        lat: GTFSRepository.coordenadaUTP.latitude,
        lon: GTFSRepository.coordenadaUTP.longitude,
        googlePlaceID: ""
    )

    // Pins y estado de las ocho sedes empresariales contrastados el 09/10/2026.
    // Procedencia y descartes: ThirdPartyNotices/Marcas/sedes-trujillo.json.
    // Son pins del establecimiento; el acceso peatonal queda por verificar.
    // Real Plaza está cerrado. Popeyes queda «Próximamente», sin sede inventada.
    static let todas: [SedeTrabajo] = sedesBase + adicionales

    private static let sedesBase: [SedeTrabajo] = [
        campusUTP,
        SedeTrabajo(id: "interbank-centro-gamarra", empresa: .interbank,
                    nombre: "Interbank Centro — Gamarra", direccion: "Jr. Gamarra 450, Trujillo",
                    lat: -8.1103596, lon: -79.0267624,
                    googlePlaceID: "ChIJdTe2doQ9rZERjFx-9JTDaA0"),
        SedeTrabajo(id: "interbank-larco", empresa: .interbank,
                    nombre: "Interbank Larco", direccion: "Av. Larco 780, Trujillo",
                    lat: -8.1211306, lon: -79.0362330,
                    googlePlaceID: "ChIJVyHXAXQ9rZERLcd2T3GuRkw"),
        SedeTrabajo(id: "interbank-mallplaza", empresa: .interbank,
                    nombre: "Interbank Mallplaza", direccion: "Av. Mansiche y América Oeste, locales B-1253 / B-1257, Trujillo",
                    lat: -8.1018948, lon: -79.0467764,
                    googlePlaceID: "ChIJE0idAbc9rZERjkZ9p_va72k"),
        SedeTrabajo(id: "interbank-el-chacarero", empresa: .interbank,
                    nombre: "Interbank El Chacarero", direccion: "Prol. Unión 2218, Trujillo",
                    lat: -8.0906329, lon: -79.0066038,
                    googlePlaceID: "ChIJG2HANogXrZERTIWcQVy_RsY"),
        SedeTrabajo(id: "plazavea-espana", empresa: .plazaVea,
                    nombre: "Plaza Vea España", direccion: "Av. España, Trujillo",
                    lat: -8.1159412, lon: -79.0261629,
                    googlePlaceID: "ChIJaebOUTE9rZERtp1ChS0rYrU"),
        SedeTrabajo(id: "plazavea-espana-780", empresa: .plazaVea,
                    nombre: "Plaza Vea España 780", direccion: "Av. España 780, Trujillo",
                    lat: -8.1076368, lon: -79.0299941,
                    googlePlaceID: "ChIJFy-0KIU9rZERvkTRFnzVzy8"),
        SedeTrabajo(id: "plazavea-primavera", empresa: .plazaVea,
                    nombre: "Plaza Vea Primavera", direccion: "Av. Teodoro Valcárcel 266–268, Trujillo",
                    lat: -8.1014367, lon: -79.0355399,
                    googlePlaceID: "ChIJl_9I_rI9rZERRueGGAB6uA4"),
        SedeTrabajo(id: "plazavea-el-chacarero", empresa: .plazaVea,
                    nombre: "Plaza Vea El Chacarero", direccion: "Prol. Unión 2218, Trujillo",
                    lat: -8.0900189, lon: -79.0062619,
                    googlePlaceID: "ChIJ0Ub_bbcXrZERU3K1JkFHb64")
    ]

    /// Catálogo local cargado una vez: ampliar las sedes no introduce búsquedas
    /// de red al abrir Perfil o mover el mapa.
    private static let adicionales: [SedeTrabajo] = {
        do {
            guard let url = Bundle.main.url(forResource: "sedes-empresas-trujillo",
                                            withExtension: "json") else {
                Logger(subsystem: "RutaUTP", category: "SedesTrabajo")
                    .error("Falta el catálogo local de sedes adicionales")
                return []
            }
            let datos = try Data(contentsOf: url)
            let sedes = try JSONDecoder().decode([SedeTrabajo].self, from: datos)
            var ids = Set(sedesBase.map(\.id))
            return sedes.filter {
                TematicaEmpresa.empresas.contains($0.empresa)
                    && CLLocationCoordinate2DIsValid($0.coordinate)
                    && ids.insert($0.id).inserted
            }
        } catch {
            Logger(subsystem: "RutaUTP", category: "SedesTrabajo")
                .error("No se pudo leer el catálogo local: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }()

    static func sede(id: String) -> SedeTrabajo? {
        todas.first { $0.id == id }
    }

    static func sedes(de empresa: TematicaEmpresa) -> [SedeTrabajo] {
        todas.filter { $0.empresa == empresa }
    }
}
