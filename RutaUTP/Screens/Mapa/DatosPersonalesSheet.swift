//
//  DatosPersonalesSheet.swift
//  RutaUTP
//
//  Datos personales del estudiante: ficha de solo lectura, datos
//  editables y contacto de emergencia.
//  
//  Estaba dentro de `SideDrawer.swift`. Se lleva consigo `Parentesco`
//  y su selector, que solo usa esta hoja.

import SwiftUI
import UIKit
// MARK: - Lista de parentesco
enum Parentesco: String, CaseIterable, Identifiable {
    case padreMadre          = "Padre/Madre"
    case tutorApoderado      = "Tutor/Apoderado"
    case conyugePareja       = "Conyuge/Pareja de hecho"
    case hermano             = "Hermano(a)"
    case hijo                = "Hijo(a)"
    case otro                = "Otro"

    var id: String { rawValue }

    /// Texto visible. El `rawValue` se guarda en `UserDefaults`
    /// (`emergencia_parentesco`), así que se mantiene como clave estable y no
    /// se traduce: cambiar el rawValue invalidaría el dato ya guardado.
    var label: String {
        switch self {
        case .padreMadre:     return L.t("Padre/Madre", "Parent")
        case .tutorApoderado: return L.t("Tutor/Apoderado", "Guardian")
        case .conyugePareja:  return L.t("Conyuge/Pareja de hecho", "Spouse/Partner")
        case .hermano:        return L.t("Hermano(a)", "Sibling")
        case .hijo:           return L.t("Hijo(a)", "Child")
        case .otro:           return L.t("Otro", "Other")
        }
    }
}

// MARK: - Selector de parentesco (ventanita)
private struct ParentescoPickerSheet: View {
    @Binding var seleccion: String
    @Environment(\.dismiss) private var dismiss
    @State private var local: String

