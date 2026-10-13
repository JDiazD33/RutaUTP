import Foundation

struct RecordatorioViaje: Codable, Equatable {
    let id: UUID
    var minutoDelDia: Int
    var dias: Set<Int> // Calendario gregoriano: domingo = 1.
    var destinoID: String

    var esValido: Bool {
        (0..<1440).contains(minutoDelDia) && !dias.isEmpty
            && dias.isSubset(of: Set(1...7)) && !destinoID.isEmpty
    }
}

struct ConfiguracionNotificaciones: Codable, Equatable {
    var version = 1
    var recordatorio: RecordatorioViaje?
    var pausaHasta: Date?
    var diasSilencio: Set<Int> = []
    var silencioHorario = false
    var inicioSilencio = 22 * 60
    var finSilencio = 7 * 60
    var sonido = true

    var esValida: Bool {
        version == 1 && (recordatorio?.esValido ?? true)
            && diasSilencio.isSubset(of: Set(1...7))
            && (0..<1440).contains(inicioSilencio) && (0..<1440).contains(finSilencio)
            && (pausaHasta.map { $0.timeIntervalSince1970.isFinite && (-62135596800..<4102444800).contains($0.timeIntervalSince1970) } ?? true)
    }

    func permite(_ fecha: Date, calendario: Calendar) -> Bool {
        guard pausaHasta.map({ fecha >= $0 }) ?? true,
              !diasSilencio.contains(calendario.component(.weekday, from: fecha)) else { return false }
        guard silencioHorario else { return true }
        let minuto = calendario.component(.hour, from: fecha) * 60 + calendario.component(.minute, from: fecha)
        // Una franja con extremos iguales silencia el dia completo.
        if inicioSilencio == finSilencio { return false }
        if inicioSilencio < finSilencio {
            return minuto < inicioSilencio || minuto >= finSilencio
        }
        return minuto >= finSilencio && minuto < inicioSilencio
    }
}

struct DestinoRecordatorio: Identifiable, Equatable {
    let id: String
    let nombre: String
    let lat: Double
    let lon: Double

    var pendiente: DestinoPendiente { DestinoPendiente(titulo: nombre, lat: lat, lon: lon) }

    static func disponibles() -> [DestinoRecordatorio] {
        var destinos: [DestinoRecordatorio] = []
        if let sede = SedeTrabajoStore.shared.sede {
            destinos.append(DestinoRecordatorio(id: "sede:" + sede.id, nombre: sede.nombre, lat: sede.lat, lon: sede.lon))
        }
        destinos += LugaresStore.cargar().compactMap { lugar in
            guard let lat = lugar.lat, let lon = lugar.lon, lat.isFinite, lon.isFinite,
                  (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
            return DestinoRecordatorio(id: "lugar:" + lugar.id.uuidString, nombre: lugar.nombre, lat: lat, lon: lon)
        }
        return destinos
    }
}
