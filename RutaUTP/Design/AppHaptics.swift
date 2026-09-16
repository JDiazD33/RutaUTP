//
//  AppHaptics.swift
//  RutaUTP
//
//  Feedback háptico compartido (no visual).
//
//  Vivía dentro de `SideDrawer.swift`, que era su única pantalla cuando se
//  escribió; hoy lo usan Mapa, Rutas, Guardado, Seguridad, Perfil, Reportar y
//  Publicar. Estaba en un archivo de pantalla por accidente histórico, no por
//  diseño: se extrae a `Design/` para que ningún módulo de UI dependa de otro
//  para algo tan transversal.
//

import UIKit

enum AppHaptics {

    /// Selección: cambio de opción en un selector o en un tab.
    ///
    /// Con VoiceOver activo el dispositivo ya vibra por defecto al mover el
    /// foco, así que se omite para no duplicar el aviso táctil.
    static func selection() {
        guard UIAccessibility.isVoiceOverRunning else {
            UISelectionFeedbackGenerator().selectionChanged()
            return
        }
    }

    /// Impacto físico. `.light` para acciones habituales, `.medium` para las
    /// que abren o cierran algo.
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    /// Operación completada con éxito (guardar, copiar, confirmar).
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Aviso: el usuario intentó algo que todavía no está disponible.
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
