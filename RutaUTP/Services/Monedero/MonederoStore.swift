// Monedero local de demostración. No procesa pagos ni valida viajes.

import Foundation
import CoreFoundation
import Combine

struct MovimientoMonedero: Codable, Identifiable, Equatable {
    let id: UUID
    let fecha: Date
    /// El signo identifica la operación también en el historial anterior.
    let importe: Double

    var esRecarga: Bool { importe > 0 }
    var descripcion: String {
        esRecarga
            ? L.t("Recarga de demostración", "Demo top-up")
            : L.t("Pasaje (simulado)", "Fare (simulated)")
    }
    // Codable omite la antigua descripción traducida: las claves adicionales
    // del historial v1 se ignoran al leer y el texto sigue el idioma actual.
}

@MainActor
final class MonederoStore: ObservableObject {
    /// Referencia de la demo, no una tarifa consultada para una ruta concreta.
    private static let tarifaCentimos = 250
    static var tarifaReferencia: Double { Double(tarifaCentimos) / 100 }
    /// Saldo con el que arranca la demo, en céntimos.
    ///
    /// Fuente única del valor: el estado inicial de `saldoCentimos` sale de
    /// aquí. Antes había además un `saldoInicial: Double = 10.00` que no leía
    /// nadie, así que editar el saldo "obvio" no hacía nada.
    private static let saldoInicialCentimos = 1_000
    /// Límite de la demo; mantiene los cálculos y las conversiones acotados.
    private static let maximoCentimos = 100_000_000

    @Published private var saldoCentimos = MonederoStore.saldoInicialCentimos
    @Published private(set) var movimientos: [MovimientoMonedero] = []
    @Published private(set) var datosLocalesInvalidos = false

    private static let llaveSaldo = "monedero.saldo.v1"
    private static let llaveMovimientos = "monedero.movimientos.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        cargar()
    }

    var saldo: Double { Double(saldoCentimos) / 100 }
    var pasajesDisponibles: Int { saldoCentimos / Self.tarifaCentimos }
    var saldoTexto: String { String(format: "S/ %.2f", saldo) }
    var tarifaTexto: String { String(format: "S/ %.2f", Self.tarifaReferencia) }

    /// Rechaza importes no finitos, no positivos, con fracciones de céntimo
    /// o que excedan el límite. Un rechazo no modifica saldo ni historial.
    @discardableResult
    func recargar(_ importe: Double) -> Bool {
        guard !datosLocalesInvalidos,
              let centimos = Self.centimos(importe), centimos > 0,
              centimos <= Self.maximoCentimos - saldoCentimos else { return false }
        return registrar(importe: Double(centimos) / 100, saldoNuevo: saldoCentimos + centimos)
    }

    @discardableResult
    func cobrarPasaje() -> Bool { cobrarPasaje(Self.tarifaReferencia) }

    @discardableResult
    func cobrarPasaje(_ importe: Double) -> Bool {
        guard !datosLocalesInvalidos,
              let centimos = Self.centimos(importe), centimos > 0,
              saldoCentimos >= centimos else { return false }
        return registrar(importe: -Double(centimos) / 100, saldoNuevo: saldoCentimos - centimos)
    }

    private static func centimos(_ importe: Double) -> Int? {
        guard importe.isFinite, importe >= 0,
              importe <= Double(maximoCentimos) / 100 else { return nil }
        let escalado = importe * 100
        let redondeado = escalado.rounded()
        // Tolera únicamente el error de representación binaria de Double.
        guard abs(escalado - redondeado) <= 0.000001 else { return nil }
        return Int(redondeado)
    }

    private func registrar(importe: Double, saldoNuevo: Int) -> Bool {
        let movimiento = MovimientoMonedero(id: UUID(), fecha: Date(), importe: importe)
        let nuevos = Array(([movimiento] + movimientos).prefix(20))
        guard let data = try? JSONEncoder().encode(nuevos) else { return false }
        defaults.set(data, forKey: Self.llaveMovimientos)
        defaults.set(Double(saldoNuevo) / 100, forKey: Self.llaveSaldo)
        movimientos = nuevos
        saldoCentimos = saldoNuevo
        return true
    }

    private func cargar() {
        if let almacenado = defaults.object(forKey: Self.llaveSaldo) {
            if let numero = almacenado as? NSNumber,
               CFGetTypeID(numero) != CFBooleanGetTypeID(),
               let centimos = Self.centimos(numero.doubleValue) {
                saldoCentimos = centimos
            } else {
                saldoCentimos = 0
                datosLocalesInvalidos = true
            }
        }
        if let almacenado = defaults.object(forKey: Self.llaveMovimientos) {
            if let data = almacenado as? Data,
               let guardados = try? JSONDecoder().decode([MovimientoMonedero].self, from: data),
               Set(guardados.map(\.id)).count == guardados.count,
               guardados.allSatisfy({
                   $0.fecha.timeIntervalSinceReferenceDate.isFinite &&
                   (Self.centimos(abs($0.importe)) ?? 0) > 0
               }), defaults.object(forKey: Self.llaveSaldo) != nil {
                movimientos = Array(guardados.prefix(20))
            } else {
                datosLocalesInvalidos = true
            }
        }
        // Conserva los originales si están dañados; no permite sobrescribirlos
        // con operaciones sobre un saldo que no se pudo recuperar con seguridad.
        if datosLocalesInvalidos { saldoCentimos = 0 }
    }
}
