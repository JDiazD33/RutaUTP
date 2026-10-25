import XCTest
@testable import RutaUTP

/// JSON/reloj inyectado y, en S10, archivos exclusivos en un directorio temporal.
/// Sin UIKit, MQTT ni datos de la app.
final class SimulationControlReceptionTests: XCTestCase {
    private let run = "8e5dc699-60d4-4f58-8ced-638313365544"
    private let other = "d32f104c-e9db-4e3e-ae3f-93f7956fcfc2"
    private let now = VehicleReceptionTime(wall: 1_000, uptime: 100)

    func testOcupacionV3ConservaLosTresEstadosYControlDeCaducidad() throws {
        for state in ["empty", "space", "full"] {
            let body = positionBody(changes: ["schemaVersion": 3, "scenarioOccupancy": state, "occupancyScriptVersion": 1])
            let value = try XCTUnwrap(decodeOccupancy(body))
            XCTAssertEqual(value.scenarioOccupancy?.rawValue, state)
            XCTAssertNil(value.communityVehicleID)
            var gate = SimulationControlGate()
            gate.receive(try control(), at: now)
            XCTAssertTrue(gate.permits(value, at: now, legacy: .disabled))
            XCTAssertFalse(gate.permits(value, at: VehicleReceptionTime(wall: 1_016, uptime: 116), legacy: .disabled))
        }
    }

    func testOcupacionV3RechazaContratoIncompletoOrigenAjenoYVersionDesconocida() throws {
        let valid: [String: Any] = ["schemaVersion": 3, "scenarioOccupancy": "full", "occupancyScriptVersion": 1]
        for change: [String: Any] in [
            ["scenarioOccupancy": "overfull"], ["scenarioOccupancy": NSNull()],
            ["occupancyScriptVersion": 2], ["occupancyScriptVersion": "1"],
            ["schemaVersion": 2], ["dataOrigin": "observed", "simulationRunId": NSNull(),
                "controlRevision": NSNull(), "vehicleId": "observed"]
        ] {
            XCTAssertNil(try decodeOccupancy(positionBody(changes: valid.merging(change) { _, b in b })))
        }
        var missing = positionBody(changes: valid)
        missing.removeValue(forKey: "occupancyScriptVersion")
        XCTAssertNil(try decodeOccupancy(missing))
        XCTAssertNil(try XCTUnwrap(decodeOccupancy(positionBody())).scenarioOccupancy)
    }

    private func decodeOccupancy(_ body: [String: Any]) throws -> VehiclePosition? {
        VehicleTrackingWire.position(data: try data(body), topic: "rutautp/vehiculos/\(body["vehicleId"]!)/posicion")
    }

    func testCheckpointInexistenteConDirectorioPadreAusenteEsPrimerArranque() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("s10-\(UUID().uuidString)")
        let file = SimulationCheckpointFile(url: root.appendingPathComponent("nested/control.json"))
        XCTAssertNil(try file.read())
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testPrimerCheckpointSeEscribeYRecuperaDesdeArchivoTemporal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("s10-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = SimulationCheckpointFile(url: root.appendingPathComponent("nested/control.json"))
        var gate = SimulationControlGate()
        gate.receive(try control(), at: now)
        try file.write(gate.checkpoint)
        XCTAssertEqual(try file.read(), gate.checkpoint)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testCheckpointCorruptoExistenteNoSeTrataComoPrimerArranque() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("s10-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = SimulationCheckpointFile(url: root.appendingPathComponent("control.json"))
        try Data("corrupt".utf8).write(to: file.url)
        XCTAssertThrowsError(try file.read())
        XCTAssertEqual(try Data(contentsOf: file.url), Data("corrupt".utf8))
    }

    private func data(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: .sortedKeys)
    }

    private func control(_ changes: [String: Any] = [:]) throws -> SimulationControlState {
        try XCTUnwrap(VehicleTrackingWire.control(data: data(controlBody(changes))))
    }

    private func controlBody(_ changes: [String: Any] = [:]) -> [String: Any] {
        ["schemaVersion": 1, "enabled": true, "runId": run, "controlRevision": 3,
         "issuedAt": 1_000, "validUntil": 1_015, "serviceEndsAt": 2_000,
         "timeZone": "America/Lima"].merging(changes) { _, new in new }
    }

