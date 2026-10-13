import Foundation

/// Referencia exacta del catalogo. No cambia nombres, recorridos ni preferencias.
struct ReferenciaMicroGTFS: Codable, Hashable {
    struct Paradero: Codable, Hashable {
        let id: String
        let lat: Double
        let lon: Double
    }
    let routeID: String
    let linea: String
    let variante: String
    let empresa: String
    let recorrido: String
    let paraderos: [Paradero]

    init(_ ruta: RutaGTFS) {
        self.init(id: ruta.id, linea: ruta.linea, variante: ruta.variante,
                  empresa: ruta.empresa, recorrido: ruta.recorrido, paraderos: ruta.paraderos)
    }

    init(_ ruta: RutaOpcion) {
        self.init(id: ruta.id, linea: ruta.linea, variante: ruta.variante,
                  empresa: ruta.empresa, recorrido: ruta.recorrido, paraderos: ruta.paraderos)
    }

    private init(id: String, linea: String, variante: String, empresa: String,
                 recorrido: String, paraderos: [ParaderoGTFS]) {
        routeID = id
        self.linea = linea
        self.variante = variante
        self.empresa = empresa
        self.recorrido = recorrido
        self.paraderos = paraderos.map { Paradero(id: $0.id, lat: $0.lat, lon: $0.lon) }
    }

    var lineaVisible: String {
        GTFSNombreParser.lineaConLetra(linea: linea, variante: variante)
    }
}

struct CatalogoMicros: Decodable {
    let version: Int
    let identidades: [IdentidadMicro]
    let vinculos: [VinculoMicro]
    let referenciasFotograficas: [ReferenciaFotoMicro]?
}

/// Foto documentada de una linea, sin afirmar un sentido o aspecto actual.
struct ReferenciaFotoMicro: Codable {
    let referenciaGTFS: ReferenciaMicroGTFS
    let codigoFuente: String
    let fuenteURL: String
    let fechaFoto: String?
    let fechaRevision: String
    let derechos: String
    let foto: IdentidadMicro.Foto
}

struct IdentidadMicro: Codable {
    struct ColorCarroceria: Codable {
        let nombre: NombreColorMicro
        let hex: String
    }
    struct Foto: Codable {
        let archivo: String
        let sha256: String
        let ancho: Int
        let alto: Int
        let credito: String
        let autorizacion: String
    }
    let id: String
    let letra: String
    let empresa: String
    let colores: [ColorCarroceria]
    let foto: Foto
}

struct VinculoMicro: Codable {
    struct Verificacion: Codable {
        let estado: String
        let fecha: String
        let vigenteHasta: String
        let fuente: String
        let verificadoPor: String
    }
    let identidadID: String
    let referenciaGTFS: ReferenciaMicroGTFS
    /// Indices del tramo cuyo cartel se comprobo, dentro de los paraderos GTFS.
    let desdeIndice: Int
    let hastaIndice: Int
    let cartelDestino: String
    let verificacion: Verificacion

    func cubre(subida: String?, bajada: String?) -> Bool {
        guard let subida, let bajada else {
            // El detalle general no elige un sentido: solo admite un cartel
            // comprobado para el recorrido completo.
            return subida == nil && bajada == nil && desdeIndice == 0
                && hastaIndice == referenciaGTFS.paraderos.count - 1
        }
        let ids = referenciaGTFS.paraderos.map(\.id)
        // Una parada repetida en un circuito no basta para saber que vuelta se eligio.
        let inicios = ids.indices.filter { ids[$0] == subida }
        let finales = ids.indices.filter { ids[$0] == bajada }
        guard inicios.count == 1, finales.count == 1,
              let inicio = inicios.first, let fin = finales.first else { return false }
        return desdeIndice <= inicio && inicio < fin && fin <= hastaIndice
    }
}

enum NombreColorMicro: String, Codable, CaseIterable {
    case blanco, negro, rojo, azul, verde, amarillo, naranja, gris, marron, morado

    var texto: String {
        switch self {
        case .blanco: return L.t("Blanco", "White")
        case .negro: return L.t("Negro", "Black")
        case .rojo: return L.t("Rojo", "Red")
        case .azul: return L.t("Azul", "Blue")
        case .verde: return L.t("Verde", "Green")
        case .amarillo: return L.t("Amarillo", "Yellow")
        case .naranja: return L.t("Naranja", "Orange")
        case .gris: return L.t("Gris", "Gray")
        case .marron: return L.t("Marrón", "Brown")
        case .morado: return L.t("Morado", "Purple")
        }
    }
}
