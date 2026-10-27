//
//  DatosPersonalesSheet.swift
//  RutaUTP
//
//  Datos personales del estudiante: ficha de solo lectura, datos
//  editables y contacto de emergencia.
//  
//  El contacto usa el mismo editor y las mismas claves que Seguridad.

import SwiftUI
import UIKit
// MARK: - 7. DATOS PERSONALES SHEET
struct DatosPersonalesSheet: View {
    // Datos institucionales (solo lectura)
    static let nombrePersona = "Joaquín Díaz"
    static var inicialesPersona: String {
        nombrePersona.split(whereSeparator: { $0.isWhitespace }).prefix(2)
            .map { String($0.prefix(1)) }.joined()
    }
    private let nombresCompletos = DatosPersonalesSheet.nombrePersona
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
    @AppStorage(ContactoEmergencia.claveNombre) private var emergenciaNombre: String = ""
    @AppStorage(ContactoEmergencia.claveParentesco) private var emergenciaParentesco: String = ""
    @AppStorage(ContactoEmergencia.claveNumero) private var emergenciaNumero: String = ""

    // Edición datos personales
    @State private var editandoDatos: Bool = false
    @State private var telefonoInput: String = ""
    @State private var correoPersonalInput: String = ""

    // Foto de perfil
    @State private var perfilImage: UIImage? = nil
    @State private var showFuenteFoto = false
    @State private var showGaleria = false
    @State private var ajustarFoto = false
    @State private var showCamera: Bool = false