    private func positionBody(origin: String? = "simulated", changes: [String: Any] = [:]) -> [String: Any] {
        var value: [String: Any] = ["vehicleId": "sim:\(run):bus-1", "routeId": "route", "linea": "C-01",
            "lat": -12.0, "lon": -77.0, "speed": 5, "heading": 90, "timestamp": 1_000]
        if let origin {
            value.merge(["schemaVersion": 2, "dataOrigin": origin,
                         "simulationRunId": origin == "simulated" ? run as Any : NSNull(),
                         "controlRevision": origin == "simulated" ? 3 as Any : NSNull()]) { _, new in new }
        }
        return value.merging(changes) { _, new in new }
    }

    private func position(origin: String? = "simulated", changes: [String: Any] = [:]) throws -> VehiclePosition {
        let body = positionBody(origin: origin, changes: changes)
        return try XCTUnwrap(VehicleTrackingWire.position(data: data(body),
            topic: "rutautp/vehiculos/\(body["vehicleId"]!)/posicion"))
    }

    private func permits(_ gate: SimulationControlGate, _ position: VehiclePosition,
                         wall: Double = 1_000, uptime: Double = 100,
                         legacy: LegacyVehicleCompatibility = .disabled) -> Bool {
        gate.permits(position, at: VehicleReceptionTime(wall: wall, uptime: uptime), legacy: legacy)
    }

    func testV2SimuladaConservaProcedenciaSinCambiarTransporte() throws {
        let value = try position()
        XCTAssertEqual(value.dataOrigin, .simulated)
        XCTAssertEqual(value.simulationRunId, run)
        XCTAssertEqual(value.controlRevision, 3)
    }

    func testV2ObservadaExigeNulls() throws {
        let value = try position(origin: "observed", changes: ["vehicleId": "observed-1"])
        XCTAssertEqual(value.dataOrigin, .observed)
        XCTAssertNil(value.simulationRunId)
        XCTAssertNil(value.controlRevision)
        var invalid = positionBody(origin: "observed", changes: ["vehicleId": "observed-1", "simulationRunId": run])
        XCTAssertNil(try VehicleTrackingWire.position(data: data(invalid), topic: "rutautp/vehiculos/observed-1/posicion"))
        invalid["simulationRunId"] = NSNull(); invalid["controlRevision"] = 3
        XCTAssertNil(try VehicleTrackingWire.position(data: data(invalid), topic: "rutautp/vehiculos/observed-1/posicion"))
    }

    func testLegadoMarcadoDesconocidoYCompatibilidadExplicita() throws {
        let value = try position(origin: nil, changes: ["vehicleId": "legacy-1"])
        XCTAssertEqual(value.dataOrigin, .legacyUnknown)
        let gate = SimulationControlGate()
        XCTAssertFalse(permits(gate, value))
        XCTAssertTrue(permits(gate, value, legacy: .whileSimulationDisabled))
    }

    func testLegadoNoPuedeUsarNamespaceSimulado() throws {
        let body = positionBody(origin: nil)
        XCTAssertNil(try VehicleTrackingWire.position(data: data(body), topic: "rutautp/vehiculos/\(body["vehicleId"]!)/posicion"))
    }

    func testVersionDesconocidaOIncompletaNuncaCaeALegado() throws {
        let topic = "rutautp/vehiculos/sim:\(run):bus-1/posicion"
        for change: [String: Any] in [["schemaVersion": 99], ["schemaVersion": NSNull()], ["schemaVersion": true],
            ["dataOrigin": "unknown"], ["dataOrigin": "legacy_unknown"], ["controlRevision": true],
            ["controlRevision": 0], ["controlRevision": 9_007_199_254_740_992 as UInt64], ["simulationRunId": NSNull()]] {
            XCTAssertNil(try VehicleTrackingWire.position(data: data(positionBody(changes: change)), topic: topic))
        }
        var missing = positionBody(); missing.removeValue(forKey: "dataOrigin")
        XCTAssertNil(try VehicleTrackingWire.position(data: data(missing), topic: topic))
    }

    func testCamposPosicionFueraDeContratoSeRechazan() throws {
        let topic = "rutautp/vehiculos/sim:\(run):bus-1/posicion"
        for change: [String: Any] in [["lat": 91], ["lon": -181], ["lat": true], ["timestamp": true],
            ["timestamp": -1], ["speed": 31], ["heading": 360], ["linea": " C-01"], ["routeId": "a/b"], ["extra": 1]] {
            XCTAssertNil(try VehicleTrackingWire.position(data: data(positionBody(changes: change)), topic: topic))
        }
    }

