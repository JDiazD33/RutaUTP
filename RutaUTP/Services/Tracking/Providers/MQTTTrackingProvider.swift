import Foundation
import CocoaMQTT

@MainActor
final class MQTTTrackingProvider: VehicleTrackingProviding {

    let source: VehicleTrackingSource = .real

    private var mqtt: CocoaMQTT?
    private let configuration: MQTTConfiguration
    private let conectar: @MainActor (CocoaMQTT) -> Bool
    private var generation = UUID()
    private let topic = "rutautp/vehiculos/+/posicion"

    private var continuation:
        AsyncStream<[VehiclePosition]>.Continuation?

    private var stream: AsyncStream<[VehiclePosition]>?

    private var positionsByID: [String: VehiclePosition] = [:]

    private(set) var currentPositions: [VehiclePosition] = []

    /// Cada cuánto se revisa si algún vehículo dejó de transmitir.
    ///
    /// El límite de obsolescencia es 45 s; barrer cada 10 s acota el
    /// retraso máximo con el que un vehículo desaparece del mapa.
    private static let stalenessSweepInterval: TimeInterval = 10

    private var stalenessTimer: Timer?

    /// Indica si el proveedor está en marcha.
    ///
    /// Los callbacks de CocoaMQTT llegan por su propio hilo y pueden quedar en
    /// vuelo cuando se llama a `stop()`. Sin esta bandera, un mensaje tardío
    /// repoblaba el estado justo después de detenerse y la siguiente sesión
    /// arrancaba con vehículos fantasma.
    private var isRunning = false

    /// Reconstruye el snapshot descartando vehículos obsoletos.
    ///
    /// **Retira además las entradas del diccionario.** Antes solo se filtraba
    /// la lista visible y `positionsByID` conservaba todo lo visto desde el
    /// arranque: en una conexión larga, los identificadores caducados se
    /// acumulaban sin límite, y bastaba con que un mensaje cualquiera llegara
    /// para que la reconstrucción los volviera a considerar.
    private func refreshCurrentPositions(now: TimeInterval) {
        let limite = VehiclePositionSanitizer.stalenessLimit

        positionsByID = positionsByID.filter {
            now - $0.value.timestamp <= limite
        }

        currentPositions = positionsByID
            .values
            .sorted {
                $0.id < $1.id
            }
    }

