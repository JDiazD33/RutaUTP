//
//  RutaUTPApp.swift
//  RutaUTP
//
//  Punto de entrada de la aplicación.
//  El modo oscuro/claro se persiste con @AppStorage y se aplica a toda
//  la app via preferredColorScheme.
//

import SwiftUI

@main
struct RutaUTPApp: App {
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(isDarkMode ? .dark : .light)
                .tint(.appPrimary)
                .background(Color.appBackground.ignoresSafeArea())
        }
    }
}
