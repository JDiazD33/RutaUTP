//
//  GTFSCSVCompatibilityTests.swift
//  RutaUTPTests
//
//  E08: registros CSV válidos y compatibilidad del feed GTFS existente.
//  Fixtures en memoria; no acceden al bundle, la red ni datos del usuario.
//

import XCTest
@testable import RutaUTP

final class GTFSCSVCompatibilityTests: XCTestCase {

    func testBOMInicialNoFormaParteDelPrimerEncabezado() {
        let tabla = GTFSCSV.parsear(texto: "\u{FEFF}route_id,route_short_name\n10,C-01\n")

        XCTAssertEqual(tabla.rowCount, 1)
        XCTAssertEqual(Set(tabla.columns.keys), Set(["route_id", "route_short_name"]))
        XCTAssertEqual(tabla.columna("route_id"), ["10"])
    }

    func testBOMInteriorSeConservaComoDatoYEncabezado() {
        let tabla = GTFSCSV.parsear(texto: "\u{FEFF}a,\u{FEFF}b\n\u{FEFF}inicio,inter\u{FEFF}ior\n")

        XCTAssertEqual(Set(tabla.columns.keys), Set(["a", "\u{FEFF}b"]))
        XCTAssertEqual(tabla.columna("a"), ["\u{FEFF}inicio"])
        XCTAssertEqual(tabla.columna("\u{FEFF}b"), ["inter\u{FEFF}ior"])
    }

    func testSeparadoresCRLFNoContaminanEncabezadosNiValores() {
        let tabla = GTFSCSV.parsear(texto: "a,b\r\n1,2\r\n3,4\r\n")

        XCTAssertEqual(tabla.rowCount, 2)
        XCTAssertEqual(Set(tabla.columns.keys), Set(["a", "b"]))
        XCTAssertEqual(tabla.columna("a"), ["1", "3"])
        XCTAssertEqual(tabla.columna("b"), ["2", "4"])
    }

    func testSeparadoresCRDelimitanRegistros() {
        let tabla = GTFSCSV.parsear(texto: "a,b\r1,2\r3,4\r")

        XCTAssertEqual(tabla.rowCount, 2)
        XCTAssertEqual(tabla.columna("a"), ["1", "3"])
        XCTAssertEqual(tabla.columna("b"), ["2", "4"])
    }

    func testSeparadoresLFCRLFYCRPuedenAlternarse() {
        let tabla = GTFSCSV.parsear(texto: "a,b\n1,2\r\n3,4\r5,6")

        XCTAssertEqual(tabla.rowCount, 3)
        XCTAssertEqual(tabla.columna("a"), ["1", "3", "5"])
        XCTAssertEqual(tabla.columna("b"), ["2", "4", "6"])
    }

    func testComillasEscapadasYComaPermanecenEnElMismoCampo() {
        let tabla = GTFSCSV.parsear(texto: "id,descripcion,fin\n1,\"Dijo \"\"hola\"\", luego salió\",ok\n")

        XCTAssertEqual(tabla.rowCount, 1)
        XCTAssertEqual(tabla.columna("descripcion"), ["Dijo \"hola\", luego salió"])
        XCTAssertEqual(tabla.columna("fin"), ["ok"])
    }

    func testCampoConUnaComillaEscapadaYCampoVacio() {
        let tabla = GTFSCSV.parsear(texto: "a,b,c\n\"\"\"\",\"\",fin\n")

        XCTAssertEqual(tabla.rowCount, 1)
        XCTAssertEqual(tabla.columna("a"), ["\""])
        XCTAssertEqual(tabla.columna("b"), [""])
        XCTAssertEqual(tabla.columna("c"), ["fin"])
    }

    func testCampoMultilineaLFConservaInclusoLaLineaVaciaInterior() {
        let tabla = GTFSCSV.parsear(texto: "id,descripcion,fin\n1,\"primera, parte\n\ntercera \"\"citada\"\"\",ok\n2,normal,listo\n")

        XCTAssertEqual(tabla.rowCount, 2, "Los saltos del campo citado no crean registros adicionales")
        XCTAssertEqual(tabla.columna("id"), ["1", "2"])
        XCTAssertEqual(tabla.columna("descripcion"), ["primera, parte\n\ntercera \"citada\"", "normal"])
        XCTAssertEqual(tabla.columna("fin"), ["ok", "listo"])
    }