    func testTopicoIDRetainedYTamanio() throws {
        let body = try data(positionBody())
        XCTAssertNil(VehicleTrackingWire.position(data: body, topic: "rutautp/vehiculos/otro/posicion"))
        XCTAssertNil(VehicleTrackingWire.position(data: body, topic: "rutautp/vehiculos/sim:\(run):bus-1/posicion", retained: true))
        XCTAssertNil(VehicleTrackingWire.position(data: Data(repeating: 32, count: 4097), topic: "x"))
        XCTAssertNil(VehicleTrackingWire.control(data: Data(repeating: 32, count: 4097)))
    }

    func testControlTiposVersionZonaYLease() throws {
        for change: [String: Any] in [["schemaVersion": 2], ["schemaVersion": true], ["enabled": 1],
            ["controlRevision": true], ["controlRevision": -1], ["controlRevision": 0], ["runId": "invalido"],
            ["timeZone": "UTC"], ["issuedAt": true], ["validUntil": 1016], ["serviceEndsAt": 1010], ["extra": 0]] {
            XCTAssertNil(try VehicleTrackingWire.control(data: data(controlBody(change))))
        }
    }

    func testAusenciaDeControlYPosicionAntesDeEstadoSeDescartan() throws {
        var gate = SimulationControlGate()
        let value = try position()
        XCTAssertFalse(permits(gate, value))
        gate.receive(try control(), at: now)
        XCTAssertTrue(permits(gate, value))
    }

    func testVencimientoExactoYFinDeServicio() throws {
        var gate = SimulationControlGate()
        gate.receive(try control(), at: now)
        XCTAssertTrue(try permits(gate, position(), wall: 1014.9, uptime: 114.9))
        XCTAssertFalse(try permits(gate, position(), wall: 1015, uptime: 115))
        gate.receive(try control(["controlRevision": 4, "runId": other, "validUntil": 1004, "serviceEndsAt": 1004]), at: now)
        let current = try position(changes: ["vehicleId": "sim:\(other):bus", "simulationRunId": other, "controlRevision": 4])
        XCTAssertTrue(permits(gate, current))
        XCTAssertFalse(permits(gate, current, wall: 1004, uptime: 104))
    }

    func testRunORevisionDePosicionDiferentesNoSeAdmiten() throws {
        var gate = SimulationControlGate(); gate.receive(try control(), at: now)
        XCTAssertFalse(try permits(gate, position(changes: ["controlRevision": 4])))
        XCTAssertFalse(try permits(gate, position(changes: ["vehicleId": "sim:\(other):bus", "simulationRunId": other])))
    }

    func testDisableRetiraSimuladosYPreservaObservados() throws {
        var gate = SimulationControlGate(); gate.receive(try control(), at: now)
        gate.receive(try control(["enabled": false, "controlRevision": 4, "validUntil": 1000]), at: now)
        XCTAssertFalse(try permits(gate, position()))
        XCTAssertTrue(try permits(gate, position(origin: "observed", changes: ["vehicleId": "observed-1"])))
    }

    func testTombstoneAntiguoSeAplicaConRevisionNuevaAunqueServicioTermino() throws {
        var gate = SimulationControlGate(); gate.receive(try control(), at: now)
        XCTAssertTrue(gate.receive(try control(["enabled": false, "controlRevision": 4,
            "issuedAt": 1, "validUntil": 1, "serviceEndsAt": 1]), at: now))
        XCTAssertFalse(try permits(gate, position()))
    }

    func testRevisionViejaNoReabreRunYUUIDRevocadoNoSeReutiliza() throws {
        var gate = SimulationControlGate(); gate.receive(try control(), at: now)
        gate.receive(try control(["enabled": false, "controlRevision": 4, "validUntil": 1000]), at: now)
        XCTAssertFalse(gate.receive(try control(), at: now))
        XCTAssertFalse(gate.receive(try control(["controlRevision": 5]), at: now))
        XCTAssertFalse(try permits(gate, position()))
        XCTAssertTrue(gate.receive(try control(["controlRevision": 5, "runId": other]), at: now))
    }

    func testCambioDeRunInvalidaAnteriorYNoPermiteVolverMasAdelante() throws {
        var gate = SimulationControlGate(); gate.receive(try control(), at: now)
        gate.receive(try control(["controlRevision": 4, "runId": other]), at: now)
        XCTAssertFalse(try permits(gate, position()))
        XCTAssertFalse(gate.receive(try control(["controlRevision": 5]), at: now))
    }

