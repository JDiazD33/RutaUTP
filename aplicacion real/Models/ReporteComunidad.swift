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
    let utiles: Int
    let comentarios: Int
    let utilMarcado: Bool
    let avatarColor: Color
    let avatarForeground: Color

    init(id: UUID = UUID(),
         iniciales: String,
         nombre: String,
         hace: String,
         tipo: TipoReporte,
         cuerpo: String,
         utiles: Int,
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
        self.utiles = utiles
        self.comentarios = comentarios
        self.utilMarcado = utilMarcado
        self.avatarColor = avatarColor
        self.avatarForeground = avatarForeground
    }
}
