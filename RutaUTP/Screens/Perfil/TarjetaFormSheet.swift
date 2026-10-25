import SwiftUI
import Security

struct TarjetaGuardada: Identifiable, Codable, Equatable {
    var id = UUID()
    var nombre: String
    var red: String
    var ultimos4: String
    var etiqueta: String { "\(red) •••• \(ultimos4)" }

    var esValida: Bool {
        !nombre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !red.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && ultimos4.count == 4 && ultimos4.allSatisfy { $0.isASCII && $0.isNumber }
    }
}

/// Adaptador inyectable para comprobar fallos sin tocar el llavero del usuario.
protocol ReferenciasTarjetasPersistiendo {
    func leer() throws -> Data?
    func guardar(_ data: Data) throws
}

struct LlaveroReferenciasTarjetas: ReferenciasTarjetasPersistiendo {
    private let service = "RutaUTP.tarjetas.referencias.v1"
    private var consulta: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "local"]
    }

    func leer() throws -> Data? {
        var query = consulta
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        guard let data = result as? Data else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecDecode))
        }
        return data
    }

    func guardar(_ data: Data) throws {
        var status = SecItemUpdate(consulta as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = consulta
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(query as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}

/// Referencias de tarjetas: nunca almacena el número completo ni el CVV.
@MainActor
final class TarjetasStore: ObservableObject {
    @Published private(set) var tarjetas: [TarjetaGuardada] = []
    @Published private(set) var lecturaFallida = false
    @Published var error: String?
    private let persistencia: ReferenciasTarjetasPersistiendo

    init(persistencia: ReferenciasTarjetasPersistiendo = LlaveroReferenciasTarjetas()) {
        self.persistencia = persistencia
        cargar()
    }

    var principal: TarjetaGuardada? { tarjetas.first }

    @discardableResult
    func cargar() -> Bool {
        do {
            let data = try persistencia.leer()
            let guardadas = try data.map { try JSONDecoder().decode([TarjetaGuardada].self, from: $0) } ?? []
            guard Set(guardadas.map(\.id)).count == guardadas.count,
                  guardadas.allSatisfy(\.esValida) else { throw CocoaError(.coderReadCorrupt) }
            tarjetas = guardadas // Ausencia real limpia la copia en memoria.
            lecturaFallida = false
            error = nil
            return true
        } catch {
            // Incluso después de una lectura válida, este fallo bloquea la
            // operación actual y mantiene intacto el original del llavero.
            lecturaFallida = true
            self.error = L.t("No se pudieron leer las tarjetas guardadas. Los originales se conservan. Inténtalo de nuevo.",
                             "Couldn't read saved cards. The originals have been preserved. Try again.")
            return false
        }
    }

    private func guardar(_ nuevas: [TarjetaGuardada]) -> Bool {
        do {
            let data = try JSONEncoder().encode(nuevas)
            try persistencia.guardar(data)
        } catch {
            self.error = L.t("No se pudo guardar el cambio. Tus tarjetas anteriores se conservan.", "Couldn't save the change. Your previous cards are preserved.")
            return false
        }
        tarjetas = nuevas
        return true
    }

    func agregar(_ tarjeta: TarjetaGuardada) -> Bool {
        guard cargar() else { return false }
        guard tarjeta.esValida, !tarjetas.contains(where: { $0.id == tarjeta.id }) else {
            error = L.t("La referencia no es válida o ya está guardada.", "The reference is invalid or already saved.")
            return false
        }
        return guardar(tarjetas + [tarjeta])
    }

    @discardableResult
    func hacerPrincipal(_ tarjeta: TarjetaGuardada) -> Bool {
        guard cargar(), let vigente = referenciaVigente(tarjeta.id) else { return false }
        return guardar([vigente] + tarjetas.filter { $0.id != vigente.id })
    }

    func eliminar(_ tarjeta: TarjetaGuardada) -> Bool {
        guard cargar(), referenciaVigente(tarjeta.id) != nil else { return false }
        return guardar(tarjetas.filter { $0.id != tarjeta.id })
    }

    private func referenciaVigente(_ id: UUID) -> TarjetaGuardada? {
        guard let tarjeta = tarjetas.first(where: { $0.id == id }) else {
            error = L.t("Esta referencia ya no está guardada. Vuelve a la lista de tarjetas.",
                        "This reference is no longer saved. Return to the card list.")
            return nil
        }
        return tarjeta
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
                    Label(L.t("Referencias de tarjetas", "Card references"),
                          systemImage: "creditcard")
                        .font(.headline)
                    Text(L.t("Organiza tus tarjetas con un nombre, su red y los últimos cuatro dígitos. Estas referencias se guardan en el llavero de este dispositivo. No permiten pagar, recargar el monedero ni usar NFC.",
                             "Organize your cards using a name, their network and the last four digits. These references are saved in this device's Keychain. They cannot be used to pay, top up the wallet or use NFC."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    if store.lecturaFallida {
                        Text(L.t("No se pudieron leer las referencias. Los cambios están bloqueados y los originales se conservan.",
                                 "References could not be read. Changes are blocked and the originals have been preserved."))
                        Button(L.t("Reintentar lectura", "Retry reading")) { store.cargar() }
                    } else if store.tarjetas.isEmpty {
                        ContentUnavailableView(L.t("Sin referencias guardadas", "No saved references"), systemImage: "creditcard", description: Text(L.t("Añade una referencia para identificar tus tarjetas aquí.", "Add a reference to identify your cards here.")))
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
                                    Text(L.t("Principal", "Default")).font(.caption.bold()).foregroundStyle(Color.appAccent)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    Button { agregar = true } label: {
                        Label(L.t("Añadir referencia", "Add reference"), systemImage: "plus.circle.fill")
                    }
                    .disabled(store.lecturaFallida)
                } footer: {
                    Text(L.t("Son referencias guardadas en este dispositivo. No habilitan pagos ni verifican la tarjeta con el banco.", "These are references saved on this device. They don't enable payments or verify cards with the bank."))
                }
            }
            .navigationTitle(L.t("Mis tarjetas", "My cards"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L.t("Listo", "Done")) { dismiss() } } }
            .sheet(isPresented: $agregar) { TarjetaFormSheet(store: store) }
            .onAppear { store.cargar() }
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
                if store.lecturaFallida {
                    Button(L.t("Reintentar lectura", "Retry reading")) { store.cargar() }
                }
                LabeledContent(L.t("Nombre", "Name"), value: tarjeta.nombre)
                LabeledContent(L.t("Red", "Network"), value: tarjeta.red)
                LabeledContent(L.t("Últimos 4 dígitos", "Last 4 digits"), value: "•••• \(tarjeta.ultimos4)")
            }
            Section {
                if store.principal?.id == tarjeta.id {
                    Label(L.t("Referencia principal", "Primary reference"), systemImage: "checkmark.circle.fill")
                } else {
                    Button(L.t("Elegir como principal", "Set as default")) { store.hacerPrincipal(tarjeta) }
                        .disabled(store.lecturaFallida)
                }
                Button(L.t("Eliminar referencia", "Delete reference"), role: .destructive) { confirmar = true }
                    .disabled(store.lecturaFallida)
            }
        }
        .navigationTitle(tarjeta.etiqueta)
        .confirmationDialog(L.t("¿Eliminar esta referencia?", "Delete this reference?"), isPresented: $confirmar, titleVisibility: .visible) {
            Button(L.t("Eliminar", "Delete"), role: .destructive) {
                if store.eliminar(tarjeta) { dismiss() }
            }
            Button(L.t("Cancelar", "Cancel"), role: .cancel) {}
        } message: { Text(L.t("Solo se eliminará la referencia local; tu tarjeta bancaria no se modifica.", "Only the local reference will be removed; your bank card will not change.")) }
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
                    Text(L.t("Se guardarán el nombre, la red y los últimos cuatro dígitos en este dispositivo. No introduzcas el número completo ni el CVV. No vincula la tarjeta con el banco ni habilita pagos.", "The name, network and last four digits will be saved on this device. Don't enter the full card number or CVV. This does not link the card to the bank or enable payments."))
                }
                Button(L.t("Guardar referencia", "Save reference")) {
                    let tarjeta = TarjetaGuardada(nombre: nombre.trimmingCharacters(in: .whitespacesAndNewlines), red: red, ultimos4: ultimos4)
                    if store.agregar(tarjeta) { dismiss() }
                }
                .disabled(!valido)
            }
            .navigationTitle(L.t("Añadir referencia", "Add reference"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L.t("Cancelar", "Cancel")) { dismiss() } } }
            .alert(L.t("No se pudo guardar", "Couldn't save"), isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button(L.t("Aceptar", "OK"), role: .cancel) { store.error = nil }
            } message: { Text(store.error ?? "") }
        }
    }
}
