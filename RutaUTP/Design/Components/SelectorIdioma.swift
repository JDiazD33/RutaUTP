import SwiftUI

struct SelectorIdioma: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L.t("Se aplica al instante y se recuerda en este dispositivo.", "Applies immediately and is remembered on this device."))
                        .font(.bodySm)
                        .foregroundStyle(Color.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(IdiomaApp.allCases) { idioma in
                        let seleccionado = IdiomaManager.shared.idioma == idioma
                        Button {
                            AppHaptics.impact(.light)
                            IdiomaManager.shared.seleccionar(codigo: idioma.rawValue)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Text(idioma.nombreNativo)
                                    .font(.bodyMdMedium)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                if seleccionado {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.appPrimary)
                                        .accessibilityHidden(true)
                                }
                            }
                            .foregroundStyle(Color.onSurface)
                            .padding(16)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            .background(Color.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 12))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(seleccionado ? L.t("Idioma seleccionado", "Selected language") : "")
                        .accessibilityAddTraits(seleccionado ? .isSelected : [])
                    }
                }
                .padding(20)
            }
            .background(Color.appBackground)
            .navigationTitle(L.t("Elige el idioma de la app", "Choose the app language"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Cerrar", "Close")) { dismiss() }
                }
            }
        }
        .environment(\.locale, IdiomaManager.shared.idioma.locale)
    }
}
