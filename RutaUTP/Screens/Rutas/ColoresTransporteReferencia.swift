//
//  ColoresTransporteReferencia.swift
//  RutaUTP
//
//  Paleta de referencia de una línea o empresa.
//

import Foundation

/// Paletas de referencias visuales o descripciones; no certifican toda la flota.
struct ColoresTransporteReferencia {
    let linea: String
    let letra: String
    let empresa: String
    let colores: [ColorTransporteReferencia]
    let fuente: URL?
    let modelo: TipoTransporte3D?
    let esOrientativa: Bool

    init(linea: String, letra: String, empresa: String, colores: [ColorTransporteReferencia],
         fuente: URL?, modelo: TipoTransporte3D? = nil, esOrientativa: Bool = false) {
        self.linea = linea
        self.letra = letra
        self.empresa = empresa
        self.colores = colores
        self.fuente = fuente
        self.modelo = modelo
        self.esOrientativa = esOrientativa
    }
}
