//
//  ObservationPublishThrottleTests.swift
//  RutaUTPTests
//
//  Verifica el ritmo mínimo de publicación de la baliza usando un
//  reloj controlado: sin broker, sin GPS y sin esperar tiempo real.
//

import XCTest
@testable import RutaUTP

final class ObservationPublishThrottleTests: XCTestCase {

    /// La primera publicación de la sesión siempre pasa.
    func testPrimeraPublicacionPermitida() {
        var throttle = ObservationPublishThrottle(
            minimumInterval: 5
        )

        XCTAssertTrue(
            throttle.canPublish(now: 1000, force: false)
        )
    }

    /// Una publicación inmediatamente posterior debe bloquearse.
    func testPublicacionDentroDelIntervaloSeBloquea() {
        var throttle = ObservationPublishThrottle(
            minimumInterval: 5
        )

        throttle.didPublish(at: 1000)

        XCTAssertFalse(
            throttle.canPublish(now: 1002, force: false)
        )
        XCTAssertFalse(
            throttle.canPublish(now: 1004.9, force: false)
        )
    }

    /// Al cumplirse el intervalo vuelve a permitir publicar.
    func testPublicacionTrasElIntervaloPermitida() {
        var throttle = ObservationPublishThrottle(
            minimumInterval: 5
        )

        throttle.didPublish(at: 1000)

        XCTAssertTrue(
            throttle.canPublish(now: 1005, force: false)
        )
    }

    /// `force` existe para no perder la primera muestra recibida
    /// mientras la conexión se establecía: ignora el intervalo.
    func testForceIgnoraElIntervalo() {
        var throttle = ObservationPublishThrottle(
            minimumInterval: 5
        )

        throttle.didPublish(at: 1000)

        XCTAssertTrue(
            throttle.canPublish(now: 1001, force: true)
        )
    }

    /// Reiniciar el throttle deja el estado como recién creado.
    func testResetEliminaLaUltimaPublicacion() {
        var throttle = ObservationPublishThrottle(
            minimumInterval: 5
        )

        throttle.didPublish(at: 1000)
        throttle.reset()

        XCTAssertEqual(throttle.lastPublishedAt, nil)
        XCTAssertTrue(
            throttle.canPublish(now: 1001, force: false)
        )
    }

    /// El intervalo es configurable para poder ajustar el ritmo de
    /// la baliza sin tocar el publicador.
    func testIntervaloPersonalizadoSeRespeta() {
        var throttle = ObservationPublishThrottle(
            minimumInterval: 30
        )

        throttle.didPublish(at: 1000)

        XCTAssertFalse(
            throttle.canPublish(now: 1020, force: false)
        )
        XCTAssertTrue(
            throttle.canPublish(now: 1030, force: false)
        )
    }
}