    @State private var mostrarContacto = false
    @AppStorage(ContactoEmergencia.claveAlternativo) private var emergenciaAlternativo = ""

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }
    private var superficie: Color { Color(uiColor: .secondarySystemGroupedBackground) }

    private let boxShape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    /// Texto del parentesco listo para mostrar. `nil` si aún no hay selección.
    ///
    /// Lo guardado es el `rawValue` de `Parentesco`, que es español **a
    /// propósito**: es una clave estable y traducirlo invalidaría el dato ya
    /// guardado en `emergencia_parentesco`. Para mostrar hay que pasar por
    /// `label`, que sí traduce. Sin esto, con la app en inglés se leía
    /// "Padre/Madre" en lugar de "Parent".
    private var parentescoGuardadoTexto: String? {
        textoParentesco(emergenciaParentesco)
    }

    /// Conserva valores antiguos desconocidos y distingue la ausencia de selección.
    private func textoParentesco(_ valor: String) -> String? {
        guard !valor.isEmpty else { return nil }
        return Parentesco(rawValue: valor)?.label ?? valor
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                SheetHeader(icon: "person.crop.circle.fill", iconColor: .appAccent, title: L.t("Datos Personales", "Personal details"))

                // ── Cabecera: foto + nombres + carrera + correo institucional ──
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [Color.primaryFill, Color.primaryContainer, Color.primaryGradientEnd],
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
                                    .foregroundStyle(.onPrimaryFill)
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
                                        .fill(Color.surfaceContainerLow)
                                        .frame(width: 26, height: 26)
                                        .overlay(Circle().stroke(Color.appAccent, lineWidth: 1.5))
                                        .accessibilityHidden(true)
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Color.appAccent)
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
                            .foregroundStyle(.appAccent)
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

                datosPersonales

                // El contacto se edita con el mismo formulario que en Seguridad.
                HStack {
                    Text(L.t("Contacto de Emergencia", "Emergency contact"))
                        .font(.headlineXs).foregroundStyle(Color.onSurface)
                    Spacer()
                    Button {
                        AppHaptics.impact(.light)
                        mostrarContacto = true
                    } label: {
                        Label(L.t("Editar", "Edit"), systemImage: "pencil")
                            .font(.bodySmMedium).foregroundStyle(Color.onSurface)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L.t("Editar contacto de emergencia", "Edit emergency contact"))
                }
                tarjetaEmergenciaGuardada

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
                    .foregroundStyle(.appAccent)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.surfaceContainerLow)
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
        }
        .task {
            guard perfilImage == nil else { return }
            let foto = await ProfileImageStore.load()
            guard !Task.isCancelled, perfilImage == nil else { return }
            perfilImage = foto
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
        .sheet(isPresented: $editandoDatos) {
            EditorDatosPersonales(telefono: $telefonoInput, correo: $correoPersonalInput) { numero, correo in
                telefono = numero
                correoPersonal = correo
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .seguirTemaForzado()
        }
        .sheet(isPresented: $mostrarContacto) {
            ContactoEmergenciaSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Subvistas
    private var datosPersonales: some View {
        VStack(alignment: .leading, spacing: 12) {
            let layout = dynamicTypeSize >= .xxxLarge
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            layout {
                Text(L.t("Mis datos personales", "My personal details"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.onSurface)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    AppHaptics.impact(.light)
                    toggleEdicion()
                } label: {
                    Label(L.t("Editar datos", "Edit details"), systemImage: "pencil")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(acento)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.t("Editar datos personales", "Edit personal details"))
            }

            VStack(spacing: 0) {
                datoPersonal(icono: "phone", titulo: L.t("Teléfono", "Phone"), valor: telefono)
                Divider().padding(.leading, 60)
                datoPersonal(icono: "envelope", titulo: L.t("Correo personal", "Personal email"), valor: correoPersonal)
            }
            .background(superficie, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            Text(L.t("Estos datos se guardan en este dispositivo.", "These details are saved on this device."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func datoPersonal(icono: String, titulo: String, valor: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icono)
                .font(.body)
                .foregroundStyle(acento)
                .frame(minWidth: 24, minHeight: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(titulo).font(.caption).foregroundStyle(.secondary)
                Text(valor.isEmpty ? "—" : valor)
                    .font(.body).foregroundStyle(Color.onSurface)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .accessibilityElement(children: .combine)
    }

    private var tarjetaEmergenciaGuardada: some View {
        VStack(spacing: 12) {
            emergenciaFila(icon: "person.fill", titulo: L.t("Nombre", "Name"), valor: emergenciaNombre)
            Divider().padding(.leading, 48).accessibilityHidden(true)
            emergenciaFila(icon: "person.2.fill", titulo: L.t("Parentesco", "Relationship"), valor: parentescoGuardadoTexto ?? "")
            Divider().padding(.leading, 48).accessibilityHidden(true)
            emergenciaFila(icon: "phone.fill", titulo: L.t("Número", "Number"), valor: emergenciaNumero)
            if !emergenciaAlternativo.isEmpty {
                Divider().padding(.leading, 48).accessibilityHidden(true)
                emergenciaFila(icon: "phone.arrow.triangle.2.circlepath",
                               titulo: L.t("Teléfono alternativo", "Alternate phone"), valor: emergenciaAlternativo)
            }
        }
        .padding(14)
        .background(boxShape.fill(Color.surfaceContainerLow))
        .overlay(boxShape.stroke(Color.outlineVariant.opacity(0.25), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L.t("Contacto de emergencia guardado", "Saved emergency contact"))
        .accessibilityValue(valorAccesibleEmergencia)
    }

    private var valorAccesibleEmergencia: String {
        let nombre = emergenciaNombre.isEmpty ? L.t("vacío", "empty") : emergenciaNombre
        let parentesco = parentescoGuardadoTexto ?? L.t("vacío", "empty")
        let numero = emergenciaNumero.isEmpty ? L.t("vacío", "empty") : emergenciaNumero

        return L.t("Nombre ", "Name ") + nombre
            + L.t(", parentesco ", ", relationship ") + parentesco
            + L.t(", número ", ", number ") + numero
            + (emergenciaAlternativo.isEmpty ? "" : ", " + L.t("Teléfono alternativo", "Alternate phone") + ": " + emergenciaAlternativo)
    }

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
        telefonoInput = telefono
        correoPersonalInput = correoPersonal
        editandoDatos = true
    }

    @ViewBuilder
    private func emergenciaFila(icon: String, titulo: String, valor: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.appPrimary.opacity(0.12)).frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.appAccent)
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

}
