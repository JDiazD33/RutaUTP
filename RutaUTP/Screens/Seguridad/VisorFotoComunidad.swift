//
//  VisorFotoComunidad.swift
//  RutaUTP
//
//  Foto de una publicación de Comunidad a pantalla completa. Reutiliza el
//  visor ampliable del carné (pellizco, doble toque y acciones de VoiceOver)
//  y conserva la atribución y la licencia de la foto de archivo.
//

import SwiftUI
import UIKit

struct VisorFotoComunidad: View {
    let foto: FotoComunidad
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let imagen = UIImage(named: foto.asset) {
                    VisorFotoCarnet(
                        imagen: imagen,
                        etiquetaAccesible: L.t("Foto de archivo: ", "Archive photo: ") + foto.lugar,
                        descripcionAccesible: foto.descripcionLocalizada,
                        textoVerCompleto: L.t("Ver completa", "Fit photo"),
                        pistaVerCompleto: L.t("Vuelve a mostrar la foto entera en pantalla",
                                              "Shows the whole photo on screen again"))
                } else {
                    ContentUnavailableView(L.t("Foto no disponible", "Photo unavailable"),
                                           systemImage: "photo")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { pie }
            .navigationTitle(foto.lugar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Cerrar", "Close")) { dismiss() }
                        .accessibilityLabel(L.t("Cerrar foto", "Close photo"))
                }
            }
        }
        // Las fotos se ven sobre negro, como en Fotos; los colores semánticos
        // del pie y la barra se adaptan a ese fondo.
        .environment(\.colorScheme, .dark)
        .accessibilityAction(.escape) { dismiss() }
    }

    private var pie: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(foto.lugar, systemImage: "mappin.and.ellipse")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            if !foto.descripcionLocalizada.isEmpty {
                Text(foto.descripcionLocalizada)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text(foto.atribucion)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 20) {
                if let url = URL(string: foto.fuente) {
                    Link(L.t("Ver fuente", "View source"), destination: url)
                        .frame(minHeight: 44)
                }
                if let licenciaURL = foto.licenciaURL, let url = URL(string: licenciaURL) {
                    Link(L.t("Licencia", "License"), destination: url)
                        .frame(minHeight: 44)
                }
            }
            .font(.footnote.weight(.medium))
            .tint(Color.primaryFixed)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Transición de zoom (iOS 18)

/// Marca la miniatura como origen de la transición de zoom del visor.
struct OrigenZoomFoto: ViewModifier {
    let id: String
    let espacio: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.matchedTransitionSource(id: id, in: espacio)
        } else {
            content
        }
    }
}

/// La hoja del visor crece desde la miniatura marcada con `OrigenZoomFoto`.
/// Con Reducir movimiento se conserva la presentación estándar.
struct DestinoZoomFoto: ViewModifier {
    let id: String
    let espacio: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reducirMovimiento

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), !reducirMovimiento {
            content.navigationTransition(.zoom(sourceID: id, in: espacio))
        } else {
            content
        }
    }
}
