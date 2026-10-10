import Foundation

/// Se prepara una vez por catálogo, incluyendo las avenidas de todos los paraderos.
struct IndiceBusquedaRuta {
    let letra: String
    private let texto: String
    private let codigo: String

    init(ruta: RutaOpcion) {
        letra = Self.compactar(ruta.letraTransporte)
        codigo = Self.compactar(ruta.linea)
        texto = Self.normalizar(([ruta.linea, ruta.letraTransporte, ruta.empresa,
                                  ruta.recorrido, ruta.paradaInicio, ruta.paradaFin]
                                 + ruta.paraderos.map(\.nombre)).joined(separator: " "))
    }

    func coincide(con consulta: ConsultaRuta) -> Bool {
        if let requerida = consulta.letra, letra != requerida { return false }
        return consulta.terminos.allSatisfy { termino in
            texto.contains(termino) || codigo.contains(Self.compactar(termino))
        }
    }

    static func normalizar(_ texto: String) -> String {
        texto.replacingOccurrences(of: "<3", with: "♥")
            .replacingOccurrences(of: "(?i)\\b(ct|m|c)[-\\s]+([0-9]+)\\b", with: "$1$2", options: .regularExpression)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_PE"))
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber && $0 != "♥" }
            .joined(separator: " ")
    }

    static func compactar(_ texto: String) -> String {
        normalizar(texto).replacingOccurrences(of: " ", with: "")
    }
}

struct ConsultaRuta {
    let letra: String?
    let terminos: [String]

    init(_ texto: String, letras: Set<String>) {
        var palabras = IndiceBusquedaRuta.normalizar(texto).split(separator: " ").map(String.init)
        var letraElegida: String?
        if let indice = palabras.firstIndex(where: { $0 == "letra" || $0 == "letter" }),
           palabras.indices.contains(indice + 1) {
            let siguientes = Array(palabras.dropFirst(indice + 1))
            let cantidad = Self.longitudLetra(siguientes, letras: letras) ?? 1
            letraElegida = siguientes.prefix(cantidad).joined()
            palabras.removeSubrange(indice...indice + cantidad)
        } else if !texto.contains("."), let cantidad = Self.longitudLetra(palabras, letras: letras) {
            letraElegida = palabras.prefix(cantidad).joined()
            palabras.removeFirst(cantidad)
        } else if palabras.count == 1, let primera = palabras.first,
                  primera.count == 1 && (primera.first?.isLetter == true || primera == "♥") {
            // «A» debe encontrar la letra A, sin coincidir con todas las avenidas.
            letraElegida = primera
            palabras.removeFirst()
        }
        letra = letraElegida
        let calificadores: Set<String> = ["linea", "line", "empresa", "company", "avenida", "av", "calle"]
        terminos = palabras.filter { !calificadores.contains($0) }
    }

    private static func longitudLetra(_ palabras: [String], letras: Set<String>) -> Int? {
        guard !palabras.isEmpty else { return nil }
        // Conserva variantes como «B ♥» y «A1», sin interpretar M-34 como letra M.
        for cantidad in stride(from: min(2, palabras.count), through: 1, by: -1) {
            if letras.contains(palabras.prefix(cantidad).joined()) { return cantidad }
        }
        return nil
    }
}
