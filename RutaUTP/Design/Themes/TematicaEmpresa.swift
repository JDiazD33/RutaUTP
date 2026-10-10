import Foundation
import Observation

/// IDs de apariencia, independientes de empresa del perfil y modo oscuro.
enum TematicaEmpresa: String, Identifiable, Decodable {
    case utp
    case interbank
    case popeyes
    case plazaVea = "plaza_vea"
    case cineplanet
    case innovaSchools = "innova_schools"
    case inkafarma
    case mifarma
    case bembos
    case donBelisario = "don_belisario"

    var id: String { rawValue }

    var nombre: String {
        switch self {
        case .utp: return "UTP"
        case .interbank: return "Interbank"
        case .popeyes: return "Popeyes"
        case .plazaVea: return "Plaza Vea"
        case .cineplanet: return "Cineplanet"
        case .innovaSchools: return "Innova Schools"
        case .inkafarma: return "Inkafarma"
        case .mifarma: return "Mifarma"
        case .bembos: return "Bembos"
        case .donBelisario: return "Don Belisario"
        }
    }

    var logoAsset: String? {
        switch self {
        case .utp: return "utp-monocromatico"
        case .interbank: return "interbank-logo"
        case .popeyes: return "popeyes-logo"
        case .plazaVea: return "plazavea-logo"
        case .cineplanet: return "cineplanet-logo"
        case .innovaSchools: return "innova-schools-logo"
        case .inkafarma: return "inkafarma-logo"
        case .mifarma: return "mifarma-logo"
        case .bembos: return "bembos-logo"
        case .donBelisario: return "don-belisario-logo"
        }
    }

    static let empresas: [TematicaEmpresa] = [
        .interbank, .popeyes, .plazaVea, .cineplanet, .innovaSchools,
        .inkafarma, .mifarma, .bembos, .donBelisario
    ]
    static let todas: [TematicaEmpresa] = [.utp] + empresas
}

/// Leer la selección desde un token Color registra la dependencia del body,
/// igual que L.t() con el idioma. No reconstruye el árbol mediante .id().
/// El candado protege también lecturas de colores desde modelos fuera de UI.
final class TematicaEmpresaStore: Observable {
    static let shared = TematicaEmpresaStore()
    static let llave = "apariencia.tematica.empresa.v1"

    private let defaults: UserDefaults
    private let observacion = ObservationRegistrar()
    private let candado = NSLock()
    private var valor: TematicaEmpresa

    var seleccion: TematicaEmpresa {
        observacion.access(self, keyPath: \.seleccion)
        candado.lock()
        defer { candado.unlock() }
        return valor
    }

    private init() {
        defaults = .standard
        valor = defaults.string(forKey: Self.llave)
            .flatMap(TematicaEmpresa.init(rawValue:)) ?? .utp
    }

    @MainActor
    func seleccionar(_ nueva: TematicaEmpresa) {
        guard seleccion != nueva else { return }
        observacion.withMutation(of: self, keyPath: \.seleccion) {
            candado.lock()
            valor = nueva
            candado.unlock()
            defaults.set(nueva.rawValue, forKey: Self.llave)
        }
    }
}
