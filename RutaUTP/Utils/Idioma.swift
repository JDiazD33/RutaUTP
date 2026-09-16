//
//  Idioma.swift
//  RutaUTP
//
//  Soporte ES/EN sin String Catalogs: gestor persistido + helper L.t().
//  El cambio de idioma reconstruye el árbol de vistas (RootView usa
//  .id(codigo)), así que todas las pantallas re-renderizan al instante.
//

import Foundation
import Observation

/// Gestor del idioma activo (ES/EN).
///
/// Es `@Observable` y NO `ObservableObject` a propósito. Con el framework
/// Observation, leer `codigo` o `esIngles` mientras se evalúa el `body` de una
/// vista registra la dependencia automáticamente — aunque el acceso venga de
/// `L.t()`, que es una función estática, o de este singleton. Esa es la pieza
/// que permite que el texto se actualice solo al cambiar de idioma, sin
/// reconstruir el árbol de vistas con `.id()`.
@Observable
final class IdiomaManager {
    static let shared = IdiomaManager()

    var codigo: String {
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
        codigo = esIngles ? "es" : "en"
    }
}

/// Traductor de una línea: L.t("Español", "English")
enum L {
    static var esIngles: Bool { IdiomaManager.shared.esIngles }

    static func t(_ es: String, _ en: String) -> String {
        esIngles ? en : es
    }

    /// Igual que `t()`, pero marca el texto como **señable**.
    ///
    /// La `clave` es un identificador estable (p. ej. "mapa.destino.casa"),
    /// NO el texto literal. Así el clip sobrevive a los cambios de copy.
    ///
    /// Efecto secundario: registra la clave en `CatalogoSenias` para que el
    /// overlay pueda mostrar la palabra que se está señando.
    static func signable(_ clave: String, _ es: String, _ en: String) -> String {
        CatalogoSenias.shared.registrar(clave: clave, es: es, en: en)
        return esIngles ? en : es
    }
}

// MARK: - Formateadores de fecha compartidos
//
// Antes cada sitio que mostraba o interpretaba una fecha construía su propio
// `DateFormatter`, y varios lo hacían dentro de un cuerpo de vista: uno por
// render. Crear un `DateFormatter` es caro (resuelve patrón, locale y
// calendario), y estos sitios están en rutas de dibujo.
//
// `DateFormatter` es thread-safe desde iOS 7, así que se pueden compartir. Los
// de esta caché no se mutan después de crearse.
enum FormatoFecha {

    private static let candado = NSLock()
    private static var cache: [String: DateFormatter] = [:]

    /// Locale del idioma activo de la app.
    static var localeActivo: Locale {
        Locale(identifier: IdiomaManager.shared.esIngles ? "en_US" : "es_PE")
    }

    /// Formateador cacheado para un patrón y un locale concretos.
    static func formateador(patron: String, locale: Locale) -> DateFormatter {
        let clave = "\(patron)|\(locale.identifier)"
        candado.lock()
        defer { candado.unlock() }
        if let existente = cache[clave] { return existente }
        let nuevo = DateFormatter()
        nuevo.dateFormat = patron
        nuevo.locale = locale
        cache[clave] = nuevo
        return nuevo
    }
}