    init(seleccion: Binding<String>) {
        self._seleccion = seleccion
        self._local = State(initialValue: seleccion.wrappedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(icon: "person.2.fill", iconColor: .appPrimary, title: L.t("Parentesco", "Relationship"))

            VStack(spacing: 8) {
                ForEach(Parentesco.allCases) { op in
                    Button {
                        AppHaptics.selection()
                        local = op.rawValue
                    } label: {
                        HStack {
                            Image(systemName: local == op.rawValue ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(local == op.rawValue ? Color.appPrimary : Color.onSurfaceVariant)
                                .accessibilityHidden(true)
                            Text(op.label)
                                .font(.bodyMd)
                                .foregroundStyle(.onSurface)
                            Spacer()
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(local == op.rawValue ? Color.primaryContainer.opacity(0.25) : Color.surfaceContainerLow)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(op.label)
                    .accessibilityValue(local == op.rawValue ? "Seleccionado" : "No seleccionado")
                    .accessibilityHint(L.t("Doble toque para elegir ", "Double tap to choose ") + op.label)
                    .accessibilityAddTraits(local == op.rawValue ? [.isButton, .isSelected] : .isButton)
                }
            }

            Spacer()

            Button {
                AppHaptics.success()
                seleccion = local
                dismiss()
            } label: {
                Text(L.t("Aceptar", "OK"))
                    .font(.headlineSm)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.appPrimary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Aceptar parentesco", "Confirm relationship"))
            .accessibilityHint(L.t("Doble toque para confirmar la selección", "Double tap to confirm the selection"))
        }
        .padding(20)
    }
}

// MARK: - 7. DATOS PERSONALES SHEET
struct DatosPersonalesSheet: View {
    // Datos institucionales (solo lectura)
    private let nombresCompletos = "Joaquín Díaz"
    private let carrera = "Ingeniería de Software"
    private let correoInstitucional = "joaquin.diaz@utp.edu.pe"
    private let codigoUTP = "1234567"
    private let dni = "76543210"
    private let modalidad = "Presencial"
    private let campus = "Trujillo"

    // Datos personales editables (persisten)
    @AppStorage("perfil_telefono") private var telefono: String = "999888777"
    @AppStorage("perfil_correoPersonal") private var correoPersonal: String = "joaquin.diaz@gmail.com"

    // Datos del contacto de emergencia (persisten)
    @AppStorage("emergencia_nombre") private var emergenciaNombre: String = ""
    @AppStorage("emergencia_parentesco") private var emergenciaParentesco: String = ""
    @AppStorage("emergencia_numero") private var emergenciaNumero: String = ""

    // Edición datos personales
    @State private var editandoDatos: Bool = false
    @State private var telefonoInput: String = ""
    @State private var correoPersonalInput: String = ""
    @State private var showCorreoTooltip: Bool = false

    // Foto de perfil
    @State private var perfilImage: UIImage? = nil
    @State private var showFuenteFoto = false
    @State private var showGaleria = false
    @State private var ajustarFoto = false
    @State private var showCamera: Bool = false

    // Edición contacto de emergencia
    @State private var editandoEmergencia: Bool = false
    @State private var emergenciaNombreInput: String = ""
    @State private var emergenciaParentescoInput: String = ""
    @State private var emergenciaNumeroInput: String = ""
    @State private var showParentescoPicker: Bool = false

    private let boxShape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                SheetHeader(icon: "person.crop.circle.fill", iconColor: .appPrimary, title: L.t("Datos Personales", "Personal details"))

                // ── Cabecera: foto + nombres + carrera + correo institucional ──
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [Color.appPrimary, Color.primaryContainer, Color.tertiary],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .frame(width: 80, height: 80)
                                .overlay(Circle().stroke(Color.white, lineWidth: 3))
                                .accessibilityHidden(true)
                            if let img = perfilImage {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.white, lineWidth: 3))
                                    .accessibilityLabel(L.t("Foto de perfil", "Profile photo"))
                                    .accessibilityAddTraits(.isImage)
                            } else {
                                Text("JD")
                                    .font(.headlineMd)
                                    .foregroundStyle(.white)
                                    .accessibilityHidden(true)
                            }
                        }
                        .overlay(alignment: .bottomTrailing) {
                            Button {
                                AppHaptics.impact(.light)
                                showFuenteFoto = true
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 26, height: 26)
                                        .overlay(Circle().stroke(Color.purple, lineWidth: 1.5))
                                        .accessibilityHidden(true)
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Color.purple)
                                        .accessibilityHidden(true)
                                }
                            }
                            .buttonStyle(.plain)
                            .offset(x: 4, y: 4)
                            .accessibilityLabel(L.t("Cambiar foto de perfil", "Change profile photo"))
                            .accessibilityHint(L.t("Elige entre cámara y biblioteca de fotos", "Choose camera or photo library"))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(nombresCompletos)
                                .font(.headlineSm)
                                .foregroundStyle(.onSurface)
                            Text(carrera)
                                .font(.bodySmMedium)
                                .foregroundStyle(.onSurfaceVariant)
                        }
                        .accessibilityElement(children: .combine)
                        Spacer()
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.appPrimary)
                            .accessibilityHidden(true)
                        Text(correoInstitucional)
                            .font(.bodySm)
                            .foregroundStyle(.onSurfaceVariant)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(L.t("Correo institucional: ", "Institutional email: ") + correoInstitucional)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // ── Cuadro: Código UTP / DNI / Modalidad / Campus ──
                VStack(spacing: 16) {
                    HStack(spacing: 0) {
                        datoInstitucional(titulo: L.t("CÓDIGO UTP", "UTP CODE"), valor: codigoUTP)
                        Rectangle()
                            .fill(Color.outlineVariant.opacity(0.5))
                            .frame(width: 1, height: 48)
                        datoInstitucional(titulo: L.t("DNI", "ID NUMBER"), valor: dni)
                    }

                    Divider()

                    datoHorizontal(titulo: L.t("MODALIDAD DE CARRERA", "STUDY MODE"), valor: modalidad)

                    Divider()

                    datoHorizontal(titulo: L.t("CAMPUS", "CAMPUS"), valor: campus)
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.surfaceContainerLowest)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.outlineVariant.opacity(0.25), lineWidth: 0.5)
                        )
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel(L.t("Datos institucionales", "Institutional details"))
                .accessibilityValue(L.t("Código UTP ", "UTP code ") + "\(codigoUTP), DNI \(dni), "
                                      + L.t("modalidad ", "modality ") + "\(modalidad), campus \(campus)")

                // ── Mis datos personales + editar ──
                HStack {
                    Text(L.t("Mis datos personales", "My personal details"))
                        .font(.headlineXs)
                        .foregroundStyle(.onSurface)
                    Spacer()
                    Button {
                        AppHaptics.impact(.light)
                        toggleEdicion()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: editandoDatos ? "checkmark" : "pencil")
                                .font(.system(size: 12, weight: .semibold))
                                .accessibilityHidden(true)
                            Text(editandoDatos ? L.t("Listo", "Done") : L.t("editar datos", "edit details"))
                                .font(.labelCapsSm)
                                .appTracking(AppTracking.wideLabel)
                        }
                        .foregroundStyle(Color.purple)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(editandoDatos ? L.t("Listo", "Done") : L.t("Editar datos personales", "Edit personal details"))
                    .accessibilityHint(editandoDatos
                               ? L.t("Doble toque para guardar los cambios", "Double tap to save your changes")
                               : L.t("Doble toque para editar tu teléfono y correo personal", "Double tap to edit your phone and personal email"))
                }

                // ── Cuadro teléfono ──
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.appPrimary.opacity(0.12)).frame(width: 36, height: 36)
                        Image(systemName: "phone.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.appPrimary)
                    }
                    .accessibilityHidden(true)
                    if editandoDatos {
                        TextField("999 888 777", text: Binding(
                            get: { telefonoInput },
                            set: { newValue in
                                let filtrado = newValue.filter { $0.isNumber }
                                telefonoInput = String(filtrado.prefix(9))
                            }
                        ))
                        .font(.bodyMd)
                        .foregroundStyle(.onSurface)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel(L.t("Teléfono, 9 dígitos", "Phone, 9 digits"))
                    } else {
                        Text(telefono)
                            .font(.bodyMd)
                            .foregroundStyle(.onSurface)
                        Spacer()
                    }
                }
                .padding(14)
                .background(boxShape.fill(Color.surfaceContainerLow))
                .overlay(boxShape.stroke(Color.outlineVariant.opacity(editandoDatos ? 0.6 : 0.25), lineWidth: 1))
                .accessibilityElement(children: editandoDatos ? .contain : .combine)
                .accessibilityLabel(editandoDatos ? L.t("Teléfono", "Phone") : L.t("Teléfono: ", "Phone: ") + telefono)

                // ── Cuadro correo personal + signo de exclamación ──
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.appPrimary.opacity(0.12)).frame(width: 36, height: 36)
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.appPrimary)
                    }
                    .accessibilityHidden(true)
                    if editandoDatos {
                        TextField("correo@ejemplo.com", text: $correoPersonalInput)
                            .font(.bodyMd)
                            .foregroundStyle(.onSurface)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .accessibilityLabel(L.t("Correo personal", "Personal email"))
                    } else {
                        Text(correoPersonal)
                            .font(.bodyMd)
                            .foregroundStyle(.onSurface)
                    }
                    Spacer()
                    Button {
                        AppHaptics.impact(.light)
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showCorreoTooltip.toggle()
                        }
                    } label: {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.purple.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L.t("Información sobre el correo personal", "Information about the personal email"))
                    .accessibilityHint(L.t("Doble toque para leer para qué se usa este correo", "Double tap to read what this email is used for"))
                    .accessibilityAddTraits(.isButton)
                }
                .padding(14)
                .background(boxShape.fill(Color.surfaceContainerLow))
                .overlay(boxShape.stroke(Color.outlineVariant.opacity(editandoDatos ? 0.6 : 0.25), lineWidth: 1))
                .accessibilityElement(children: .contain)
                .accessibilityLabel(editandoDatos ? L.t("Correo personal", "Personal email") : L.t("Correo personal: ", "Personal email: ") + correoPersonal)

                // Tooltip del correo personal
                if showCorreoTooltip {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.purple)
                            .accessibilityHidden(true)
                        Text(L.t("Correo personal utilizado para recuperar contraseña del correo institucional",
                                 "Personal email used to recover your institutional email password"))
                            .font(.bodyXs)
                            .foregroundStyle(.onSurfaceVariant)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.purple.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.purple.opacity(0.25), lineWidth: 0.5)
                            )
                    )
                    .transition(.opacity)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(L.t("Correo personal utilizado para recuperar contraseña del correo institucional",
                                            "Personal email used to recover your institutional email password"))
                }

                // ── Contacto de Emergencia + editar ──
                HStack {
                    Text(L.t("Contacto de Emergencia", "Emergency contact"))
                        .font(.headlineXs)
                        .foregroundStyle(.onSurface)
                    Spacer()
                    Button {
                        AppHaptics.impact(.light)
                        toggleEdicionEmergencia()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: editandoEmergencia ? "checkmark" : "pencil")
                                .font(.system(size: 12, weight: .semibold))
                                .accessibilityHidden(true)
                            Text(editandoEmergencia ? L.t("Listo", "Done") : L.t("editar datos", "edit details"))
                                .font(.labelCapsSm)
                                .appTracking(AppTracking.wideLabel)
                        }
                        .foregroundStyle(Color.purple)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(editandoEmergencia ? L.t("Listo", "Done") : L.t("Editar contacto de emergencia", "Edit emergency contact"))
                    .accessibilityHint(editandoEmergencia
                               ? L.t("Doble toque para cerrar la edición", "Double tap to close editing")
                               : L.t("Doble toque para editar el contacto de emergencia", "Double tap to edit the emergency contact"))
                }

                if editandoEmergencia {
                    // ── Formulario inline de contacto de emergencia ──
                    VStack(alignment: .leading, spacing: 14) {
                        // Nombre del contacto
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L.t("Nombre del contacto", "Contact name"))
                                .font(.bodySmMedium)
                                .foregroundStyle(.onSurface)
                            TextField(L.t("Ingresa el nombre del contacto", "Enter the contact name"), text: Binding(
                                get: { emergenciaNombreInput },
                                set: { newValue in
                                    let filtrado = newValue.filter { $0.isLetter || $0.isWhitespace }
                                    emergenciaNombreInput = String(filtrado.prefix(20))
                                }
                            ))
                            .font(.bodyMd)
                            .foregroundStyle(.onSurface)
                            .textInputAutocapitalization(.words)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(boxShape.fill(Color.surfaceContainerLow))
                            .overlay(boxShape.stroke(Color.outlineVariant.opacity(0.6), lineWidth: 1))
                            .accessibilityLabel(L.t("Nombre del contacto, solo letras, máximo 20", "Contact name, letters only, up to 20"))
                        }

                        // Parentesco (combo box)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L.t("Parentesco", "Relationship"))
                                .font(.bodySmMedium)
                                .foregroundStyle(.onSurface)
                            Button {
                                AppHaptics.impact(.light)
                                showParentescoPicker = true
                            } label: {
                                HStack {
                                    Text(emergenciaParentescoInput.isEmpty ? L.t("Seleccionar", "Select") : emergenciaParentescoInput)
                                        .font(.bodyMd)
                                        .foregroundStyle(emergenciaParentescoInput.isEmpty ? Color.onSurfaceVariant : Color.onSurface)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.purple)
                                        .accessibilityHidden(true)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(boxShape.fill(Color.surfaceContainerLow))
                                .overlay(boxShape.stroke(Color.purple.opacity(0.5), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L.t("Parentesco del contacto", "Relationship of the contact"))
                            .accessibilityValue(emergenciaParentescoInput.isEmpty ? "No seleccionado" : emergenciaParentescoInput)
                            .accessibilityHint(L.t("Doble toque para elegir una opción de parentesco", "Double tap to choose a relationship option"))
                            .accessibilityAddTraits(.isButton)
                        }

                        // Número del contacto
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L.t("Número del Contacto", "Contact number"))
                                .font(.bodySmMedium)
                                .foregroundStyle(.onSurface)
                            TextField("99999999999", text: Binding(
                                get: { emergenciaNumeroInput },
                                set: { newValue in
                                    let filtrado = newValue.filter { $0.isNumber }
                                    emergenciaNumeroInput = String(filtrado.prefix(11))
                                }
                            ))
                            .font(.bodyMd)
                            .foregroundStyle(.onSurface)
                            .keyboardType(.numberPad)
                            .textInputAutocapitalization(.never)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(boxShape.fill(Color.surfaceContainerLow))
                            .overlay(boxShape.stroke(Color.outlineVariant.opacity(0.6), lineWidth: 1))
                            .accessibilityLabel(L.t("Número del contacto, solo números, máximo 11 dígitos", "Contact number, numbers only, up to 11 digits"))
                        }

                        // Botones Guardar / Cancelar
                        Button {
                            AppHaptics.success()
                            guardarEmergencia()
                        } label: {
                            Text(L.t("Guardar", "Save"))
                                .font(.bodyMdMedium)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.purple))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L.t("Guardar contacto de emergencia", "Save emergency contact"))
                        .accessibilityHint(L.t("Doble toque para guardar los datos del contacto", "Double tap to save the contact details"))

                        Button {
                            AppHaptics.impact(.light)
                            cancelarEmergencia()
                        } label: {
                            Text(L.t("Cancelar", "Cancel"))
                                .font(.bodyMdMedium)
                                .foregroundStyle(Color.purple)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.purple, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L.t("Cancelar edición del contacto", "Cancel contact editing"))
                        .accessibilityHint(L.t("Doble toque para descartar los cambios", "Double tap to discard the changes"))
                    }
                } else {
                    // ── Datos guardados del contacto de emergencia ──
                    VStack(spacing: 12) {
                        emergenciaFila(icon: "person.fill", titulo: L.t("Nombre", "Name"), valor: emergenciaNombre)
                        Divider().padding(.leading, 48).accessibilityHidden(true)
                        emergenciaFila(icon: "person.2.fill", titulo: L.t("Parentesco", "Relationship"), valor: emergenciaParentesco)
                        Divider().padding(.leading, 48).accessibilityHidden(true)
                        emergenciaFila(icon: "phone.fill", titulo: L.t("Número", "Number"), valor: emergenciaNumero)
                    }
                    .padding(14)
                    .background(boxShape.fill(Color.surfaceContainerLow))
                    .overlay(boxShape.stroke(Color.outlineVariant.opacity(0.25), lineWidth: 1))
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(L.t("Contacto de emergencia guardado", "Saved emergency contact"))
                    .accessibilityValue(
                        L.t("Nombre ", "Name ") + (emergenciaNombre.isEmpty ? L.t("vacío", "empty") : emergenciaNombre)
                        + L.t(", parentesco ", ", relationship ") + (emergenciaParentesco.isEmpty ? L.t("vacío", "empty") : emergenciaParentesco)
                        + L.t(", número ", ", number ") + (emergenciaNumero.isEmpty ? L.t("vacío", "empty") : emergenciaNumero))
                }

                Spacer(minLength: 24)

                // ── Cerrar sesión (solo de diseño) ──
                Button {
                    AppHaptics.warning()
                    // Solo de diseño: no ejecuta acción real
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 16, weight: .bold))
                            .accessibilityHidden(true)
                        Text(L.t("Cerrar sesión", "Log out"))
                            .font(.bodyMdMedium)
                    }
                    .foregroundStyle(.appPrimary)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.primaryFixed)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.t("Cerrar sesión", "Log out"))
                .accessibilityHint(L.t("Botón de diseño, sin acción real en este prototipo", "Design-only button, no real action in this prototype"))
            }
            .padding(20)
        }
        .onAppear {
            telefonoInput = telefono
            correoPersonalInput = correoPersonal
            emergenciaNombreInput = emergenciaNombre
            emergenciaParentescoInput = emergenciaParentesco
            emergenciaNumeroInput = emergenciaNumero
            if perfilImage == nil {
                perfilImage = ProfileImageStore.load()
            }
        }
        .confirmationDialog(L.t("Foto de perfil", "Profile photo"),
                            isPresented: $showFuenteFoto,
                            titleVisibility: .visible) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button(L.t("Tomar foto", "Take photo")) { showCamera = true }
            }
            Button(L.t("Elegir de la galería / biblioteca de fotos", "Choose from photo library")) {
                showGaleria = true
            }
            if perfilImage != nil {
                Button(L.t("Ajustar foto actual", "Adjust current photo")) { ajustarFoto = true }
            }
            Button(L.t("Cancelar", "Cancel"), role: .cancel) { }
        }
        .modifier(EditorFotoPerfilModifier(camara: $showCamera, galeria: $showGaleria, ajustar: $ajustarFoto) { img in
            perfilImage = img
        })
        .sheet(isPresented: $showParentescoPicker) {
            ParentescoPickerSheet(seleccion: $emergenciaParentescoInput)
                .seguirTemaForzado()
        }
    }

    // MARK: - Subvistas
    @ViewBuilder
    private func datoInstitucional(titulo: String, valor: String) -> some View {
        VStack(alignment: .center, spacing: 6) {
            Text(titulo)
                .font(.labelCapsSm)
                .foregroundStyle(.onSurfaceVariant)
                .appTracking(AppTracking.wideLabel)
            Text(valor)
                .font(.bodyMdMedium)
                .foregroundStyle(.onSurface)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func datoHorizontal(titulo: String, valor: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(titulo)
                    .font(.labelCapsSm)
                    .foregroundStyle(.onSurfaceVariant)
                    .appTracking(AppTracking.wideLabel)
                Text(valor)
                    .font(.bodyMdMedium)
                    .foregroundStyle(.onSurface)
            }
            Spacer()
        }
    }

    // MARK: - Acciones
    private func toggleEdicion() {
        if editandoDatos {
            telefono = telefonoInput
            correoPersonal = correoPersonalInput
            editandoDatos = false
        } else {
            telefonoInput = telefono
            correoPersonalInput = correoPersonal
            editandoDatos = true
        }
    }

    @ViewBuilder
    private func emergenciaFila(icon: String, titulo: String, valor: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.appPrimary.opacity(0.12)).frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.appPrimary)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo)
                    .font(.bodyXs)
                    .foregroundStyle(.onSurfaceVariant)
                Text(valor.isEmpty ? "—" : valor)
                    .font(.bodyMdMedium)
                    .foregroundStyle(.onSurface)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(titulo + ": " + (valor.isEmpty ? L.t("vacío", "empty") : valor))
    }

    // MARK: - Contacto de emergencia: acciones
    private func toggleEdicionEmergencia() {
        if editandoEmergencia {
            editandoEmergencia = false
        } else {
            emergenciaNombreInput = emergenciaNombre
            emergenciaParentescoInput = emergenciaParentesco
            emergenciaNumeroInput = emergenciaNumero
            editandoEmergencia = true
        }
    }

    private func guardarEmergencia() {
        emergenciaNombre = emergenciaNombreInput
        emergenciaParentesco = emergenciaParentescoInput
        emergenciaNumero = emergenciaNumeroInput
        editandoEmergencia = false
    }

    private func cancelarEmergencia() {
        emergenciaNombreInput = emergenciaNombre
        emergenciaParentescoInput = emergenciaParentesco
        emergenciaNumeroInput = emergenciaNumero
        editandoEmergencia = false
    }
}

