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
    /// Vía por la que pasa ahora el transporte, si algún reporte la indicó.
    var via: String? = nil
    /// Punto donde retoma su recorrido habitual. Con él se conoce el tramo
    /// que deja de atender; sin él solo se conoce dónde empieza el cambio.
    var endLat: Double? = nil
    var endLon: Double? = nil
    /// Calle nueva como polilínea codificada. El servidor solo la publica
    /// cuando dos cuentas grabaron a bordo trazos que coinciden.
    var path: String? = nil
    /// Incidencia de la presentación: no es un reporte de la comunidad.
    var simulated: Bool? = nil
}

private struct RouteChangeSnapshot: Decodable {
    let schemaVersion: Int
    let timestamp: TimeInterval
    /// Cuentas distintas que exige el servidor. Ausente en servidores antiguos.
    let quorum: Int?
    let alerts: [RouteChangeAlert]
}

private struct RouteChangeReceipt: Decodable {
    let requestId: String
    let accepted: Bool
    let code: String
    let confirmations: Int?
    let required: Int?
}

/// Canal independiente: no modifica posiciones, rutas ni estimaciones de buses.
/// Los avisos confirmados se dibujan sobre el mapa como información añadida.
@MainActor
final class RouteChangesService: ObservableObject {
    private let clock: () -> TimeInterval
    private let deadlineScheduler: ServiceDeadlineScheduler

    init(clock: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.clock = clock
        deadlineScheduler = ServiceDeadlineScheduler(clock: clock)
    }

    @Published private(set) var alerts: [RouteChangeAlert] = []
    @Published private(set) var ready = false
    @Published private(set) var sending = false
    @Published private(set) var result: String?
    @Published private(set) var configured = false
    /// Cuentas distintas necesarias para confirmar, según el último snapshot.
    @Published private(set) var quorum = 2
    /// Recibos aceptados por el servidor. Permite saber que un reporte con
    /// trazo llegó y que el desvío grabado ya no hace falta.
    @Published private(set) var reportesAceptados = 0

    /// Vigencia máxima de un voto en el servidor (24 h) más el margen de reloj.
    private static let vigenciaMaxima: TimeInterval = 24 * 3600 + 10

    private var mqtt: CocoaMQTT?
    private var principal = ""
    private var running = false
    private var subscribed = false
    private var lastSnapshot: TimeInterval?
    private var pendingID: String?
    private var sentAt: TimeInterval = 0