    func testCampoMultilineaConservaCRLFYCRSinNormalizarlos() {
        let contenido = "primera\r\nsegunda\rtercera"
        let tabla = GTFSCSV.parsear(texto: "id,descripcion\r\n1,\"\(contenido)\"\r\n2,normal")

        XCTAssertEqual(tabla.rowCount, 2)
        XCTAssertEqual(tabla.columna("id"), ["1", "2"])
        XCTAssertEqual(tabla.columna("descripcion"), [contenido, "normal"])
        XCTAssertEqual(tabla.columna("descripcion").first.map { Array($0.utf8) }, .some(Array(contenido.utf8)), "Debe preservar los bytes de los saltos interiores")
    }

    func testCamposVaciosFinalesYRegistroDeSoloDelimitadoresSeConservan() {
        let tabla = GTFSCSV.parsear(texto: "a,b,c,d\n1,2,,\n,,,\n")

        XCTAssertEqual(tabla.rowCount, 2)
        XCTAssertEqual(tabla.columna("a"), ["1", ""])
        XCTAssertEqual(tabla.columna("b"), ["2", ""])
        XCTAssertEqual(tabla.columna("c"), ["", ""])
        XCTAssertEqual(tabla.columna("d"), ["", ""])
    }

    func testFilasCortasRellenanColumnasSinDesalinearLosRegistros() {
        let tabla = GTFSCSV.parsear(texto: "a,b,c\n1\n2,\n3,4,5\n")

        XCTAssertEqual(tabla.rowCount, 3)
        XCTAssertEqual(tabla.columna("a"), ["1", "2", "3"])
        XCTAssertEqual(tabla.columna("b"), ["", "", "4"])
        XCTAssertEqual(tabla.columna("c"), ["", "", "5"])
        XCTAssertEqual(tabla.columna("ausente"), ["", "", ""])
    }

    func testUltimoRegistroSinSaltoFinalSeEmiteUnaSolaVez() {
        let tabla = GTFSCSV.parsear(texto: "a,b\n1,normal\n2,\"ultimo, citado\"")

        XCTAssertEqual(tabla.rowCount, 2)
        XCTAssertEqual(tabla.columna("a"), ["1", "2"])
        XCTAssertEqual(tabla.columna("b"), ["normal", "ultimo, citado"])
    }

    func testNombreDeRutaConComillasLiteralesYEspaciosConservaCompatibilidad() {
        let tabla = GTFSCSV.parsear(texto: "route_id,route_short_name,detalle\n1, C-01 \"B\" ,  texto literal  \n2,  \"x,y\"  ,fin\n")

        XCTAssertEqual(tabla.rowCount, 2)
        XCTAssertEqual(tabla.columna("route_short_name"), [" C-01 \"B\" ", "  x,y  "])
        XCTAssertEqual(tabla.columna("detalle"), ["  texto literal  ", "fin"])
    }

    func testUnicodeSeConservaEnEncabezadosYCamposCitados() {
        let tabla = GTFSCSV.parsear(texto: "identificador,dirección,emoji\nñ-1,\"Av. España, José 🚌\",👩🏽‍💻\n")

        XCTAssertEqual(tabla.rowCount, 1)
        XCTAssertEqual(tabla.columna("identificador"), ["ñ-1"])
        XCTAssertEqual(tabla.columna("dirección"), ["Av. España, José 🚌"])
        XCTAssertEqual(tabla.columna("emoji"), ["👩🏽‍💻"])
    }

    func testLineasVaciasSeOmitenPeroUnCampoVacioExplicitoEsUnRegistro() {
        let tabla = GTFSCSV.parsear(texto: "\nvalor\n\n\"\"\n\ntexto\n\n")

        XCTAssertEqual(tabla.rowCount, 2)
        XCTAssertEqual(tabla.columna("valor"), ["", "texto"])
    }

    func testEntradaVaciaYEncabezadoSinRegistrosConservanTablaVacia() {
        let vacia = GTFSCSV.parsear(texto: "\r\n\n\r")
        XCTAssertEqual(vacia.rowCount, 0)
        XCTAssertTrue(vacia.columns.isEmpty)
        XCTAssertEqual(vacia.columna("ausente"), [])

        let encabezado = GTFSCSV.parsear(texto: "\u{FEFF}a,b\r\n")
        XCTAssertEqual(encabezado.rowCount, 0)
        XCTAssertEqual(Set(encabezado.columns.keys), Set(["a", "b"]))
        XCTAssertEqual(encabezado.columna("a"), [])
        XCTAssertEqual(encabezado.columna("b"), [])
    }
}
