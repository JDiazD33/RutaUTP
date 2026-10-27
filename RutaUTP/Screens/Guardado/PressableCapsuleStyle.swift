//
//  PressableCapsuleStyle.swift
//  RutaUTP
//
//  Estilo presionable del botón Añadir.
//
//  Vive aparte de GuardadoView porque lo usan varias pantallas.
//

import SwiftUI

// MARK: - Estilo presionable del botón Añadir
struct PressableCapsuleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}
