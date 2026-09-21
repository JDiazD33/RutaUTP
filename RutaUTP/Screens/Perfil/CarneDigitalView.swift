// Carné digital de muestra. No acredita identidad, matrícula ni acceso al campus.
// Código de barras generado localmente con CoreImage, sin validación institucional.

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct CarneDigitalView: View {
    var nombre: String


    // Identificador ficticio del prototipo (no proviene de la universidad).
    private let codigoUTP = "1234567"

    // Foto de perfil: ProfileImageStore es la fuente única (drawer, perfil y carné)
    @State private var fotoPerfil: UIImage? = nil
    @State private var showPicker: Bool = false
    @State private var showGaleria = false
    @State private var showFuente = false
    @State private var ajustarFoto = false

    // Código de barras generado una sola vez al aparecer
    @State private var codigoBarras: UIImage? = nil

    // Mostaza para la tarjeta de aviso (color puntual, fuera del Design System)
    private let mostaza = Color(hex: "#DBA612")
    private let onMostaza = Color(hex: "#4A3700")

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 18) {
                encabezado

                carnet

                avisoDemostracion

                marcaUniversidad

            }
            .padding(20)
        }
        .background(Color.appSurface)
        .presentationDragIndicator(.visible)
        .onAppear {
            fotoPerfil = ProfileImageStore.load()
            if codigoBarras == nil {
                codigoBarras = generarCodigoBarras(desde: codigoUTP)
            }
        }
        .confirmationDialog(L.t("Foto de perfil", "Profile photo"), isPresented: $showFuente, titleVisibility: .visible) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button(L.t("Tomar foto", "Take photo")) { showPicker = true }
            }
            Button(L.t("Elegir de la galería", "Choose from photo library")) { showGaleria = true }
            if fotoPerfil != nil {
                Button(L.t("Ajustar foto actual", "Adjust current photo")) { ajustarFoto = true }
            }
            Button(L.t("Cancelar", "Cancel"), role: .cancel) {}
        }
        .modifier(EditorFotoPerfilModifier(camara: $showPicker, galeria: $showGaleria, ajustar: $ajustarFoto) { img in
            fotoPerfil = img
        })
    }

    // MARK: - Encabezado
    private var encabezado: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.appPrimary.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "person.crop.rectangle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.appPrimary)
            }
            .accessibilityHidden(true)
            Text(L.t("Carné Digital · muestra", "Digital ID · sample"))
                .font(.headlineMd)
                .foregroundStyle(.onSurface)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Carné (tarjeta principal)
    private var carnet: some View {
        VStack(spacing: 0) {
            // Foto + nombre completo
            HStack(spacing: 14) {
                fotoConCamara
                VStack(alignment: .leading, spacing: 3) {
                    Text(nombre)
                        .font(.headlineSm)
                        .foregroundStyle(.onSurface)
                    Text(L.t("Identidad no verificada", "Unverified identity"))
                        .font(.bodyXsMedium)
                        .foregroundStyle(.onSurfaceVariant)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 16)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L.t("Foto de perfil, ", "Profile photo, ") + nombre)
            .accessibilityAddTraits(.isImage)

            // Línea gris que separa el nombre del código
            Rectangle()
                .fill(Color.gray.opacity(0.45))
                .frame(height: 1)
                .accessibilityHidden(true)

            // Código UTP
            VStack(alignment: .leading, spacing: 6) {
                Text(L.t("CÓDIGO DE MUESTRA", "SAMPLE CODE"))
                    .font(.labelCapsMd)
                    .foregroundStyle(.onSurfaceVariant)
                    .appTracking(AppTracking.wideLabelMd)
                Text(codigoUTP)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.onSurface)
                    .tracking(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 14)

            // Espacio breve + segunda línea gris
            Rectangle()
                .fill(Color.gray.opacity(0.45))
                .frame(height: 1)
                .padding(.top, 16)
                .accessibilityHidden(true)

            // Indicación + código de barras
            VStack(spacing: 12) {
                Text(L.t("Código de demostración. No permite ingresar al campus.", "Demo code. It does not grant campus access."))
                    .font(.bodySm)
                    .foregroundStyle(.onSurfaceVariant)
                    .multilineTextAlignment(.center)

                if let codigoBarras {
                    Image(uiImage: codigoBarras)
                        .resizable()
                        .interpolation(.none)
                        .frame(height: 104)
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white))
                        .accessibilityLabel(L.t("Código de barras de muestra, sin validez: ", "Sample barcode, not valid: ") + codigoUTP)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .accessibilityElement(children: .contain)

            // Aviso integrado en la tarjeta, también visible en una captura.
            Text(L.t("MUESTRA · SIN VALIDEZ UNIVERSITARIA", "SAMPLE · NOT A VALID UNIVERSITY ID"))
                .font(.labelCapsSm)
                .foregroundStyle(.white)
                .appTracking(AppTracking.wideLabelMd)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Color.black)
                .padding(.top, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.surfaceContainerLowest)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.outlineVariant.opacity(0.25), lineWidth: 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L.t("Carné digital de muestra de ", "Sample digital ID of ") + "\(nombre)" + L.t(", código ficticio ", ", sample code ") + codigoUTP)
    }

    // MARK: - Foto circular con insignia de cámara morada
    private var fotoConCamara: some View {
        ZStack {
            Circle()
                .fill(Color.inversePrimary)
                .frame(width: 84, height: 84)
                .overlay(Circle().stroke(Color.white, lineWidth: 3))
            if let foto = fotoPerfil {
                Image(uiImage: foto)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 84, height: 84)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 3))
                    .accessibilityHidden(true)
            } else {
                Text(iniciales(nombre))
                    .font(.headlineMd)
                    .foregroundStyle(.appPrimary)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                AppHaptics.impact(.light)
                showFuente = true
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 28, height: 28)
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
            .accessibilityLabel(L.t("Cambiar foto del carné", "Change ID photo"))
            .accessibilityHint(L.t("Doble toque para capturar o elegir tu foto", "Double tap to capture or choose your photo"))
        }
    }

    // MARK: - Aviso de demostración
    private var avisoDemostracion: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("⚠️")
                .font(.system(size: 24))
                .accessibilityHidden(true)
            Text(L.t(
                "Este carné es una muestra con un código ficticio. El nombre y la foto no verifican tu identidad ni tu matrícula. No es una credencial emitida por la universidad y no permite ingresar al campus.",
                "This ID is a sample with a fictional code. The name and photo do not verify your identity or enrollment. It is not a university-issued credential and does not grant campus access."
            ))
            .font(.bodyXsMedium)
            .foregroundStyle(onMostaza)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(mostaza)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L.t(
            "Carné de muestra con código ficticio. No verifica identidad ni matrícula, no está emitido por la universidad y no permite ingresar al campus.",
            "Sample ID with a fictional code. It does not verify identity or enrollment, is not university-issued and does not grant campus access."
        ))
    }

    // MARK: - Pie: marca de la universidad

    /// Marca de la universidad al pie del carné.
    ///
    /// El recurso es la marca de tres cuadros (U · T · P) y **no** lleva
    /// `template-rendering-intent`: con «template» se dibujaba como una silueta
    /// plana y las letras blancas desaparecían dentro de una mancha oscura. Por
    /// eso tampoco se usa ya `foregroundStyle`: el logo trae su propio color.
    ///
    /// Va sobre placa blanca porque la marca es oscura sobre claro; así se lee
    /// igual en tema claro y en oscuro, donde el carné es negro. Como el archivo
    /// no trae texto, el nombre lo pone la interfaz debajo.
    private var marcaUniversidad: some View {
        VStack(spacing: 12) {
            Image("UTPLogo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 150)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white)
                )
                .accessibilityHidden(true)

            Text(L.t("UNIVERSIDAD TECNOLÓGICA DEL PERÚ",
                     "UNIVERSIDAD TECNOLÓGICA DEL PERÚ"))
                .font(.labelCapsSm)
                .foregroundStyle(.onSurface)
                .appTracking(AppTracking.wideLabel)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.surfaceContainerLowest)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.outlineVariant.opacity(0.3), lineWidth: 0.5)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L.t("Universidad Tecnológica del Perú",
                                "Universidad Tecnológica del Perú"))
    }

    // MARK: - Helpers
    private func iniciales(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first }.map { String($0) }.joined()
    }

    /// Genera un código de barras Code 128 con CoreImage (barras negras, fondo blanco).
    private func generarCodigoBarras(desde texto: String) -> UIImage? {
        let filtro = CIFilter.code128BarcodeGenerator()
        filtro.message = Data(texto.utf8)
        filtro.quietSpace = 10
        guard let salida = filtro.outputImage else { return nil }
        // Escala x4 para barras nítidas al escanear
        let escalada = salida.transformed(by: CGAffineTransform(scaleX: 4, y: 4))
        let contexto = CIContext()
        guard let cg = contexto.createCGImage(escalada, from: escalada.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

#Preview {
    CarneDigitalView(nombre: "Joaquín Díaz")
}
