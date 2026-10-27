//
//  EditorDatosPersonales.swift
//  RutaUTP
//
//  Edición del teléfono y correo personales, con validación y guardado
//  explícito en las claves del perfil.
//

import SwiftUI

// Borrador separado: cerrar o cancelar nunca escribe en las claves del perfil.
struct EditorDatosPersonales: View {
    @Binding var telefono: String
    @Binding var correo: String
    let onGuardar: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var campo: Campo?
    private enum Campo { case telefono, correo }

    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }
    private var numeroValido: String? { ContactoEmergencia.telefonoValido(telefono) }
    private var telefonoValido: Bool {
        telefono.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || numeroValido != nil
    }
    private var correoLimpio: String { correo.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var correoValido: Bool {
        correoLimpio.isEmpty || correoLimpio.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }
    private var puedeGuardar: Bool { telefonoValido && correoValido }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(L.t("Actualiza tu teléfono y correo personal.", "Update your phone and personal email."))
                        .font(.body).foregroundStyle(.secondary)
                }
                Section {
                    TextField(L.t("Teléfono", "Phone"), text: $telefono)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($campo, equals: .telefono)
                        .accessibilityLabel(L.t("Teléfono", "Phone"))
                } header: {
                    Label(L.t("Teléfono", "Phone"), systemImage: "phone")
                } footer: {
                    if !telefonoValido {
                        Text(L.t("Ingresa un teléfono válido.", "Enter a valid phone number."))
                            .foregroundStyle(Color(uiColor: .systemRed))
                    }
                }
                Section {
                    TextField(L.t("correo@ejemplo.com", "email@example.com"), text: $correo)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($campo, equals: .correo)
                        .submitLabel(.done)
                        .onSubmit { campo = nil }
                        .accessibilityLabel(L.t("Correo personal", "Personal email"))
                } header: {
                    Label(L.t("Correo personal", "Personal email"), systemImage: "envelope")
                } footer: {
                    if !correoValido {
                        Text(L.t("Escribe un correo válido.", "Enter a valid email address."))
                            .foregroundStyle(Color(uiColor: .systemRed))
                    }
                }
                Section {
                    Text(L.t("Estos datos se guardan en este dispositivo.", "These details are saved on this device."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(L.t("Editar datos personales", "Edit personal details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("Cancelar", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Guardar", "Save")) {
                        guard puedeGuardar else { return }
                        campo = nil
                        onGuardar(numeroValido ?? "", correoLimpio)
                        AppHaptics.success()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!puedeGuardar)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L.t("Listo", "Done")) { campo = nil }
                }
            }
        }
        .tint(acento)
    }
}
