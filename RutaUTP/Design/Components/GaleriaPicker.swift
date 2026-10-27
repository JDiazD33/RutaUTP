//
//  GaleriaPicker.swift
//  RutaUTP
//
//  Selector de fotos del sistema sin pedir permiso de fotos.
//

import SwiftUI
import PhotosUI
import UIKit

// MARK: - Galería (PHPicker, sin permiso de fotos)

struct GaleriaPicker: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: GaleriaPicker
        init(_ parent: GaleriaPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // Conservar el callback antes de cerrar el sheet: el coordinador
            // puede liberarse mientras Fotos carga la imagen seleccionada.
            let onImagePicked = parent.onImagePicked
            parent.dismiss()
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { objeto, _ in
                guard let imagen = objeto as? UIImage else { return }
                DispatchQueue.main.async { onImagePicked(imagen) }
            }
        }
    }
}
