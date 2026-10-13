import Foundation
import Observation
import CryptoKit

enum TipoAvisoDiario: String, Codable, CaseIterable, Identifiable {
    case rutas, cambios, cupones, guardado
    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .rutas: return L.t("Antes de salir", "Before heading out")
        case .cambios: return L.t("Consulta los cambios de ruta", "Check route changes")
        case .cupones: return L.t("Revisa las condiciones de tus cupones", "Check your coupon terms")
        case .guardado: return L.t("Prepara tu próximo viaje", "Prepare your next trip")
        }
    }

    var mensaje: String {
        switch self {
        case .rutas:
            return L.t("Revisa tu línea y sus paraderos antes de salir. Los horarios del catálogo son una referencia para planear tu viaje.", "Check your line and stops before heading out. Catalog timetables are a reference for planning your trip.")
        case .cambios:
            return L.t("Abre la consulta de cambios para revisar los reportes disponibles de tu línea. Sin información reciente no se puede confirmar el estado de la ruta.", "Open route changes to check available reports for your line. Without recent information, the route status cannot be confirmed.")
        case .cupones:
            return L.t("Antes de canjear un cupón, comprueba sus condiciones, su fecha de vencimiento y la confirmación del negocio.", "Before redeeming a coupon, check its terms, expiry date and confirmation from the business.")
        case .guardado:
            return L.t("Guarda las líneas que usas y revisa tu destino con tiempo para preparar tu salida.", "Save the lines you use and check your destination ahead of time to prepare your departure.")
        }
    }
}

struct ConfiguracionAvisosDiarios: Codable, Equatable {
    var version = 1
    var id = UUID()
    var activa = false
    var cantidad = 1
    var inicio = 9 * 60
    var fin = 20 * 60 // Final exclusivo. Franja del mismo dia.

    var esValida: Bool {
        version == 1 && (1...3).contains(cantidad) && (0..<1440).contains(inicio)
            && (1..<1440).contains(fin) && inicio < fin && fin - inicio >= cantidad
    }

    static func textoCantidad(_ cantidad: Int) -> String {
        cantidad == 1 ? L.t("Hasta 1 aviso al día", "Up to 1 notification a day")
            : L.f("Hasta {0} avisos al día", "Up to {0} notifications a day", [String(cantidad)])
    }
}

struct PlanAvisoDiario: Codable {
    let dia: String
    let indice: Int
    let fecha: Date
    let zona: String
    let tipo: TipoAvisoDiario

    var clave: String { dia + "." + String(indice) }
    var esValido: Bool {
        guard (0..<3).contains(indice), let timeZone = TimeZone(identifier: zona),
              fecha.timeIntervalSince1970.isFinite,
              (0..<4102444800).contains(fecha.timeIntervalSince1970) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return fecha.timeIntervalSince1970 == fecha.timeIntervalSince1970.rounded(.towardZero)
            && calendar.component(.second, from: fecha) == 0
            && dia == ProgramadorAvisosDiarios.claveDia(fecha, calendario: calendar)
    }
}

private struct RegistroAvisosDiarios: Codable {
    var version = 1
    var planes: [String: PlanAvisoDiario] = [:]
}

/// Separado de la configuracion de viajes para conservar su esquema y datos.
/// El registro recuerda los horarios elegidos: abrir la app no vuelve a sortear
/// un aviso del mismo dia que ya paso, aunque se haya borrado de iOS.
@MainActor @Observable
final class AvisosDiariosStore {
    static let llave = "notificaciones.diarios.v1"
    private static let llaveRegistro = "notificaciones.diarios.agenda.v1"
    private let defaults: UserDefaults
    private(set) var configuracion = ConfiguracionAvisosDiarios()
    private(set) var datosInvalidos = false
    private(set) var registroInvalido = false
    private(set) var planes: [String: PlanAvisoDiario] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recargar()
    }

    func recargar() {
        if let original = defaults.object(forKey: Self.llave) {
            if let data = original as? Data,
               let config = try? JSONDecoder().decode(ConfiguracionAvisosDiarios.self, from: data), config.esValida {
                configuracion = config
                datosInvalidos = false
            } else { datosInvalidos = true }
        } else { configuracion = ConfiguracionAvisosDiarios(); datosInvalidos = false }
        if let original = defaults.object(forKey: Self.llaveRegistro) {
            if let data = original as? Data, data.count <= 512_000,
               let registro = try? JSONDecoder().decode(RegistroAvisosDiarios.self, from: data),
               registro.version == 1, registro.planes.count <= 600,
               registro.planes.allSatisfy({ $0.key == $0.value.clave && $0.value.esValido }) {
                planes = registro.planes
                registroInvalido = false
            } else { registroInvalido = true }
        } else { planes = [:]; registroInvalido = false }
    }

    @discardableResult
    func guardar(_ config: ConfiguracionAvisosDiarios) -> Bool {
        recargar()
        guard !datosInvalidos, !registroInvalido, config.esValida,
              let data = try? JSONEncoder().encode(config) else { return false }
        defaults.set(data, forKey: Self.llave)
        configuracion = config
        return true
    }

    @discardableResult
    func registrar(_ plan: PlanAvisoDiario, ahora: Date) -> Bool {
        recargar()
        guard !datosInvalidos, !registroInvalido, plan.esValido else { return false }
        var nuevos = planes.filter { $0.value.fecha >= ahora.addingTimeInterval(-60 * 86400) }
        nuevos[plan.clave] = plan
        guard nuevos.count <= 600,
              let data = try? JSONEncoder().encode(RegistroAvisosDiarios(planes: nuevos)) else { return false }
        defaults.set(data, forKey: Self.llaveRegistro)
        planes = nuevos
        return true
    }
}

