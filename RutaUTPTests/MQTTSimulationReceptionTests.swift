import XCTest
import CocoaMQTT
import UIKit
@testable import RutaUTP

/// Clientes capturados; conectar está sustituido y no abre sockets.
@MainActor
final class MQTTSimulationReceptionTests: XCTestCase {
    private let run = "8e5dc699-60d4-4f58-8ced-638313365544"

    private final class Rig {
        var now = VehicleReceptionTime(wall: 1000, uptime: 100)
        var clients: [CocoaMQTT] = []
        var checkpoint: SimulationControlCheckpoint?
        var failWrite = false
        var failRead = false
    }

    private func provider(_ rig: Rig, legacy: LegacyVehicleCompatibility = .disabled,
                          readOnly: Bool = false) -> MQTTTrackingProvider {
        MQTTTrackingProvider(configuration: MQTTConfiguration(host: "offline.invalid", port: 8883,
            username: "captured-reader", password: "unused", useTLS: true, isReadOnly: readOnly), legacyCompatibility: legacy,
            clock: { rig.now }, loadCheckpoint: {
                if rig.failRead { throw CocoaError(.fileReadCorruptFile) }
                return rig.checkpoint
            }, saveCheckpoint: {
                if rig.failWrite { throw CocoaError(.fileWriteOutOfSpace) }
                rig.checkpoint = $0
            }, conectar: { rig.clients.append($0); return true })
    }

    private func connect(_ provider: MQTTTrackingProvider, _ rig: Rig) throws -> CocoaMQTT {
        provider.start()
        let client = try XCTUnwrap(rig.clients.last)
        client.didConnectAck(client, .accept)
        client.didSubscribeTopics(client, [VehicleTrackingWire.controlTopic: 1] as NSDictionary, [])
        return client
    }

    private func message(_ body: [String: Any], topic: String, retained: Bool = false) throws -> CocoaMQTTMessage {
        CocoaMQTTMessage(topic: topic, payload: [UInt8](try JSONSerialization.data(withJSONObject: body)), retained: retained)
    }

    private func state(_ changes: [String: Any] = [:]) throws -> CocoaMQTTMessage {
        try message(["schemaVersion": 1, "enabled": true, "runId": run, "controlRevision": 3,
            "issuedAt": 1000, "validUntil": 1015, "serviceEndsAt": 2000, "timeZone": "America/Lima"]
            .merging(changes) { _, new in new }, topic: VehicleTrackingWire.controlTopic, retained: true)
    }

    private func position(_ rig: Rig, simulated: Bool = true, legacy: Bool = false,
                          occupancy: String? = nil) throws -> CocoaMQTTMessage {
        let id = simulated ? "sim:\(run):bus" : "observed-bus"
        var body: [String: Any] = ["vehicleId": id, "routeId": "route", "linea": "C-01", "lat": -12,
            "lon": -77, "speed": 5, "heading": 90, "timestamp": rig.now.wall]
        if !legacy {
            body.merge(["schemaVersion": 2, "dataOrigin": simulated ? "simulated" : "observed",
                "simulationRunId": simulated ? run as Any : NSNull(),
                "controlRevision": simulated ? 3 as Any : NSNull()]) { _, new in new }
        }
        if let occupancy {
            body.merge(["schemaVersion": 3, "scenarioOccupancy": occupancy, "occupancyScriptVersion": 1]) { _, new in new }
        }
        return try message(body, topic: "rutautp/vehiculos/\(id)/posicion")
    }

    func testPosicionAntesDeEstadoSeDescartaYLuegoSeAdmiteSoloLaSiguiente() throws {
        let rig = Rig(); let provider = provider(rig); defer { provider.stop() }
        let client = try connect(provider, rig)
        client.didReceiveMessage(client, try position(rig), 1)
        XCTAssertTrue(provider.currentPositions.isEmpty)
        client.didReceiveMessage(client, try state(), 2)
        XCTAssertTrue(provider.currentPositions.isEmpty)
        client.didReceiveMessage(client, try position(rig), 3)
        XCTAssertEqual(provider.currentPositions.count, 1)
        XCTAssertEqual(provider.currentPositions.first?.dataOrigin, .simulated)
        XCTAssertEqual(provider.source, .real)
    }

    func testDisablePurgaSoloSinteticosYMensajeTardioNoLosRepone() throws {
        let rig = Rig(); let provider = provider(rig); defer { provider.stop() }
        let client = try connect(provider, rig)
        client.didReceiveMessage(client, try state(), 1)
        client.didReceiveMessage(client, try position(rig), 2)
        client.didReceiveMessage(client, try position(rig, simulated: false), 3)
        XCTAssertEqual(provider.currentPositions.count, 2)
        client.didReceiveMessage(client, try state(["enabled": false, "controlRevision": 4, "validUntil": 1000]), 4)
        client.didReceiveMessage(client, try position(rig), 5)
        client.didReceiveMessage(client, try state(), 6)
        XCTAssertEqual(provider.currentPositions.map(\.id), ["observed-bus"])
    }