    /// Arranca el barrido periódico de posiciones obsoletas.
    ///
    /// Sin este temporizador la poda dependía de que llegara un mensaje
    /// cualquiera: si todas las balizas callaban a la vez, las últimas
    /// posiciones conocidas se quedaban dibujadas indefinidamente.
    private func startStalenessSweep() {
        guard stalenessTimer == nil else {
            return
        }

        let token = generation
        stalenessTimer = Timer.scheduledTimer(
            withTimeInterval: Self.stalenessSweepInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning, self.generation == token else { return }
                self.sweepStalePositions()
            }
        }
    }

    private func stopStalenessSweep() {
        stalenessTimer?.invalidate()
        stalenessTimer = nil
    }

    /// Retira del mapa los vehículos que dejaron de transmitir.
    ///
    /// Solo emite cuando el snapshot cambia, para no despertar al
    /// consumidor en cada tick sin motivo.
    private func sweepStalePositions() {
        let previous = currentPositions

        refreshCurrentPositions(now: Date().timeIntervalSince1970)

        guard currentPositions != previous else {
            return
        }

        #if DEBUG
        print(
            "[MQTT] Barrido: \(previous.count) → " +
            "\(currentPositions.count) vehículos"
        )
        #endif

        continuation?.yield(currentPositions)
    }

    init(configuration: MQTTConfiguration,
         conectar: @escaping @MainActor (CocoaMQTT) -> Bool = { $0.connect() }) {
        self.configuration = configuration
        self.conectar = conectar
    }

    private func makeClient() -> CocoaMQTT {
        let clientID = "rutautp-ios-\(UUID().uuidString)"

        let mqtt = CocoaMQTT(
            clientID: clientID,
            host: configuration.host,
            port: configuration.port
        )

        mqtt.username = configuration.username
        mqtt.password = configuration.password
        mqtt.keepAlive = 30
        mqtt.cleanSession = true
        mqtt.autoReconnect = true
        mqtt.enableSSL = configuration.useTLS

        // Con una CA propia (Mosquitto con certificado autofirmado) el
        // certificado no está en el almacén del sistema y el handshake
        // falla. Se declara la CA en lugar de desactivar la validación.
        if !configuration.trustedCACertificates.isEmpty {
            mqtt.trustedServerCertificates =
                configuration.trustedCACertificates
        }

        return mqtt
    }

    func start() {
        guard !isRunning else { return }

        prepareStreamIfNeeded()
        generation = UUID()
        let client = makeClient()
        mqtt = client
        configureCallbacks(for: client)
        isRunning = true
        startStalenessSweep()

        #if DEBUG
        print("[MQTT] Intentando conectar con el broker...")
        #endif

        let aceptado = conectar(client)
        guard isRunning, mqtt === client else { return }
        if !aceptado {
            // Un fallo al iniciar el socket no debe bloquear un start posterior.
            mqtt = nil
            isRunning = false
            generation = UUID()
            client.autoReconnect = false
            client.disconnect()
            stopStalenessSweep()
        }
    }

    func stop() {
        isRunning = false
        generation = UUID()
        let previous = mqtt
        mqtt = nil
        previous?.autoReconnect = false
        previous?.disconnect()

        stopStalenessSweep()

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

        // Cada emisión contiene toda la flota actual: un lector retrasado
        // necesita el último snapshot, sin acumular estados intermedios.
        stream = AsyncStream<[VehiclePosition]>(bufferingPolicy: .bufferingNewest(1)) { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }

            self.continuation = continuation
            continuation.yield(self.currentPositions)
        }
    }

    private func configureCallbacks(for mqtt: CocoaMQTT) {
        mqtt.didConnectAck = { [weak self] mqtt, acknowledgment in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning, self.mqtt === mqtt else { return }

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
        }

        mqtt.didSubscribeTopics = { _, success, failed in
            #if DEBUG
            print("[MQTT] Suscripciones aceptadas: \(success)")

            if !failed.isEmpty {
                print("[MQTT] Suscripciones rechazadas: \(failed)")
            }
            #endif
        }

        mqtt.didReceiveMessage = { [weak self] client, message, _ in
            guard let json = message.string else { return }
            let topic = message.topic
            // La decodificación usa solo valores locales en la cola de CocoaMQTT.
            guard let position = Self.decodePosition(json: json, topic: topic) else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isRunning, self.mqtt === client else { return }
                self.process(position: position, topic: topic)
            }
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

    nonisolated private static func decodePosition(
        json: String,
        topic: String
    ) -> VehiclePosition? {
        guard let data = json.data(using: .utf8) else {
            return nil
        }

        do {
            let dto = try JSONDecoder().decode(
                VehiclePositionMessage.self,
                from: data
            )

            return VehiclePosition(
                id: dto.vehicleId,
                linea: dto.linea,
                routeId: dto.routeId,
                lat: dto.lat,
                lon: dto.lon,
                heading: dto.heading,
                speed: dto.speed,
                timestamp: dto.timestamp
            )

        } catch {
            #if DEBUG
            print("[MQTT] JSON inválido en \(topic): " + error.localizedDescription)
            #endif
            return nil
        }
    }

    private func process(position: VehiclePosition, topic: String) {
        // El broker es un canal compartido: nada garantiza que
        // el mensaje entrante sea razonable, así que se filtra
        // antes de tocar el estado que alimenta el mapa.
        guard let position = VehiclePositionSanitizer.sanitize(
            position
        ) else {
            #if DEBUG
            print(
                "[MQTT] Posición inválida u obsoleta en \(topic): " +
                "\(position.id)"
            )
            #endif

            return
        }

        // Un mensaje atrasado no debe retroceder un vehículo ya
        // actualizado. El broker no garantiza el orden entre
        // publicaciones distintas, así que la comprobación es por
        // marca de tiempo y no por orden de llegada.
        if let conocida = self.positionsByID[position.id],
           position.timestamp <= conocida.timestamp {
            #if DEBUG
            print(
                "[MQTT] Posición atrasada ignorada: " +
                "\(position.id)"
            )
            #endif

            return
        }

        self.positionsByID[position.id] = position

        self.refreshCurrentPositions(
            now: Date().timeIntervalSince1970
        )

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
}

private struct VehiclePositionMessage: Decodable {
    let vehicleId: String
    let routeId: String
    let linea: String
    let lat: Double
    let lon: Double
    let speed: Double
    let heading: Double
    let timestamp: TimeInterval
}
