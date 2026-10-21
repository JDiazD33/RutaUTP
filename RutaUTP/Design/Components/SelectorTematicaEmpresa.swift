import SwiftUI
import UIKit

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
            IconoPreferencias(simbolo: simbolo)
            VStack(alignment: .leading, spacing: 3) {
                Text(titulo).font(.body).foregroundStyle(EstiloPreferencias.texto)
                if let detalle {
                    Text(detalle).font(.subheadline).foregroundStyle(EstiloPreferencias.textoSecundario)
                }
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if muestraFlecha {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(EstiloPreferencias.textoSecundario)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Colores semánticos para las preferencias; la marca se reserva al acento.
enum EstiloPreferencias {
    static let fondo = Color(uiColor: .systemGroupedBackground)
    static let texto = Color(uiColor: .label)
    static let textoSecundario = Color(uiColor: .secondaryLabel)

    static func acento(para esquema: ColorScheme) -> Color {
        esquema == .dark ? Color.primaryFixed : Color.appPrimary
    }
}

/// Un símbolo sin tarjeta propia. El tamaño decorativo se limita para dejar
/// espacio al texto de accesibilidad, que conserva su escalado completo.
struct IconoPreferencias: View {
    let simbolo: String
    @ScaledMetric(relativeTo: .body) private var tamano = 18.0
    @ScaledMetric(relativeTo: .body) private var ancho = 28.0

    var body: some View {
        Image(systemName: simbolo)
            .font(.system(size: min(tamano, 26), weight: .regular))
            .foregroundStyle(.tint)
            .frame(width: min(ancho, 36), height: min(ancho, 36))
            .accessibilityHidden(true)
    }
}

private struct TintePreferencias: ViewModifier {
    @Environment(\.colorScheme) private var esquema

    func body(content: Content) -> some View {
        content.tint(EstiloPreferencias.acento(para: esquema))
    }
}

extension View {
    func estiloFormularioPreferencias() -> some View {
        self.scrollContentBackground(.hidden)
            .background(EstiloPreferencias.fondo)
            .foregroundStyle(EstiloPreferencias.texto)
            .tintePreferencias()
    }

    func tintePreferencias() -> some View {
        modifier(TintePreferencias())
    }
}