    func testDesconexionPurgaSinteticosYReconexionExigeOtroControl() throws {
        let rig = Rig(); let provider = provider(rig); defer { provider.stop() }
        let client = try connect(provider, rig)
        client.didReceiveMessage(client, try state(), 1)
        client.didReceiveMessage(client, try position(rig), 2)
        client.didDisconnect(client, nil)
        XCTAssertTrue(provider.currentPositions.isEmpty)
        client.didReceiveMessage(client, try position(rig), 3)
        XCTAssertTrue(provider.currentPositions.isEmpty)
        client.didConnectAck(client, .accept)
        client.didSubscribeTopics(client, [VehicleTrackingWire.controlTopic: 1] as NSDictionary, [])
        client.didReceiveMessage(client, try position(rig), 4)
        XCTAssertTrue(provider.currentPositions.isEmpty)
        client.didReceiveMessage(client, try state(), 5)
        client.didReceiveMessage(client, try position(rig), 6)
        XCTAssertEqual(provider.currentPositions.count, 1)
    }

    func testOcupacionV3NoReviveTrasDesconexionSinControlNiTrasCaducar() throws {
        let rig = Rig(); let provider = provider(rig); defer { provider.stop() }
        let client = try connect(provider, rig)
        client.didReceiveMessage(client, try state(), 1)
        client.didReceiveMessage(client, try position(rig, occupancy: "full"), 2)
        XCTAssertEqual(provider.currentPositions.first?.scenarioOccupancy, .full)
        client.didDisconnect(client, nil)
        XCTAssertTrue(provider.currentPositions.isEmpty)
        client.didConnectAck(client, .accept)
        client.didSubscribeTopics(client, [VehicleTrackingWire.controlTopic: 1] as NSDictionary, [])
        client.didReceiveMessage(client, try position(rig, occupancy: "full"), 3)
        XCTAssertTrue(provider.currentPositions.isEmpty)
        client.didReceiveMessage(client, try state(), 4)
        client.didReceiveMessage(client, try position(rig, occupancy: "space"), 5)
        XCTAssertEqual(provider.currentPositions.first?.scenarioOccupancy, .space)
        rig.now = VehicleReceptionTime(wall: 1016, uptime: 116)
        client.didReceiveMessage(client, try position(rig, occupancy: "empty"), 6)
        XCTAssertTrue(provider.currentPositions.isEmpty)
    }

    func testControlMalformadoYFalloDeSuscripcionRetiranSinteticos() throws {
        let rig = Rig(); let provider = provider(rig); defer { provider.stop() }
        let client = try connect(provider, rig)
        client.didReceiveMessage(client, try state(), 1)
        client.didReceiveMessage(client, try position(rig), 2)
        client.didReceiveMessage(client, CocoaMQTTMessage(topic: VehicleTrackingWire.controlTopic, string: "{}"), 3)
        XCTAssertTrue(provider.currentPositions.isEmpty)
        client.didReceiveMessage(client, try state(), 4)
        client.didReceiveMessage(client, try position(rig), 5)
        client.didSubscribeTopics(client, [:], [VehicleTrackingWire.controlTopic])
        XCTAssertTrue(provider.currentPositions.isEmpty)
    }

    func testCheckpointFallaCerradoYObservadoContinua() throws {
        let rig = Rig(); rig.failWrite = true
        let provider = provider(rig); defer { provider.stop() }
        let client = try connect(provider, rig)
        client.didReceiveMessage(client, try state(), 1)
        client.didReceiveMessage(client, try position(rig), 2)
        client.didReceiveMessage(client, try position(rig, simulated: false), 3)
        XCTAssertEqual(provider.currentPositions.map(\.id), ["observed-bus"])
    }

    func testCheckpointCorruptoNoRestauraPermiso() throws {
        let rig = Rig(); rig.failRead = true
        let provider = provider(rig); defer { provider.stop() }
        let client = try connect(provider, rig)
        client.didReceiveMessage(client, try state(), 1)
        client.didReceiveMessage(client, try position(rig), 2)
        XCTAssertTrue(provider.currentPositions.isEmpty)
    }

    func testForegroundNoReutilizaAutorizacionEnMemoria() throws {
        let rig = Rig(); let provider = provider(rig); defer { provider.stop() }
        let client = try connect(provider, rig)
        client.didReceiveMessage(client, try state(), 1)
        client.didReceiveMessage(client, try position(rig), 2)
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertTrue(provider.currentPositions.isEmpty)
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        client.didReceiveMessage(client, try position(rig), 3)
        XCTAssertTrue(provider.currentPositions.isEmpty)
        client.didReceiveMessage(client, try state(), 4)
        client.didReceiveMessage(client, try position(rig), 5)
        XCTAssertEqual(provider.currentPositions.count, 1)
    }

