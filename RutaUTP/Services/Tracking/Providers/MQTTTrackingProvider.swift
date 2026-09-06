import Foundation
import CocoaMQTT

final class MQTTTrackingProvider: VehicleTrackingProviding {

    let source: VehicleTrackingSource = .real

    private let mqtt: CocoaMQTT
    private let topic = "rutautp/vehiculos/+/posicion"

    private var continuation:
        AsyncStream<[VehiclePosition]>.Continuation?

    private var stream: AsyncStream<[VehiclePosition]>?

    private var positionsByID: [String: VehiclePosition] = [:]

    private(set) var currentPositions: [VehiclePosition] = []

    init(configuration: MQTTConfiguration) {
        let clientID = "rutautp-ios-\(UUID().uuidString)"

        mqtt = CocoaMQTT(
            clientID: clientID,
            host: configuration.host,
            port: configuration.port
        )

        mqtt.username = configuration.username
        mqtt.password = configuration.password
        mqtt.keepAlive = 30
        mqtt.cleanSession = true
        mqtt.autoReconnect = true

        configureCallbacks()
    }

    func start() {
        guard mqtt.connState == .disconnected else {
            return
        }

        prepareStreamIfNeeded()

        #if DEBUG
        print("[MQTT] Intentando conectar con el broker...")
        #endif

        _ = mqtt.connect()
    }

    func stop() {
        mqtt.disconnect()

        continuation?.finish()
        continuation = nil
        stream = nil

        positionsByID.removeAll()
        currentPositions = []
    }

    func positions() -> AsyncStream<[VehiclePosition]> {
        prepareStreamIfNeeded()

        guard let stream else {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }

        return stream
    }

    private func prepareStreamIfNeeded() {
        guard stream == nil else {
            return
        }

        stream = AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }

            self.continuation = continuation
            continuation.yield(self.currentPositions)
        }
    }

    private func configureCallbacks() {
        mqtt.didConnectAck = { [weak self] mqtt, acknowledgment in
            guard let self else {
                return
            }

            guard acknowledgment == .accept else {
                #if DEBUG
                print(
                    "[MQTT] Conexión rechazada: \(acknowledgment)"
                )
                #endif
                return
            }

            #if DEBUG
            print("[MQTT] Conexión aceptada")
            print("[MQTT] Suscribiendo a \(self.topic)")
            #endif

            mqtt.subscribe(
                self.topic,
                qos: .qos1
            )
        }

        mqtt.didSubscribeTopics = { _, success, failed in
            #if DEBUG
            print("[MQTT] Suscripciones aceptadas: \(success)")

            if !failed.isEmpty {
                print("[MQTT] Suscripciones rechazadas: \(failed)")
            }
            #endif
        }

        mqtt.didReceiveMessage = { [weak self] _, message, _ in
            guard
                let self,
                let json = message.string
            else {
                return
            }

            self.process(
                json: json,
                topic: message.topic
            )
        }

        mqtt.didDisconnect = { _, error in
            #if DEBUG
            if let error {
                print(
                    "[MQTT] Desconectado con error: " +
                    error.localizedDescription
                )
            } else {
                print("[MQTT] Desconectado")
            }
            #endif
        }
    }

    private func process(
        json: String,
        topic: String
    ) {
        guard let data = json.data(using: .utf8) else {
            return
        }

        do {
            let dto = try JSONDecoder().decode(
                VehiclePositionMessage.self,
                from: data
            )

            let position = VehiclePosition(
                id: dto.vehicleId,
                linea: dto.linea,
                lat: dto.lat,
                lon: dto.lon,
                heading: dto.heading,
                speed: dto.speed,
                timestamp: dto.timestamp
            )

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                self.positionsByID[position.id] = position

                self.currentPositions = self.positionsByID
                    .values
                    .sorted {
                        $0.id < $1.id
                    }

                self.continuation?.yield(
                    self.currentPositions
                )

                #if DEBUG
                print(
                    "[MQTT] Posición recibida: " +
                    "\(position.id), línea \(position.linea), " +
                    "\(position.lat), \(position.lon)"
                )
                #endif
            }
        } catch {
            #if DEBUG
            print(
                "[MQTT] JSON inválido en \(topic): " +
                error.localizedDescription
            )
            #endif
        }
    }
}

private struct VehiclePositionMessage: Decodable {
    let vehicleId: String
    let linea: String
    let lat: Double
    let lon: Double
    let speed: Double
    let heading: Double
    let timestamp: TimeInterval
}
