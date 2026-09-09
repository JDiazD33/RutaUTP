//
//  VehiclePositionSanitizerTests.swift
//  RutaUTPTests
//
//  Verifica el filtro de posiciones que llegan por MQTT: el broker es
//  un canal compartido y el consumidor no debe aceptar coordenadas
//  imposibles, timestamps del futuro ni vehículos obsoletos.
//

import XCTest
@testable import RutaUTP

final class VehiclePositionSanitizerTests: XCTestCase {

    private var now: TimeInterval {
        1_760_000_000
    }

    /// Una posición razonable debe atravesar el filtro intacta,
    /// con speed y heading normalizados.
    func testPosicionValidaPasaFiltro() throws {
        let position = VehiclePosition(
            id: "baliza-1",
            linea: "10",
            lat: -8.107_722,
            lon: -79.032_589,
            heading: 90,
            speed: 11.4,
            timestamp: now - 3
        )

        let sanitized = try XCTUnwrap(
            VehiclePositionSanitizer.sanitize(
                position,
                now: now
            )
        )

        XCTAssertEqual(sanitized.id, "baliza-1")
        XCTAssertEqual(sanitized.linea, "10")
        XCTAssertEqual(sanitized.lat, -8.107_722)
        XCTAssertEqual(sanitized.lon, -79.032_589)
        XCTAssertEqual(sanitized.speed, 11.4)
        XCTAssertEqual(sanitized.heading, 90)
    }

    func testLatitudFueraDeRangoSeDescarta() {
        let position = VehiclePosition(
            id: "baliza-2",
            linea: "10",
            lat: 999,
            lon: -79.03,
            timestamp: now - 3
        )

        XCTAssertNil(
            VehiclePositionSanitizer.sanitize(
                position,
                now: now
            )
        )
    }

    func testLongitudNaNSeDescarta() {
        var position = VehiclePosition(
            id: "baliza-3",
            linea: "10",
            lat: -8.10,
            lon: -79.03,
            timestamp: now - 3
        )

        position.lon = .nan

        XCTAssertNil(
            VehiclePositionSanitizer.sanitize(
                position,
                now: now
            )
        )
    }

    /// Un mensaje con timestamp demasiado futuro no debe usarse:
    /// indica reloj mal ajustado o un mensaje manipulado.
    func testTimestampDelFuturoSeDescarta() {
        let position = VehiclePosition(
            id: "baliza-4",
            linea: "10",
            lat: -8.10,
            lon: -79.03,
            timestamp: now + 60
        )

        XCTAssertNil(
            VehiclePositionSanitizer.sanitize(
                position,
                now: now
            )
        )
    }

    /// Un pequeño desfase de reloj hacia adelante es tolerable.
    func testTimestampConSkewMenorAlToleradoPasa() throws {
        let position = VehiclePosition(
            id: "baliza-5",
            linea: "10",
            lat: -8.10,
            lon: -79.03,
            timestamp: now + 5
        )

        XCTAssertNotNil(
            VehiclePositionSanitizer.sanitize(
                position,
                now: now
            )
        )
    }

    /// Una baliza que dejó de transmitir hace más del límite no debe
    /// seguir dibujada: la obsolescencia evita vehículos fantasmas.
    func testPosicionObsoletaSeDescarta() {
        let position = VehiclePosition(
            id: "baliza-6",
            linea: "10",
            lat: -8.10,
            lon: -79.03,
            timestamp: now - VehiclePositionSanitizer.stalenessLimit - 1
        )

        XCTAssertNil(
            VehiclePositionSanitizer.sanitize(
                position,
                now: now
            )
        )
    }

    /// Una baliza dentro del límite de obsolescencia sigue válida.
    func testPosicionDentroDelLimiteDeObsolescenciaPasa() throws {
        let position = VehiclePosition(
            id: "baliza-7",
            linea: "10",
            lat: -8.10,
            lon: -79.03,
            timestamp: now - VehiclePositionSanitizer.stalenessLimit + 5
        )

        XCTAssertNotNil(
            VehiclePositionSanitizer.sanitize(
                position,
                now: now
            )
        )
    }

    /// NaN no es "desconocido": el contrato exige -1 para que el mapa
    /// y los cálculos puedan distinguirlo.
    func testVelocidadNaNSeReemplazaPorDesconocida() throws {
        var position = VehiclePosition(
            id: "baliza-8",
            linea: "10",
            lat: -8.10,
            lon: -79.03,
            timestamp: now - 3
        )

        position.speed = .nan

        let sanitized = try XCTUnwrap(
            VehiclePositionSanitizer.sanitize(
                position,
                now: now
            )
        )

        XCTAssertEqual(sanitized.speed, -1)
    }

    /// Velocidades imposibles se acotan al techo del contrato.
    func testVelocidadAbsurdaSeAcota() throws {
        var position = VehiclePosition(
            id: "baliza-9",
            linea: "10",
            lat: -8.10,
            lon: -79.03,
            timestamp: now - 3
        )

        position.speed = 500

        let sanitized = try XCTUnwrap(
            VehiclePositionSanitizer.sanitize(
                position,
                now: now
            )
        )

        XCTAssertEqual(sanitized.speed, 100)
    }

    /// El rumbo se normaliza al rango [0, 360).
    func testRumboSeNormaliza() throws {
        var position = VehiclePosition(
            id: "baliza-10",
            linea: "10",
            lat: -8.10,
            lon: -79.03,
            timestamp: now - 3
        )

        position.heading = 405

        let sanitized = try XCTUnwrap(
            VehiclePositionSanitizer.sanitize(
                position,
                now: now
            )
        )

        XCTAssertEqual(sanitized.heading, 45)
    }
}
