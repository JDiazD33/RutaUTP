//
//  Senia.swift
//  RutaUTP
//
//  Modelo del contenido del Modo Señas.
//
//  Regla de diseño: el mapeo texto -> clip se hace por CLAVE ESTABLE, nunca
//  por el texto literal. Si mañana el copy cambia de "Casa" a "Mi casa", la
//  clave "mapa.destino.casa" sigue apuntando al clip correcto. Con el texto
//  literal el feature se rompería en silencio.
//

import Foundation

// MARK: - Catálogo de textos señables

/// Registro en memoria de `clave estable -> textos por idioma`.
///
/// Se llena solo: cada llamada a `L.signable(...)` registra su clave al
/// evaluar el body de la vista. Es idempotente y barato (un diccionario).
final class CatalogoSenias {

    static let shared = CatalogoSenias()

    private let lock = NSLock()
    private var textos: [String: (es: String, en: String)] = [:]

    private init() {}

    func registrar(clave: String, es: String, en: String) {
        lock.lock()
        defer { lock.unlock() }
        textos[clave] = (es, en)
    }

    func texto(clave: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let par = textos[clave] else { return nil }
        return IdiomaManager.shared.esIngles ? par.en : par.es
    }

    var claves: [String] {
        lock.lock()
        defer { lock.unlock() }
        return textos.keys.sorted()
    }
}

// MARK: - Modelo del manifiesto

/// Una entrada del `manifest.json`: qué clip reproduce una clave.
struct Senia: Codable {
    /// Clave estable, p. ej. "mapa.destino.casa".
    let clave: String
    /// Nombre del archivo dentro de senias/clips/.
    let archivo: String
    /// Procedencia del clip. Informativo, para no perder la trazabilidad.
    let fuente: String?

    /// "placeholder" = clip de prueba, NO es una seña real.
    var esPlaceholder: Bool { (fuente ?? "placeholder") == "placeholder" }
}

/// Contenido de senias/manifest.json.
struct ManifestoSenias: Codable {
    let version: Int
    let señas: [Senia]

    private var indice: [String: Senia] {
        var d: [String: Senia] = [:]
        for s in señas { d[s.clave] = s }
        return d
    }

    func senia(para clave: String) -> Senia? {
        indice[clave]
    }
}

// MARK: - Estado de resolución

/// Resultado de intentar reproducir una seña.
enum EstadoSenia {
    /// Hay clip listo para reproducir.
    case clip(URL, senia: Senia)
    /// No hay clip: la clave no está en el manifiesto o el archivo no existe.
    case pendiente(motivo: String)

    var descripcion: String {
        switch self {
        case .clip(_, let s):    return "clip: \(s.archivo)"
        case .pendiente(let m):  return "pendiente: \(m)"
        }
    }
}
