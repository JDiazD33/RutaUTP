//
//  GTFSCSV.swift
//  RutaUTP
//
//  Parser CSV para los archivos .txt del feed GTFS.
//
//  - Reconoce BOM inicial, LF/CRLF/CR y campos citados con escapes y saltos.
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
        case encabezadosAusentes(String, [String])

        var errorDescription: String? {
            switch self {
            case .archivoNoEncontrado(let nombre):
                return "No se encontró \(nombre).txt en el bundle (carpeta gtfs)."
            case .encabezadosAusentes(let nombre, let columnas):
                return "Faltan encabezados en \(nombre).txt: \(columnas.joined(separator: ", "))."
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
        let bytes = Array(texto.utf8)
        // Reserva aproximada: los saltos dentro de campos citados pueden
        // sobreestimarla, pero no cambian la cantidad de registros emitidos.
        let capacidad = bytes.reduce(into: 0) { if $1 == 10 { $0 += 1 } }
        var encabezado: [String]?
        var columnas: [String: [String]] = [:]
        var filas = 0

        leerRegistros(bytes) { valores in
            if let nombres = encabezado {
                for (i, nombre) in nombres.enumerated() where !nombre.isEmpty {
                    columnas[nombre]?.append(i < valores.count ? valores[i] : "")
                }
                filas += 1
            } else {
                encabezado = valores
                for nombre in valores where !nombre.isEmpty {
                    columnas[nombre] = []
                    columnas[nombre]?.reserveCapacity(capacidad)
                }
            }
        }

        return GTFSTable(columns: columnas, rowCount: filas)
    }

    /// Emite registros completos, sin partir un salto que pertenece al dato.
    /// Los delimitadores son ASCII: leer UTF-8 evita que Swift agrupe CRLF
    /// en un solo Character y conserva los bytes de Unicode y saltos citados.
    private static func leerRegistros(_ bytes: [UInt8], procesar: ([String]) -> Void) {
        var indice = 0
        // Quitar únicamente la firma UTF-8 inicial; otro BOM es parte del dato.
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { indice = 3 }

        var valores: [String] = []
        var campo: [UInt8] = []
        var enComillas = false
        var registroConDatos = false

        func cerrarCampo() {
            valores.append(String(decoding: campo, as: UTF8.self))
            campo.removeAll(keepingCapacity: true)
        }

        func cerrarRegistro() {
            cerrarCampo()
            procesar(valores)
            valores.removeAll(keepingCapacity: true)
            registroConDatos = false
        }

        while indice < bytes.count {
            let byte = bytes[indice]
            indice += 1
            if enComillas {
                if byte == 34 {
                    if indice < bytes.count, bytes[indice] == 34 {
                        campo.append(34) // "" dentro de un campo representa una comilla.
                        indice += 1
                    } else {
                        enComillas = false
                    }
                } else {
                    campo.append(byte)
                }
            } else if byte == 34 {
                registroConDatos = true
                // Compatibilidad con C-01 "B" y con los espacios que el
                // parser anterior conservaba antes de abrir un campo citado.
                if String(decoding: campo, as: UTF8.self)
                    .trimmingCharacters(in: .whitespaces).isEmpty {
                    enComillas = true
                } else {
                    campo.append(byte)
                }
            } else if byte == 44 {
                registroConDatos = true
                cerrarCampo()
            } else if byte == 10 || byte == 13 {
                // CRLF es un separador único solo fuera de las comillas.
                if byte == 13, indice < bytes.count, bytes[indice] == 10 { indice += 1 }
                // Mantener la omisión de líneas vacías; "" y , sí son datos.
                if registroConDatos { cerrarRegistro() }
            } else {
                registroConDatos = true
                campo.append(byte)
            }
        }
        if registroConDatos { cerrarRegistro() }
    }
}
