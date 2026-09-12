//
//  ReporteComunidad.swift
//  RutaUTP
//

import Foundation
import SwiftUI

enum TipoReporte: String, CaseIterable, Identifiable {
    case alerta    = "ALERTA"
    case trafico   = "TRÁFICO"
    case sugerencia = "SUGERENCIA"
    case otro      = "OTRO"

    var id: String { rawValue }

    var background: Color {
        switch self {
        case .alerta:     return .errorContainer
        case .trafico:    return .secondaryContainer
        case .sugerencia: return .tertiaryContainer
        case .otro:       return .surfaceContainerHigh
        }
    }

    var foreground: Color {
        switch self {
        case .alerta:     return .onErrorContainer
        case .trafico:    return .onSecondaryContainer
        case .sugerencia: return .onTertiaryContainer
        case .otro:       return .onSurfaceVariant
        }
    }
}

struct ReporteComunidad: Identifiable, Equatable {
    let id: UUID
    let iniciales: String
    let nombre: String
    let hace: String
    let tipo: TipoReporte
    let cuerpo: String
    let cuerpoIngles: String?
    let foto: FotoComunidad?
    let utiles: Int
    /// Conteo base de "no me gusta". El voto del usuario se suma en vivo
    /// vía `ComunidadReacciones` (no se persiste, es demo).
    let dislikes: Int
    let comentarios: Int
    let utilMarcado: Bool
    let avatarColor: Color
    let avatarForeground: Color

    var cuerpoLocalizado: String { L.esIngles ? (cuerpoIngles ?? cuerpo) : cuerpo }
    var tiempoLocalizado: String {
        guard L.esIngles else { return hace }
        let translations = ["HACE 3 MIN": "3 MIN AGO", "HACE 8 MIN": "8 MIN AGO",
                            "HACE 12 MIN": "12 MIN AGO", "HACE 20 MIN": "20 MIN AGO",
                            "HACE 35 MIN": "35 MIN AGO", "HACE 1 HORA": "1 HOUR AGO",
                            "HACE 2 HORAS": "2 HOURS AGO"]
        return translations[hace] ?? hace
    }

    init(id: UUID = UUID(),
         iniciales: String,
         nombre: String,
         hace: String,
         tipo: TipoReporte,
         cuerpo: String,
         cuerpoIngles: String? = nil,
         foto: FotoComunidad? = nil,
         utiles: Int,
         dislikes: Int = 0,
         comentarios: Int,
         utilMarcado: Bool = false,
         avatarColor: Color = .surfaceContainerHigh,
         avatarForeground: Color = .onSurfaceVariant) {
        self.id = id
        self.iniciales = iniciales
        self.nombre = nombre
        self.hace = hace
        self.tipo = tipo
        self.cuerpo = cuerpo
        self.cuerpoIngles = cuerpoIngles
        self.foto = foto
        self.utiles = utiles
        self.dislikes = dislikes
        self.comentarios = comentarios
        self.utilMarcado = utilMarcado
        self.avatarColor = avatarColor
        self.avatarForeground = avatarForeground
    }
}

/// Fotos de archivo para publicaciones ficticias, con procedencia y licencia.
struct FotoComunidad: Equatable {
    let asset: String
    let lugar: String
    let autor: String
    let fecha: String
    let fuente: String
    let licencia: String
    var licenciaURL: String { "https://creativecommons.org/licenses/by-sa/" + licencia + "/" }

    static let pizarro = FotoComunidad(asset: "comunidad-pizarro", lugar: "Jirón Pizarro · Trujillo",
        autor: "EACC", fecha: "2012", fuente: "https://commons.wikimedia.org/wiki/File:Jir%C3%B3n_Pizarro.jpg", licencia: "3.0")
    static let centro = FotoComunidad(asset: "comunidad-centro", lugar: "Centro de Trujillo",
        autor: "Pitxiquin", fecha: "2017", fuente: "https://commons.wikimedia.org/wiki/File:Carrers_del_centre_de_Trujillo.jpg", licencia: "4.0")
    static let papal = FotoComunidad(asset: "comunidad-papal", lugar: "Óvalo Papal · Trujillo",
        autor: "Latimax", fecha: "2011", fuente: "https://commons.wikimedia.org/wiki/File:Ovalo_papal_-_Trujillo_,Per%C3%BA.jpg", licencia: "3.0")
}
