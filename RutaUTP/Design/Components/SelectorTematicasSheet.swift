import SwiftUI

/// La misma tinta monocromática para todas las marcas, incluido el campus UTP.
struct LogoEmpresa: View {
    let empresa: TematicaEmpresa
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let asset = empresa.logoAsset {
            Image(asset)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                .accessibilityHidden(true)
        }
    }
}

/// Una sola hoja: elegir una marca abre sus sedes sin cambiar aún el contexto.
struct SelectorTematicasSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @ScaledMetric(relativeTo: .body) private var alturaLogo = 34.0
    @State private var busqueda = ""
    @State private var empresaParaSede: TematicaEmpresa?
    private let store = TematicaEmpresaStore.shared

    private var opciones: [TematicaEmpresa] {
        let consulta = busqueda.trimmingCharacters(in: .whitespacesAndNewlines)
        return TematicaEmpresa.todas.filter {
            consulta.isEmpty || $0.nombre.localizedStandardContains(consulta)
        }
    }

    private var columnas: [GridItem] {
        textSize >= .xxxLarge
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 145), spacing: 12)]
    }

    var body: some View {
        Group {
            if let empresaParaSede {
                SedeTrabajoSheet(empresaInicial: empresaParaSede,
                                 alVolver: { self.empresaParaSede = nil })
            } else {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            Text(L.t("Elige la empresa a la que perteneces. Después podrás confirmar tu sede.",
                                     "Choose the company you belong to. Then you can confirm your workplace."))
                                .font(.body).foregroundStyle(.onSurfaceVariant)
                                .fixedSize(horizontal: false, vertical: true)
                            if TransporteApp.busesUTPActivos {
                                Text(L.t("Confirmar otra empresa vuelve al transporte urbano y termina el viaje en curso.",
                                         "Confirming another company returns to city transport and ends the current trip."))
                                    .font(.caption).foregroundStyle(.onSurfaceVariant)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if opciones.isEmpty {
                                ContentUnavailableView.search(text: busqueda)
                            } else {
                                LazyVGrid(columns: columnas, spacing: 12) {
                                    ForEach(opciones) { opcion in
                                        boton(opcion)
                                    }
                                }
                            }
                        }
                        .padding(20)
                    }
                    .background(Color.appBackground)
                    .navigationTitle(L.t("Temáticas de colores", "Color themes"))
                    .navigationBarTitleDisplayMode(.inline)
                    .searchable(text: $busqueda, prompt: L.t("Buscar empresa", "Search company"))
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(L.t("Cerrar", "Close")) { dismiss() }
                        }
                    }
                }
            }
        }
        .tint(.appPrimary)
    }

    private func boton(_ opcion: TematicaEmpresa) -> some View {
        let elegida = store.seleccion == opcion
        return Button {
            AppHaptics.selection()
            if opcion == .utp {
                TransporteApp.usarSedeTrabajo(CatalogoSedesTrabajo.campusUTP)
                dismiss()
            } else {
                empresaParaSede = opcion
            }
        } label: {
            VStack(spacing: 12) {
                LogoEmpresa(empresa: opcion)
                    .frame(maxWidth: .infinity)
                    .frame(height: alturaLogo)
                HStack(alignment: .top, spacing: 6) {
                    Circle().fill(PaletasEmpresa.paleta(para: opcion).colorMarca)
                        .frame(width: 7, height: 7).padding(.top, 4)
                        .accessibilityHidden(true)
                    Text(opcion.nombre).font(.bodySm.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: elegida ? "checkmark.circle.fill" : "circle")
                        .font(.bodySm).accessibilityHidden(true)
                }
                .foregroundStyle(.onSurface)
                if opcion == .utp {
                    Text(L.t("Predeterminada", "Default"))
                        .font(.caption).foregroundStyle(.onSurfaceVariant)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 100)
            .padding(16)
            .background(Color.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(elegida ? Color.onSurface : Color.outlineVariant,
                            lineWidth: elegida ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("Temática ", "Theme ") + opcion.nombre)
        .accessibilityValue(elegida ? L.t("Seleccionada", "Selected") : L.t("No seleccionada", "Not selected"))
        .accessibilityHint(opcion == .utp
            ? L.t("Restaura los colores UTP y el campus de Trujillo", "Restores UTP colors and the Trujillo campus")
            : L.t("Abre sus sedes; los colores se aplican al confirmar", "Opens its workplaces; colors apply when you confirm"))
        .accessibilityAddTraits(elegida ? .isSelected : [])
    }
}
