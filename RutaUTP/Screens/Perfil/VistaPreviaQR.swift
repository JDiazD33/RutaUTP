// VistaPreviaQR.swift
// Separado por responsabilidad; conserva el comportamiento existente.

import SwiftUI
import AVFoundation
import UIKit

// MARK: - Previsualización

/// Capa de vídeo de la cámara.
///
/// `layerClass` es la propia capa de vídeo, así que se redimensiona sola con la
/// vista y no hay que recalcular el frame en cada cambio de tamaño.
struct VistaPreviaQR: UIViewRepresentable {

    let sesion: AVCaptureSession

    func makeUIView(context: Context) -> VistaPreviaQRUIView {
        let vista = VistaPreviaQRUIView()
        vista.backgroundColor = .black
        vista.capa?.videoGravity = .resizeAspectFill
        vista.capa?.session = sesion
        return vista
    }

    func updateUIView(_ vista: VistaPreviaQRUIView, context: Context) {
        vista.capa?.session = sesion
    }

    final class VistaPreviaQRUIView: UIView {

        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        /// Sin force-cast: `layerClass` lo garantiza, pero devolverlo opcional
        /// evita una conversión forzada que el compilador no puede comprobar.
        var capa: AVCaptureVideoPreviewLayer? { layer as? AVCaptureVideoPreviewLayer }
    }
}
