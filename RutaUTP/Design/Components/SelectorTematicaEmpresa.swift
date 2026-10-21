import SwiftUI

/// Fila de Ajustes; el catálogo y su confirmación conservan el flujo existente.
struct SelectorTematicaEmpresa: View {
    @State private var mostrarTematicas = false
    private let store = TematicaEmpresaStore.shared

    var body: some View {
        Button { mostrarTematicas = true } label: {
            FilaAjustes(titulo: L.t("Temática de colores", "Color theme"), simbolo: "paintpalette.fill",
                        detalle: store.seleccion.nombre)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("Cambiar temática de colores", "Change color theme"))
        .accessibilityValue(store.seleccion.nombre)
        .accessibilityHint(L.t("Abre las empresas disponibles y permite elegir tu sede", "Opens available companies and lets you choose your workplace"))
        .sheet(isPresented: $mostrarTematicas) {
            SelectorTematicasSheet()
                .seguirTemaForzado()
                .presentationDetents([.large])
        }
    }
}

/// Etiqueta para filas nativas: icono de temática, título y valor actual.
struct FilaAjustes: View {
    let titulo: String
    let simbolo: String
    var detalle: String? = nil
    var muestraFlecha = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: simbolo)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.onPrimaryFill)
                .frame(width: 30, height: 30)
                .background(Color.primaryFill, in: RoundedRectangle(cornerRadius: 7))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(titulo).font(.body).foregroundStyle(.onSurface)
                if let detalle {
                    Text(detalle).font(.subheadline).foregroundStyle(.onSurfaceVariant)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if muestraFlecha {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.onSurfaceVariant)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
