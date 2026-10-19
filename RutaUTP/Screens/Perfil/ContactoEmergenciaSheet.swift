import SwiftUI
import Contacts
import ContactsUI

/// Las claves históricas siguen siendo la fuente compartida de Perfil y Seguridad.
enum ContactoEmergencia {
    static let claveNombre = "emergencia_nombre"
    static let claveParentesco = "emergencia_parentesco"
    static let claveNumero = "emergencia_numero"
    static let claveAlternativo = "emergencia_numeroAlternativo"

    static func telefonoValido(_ valor: String) -> String? {
        let limpio = valor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard limpio.allSatisfy({ "0123456789+()- .".contains($0) || $0 == "\u{00a0}" }),
              limpio.filter({ $0 == "+" }).count <= 1,
              !limpio.contains("+") || limpio.hasPrefix("+") else { return nil }
        let digitos = limpio.filter { $0 >= "0" && $0 <= "9" }
        guard (7...15).contains(digitos.count) else { return nil }
        return limpio.hasPrefix("+") ? "+" + digitos : digitos
    }
}

enum Parentesco: String, CaseIterable, Identifiable {
    // Los rawValue ya persistidos se conservan, incluidos su escritura y acentos.
    case padreMadre = "Padre/Madre"
    case tutorApoderado = "Tutor/Apoderado"
    case conyugePareja = "Conyuge/Pareja de hecho"
    case hermano = "Hermano(a)"
    case hijo = "Hijo(a)"
    case amistad = "Amigo(a)"
    case abuelo = "Abuelo(a)"
    case tio = "Tío(a)"
    case primo = "Primo(a)"
    case otro = "Otro"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .padreMadre: return L.t("Padre/Madre", "Parent")
        case .tutorApoderado: return L.t("Tutor/Apoderado", "Guardian")
        case .conyugePareja: return L.t("Conyuge/Pareja de hecho", "Spouse/Partner")
        case .hermano: return L.t("Hermano(a)", "Sibling")
        case .hijo: return L.t("Hijo(a)", "Child")
        case .amistad: return L.t("Amigo(a)", "Friend")
        case .abuelo: return L.t("Abuelo(a)", "Grandparent")
        case .tio: return L.t("Tío(a)", "Aunt/Uncle")
        case .primo: return L.t("Primo(a)", "Cousin")
        case .otro: return L.t("Otro", "Other")
        }
    }
}