    func testPresentacionRenuevaSocketSinTerminarStreamNiAceptarCallbacksViejos() async throws {
        let rig = Rig(); let provider = provider(rig, readOnly: true); defer { provider.stop() }
        let old = try connect(provider, rig)
        var iterator = provider.positions().makeAsyncIterator()
        old.didReceiveMessage(old, try state(), 1)
        old.didReceiveMessage(old, try position(rig), 2)
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.post(name: UIScene.didEnterBackgroundNotification, object: nil)
        XCTAssertTrue(provider.currentPositions.isEmpty)
        XCTAssertFalse(old.autoReconnect)
        NotificationCenter.default.post(name: UIScene.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(rig.clients.count, 2)
        let fresh = try XCTUnwrap(rig.clients.last)
        XCTAssertFalse(old === fresh)
        old.didConnectAck(old, .accept)
        old.didReceiveMessage(old, try state(), 3)
        old.didReceiveMessage(old, try position(rig), 4)
        XCTAssertTrue(provider.currentPositions.isEmpty)
        fresh.didConnectAck(fresh, .accept)
        fresh.didSubscribeTopics(fresh, [VehicleTrackingWire.controlTopic: 1] as NSDictionary, [])
        fresh.didReceiveMessage(fresh, try position(rig), 5)
        XCTAssertTrue(provider.currentPositions.isEmpty)
        fresh.didReceiveMessage(fresh, try state(), 6)
        fresh.didReceiveMessage(fresh, try position(rig), 7)
        let value = await iterator.next()
        XCTAssertEqual(value?.count, 1)
        XCTAssertTrue(provider.keepsConnectionWhileMapHidden)
    }

    func testPresentacionVuelveAControlOffSinReponerPosiciones() throws {
        let rig = Rig(); let provider = provider(rig, readOnly: true); defer { provider.stop() }
        let old = try connect(provider, rig)
        old.didReceiveMessage(old, try state(), 1)
        old.didReceiveMessage(old, try position(rig), 2)
        NotificationCenter.default.post(name: UIScene.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.post(name: UIScene.didActivateNotification, object: nil)
        let fresh = try XCTUnwrap(rig.clients.last)
        fresh.didConnectAck(fresh, .accept)
        fresh.didSubscribeTopics(fresh, [VehicleTrackingWire.controlTopic: 1] as NSDictionary, [])
        fresh.didReceiveMessage(fresh, try state(["enabled":false,"controlRevision":4,"validUntil":1000]), 3)
        fresh.didReceiveMessage(fresh, try position(rig), 4)
        XCTAssertTrue(provider.currentPositions.isEmpty)
    }

    func testCallbackDeClienteAnteriorNoRevocaNiRepueblaNuevaConexion() throws {
        let rig = Rig(); let provider = provider(rig); defer { provider.stop() }
        let old = try connect(provider, rig)
        provider.stop()
        let current = try connect(provider, rig)
        current.didReceiveMessage(current, try state(), 1)
        current.didReceiveMessage(current, try position(rig), 2)
        old.didDisconnect(old, nil)
        old.didReceiveMessage(old, try state(["enabled": false, "controlRevision": 4, "validUntil": 1000]), 3)
        XCTAssertEqual(provider.currentPositions.count, 1)
    }

    func testCompatibilidadNoMezclaLegadoConProduccionSintetica() throws {
        let rig = Rig(); let provider = provider(rig, legacy: .whileSimulationDisabled); defer { provider.stop() }
        let client = try connect(provider, rig)
        client.didReceiveMessage(client, try position(rig, simulated: false, legacy: true), 1)
        XCTAssertEqual(provider.currentPositions.first?.dataOrigin, .legacyUnknown)
        client.didReceiveMessage(client, try state(), 2)
        XCTAssertTrue(provider.currentPositions.isEmpty)
        client.didReceiveMessage(client, try position(rig, simulated: false, legacy: true), 3)
        XCTAssertTrue(provider.currentPositions.isEmpty)
    }

    func testVencimientoSeAplicaAntesDeProcesarOtroVehiculo() throws {
        let rig = Rig(); let provider = provider(rig); defer { provider.stop() }
        let client = try connect(provider, rig)
        client.didReceiveMessage(client, try state(), 1)
        client.didReceiveMessage(client, try position(rig), 2)
        rig.now = .init(wall: 1015, uptime: 115)
        client.didReceiveMessage(client, try position(rig, simulated: false), 3)
        XCTAssertEqual(provider.currentPositions.map(\.id), ["observed-bus"])
    }
}
