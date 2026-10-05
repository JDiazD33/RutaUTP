//
//  QRPaymentEligibilityTests.swift
//  RutaUTPTests
//
//  E11: una lectura ajena o incompleta no puede convertirse en un cobro de
//  referencia. Cada monedero usa preferencias aisladas de la instalación.
//

import XCTest
@testable import RutaUTP

@MainActor
final class QRPaymentEligibilityTests: XCTestCase {
    private var dominio: String!
    private var defaults: UserDefaults!
    private let llaveSaldo = "monedero.saldo.v1"
    private let llaveMovimientos = "monedero.movimientos.v1"

    override func setUp() {
        super.setUp()
        dominio = "RutaUTPTests.QRPaymentEligibility.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: dominio)!
        defaults.removePersistentDomain(forName: dominio)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: dominio)
        defaults = nil
        dominio = nil
        super.tearDown()
    }

    func testURLsTextoHTMLYUnicodeAjenosNoAdmitenPagoNiInvocanCallback() {
        let textos = [
            "https://ejemplo.invalid/pagar?importe=2.50",
            "Texto sin estructura de pago",
            "<html><body>importe: 2.50</body></html>",
            "Ruta a la universidad 🚌 — información pública",
            "DEMO WALLET\ntitular: Persona\nimporte: 2.50",
            "DEMO \ntitular: Persona\nimporte: 2.50",
            ""
        ]
        for texto in textos {
            assertNoAdmitePago(texto)
        }
    }

    func testResultadoNoDePagoRechazaImportePresenteSinLlamarCallback() {
        let campos = PagoQR.CamposQR(importe: 3.75, esPago: false)
        let resultado = ResultadoQR(texto: "importe: 3.75", campos: campos)
        var llamadas = 0

        XCTAssertNil(resultado.importeParaPagoDemo)
        XCTAssertNil(resultado.pagarDemo { _ in llamadas += 1; return true })
        XCTAssertEqual(llamadas, 0)
    }

    func testResultadoPagoConImporteInvalidoNoCaeEnTarifaReferencia() {
        let campos = PagoQR.CamposQR(importeInvalido: true, esPago: true)
        let resultado = ResultadoQR(texto: "importe ilegible", campos: campos)
        var llamadas = 0

        XCTAssertNil(resultado.importeParaPagoDemo)
        XCTAssertNil(resultado.pagarDemo { _ in llamadas += 1; return true })
        XCTAssertEqual(llamadas, 0)
    }

    func testDemoYapoEstaticoAdmiteTarifaDeReferenciaYConservaDatos() {
        let texto = PagoQR.cargaUtil()
        let resultado = leer(texto)
        XCTAssertTrue(resultado.campos.esPago)
        XCTAssertTrue(resultado.campos.esDemo)
        XCTAssertFalse(resultado.campos.importeInvalido)
        XCTAssertEqual(resultado.campos.billetera, "Yapo")
        XCTAssertEqual(resultado.campos.titular, "Joaquin Diaz")
        XCTAssertEqual(resultado.campos.celular, "999888777")
        XCTAssertEqual(resultado.campos.ciudad, "Trujillo")
        XCTAssertEqual(resultado.campos.moneda, "PEN")
        XCTAssertNil(resultado.campos.importe)
        XCTAssertEqual(resultado.texto, texto)
        XCTAssertEqual(resultado.importeParaPagoDemo, MonederoStore.tarifaReferencia)
        var recibido: Double?
        XCTAssertEqual(resultado.pagarDemo { recibido = $0; return true }, true)
        XCTAssertEqual(recibido, MonederoStore.tarifaReferencia)
    }

    func testDemoPlunEstaticoAdmiteTarifaDeReferencia() {
        let cuenta = CuentaCobro(titular: "Ana López", celular: "912345678",
                                ciudad: "Trujillo", billetera: .plin)
        let resultado = leer(PagoQR.cargaUtil(cuenta: cuenta))
        XCTAssertTrue(resultado.campos.esPago)
        XCTAssertTrue(resultado.campos.esDemo)
        XCTAssertEqual(resultado.campos.billetera, "Plun")
        XCTAssertEqual(resultado.campos.titular, "Ana Lopez")
        XCTAssertEqual(resultado.importeParaPagoDemo, MonederoStore.tarifaReferencia)
    }

    func testAmbasBilleterasConImporteExplicitoLoEntreganExactamente() {
        for billetera in BilleteraPago.allCases {
            let cuenta = CuentaCobro(titular: "Cuenta demo", celular: "999888777",
                                    ciudad: "Trujillo", billetera: billetera)
            let resultado = leer(PagoQR.cargaUtil(cuenta: cuenta, importe: 3.75))
            var importes: [Double] = []
            XCTAssertEqual(resultado.campos.importe, 3.75)
            XCTAssertEqual(resultado.importeParaPagoDemo, 3.75)
            XCTAssertEqual(resultado.pagarDemo { importes.append($0); return true }, true)
            XCTAssertEqual(importes, [3.75])
        }
    }

    func testGeneracionDemoSigueEnASCIIYLaLecturaConservaCuenta() {
        let cuenta = CuentaCobro(titular: "José Núñez 🚌", celular: "912345678",
                                ciudad: "Huanchacó", billetera: .plin)
        let texto = PagoQR.cargaUtil(cuenta: cuenta, importe: 4.20)
        XCTAssertTrue(texto.utf8.allSatisfy { $0 < 128 })
        let resultado = leer(texto)
        XCTAssertTrue(resultado.campos.esPago)
        XCTAssertEqual(resultado.campos.titular, "Jose Nunez")
        XCTAssertEqual(resultado.campos.celular, cuenta.celular)
        XCTAssertEqual(resultado.campos.ciudad, "Huanchaco")
        XCTAssertEqual(resultado.importeParaPagoDemo, 4.20)
    }

    func testDemoConImporteVacioNoPuedeCobrarTarifaReferencia() {
        for fila in ["importe:", "importe:   "] {
            let resultado = leer(demo + "\n" + fila)
            XCTAssertTrue(resultado.campos.importeInvalido)
            assertNoAdmitePago(resultado)
        }
    }

    func testDemoConImporteIlegibleNoPuedeCobrarTarifaReferencia() {
        for valor in ["dos soles", "S/ 2.50", "2.50 extra"] {
            let resultado = leer(demo + "\nimporte: " + valor)
            XCTAssertTrue(resultado.campos.importeInvalido)
            assertNoAdmitePago(resultado)
        }
    }

    func testDemoConImporteDuplicadoNoEscogeUnoNiAplicaReferencia() {
        for filas in ["importe: 2.50\nimporte: 3.75",
                      "importe: 2.50\nimporte: 2.50",
                      "importe: ilegible\nimporte: 2.50",
                      "importe: 2.50\n IMPORTE : 3.75"] {
            let resultado = leer(demo + "\n" + filas)
            XCTAssertTrue(resultado.campos.importeInvalido)
            assertNoAdmitePago(resultado)
        }
    }

    func testDemoConFilaMalformadaNoAdmitePago() {
        for fila in ["importe 2.50", "titular sin separador", ": sin clave"] {
            assertNoAdmitePago(demo + "\n" + fila)
        }
    }

    func testCabeceraDemoDesconocidaNoSeAdmiteAunqueRestoSeaValido() {
        for cabecera in ["DEMO YAPE", "DEMO PLIN", "DEMO YAPO EXTRA", "DEMO OTRA"] {
            let texto = demo.replacingOccurrences(of: "DEMO YAPO", with: cabecera)
            assertNoAdmitePago(texto)
        }
    }

    func testDemoEstaticoConMetadataOpcionalOVaciaSigueSiendoAdmitido() {
        for texto in ["DEMO YAPO", "DEMO PLUN\ntitular:\nciudad:\ncelular:",
                      demo + "\nreferencia: Viaje de prueba"] {
            let resultado = leer(texto)
            XCTAssertTrue(resultado.campos.esPago)
            XCTAssertTrue(resultado.campos.esDemo)
            XCTAssertFalse(resultado.campos.importeInvalido)
            XCTAssertEqual(resultado.importeParaPagoDemo, MonederoStore.tarifaReferencia)
        }
    }

    func testTLVEstaticoIntegroAdmiteReferenciaYConservaCamposUTF8() {
        let texto = pagoTLV()
        let resultado = leer(texto)
        XCTAssertTrue(resultado.campos.esPago)
        XCTAssertFalse(resultado.campos.esDemo)
        XCTAssertFalse(resultado.campos.importeInvalido)
        XCTAssertEqual(resultado.campos.titular, "Joaquín Díaz")
        XCTAssertEqual(resultado.campos.ciudad, "Trujillo")
        XCTAssertEqual(resultado.campos.pais, "PE")
        XCTAssertEqual(resultado.campos.moneda, "604")
        XCTAssertEqual(resultado.campos.celular, "999888777")
        XCTAssertNil(resultado.campos.importe)
        XCTAssertEqual(resultado.importeParaPagoDemo, MonederoStore.tarifaReferencia)
        var recibido: Double?
        XCTAssertEqual(resultado.pagarDemo { recibido = $0; return true }, true)
        XCTAssertEqual(recibido, MonederoStore.tarifaReferencia)
    }

    func testTLVConImporteExplicitoYNombreUnicodeAdmiteMontoExacto() {
        let texto = pagoTLV(importe: "4.20", titular: "María Núñez 🚌")
        let resultado = leer(texto)
        XCTAssertTrue(resultado.campos.esPago)
        XCTAssertEqual(resultado.campos.titular, "María Núñez 🚌")
        XCTAssertEqual(resultado.campos.importe, 4.20)
        var importes: [Double] = []
        XCTAssertEqual(resultado.pagarDemo { importes.append($0); return true }, true)
        XCTAssertEqual(importes, [4.20])
    }

    func testTLVConColaAjenaOCampoTruncadoNoAdmitePagoParcial() {
        let valido = pagoTLV(importe: "2.50")
        for cola in ["x", "59", "5999abc", "AB00", "59+2ab", "59-0"] {
            assertNoAdmitePago(valido + cola)
        }
    }

    func testTLVExigeVersionYMarcadorDeLongitudCuatro() {
        let base = tlv("59", "Cuenta") + tlv("53", "604")
        for texto in [base + tlv("63", "0000"),
                      tlv("00", "02") + base + tlv("63", "0000"),
                      tlv("00", "01") + base,
                      tlv("00", "01") + base + tlv("63", "abc"),
                      tlv("00", "01") + base + tlv("63", "abcde"),
                      tlv("00", "01") + base + "6304abc"] {
            assertNoAdmitePago(texto)
        }
    }

    func testTLVConIdentificadorOConteoNoDecimalASCIINoAdmitePago() {
        for bloque in ["A102xx", "-102xx", "599٩abcdefghij", "59+2xx", "59 2xx"] {
            assertNoAdmitePago(tlv("00", "01") + bloque + tlv("63", "0000"))
        }
    }

    func testTLVMarcadorCRCRequiereCuatroBytesHexadecimalesASCII() {
        let prefijo = tlv("00", "01") + tlv("59", "Cuenta demo")
        for marcador in ["ZZZZ", "+000", "0 00", "éé"] {
            assertNoAdmitePago(prefijo + tlv("63", marcador))
        }
        // Un marcador estructural con letras hex no promete autenticidad del QR.
        XCTAssertTrue(leer(prefijo + tlv("63", "aBcF")).campos.esPago)
    }

    func testTLVQueCortaBytesUTF8NoAdmitePago() {
        // José ocupa cinco bytes; una longitud de cuatro termina en el primer
        // byte de é. El prefijo reconocido no vuelve válida esa lectura.
        assertNoAdmitePago(tlv("00", "01") + "5904José" + tlv("63", "0000"))
    }

    func testTLVConCamposDuplicadosNoAdmitePago() {
        let prefijo = tlv("00", "01")
        let fin = tlv("63", "0000")
        for medio in [tlv("00", "01"),
                      tlv("59", "Uno") + tlv("59", "Dos"),
                      tlv("54", "2.50") + tlv("54", "3.75"),
                      tlv("63", "0000")] {
            assertNoAdmitePago(prefijo + medio + fin)
        }
    }

    func testTLVConCuentaInternaIncompletaODuplicadaNoAdmitePago() {
        for cuenta in ["0109999", tlv("01", "999888777") + "x",
                       tlv("01", "999888777") + tlv("01", "912345678")] {
            let texto = tlv("00", "01") + tlv("26", cuenta) + tlv("63", "0000")
            assertNoAdmitePago(texto)
        }
    }

    func testTLVConImporteVacioOIlegibleNoCaeEnReferencia() {
        for valor in ["", "dos soles", "S/ 2.50"] {
            let resultado = leer(pagoTLV(importe: valor))
            XCTAssertTrue(resultado.campos.importeInvalido)
            assertNoAdmitePago(resultado)
        }
    }

    func testAuxiliarTLVConservaLecturaDeCamposValidosEnBytesUTF8() {
        let texto = tlv("59", "María") + tlv("60", "Trujillo") + tlv("54", "2.50")
        XCTAssertEqual(PagoQR.camposTLV(texto),
                       ["59": "María", "60": "Trujillo", "54": "2.50"])
    }

    func testCallbackAdmitidoDevuelveRechazoSinConvertirloEnExito() {
        let resultado = leer(PagoQR.cargaUtil(importe: 3.75))
        var importes: [Double] = []
        XCTAssertEqual(resultado.pagarDemo { importes.append($0); return false }, false)
        XCTAssertEqual(importes, [3.75])
    }

    func testLecturasRechazadasConservanSaldoHistorialYBytesPersistidos() throws {
        let store = MonederoStore(defaults: defaults)
        XCTAssertTrue(store.recargar(1))
        let saldo = store.saldo
        let movimientos = store.movimientos
        let bytes = try XCTUnwrap(defaults.data(forKey: llaveMovimientos))
        let persistido = snapshot()
        let textos = ["https://ejemplo.invalid/", demo + "\nimporte:",
                      pagoTLV() + "resto", demo + "\nimporte: 2.50\nimporte: 3.75"]
        var llamadas = 0

        for texto in textos {
            let resultado = leer(texto)
            XCTAssertNil(resultado.pagarDemo { importe in
                llamadas += 1
                return store.cobrarPasaje(importe)
            })
        }
        XCTAssertEqual(llamadas, 0)
        XCTAssertEqual(store.saldo, saldo)
        XCTAssertEqual(store.movimientos, movimientos)
        XCTAssertEqual(defaults.data(forKey: llaveMovimientos), bytes)
        XCTAssertTrue(snapshot().isEqual(persistido))
    }

    func testPagoAdmitidoDebitaMontoExplicitoYRecargaConLasMismasClaves() throws {
        let store = MonederoStore(defaults: defaults)
        let resultado = leer(PagoQR.cargaUtil(importe: 3.75))
        XCTAssertEqual(resultado.pagarDemo { store.cobrarPasaje($0) }, true)
        XCTAssertEqual(store.saldo, 6.25)
        XCTAssertEqual(store.movimientos.count, 1)
        XCTAssertEqual(store.movimientos.first?.importe, -3.75)
        XCTAssertEqual(defaults.double(forKey: llaveSaldo), 6.25)
        let bytes = try XCTUnwrap(defaults.data(forKey: llaveMovimientos))
        let guardados = try JSONDecoder().decode([MovimientoMonedero].self, from: bytes)
        XCTAssertEqual(guardados, store.movimientos)
        XCTAssertEqual(Set((defaults.persistentDomain(forName: dominio) ?? [:]).keys),
                       Set([llaveSaldo, llaveMovimientos]))

        let recargado = MonederoStore(defaults: defaults)
        XCTAssertFalse(recargado.datosLocalesInvalidos)
        XCTAssertEqual(recargado.saldo, store.saldo)
        XCTAssertEqual(recargado.movimientos, store.movimientos)
        XCTAssertEqual(recargado.movimientos.first?.id, store.movimientos.first?.id)
    }

    func testPagoEstaticoAdmitidoDebitaSoloLaReferenciaDelMonedero() {
        let store = MonederoStore(defaults: defaults)
        let inicial = store.saldo
        let resultado = leer(PagoQR.cargaUtil())
        XCTAssertEqual(resultado.pagarDemo { store.cobrarPasaje($0) }, true)
        XCTAssertEqual(store.saldo, inicial - MonederoStore.tarifaReferencia)
        XCTAssertEqual(store.movimientos.first?.importe, -MonederoStore.tarifaReferencia)
    }

    func testSaldoInsuficienteEnPagoAdmitidoConservaEstadoYDatosPersistidos() {
        defaults.set(1.25, forKey: llaveSaldo)
        let store = MonederoStore(defaults: defaults)
        let persistido = snapshot()
        let resultado = leer(PagoQR.cargaUtil(importe: 3.75))
        XCTAssertEqual(resultado.pagarDemo { store.cobrarPasaje($0) }, false)
        XCTAssertEqual(store.saldo, 1.25)
        XCTAssertTrue(store.movimientos.isEmpty)
        XCTAssertTrue(snapshot().isEqual(persistido))
    }

    func testDatosCorruptosEnPagoAdmitidoConservanBytesOriginales() {
        let original = Data("[{\"id\":".utf8)
        defaults.set(10.0, forKey: llaveSaldo)
        defaults.set(original, forKey: llaveMovimientos)
        let persistido = snapshot()
        let store = MonederoStore(defaults: defaults)
        XCTAssertTrue(store.datosLocalesInvalidos)
        let resultado = leer(PagoQR.cargaUtil(importe: 2.50))
        XCTAssertEqual(resultado.pagarDemo { store.cobrarPasaje($0) }, false)
        XCTAssertEqual(defaults.data(forKey: llaveMovimientos), original)
        XCTAssertTrue(snapshot().isEqual(persistido))
        XCTAssertTrue(store.movimientos.isEmpty)
    }

    func testScannerDeEjemploEntregaPagoSinIniciarCapturaReal() throws {
        let modelo = EscanerQRModel()
        defer { modelo.detener() }
        XCTAssertNil(modelo.resultado)
        modelo.simularLectura()
        let resultado = try XCTUnwrap(modelo.resultado)
        XCTAssertEqual(resultado.texto, PagoQR.cargaUtil())
        XCTAssertTrue(resultado.campos.esDemo)
        XCTAssertEqual(resultado.importeParaPagoDemo, MonederoStore.tarifaReferencia)
        XCTAssertEqual(modelo.estado, .comprobando)
        XCTAssertFalse(modelo.camara.sesion.isRunning)
        // Una segunda entrega mientras está el resultado visible conserva la
        // lectura original; no solicita cámara ni vuelve a interpretar texto.
        modelo.simularLectura()
        XCTAssertEqual(modelo.resultado, resultado)
    }

    private var demo: String { PagoQR.cargaUtil() }

    private func leer(_ texto: String) -> ResultadoQR {
        ResultadoQR(texto: texto, campos: PagoQR.leer(texto))
    }

    private func assertNoAdmitePago(_ texto: String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        assertNoAdmitePago(leer(texto), file: file, line: line)
    }

    private func assertNoAdmitePago(_ resultado: ResultadoQR,
                                  file: StaticString = #filePath, line: UInt = #line) {
        var llamadas = 0
        XCTAssertNil(resultado.importeParaPagoDemo, file: file, line: line)
        XCTAssertNil(resultado.pagarDemo { _ in llamadas += 1; return true },
                     file: file, line: line)
        XCTAssertEqual(llamadas, 0, file: file, line: line)
    }

    private func snapshot() -> NSDictionary {
        NSDictionary(dictionary: defaults.persistentDomain(forName: dominio) ?? [:])
    }

    private func tlv(_ identificador: String, _ valor: String) -> String {
        precondition(valor.utf8.count < 100)
        return identificador + String(format: "%02d", valor.utf8.count) + valor
    }

    private func pagoTLV(importe: String? = nil, titular: String = "Joaquín Díaz") -> String {
        var texto = tlv("00", "01")
        texto += tlv("26", tlv("00", "DEMO") + tlv("01", "999888777"))
        texto += tlv("53", "604")
        if let importe { texto += tlv("54", importe) }
        texto += tlv("58", "PE")
        texto += tlv("59", titular)
        texto += tlv("60", "Trujillo")
        // E11 comprueba integridad estructural, sin pretender autenticidad CRC.
        texto += tlv("63", "0000")
        return texto
    }
}
