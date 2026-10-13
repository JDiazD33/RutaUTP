import Foundation

/// Fechas de una sola entrega: las pausas no dependen de despertar la app.
enum ProgramadorRecordatorios {
    static var calendario: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    static func fechas(config: ConfiguracionNotificaciones, desde ahora: Date, limite: Int = 30) -> [Date] {
        guard limite > 0, config.esValida, let recordatorio = config.recordatorio else { return [] }
        let calendar = calendario
        let inicio = max(ahora, config.pausaHasta ?? ahora)
        var dia = calendar.startOfDay(for: inicio)
        var fechas: [Date] = []
        let hora = DateComponents(hour: recordatorio.minutoDelDia / 60, minute: recordatorio.minutoDelDia % 60, second: 0)
        // Hasta 30 semanas si solo hay un dia habilitado; un limite evita
        // bucles cuando las reglas silencian todas las ocurrencias.
        for _ in 0..<366 {
            if recordatorio.dias.contains(calendar.component(.weekday, from: dia)),
               let fecha = calendar.nextDate(after: dia.addingTimeInterval(-1), matching: hora,
                                             matchingPolicy: .nextTimePreservingSmallerComponents,
                                             repeatedTimePolicy: .first, direction: .forward),
               calendar.isDate(fecha, inSameDayAs: dia), fecha > ahora,
               config.permite(fecha, calendario: calendar) {
                fechas.append(fecha)
                if fechas.count >= limite { break }
            }
            guard let siguiente = calendar.date(byAdding: .day, value: 1, to: dia) else { break }
            dia = siguiente
        }
        return fechas
    }
}
