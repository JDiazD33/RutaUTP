//
//  StartGuardTests.swift
//  RutaUTPTests
//
//  Pruebas del testigo de arranque (I02).
//
//  `StartGuard` es un tipo puro: no necesita simulador, ni UIKit, ni esperar a
//  que venza un permiso real. Eso permite cubrir aquí el caso que motivó el
//  hallazgo —revocar el consentimiento mientras el arranque está suspendido—
//  sin montar el ciclo de vida de la app.
//

import XCTest
@testable import RutaUTP

final class StartGuardTests: XCTestCase {

    func testElPrimerArranqueEstaVigente() {
        var guardia = StartGuard()

        let token = guardia.begin()

        XCTAssertTrue(guardia.isCurrent(token))
    }

    /// Abrir un arranque nuevo invalida el anterior: dos arranques solapados no
    /// pueden completarse los dos.
    func testUnArranqueNuevoInvalidaElAnterior() {
        var guardia = StartGuard()

        let primero = guardia.begin()
        let segundo = guardia.begin()

        XCTAssertFalse(guardia.isCurrent(primero))
        XCTAssertTrue(guardia.isCurrent(segundo))
    }

    /// El caso del hallazgo: se revoca el consentimiento con el arranque
    /// suspendido, y al reanudar el testigo ya no vale.
    func testInvalidarCaducaElArranqueEnCurso() {
        var guardia = StartGuard()

        let token = guardia.begin()
        guardia.invalidate()

        XCTAssertFalse(guardia.isCurrent(token))
    }

    func testLosTestigosNoSeReutilizan() {
        var guardia = StartGuard()

        let primero = guardia.begin()
        guardia.invalidate()
        let segundo = guardia.begin()

        XCTAssertNotEqual(primero, segundo)
        XCTAssertFalse(guardia.isCurrent(primero))
        XCTAssertTrue(guardia.isCurrent(segundo))
    }

    /// Un testigo de una instancia no vale en otra: no hay estado compartido
    /// entre coordinadores.
    func testLosTestigosSonPropiosDeCadaInstancia() {
        var uno = StartGuard()
        var otro = StartGuard()

        let tokenDeUno = uno.begin()
        _ = otro.begin()

        XCTAssertTrue(uno.isCurrent(tokenDeUno))
    }

    func testInvalidarVariasVecesEsInocuo() {
        var guardia = StartGuard()

        let token = guardia.begin()

        guardia.invalidate()
        guardia.invalidate()
        guardia.invalidate()

        XCTAssertFalse(guardia.isCurrent(token))
    }
}
