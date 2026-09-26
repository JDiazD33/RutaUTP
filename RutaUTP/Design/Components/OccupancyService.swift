import Foundation
import Combine
import CocoaMQTT

enum BusOccupancyState: String, Codable, CaseIterable {
    case empty, full

    var title: String {
        self == .empty ? L.t("Vacío", "Empty") : L.t("Lleno", "Full")
    }
}

struct OccupancyReading: Codable, Identifiable, Equatable {
    var id: String { vehicleId }
    let vehicleId: String
    let state: BusOccupancyState
    let confirmations: Int
    let updatedAt: TimeInterval
    let expiresAt: TimeInterval

    func isValid(at now: TimeInterval) -> Bool {
        !vehicleId.isEmpty && vehicleId.count <= 200 && confirmations >= 2
        && updatedAt.isFinite && expiresAt.isFinite
        && (-10...180).contains(now - updatedAt)
        && expiresAt > now && expiresAt <= updatedAt + 180
    }
}

private struct OccupancySnapshot: Decodable {
    let schemaVersion: Int
    let timestamp: TimeInterval
    let buses: [OccupancyReading]
}

private struct OccupancyReceipt: Decodable {
    let requestId: String
    let accepted: Bool
    let code: String
}

/// Canal independiente: no modifica posiciones, rutas ni estimaciones de buses.
final class OccupancyService: ObservableObject {
    @Published private(set) var buses: [OccupancyReading] = []
    @Published private(set) var ready = false
    @Published private(set) var sending = false
    @Published private(set) var result: String?
    @Published private(set) var configured = false

    private var mqtt: CocoaMQTT?
    private var principal = ""
    private var running = false
    private var subscribed = false
    private var lastSnapshot: TimeInterval?
    private var pendingID: String?
    private var sentAt: TimeInterval = 0
    private var timer: Timer?

    func start() {
        guard !running else { return }
        guard let config = MQTTConfiguration.fromEnvironment() else { return }
        configured = true
        running = true
        principal = config.username
        let client = CocoaMQTT(clientID: "rutautp-occupancy-\(UUID().uuidString)",
                               host: config.host, port: config.port)
        client.username = config.username
        client.password = config.password
        client.delegateQueue = .main
        client.keepAlive = 30
        client.cleanSession = true
        client.autoReconnect = true
        client.enableSSL = config.useTLS
        if !config.trustedCACertificates.isEmpty {
            client.trustedServerCertificates = config.trustedCACertificates
        }
        client.didConnectAck = { [weak self] client, ack in
            guard let self, self.running, self.mqtt === client, ack == .accept else { return }
            self.subscribed = false
            client.subscribe([( "rutautp/ocupacion/estado", .qos1),
                              ("rutautp/ocupacion/\(self.principal)/recibo", .qos1)])
        }
        client.didSubscribeTopics = { [weak self] client, success, failed in
            guard let self, self.running, self.mqtt === client else { return }
            self.subscribed = failed.isEmpty && success.count == 2
            self.refresh()
        }
        client.didReceiveMessage = { [weak self] client, message, _ in
            guard let self, self.running, self.mqtt === client, let json = message.string,
                  let data = json.data(using: .utf8) else { return }
            self.receive(data, topic: message.topic)
        }
        client.didDisconnect = { [weak self] client, _ in
            guard let self, self.mqtt === client else { return }
            self.subscribed = false
            self.lastSnapshot = nil
            self.refresh()
        }
        mqtt = client
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        _ = client.connect()
    }

    func stop() {
        running = false
        mqtt?.autoReconnect = false
        mqtt?.disconnect()
        mqtt = nil
        timer?.invalidate()
        timer = nil
        subscribed = false
        lastSnapshot = nil
        pendingID = nil
        sending = false
        refresh()
    }

    func send(vehicleID: String, state: BusOccupancyState) {
        guard ready, !sending, let mqtt else { return }
        let id = UUID().uuidString
        let body: [String: Any] = ["schemaVersion": 1, "requestId": id,
                                  "vehicleId": vehicleID, "state": state.rawValue,
                                  "timestamp": Date().timeIntervalSince1970]
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let json = String(data: data, encoding: .utf8) else { return }
        pendingID = id
        sending = true
        result = nil
        sentAt = Date().timeIntervalSince1970
        mqtt.publish("rutautp/ocupacion/\(principal)/reporte", withString: json, qos: .qos1, retained: false)
    }

    private func refresh() {
        let now = Date().timeIntervalSince1970
        let available = running && subscribed && lastSnapshot.map { now - $0 < 20 } == true
        if ready != available { ready = available }
        let current = available ? buses.filter { $0.expiresAt > now } : []
        if buses != current { buses = current }
        if sending, now - sentAt >= 12 {
            sending = false
            pendingID = nil
            result = L.t("No pudimos confirmar la recepción. Intenta de nuevo cuando haya conexión.",
                         "We couldn't confirm receipt. Try again when connected.")
        }
    }

    private func receive(_ data: Data, topic: String) {
        let now = Date().timeIntervalSince1970
        if topic == "rutautp/ocupacion/estado",
           data.count <= 300_000,
           let snapshot = try? JSONDecoder().decode(OccupancySnapshot.self, from: data),
           snapshot.schemaVersion == 1, snapshot.timestamp.isFinite,
           (-10...20).contains(now - snapshot.timestamp), snapshot.buses.count <= 500 {
            // Un snapshot tardío no debe sustituir uno más reciente.
            guard lastSnapshot.map({ snapshot.timestamp >= $0 }) ?? true else { return }
            lastSnapshot = snapshot.timestamp
            var seen = Set<String>()
            let current = snapshot.buses.filter {
                $0.isValid(at: now) && seen.insert($0.id).inserted
            }
            if buses != current { buses = current }
            refresh()
        } else if topic == "rutautp/ocupacion/\(principal)/recibo",
                  let receipt = try? JSONDecoder().decode(OccupancyReceipt.self, from: data),
                  receipt.requestId == pendingID {
            sending = false
            pendingID = nil
            if receipt.accepted {
                result = receipt.code == "confirmed"
                    ? L.t("Reporte recibido. La ocupación ya cuenta con al menos dos cuentas distintas.",
                          "Report received. At least two different accounts now support this occupancy report.")
                    : L.t("Reporte recibido. Aún no hay suficientes reportes coincidentes para confirmar este estado.",
                          "Report received. There are not enough matching reports yet to confirm this state.")
            } else {
                switch receipt.code {
                case "not_onboard":
                    result = L.t("Necesitamos detectarte a bordo de este bus. Activa «Ayudar con ubicaciones» y espera la detección antes de reportar.",
                                 "You must be detected aboard this bus. Enable location contributions and wait for detection before reporting.")
                case "unavailable":
                    result = L.t("Este bus ya no tiene una ubicación reciente. Vuelve a seleccionarlo en el mapa.",
                                 "This bus no longer has a recent position. Select it again on the map.")
                case "rate_limit":
                    result = L.t("Espera 30 segundos entre reportes. Repetirlo no suma otra confirmación.",
                                 "Wait 30 seconds between reports. Repeating it won't add another confirmation.")
                default:
                    result = L.t("No se aceptó el reporte. Revisa los datos e inténtalo de nuevo.",
                                 "Report not accepted. Check the details and try again.")
                }
            }
        }
    }
}
