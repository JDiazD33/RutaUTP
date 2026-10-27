//
//  EditorFotoPerfilModifier.swift
//  RutaUTP
//
//  Flujo compartido para elegir y ajustar la foto de perfil.
//

import SwiftUI
import UIKit

/// Flujo común para la foto que comparten Perfil, menú y carné digital.
struct EditorFotoPerfilModifier: ViewModifier {
    @Binding var camara: Bool
    @Binding var galeria: Bool
    @Binding var ajustar: Bool
    let onGuardar: (UIImage) -> Void
    @State private var pendiente: UIImage?
    @State private var editor: FotoParaEncuadrar?
    @State private var selectorCerrado = true
    @State private var errorGuardado = false
    @State private var guardando = false

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $camara, onDismiss: cerrarSelector) {
                ImagePicker(sourceType: .camera, allowsEditing: false, onImagePicked: recibir)
                    .onAppear { selectorCerrado = false }
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $galeria, onDismiss: cerrarSelector) {
                GaleriaPicker(onImagePicked: recibir)
                    .onAppear { selectorCerrado = false }
            }
            .task(id: ajustar) {
                guard ajustar else { return }
                let foto = await ProfileImageStore.load()
                guard !Task.isCancelled, ajustar else { return }
                ajustar = false
                if let foto { editor = FotoParaEncuadrar(image: foto) }
            }
            .fullScreenCover(item: $editor) { seleccion in
                EncuadreFotoView(image: seleccion.image, esPerfil: true) { imagen in
                    guard !guardando else { return }
                    guardando = true
                    Task { @MainActor in
                        let saved = await ProfileImageStore.save(imagen)
                        guardando = false
                        guard editor?.id == seleccion.id else { return }
                        if saved {
                            onGuardar(imagen)
                            editor = nil
                        } else {
                            errorGuardado = true
                        }
                    }
                }
                .disabled(guardando)
                .interactiveDismissDisabled(guardando)
                .overlay {
                    if guardando {
                        ProgressView(L.t("Guardando foto…", "Saving photo…"))
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .alert(L.t("No se pudo guardar la foto", "Couldn't save photo"), isPresented: $errorGuardado) {
                    Button(L.t("Aceptar", "OK"), role: .cancel) {}
                } message: {
                    Text(L.t("Comprueba el espacio disponible e inténtalo de nuevo. Tu foto anterior se conserva.", "Check available storage and try again. Your previous photo is preserved."))
                }
            }
    }

    private func recibir(_ imagen: UIImage) {
        pendiente = imagen
        if selectorCerrado { presentar() }
    }

    private func cerrarSelector() {
        selectorCerrado = true
        presentar()
    }

    private func presentar() {
        guard let imagen = pendiente else { return }
        pendiente = nil
        editor = FotoParaEncuadrar(image: imagen)
    }
}
