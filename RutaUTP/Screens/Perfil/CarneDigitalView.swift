//
//  CarneDigitalView.swift
//  RutaUTP
//
//  Carné Digital: identificación estudiantil para ingresar al campus.
//  - Foto circular (misma de perfil) con insignia de cámara morada para cambiarla
//  - Nombre completo, línea divisoria, Código UTP, código de barras (Code 128)
//  - Barra negra "ÚLTIMO CICLO MATRICULADO" como decoración
//  - Tarjeta mostaza con el aviso del Reglamento de Disciplina
//
//  El código de barras se genera localmente con CoreImage (CICode128BarcodeGenerator),
//  sin dependencias externas.
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct CarneDigitalView: View {
    var nombre: String

    @Environment(\.dismiss) private var dismiss

    // Datos institucionales (mismos que en Datos Personales)
    private let codigoUTP = "1234567"

    // Foto de perfil: ProfileImageStore es la fuente única (drawer, perfil y carné)
    @State private var fotoPerfil: UIImage? = nil
    @State private var showPicker: Bool = false

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

                avisoReglamento

                Button {
                    AppHaptics.impact(.light)
                    dismiss()
                } label: {
                    Text(L.t("Cerrar", "Close"))
                        .font(.bodyMdMedium)
                        .foregroundStyle(.onSurfaceVariant)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.t("Cerrar carné digital", "Close digital ID"))
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
        .fullScreenCover(isPresented: $showPicker) {
            ImagePicker(sourceType: UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary) { img in
                ProfileImageStore.save(img)
                fotoPerfil = img
            }
        }
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
            Text(L.t("Carné Digital", "Digital ID"))
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
                    Text(L.t("Estudiante UTP", "UTP Student"))
                        .font(.bodyXsMedium)
                        .foregroundStyle(.onSurfaceVariant)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 16)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Foto de perfil, \(nombre)")
            .accessibilityAddTraits(.isImage)

            // Línea gris que separa el nombre del código
            Rectangle()
                .fill(Color.gray.opacity(0.45))
                .frame(height: 1)
                .accessibilityHidden(true)

            // Código UTP
            VStack(alignment: .leading, spacing: 6) {
                Text(L.t("CÓDIGO UTP", "UTP CODE"))
                    .font(.labelCapsMd)
                    .foregroundStyle(.onSurfaceVariant)
                    .appTracking(AppTracking.wideLabelMd)
                Text(codigoUTP)
                    .font(Font.custom(AppFontFamily.jetBrainsMono, size: 26, relativeTo: .title2).weight(.semibold))
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
                Text(L.t("Ingresa al campus mostrando este código", "Enter the campus showing this code"))
                    .font(.bodySm)
                    .foregroundStyle(.onSurfaceVariant)
                    .multilineTextAlignment(.center)

                if let codigoBarras {
                    Image(uiImage: codigoBarras)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(height: 66)
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white))
                        .accessibilityLabel("Código de barras del código \(codigoUTP)")
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .accessibilityElement(children: .contain)

            // Decoración: último ciclo matriculado
            Text(L.t("ÚLTIMO CICLO MATRICULADO", "LAST ENROLLED TERM"))
                .font(.labelCapsSm)
                .foregroundStyle(.white)
                .appTracking(AppTracking.wideLabelMd)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Color.black)
                .padding(.top, 16)
                .accessibilityHidden(true)
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
        .accessibilityLabel("Carné digital de \(nombre), código UTP \(codigoUTP)")
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
                showPicker = true
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

    // MARK: - Tarjeta mostaza: aviso del reglamento
    private var avisoReglamento: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("⚠️")
                .font(.system(size: 24))
                .accessibilityHidden(true)
            Text(L.t(
                "Recuerda que compartir tus credenciales de identificación es una infracción muy grave que conlleva la máxima sanción bajo el Reglamento de Disciplina.",
                "Remember that sharing your identification credentials is a very serious offense that carries the maximum penalty under the Disciplinary Regulations."
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
            "Aviso: compartir tus credenciales de identificación es una infracción muy grave",
            "Warning: sharing your identification credentials is a very serious offense"
        ))
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