    func start() {
        guard !running else { return }
        guard let config = MQTTConfiguration.contributionFromEnvironment() else { return }
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
            Task { @MainActor [weak self] in
                guard let self, self.running, self.mqtt === client, ack == .accept else { return }
                self.subscribed = false
                self.refresh()
                client.subscribe([( "rutautp/cambios/estado", .qos1),
                                  ("rutautp/cambios/\(self.principal)/recibo", .qos1)])
            }
        }
        client.didSubscribeTopics = { [weak self] client, success, failed in
            Task { @MainActor [weak self] in
                guard let self, self.running, self.mqtt === client else { return }
                self.subscribed = failed.isEmpty && success.count == 2
                self.refresh()
            }
        }
        client.didReceiveMessage = { [weak self] client, message, _ in
            guard let json = message.string, let data = json.data(using: .utf8) else { return }
            let topic = message.topic
            Task { @MainActor [weak self] in
                guard let self, self.running, self.mqtt === client else { return }
                self.receive(data, topic: topic)
            }
        }
        client.didDisconnect = { [weak self] client, _ in
            Task { @MainActor [weak self] in
                guard let self, self.mqtt === client else { return }
                self.subscribed = false
                self.lastSnapshot = nil
                self.refresh()
            }
        }
        mqtt = client
        deadlineScheduler.start { [weak self] in self?.refresh() }
        refresh()
        _ = client.connect()
    }

    func stop() {
        running = false
        mqtt?.autoReconnect = false
        mqtt?.disconnect()
        mqtt = nil
        deadlineScheduler.stop()
        subscribed = false
        lastSnapshot = nil
        pendingID = nil
        sending = false
        refresh()
    }

    func send(routeID: String, reason: String, lat: Double, lon: Double, place: String,
              via: String? = nil, end: (lat: Double, lon: Double)? = nil, path: String? = nil) {
        refresh()
        defer { reprogramarVencimiento() }
        guard ready, !sending, let mqtt else { return }
        let id = UUID().uuidString
        var body: [String: Any] = ["schemaVersion": 1, "requestId": id,
                                  "routeId": routeID, "reason": reason,
                                  "lat": lat, "lon": lon, "place": place,
                                  "timestamp": clock()]
        if let via, via.count >= 3 { body["via"] = via }
        if let end {
            body["endLat"] = end.lat
            body["endLon"] = end.lon
            // El trazo solo vale con el punto donde retoma.
            if let path { body["path"] = path }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let json = String(data: data, encoding: .utf8) else { return }
        let now = clock()
        guard isAvailable(at: now) else { return }
        pendingID = id
        sending = true
        result = nil
        sentAt = now
        mqtt.publish("rutautp/cambios/\(principal)/reporte", withString: json, qos: .qos1, retained: false)
    }

    private func isAvailable(at now: TimeInterval) -> Bool {
        running && subscribed && lastSnapshot.map { now - $0 < 20 } == true
    }

    private func refresh() {
        defer { reprogramarVencimiento() }
        let now = clock()
        let available = isAvailable(at: now)
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

    private func reprogramarVencimiento() {
        guard running else { deadlineScheduler.cancel(); return }
        var next: TimeInterval?
        func include(_ deadline: TimeInterval) {
            guard deadline.isFinite else { return }
            next = next.map { min($0, deadline) } ?? deadline
        }
        if ready, let lastSnapshot {
            include(lastSnapshot + 20)
            for alert in alerts { include(alert.expiresAt) }
        }
        if sending { include(sentAt + 12) }
        deadlineScheduler.schedule(at: next)
    }

    private func receive(_ data: Data, topic: String) {
        defer { refresh() }
        let now = clock()
        if topic == "rutautp/cambios/estado",
           // Con trazos cabe un snapshot mayor; sigue por debajo del paquete
           // máximo de 1 MB del broker.
           data.count <= 900_000,
           let snapshot = try? JSONDecoder().decode(RouteChangeSnapshot.self, from: data),
           snapshot.schemaVersion == 1, snapshot.timestamp.isFinite,
           (-10...20).contains(now - snapshot.timestamp), snapshot.alerts.count <= 500 {
            // Un snapshot tardío no debe sustituir uno más reciente.
            guard lastSnapshot.map({ snapshot.timestamp >= $0 }) ?? true else { return }
            lastSnapshot = snapshot.timestamp
            // Nunca se muestra un aviso con menos de dos cuentas, diga lo que
            // diga el servidor.
            let minimo = max(2, snapshot.quorum ?? 2)
            if quorum != minimo { quorum = minimo }
            var seen = Set<String>()
            let current = snapshot.alerts.filter {
                $0.confirmations >= minimo && $0.expiresAt.isFinite && $0.expiresAt > now
                && $0.expiresAt <= now + Self.vigenciaMaxima && (-90...90).contains($0.lat)
                && (-180...180).contains($0.lon) && $0.place.count <= 120
                && ($0.via?.count ?? 0) <= 80
                && ($0.path?.utf8.count ?? 0) <= 4_000
                && ($0.endLat == nil) == ($0.endLon == nil)
                && $0.endLat.map { (-90...90).contains($0) } != false
                && $0.endLon.map { (-180...180).contains($0) } != false
                && MotivoCambioRuta(rawValue: $0.reason) != nil
                && seen.insert($0.id).inserted
            }.map { aviso -> RouteChangeAlert in
                // Un trazo ilegible no invalida el aviso: se muestra sin calle nueva.
                guard let path = aviso.path, PolilineaCodificada.decodificar(path) == nil else { return aviso }
                var limpio = aviso
                limpio.path = nil
                return limpio
            }
            if alerts != current { alerts = current }
        } else if topic == "rutautp/cambios/\(principal)/recibo",
                  let receipt = try? JSONDecoder().decode(RouteChangeReceipt.self, from: data),
                  receipt.requestId == pendingID, now - sentAt < 12 {
            sending = false
            pendingID = nil
            if receipt.accepted {
                reportesAceptados += 1
                let cuentas = receipt.confirmations ?? 1
                let necesarias = receipt.required ?? quorum
                result = receipt.code == "confirmed"
                    ? L.f("Reporte recibido. Ya lo confirman {0} cuentas distintas y se muestra en el mapa.",
                          "Report received. {0} different accounts now confirm it and it shows on the map.",
                          ["\(cuentas)"])
                    : L.f("Reporte recibido. Van {0} de {1} cuentas distintas necesarias para mostrarlo en el mapa.",
                          "Report received. {0} of the {1} different accounts needed to show it on the map.",
                          ["\(cuentas)", "\(necesarias)"])
            } else {
                switch receipt.code {
                case "off_route":
                    result = L.t("El punto está lejos de esta ruta. Revisa la línea y el lugar.",
                                 "The point is far from this route. Check the line and location.")
                case "invalid_path":
                    result = L.t("No se pudo usar el recorrido grabado. Quítalo y vuelve a enviar en 30 segundos.",
                                 "The recorded route couldn't be used. Remove it and send again in 30 seconds.")
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
