import Foundation
import Combine
import CocoaMQTT

struct RouteChangeAlert: Codable, Identifiable, Equatable {
    let id: String
    let routeId: String
    let reason: String
    let lat: Double
    let lon: Double
    let place: String
    let confirmations: Int
    let expiresAt: TimeInterval
}

private struct RouteChangeSnapshot: Decodable {
    let schemaVersion: Int
    let timestamp: TimeInterval
    let alerts: [RouteChangeAlert]
}

private struct RouteChangeReceipt: Decodable {
    let requestId: String
    let accepted: Bool
    let code: String
}

/// Canal independiente: no modifica posiciones, rutas ni estimaciones de buses.
final class RouteChangesService: ObservableObject {
    @Published private(set) var alerts: [RouteChangeAlert] = []
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
        let client = CocoaMQTT(clientID: "rutautp-changes-\(UUID().uuidString)",
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
            client.subscribe([( "rutautp/cambios/estado", .qos1),
                              ("rutautp/cambios/\(self.principal)/recibo", .qos1)])
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

    func send(routeID: String, reason: String, lat: Double, lon: Double, place: String) {
        guard ready, !sending, let mqtt else { return }
        let id = UUID().uuidString
        let body: [String: Any] = ["schemaVersion": 1, "requestId": id,
                                  "routeId": routeID, "reason": reason,
                                  "lat": lat, "lon": lon, "place": place,
                                  "timestamp": Date().timeIntervalSince1970]
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let json = String(data: data, encoding: .utf8) else { return }
        pendingID = id
        sending = true
        result = nil
        sentAt = Date().timeIntervalSince1970
        mqtt.publish("rutautp/cambios/\(principal)/reporte", withString: json, qos: .qos1, retained: false)
    }

    private func refresh() {
        let now = Date().timeIntervalSince1970
        let available = running && subscribed && lastSnapshot.map { now - $0 < 20 } == true
        if ready != available { ready = available }
        let current = available ? alerts.filter { $0.expiresAt > now } : []
        if alerts != current { alerts = current }
        if sending, now - sentAt >= 12 {
            sending = false
            pendingID = nil
            result = L.t("No pudimos confirmar la recepción. Intenta de nuevo cuando haya conexión.",
                         "We couldn't confirm receipt. Try again when connected.")
        }
    }

    private func receive(_ data: Data, topic: String) {
        let now = Date().timeIntervalSince1970
        if topic == "rutautp/cambios/estado",
           data.count <= 300_000,
           let snapshot = try? JSONDecoder().decode(RouteChangeSnapshot.self, from: data),
           snapshot.schemaVersion == 1, snapshot.timestamp.isFinite,
           (-10...20).contains(now - snapshot.timestamp), snapshot.alerts.count <= 500 {
            // Un snapshot tardío no debe sustituir uno más reciente.
            guard lastSnapshot.map({ snapshot.timestamp >= $0 }) ?? true else { return }
            lastSnapshot = snapshot.timestamp
            var seen = Set<String>()
            let current = snapshot.alerts.filter {
                $0.confirmations >= 2 && $0.expiresAt.isFinite && $0.expiresAt > now
                && $0.expiresAt <= now + 910 && (-90...90).contains($0.lat)
                && (-180...180).contains($0.lon) && $0.place.count <= 120
                && ["works", "closure", "detour"].contains($0.reason)
                && seen.insert($0.id).inserted
            }
            if alerts != current { alerts = current }
            refresh()
        } else if topic == "rutautp/cambios/\(principal)/recibo",
                  let receipt = try? JSONDecoder().decode(RouteChangeReceipt.self, from: data),
                  receipt.requestId == pendingID {
            sending = false
            pendingID = nil
            if receipt.accepted {
                result = receipt.code == "confirmed"
                    ? L.t("Reporte recibido. El cambio ya cuenta con al menos dos cuentas distintas.",
                          "Report received. At least two different accounts now support this change.")
                    : L.t("Reporte recibido. Queda pendiente: hace falta otra cuenta que confirme el mismo cambio.",
                          "Report received and pending: another account must confirm the same change.")
            } else {
                switch receipt.code {
                case "off_route":
                    result = L.t("El punto está lejos de esta ruta. Revisa la línea y el lugar.",
                                 "The point is far from this route. Check the line and location.")
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
