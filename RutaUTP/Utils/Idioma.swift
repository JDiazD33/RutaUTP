//
//  Idioma.swift
//  RutaUTP
//
//  Idiomas de la app: gestor persistido + catálogo local de traducciones.
//  No hace falta reconstruir el árbol al cambiar de idioma: leer el idioma
//  durante el `body` registra la dependencia (ver la nota de `IdiomaManager`)
//  y la vista se vuelve a evaluar sola. Aquí hubo un `.id(codigo)` en
//  RootView; se quitó justamente porque era innecesario y además recreaba el
//  AppRouter, devolviendo al usuario a Bienvenida al cambiar de idioma.
//

import Foundation
import Observation

/// Códigos persistidos estables. Español sigue siendo el idioma predeterminado.
enum IdiomaApp: String, CaseIterable, Identifiable {
    case espanol = "es"
    case ingles = "en"
    case frances = "fr"
    case portuguesBrasil = "pt-BR"
    case aleman = "de"
    case chinoSimplificado = "zh-Hans"

    var id: String { rawValue }

    /// Los nombres nativos permiten reconocer una opción desde cualquier idioma.
    var nombreNativo: String {
        switch self {
        case .espanol: return "Español"
        case .ingles: return "English"
        case .frances: return "Français"
        case .portuguesBrasil: return "Português (Brasil)"
        case .aleman: return "Deutsch"
        case .chinoSimplificado: return "中文（简体）"
        }
    }

    var etiqueta: String {
        switch self {
        case .espanol: return "ES"
        case .ingles: return "EN"
        case .frances: return "FR"
        case .portuguesBrasil: return "PT-BR"
        case .aleman: return "DE"
        case .chinoSimplificado: return "中文"
        }
    }

    var locale: Locale { Locale(identifier: codigoRegional) }
    var codigoRegional: String {
        switch self {
        case .espanol: return "es-PE"
        case .ingles: return "en-US"
        case .frances: return "fr-FR"
        case .portuguesBrasil: return "pt-BR"
        case .aleman: return "de-DE"
        case .chinoSimplificado: return "zh-Hans-CN"
        }
    }
}

/// Gestor del idioma activo, compartido también con los servicios.
///
/// Usa Observation a propósito. Con el framework
/// Observation, leer `codigo` o `esIngles` mientras se evalúa el `body` de una
/// vista registra la dependencia automáticamente — aunque el acceso venga de
/// `L.t()`, que es una función estática, o de este singleton. Esa es la pieza
/// que permite que el texto se actualice solo al cambiar de idioma, sin
/// reconstruir el árbol de vistas con `.id()`.
/// Las lecturas de traducción pueden venir de servicios; el valor queda bajo
/// candado y las elecciones de la interfaz se publican desde MainActor.
final class IdiomaManager: Observable {
    static let shared = IdiomaManager()
    private let defaults: UserDefaults
    private let observacion = ObservationRegistrar()
    private let candado = NSLock()
    private var valor: String

    var codigo: String {
        observacion.access(self, keyPath: \.codigo)
        candado.lock()
        defer { candado.unlock() }
        return valor
    }

    init(defaults: UserDefaults = .standard,
         argumentos: [String] = ProcessInfo.processInfo.arguments) {
        self.defaults = defaults
        #if DEBUG
        if argumentos.contains("--idioma") {
            // Para comprobaciones visuales autorizadas: --idioma <código>.
            if let i = argumentos.firstIndex(of: "--idioma"), i + 1 < argumentos.count {
                valor = IdiomaApp(rawValue: argumentos[i + 1])?.rawValue ?? "es"
                return
            }
        }
        #endif
        let guardado = defaults.string(forKey: "idioma.app")
        valor = guardado.flatMap(IdiomaApp.init(rawValue:))?.rawValue ?? "es"
    }

    var esIngles: Bool { codigo == "en" }
    var idioma: IdiomaApp { IdiomaApp(rawValue: codigo) ?? .espanol }
    var etiqueta: String { idioma.etiqueta }

    @MainActor
    func alternar() {
        let opciones = IdiomaApp.allCases
        let indice = opciones.firstIndex(of: idioma) ?? 0
        seleccionar(codigo: opciones[(indice + 1) % opciones.count].rawValue)
    }

    @MainActor
    func seleccionar(codigo: String) {
        guard IdiomaApp(rawValue: codigo) != nil else { return }
        guard self.codigo != codigo else {
            defaults.set(codigo, forKey: "idioma.app")
            return
        }
        observacion.withMutation(of: self, keyPath: \.codigo) {
            candado.lock()
            valor = codigo
            candado.unlock()
            defaults.set(codigo, forKey: "idioma.app")
        }
    }
}

/// Traductor de una línea: L.t("Español", "English")
enum L {
    static var esIngles: Bool { IdiomaManager.shared.esIngles }

    static func t(_ es: String, _ en: String) -> String {
        CatalogoTraducciones.texto(es: es, en: en, idioma: IdiomaManager.shared.idioma)
    }

    /// Las plantillas mantienen {0}, {1}… para que cada idioma ordene sus datos.
    static func f(_ es: String, _ en: String, _ argumentos: [String]) -> String {
        CatalogoTraducciones.formatear(t(es, en), argumentos: argumentos)
    }

    /// Reevalúa avisos que un modelo creó antes de cambiar el idioma.
    /// Solo se usa con textos de la app, nunca con datos escritos por el usuario.
    static func aviso(_ texto: String) -> String {
        CatalogoTraducciones.relocalizar(texto, idioma: IdiomaManager.shared.idioma)
    }

    static func tipoVehiculo(_ tipo: String) -> String {
        switch tipo {
        case "Bus", "Micro": return t("Micro", "Bus")
        case "Combi": return t("Combi", "Minibus")
        default: return tipo
        }
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
        return t(es, en)
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
        IdiomaManager.shared.idioma.locale
    }

    /// Formateador cacheado para un patrón y un locale concretos.
    static func formateador(patron: String, locale: Locale) -> DateFormatter {
        let clave = "\(patron)|\(locale.identifier)"
        candado.lock()
        defer { candado.unlock() }
        if let existente = cache[clave] { return existente }
        let nuevo = DateFormatter()
        nuevo.locale = locale
        nuevo.dateFormat = patron
        cache[clave] = nuevo
        return nuevo
    }

    /// El orden y los conectores de día/mes pertenecen al locale, no a ES/EN.
    static func fecha(_ fecha: Date, plantilla: String = "EEEE d MMMM") -> String {
        let locale = localeActivo
        let patron = DateFormatter.dateFormat(fromTemplate: plantilla, options: 0, locale: locale)
            ?? "yyyy-MM-dd"
        return formateador(patron: patron, locale: locale).string(from: fecha)
    }
}

/// Solo presentación: los importes, coordenadas y payloads conservan sus datos.
enum FormatoNumero {
    static func decimal(_ valor: Double, decimales: Int = 1) -> String {
        valor.formatted(.number.precision(.fractionLength(decimales))
            .grouping(.never).locale(FormatoFecha.localeActivo))
    }

    static func soles(_ importe: Double, decimales: Int = 2) -> String {
        "S/ " + decimal(importe, decimales: decimales)
    }
}
