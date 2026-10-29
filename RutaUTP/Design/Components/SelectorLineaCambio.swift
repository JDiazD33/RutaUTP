import SwiftUI

/// Comparte la identidad y la búsqueda de Rutas sin cambiar el route_id del reporte.
struct SelectorLineaCambio: View {
    @Binding var seleccion: String
    @StateObject private var catalogo: CatalogoSelectorLinea
    @State private var busqueda = ""
    @Environment(\.dismiss) private var dismiss

    init(routes: [RutaGTFS], seleccion: Binding<String>) {
        _seleccion = seleccion
        _catalogo = StateObject(wrappedValue: CatalogoSelectorLinea(rutas: routes))
    }

    var body: some View {
        let rutas = catalogo.filtrar(busqueda)
        List {
            VStack(alignment: .leading, spacing: 10) {
                Text(L.t("Elige la línea y el ramal del cambio.", "Choose the line and branch affected by the change."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let actual = catalogo.rutas.first(where: { $0.id == seleccion }) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.t("Línea seleccionada", "Selected line"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Label(actual.lineaConLetra, systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.onSurface)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 16, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            Section {
                if rutas.isEmpty {
                    estadoVacio
                        .listRowInsets(EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                ForEach(rutas) { ruta in
                    Button {
                        seleccion = ruta.id
                        dismiss()
                    } label: {
                        FilaLineaCambio(ruta: ruta, seleccionada: seleccion == ruta.id)
                    }
                    .buttonStyle(PulsacionLineaCambio())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel([ruta.lineaConLetra, ruta.empresa, ruta.recorridoLocalizado].joined(separator: ". "))
                    .accessibilityValue(ruta.paraderos.isEmpty ? "" : L.f("{0} paraderos", "{0} stops", ["\(ruta.paraderos.count)"]))
                    .accessibilityAddTraits(seleccion == ruta.id ? .isSelected : [])
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            } header: {
                HStack(spacing: 8) {
                    Text(L.t("Rutas disponibles", "Available routes"))
                    Text("\(rutas.count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Capsule())
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.onSurface)
                .textCase(nil)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle(L.t("Línea y ramal", "Line and branch"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.appSurface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            if !seleccion.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L.t("Quitar", "Remove")) {
                        seleccion = ""
                        dismiss()
                    }
                    .accessibilityLabel(L.t("Quitar selección", "Clear selection"))
                }
            }
        }
        .searchable(text: $busqueda, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: L.t("Código, letra, calle o empresa", "Code, letter, street or operator"))
        .scrollDismissesKeyboard(.interactively)
        .tint(Color.appAccent)
    }

    private var estadoVacio: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(L.t("No se encontraron rutas.", "No routes found."))
                .font(.headline)
            Text(catalogo.rutas.isEmpty
                 ? L.t("El catálogo no contiene rutas.", "The catalog contains no routes.")
                 : L.t("Prueba con el código, la letra, una calle o la empresa.",
                       "Try the code, letter, a street or the operator."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !busqueda.isEmpty && !catalogo.rutas.isEmpty {
                Button(L.t("Ver todas las rutas", "Show all routes")) { busqueda = "" }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

private struct FilaLineaCambio: View {
    let ruta: RutaGTFS
    let seleccionada: Bool
    private static let sufijoCircular = " (ramal circular)"

    private var esCircular: Bool { ruta.recorrido.hasSuffix(Self.sufijoCircular) }
    private var recorrido: String {
        guard esCircular else { return ruta.recorridoLocalizado }
        let nombre = String(ruta.recorrido.dropLast(Self.sufijoCircular.count))
        return nombre.isEmpty ? ruta.recorridoLocalizado : nombre
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                RouteLineIdentity(route: ruta, showsOperator: true, titleFont: .headline)
                Image(systemName: seleccionada ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(seleccionada ? Color.onSurface : Color(uiColor: .secondaryLabel))
                    .accessibilityHidden(true)
            }
            Label {
                Text(recorrido)
                    .foregroundStyle(Color.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(.secondary)
            }
            .font(.body)
            if esCircular || !ruta.paraderos.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { datos }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 8) { datos }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(seleccionada ? Color.appAccent.opacity(0.05) : .clear)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(seleccionada ? Color.appAccent.opacity(0.65)
                              : Color(uiColor: .separator).opacity(0.25), lineWidth: seleccionada ? 1.5 : 0.5)
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private var datos: some View {
        if esCircular {
            Label(L.t("Ramal circular", "Circular branch"), systemImage: "arrow.triangle.2.circlepath")
                .fixedSize(horizontal: false, vertical: true)
        }
        if !ruta.paraderos.isEmpty {
            Label(L.f("{0} paraderos", "{0} stops", ["\(ruta.paraderos.count)"]), systemImage: "mappin.and.ellipse")
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// El catálogo y sus índices se preparan una vez mientras el selector está abierto.
@MainActor
private final class CatalogoSelectorLinea: ObservableObject {
    let rutas: [RutaGTFS]
    private let entradas: [(ruta: RutaGTFS, indice: IndiceBusquedaRuta)]
    private let letras: Set<String>

    init(rutas: [RutaGTFS]) {
        self.rutas = rutas
        entradas = rutas.map { ($0, IndiceBusquedaRuta(ruta: $0)) }
        letras = Set(rutas.map { IndiceBusquedaRuta.compactar($0.letraTransporte) })
    }

    func filtrar(_ texto: String) -> [RutaGTFS] {
        guard !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return rutas }
        let consulta = ConsultaRuta(texto, letras: letras)
        return entradas.compactMap { $0.indice.coincide(con: consulta) ? $0.ruta : nil }
    }
}

private struct PulsacionLineaCambio: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
