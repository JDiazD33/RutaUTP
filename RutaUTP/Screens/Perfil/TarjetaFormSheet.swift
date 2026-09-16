import SwiftUI
import Security

struct TarjetaGuardada: Identifiable, Codable, Equatable {
    var id = UUID()
    var nombre: String
    var red: String
    var ultimos4: String
    var etiqueta: String { "\(red) •••• \(ultimos4)" }
}

/// Referencias de tarjetas: nunca almacena el número completo ni el CVV.
final class TarjetasStore: ObservableObject {
    @Published private(set) var tarjetas: [TarjetaGuardada] = []
    @Published var error: String?
    private var cargado = false
    private let service = "RutaUTP.tarjetas.referencias.v1"

    init() { cargar() }
    var principal: TarjetaGuardada? { tarjetas.first }
    private var consulta: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "local"]
    }

    func cargar() {
        var query = consulta
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { cargado = true; return }
        guard status == errSecSuccess, let data = result as? Data,
              let saved = try? JSONDecoder().decode([TarjetaGuardada].self, from: data) else {
            error = L.t("No se pudieron leer las tarjetas guardadas. Inténtalo de nuevo.", "Couldn't read saved cards. Try again.")
            return
        }
        tarjetas = saved
        cargado = true
    }

    @discardableResult private func guardar(_ nuevas: [TarjetaGuardada]) -> Bool {
        // La rama de lectura previa ya publica su propio error desde `cargar()`.
        guard cargado else { cargar(); return false }
        // Esta era la única ruta realmente silenciosa: si fallaba la
        // codificación, el botón "Guardar tarjeta" no hacía nada y el usuario
        // no tenía forma de saber por qué.
        guard let data = try? JSONEncoder().encode(nuevas) else {
            error = L.t("No se pudo preparar el cambio para guardarlo. Inténtalo de nuevo.",
                        "Couldn't prepare the change to be saved. Try again.")
            return false
        }
        var status = SecItemUpdate(consulta as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = consulta
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(query as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            error = L.t("No se pudo guardar el cambio. Tus tarjetas anteriores se conservan.", "Couldn't save the change. Your previous cards are preserved.")
            return false
        }
        tarjetas = nuevas
        return true
    }

    func agregar(_ tarjeta: TarjetaGuardada) -> Bool { guardar(tarjetas + [tarjeta]) }
    func hacerPrincipal(_ tarjeta: TarjetaGuardada) {
        guardar([tarjeta] + tarjetas.filter { $0.id != tarjeta.id })
    }
    func eliminar(_ tarjeta: TarjetaGuardada) -> Bool {
        guardar(tarjetas.filter { $0.id != tarjeta.id })
    }
}

struct MetodosPagoSheet: View {
    @ObservedObject var store: TarjetasStore
    @Environment(\.dismiss) private var dismiss
    @State private var agregar = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.tarjetas.isEmpty {
                        ContentUnavailableView(L.t("Sin tarjetas guardadas", "No saved cards"), systemImage: "creditcard", description: Text(L.t("Añade una referencia para identificar tus tarjetas aquí.", "Add a reference to identify your cards here.")))
                    }
                    ForEach(store.tarjetas) { tarjeta in
                        NavigationLink {
                            TarjetaDetalleView(store: store, tarjeta: tarjeta)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(tarjeta.etiqueta, systemImage: "creditcard.fill")
                                    .font(.headline)
                                Text(tarjeta.nombre).foregroundStyle(.secondary)
                                if store.principal?.id == tarjeta.id {
                                    Text(L.t("Principal", "Default")).font(.caption.bold()).foregroundStyle(Color.appPrimary)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    Button { agregar = true } label: {
                        Label(L.t("Añadir tarjeta", "Add card"), systemImage: "plus.circle.fill")
                    }
                } footer: {
                    Text(L.t("Son referencias guardadas en este dispositivo. No habilitan pagos ni verifican la tarjeta con el banco.", "These are references saved on this device. They don't enable payments or verify cards with the bank."))
                }
            }
            .navigationTitle(L.t("Mis tarjetas", "My cards"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L.t("Listo", "Done")) { dismiss() } } }
            .sheet(isPresented: $agregar) { TarjetaFormSheet(store: store) }
            .alert(L.t("Tarjetas", "Cards"), isPresented: Binding(get: { store.error != nil && !agregar }, set: { if !$0 { store.error = nil } })) {
                Button(L.t("Aceptar", "OK"), role: .cancel) { store.error = nil }
            } message: { Text(store.error ?? "") }
        }
    }
}

