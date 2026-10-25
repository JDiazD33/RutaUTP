import SwiftUI
import Observation

enum CarnetPerfil: String, CaseIterable {
    case foto, digital

    func titulo(para empresa: TematicaEmpresa) -> String {
        switch self {
        case .foto:
            return empresa == .utp
                ? L.t("Carnet Universitario", "University Card")
                : L.t("Carnet de empresa", "Company Card")
        case .digital:
            return L.t("Carné Digital", "Digital ID")
        }
    }

    func tituloBreve(para empresa: TematicaEmpresa) -> String {
        switch self {
        case .foto:
            return empresa == .utp
                ? L.t("Foto del carné", "Card photo")
                : L.t("Foto de credencial", "ID photo")
        case .digital:
            return L.t("Carné Digital", "Digital ID")
        }
    }

    var icono: String {
        self == .foto ? "person.text.rectangle.fill" : "person.crop.rectangle.fill"
    }
}

/// Solo controla la visibilidad; ocultar un carné nunca borra su foto.
/// Las elecciones se recuerdan por empresa sin cambiar sus valores al navegar.
@MainActor
@Observable
final class PreferenciasVisualesPerfilStore {
    static let shared = PreferenciasVisualesPerfilStore()
    @ObservationIgnored private let defaults: UserDefaults
    private var valores: [String: Bool] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        for empresa in TematicaEmpresa.todas {
            for carnet in CarnetPerfil.allCases {
                let clave = Self.clave(carnet, empresa: empresa)
                if let valor = PreferenciasApp.boolGuardado(para: clave, defaults: defaults) {
                    valores[clave] = valor
                }
            }
        }
    }

    private static func clave(_ carnet: CarnetPerfil, empresa: TematicaEmpresa) -> String {
        "perfil.carnet.\(carnet.rawValue).\(empresa.rawValue).visible.v1"
    }

    func visible(_ carnet: CarnetPerfil, empresa: TematicaEmpresa) -> Bool {
        valores[Self.clave(carnet, empresa: empresa)] ?? (empresa == .utp)
    }

    func establecer(_ visible: Bool, carnet: CarnetPerfil, empresa: TematicaEmpresa) {
        let clave = Self.clave(carnet, empresa: empresa)
        valores[clave] = visible
        defaults.set(visible, forKey: clave)
    }
}

struct PerfilPreferenciasVisuales: View {
    @Environment(\.dismiss) private var dismiss
    let empresa: TematicaEmpresa
    private let store = PreferenciasVisualesPerfilStore.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(CarnetPerfil.allCases, id: \.rawValue) { carnet in
                        Toggle(isOn: Binding(
                            get: { store.visible(carnet, empresa: empresa) },
                            set: { store.establecer($0, carnet: carnet, empresa: empresa) }
                        )) {
                            Label(carnet.tituloBreve(para: empresa), systemImage: carnet.icono)
                                .foregroundStyle(Color.onSurface)
                        }
                        .tint(.appAccent)
                        .accessibilityHint(L.t("Muestra u oculta esta credencial sin borrar sus datos", "Show or hide this credential without deleting its data"))
                    }
                } header: {
                    Text(empresa.nombre)
                } footer: {
                    Text(L.t("Ocultarlas conserva tus fotos.", "Hiding them keeps your photos."))
                }
                Section {
                    DisclosureGroup(L.t("Más información", "More information")) {
                        Text(L.f("Elige los carnets que aparecen en tu billetera de {0}. Se recuerda para cada empresa; ocultarlos conserva tus fotos.", "Choose the cards shown in your {0} wallet. Choices are remembered for each company; hiding cards keeps your photos.", [empresa.nombre]))
                            .font(.footnote)
                            .foregroundStyle(Color.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle(L.t("Credenciales", "Credentials"))
            .navigationBarTitleDisplayMode(.inline)
            .tint(.appAccent)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Listo", "Done")) { dismiss() }
                }
            }
        }
    }
}
