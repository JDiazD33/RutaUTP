import SwiftUI

/// Logos originales en plantilla: tinta negra en claro y blanca en oscuro.
struct SelectorTematicaEmpresa: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var textSize
    @ScaledMetric(relativeTo: .body) private var alturaLogo = 30.0

    private let store = TematicaEmpresaStore.shared
    private var apilar: Bool { textSize >= .xxxLarge }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("TEMÁTICA DE COLORES", "COLOR THEME"))
                .font(.labelCapsMd)
                .foregroundStyle(.onSurfaceVariant)
                .appTracking(AppTracking.wideLabel)
                .accessibilityAddTraits(.isHeader)

            Text(L.t("Elige los colores de la aplicación.", "Choose the app's colors."))
                .font(.bodySm)
                .foregroundStyle(.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)

            if apilar {
                VStack(spacing: 10) {
                    ForEach(TematicaEmpresa.empresas) { opcion in
                        boton(opcion)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(TematicaEmpresa.empresas) { opcion in
                        boton(opcion)
                    }
                }
            }

            Button {
                elegir(.utp)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: store.seleccion == .utp
                          ? "checkmark.circle.fill" : "arrow.uturn.backward")
                        .accessibilityHidden(true)
                    Text(L.t("Colores originales UTP", "Original UTP colors"))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .font(.bodySm)
                .foregroundStyle(.appPrimary)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Temática UTP", "UTP theme"))
            .accessibilityValue(valorAccesible(.utp))
            .accessibilityAddTraits(store.seleccion == .utp ? [.isSelected] : [])
        }
    }

    private func boton(_ opcion: TematicaEmpresa) -> some View {
        let elegida = store.seleccion == opcion
        return Button {
            elegir(opcion)
        } label: {
            VStack(spacing: 12) {
                if let asset = opcion.logoAsset {
                    Image(asset)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: alturaLogo)
                        .accessibilityHidden(true)
                }
                HStack(spacing: 4) {
                    Circle()
                        .fill(PaletasEmpresa.paleta(para: opcion).colorMarca)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(opcion.nombre)
                        .font(.caption.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: elegida ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Color.onSurface)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 16)
            .background(Color.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(elegida ? Color.onSurface : Color.outlineVariant,
                            lineWidth: elegida ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("Temática ", "Theme ") + opcion.nombre)
        .accessibilityValue(valorAccesible(opcion))
        .accessibilityHint(L.t("Doble toque para aplicar estos colores.",
                              "Double tap to apply these colors."))
        .accessibilityAddTraits(elegida ? [.isSelected] : [])
    }

    private func valorAccesible(_ opcion: TematicaEmpresa) -> String {
        store.seleccion == opcion
            ? L.t("Seleccionada", "Selected")
            : L.t("No seleccionada", "Not selected")
    }

    private func elegir(_ opcion: TematicaEmpresa) {
        guard store.seleccion != opcion else { return }
        AppHaptics.selection()
        store.seleccionar(opcion)
    }
}
