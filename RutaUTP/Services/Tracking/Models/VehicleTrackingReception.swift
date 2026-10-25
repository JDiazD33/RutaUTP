import Foundation
import CryptoKit

/// Políticas internas de despliegue; no son interruptores públicos.
enum LegacyVehicleCompatibility {
    case disabled
    case whileSimulationDisabled
}

struct VehicleReceptionTime {
    let wall: TimeInterval
    let uptime: TimeInterval

    static var now: Self {
        Self(wall: Date().timeIntervalSince1970, uptime: ProcessInfo.processInfo.systemUptime)
    }
}

private struct WireKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

enum VehicleTrackingWire {
    static let maximumBytes = 4096
    static let maximumRevision: UInt64 = 9_007_199_254_740_991
    static let controlTopic = "rutautp/simulacion/estado"

    static func uuid(_ text: String) -> String? {
        guard text.utf8.count == 36, let value = UUID(uuidString: text),
              value.uuidString.lowercased() == text.lowercased() else { return nil }
        return value.uuidString.lowercased()
    }

    static func identifier(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        func alphanumeric(_ b: UInt8) -> Bool {
            (48...57).contains(b) || (65...90).contains(b) || (97...122).contains(b)
        }
        return !bytes.isEmpty && bytes.count <= 128 && alphanumeric(bytes[0])
            && bytes.allSatisfy { alphanumeric($0) || [58, 46, 95, 45].contains($0) }
    }

    static func keys(_ decoder: Decoder) throws -> Set<String> {
        Set(try decoder.container(keyedBy: WireKey.self).allKeys.map(\.stringValue))
    }

    static func invalid(_ decoder: Decoder) -> DecodingError {
        .dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Contrato MQTT inválido"))
    }

    static func position(data: Data, topic: String, retained: Bool = false) -> VehiclePosition? {
        guard data.count <= maximumBytes, !retained,
              let decoded = try? JSONDecoder().decode(VehiclePositionWire.self, from: data) else { return nil }
        let parts = topic.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == "rutautp", parts[1] == "vehiculos",
              parts[2] == decoded.position.id, parts[3] == "posicion" else { return nil }
        return decoded.position
    }

    static func control(data: Data) -> SimulationControlState? {
        guard data.count <= maximumBytes else { return nil }
        return try? JSONDecoder().decode(SimulationControlState.self, from: data)
    }
}

private struct VehiclePositionWire: Decodable {
    let position: VehiclePosition
    private enum Keys: String, CodingKey {
        case vehicleId, routeId, linea, lat, lon, speed, heading, timestamp
        case schemaVersion, dataOrigin, simulationRunId, controlRevision
    }

