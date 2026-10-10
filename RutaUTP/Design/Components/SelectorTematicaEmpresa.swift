import SwiftUI

/// Resumen compacto: el catálogo completo se abre solo cuando se quiere cambiar.
struct SelectorTematicaEmpresa: View {
    @State private var mostrarTematicas = false
    private let store = TematicaEmpresaStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("TEMÁTICA DE COLORES", "COLOR THEME"))
                .font(.labelCapsMd)
                .foregroundStyle(.onSurfaceVariant)
                .appTracking(AppTracking.wideLabel)
                .accessibilityAddTraits(.isHeader)

            Button { mostrarTematicas = true } label: {
                HStack(spacing: 16) {
                    LogoEmpresa(empresa: store.seleccion)
                        .frame(width: 88, height: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.seleccion.nombre).font(.body.weight(.semibold))
                        Text(L.t("Cambiar temática", "Change theme"))
                            .font(.caption).foregroundStyle(.onSurfaceVariant)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.onSurfaceVariant)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(.onSurface)
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .background(Color.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L.t("Cambiar temática de colores", "Change color theme"))
            .accessibilityValue(store.seleccion.nombre)
            .accessibilityHint(L.t("Abre las empresas disponibles y permite elegir tu sede", "Opens available companies and lets you choose your workplace"))

            Text(L.t("Confirma tu empresa y sede para aplicar sus colores y la referencia del mapa.",
                     "Confirm your company and workplace to apply its colors and map reference."))
                .font(.bodySm).foregroundStyle(.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)

            if store.seleccion != .utp || !TransporteApp.utpComoReferencia {
                Button {
                    AppHaptics.selection()
                    TransporteApp.usarSedeTrabajo(CatalogoSedesTrabajo.campusUTP)
                } label: {
                    HStack(spacing: 12) {
                        LogoEmpresa(empresa: .utp).frame(width: 64, height: 24)
                        Text(L.t("Volver a UTP", "Return to UTP"))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.uturn.backward").accessibilityHidden(true)
                    }
                    .font(.bodySm).foregroundStyle(.appPrimary)
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L.t("Volver a UTP", "Return to UTP"))
                .accessibilityHint(L.t("Restaura los colores UTP y el campus de Trujillo en el mapa", "Restores UTP colors and the Trujillo campus on the map"))
            }
        }
        .sheet(isPresented: $mostrarTematicas) {
            SelectorTematicasSheet()
                .seguirTemaForzado()
                .presentationDetents([.large])
        }
    }
}
