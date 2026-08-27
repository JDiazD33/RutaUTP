//
//  GTFSCSV.swift
//  RutaUTP
//
//  Parser CSV minimalista para los archivos .txt del feed GTFS.
//
//  - Soporta campos entre comillas con comas adentro (RFC 4180 básico).
//  - Devuelve los datos "por columna" (GTFSTable) en lugar de un array
//    de diccionarios por fila: parsear shapes.txt (53k líneas) así
//    genera 4 arrays en vez de 53k diccionarios.
//

import Foundation

// MARK: - Tabla por columnas
struct GTFSTable {
    let columns: [String: [String]]
    let rowCount: Int

    func columna(_ nombre: String) -> [String] {
        columns[nombre] ?? Array(repeating: "", count: rowCount)
    }
}

// MARK: - Parser
enum GTFSCSV {

    enum GTFSError: LocalizedError {
        case archivoNoEncontrado(String)

        var errorDescription: String? {
            switch self {
            case .archivoNoEncontrado(let nombre):
                return "No se encontró \(nombre).txt en el bundle (carpeta gtfs)."
            }
        }
    }

    static let subdirectorio = "gtfs"

    /// Lee y parsea `nombre.txt` desde la carpeta gtfs del bundle principal.
    /// Si está definida la variable de entorno GTFS_BUNDLE_DIR lee de ahí
    /// (útil para pruebas fuera del bundle iOS).
    static func tabla(_ nombre: String) throws -> GTFSTable {
        if let dir = ProcessInfo.processInfo.environment["GTFS_BUNDLE_DIR"] {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(nombre).txt")
            return parsear(texto: try String(contentsOf: url, encoding: .utf8))
        }
        guard let url = Bundle.main.url(forResource: nombre, withExtension: "txt", subdirectory: subdirectorio)
              ?? Bundle.main.url(forResource: nombre, withExtension: "txt") else {
            throw GTFSError.archivoNoEncontrado(nombre)
        }
        let texto = try String(contentsOf: url, encoding: .utf8)
        return parsear(texto: texto)
    }

    /// Parsea texto CSV a GTFSTable.
    static func parsear(texto: String) -> GTFSTable {
        let lineas = texto.split(separator: "\n", omittingEmptySubsequences: true)
        guard let primera = lineas.first else { return GTFSTable(columns: [:], rowCount: 0) }

        let encabezado = parsearLinea(String(primera))
        var columnas: [String: [String]] = [:]
        for nombre in encabezado where !nombre.isEmpty {
            columnas[nombre] = []
            columnas[nombre]?.reserveCapacity(lineas.count - 1)
        }

        for linea in lineas.dropFirst() {
            let valores = parsearLinea(String(linea))
            for (i, nombre) in encabezado.enumerated() where !nombre.isEmpty {
                columnas[nombre]?.append(i < valores.count ? valores[i] : "")
            }
        }

        return GTFSTable(columns: columnas, rowCount: lineas.count - 1)
    }

    /// Divide una línea CSV respetando comillas dobles.
    /// Fast path: sin comillas usa components(separatedBy:) directo.
    ///
    /// Nota sobre comillas "embebidas": los short names de este feed traen
    /// valores como `C-01 "B"`. Como el campo NO abre entrecomillado al
    /// inicio (ya tiene contenido), esas comillas se tratan como texto
    /// literal y no como delimitadores RFC.
    private static func parsearLinea(_ linea: String) -> [String] {
        guard linea.contains("\"") else {
            return linea.components(separatedBy: ",")
        }

        var valores: [String] = []
        var actual = ""
        var enComillas = false
        var iterador = linea.makeIterator()

        while let c = iterador.next() {
            if enComillas {
                if c == "\"" {
                    enComillas = false
                } else {
                    actual.append(c)
                }
            } else if c == "\"" {
                if actual.trimmingCharacters(in: .whitespaces).isEmpty {
                    enComillas = true
                } else {
                    actual.append(c)   // comilla embebida: es parte del dato
                }
            } else if c == "," {
                valores.append(actual)
                actual = ""
            } else {
                actual.append(c)
            }
        }
        valores.append(actual)
        return valores
    }
}