    init(from decoder: Decoder) throws {
        let keys = try VehicleTrackingWire.keys(decoder)
        let legacyKeys: Set<String> = ["vehicleId", "routeId", "linea", "lat", "lon", "speed", "heading", "timestamp"]
        let values = try decoder.container(keyedBy: Keys.self)
        let isLegacy = !keys.contains("schemaVersion")
        guard keys == (isLegacy ? legacyKeys : legacyKeys.union(["schemaVersion", "dataOrigin", "simulationRunId", "controlRevision"]))
        else { throw VehicleTrackingWire.invalid(decoder) }
        let id = try values.decode(String.self, forKey: .vehicleId)
        let route = try values.decode(String.self, forKey: .routeId)
        let line = try values.decode(String.self, forKey: .linea)
        let lat = try values.decode(Double.self, forKey: .lat)
        let lon = try values.decode(Double.self, forKey: .lon)
        let speed = try values.decode(Double.self, forKey: .speed)
        let heading = try values.decode(Double.self, forKey: .heading)
        let timestamp = try values.decode(Double.self, forKey: .timestamp)
        guard VehicleTrackingWire.identifier(id), VehicleTrackingWire.identifier(route),
              !line.isEmpty, line.count <= 128, line == line.trimmingCharacters(in: .whitespacesAndNewlines),
              line.rangeOfCharacter(from: .controlCharacters) == nil,
              lat.isFinite, abs(lat) <= 90, lon.isFinite, abs(lon) <= 180,
              speed.isFinite, heading.isFinite, timestamp.isFinite, timestamp >= 0
        else { throw VehicleTrackingWire.invalid(decoder) }
        var origin: VehicleDataOrigin = .legacyUnknown
        var run: String?
        var revision: UInt64?
        if !isLegacy {
            guard try values.decode(Int.self, forKey: .schemaVersion) == 2 else { throw VehicleTrackingWire.invalid(decoder) }
            origin = try values.decode(VehicleDataOrigin.self, forKey: .dataOrigin)
            guard speed == -1 || (0...30).contains(speed), heading == -1 || (0..<360).contains(heading)
            else { throw VehicleTrackingWire.invalid(decoder) }
            switch origin {
            case .observed:
                guard try values.decodeNil(forKey: .simulationRunId), try values.decodeNil(forKey: .controlRevision)
                else { throw VehicleTrackingWire.invalid(decoder) }
            case .simulated:
                let text = try values.decode(String.self, forKey: .simulationRunId)
                revision = try values.decode(UInt64.self, forKey: .controlRevision)
                run = VehicleTrackingWire.uuid(text)
                guard let run, let revision, revision > 0, revision <= VehicleTrackingWire.maximumRevision,
                      id.hasPrefix("sim:\(run):"), id.count > "sim:\(run):".count
                else { throw VehicleTrackingWire.invalid(decoder) }
            case .legacyUnknown, .unknown:
                throw VehicleTrackingWire.invalid(decoder)
            }
        }
        if origin != .simulated && id.lowercased().hasPrefix("sim:") { throw VehicleTrackingWire.invalid(decoder) }
        position = VehiclePosition(id: id, linea: line, routeId: route, lat: lat, lon: lon,
            heading: heading, speed: speed, timestamp: timestamp, dataOrigin: origin,
            simulationRunId: run, controlRevision: revision)
    }
}

struct SimulationControlState: Codable, Equatable {
    let schemaVersion: Int
    let enabled: Bool
    let runId: String?
    let controlRevision: UInt64
    let issuedAt: TimeInterval
    let validUntil: TimeInterval
    let serviceEndsAt: TimeInterval
    let timeZone: String

    private enum Keys: String, CodingKey {
        case schemaVersion, enabled, runId, controlRevision, issuedAt, validUntil, serviceEndsAt, timeZone
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: Keys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(enabled, forKey: .enabled)
        try values.encode(runId, forKey: .runId) // null explícito también en checkpoint
        try values.encode(controlRevision, forKey: .controlRevision)
        try values.encode(issuedAt, forKey: .issuedAt)
        try values.encode(validUntil, forKey: .validUntil)
        try values.encode(serviceEndsAt, forKey: .serviceEndsAt)
        try values.encode(timeZone, forKey: .timeZone)
    }

    init(from decoder: Decoder) throws {
        guard try VehicleTrackingWire.keys(decoder) == Set(["schemaVersion", "enabled", "runId", "controlRevision",
            "issuedAt", "validUntil", "serviceEndsAt", "timeZone"]) else { throw VehicleTrackingWire.invalid(decoder) }
        let values = try decoder.container(keyedBy: Keys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        enabled = try values.decode(Bool.self, forKey: .enabled)
        let text = try values.decodeIfPresent(String.self, forKey: .runId)
        runId = text.flatMap(VehicleTrackingWire.uuid)
        controlRevision = try values.decode(UInt64.self, forKey: .controlRevision)
        issuedAt = try values.decode(Double.self, forKey: .issuedAt)
        validUntil = try values.decode(Double.self, forKey: .validUntil)
        serviceEndsAt = try values.decode(Double.self, forKey: .serviceEndsAt)
        timeZone = try values.decode(String.self, forKey: .timeZone)
        guard schemaVersion == 1, timeZone == "America/Lima", controlRevision <= VehicleTrackingWire.maximumRevision,
              text == nil || runId != nil, [issuedAt, validUntil, serviceEndsAt].allSatisfy({ $0.isFinite && $0 >= 0 }),
              controlRevision != 0 || (!enabled && runId == nil)
        else { throw VehicleTrackingWire.invalid(decoder) }
        if enabled {
            guard runId != nil, controlRevision > 0, issuedAt < validUntil, validUntil <= serviceEndsAt,
                  validUntil - issuedAt <= 15 else { throw VehicleTrackingWire.invalid(decoder) }
        } else if validUntil != issuedAt {
            throw VehicleTrackingWire.invalid(decoder)
        }
    }
}

/// Solo persiste evidencia de revisión/revocación; nunca restaura un permiso.
struct SimulationControlCheckpoint: Codable, Equatable {
    let version: Int
    let lastControl: SimulationControlState?
    let retiredRuns: Set<String>
    let exhausted: Bool

