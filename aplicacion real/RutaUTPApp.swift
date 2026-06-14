//
//  RutaUTPApp.swift
//  RutaUTP
//
//  Punto de entrada de la aplicación.
//  Esta versión reemplaza el WKWebView del prototipo HTML por SwiftUI 100% nativo.
//

import SwiftUI

@main
struct RutaUTPApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
                .tint(.appPrimary)
                .background(Color.appBackground.ignoresSafeArea())
        }
    }
}
