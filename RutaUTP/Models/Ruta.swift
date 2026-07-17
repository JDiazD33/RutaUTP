//
//  Ruta.swift
//  RutaUTP
//
//  Modelo de una ruta de transporte público.
//

import Foundation
import SwiftUI

enum TipoVehiculo: String, CaseIterable, Identifiable {
    case micro = "Micro"
    case combi = "Combi"
    case bus   = "Bus"

    var id: String { rawValue }
}

struct Ruta: Identifiable, Equatable {
    let id: String
    let linea: String
    let nombre: String
    let empresa: String
    let tipo: TipoVehiculo
    let placa: String
    let minutosLlegada: Int
    let colorIdentificador: Color
}