    func testHeartbeatRenuevaSinRevivirMensajesDeRevisionAnterior() throws {
        var gate = SimulationControlGate(); gate.receive(try control(), at: now)
        gate.receive(try control(["issuedAt": 1005, "validUntil": 1020]), at: .init(wall: 1005, uptime: 105))
        XCTAssertFalse(gate.receive(try control(), at: .init(wall: 1006, uptime: 106)))
        XCTAssertTrue(try permits(gate, position(), wall: 1019, uptime: 119))
    }

    func testDuplicadoNoAlargaPlazoMonotonico() throws {
        var gate = SimulationControlGate(); let state = try control()
        gate.receive(state, at: now)
        let first = gate.remainingAuthorization(at: now)
        gate.receive(state, at: .init(wall: 1005, uptime: 105))
        XCTAssertEqual(first, 15)
        XCTAssertEqual(gate.remainingAuthorization(at: .init(wall: 1005, uptime: 105)), 10)
    }

    func testMismaRevisionNoPuedeCambiarRunPoliticaOLeaseContradictorio() throws {
        for changes: [String: Any] in [["runId": other], ["enabled": false, "validUntil": 1000],
            ["serviceEndsAt": 3000], ["validUntil": 1014]] {
            var gate = SimulationControlGate(); gate.receive(try control(), at: now)
            XCTAssertFalse(gate.receive(try control(changes), at: now))
            XCTAssertFalse(try permits(gate, position()))
        }
    }

    func testControlFuturoYRetainedVencidoNoDanPermiso() throws {
        var gate = SimulationControlGate()
        XCTAssertFalse(gate.receive(try control(["issuedAt": 1011, "validUntil": 1026]), at: now))
        gate.receive(try control(["issuedAt": 900, "validUntil": 915]), at: now)
        XCTAssertFalse(try permits(gate, position()))
    }

    func testDesconexionYBackgroundInvalidanSinReactivarSnapshotGuardado() throws {
        var gate = SimulationControlGate(); gate.receive(try control(), at: now)
        let checkpoint = gate.checkpoint
        gate.invalidate()
        XCTAssertFalse(try permits(gate, position()))
        let restarted = SimulationControlGate(checkpoint: checkpoint)
        XCTAssertFalse(try permits(restarted, position()))
    }

    func testCheckpointConservaRevocacionEntreInstancias() throws {
        var gate = SimulationControlGate(); gate.receive(try control(), at: now)
        gate.receive(try control(["enabled": false, "controlRevision": 4, "validUntil": 1000]), at: now)
        let bytes = try JSONEncoder().encode(gate.checkpoint)
        var restarted = SimulationControlGate(checkpoint: try JSONDecoder().decode(SimulationControlCheckpoint.self, from: bytes).validated())
        XCTAssertFalse(restarted.receive(try control(), at: now))
        XCTAssertFalse(restarted.receive(try control(["controlRevision": 5]), at: now))
    }

    func testLegadoSeBloqueaDuranteEnableEInclusoLeaseVencido() throws {
        var gate = SimulationControlGate(); let old = try position(origin: nil, changes: ["vehicleId": "legacy"])
        gate.receive(try control(), at: now)
        XCTAssertFalse(permits(gate, old, legacy: .whileSimulationDisabled))
        gate.invalidate()
        XCTAssertFalse(permits(gate, old, wall: 1020, uptime: 120, legacy: .whileSimulationDisabled))
        gate.receive(try control(["enabled": false, "controlRevision": 4, "validUntil": 1000]), at: now)
        XCTAssertTrue(permits(gate, old, legacy: .whileSimulationDisabled))
    }

    func testRelojQueRetrocedeOCambiaDeBaseExigeHeartbeatNuevo() throws {
        for stamp in [VehicleReceptionTime(wall: 999, uptime: 101), .init(wall: 1010, uptime: 101), .init(wall: 1001, uptime: 99)] {
            var gate = SimulationControlGate(); gate.receive(try control(), at: now)
            XCTAssertFalse(gate.checkTime(stamp))
            XCTAssertFalse(try permits(gate, position(), wall: stamp.wall, uptime: stamp.uptime))
        }
    }