/// Un solo editor, abierto tanto desde Datos personales como desde Seguridad.
struct ContactoEmergenciaSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var textSize
    @AppStorage(ContactoEmergencia.claveNombre) private var nombreGuardado = ""
    @AppStorage(ContactoEmergencia.claveParentesco) private var parentescoGuardado = ""
    @AppStorage(ContactoEmergencia.claveNumero) private var numeroGuardado = ""
    @AppStorage(ContactoEmergencia.claveAlternativo) private var alternativoGuardado = ""
    @State private var nombre = ""
    @State private var parentesco = ""
    @State private var numero = ""
    @State private var alternativo = ""
    @State private var cargado = false
    @State private var mostrarAgenda = false
    @State private var confirmarEliminar = false
    @FocusState private var campo: Campo?

    private enum Campo: Hashable { case nombre, numero, alternativo }
    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }
    private var nombreLimpio: String { nombre.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var numeroValido: String? { ContactoEmergencia.telefonoValido(numero) }
    private var alternativoLimpio: String { alternativo.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var errorAlternativo: String? {
        guard !alternativoLimpio.isEmpty else { return nil }
        guard let otro = ContactoEmergencia.telefonoValido(alternativo) else {
            return L.t("Usa entre 7 y 15 dígitos, con código de país si hace falta.",
                       "Use 7 to 15 digits, with a country code if needed.")
        }
        return otro == numeroValido
            ? L.t("Usa un número diferente al principal.", "Use a different number from the primary one.") : nil
    }
    private var puedeGuardar: Bool { !nombreLimpio.isEmpty && numeroValido != nil && errorAlternativo == nil }
    private var hayContacto: Bool {
        !nombreGuardado.isEmpty || !numeroGuardado.isEmpty || !alternativoGuardado.isEmpty || !parentescoGuardado.isEmpty
    }
    private var relacion: String {
        Parentesco(rawValue: parentesco)?.label ?? (parentesco.isEmpty ? L.t("Sin especificar", "Not specified") : parentesco)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    vistaPrevia
                    Button {
                        campo = nil
                        mostrarAgenda = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.rectangle.stack")
                            Text(L.t("Elegir de Contactos", "Choose from Contacts"))
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        }
                        .font(.bodyMd)
                        .foregroundStyle(acento)
                        .padding(16)
                        .frame(minHeight: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(superficie, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    VStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 6) {
                            etiqueta(L.t("Nombre", "Name"))
                            TextField(L.t("Nombre y apellido", "Full name"), text: $nombre)
                                .textContentType(.name)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .focused($campo, equals: .nombre)
                                .submitLabel(.next)
                                .onSubmit { campo = .numero }
                                .accessibilityLabel(L.t("Nombre del contacto", "Contact name"))
                        }
                        .padding(16)
                        separador
                        VStack(alignment: .leading, spacing: 4) {
                            etiqueta(L.t("Parentesco", "Relationship"))
                            Menu {
                                Picker(L.t("Parentesco", "Relationship"), selection: $parentesco) {
                                    Text(L.t("Sin especificar", "Not specified")).tag("")
                                    ForEach(Parentesco.allCases) { opcion in
                                        Text(opcion.label).tag(opcion.rawValue)
                                    }
                                    if !parentesco.isEmpty, Parentesco(rawValue: parentesco) == nil {
                                        Text(parentesco).tag(parentesco)
                                    }
                                }
                                .pickerStyle(.inline)
                            } label: {
                                HStack {
                                    Text(relacion).fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption.weight(.semibold)).foregroundStyle(acento)
                                }
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .accessibilityLabel(L.t("Parentesco del contacto", "Relationship of the contact"))
                            .accessibilityValue(relacion)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        separador
                        campoTelefono(L.t("Teléfono principal", "Primary phone"), texto: $numero, foco: .numero)
                        if !numero.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, numeroValido == nil {
                            errorTelefono(L.t("Usa entre 7 y 15 dígitos, con código de país si hace falta.",
                                               "Use 7 to 15 digits, with a country code if needed."))
                        }
                        separador
                        campoTelefono(L.t("Teléfono alternativo (opcional)", "Alternate phone (optional)"),
                                      texto: $alternativo, foco: .alternativo)
                        if let errorAlternativo { errorTelefono(errorAlternativo) }
                    }
                    .font(.bodyMd).foregroundStyle(Color.onSurface)
                    .background(superficie, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    if hayContacto {
                        Button(role: .destructive) {
                            campo = nil
                            confirmarEliminar = true
                        } label: {
                            Label(L.t("Quitar contacto", "Remove contact"), systemImage: "person.crop.circle.badge.minus")
                                .font(.bodyMd).frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.plain).foregroundStyle(Color.appError)
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.appBackground)
            .safeAreaInset(edge: .bottom, spacing: 0) { guardar }
            .navigationTitle(L.t("Mi contacto", "My contact"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("Cancelar", "Cancel")) { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L.t("Listo", "Done")) { campo = nil }
                }
            }
            .confirmationDialog(L.t("¿Quitar contacto de emergencia?", "Remove emergency contact?"),
                                isPresented: $confirmarEliminar, titleVisibility: .visible) {
                Button(L.t("Quitar contacto", "Remove contact"), role: .destructive) {
                    nombreGuardado = ""; parentescoGuardado = ""; numeroGuardado = ""; alternativoGuardado = ""
                    dismiss()
                }
                Button(L.t("Cancelar", "Cancel"), role: .cancel) {}
            } message: {
                Text(L.t("Se quitará de Perfil y Seguridad.", "It will be removed from Profile and Safety."))
            }
            .sheet(isPresented: $mostrarAgenda) {
                SelectorContactoEmergencia { nombreElegido, telefono in
                    nombre = nombreElegido
                    parentesco = ""
                    alternativo = ""
                    numero = telefono
                    mostrarAgenda = false
                } cancelar: { mostrarAgenda = false }
                .ignoresSafeArea()
            }
        }
        .tint(acento)
        .seguirTemaForzado()
        .onAppear {
            guard !cargado else { return }
            nombre = nombreGuardado; parentesco = parentescoGuardado
            numero = numeroGuardado; alternativo = alternativoGuardado
            cargado = true
        }
    }

    private var superficie: Color { Color(uiColor: .secondarySystemGroupedBackground) }
    private var separador: some View { Divider().padding(.leading, 16).accessibilityHidden(true) }

    private var vistaPrevia: some View {
        VStack(alignment: .leading, spacing: 14) {
            (textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                                         : AnyLayout(HStackLayout(spacing: 14))) {
                ZStack {
                    Circle().fill(Color(uiColor: .tertiarySystemGroupedBackground))
                    if nombreLimpio.isEmpty {
                        Image(systemName: "person.fill").font(.title2)
                    } else {
                        Text(nombreLimpio.split(whereSeparator: \.isWhitespace).prefix(2)
                            .compactMap(\.first).map(String.init).joined().uppercased())
                            .font(.title3.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.5)
                    }
                }
                .foregroundStyle(acento).frame(width: 56, height: 56).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(nombreLimpio.isEmpty ? L.t("Mi contacto", "My contact") : nombreLimpio)
                        .font(.title3.weight(.semibold)).foregroundStyle(Color.onSurface)
                    if !parentesco.isEmpty {
                        Text(relacion).font(.bodySm).foregroundStyle(Color.onSurfaceVariant)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                if !textSize.isAccessibilitySize { Spacer(minLength: 0) }
            }
            Label(L.t("El mismo contacto en Perfil y Seguridad", "The same contact in Profile and Safety"),
                  systemImage: "link")
                .font(.footnote).foregroundStyle(Color.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func etiqueta(_ texto: String) -> some View {
        Text(texto).font(.caption).foregroundStyle(Color.onSurfaceVariant)
    }

    private func campoTelefono(_ titulo: String, texto: Binding<String>, foco: Campo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            etiqueta(titulo)
            TextField(L.t("Ej. +51 999 888 777", "E.g. +51 999 888 777"), text: texto)
                .keyboardType(.phonePad).textContentType(.telephoneNumber)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($campo, equals: foco)
                .accessibilityLabel(titulo)
        }
        .padding(16)
    }

    private func errorTelefono(_ texto: String) -> some View {
        Text(texto).font(.footnote).foregroundStyle(Color.appError)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16).padding(.bottom, 12)
    }

    private var guardar: some View {
        Button {
            guard puedeGuardar, let telefono = numeroValido else { return }
            nombreGuardado = nombreLimpio
            parentescoGuardado = parentesco
            numeroGuardado = telefono
            alternativoGuardado = ContactoEmergencia.telefonoValido(alternativo) ?? ""
            AppHaptics.success()
            dismiss()
        } label: {
            Text(L.t("Guardar contacto", "Save contact"))
                .font(.bodyMdMedium).frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(puedeGuardar ? Color.onPrimaryFill : Color.onSurfaceVariant)
                .background(puedeGuardar ? Color.primaryFill : Color.surfaceContainerHigh,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain).disabled(!puedeGuardar)
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Color.appSurface)
    }
}

/// El selector del sistema entrega únicamente la selección hecha por la persona.
private struct SelectorContactoEmergencia: UIViewControllerRepresentable {
    let seleccionar: (String, String) -> Void
    let cancelar: () -> Void

    func makeCoordinator() -> Coordinador { Coordinador(seleccionar: seleccionar, cancelar: cancelar) }
    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        picker.predicateForSelectionOfContact = NSPredicate(format: "phoneNumbers.@count == 1")
        picker.predicateForSelectionOfProperty = NSPredicate(format: "key == %@", CNContactPhoneNumbersKey)
        return picker
    }
    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    final class Coordinador: NSObject, CNContactPickerDelegate {
        let seleccionar: (String, String) -> Void
        let cancelar: () -> Void
        init(seleccionar: @escaping (String, String) -> Void, cancelar: @escaping () -> Void) {
            self.seleccionar = seleccionar; self.cancelar = cancelar
        }
        func contactPickerDidCancel(_ picker: CNContactPickerViewController) { cancelar() }
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            guard let telefono = contact.phoneNumbers.first?.value.stringValue else { return }
            seleccionar(CNContactFormatter.string(from: contact, style: .fullName) ?? "", telefono)
        }
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty) {
            guard let telefono = contactProperty.value as? CNPhoneNumber else { return }
            seleccionar(CNContactFormatter.string(from: contactProperty.contact, style: .fullName) ?? "",
                        telefono.stringValue)
        }
    }
}