enum ProgramadorAvisosDiarios {
    static func claveDia(_ fecha: Date, calendario: Calendar) -> String {
        let partes = calendario.dateComponents([.year, .month, .day], from: fecha)
        return String(format: "%04d-%02d-%02d", partes.year ?? 0, partes.month ?? 0, partes.day ?? 0)
    }

    static func planes(config: ConfiguracionAvisosDiarios, silencios: ConfiguracionNotificaciones,
                       registro: [String: PlanAvisoDiario], desde ahora: Date, limite: Int) -> [PlanAvisoDiario] {
        guard config.esValida, config.activa, silencios.esValida, limite > 0 else { return [] }
        let calendar = ProgramadorRecordatorios.calendario
        let zona = calendar.timeZone.identifier
        let inicioAgenda = max(ahora, silencios.pausaHasta ?? ahora)
        var dia = calendar.startOfDay(for: inicioAgenda)
        var resultado: [PlanAvisoDiario] = []
        // Filtrar por minuto antes de usar Calendar evita buscar miles de
        // fechas cuando el silencio cubre toda la franja elegida.
        let minutosPermitidos = (config.inicio..<config.fin).filter { minuto in
            guard silencios.silencioHorario else { return true }
            let inicio = silencios.inicioSilencio, fin = silencios.finSilencio
            if inicio == fin { return false }
            return inicio < fin ? minuto < inicio || minuto >= fin : minuto >= fin && minuto < inicio
        }
        guard !minutosPermitidos.isEmpty else { return [] }
        for _ in 0..<366 {
            let clave = claveDia(dia, calendario: calendar)
            if !silencios.diasSilencio.contains(calendar.component(.weekday, from: dia)) {
                var generadorTipos = GeneradorAvisos(semilla: semilla(config.id.uuidString + clave + "tipos"))
                let tipos = TipoAvisoDiario.allCases.shuffled(using: &generadorTipos)
                let pasados = (0..<3).filter { indice in
                    registro[clave + "." + String(indice)].map { $0.fecha <= ahora } ?? false
                }
                var disponibles = max(0, config.cantidad - pasados.count)
                for indice in 0..<config.cantidad where disponibles > 0 && !pasados.contains(indice) {
                    let inferior = config.inicio + (config.fin - config.inicio) * indice / config.cantidad
                    let superior = config.inicio + (config.fin - config.inicio) * (indice + 1) / config.cantidad
                    let anterior = registro[clave + "." + String(indice)]
                    if let anterior, anterior.zona == zona, anterior.fecha > ahora,
                       calendar.isDate(anterior.fecha, inSameDayAs: dia),
                       (inferior..<superior).contains(calendar.component(.hour, from: anterior.fecha) * 60 + calendar.component(.minute, from: anterior.fecha)),
                       silencios.permite(anterior.fecha, calendario: calendar) {
                        resultado.append(anterior)
                        disponibles -= 1
                    } else {
                        var generador = GeneradorAvisos(semilla: semilla(config.id.uuidString + clave + String(indice)))
                        let candidatos = minutosPermitidos.filter { (inferior..<superior).contains($0) }.shuffled(using: &generador)
                        // DST: excluir horas inexistentes y elegir solo la
                        // primera ocurrencia cuando el reloj repite una hora.
                        let fecha = candidatos.lazy.compactMap { minuto -> Date? in
                            let hora = DateComponents(hour: minuto / 60, minute: minuto % 60, second: 0)
                            guard let fecha = calendar.nextDate(after: dia.addingTimeInterval(-1), matching: hora,
                                                                matchingPolicy: .strict, repeatedTimePolicy: .first),
                                  calendar.isDate(fecha, inSameDayAs: dia), fecha > ahora,
                                  silencios.permite(fecha, calendario: calendar) else { return nil }
                            return fecha
                        }.first
                        if let fecha {
                            let tipo = tipos[indice]
                            resultado.append(PlanAvisoDiario(dia: clave, indice: indice, fecha: fecha, zona: zona, tipo: tipo))
                            disponibles -= 1
                        }
                    }
                    if resultado.count >= limite { return resultado }
                }
            }
            guard let siguiente = calendar.date(byAdding: .day, value: 1, to: dia) else { break }
            dia = siguiente
        }
        return resultado
    }

    private static func semilla(_ texto: String) -> UInt64 {
        SHA256.hash(data: Data(texto.utf8)).prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    private struct GeneradorAvisos: RandomNumberGenerator {
        var semilla: UInt64
        mutating func next() -> UInt64 {
            semilla &+= 0x9E3779B97F4A7C15
            var x = semilla
            x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9
            x = (x ^ (x >> 27)) &* 0x94D049BB133111EB
            return x ^ (x >> 31)
        }
    }
}
