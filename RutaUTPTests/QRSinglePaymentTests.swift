//
//  QRSinglePaymentTests.swift
//  RutaUTPTests
//
//  E12: una lectura solo puede debitar una vez. Una lectura nueva permite
//  otro viaje y un cobro rechazado conserva la posibilidad de reintentar.
//  No se inicia la cámara ni se usan las preferencias de la instalación.
//

import XCTest
import Combine
@testable import RutaUTP

@MainActor
final class QRSinglePaymentTests: XCTestCase {
    private var dominio: String!
    private var defaults: UserDefaults!
    private let llaveSaldo = "monedero.saldo.v1"
    private let llaveMovimientos = "monedero.movimientos.v1"

    override func setUp() {
        super.setUp()
        dominio = "RutaUTPTests.QRSinglePayment.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: dominio)!
        defaults.removePersistentDomain(forName: dominio)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: dominio)
        defaults = nil
        dominio = nil
        super.tearDown()
    }

    func testDobleToqueDebitaUnaVezYConservaMovimientoYBytes() throws {
        let store = MonederoStore(defaults: defaults)
        let modelo = EscanerQRModel()
        defer { modelo.detener() }
        let lectura = try ejemplo(en: modelo)
        var llamadas = 0

        XCTAssertTrue(modelo.puedePagar(lectura))
        XCTAssertEqual(modelo.pagar(lectura) { importe in
            llamadas += 1
            return store.cobrarPasaje(importe)
        }, true)
        let persistido = snapshot()
        let bytes = try XCTUnwrap(defaults.data(forKey: llaveMovimientos))
        let movimiento = try XCTUnwrap(store.movimientos.first)

        XCTAssertNil(modelo.pagar(lectura) { importe in
            llamadas += 1
            return store.cobrarPasaje(importe)
        })
        XCTAssertEqual(llamadas, 1)
        XCTAssertTrue(modelo.pagoRealizado)
        XCTAssertFalse(modelo.puedePagar(lectura))
        XCTAssertEqual(store.saldo, 7.50)
        XCTAssertEqual(store.movimientos, [movimiento])
        XCTAssertEqual(movimiento.importe, -MonederoStore.tarifaReferencia)
        XCTAssertEqual(defaults.data(forKey: llaveMovimientos), bytes)
        XCTAssertTrue(snapshot().isEqual(persistido))
        XCTAssertEqual(Set((defaults.persistentDomain(forName: dominio) ?? [:]).keys),
                       Set([llaveSaldo, llaveMovimientos]))
        XCTAssertEqual(try JSONDecoder().decode([MovimientoMonedero].self, from: bytes),
                       [movimiento])

        let recargado = MonederoStore(defaults: defaults)
        XCTAssertFalse(recargado.datosLocalesInvalidos)
        XCTAssertEqual(recargado.saldo, 7.50)
        XCTAssertEqual(recargado.movimientos, [movimiento])
        XCTAssertEqual(recargado.movimientos.first?.id, movimiento.id)
        XCTAssertEqual(modelo.resultado?.id, lectura.id)
        XCTAssertFalse(modelo.camara.sesion.isRunning)
    }

    func testCallbackRechazadoPermiteReintentoYSoloExitoConsumeLectura() throws {
        let modelo = EscanerQRModel()
        defer { modelo.detener() }
        let lectura = try ejemplo(en: modelo)
        var importes: [Double] = []

        XCTAssertEqual(modelo.pagar(lectura) { importes.append($0); return false }, false)
        XCTAssertFalse(modelo.pagoRealizado)
        XCTAssertTrue(modelo.puedePagar(lectura))
        XCTAssertEqual(modelo.resultado?.id, lectura.id)
        XCTAssertEqual(modelo.pagar(lectura) { importes.append($0); return true }, true)
        XCTAssertNil(modelo.pagar(lectura) { importes.append($0); return true })
        XCTAssertEqual(importes, [MonederoStore.tarifaReferencia, MonederoStore.tarifaReferencia])
        XCTAssertTrue(modelo.pagoRealizado)
    }

    func testSaldoInsuficienteNoConsumeQRYRecargaPermiteUnSoloCobro() throws {
        defaults.set(1.25, forKey: llaveSaldo)
        let store = MonederoStore(defaults: defaults)
        let modelo = EscanerQRModel()
        defer { modelo.detener() }
        let lectura = try ejemplo(en: modelo)
        let original = snapshot()
        var llamadas = 0

        XCTAssertEqual(modelo.pagar(lectura) { importe in
            llamadas += 1
            return store.cobrarPasaje(importe)
        }, false)
        XCTAssertTrue(snapshot().isEqual(original))
        XCTAssertFalse(modelo.pagoRealizado)
        XCTAssertTrue(modelo.puedePagar(lectura))
        XCTAssertTrue(store.recargar(5))
        XCTAssertEqual(modelo.pagar(lectura) { importe in
            llamadas += 1
            return store.cobrarPasaje(importe)
        }, true)
        let pagado = snapshot()
        XCTAssertNil(modelo.pagar(lectura) { importe in
            llamadas += 1
            return store.cobrarPasaje(importe)
        })
        XCTAssertEqual(llamadas, 2)
        XCTAssertEqual(store.saldo, 3.75)
        XCTAssertEqual(store.movimientos.map(\.importe), [-2.50, 5])
        XCTAssertEqual(Set(store.movimientos.map(\.id)).count, 2)
        XCTAssertTrue(snapshot().isEqual(pagado))
    }

    func testEscanearOtraVezMismoTextoCreaNuevaIdentidadYRechazaAccionAnterior() throws {
        let store = MonederoStore(defaults: defaults)
        let modelo = EscanerQRModel()
        defer { modelo.detener() }
        let primera = try ejemplo(en: modelo)
        XCTAssertEqual(modelo.pagar(primera) { store.cobrarPasaje($0) }, true)

        modelo.reanudar()
        XCTAssertNil(modelo.resultado)
        XCTAssertFalse(modelo.pagoRealizado)
        XCTAssertFalse(modelo.puedePagar(primera))
        let segunda = try ejemplo(en: modelo)
        XCTAssertEqual(primera.texto, segunda.texto)
        XCTAssertEqual(primera.campos, segunda.campos)
        XCTAssertNotEqual(primera.id, segunda.id)
        XCTAssertNotEqual(primera, segunda)
        var llamadasAntiguas = 0
        XCTAssertNil(modelo.pagar(primera) { importe in
            llamadasAntiguas += 1
            return store.cobrarPasaje(importe)
        })
        XCTAssertEqual(llamadasAntiguas, 0)
        XCTAssertTrue(modelo.puedePagar(segunda))
        XCTAssertEqual(modelo.pagar(segunda) { store.cobrarPasaje($0) }, true)
        XCTAssertEqual(store.saldo, 5)
        XCTAssertEqual(store.movimientos.count, 2)
        XCTAssertEqual(Set(store.movimientos.map(\.id)).count, 2)
        XCTAssertFalse(modelo.camara.sesion.isRunning)
    }

    func testNuevaLecturaConOtroImporteNoEjecutaAccionDeTarjetaAnterior() async throws {
        let store = MonederoStore(defaults: defaults)
        let modelo = EscanerQRModel()
        defer { modelo.detener() }
        let primera = try await leer(PagoQR.cargaUtil(importe: 3.75), en: modelo)
        XCTAssertEqual(modelo.pagar(primera) { store.cobrarPasaje($0) }, true)
        modelo.reanudar()
        let segunda = try await leer(PagoQR.cargaUtil(importe: 1.20), en: modelo)
        var recibidos: [Double] = []

        XCTAssertNil(modelo.pagar(primera) { recibidos.append($0); return true })
        XCTAssertEqual(modelo.pagar(segunda) { importe in
            recibidos.append(importe)
            return store.cobrarPasaje(importe)
        }, true)
        XCTAssertNil(modelo.pagar(segunda) { recibidos.append($0); return true })
        XCTAssertEqual(recibidos, [1.20])
        XCTAssertEqual(store.saldo, 5.05)
        XCTAssertEqual(store.movimientos.map(\.importe), [-1.20, -3.75])
        XCTAssertTrue(modelo.pagoRealizado)
    }

    func testEscanearOtroAntesDePagarDescartaLecturaAntigua() throws {
        let modelo = EscanerQRModel()
        defer { modelo.detener() }
        let primera = try ejemplo(en: modelo)
        modelo.reanudar()
        let segunda = try ejemplo(en: modelo)
        var llamadas = 0

        XCTAssertNil(modelo.pagar(primera) { _ in llamadas += 1; return true })
        XCTAssertEqual(llamadas, 0)
        XCTAssertFalse(modelo.pagoRealizado)
        XCTAssertTrue(modelo.puedePagar(segunda))
        XCTAssertEqual(modelo.pagar(segunda) { _ in llamadas += 1; return true }, true)
        XCTAssertEqual(llamadas, 1)
    }

    func testModeloAjenoNoPuedePagarLecturaAunqueTextoYCamposCoincidan() throws {
        let modelo = EscanerQRModel()
        let ajeno = EscanerQRModel()
        defer { modelo.detener(); ajeno.detener() }
        let propia = try ejemplo(en: modelo)
        let otra = try ejemplo(en: ajeno)
        XCTAssertEqual(propia.texto, otra.texto)
        XCTAssertEqual(propia.campos, otra.campos)
        XCTAssertNotEqual(propia.id, otra.id)
        var llamadas = 0

        XCTAssertFalse(modelo.puedePagar(otra))
        XCTAssertNil(modelo.pagar(otra) { _ in llamadas += 1; return true })
        XCTAssertEqual(llamadas, 0)
        XCTAssertTrue(modelo.puedePagar(propia))
        XCTAssertEqual(modelo.pagar(propia) { _ in llamadas += 1; return true }, true)
        XCTAssertEqual(llamadas, 1)
        XCTAssertFalse(ajeno.pagoRealizado)
        XCTAssertTrue(ajeno.puedePagar(otra))
    }

    func testResultadoFabricadoYModeloSinLecturaNoInvocanMonedero() throws {
        let modelo = EscanerQRModel()
        defer { modelo.detener() }
        let texto = PagoQR.cargaUtil()
        let fabricado = ResultadoQR(texto: texto, campos: PagoQR.leer(texto))
        var llamadas = 0
        XCTAssertFalse(modelo.puedePagar(fabricado))
        XCTAssertNil(modelo.pagar(fabricado) { _ in llamadas += 1; return true })
        let propia = try ejemplo(en: modelo)
        XCTAssertNotEqual(fabricado.id, propia.id)
        XCTAssertNil(modelo.pagar(fabricado) { _ in llamadas += 1; return true })
        XCTAssertEqual(llamadas, 0)
        XCTAssertTrue(modelo.puedePagar(propia))
    }

    func testDetenerNoBorraConsumoYUnModeloNuevoPuedePagarOtroViaje() throws {
        let store = MonederoStore(defaults: defaults)
        let anterior = EscanerQRModel()
        let nuevo = EscanerQRModel()
        defer { anterior.detener(); nuevo.detener() }
        let pagada = try ejemplo(en: anterior)
        XCTAssertEqual(anterior.pagar(pagada) { store.cobrarPasaje($0) }, true)
        anterior.detener()
        var llamadasAntiguas = 0
        XCTAssertTrue(anterior.pagoRealizado)
        XCTAssertEqual(anterior.resultado?.id, pagada.id)
        XCTAssertNil(anterior.pagar(pagada) { importe in
            llamadasAntiguas += 1
            return store.cobrarPasaje(importe)
        })
        let otra = try ejemplo(en: nuevo)
        XCTAssertEqual(otra.texto, pagada.texto)
        XCTAssertNotEqual(otra.id, pagada.id)
        XCTAssertEqual(nuevo.pagar(otra) { store.cobrarPasaje($0) }, true)
        XCTAssertEqual(llamadasAntiguas, 0)
        XCTAssertEqual(store.saldo, 5)
        XCTAssertEqual(store.movimientos.count, 2)
    }

    func testEntregasRepetidasMientrasResultadoVisibleConservanIdentidadYConsumo() throws {
        let modelo = EscanerQRModel()
        defer { modelo.detener() }
        let primera = try ejemplo(en: modelo)
        XCTAssertEqual(modelo.pagar(primera) { _ in true }, true)
        modelo.simularLectura()
        modelo.simularLectura()
        XCTAssertEqual(modelo.resultado?.id, primera.id)
        XCTAssertEqual(modelo.resultado?.texto, primera.texto)
        XCTAssertTrue(modelo.pagoRealizado)
        var llamadas = 0
        XCTAssertNil(modelo.pagar(primera) { _ in llamadas += 1; return true })
        XCTAssertEqual(llamadas, 0)
        XCTAssertFalse(modelo.camara.sesion.isRunning)
    }

    func testReglasE11SiguenBloqueandoPagoSinConsumirNiAlterarDatos() async throws {
        let store = MonederoStore(defaults: defaults)
        XCTAssertTrue(store.recargar(1))
        let original = snapshot()
        let movimientos = store.movimientos
        let modelo = EscanerQRModel()
        defer { modelo.detener() }
        let textos = ["https://ejemplo.invalid/pagar", "texto informativo",
                      PagoQR.cargaUtil() + "\nimporte:",
                      PagoQR.cargaUtil() + "\nimporte: 2.50\nimporte: 3.75",
                      "0002016304abc"]
        var llamadas = 0

        for texto in textos {
            modelo.reanudar()
            let lectura = try await leer(texto, en: modelo)
            XCTAssertFalse(modelo.puedePagar(lectura))
            XCTAssertNil(modelo.pagar(lectura) { importe in
                llamadas += 1
                return store.cobrarPasaje(importe)
            })
            XCTAssertFalse(modelo.pagoRealizado)
            XCTAssertTrue(snapshot().isEqual(original))
        }
        XCTAssertEqual(llamadas, 0)
        XCTAssertEqual(store.saldo, 11)
        XCTAssertEqual(store.movimientos, movimientos)
        modelo.reanudar()
        let valida = try ejemplo(en: modelo)
        XCTAssertTrue(modelo.puedePagar(valida))
        XCTAssertEqual(modelo.pagar(valida) { store.cobrarPasaje($0) }, true)
        XCTAssertEqual(store.saldo, 8.50)
    }

    func testHistorialCorruptoConservaOriginalYRechazoNoConsumeLectura() throws {
        let bytes = Data("[{\"id\":".utf8)
        defaults.set(10.0, forKey: llaveSaldo)
        defaults.set(bytes, forKey: llaveMovimientos)
        let original = snapshot()
        let store = MonederoStore(defaults: defaults)
        let modelo = EscanerQRModel()
        defer { modelo.detener() }
        let lectura = try ejemplo(en: modelo)
        var llamadas = 0
        for _ in 0..<2 {
            XCTAssertEqual(modelo.pagar(lectura) { importe in
                llamadas += 1
                return store.cobrarPasaje(importe)
            }, false)
        }
        XCTAssertEqual(llamadas, 2)
        XCTAssertTrue(store.datosLocalesInvalidos)
        XCTAssertTrue(store.movimientos.isEmpty)
        XCTAssertFalse(modelo.pagoRealizado)
        XCTAssertTrue(modelo.puedePagar(lectura))
        XCTAssertEqual(defaults.data(forKey: llaveMovimientos), bytes)
        XCTAssertTrue(snapshot().isEqual(original))
    }

    func testReentradaEnCallbackNoCobraNiPermiteReanudarAntesDeTerminar() throws {
        let store = MonederoStore(defaults: defaults)
        let modelo = EscanerQRModel()
        defer { modelo.detener() }
        let lectura = try ejemplo(en: modelo)
        var llamadasAnidadas = 0
        XCTAssertEqual(modelo.pagar(lectura) { importe in
            XCTAssertFalse(modelo.puedePagar(lectura))
            XCTAssertNil(modelo.pagar(lectura) { monto in
                llamadasAnidadas += 1
                return store.cobrarPasaje(monto)
            })
            modelo.reanudar()
            modelo.simularLectura()
            XCTAssertEqual(modelo.resultado?.id, lectura.id)
            return store.cobrarPasaje(importe)
        }, true)
        XCTAssertEqual(llamadasAnidadas, 0)
        XCTAssertTrue(modelo.pagoRealizado)
        XCTAssertEqual(modelo.resultado?.id, lectura.id)
        XCTAssertEqual(store.saldo, 7.50)
        XCTAssertEqual(store.movimientos.count, 1)
    }

    func testReentradaTrasCallbackFalseLiberaBloqueoParaUnReintentoPosterior() throws {
        let modelo = EscanerQRModel()
        defer { modelo.detener() }
        let lectura = try ejemplo(en: modelo)
        var anidadas = 0
        XCTAssertEqual(modelo.pagar(lectura) { _ in
            XCTAssertNil(modelo.pagar(lectura) { _ in anidadas += 1; return true })
            modelo.reanudar()
            XCTAssertEqual(modelo.resultado?.id, lectura.id)
            return false
        }, false)
        XCTAssertEqual(anidadas, 0)
        XCTAssertFalse(modelo.pagoRealizado)
        XCTAssertTrue(modelo.puedePagar(lectura))
        XCTAssertEqual(modelo.pagar(lectura) { _ in true }, true)
        XCTAssertTrue(modelo.pagoRealizado)
    }

    func testPublicacionesDelMonederoNoAbrenReentradaDuranteDebito() throws {
        let store = MonederoStore(defaults: defaults)
        let modelo = EscanerQRModel()
        defer { modelo.detener() }
        let lectura = try ejemplo(en: modelo)
        var avisos = 0
        var llamadasAnidadas = 0
        let observador = store.objectWillChange.sink {
            avisos += 1
            XCTAssertFalse(modelo.puedePagar(lectura))
            XCTAssertNil(modelo.pagar(lectura) { importe in
                llamadasAnidadas += 1
                return store.cobrarPasaje(importe)
            })
            modelo.reanudar()
            XCTAssertEqual(modelo.resultado?.id, lectura.id)
        }
        XCTAssertEqual(modelo.pagar(lectura) { store.cobrarPasaje($0) }, true)
        observador.cancel()
        XCTAssertGreaterThan(avisos, 0)
        XCTAssertEqual(llamadasAnidadas, 0)
        XCTAssertEqual(store.saldo, 7.50)
        XCTAssertEqual(store.movimientos.count, 1)
        XCTAssertTrue(modelo.pagoRealizado)
    }

    func testPublicacionPagoRealizadoBloqueaAntesDeQuePublishedActualiceValor() throws {
        let store = MonederoStore(defaults: defaults)
        let modelo = EscanerQRModel()
        defer { modelo.detener() }
        let lectura = try ejemplo(en: modelo)
        var avisos = 0
        var llamadasAnidadas = 0
        let observador = modelo.$pagoRealizado.dropFirst().sink { pagado in
            guard pagado else { return }
            avisos += 1
            // @Published emite desde willSet: la regla privada debe impedir
            // otro débito aunque el valor público todavía sea false.
            XCTAssertFalse(modelo.puedePagar(lectura))
            XCTAssertNil(modelo.pagar(lectura) { importe in
                llamadasAnidadas += 1
                return store.cobrarPasaje(importe)
            })
            modelo.reanudar()
            XCTAssertEqual(modelo.resultado?.id, lectura.id)
        }
        XCTAssertEqual(modelo.pagar(lectura) { store.cobrarPasaje($0) }, true)
        observador.cancel()
        XCTAssertEqual(avisos, 1)
        XCTAssertEqual(llamadasAnidadas, 0)
        XCTAssertEqual(store.movimientos.count, 1)
        XCTAssertEqual(store.saldo, 7.50)
        XCTAssertTrue(modelo.pagoRealizado)
    }

    func testObjectWillChangeDelModeloNoAbreReentradaNiBorraTarjetaPagada() throws {
        let store = MonederoStore(defaults: defaults)
        let modelo = EscanerQRModel()
        defer { modelo.detener() }
        let lectura = try ejemplo(en: modelo)
        var avisos = 0
        var llamadasAnidadas = 0
        let observador = modelo.objectWillChange.sink {
            avisos += 1
            XCTAssertFalse(modelo.puedePagar(lectura))
            XCTAssertNil(modelo.pagar(lectura) { importe in
                llamadasAnidadas += 1
                return store.cobrarPasaje(importe)
            })
            modelo.reanudar()
            XCTAssertEqual(modelo.resultado?.id, lectura.id)
        }
        XCTAssertEqual(modelo.pagar(lectura) { store.cobrarPasaje($0) }, true)
        observador.cancel()
        XCTAssertGreaterThan(avisos, 0)
        XCTAssertEqual(llamadasAnidadas, 0)
        XCTAssertEqual(modelo.resultado?.id, lectura.id)
        XCTAssertTrue(modelo.pagoRealizado)
        XCTAssertEqual(store.saldo, 7.50)
        XCTAssertEqual(store.movimientos.count, 1)
    }

    func testPublicacionDeResetNoPermitePagarLecturaPendienteNiCapturarAnidado() throws {
        let store = MonederoStore(defaults: defaults)
        let original = snapshot()
        let modelo = EscanerQRModel()
        defer { modelo.detener() }
        let anterior = try ejemplo(en: modelo)
        var avisos = 0
        var llamadas = 0
        let observador = modelo.$resultado.dropFirst().sink { resultado in
            guard resultado == nil else { return }
            avisos += 1
            XCTAssertFalse(modelo.puedePagar(anterior))
            XCTAssertNil(modelo.pagar(anterior) { importe in
                llamadas += 1
                return store.cobrarPasaje(importe)
            })
            modelo.reanudar()
            modelo.simularLectura()
            // El willSet aún expone la lectura anterior. Las operaciones
            // anidadas no pueden cobrarla ni sustituirla por una nueva.
            XCTAssertEqual(modelo.resultado?.id, anterior.id)
        }
        modelo.reanudar()
        observador.cancel()
        XCTAssertEqual(avisos, 1)
        XCTAssertEqual(llamadas, 0)
        XCTAssertNil(modelo.resultado)
        XCTAssertFalse(modelo.pagoRealizado)
        XCTAssertEqual(store.saldo, 10)
        XCTAssertTrue(store.movimientos.isEmpty)
        XCTAssertTrue(snapshot().isEqual(original))
        let siguiente = try ejemplo(en: modelo)
        XCTAssertNotEqual(siguiente.id, anterior.id)
        XCTAssertTrue(modelo.puedePagar(siguiente))
        XCTAssertFalse(modelo.camara.sesion.isRunning)
    }

    func testPublicacionConsumoFalseDuranteResetNoReactivaLecturaYaPagada() throws {
        let store = MonederoStore(defaults: defaults)
        let modelo = EscanerQRModel()
        defer { modelo.detener() }
        let anterior = try ejemplo(en: modelo)
        XCTAssertEqual(modelo.pagar(anterior) { store.cobrarPasaje($0) }, true)
        let original = snapshot()
        var avisos = 0
        var llamadas = 0
        let observador = modelo.$pagoRealizado.dropFirst().sink { pagado in
            guard !pagado else { return }
            avisos += 1
            XCTAssertFalse(modelo.puedePagar(anterior))
            XCTAssertNil(modelo.pagar(anterior) { importe in
                llamadas += 1
                return store.cobrarPasaje(importe)
            })
            modelo.simularLectura()
            XCTAssertNil(modelo.resultado)
        }
        modelo.reanudar()
        observador.cancel()
        XCTAssertEqual(avisos, 1)
        XCTAssertEqual(llamadas, 0)
        XCTAssertNil(modelo.resultado)
        XCTAssertFalse(modelo.pagoRealizado)
        XCTAssertTrue(snapshot().isEqual(original))
        XCTAssertEqual(store.movimientos.count, 1)
        XCTAssertEqual(store.saldo, 7.50)
        let siguiente = try ejemplo(en: modelo)
        XCTAssertNotEqual(siguiente.id, anterior.id)
        XCTAssertTrue(modelo.puedePagar(siguiente))
    }

    func testPublicacionDeNuevaLecturaNoPermiteResetNiCapturaAnidados() throws {
        let modelo = EscanerQRModel()
        defer { modelo.detener() }
        var emitida: ResultadoQR?
        var avisos = 0
        var llamadas = 0
        let observador = modelo.$resultado.compactMap { $0 }.sink { lectura in
            avisos += 1
            emitida = lectura
            XCTAssertFalse(modelo.puedePagar(lectura))
            XCTAssertNil(modelo.pagar(lectura) { _ in llamadas += 1; return true })
            modelo.reanudar()
            modelo.simularLectura()
            XCTAssertNil(modelo.resultado)
        }
        modelo.simularLectura()
        observador.cancel()
        let lectura = try XCTUnwrap(modelo.resultado)
        XCTAssertEqual(emitida?.id, lectura.id)
        XCTAssertEqual(avisos, 1)
        XCTAssertEqual(llamadas, 0)
        XCTAssertFalse(modelo.pagoRealizado)
        XCTAssertTrue(modelo.puedePagar(lectura))
        XCTAssertEqual(modelo.pagar(lectura) { _ in llamadas += 1; return true }, true)
        XCTAssertEqual(llamadas, 1)
        XCTAssertFalse(modelo.camara.sesion.isRunning)
    }

    private func ejemplo(en modelo: EscanerQRModel) throws -> ResultadoQR {
        modelo.simularLectura()
        return try XCTUnwrap(modelo.resultado)
    }

    private func leer(_ texto: String, en modelo: EscanerQRModel) async throws -> ResultadoQR {
        let recibida = expectation(description: "Lectura QR por el puente de cámara sin captura")
        let observador = modelo.$resultado.compactMap { $0 }.prefix(1).sink { _ in
            recibida.fulfill()
        }
        modelo.camara.alLeer?(texto)
        await fulfillment(of: [recibida], timeout: 2)
        observador.cancel()
        return try XCTUnwrap(modelo.resultado)
    }

    private func snapshot() -> NSDictionary {
        NSDictionary(dictionary: defaults.persistentDomain(forName: dominio) ?? [:])
    }
}
