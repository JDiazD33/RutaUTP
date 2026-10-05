//
//  QRCurrencyAndAmountTests.swift
//  RutaUTPTests
//
//  E13: validar moneda e importe antes del callback y comunicar el motivo
//  del rechazo. Preferencias aisladas; no se inicia la cámara ni se paga real.
//

import XCTest
import Combine
@testable import RutaUTP

@MainActor
final class QRCurrencyAndAmountTests: XCTestCase {
    private var dominio: String!
    private var defaults: UserDefaults!
    private let llaveSaldo = "monedero.saldo.v1"
    private let llaveMovimientos = "monedero.movimientos.v1"

    override func setUp() {
        super.setUp()
        dominio = "RutaUTPTests.QRCurrencyAndAmount.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: dominio)!
        defaults.removePersistentDomain(forName: dominio)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: dominio)
        defaults = nil
        dominio = nil
        super.tearDown()
    }

    func testAliasDeSolesNormalizadosAdmitenReferenciaEnAmbosFormatos() {
        for moneda in ["PEN", "pen", "PeN", "604", "  PEN  ", "\t604\t"] {
            for texto in codigos(moneda: moneda) {
                let resultado = leer(texto)
                XCTAssertTrue(resultado.campos.esPago)
                XCTAssertFalse(resultado.campos.monedaInvalida)
                XCTAssertTrue(["PEN", "604"].contains(resultado.campos.monedaNormalizada ?? ""))
                XCTAssertNil(resultado.errorParaPagoDemo)
                XCTAssertEqual(resultado.importeParaPagoDemo, MonederoStore.tarifaReferencia)
            }
        }
    }

    func testAliasDeSolesAdmitenImporteExplicitoSinConvertirMoneda() {
        for moneda in ["PEN", "pen", "604", "  pEn  ", "\t604\t"] {
            for texto in codigos(moneda: moneda, importe: "3.75") {
                let resultado = leer(texto)
                var entregados: [Double] = []
                XCTAssertNil(resultado.errorParaPagoDemo)
                XCTAssertEqual(resultado.importeParaPagoDemo, 3.75)
                XCTAssertEqual(resultado.pagarDemo { entregados.append($0); return true }, true)
                XCTAssertEqual(entregados, [3.75])
            }
        }
    }

    func testAusenciaDeMonedaConservaCompatibilidadSoloEnQREstatico() {
        for texto in codigos(moneda: nil) {
            let resultado = leer(texto)
            XCTAssertNil(resultado.campos.moneda)
            XCTAssertNil(resultado.campos.monedaNormalizada)
            XCTAssertNil(resultado.errorParaPagoDemo)
            XCTAssertEqual(resultado.importeParaPagoDemo, MonederoStore.tarifaReferencia)
        }
        for texto in codigos(moneda: nil, importe: "2.50") {
            assertRechazo(texto, error: .monedaNoIndicada)
        }
    }

    func testMonedaDeclaradaVaciaNoSeConfundeConAusenciaEstatica() {
        for moneda in ["", " ", "\t  \t"] {
            for importe in [nil, "2.50"] as [String?] {
                for texto in codigos(moneda: moneda, importe: importe) {
                    let resultado = leer(texto)
                    XCTAssertNotNil(resultado.campos.moneda)
                    assertRechazo(resultado, error: .monedaNoIndicada)
                }
            }
        }
    }

    func testMonedasAjenasNoAdmitenPagoEstaticoNiExplicito() {
        for moneda in ["USD", "usd", "840", "EUR", "978", "S/", "SOLES", "P E N", "0604"] {
            for importe in [nil, "2.50"] as [String?] {
                for texto in codigos(moneda: moneda, importe: importe) {
                    assertRechazo(texto, error: .monedaNoAdmitida)
                }
            }
        }
    }

    func testMonedaDemoDuplicadaEsAmbiguaAunqueValoresCoincidanOUltimoSeaValido() {
        for filas in ["moneda: PEN\nmoneda: PEN", "moneda: USD\nmoneda: PEN",
                      "moneda: PEN\nmoneda: USD", "moneda:\nmoneda: PEN",
                      "moneda: PEN\n MONEDA : 604", "moneda: USD\nmoneda: PEN\nmoneda: PEN"] {
            for importe in [nil, "2.50"] as [String?] {
                var texto = "DEMO YAPO\n" + filas
                if let importe { texto += "\nimporte: " + importe }
                let resultado = leer(texto)
                XCTAssertTrue(resultado.campos.esPago)
                XCTAssertTrue(resultado.campos.monedaInvalida)
                assertRechazo(resultado, error: .monedaAmbigua)
            }
        }
    }

    func testMonedaTLVDuplicadaSigueRechazandoEstructuraCompletaE11() {
        for repetida in ["604", "PEN", "840", ""] {
            let texto = tlv("00", "01") + tlv("53", "604") + tlv("53", repetida)
                + tlv("54", "2.50") + tlv("63", "0000")
            XCTAssertFalse(leer(texto).campos.esPago)
            assertRechazo(texto, error: .formatoNoReconocido)
        }
    }

    func testNormalizacionDeMonedaNoReescribeTextoNiDatoLeido() {
        let texto = codigoTLV(moneda: " \tpeN\n", importe: "2.50")
        let resultado = leer(texto)
        XCTAssertEqual(resultado.texto, texto)
        XCTAssertEqual(resultado.campos.moneda, " \tpeN\n")
        XCTAssertEqual(resultado.campos.monedaNormalizada, "PEN")
        XCTAssertNil(resultado.errorParaPagoDemo)
        XCTAssertEqual(resultado.campos.importeTexto, "S/ 2.50")
    }

    func testValoresNumericosInvalidosNoLleganAlCallbackEnAmbosFormatos() {
        for importe in ["nan", "inf", "-inf", "0", "-0.0", "-2.50", "2.501",
                        "0.001", "0.000000000000000001", "1000000.01", "1e308"] {
            for texto in codigos(moneda: "PEN", importe: importe) {
                let resultado = leer(texto)
                XCTAssertTrue(resultado.campos.esPago)
                XCTAssertFalse(resultado.campos.importeInvalido)
                assertRechazo(resultado, error: .importeInvalido)
            }
        }
    }

    func testImporteIlegibleConservaDiagnosticoYNoCaeEnReferencia() {
        for importe in ["", "dos soles", "S/ 2.50", "2.50 extra"] {
            for texto in codigos(moneda: "PEN", importe: importe) {
                XCTAssertTrue(leer(texto).campos.importeInvalido)
                assertRechazo(texto, error: .importeIlegible)
            }
        }
    }

    func testLimitesValidosDeCentimosIncluyenMinimoYMaximoDeDemo() {
        for importe in [0.01, 0.10, 0.29, 3.75, 999_999.99, 1_000_000.0] {
            XCTAssertEqual(MonederoStore.importeValidoParaPasaje(importe), importe)
        }
    }

    func testLimitesInvalidosNoSeRedondeanParaCobrarOtroImporte() {
        for importe in [Double.nan, Double.infinity, -Double.infinity,
                        0, -0.0, -0.01, 0.001, 2.501, 1_000_000.01,
                        Double.greatestFiniteMagnitude] {
            XCTAssertNil(MonederoStore.importeValidoParaPasaje(importe))
        }
    }

    func testErrorBinarioDeDoubleSeCanonizaAntesDelCallback() {
        let importe = 0.1 + 0.2
        XCTAssertNotEqual(importe, 0.3)
        XCTAssertEqual(MonederoStore.importeValidoParaPasaje(importe), 0.3)
        var campos = PagoQR.CamposQR(esPago: true)
        campos.moneda = "PEN"
        campos.importe = importe
        let resultado = ResultadoQR(texto: "importe binario de prueba", campos: campos)
        var recibidos: [Double] = []
        XCTAssertEqual(resultado.importeParaPagoDemo, 0.3)
        XCTAssertEqual(resultado.pagarDemo { recibidos.append($0); return true }, true)
        XCTAssertEqual(recibidos, [0.3])
    }

    func testToleranciaSoloAdmiteRuidoMenorAUnaMillonesimaDeCentimo() {
        for importe in ["1.230000005", "1.229999995"] {
            for texto in codigos(moneda: "604", importe: importe) {
                let resultado = leer(texto)
                XCTAssertNil(resultado.errorParaPagoDemo)
                XCTAssertEqual(resultado.importeParaPagoDemo, 1.23)
                var recibidos: [Double] = []
                XCTAssertEqual(resultado.pagarDemo { recibidos.append($0); return true }, true)
                XCTAssertEqual(recibidos, [1.23])
                XCTAssertEqual(resultado.campos.importeTexto, "S/ 1.23")
            }
        }
        for importe in ["1.23000002", "1.22999998"] {
            for texto in codigos(moneda: "604", importe: importe) {
                assertRechazo(texto, error: .importeInvalido)
            }
        }
    }

    func testImporteTextoInvalidoNoPresentaNanInfNiRedondeaUnaFraccion() throws {
        let referencia = try XCTUnwrap(leer(codigoDemo(moneda: "PEN", importe: "2.501")).campos.importeTexto)
        XCTAssertFalse(referencia.isEmpty)
        for importe in ["nan", "inf", "-inf", "0", "-2.50", "2.501", "0.001", "1000000.01"] {
            for texto in codigos(moneda: "PEN", importe: importe) {
                XCTAssertEqual(leer(texto).campos.importeTexto, referencia)
            }
        }
        for texto in codigos(moneda: "PEN") {
            XCTAssertNil(leer(texto).campos.importeTexto)
        }
    }

    func testReglasDeRechazoTienenMensajesPresentablesYDistintos() {
        let errores: [ErrorPagoQR] = [.formatoNoReconocido, .importeIlegible,
                                     .monedaAmbigua, .monedaNoIndicada,
                                     .monedaNoAdmitida, .importeInvalido]
        XCTAssertTrue(errores.allSatisfy { !$0.mensaje.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        XCTAssertEqual(Set(errores.map(\.mensaje)).count, errores.count)
        let erroresCobro: [ErrorCobroPasaje] = [.datosLocalesInvalidos, .importeInvalido, .saldoInsuficiente]
        XCTAssertTrue(erroresCobro.allSatisfy { !$0.mensaje.isEmpty })
        XCTAssertEqual(Set(erroresCobro.map(\.mensaje)).count, erroresCobro.count)
    }

    func testDiagnosticoPriorizaFormatoYDatosAmbiguosAntesDeMonedaOMonto() {
        var campos = PagoQR.CamposQR(esPago: false)
        campos.importe = 2.501
        campos.importeInvalido = true
        campos.moneda = "USD"
        campos.monedaInvalida = true
        assertRechazo(ResultadoQR(texto: "inválido", campos: campos), error: .formatoNoReconocido)
        campos.esPago = true
        assertRechazo(ResultadoQR(texto: "importe ambiguo", campos: campos), error: .importeIlegible)
        campos.importeInvalido = false
        assertRechazo(ResultadoQR(texto: "moneda ambigua", campos: campos), error: .monedaAmbigua)
        campos.monedaInvalida = false
        assertRechazo(ResultadoQR(texto: "moneda ajena", campos: campos), error: .monedaNoAdmitida)
        campos.moneda = "PEN"
        assertRechazo(ResultadoQR(texto: "fracción de céntimo", campos: campos), error: .importeInvalido)
    }

    func testRechazosDeMonedaYImporteNoCambianSaldoHistorialNiBytes() throws {
        let store = MonederoStore(defaults: defaults)
        XCTAssertTrue(store.recargar(1))
        let original = snapshot()
        let movimientos = store.movimientos
        let bytes = try XCTUnwrap(defaults.data(forKey: llaveMovimientos))
        let textos = codigos(moneda: "USD", importe: "2.50")
            + codigos(moneda: nil, importe: "2.50")
            + codigos(moneda: "", importe: "2.50")
            + codigos(moneda: "PEN", importe: "nan")
            + codigos(moneda: "PEN", importe: "2.501")
            + ["DEMO YAPO\nmoneda: USD\nmoneda: PEN\nimporte: 2.50"]
        var llamadas = 0
        for texto in textos {
            XCTAssertNil(leer(texto).pagarDemo { importe in
                llamadas += 1
                return store.cobrarPasaje(importe)
            })
        }
        XCTAssertEqual(llamadas, 0)
        XCTAssertEqual(store.saldo, 11)
        XCTAssertEqual(store.movimientos, movimientos)
        XCTAssertEqual(defaults.data(forKey: llaveMovimientos), bytes)
        XCTAssertTrue(snapshot().isEqual(original))
    }

    func testPagoCanonicoConservaClavesHistorialIdentidadYRecargaDelStore() throws {
        let store = MonederoStore(defaults: defaults)
        let resultado = leer(codigoTLV(moneda: "  pEn  ", importe: "1.230000005"))
        var recibidos: [Double] = []
        XCTAssertEqual(resultado.pagarDemo { importe in
            recibidos.append(importe)
            return store.cobrarPasaje(importe)
        }, true)
        XCTAssertEqual(recibidos, [1.23])
        XCTAssertEqual(store.saldo, 8.77)
        XCTAssertEqual(store.movimientos.map(\.importe), [-1.23])
        XCTAssertEqual(defaults.double(forKey: llaveSaldo), 8.77)
        let bytes = try XCTUnwrap(defaults.data(forKey: llaveMovimientos))
        XCTAssertEqual(try JSONDecoder().decode([MovimientoMonedero].self, from: bytes), store.movimientos)
        XCTAssertEqual(Set((defaults.persistentDomain(forName: dominio) ?? [:]).keys),
                       Set([llaveSaldo, llaveMovimientos]))
        let recargado = MonederoStore(defaults: defaults)
        XCTAssertFalse(recargado.datosLocalesInvalidos)
        XCTAssertEqual(recargado.saldo, store.saldo)
        XCTAssertEqual(recargado.movimientos, store.movimientos)
    }

    func testDiagnosticoDeImporteValidoNoEscribeNiDebitaHastaCobrar() {
        let store = MonederoStore(defaults: defaults)
        let original = snapshot()
        for importe in [0.01, 0.1 + 0.2, 2.50, 10.0] {
            XCTAssertNil(store.errorParaCobrarPasaje(importe))
        }
        XCTAssertEqual(store.saldo, 10)
        XCTAssertTrue(store.movimientos.isEmpty)
        XCTAssertTrue(snapshot().isEqual(original))
    }

    func testImporteInvalidoSeDistingueDeSaldoInsuficienteSinMutaciones() {
        defaults.set(1.25, forKey: llaveSaldo)
        let store = MonederoStore(defaults: defaults)
        let original = snapshot()
        for importe in [Double.nan, Double.infinity, -2.50, 0, 2.501, 1_000_000.01] {
            XCTAssertEqual(store.errorParaCobrarPasaje(importe), .importeInvalido)
            XCTAssertFalse(store.cobrarPasaje(importe))
        }
        for importe in [2.50, 10.0, 1_000_000.0] {
            XCTAssertEqual(store.errorParaCobrarPasaje(importe), .saldoInsuficiente)
            XCTAssertFalse(store.cobrarPasaje(importe))
        }
        XCTAssertEqual(store.saldo, 1.25)
        XCTAssertTrue(store.movimientos.isEmpty)
        XCTAssertTrue(snapshot().isEqual(original))
    }

    func testHistorialCorruptoTienePrioridadYConservaBytesOriginales() {
        let bytes = Data("[{\"id\":".utf8)
        defaults.set(10.0, forKey: llaveSaldo)
        defaults.set(bytes, forKey: llaveMovimientos)
        let original = snapshot()
        let store = MonederoStore(defaults: defaults)
        for importe in [2.50, 1_000_000.0, Double.nan, -1.0, 0, 2.501] {
            XCTAssertEqual(store.errorParaCobrarPasaje(importe), .datosLocalesInvalidos)
            XCTAssertFalse(store.cobrarPasaje(importe))
        }
        XCTAssertTrue(store.datosLocalesInvalidos)
        XCTAssertTrue(store.movimientos.isEmpty)
        XCTAssertEqual(defaults.data(forKey: llaveMovimientos), bytes)
        XCTAssertTrue(snapshot().isEqual(original))
    }

    func testSaldoCeroPersistidoSigueValidoYRecargaHabilitaCobro() {
        defaults.set(0.0, forKey: llaveSaldo)
        defaults.set(Data("[]".utf8), forKey: llaveMovimientos)
        let original = snapshot()
        let store = MonederoStore(defaults: defaults)
        XCTAssertFalse(store.datosLocalesInvalidos)
        XCTAssertEqual(store.saldo, 0)
        XCTAssertEqual(store.errorParaCobrarPasaje(0.01), .saldoInsuficiente)
        XCTAssertFalse(store.cobrarPasaje(0.01))
        XCTAssertTrue(snapshot().isEqual(original))
        XCTAssertTrue(store.recargar(2.50))
        XCTAssertNil(store.errorParaCobrarPasaje(2.50))
        XCTAssertTrue(store.cobrarPasaje(2.50))
        XCTAssertEqual(store.saldo, 0)
        XCTAssertEqual(store.movimientos.map(\.importe), [-2.50, 2.50])
        let recargado = MonederoStore(defaults: defaults)
        XCTAssertFalse(recargado.datosLocalesInvalidos)
        XCTAssertEqual(recargado.saldo, 0)
        XCTAssertEqual(recargado.movimientos, store.movimientos)
    }

    func testModeloRechazaMonedaSinConsumirYDespuesAdmiteNuevaLectura() async throws {
        let store = MonederoStore(defaults: defaults)
        let original = snapshot()
        let modelo = EscanerQRModel()
        defer { modelo.detener() }
        let invalida = try await leer(codigoDemo(moneda: "USD", importe: "2.50"), en: modelo)
        var llamadas = 0
        XCTAssertFalse(modelo.puedePagar(invalida))
        XCTAssertNil(modelo.pagar(invalida) { importe in
            llamadas += 1
            return store.cobrarPasaje(importe)
        })
        XCTAssertEqual(llamadas, 0)
        XCTAssertFalse(modelo.pagoRealizado)
        XCTAssertTrue(snapshot().isEqual(original))
        modelo.reanudar()
        let valida = try await leer(codigoDemo(moneda: "pen", importe: "2.50"), en: modelo)
        XCTAssertNotEqual(valida.id, invalida.id)
        XCTAssertNil(modelo.pagar(invalida) { _ in llamadas += 1; return true })
        XCTAssertEqual(modelo.pagar(valida) { importe in
            llamadas += 1
            return store.cobrarPasaje(importe)
        }, true)
        XCTAssertEqual(llamadas, 1)
        XCTAssertEqual(store.saldo, 7.50)
        XCTAssertTrue(modelo.pagoRealizado)
        XCTAssertFalse(modelo.camara.sesion.isRunning)
    }

    func testModeloRechazaImporteSinConsumirYNuevaLecturaCanonicaPagaUnaVez() async throws {
        let store = MonederoStore(defaults: defaults)
        let original = snapshot()
        let modelo = EscanerQRModel()
        defer { modelo.detener() }
        let invalida = try await leer(codigoTLV(moneda: "604", importe: "2.501"), en: modelo)
        var recibidos: [Double] = []
        XCTAssertFalse(modelo.puedePagar(invalida))
        XCTAssertNil(modelo.pagar(invalida) { recibidos.append($0); return true })
        XCTAssertFalse(modelo.pagoRealizado)
        XCTAssertTrue(snapshot().isEqual(original))
        modelo.reanudar()
        let valida = try await leer(codigoTLV(moneda: "604", importe: "1.230000005"), en: modelo)
        XCTAssertEqual(modelo.pagar(valida) { importe in
            recibidos.append(importe)
            return store.cobrarPasaje(importe)
        }, true)
        XCTAssertNil(modelo.pagar(valida) { recibidos.append($0); return true })
        XCTAssertEqual(recibidos, [1.23])
        XCTAssertEqual(store.saldo, 8.77)
        XCTAssertEqual(store.movimientos.map(\.importe), [-1.23])
        XCTAssertTrue(modelo.pagoRealizado)
        XCTAssertFalse(modelo.camara.sesion.isRunning)
    }

    func testRechazoPorSaldoPermiteReintentoTrasRecargarYSoloExitoConsume() async throws {
        defaults.set(1.25, forKey: llaveSaldo)
        let store = MonederoStore(defaults: defaults)
        let modelo = EscanerQRModel()
        defer { modelo.detener() }
        let lectura = try await leer(codigoDemo(moneda: "  pen  ", importe: "2.50"), en: modelo)
        XCTAssertNil(lectura.errorParaPagoDemo)
        XCTAssertEqual(store.errorParaCobrarPasaje(lectura.importeParaPagoDemo ?? -1), .saldoInsuficiente)
        XCTAssertEqual(modelo.pagar(lectura) { store.cobrarPasaje($0) }, false)
        XCTAssertFalse(modelo.pagoRealizado)
        XCTAssertTrue(modelo.puedePagar(lectura))
        XCTAssertTrue(store.recargar(5))
        XCTAssertNil(store.errorParaCobrarPasaje(2.50))
        XCTAssertEqual(modelo.pagar(lectura) { store.cobrarPasaje($0) }, true)
        let pagado = snapshot()
        var llamadasAdicionales = 0
        XCTAssertNil(modelo.pagar(lectura) { _ in llamadasAdicionales += 1; return true })
        XCTAssertEqual(llamadasAdicionales, 0)
        XCTAssertTrue(snapshot().isEqual(pagado))
        XCTAssertEqual(store.saldo, 3.75)
        XCTAssertEqual(store.movimientos.map(\.importe), [-2.50, 5])
    }

    func testNuevoViajeConMismoQREstaticoNormalizadoConservaReglaE12() async throws {
        let store = MonederoStore(defaults: defaults)
        let modelo = EscanerQRModel()
        defer { modelo.detener() }
        let texto = codigoTLV(moneda: " 604 ")
        let primera = try await leer(texto, en: modelo)
        XCTAssertEqual(modelo.pagar(primera) { store.cobrarPasaje($0) }, true)
        XCTAssertNil(modelo.pagar(primera) { store.cobrarPasaje($0) })
        modelo.reanudar()
        let segunda = try await leer(texto, en: modelo)
        XCTAssertEqual(primera.texto, segunda.texto)
        XCTAssertEqual(primera.campos, segunda.campos)
        XCTAssertNotEqual(primera.id, segunda.id)
        XCTAssertNil(modelo.pagar(primera) { store.cobrarPasaje($0) })
        XCTAssertEqual(modelo.pagar(segunda) { store.cobrarPasaje($0) }, true)
        XCTAssertNil(modelo.pagar(segunda) { store.cobrarPasaje($0) })
        XCTAssertEqual(store.saldo, 5)
        XCTAssertEqual(store.movimientos.count, 2)
        XCTAssertEqual(Set(store.movimientos.map(\.id)).count, 2)
        XCTAssertFalse(modelo.camara.sesion.isRunning)
    }

    private func leer(_ texto: String) -> ResultadoQR {
        ResultadoQR(texto: texto, campos: PagoQR.leer(texto))
    }

    private func leer(_ texto: String, en modelo: EscanerQRModel) async throws -> ResultadoQR {
        let recibida = expectation(description: "Lectura sin configurar la cámara")
        let observador = modelo.$resultado.compactMap { $0 }.prefix(1).sink { _ in
            recibida.fulfill()
        }
        modelo.camara.alLeer?(texto)
        await fulfillment(of: [recibida], timeout: 2)
        observador.cancel()
        return try XCTUnwrap(modelo.resultado)
    }

    private func assertRechazo(_ texto: String, error: ErrorPagoQR,
                               file: StaticString = #filePath, line: UInt = #line) {
        assertRechazo(leer(texto), error: error, file: file, line: line)
    }

    private func assertRechazo(_ resultado: ResultadoQR, error: ErrorPagoQR,
                               file: StaticString = #filePath, line: UInt = #line) {
        var llamadas = 0
        XCTAssertEqual(resultado.errorParaPagoDemo, error, file: file, line: line)
        XCTAssertNil(resultado.importeParaPagoDemo, file: file, line: line)
        XCTAssertNil(resultado.pagarDemo { _ in llamadas += 1; return true }, file: file, line: line)
        XCTAssertEqual(llamadas, 0, file: file, line: line)
    }

    private func snapshot() -> NSDictionary {
        NSDictionary(dictionary: defaults.persistentDomain(forName: dominio) ?? [:])
    }

    private func codigos(moneda: String?, importe: String? = nil) -> [String] {
        let demo = codigoDemo(moneda: moneda, importe: importe)
        return [demo, demo.replacingOccurrences(of: "DEMO YAPO", with: "DEMO PLUN"),
                codigoTLV(moneda: moneda, importe: importe)]
    }

    private func codigoDemo(moneda: String?, importe: String? = nil) -> String {
        var filas = ["DEMO YAPO", "titular: Cuenta demo"]
        if let moneda { filas.append("moneda: " + moneda) }
        if let importe { filas.append("importe: " + importe) }
        return filas.joined(separator: "\n")
    }

    private func codigoTLV(moneda: String?, importe: String? = nil) -> String {
        var texto = tlv("00", "01") + tlv("59", "Cuenta demo")
        if let moneda { texto += tlv("53", moneda) }
        if let importe { texto += tlv("54", importe) }
        return texto + tlv("63", "0000")
    }

    private func tlv(_ identificador: String, _ valor: String) -> String {
        precondition(valor.utf8.count < 100)
        return identificador + String(format: "%02d", valor.utf8.count) + valor
    }
}
