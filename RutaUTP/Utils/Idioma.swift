//
//  Idioma.swift
//  RutaUTP
//
//  Soporte ES/EN sin String Catalogs: gestor persistido + helper L.t().
//  El cambio de idioma reconstruye el árbol de vistas (RootView usa
//  .id(codigo)), así que todas las pantallas re-renderizan al instante.
//

import Foundation
import Combine

final class IdiomaManager: ObservableObject {
    static let shared = IdiomaManager()

    @Published var codigo: String {
        didSet { UserDefaults.standard.set(codigo, forKey: "idioma.app") }
    }

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--idioma") {
            // Para pruebas visuales: --idioma en|es
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "--idioma"), i + 1 < args.count {
                codigo = args[i + 1] == "en" ? "en" : "es"
                return
            }
        }
        #endif
        codigo = UserDefaults.standard.string(forKey: "idioma.app") ?? "es"
    }

    var esIngles: Bool { codigo == "en" }
    var etiqueta: String { esIngles ? "EN" : "ES" }

    func alternar() {
        objectWillChange.send()
        codigo = esIngles ? "es" : "en"
    }
}

/// Traductor de una línea: L.t("Español", "English")
enum L {
    static var esIngles: Bool { IdiomaManager.shared.esIngles }

    static func t(_ es: String, _ en: String) -> String {
        esIngles ? en : es
    }
}
