//
//  SeniasOverlayVentana.swift
//  RutaUTP
//
//  Ventana propia del Modo Señas: mantiene la tarjeta por encima de sheets y
//  fullScreenCovers, con toque libre fuera del miniplayer.
//

import SwiftUI
import UIKit

// MARK: - 2b. Ventana propia (por encima de sheets y covers)

/// Muestra `SeniasOverlay` en una UIWindow dedicada a nivel `.alert + 1`.
///
/// Los sheets y fullScreenCovers se presentan por encima del contenido de la
/// ventana principal, así que el overlay raíz quedaba DEBAJO y las señas
/// dentro de un sheet (ej. "Guardar lugar") no se veían. Una ventana a nivel
/// alert flota sobre todo eso. Sólo hilo principal (se llama desde
/// SeniasPresenter, que siempre se toca desde la UI).
final class SeniasOverlayVentana {

    static let shared = SeniasOverlayVentana()

    private var ventana: VentanaSenias?

    private init() {}

    /// Sincroniza la ventana con el estado del presentador.
    func actualizar(hayClave: Bool) {
        if hayClave {
            mostrar()
        } else {
            ventana?.isHidden = true
        }
    }

    private func mostrar() {
        guard let escena = escenaActiva() else { return }

        if let ventana {
            // Reubica por si hubo rotación desde la última vez.
            ventana.frame = escena.coordinateSpace.bounds
            ventana.isHidden = false
            return
        }

        let ventana = VentanaSenias(frame: escena.coordinateSpace.bounds)
        ventana.windowScene = escena
        ventana.windowLevel = .alert + 1
        ventana.backgroundColor = .clear
        // La ventana se crea tarde (primer seña visible) y ya se perdió el
        // onChange del tema: aplica el mismo escritor que usa RootView.
        ventana.overrideUserInterfaceStyle =
            UserDefaults.standard.bool(forKey: "isDarkMode") ? .dark : .light

        let controlador = UIHostingController(rootView: SeniasOverlay().ignoresSafeArea())
        controlador.view.backgroundColor = .clear
        ventana.rootViewController = controlador

        self.ventana = ventana
        ventana.isHidden = false
    }

    private func escenaActiva() -> UIWindowScene? {
        let escenas = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return escenas.first {
            $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive
        } ?? escenas.first
    }
}

/// UIWindow del miniplayer: transparente y con toque libre — los toques que
/// no caen sobre la tarjeta pasan a la app de debajo sin bloquear nada.
private final class VentanaSenias: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let vista = super.hitTest(point, with: event) else { return nil }
        // Si SwiftUI no reclama el toque, hitTest devuelve la vista raíz del
        // hosting controller (o nil): en ambos casos se deja pasar.
        return vista === rootViewController?.view ? nil : vista
    }
}
