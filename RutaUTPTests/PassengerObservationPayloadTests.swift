//
//  PassengerObservationPayloadTests.swift
//  RutaUTPTests
//
//  Contrato JSON de la baliza. Lo que sale por el canal público debe
//  tener exactamente las claves acordadas con el backend y, sobre
//  todo, NO debe contener ningún identificador personal.
//

import XCTest
@testable import RutaUTP

final class PassengerObservationPayloadTests: XCTestCase {

    private func makePayload() -> PassengerObservationPayload {
        PassengerObservationPayload(
            schemaVersion: 1,
            sessionId: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            routeId: "route-10",
            linea: "10",
            lat: -8.107_722,
            lon: -79.032_589,
            speed: 11.4,
            heading: 90,
            accuracy: 8.0,
            motionActivity: "automotive",
            timestamp: 1_760_000_000
        )
    }

    /// El JSON debe usar exactamente las claves del contrato.
    func testCodificaConLasClavesDelContrato() throws {
        let data = try JSONEncoder().encode(makePayload())

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        )

        let expectedKeys: Set<String> = [
            "schemaVersion",
            "sessionId",
            "routeId",
            "linea",
            "lat",
            "lon",
            "speed",
            "heading",
            "accuracy",
            "motionActivity",
            "timestamp"
        ]

        XCTAssertEqual(
            Set(object.keys),
            expectedKeys
        )

        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["linea"] as? String, "10")
        XCTAssertEqual(object["lat"] as? Double, -8.107_722)
        XCTAssertEqual(object["motionActivity"] as? String, "automotive")
        XCTAssertEqual(
            object["timestamp"] as? Double,
            1_760_000_000
        )
    }

    /// El payload es anónimo por diseño: esta prueba lo deja clavado
    /// para que nadie agregue un identificador sin darse cuenta.
    func testNoContieneIdentificadoresPersonales() throws {
        let data = try JSONEncoder().encode(makePayload())

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        )

        let forbiddenKeys = [
            "userId",
            "device",
            "deviceId",
            "email",
            "name",
            "phone",
            "idfa",
            "advertisingId"
        ]

        for key in forbiddenKeys {
            XCTAssertNil(
                object[key],
                "El payload no debe contener '\(key)'"
            )
        }
    }

    /// Round-trip: lo que el backend decodifique debe ser lo mismo
    /// que el teléfono codificó.
    func testRoundTripCodificacionDecodificacion() throws {
        let original = makePayload()

        let data = try JSONEncoder().encode(original)

        let decoded = try JSONDecoder().decode(
            PassengerObservationPayload.self,
            from: data
        )

        XCTAssertEqual(decoded, original)
    }
}
