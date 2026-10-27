//
//  DiasNotificaciones.swift
//  RutaUTP
//
//  Utilidades de dias y horas para las notificaciones.
//

import Foundation

enum DiasNotificaciones {
    static func fecha(minutos: Int) -> Date {
        let calendar = ProgramadorRecordatorios.calendario
        return calendar.date(bySettingHour: minutos / 60, minute: minutos % 60, second: 0, of: Date()) ?? Date()
    }
    static func minutos(_ fecha: Date) -> Int {
        let calendar = ProgramadorRecordatorios.calendario
        return calendar.component(.hour, from: fecha) * 60 + calendar.component(.minute, from: fecha)
    }
    static func nombre(_ dia: Int, corto: Bool) -> String {
        let formatter = FormatoFecha.formateador(patron: "EEEE", locale: IdiomaManager.shared.idioma.locale)
        let nombres = corto ? formatter.shortStandaloneWeekdaySymbols ?? [] : formatter.standaloneWeekdaySymbols ?? []
        guard nombres.indices.contains(dia - 1) else { return "" }
        return nombres[dia - 1]
    }
    static func resumen(_ dias: Set<Int>) -> String {
        [2, 3, 4, 5, 6, 7, 1].filter(dias.contains).map { nombre($0, corto: true) }.joined(separator: ", ")
    }
}
