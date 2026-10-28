import Foundation
import CocoaMQTT
import UIKit

@MainActor
final class MQTTTrackingProvider: VehicleTrackingProviding {

    let source: VehicleTrackingSource = .real
    var keepsConnectionWhileMapHidden: Bool { configuration.isReadOnly }

    private var mqtt: CocoaMQTT?
    private let configuration: MQTTConfiguration
    private let conectar: @MainActor (CocoaMQTT) -> Bool
    private var generation = UUID()
    private let topic = "rutautp/vehiculos/+/posicion"
    private let legacyCompatibility: LegacyVehicleCompatibility
    private let clock: @MainActor () -> VehicleReceptionTime
    private let loadCheckpoint: @MainActor () throws -> SimulationControlCheckpoint?
    private let saveCheckpoint: @MainActor (SimulationControlCheckpoint) throws -> Void
    private var control = SimulationControlGate()
    private var checkpointAvailable = true
    private var checkpointLoaded = false
    private var connected = false
    private var controlSubscribed = false
    private var isForeground = true
    private var controlExpiryTimer: Timer?
    private var expiryGeneration = UUID()
    private var lifecycleObservers: [NSObjectProtocol] = []

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
    private var trialResourceTimer: Timer?

    /// Códigos estables del diagnóstico S10; applicationState usa los valores
    /// UIKit: active=0, inactive=1, background=2. startEntered y stopEntered
    /// registran el estado anterior a las mutaciones de ese método; los ACK
    /// y disconnected registran connected después de actualizarlo.
    private enum TrialLifecycleStage: Int {
        case startEntered = 1
        case startRunning = 2
        case socketStartRejected = 3
        case stopEntered = 4
        case connectionAckAccepted = 5
        case connectionAckRejected = 6
        case disconnected = 7
        case willResignActive = 8
        case didBecomeActive = 9
        case didEnterBackground = 10
        case willEnterForeground = 11
    }

    // MainActor serializa el contador; fuera de un ensayo no se asignan IDs.
    // La pareja processID/providerInstance identifica la instancia sin direcciones.
    private static var trialInstanceSequence = 0
    private let trialInstanceID: Int?

    private func logTrialLifecycle(_ stage: TrialLifecycleStage) {
        guard TrialProcessResources.isEnabled(), let trialInstanceID else { return }
        MQTTConfiguration.trialLog("providerLifecycle", [
            "processID": Int(ProcessInfo.processInfo.processIdentifier),
            "providerInstance": trialInstanceID,
            "stage": stage.rawValue,
            "running": isRunning ? 1 : 0,
            "connected": connected ? 1 : 0,
            "applicationState": UIApplication.shared.applicationState.rawValue
        ])
    }

