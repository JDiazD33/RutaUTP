import Foundation

/// Catálogo inmutable empaquetado: no consulta red ni traduce durante el viaje.
enum CatalogoTraducciones {
    private static let textos: [String: [String: String]] = {
        guard let url = Bundle.main.url(forResource: "Traducciones", withExtension: "json"),
              let datos = try? Data(contentsOf: url),
              let contenido = try? JSONDecoder().decode([String: [String: String]].self, from: datos) else {
            #if DEBUG
            assertionFailure("Falta el catálogo local de traducciones")
            #endif
            return [:]
        }
        return contenido
    }()

    static func texto(es: String, en: String, idioma: IdiomaApp) -> String {
        switch idioma {
        case .espanol: return es
        case .ingles: return en
        default: return textos[es]?[idioma.rawValue] ?? es
        }
    }

    private static let marcadores = try! NSRegularExpression(pattern: #"\{([0-9]+)\}"#)

    static func formatear(_ plantilla: String, argumentos: [String]) -> String {
        let resultado = NSMutableString(string: plantilla)
        // Sustituir desde el final evita reinterpretar marcadores dentro de un dato.
        for coincidencia in marcadores.matches(in: plantilla, range: NSRange(plantilla.startIndex..., in: plantilla)).reversed() {
            guard let rango = Range(coincidencia.range(at: 1), in: plantilla),
                  let indice = Int(plantilla[rango]), argumentos.indices.contains(indice) else { continue }
            resultado.replaceCharacters(in: coincidencia.range, with: argumentos[indice])
        }
        return resultado as String
    }

    private static let originales: [String: String] = {
        var indice: [String: String] = [:]
        for es in textos.keys.sorted() {
            guard !es.contains("{0}") else { continue }
            indice[es] = es
            for texto in textos[es]?.values ?? Dictionary<String, String>().values {
                if indice[texto] == nil { indice[texto] = es }
            }
        }
        return indice
    }()

    private struct Plantilla {
        let es: String
        let patron: NSRegularExpression
        let indices: [Int]
    }

    /// Solo los avisos ya materializados necesitan búsqueda inversa.
    /// Se prepara una vez y no participa en las traducciones normales de vistas.
    private static let plantillas: [Plantilla] = {
        var resultado: [Plantilla] = []
        for es in textos.keys.sorted() where es.contains("{0}") {
            let versiones = Set([es] + Array(textos[es]?.values ?? Dictionary<String, String>().values))
            for version in versiones {
                let coincidencias = marcadores.matches(in: version, range: NSRange(version.startIndex..., in: version))
                var patron = "^", indices: [Int] = [], inicio = version.startIndex
                for coincidencia in coincidencias {
                    guard let rango = Range(coincidencia.range, in: version),
                          let numero = Range(coincidencia.range(at: 1), in: version),
                          let indice = Int(version[numero]) else { continue }
                    patron += NSRegularExpression.escapedPattern(for: String(version[inicio..<rango.lowerBound])) + "(.*?)"
                    indices.append(indice)
                    inicio = rango.upperBound
                }
                patron += NSRegularExpression.escapedPattern(for: String(version[inicio...])) + "$"
                if let expresion = try? NSRegularExpression(pattern: patron, options: [.dotMatchesLineSeparators]) {
                    resultado.append(Plantilla(es: es, patron: expresion, indices: indices))
                }
            }
        }
        return resultado
    }()

    static func relocalizar(_ valor: String, idioma: IdiomaApp) -> String {
        if let es = originales[valor] {
            return texto(es: es, en: textos[es]?["en"] ?? es, idioma: idioma)
        }
        for plantilla in plantillas {
            guard let coincidencia = plantilla.patron.firstMatch(in: valor, range: NSRange(valor.startIndex..., in: valor)),
                  let maximo = plantilla.indices.max() else { continue }
            var argumentos = Array(repeating: "", count: maximo + 1)
            for (posicion, indice) in plantilla.indices.enumerated() {
                if let rango = Range(coincidencia.range(at: posicion + 1), in: valor) {
                    argumentos[indice] = String(valor[rango])
                }
            }
            return formatear(texto(es: plantilla.es, en: textos[plantilla.es]?["en"] ?? plantilla.es, idioma: idioma), argumentos: argumentos)
        }
        return valor
    }
}
