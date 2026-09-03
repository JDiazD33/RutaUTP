//
//  RutaUTPApp.swift
//  RutaUTP
//
//  Punto de entrada de la aplicación.
//  - Modo oscuro/claro persistido con @AppStorage; se APLICA en RootView
//    (@AppStorage dentro del App no siempre invalida la escena).
//  - Idioma ES/EN vía IdiomaManager; cambiarlo reconstruye el árbol
//    (.id(idioma.codigo)) para que todas las vistas se re-rendericen.
//

import SwiftUI

@main
struct RutaUTPApp: App {
    @StateObject private var idioma = IdiomaManager.shared

    var body: some Scene {
        WindowGroup {
            // Cambio de idioma suave: cross-fade (+ sutil escala) en vez
            // del reemplazo seco del árbol de vistas.
            ZStack {
                RootView()
                    .id(idioma.codigo)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
            .animation(.easeInOut(duration: 0.35), value: idioma.codigo)
            // El tema claro/oscuro se aplica en RootView (ver comentario ahí):
            // @AppStorage dentro del App no invalida la escena de forma
            // confiable y dejaba el tema "pegado" al volver a claro.
            .tint(.appPrimary)
            .background(Color.appBackground.ignoresSafeArea())
            .environmentObject(idioma)
        }
    }
}
