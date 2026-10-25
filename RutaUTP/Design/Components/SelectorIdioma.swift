import SwiftUI

struct SelectorIdioma: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(IdiomaApp.allCases) { idioma in
                        let seleccionado = IdiomaManager.shared.idioma == idioma
                        Button {
                            AppHaptics.impact(.light)
                            IdiomaManager.shared.seleccionar(codigo: idioma.rawValue)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Text(idioma.nombreNativo)
                                    .font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                if seleccionado {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(acento)
                                        .accessibilityHidden(true)
                                }
                            }
                            .foregroundStyle(Color.onSurface)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(seleccionado ? L.t("Idioma seleccionado", "Selected language") : "")
                        .accessibilityAddTraits(seleccionado ? .isSelected : [])
                    }
                } header: {
                    HStack(alignment: .top, spacing: 16) {
                        Text(L.t("Elige el idioma de la app", "Choose the app language"))
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Color.onSurface)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 0)
                        Image(systemName: "globe")
                            .font(.title2)
                            .foregroundStyle(acento)
                            .accessibilityHidden(true)
                    }
                    .padding(.bottom, 8)
                } footer: {
                    Text(L.t("Se aplica al instante y se recuerda en este dispositivo.", "Applies immediately and is remembered on this device."))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .textCase(nil)
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle(L.t("Idioma", "Language"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Cerrar", "Close")) { dismiss() }
                }
            }
        }
        .tint(acento)
        .environment(\.locale, IdiomaManager.shared.idioma.locale)
    }
}
