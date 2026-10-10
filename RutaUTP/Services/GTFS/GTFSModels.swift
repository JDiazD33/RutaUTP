//
//  GTFSModels.swift
//  RutaUTP
//
//  Modelos de dominio construidos a partir del feed GTFS estático
//  (gtfs/*.txt embebido en el bundle).
//
//  IMPORTANTE: el GTFS describe la ESTRUCTURA del transporte (rutas,
//  recorridos, paraderos, frecuencias y tarifas). NO contiene posiciones
//  GPS en vivo de las unidades: las posiciones "en tiempo real" de la app
//  siguen siendo simuladas sobre los recorridos reales.
//

import SwiftUI
import CoreLocation

// MARK: - Paradero
struct ParaderoGTFS: Identifiable, Equatable {
    let id: String
    let nombre: String
    let lat: Double
    let lon: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

// MARK: - Ruta GTFS (dominio)
struct RutaGTFS: Identifiable {
    let id: String                  // route_id del feed
    let linea: String               // "C-01"
    let variante: String            // "B" (letra entre comillas del short name)
    let recorrido: String           // "Av. Miguel Grau → Av. Libertad"
    let empresa: String             // nombre de la agencia
    let colorHex: String            // "00CC00"
    let color: Color
    let shape: [CLLocationCoordinate2D]  // recorrido completo ordenado
    let paraderos: [ParaderoGTFS]   // en orden de viaje
    let duracionMin: Int            // duración del viaje según stop_times
    let headwayMin: Int             // frecuencia: sale uno cada N min
    let precio: Double              // tarifa en PEN (fare_attributes)
    let distanciaKm: Double         // longitud del recorrido
    let distanciaUTPMetros: Double  // distancia mínima del shape al campus UTP

    /// Identificación para abordar; conserva los campos del feed y el route_id.
    var lineaConLetra: String {
        GTFSNombreParser.lineaConLetra(linea: linea, variante: variante)
    }

    /// Letra visible, también para las CT que la incluyen dentro de `linea`.
    var letraTransporte: String {
        GTFSNombreParser.identificacionTransporte(linea: linea, variante: variante).letra
    }

    var precioTexto: String {
        precio > 0 ? String(format: "S/ %.2f", precio) : "S/ —"
    }

    var frecuenciaTexto: String {
        headwayMin > 0 ? "cada \(headwayMin) min" : "—"
    }
}

// MARK: - Parser de nombres
enum GTFSNombreParser {

    /// Presentación compartida por Mapa, confirmación de subida y Rutas.
    /// No cambia los campos originales: las CT guardan la letra en `linea`.
    static func identificacionTransporte(linea: String, variante: String) -> (codigo: String, letra: String) {
        var codigo = linea
        var letra = variante.trimmingCharacters(in: .whitespacesAndNewlines)
        if letra.isEmpty && linea.hasPrefix("CT-") {
            let partes = linea.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            if partes.count == 2 {
                codigo = String(partes[0])
                letra = String(partes[1])
            }
        }
        let letraVisible = letra.replacingOccurrences(of: "<3", with: " ♥")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return (codigo, letraVisible)
    }

    static func lineaConLetra(linea: String, variante: String) -> String {
        let identificacion = identificacionTransporte(linea: linea, variante: variante)
        guard !identificacion.letra.isEmpty else { return linea }
        return identificacion.codigo + L.t(" · Letra ", " · Letter ") + identificacion.letra
    }

    /// `C-01 "B"` → línea "C-01", variante "B".
    static func lineaYVariante(shortName: String) -> (linea: String, variante: String) {
        let partes = shortName.components(separatedBy: "\"")
        let linea = (partes.first ?? shortName).trimmingCharacters(in: .whitespaces)
        let variante = partes.count > 1 ? partes[1].trimmingCharacters(in: .whitespaces) : ""
        return (linea.isEmpty ? shortName : linea, variante)
    }

    /// `C-01 "B" : Av. Grau → Av. Grau` → "Av. Grau → Av. Grau".
    /// Si origen == destino (ruta circular), devuelve "Origen (ramal circular)".
    static func recorrido(longName: String, shortName: String) -> String {
        var nombre = longName
        let prefijo = shortName + " : "
        if nombre.hasPrefix(prefijo) {
            nombre = String(nombre.dropFirst(prefijo.count))
        } else if let rango = nombre.range(of: " : ") {
            nombre = String(nombre[rango.upperBound...])
        }
        nombre = nombre.trimmingCharacters(in: .whitespaces)

        let partes = nombre.components(separatedBy: "→").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        if partes.count == 2, partes[0] == partes[1], !partes[0].isEmpty {
            return "\(partes[0]) (ramal circular)"
        }
        return nombre
    }
}
