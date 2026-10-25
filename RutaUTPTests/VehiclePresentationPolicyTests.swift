import XCTest
@testable import RutaUTP

/// Política pura: relojes y posiciones en memoria, sin app ni red.
final class VehiclePresentationPolicyTests: XCTestCase {
    private func position(_ id: String = "bus", route: String = "route",
                          origin: VehicleDataOrigin = .simulated, run: String? = "run-a",
                          revision: UInt64? = 1, speed: Double = 0) -> VehiclePosition {
        VehiclePosition(id: id, linea: "T", routeId: route, lat: -8.1, lon: -79,
            heading: 90, speed: speed, timestamp: 1000, dataOrigin: origin,
            simulationRunId: run, controlRevision: revision)
    }

    func testPrimerSnapshotVacioSePublica() {
        var gate = VehiclePresentationUpdateGate()
        XCTAssertTrue(gate.shouldPublish([], at: 100))
    }

    func testMovimientoNormalSeLimitaACuatroHz() {
        var gate = VehiclePresentationUpdateGate()
        let first = position()
        var moved = first; moved.lat += 0.001
        XCTAssertTrue(gate.shouldPublish([first], at: 100))
        XCTAssertFalse(gate.shouldPublish([moved], at: 100.1))
        XCTAssertFalse(gate.shouldPublish([moved], at: 100.249))
        XCTAssertTrue(gate.shouldPublish([moved], at: 100.25))
    }

    func testRetiradaNoEsDescartadaPorThrottle() {
        var gate = VehiclePresentationUpdateGate()
        let observed = position("observed", origin: .observed, run: nil, revision: nil)
        XCTAssertTrue(gate.shouldPublish([position(), observed], at: 100))
        XCTAssertTrue(gate.shouldPublish([observed], at: 100.001))
    }

    func testUltimoSnapshotVacioSePublicaInmediatamente() {
        var gate = VehiclePresentationUpdateGate()
        XCTAssertTrue(gate.shouldPublish([position()], at: 100))
        XCTAssertTrue(gate.shouldPublish([], at: 100.001))
        XCTAssertFalse(gate.shouldPublish([], at: 100.002))
    }

    func testAltaSePublicaInmediatamente() {
        var gate = VehiclePresentationUpdateGate()
        XCTAssertTrue(gate.shouldPublish([], at: 100))
        XCTAssertTrue(gate.shouldPublish([position()], at: 100.001))
    }

    func testReordenarNoEvitaElThrottle() {
        var gate = VehiclePresentationUpdateGate()
        let values = [position("a"), position("b")]
        XCTAssertTrue(gate.shouldPublish(values, at: 100))
        XCTAssertFalse(gate.shouldPublish(Array(values.reversed()), at: 100.001))
    }

    func testCambioDeRutaSePublicaInmediatamente() {
        var gate = VehiclePresentationUpdateGate()
        XCTAssertTrue(gate.shouldPublish([position()], at: 100))
        XCTAssertTrue(gate.shouldPublish([position(route: "other")], at: 100.001))
    }

    func testCambioDeOrigenSePublicaInmediatamente() {
        var gate = VehiclePresentationUpdateGate()
        XCTAssertTrue(gate.shouldPublish([position(origin: .unknown)], at: 100))
        XCTAssertTrue(gate.shouldPublish([position(origin: .simulated)], at: 100.001))
    }

    func testCambioDeRunSePublicaInmediatamente() {
        var gate = VehiclePresentationUpdateGate()
        XCTAssertTrue(gate.shouldPublish([position()], at: 100))
        XCTAssertTrue(gate.shouldPublish([position(run: "run-b")], at: 100.001))
    }

    func testCambioDeRevisionSePublicaInmediatamente() {
        var gate = VehiclePresentationUpdateGate()
        XCTAssertTrue(gate.shouldPublish([position()], at: 100))
        XCTAssertTrue(gate.shouldPublish([position(revision: 2)], at: 100.001))
    }

    func testRetrocesoDeRelojNoBloqueaPresentacion() {
        var gate = VehiclePresentationUpdateGate()
        XCTAssertTrue(gate.shouldPublish([position()], at: 100))
        XCTAssertTrue(gate.shouldPublish([position()], at: 90))
    }

    func testReaperturaNoHeredaThrottleAnterior() {
        var gate = VehiclePresentationUpdateGate()
        XCTAssertTrue(gate.shouldPublish([position()], at: 100))
        gate = VehiclePresentationUpdateGate()
        XCTAssertTrue(gate.shouldPublish([], at: 100.001))
    }

    func testIdentidadNoDependeDeMovimientoNiTimestamp() {
        let first = position()
        var moved = first
        moved.lat += 0.1; moved.heading = -1; moved.speed = -1; moved.timestamp += 5
        XCTAssertEqual(first.presentationIdentity, moved.presentationIdentity)
        XCTAssertNotEqual(first, moved)
    }

    func testIdentidadDistingueProcedenciaRutaRunYRevision() {
        let first = position()
        for changed in [position("other"), position(route: "other"), position(origin: .unknown),
                        position(run: "run-b"), position(revision: 2)] {
            XCTAssertNotEqual(first.presentationIdentity, changed.presentationIdentity)
        }
    }

    func testSoloObservadoAbreOcupacion() {
        XCTAssertEqual(position(origin: .observed, run: nil, revision: nil).communityVehicleID, "bus")
        for origin in [VehicleDataOrigin.simulated, .legacyUnknown, .unknown] {
            XCTAssertNil(position(origin: origin).communityVehicleID)
        }
    }

    func testNamespaceReservadoNoAbreOcupacionAunqueDigaObservado() {
        for id in ["sim:run:bus", "SIM:run:bus", "sIm:run:bus"] {
            XCTAssertNil(position(id, origin: .observed, run: nil, revision: nil).communityVehicleID)
        }
    }

    func testVelocidadCeroConservaVehiculoDetenido() {
        XCTAssertEqual(position(speed: 0).reportedSpeedForPresentation, 0)
    }

    func testVelocidadDesconocidaNoSeConvierteEnCero() {
        XCTAssertNil(position(speed: -1).reportedSpeedForPresentation)
    }

    func testVelocidadNoFinitaOFueraDeRangoNoSePresenta() {
        for speed in [Double.nan, .infinity, -.infinity, -0.1, 100.01] {
            XCTAssertNil(position(speed: speed).reportedSpeedForPresentation)
        }
    }

    func testExtremoDeVelocidadValido() {
        XCTAssertEqual(position(speed: 100).reportedSpeedForPresentation, 100)
    }

    func testLimiteDeMarcadoresNoRecortaSnapshot() {
        let snapshot = (0..<12).map { position("bus-\($0)") }
        XCTAssertEqual(snapshot.prefix(VehiclePresentationLimits.maximumMapMarkers).count, 8)
        XCTAssertEqual(snapshot.count, 12)
    }
}
