//
//  RutaUTPApp.swift
//  RutaUTP
//
//  Punto de entrada de la aplicación.
//  - Modo oscuro/claro persistido con @AppStorage.
//  - Idioma ES/EN vía IdiomaManager; cambiarlo reconstruye el árbol
//    (.id(idioma.codigo)) para que todas las vistas se re-rendericen.
//

import SwiftUI

@main
struct RutaUTPApp: App {
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    @StateObject private var idioma = IdiomaManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .id(idioma.codigo)
                .preferredColorScheme(isDarkMode ? .dark : .light)
                .tint(.appPrimary)
                .background(Color.appBackground.ignoresSafeArea())
                .environmentObject(idioma)
        }
    }
}