    func validated() throws -> Self {
        guard version == 1, retiredRuns.count <= 256,
              retiredRuns.allSatisfy({ VehicleTrackingWire.uuid($0) == $0 }),
              exhausted || lastControl?.enabled != true || !retiredRuns.contains(lastControl?.runId ?? "")
        else { throw CocoaError(.fileReadCorruptFile) }
        return self
    }

    /// Varios proveedores del mismo endpoint comparten el archivo. Ninguno
    /// puede guardar una revisión menor ni perder revocaciones del otro.
    func merging(_ existing: Self?) throws -> Self {
        _ = try validated()
        guard let existing else { return self }
        _ = try existing.validated()
        let currentRevision = existing.lastControl?.controlRevision ?? 0
        let nextRevision = lastControl?.controlRevision ?? 0
        guard nextRevision >= currentRevision else { throw CocoaError(.fileWriteUnknown) }
        var latest = lastControl
        if nextRevision == currentRevision, let old = existing.lastControl, let new = lastControl {
            guard old.enabled == new.enabled, old.runId == new.runId, old.serviceEndsAt == new.serviceEndsAt,
                  old.issuedAt != new.issuedAt || old == new else { throw CocoaError(.fileWriteUnknown) }
            if old.issuedAt > new.issuedAt { latest = old }
        }
        let allRuns = retiredRuns.union(existing.retiredRuns)
        return try Self(version: 1, lastControl: latest, retiredRuns: Set(allRuns.sorted().prefix(256)),
                        exhausted: exhausted || existing.exhausted || allRuns.count > 256).validated()
    }
}

struct SimulationControlGate {
    private(set) var lastControl: SimulationControlState?
    private(set) var retiredRuns: Set<String> = []
    private(set) var exhausted = false
    private var lease: SimulationControlState?
    private var expiresUptime: TimeInterval?
    private var previousClock: VehicleReceptionTime?
    private var requireIssuedAfter: TimeInterval?
    private(set) var legacyBlocked = false

    init(checkpoint: SimulationControlCheckpoint? = nil) {
        lastControl = checkpoint?.lastControl
        retiredRuns = checkpoint?.retiredRuns ?? []
        exhausted = checkpoint?.exhausted ?? false
        legacyBlocked = lastControl?.enabled == true
    }

    var checkpoint: SimulationControlCheckpoint {
        SimulationControlCheckpoint(version: 1, lastControl: lastControl, retiredRuns: retiredRuns, exhausted: exhausted)
    }

    mutating func invalidate(blockLegacy: Bool = false) {
        lease = nil
        expiresUptime = nil
        if blockLegacy { legacyBlocked = true }
    }

    @discardableResult
    mutating func checkTime(_ now: VehicleReceptionTime) -> Bool {
        guard now.wall.isFinite, now.wall >= 0, now.uptime.isFinite, now.uptime >= 0 else {
            invalidate(blockLegacy: true)
            return false
        }
        defer { previousClock = now }
        if let previousClock {
            let civil = now.wall - previousClock.wall
            let monotonic = now.uptime - previousClock.uptime
            if civil < 0 || monotonic < 0 || abs(civil - monotonic) > 2 {
                requireIssuedAfter = lastControl?.issuedAt
                invalidate(blockLegacy: true)
                return false
            }
        }
        return true
    }