private struct TarjetaDetalleView: View {
    @ObservedObject var store: TarjetasStore
    let tarjeta: TarjetaGuardada
    @Environment(\.dismiss) private var dismiss
    @State private var confirmar = false

    var body: some View {
        List {
            Section {
                LabeledContent(L.t("Nombre", "Name"), value: tarjeta.nombre)
                LabeledContent(L.t("Red", "Network"), value: tarjeta.red)
                LabeledContent(L.t("Número", "Number"), value: "•••• \(tarjeta.ultimos4)")
            }
            Section {
                if store.principal?.id == tarjeta.id {
                    Label(L.t("Tarjeta principal", "Default card"), systemImage: "checkmark.circle.fill")
                } else {
                    Button(L.t("Elegir como principal", "Set as default")) { store.hacerPrincipal(tarjeta) }
                }
                Button(L.t("Eliminar tarjeta", "Delete card"), role: .destructive) { confirmar = true }
            }
        }
        .navigationTitle(tarjeta.etiqueta)
        .confirmationDialog(L.t("¿Eliminar esta tarjeta?", "Delete this card?"), isPresented: $confirmar, titleVisibility: .visible) {
            Button(L.t("Eliminar", "Delete"), role: .destructive) {
                if store.eliminar(tarjeta) { dismiss() }
            }
            Button(L.t("Cancelar", "Cancel"), role: .cancel) {}
        } message: { Text(L.t("Se quitará de este dispositivo.", "It will be removed from this device.")) }
    }
}

struct TarjetaFormSheet: View {
    @ObservedObject var store: TarjetasStore
    @Environment(\.dismiss) private var dismiss
    @State private var nombre = ""
    @State private var red = "Visa"
    @State private var ultimos4 = ""

    private var valido: Bool {
        !nombre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && ultimos4.count == 4
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L.t("Nombre (ej. Débito personal)", "Name (e.g. Personal debit)"), text: $nombre)
                        .onChange(of: nombre) { _, value in nombre = String(value.prefix(60)) }
                    Picker(L.t("Red de la tarjeta", "Card network"), selection: $red) {
                        ForEach(["Visa", "Mastercard", "American Express", "Diners Club", L.t("Otra", "Other")], id: \.self) { Text($0).tag($0) }
                    }
                    TextField(L.t("Últimos 4 dígitos", "Last 4 digits"), text: $ultimos4)
                        .keyboardType(.numberPad)
                        .onChange(of: ultimos4) { _, value in
                            ultimos4 = String(value.filter { $0.isASCII && $0.isNumber }.prefix(4))
                        }
                } footer: {
                    Text(L.t("Solo necesitamos un nombre y los últimos cuatro dígitos para reconocerla. No introduzcas el número completo ni el CVV.", "We only need a name and the last four digits to identify it. Don't enter the full card number or CVV."))
                }
                Button(L.t("Guardar tarjeta", "Save card")) {
                    let tarjeta = TarjetaGuardada(nombre: nombre.trimmingCharacters(in: .whitespacesAndNewlines), red: red, ultimos4: ultimos4)
                    if store.agregar(tarjeta) { dismiss() }
                }
                .disabled(!valido)
            }
            .navigationTitle(L.t("Añadir tarjeta", "Add card"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L.t("Cancelar", "Cancel")) { dismiss() } } }
            .alert(L.t("No se pudo guardar", "Couldn't save"), isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button(L.t("Aceptar", "OK"), role: .cancel) { store.error = nil }
            } message: { Text(store.error ?? "") }
        }
    }
}