    private func startTrialResourceSampling() {
        guard TrialProcessResources.isEnabled(), trialResourceTimer == nil else { return }
        let token = generation
        sampleTrialResources()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning, self.generation == token else { return }
                self.sampleTrialResources()
            }
        }
        trialResourceTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func sampleTrialResources() {
        guard let sample = TrialProcessResources.read() else {
            MQTTConfiguration.trialLog("processResourceFailure", ["code": 1])
            return
        }
        MQTTConfiguration.trialLog("processResources", sample.counts.merging(
            ["active": UIApplication.shared.applicationState == .active ? 1 : 0]
        ) { _, new in new })
    }

    private func stopTrialResourceSampling() {
        trialResourceTimer?.invalidate()
        trialResourceTimer = nil
    }

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
    private func refreshCurrentPositions(now: VehicleReceptionTime) {
        control.checkTime(now)
        let limite = VehiclePositionSanitizer.stalenessLimit

        positionsByID = positionsByID.filter {
            now.wall - $0.value.timestamp <= limite
                && ($0.value.dataOrigin == .observed || (checkpointAvailable &&
                    control.permits($0.value, at: now, legacy: legacyCompatibility)))
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

        refreshCurrentPositions(now: clock())

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
         legacyCompatibility: LegacyVehicleCompatibility = .disabled,
         clock: @escaping @MainActor () -> VehicleReceptionTime = { .now },
         loadCheckpoint: (@MainActor () throws -> SimulationControlCheckpoint?)? = nil,
         saveCheckpoint: (@MainActor (SimulationControlCheckpoint) throws -> Void)? = nil,
         conectar: @escaping @MainActor (CocoaMQTT) -> Bool = { $0.connect() }) {
        self.configuration = configuration
        self.legacyCompatibility = legacyCompatibility
        self.clock = clock
        let file = SimulationCheckpointFile(endpointIdentity:
            "v1|\(configuration.host.lowercased())|\(configuration.port)|\(configuration.useTLS)")
        self.loadCheckpoint = loadCheckpoint ?? { try file.read() }
        self.saveCheckpoint = saveCheckpoint ?? { try file.write($0) }
        self.conectar = conectar
        if TrialProcessResources.isEnabled() {
            Self.trialInstanceSequence += 1
            self.trialInstanceID = Self.trialInstanceSequence
        } else {
            self.trialInstanceID = nil
        }
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
        // Entrega serial y síncrona al MainActor: no crear Tasks que permitan
        // reordenar posición/control/desconexión al salir de la cola MQTT.
        mqtt.delegateQueue = .main
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
        logTrialLifecycle(.startEntered)

        if !checkpointLoaded {
            checkpointLoaded = true
            do {
                control = SimulationControlGate(checkpoint: try loadCheckpoint()?.validated())
            } catch {
                checkpointAvailable = false
                control.invalidate(blockLegacy: true)
                MQTTConfiguration.trialLog("checkpointFailure", ["code": (error as NSError).code])
            }
        }
        control.invalidate()
        connected = false
        controlSubscribed = false
        isForeground = UIApplication.shared.applicationState != .background

        prepareStreamIfNeeded()
        generation = UUID()
        let client = makeClient()
        mqtt = client
        configureCallbacks(for: client)
        isRunning = true
        logTrialLifecycle(.startRunning)
        startTrialResourceSampling()
        startStalenessSweep()
        observeLifecycle()

        if configuration.isReadOnly && !isForeground {
            retirePresentationSocket()
            return
        }

        #if DEBUG
        print("[MQTT] Intentando conectar con el broker...")
        #endif

        let aceptado = conectar(client)
        guard isRunning, mqtt === client else { return }
        if !aceptado {
            logTrialLifecycle(.socketStartRejected)
            // Un fallo al iniciar el socket no debe bloquear un start posterior.
            mqtt = nil
            if configuration.isReadOnly {
                client.autoReconnect = false
                client.disconnect()
                return // Conservar stream y observadores para el siguiente foreground.
            }
            isRunning = false
            generation = UUID()
            client.autoReconnect = false
            client.disconnect()
            stopStalenessSweep()
            stopTrialResourceSampling()
            stopControlExpiry()
            stopObservingLifecycle()
        }
    }

    func stop() {
        logTrialLifecycle(.stopEntered)
        isRunning = false
        generation = UUID()
        let previous = mqtt
        mqtt = nil
        previous?.autoReconnect = false
        previous?.disconnect()

        stopStalenessSweep()
        stopTrialResourceSampling()
        stopControlExpiry()
        stopObservingLifecycle()
        connected = false
        controlSubscribed = false
        control.invalidate()

        continuation?.yield([])
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

    func positionsForPresentation() -> [VehiclePosition] {
        guard isRunning else { return [] }
        publishIfChanged(now: clock())
        return currentPositions
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
        let token = generation
        mqtt.didConnectAck = { [weak self] client, acknowledgment in
            MainActor.assumeIsolated {
                guard let self, self.isCurrent(client, token: token) else { return }
                self.connected = acknowledgment == .accept
                MQTTConfiguration.trialLog("connection", ["accepted": self.connected ? 1 : 0])
                self.logTrialLifecycle(self.connected ? .connectionAckAccepted : .connectionAckRejected)
                self.controlSubscribed = false
                self.control.invalidate()
                self.stopControlExpiry()
                self.publishIfChanged(now: self.clock())
                guard self.connected else { return }
                client.subscribe(VehicleTrackingWire.controlTopic, qos: .qos1)
                client.subscribe(self.topic, qos: .qos1)
            }
        }
        mqtt.didSubscribeTopics = { [weak self] client, success, failed in
            MainActor.assumeIsolated {
                guard let self, self.isCurrent(client, token: token) else { return }
                let topic = VehicleTrackingWire.controlTopic
                if failed.contains(topic) || success[topic] != nil {
                    self.controlSubscribed = !failed.contains(topic)
                        && (success[topic] as? NSNumber)?.intValue == 1
                    MQTTConfiguration.trialLog("subscription", ["control": self.controlSubscribed ? 1 : 0])
                    if !self.controlSubscribed {
                        self.control.invalidate(blockLegacy: true)
                        self.stopControlExpiry()
                        self.publishIfChanged(now: self.clock())
                    }
                }
            }
        }
        mqtt.didReceiveMessage = { [weak self] client, message, _ in
            // CocoaMQTT entrega en delegateQueue=.main; procesar aquí conserva
            // el orden y evita una Task vieja que reaparezca tras disable/stop.
            MainActor.assumeIsolated {
                guard let self, self.isCurrent(client, token: token) else { return }
                guard message.payload.count <= VehicleTrackingWire.maximumBytes, message.qos == .qos1 else {
                    if message.topic == VehicleTrackingWire.controlTopic {
                        self.control.invalidate(blockLegacy: true)
                        self.stopControlExpiry()
                        self.publishIfChanged(now: self.clock())
                    }
                    return
                }
                let data = Data(message.payload)
                if message.topic == VehicleTrackingWire.controlTopic {
                    self.receiveControl(data, now: self.clock())
                } else if let position = VehicleTrackingWire.position(data: data, topic: message.topic,
                                                                      retained: message.retained) {
                    self.process(position: position, now: self.clock())
                }
            }
        }
        mqtt.didDisconnect = { [weak self] client, _ in
            MainActor.assumeIsolated {
                guard let self, self.isCurrent(client, token: token) else { return }
                MQTTConfiguration.trialLog("disconnection", ["accepted": 0])
                self.connected = false
                self.controlSubscribed = false
                self.logTrialLifecycle(.disconnected)
                self.control.invalidate()
                self.stopControlExpiry()
                self.publishIfChanged(now: self.clock())
            }
        }
    }

    private func isCurrent(_ client: CocoaMQTT, token: UUID) -> Bool {
        isRunning && generation == token && mqtt === client
    }

    private func receiveControl(_ data: Data, now: VehicleReceptionTime) {
        guard connected, controlSubscribed, checkpointAvailable else { return }
        guard let state = VehicleTrackingWire.control(data: data) else {
            control.invalidate(blockLegacy: true)
            stopControlExpiry()
            publishIfChanged(now: now)
            return
        }
        let previous = control.checkpoint
        control.receive(state, at: now)
        MQTTConfiguration.trialLog("control", ["enabled": state.enabled ? 1 : 0,
            "revision": Int(state.controlRevision)])
        do {
            if previous != control.checkpoint { try saveCheckpoint(control.checkpoint) }
        } catch {
            checkpointAvailable = false
            control.invalidate(blockLegacy: true)
        }
        if !isForeground { control.invalidate() }
        publishIfChanged(now: now)
        scheduleControlExpiry(now: now)
    }

    private func process(position: VehiclePosition, now: VehicleReceptionTime) {
        // Evaluar caducidad incluso si esta posición se descarta.
        publishIfChanged(now: now)
        guard let position = VehiclePositionSanitizer.sanitize(position, now: now.wall),
              position.dataOrigin == .observed || (checkpointAvailable &&
                control.permits(position, at: now, legacy: legacyCompatibility)) else { return }
        if position.dataOrigin == .simulated && (!isForeground || !connected || !controlSubscribed) { return }
        if let known = positionsByID[position.id], position.timestamp <= known.timestamp { return }
        positionsByID[position.id] = position
        publishIfChanged(now: now)
    }

    private func publishIfChanged(now: VehicleReceptionTime) {
        let previous = currentPositions
        refreshCurrentPositions(now: now)
        if currentPositions != previous {
            MQTTConfiguration.trialLog("reception", ["total": currentPositions.count,
                "synthetic": currentPositions.filter { $0.dataOrigin == .simulated }.count])
            continuation?.yield(currentPositions)
        }
    }

    private func stopControlExpiry() {
        expiryGeneration = UUID()
        controlExpiryTimer?.invalidate()
        controlExpiryTimer = nil
    }

    private func scheduleControlExpiry(now: VehicleReceptionTime) {
        stopControlExpiry()
        guard isForeground, checkpointAvailable, let remaining = control.remainingAuthorization(at: now) else { return }
        guard remaining > 0 else {
            control.invalidate()
            publishIfChanged(now: now)
            return
        }
        let token = generation
        let expiryToken = expiryGeneration
        let timer = Timer(timeInterval: remaining, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRunning, self.generation == token,
                      self.expiryGeneration == expiryToken else { return }
                self.controlExpiryTimer = nil
                let now = self.clock()
                self.publishIfChanged(now: now)
                // Si el timer despertó apenas antes del plazo, rearmarlo;
                // nunca renovar la fecha de una autorización recibida.
                if let remaining = self.control.remainingAuthorization(at: now), remaining > 0 {
                    self.scheduleControlExpiry(now: now)
                } else {
                    self.control.invalidate()
                }
            }
        }
        controlExpiryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func observeLifecycle() {
        guard lifecycleObservers.isEmpty else { return }
        let token = generation
        var names = [UIApplication.didEnterBackgroundNotification, UIApplication.willEnterForegroundNotification]
        if TrialProcessResources.isEnabled() || configuration.isReadOnly {
            names += [UIApplication.willResignActiveNotification, UIApplication.didBecomeActiveNotification]
        }
        if configuration.isReadOnly {
            names += [UIScene.didEnterBackgroundNotification, UIScene.willEnterForegroundNotification,
                      UIScene.didActivateNotification]
        }
        for name in names {
            lifecycleObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self, self.isRunning, self.generation == token else { return }
                    if self.configuration.isReadOnly {
                        switch notification.name {
                        case UIApplication.didEnterBackgroundNotification, UIScene.didEnterBackgroundNotification:
                            self.enterPresentationBackground()
                        case UIApplication.willEnterForegroundNotification, UIScene.willEnterForegroundNotification,
                             UIApplication.didBecomeActiveNotification, UIScene.didActivateNotification:
                            self.resumePresentationConnection()
                        default: break
                        }
                        return
                    }
                    switch notification.name {
                    case UIApplication.willResignActiveNotification:
                        self.logTrialLifecycle(.willResignActive)
                        return // Solo diagnóstico; no invalidar ni reconectar.
                    case UIApplication.didBecomeActiveNotification:
                        self.logTrialLifecycle(.didBecomeActive)
                        return // Solo diagnóstico; no invalidar ni reconectar.
                    case UIApplication.didEnterBackgroundNotification:
                        self.logTrialLifecycle(.didEnterBackground)
                    default:
                        self.logTrialLifecycle(.willEnterForeground)
                    }
                    self.isForeground = notification.name == UIApplication.willEnterForegroundNotification
                    self.control.invalidate() // esperar otro control recibido, no restaurar el guardado
                    self.stopControlExpiry()
                    self.publishIfChanged(now: self.clock())
                    if self.isForeground, self.connected, let client = self.mqtt {
                        // Pedir el retained de nuevo; la puerta de control sigue
                        // exigiendo vigencia, run y revisión antes de mostrar datos.
                        client.subscribe(VehicleTrackingWire.controlTopic, qos: .qos1)
                    }
                }
            })
        }
    }

    private func retirePresentationSocket() {
        let previous = mqtt
        // Invalidar la identidad antes de disconnect: callbacks pendientes del
        // socket retirado no pueden revocar ni repoblar la conexión siguiente.
        mqtt = nil
        connected = false
        controlSubscribed = false
        previous?.autoReconnect = false
        previous?.disconnect()
    }

    private func enterPresentationBackground() {
        guard isForeground || mqtt != nil else { return }
        isForeground = false
        control.invalidate()
        stopControlExpiry()
        stopStalenessSweep()
        retirePresentationSocket()
        publishIfChanged(now: clock())
    }

    private func resumePresentationConnection() {
        // UIKit y UIScene pueden emitir el mismo cambio. No abrir dos sockets
        // ni renovar la autorización en el segundo aviso.
        let needsConnection = !isForeground || mqtt == nil
        isForeground = true
        guard needsConnection else { return }
        control.invalidate()
        stopControlExpiry()
        retirePresentationSocket()
        publishIfChanged(now: clock())
        startStalenessSweep()
        let client = makeClient()
        mqtt = client
        configureCallbacks(for: client)
        if !conectar(client), mqtt === client {
            retirePresentationSocket()
        }
        // No terminar AsyncStream: Mapa conserva su consumidor al volver.
    }

    private func stopObservingLifecycle() {
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
        lifecycleObservers.removeAll()
    }
}