    /// `true` significa control aceptado, no permiso activo. El llamador guarda
    /// el checkpoint antes de admitir posiciones y bloquea si falla esa escritura.
    @discardableResult
    mutating func receive(_ state: SimulationControlState, at now: VehicleReceptionTime) -> Bool {
        let clockOK = checkTime(now)
        guard !exhausted, clockOK || !state.enabled else { return false }
        guard state.issuedAt <= now.wall + 10 else { invalidate(blockLegacy: true); return false }
        if let lastControl {
            if state.controlRevision < lastControl.controlRevision { return false }
            if state.controlRevision == lastControl.controlRevision {
                guard state.enabled == lastControl.enabled, state.runId == lastControl.runId,
                      state.serviceEndsAt == lastControl.serviceEndsAt else { invalidate(blockLegacy: true); return false }
                if state.issuedAt < lastControl.issuedAt { return false }
                if state.issuedAt == lastControl.issuedAt && state != lastControl { invalidate(blockLegacy: true); return false }
            }
        }
        if state.enabled, let run = state.runId, retiredRuns.contains(run) {
            invalidate(blockLegacy: true)
            return false
        }
        if let lastControl, state.controlRevision > lastControl.controlRevision,
           let oldRun = lastControl.runId, oldRun != state.runId || !state.enabled {
            retire(oldRun)
        }
        if !state.enabled, let run = state.runId { retire(run) }
        guard !exhausted else { invalidate(blockLegacy: true); return false }
        let duplicate = state == lastControl
        lastControl = state
        legacyBlocked = state.enabled
        if !state.enabled { invalidate(); return true }
        if let requireIssuedAfter, state.issuedAt <= requireIssuedAfter { invalidate(blockLegacy: true); return true }
        if !duplicate || lease == nil {
            lease = state
            expiresUptime = now.uptime + min(15, max(0, min(state.validUntil, state.serviceEndsAt) - now.wall))
        }
        return true
    }

    private mutating func retire(_ run: String) {
        if retiredRuns.count >= 256 && !retiredRuns.contains(run) { exhausted = true; return }
        retiredRuns.insert(run)
    }

    func permits(_ position: VehiclePosition, at now: VehicleReceptionTime,
                 legacy: LegacyVehicleCompatibility) -> Bool {
        switch position.dataOrigin {
        case .observed: return true
        case .legacyUnknown: return legacy == .whileSimulationDisabled && !legacyBlocked && !exhausted
        case .unknown: return false
        case .simulated:
            guard !exhausted, let lease, let expiresUptime,
                  now.wall >= lease.issuedAt, now.wall < min(lease.validUntil, lease.serviceEndsAt),
                  now.uptime < expiresUptime, position.simulationRunId == lease.runId,
                  position.controlRevision == lease.controlRevision else { return false }
            return true
        }
    }

    func remainingAuthorization(at now: VehicleReceptionTime) -> TimeInterval? {
        guard let lease, let expiresUptime else { return nil }
        return max(0, min(expiresUptime - now.uptime, min(lease.validUntil, lease.serviceEndsAt) - now.wall))
    }
}

/// Una copia antigua de todo el contenedor no puede detectarse sin referencia
/// externa. Corrupción/fallo de escritura cierran únicamente la rama sintética.
struct SimulationCheckpointFile {
    let url: URL

    init(url: URL) { self.url = url }

    init(endpointIdentity: String) {
        let key = SHA256.hash(data: Data(endpointIdentity.utf8)).map { String(format: "%02x", $0) }.joined()
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        url = base.appendingPathComponent("RutaUTP/TrackingControl", isDirectory: true).appendingPathComponent(key + ".json")
    }

    func read() throws -> SimulationControlCheckpoint? {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        }
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 32_769) ?? Data()
        guard data.count <= 32_768 else { throw CocoaError(.fileReadCorruptFile) }
        return try JSONDecoder().decode(SimulationControlCheckpoint.self, from: data).validated()
    }

    func write(_ checkpoint: SimulationControlCheckpoint) throws {
        let merged = try checkpoint.merging(read())
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(merged).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        if merged.exhausted { throw CocoaError(.fileWriteUnknown) }
    }
}
