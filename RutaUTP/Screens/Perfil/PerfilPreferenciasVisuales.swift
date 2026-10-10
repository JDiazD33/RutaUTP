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

    private init() {
        defaults = .standard
        for empresa in TematicaEmpresa.todas {
            for carnet in CarnetPerfil.allCases {
                let clave = Self.clave(carnet, empresa: empresa)
                if let valor = defaults.object(forKey: clave) as? Bool {
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
    let empresa: TematicaEmpresa
    private let store = PreferenciasVisualesPerfilStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("Preferencias visuales", "Visual preferences"))
                .font(.labelCapsLg)
                .foregroundStyle(.onSurfaceVariant)
                .appTracking(AppTracking.wideLabel)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(CarnetPerfil.allCases, id: \.rawValue) { carnet in
                    HStack(spacing: 14) {
                        Image(systemName: carnet.icono)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.appPrimary)
                            .frame(width: 36, height: 36)
                            .background(Color.appPrimary.opacity(0.14), in: Circle())
                            .accessibilityHidden(true)
                        Toggle(isOn: Binding(
                            get: { store.visible(carnet, empresa: empresa) },
                            set: { store.establecer($0, carnet: carnet, empresa: empresa) }
                        )) {
                            Text(L.t("Mostrar ", "Show ") + carnet.titulo(para: empresa))
                                .font(.bodyMdMedium)
                                .foregroundStyle(.onSurface)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .tint(.appPrimary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    if carnet == .foto {
                        Divider().padding(.leading, 56).accessibilityHidden(true)
                    }
                }
            }
            .background(Color.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.outlineVariant.opacity(0.20), lineWidth: 0.5)
            }

            Text(L.t("Elige los carnets que aparecen en tu billetera de \(empresa.nombre). Se recuerda para cada empresa; ocultarlos conserva tus fotos.",
                     "Choose the cards shown in your \(empresa.nombre) wallet. Choices are remembered for each company; hiding cards keeps your photos."))
                .font(.bodySm)
                .foregroundStyle(.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