    func testCodableInternoAntiguoNoSeConvierteEnObservado() throws {
        var body = positionBody(origin: nil, changes: ["vehicleId": "legacy"])
        body["id"] = body.removeValue(forKey: "vehicleId")
        let value = try JSONDecoder().decode(VehiclePosition.self, from: data(body))
        XCTAssertEqual(value.dataOrigin, .legacyUnknown)
        let decoded = try JSONDecoder().decode(VehiclePosition.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(decoded, value)
    }

    func testDisableSeAplicaInclusoDuranteSaltoDeReloj() throws {
        var gate = SimulationControlGate(); gate.receive(try control(), at: now)
        let stamp = VehicleReceptionTime(wall: 999, uptime: 101)
        XCTAssertTrue(gate.receive(try control(["enabled": false, "controlRevision": 4,
            "issuedAt": 999, "validUntil": 999]), at: stamp))
        XCTAssertEqual(gate.lastControl?.controlRevision, 4)
        XCTAssertTrue(gate.retiredRuns.contains(run))
    }

    func testLimiteDeTombstonesFallaCerradoSinEliminarRevocaciones() throws {
        let retired = Set((0..<256).map { String(format: "00000000-0000-0000-0000-%012x", $0) })
        let cp = SimulationControlCheckpoint(version: 1, lastControl: try control(), retiredRuns: retired, exhausted: false)
        var gate = SimulationControlGate(checkpoint: try cp.validated())
        XCTAssertFalse(gate.receive(try control(["controlRevision": 4, "runId": other]), at: now))
        XCTAssertTrue(gate.exhausted)
        XCTAssertEqual(gate.retiredRuns.count, 256)
        XCTAssertNoThrow(try gate.checkpoint.validated())
        XCTAssertFalse(try permits(gate, position()))
    }

    func testCheckpointCorruptoSeRechaza() throws {
        let bytes = try data(["version": 1, "lastControl": NSNull(), "retiredRuns": ["invalido"], "exhausted": false])
        let checkpoint = try JSONDecoder().decode(SimulationControlCheckpoint.self, from: bytes)
        XCTAssertThrowsError(try checkpoint.validated())
    }

    func testRelojRequiereEmisionPosteriorNoDuplicadoAnterior() throws {
        var gate = SimulationControlGate(); gate.receive(try control(), at: now)
        let stamp = VehicleReceptionTime(wall: 1010, uptime: 101)
        XCTAssertFalse(gate.checkTime(stamp))
        gate.receive(try control(), at: stamp)
        XCTAssertFalse(try permits(gate, position(), wall: 1010, uptime: 101))
        gate.receive(try control(["issuedAt": 1010, "validUntil": 1025]), at: stamp)
        XCTAssertTrue(try permits(gate, position(), wall: 1010, uptime: 101))
    }

    func testControlInicialSinRunConservaNullEnCheckpoint() throws {
        var gate = SimulationControlGate()
        gate.receive(try control(["enabled": false, "runId": NSNull(), "controlRevision": 1, "validUntil": 1000]), at: now)
        let encoded = try JSONEncoder().encode(gate.checkpoint)
        let restored = try JSONDecoder().decode(SimulationControlCheckpoint.self, from: encoded).validated()
        XCTAssertEqual(restored, gate.checkpoint)
        XCTAssertNil(restored.lastControl?.runId)
    }

    func testDosProveedoresNoPuedenGuardarRevisionRegresiva() throws {
        var old = SimulationControlGate(); old.receive(try control(), at: now)
        var recent = old
        recent.receive(try control(["enabled": false, "controlRevision": 4, "validUntil": 1000]), at: now)
        XCTAssertThrowsError(try old.checkpoint.merging(recent.checkpoint))
    }

    func testCheckpointCompartidoUneRevocacionesYSoloConservaHeartbeatMasNuevo() throws {
        let first = SimulationControlCheckpoint(version: 1, lastControl: try control(), retiredRuns: [other], exhausted: false)
        let extra = "1afc70e8-05f4-4e7d-b7ed-070710daeb15"
        let second = SimulationControlCheckpoint(version: 1, lastControl: try control(["issuedAt": 1005, "validUntil": 1020]),
                                               retiredRuns: [extra], exhausted: false)
        let merged = try first.merging(second)
        XCTAssertEqual(merged.retiredRuns, [other, extra])
        XCTAssertEqual(merged.lastControl?.issuedAt, 1005)
    }
}
