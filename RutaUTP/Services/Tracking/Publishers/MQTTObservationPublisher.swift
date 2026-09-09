//
//  MQTTObservationPublisher.swift
//  RutaUTP
//
//  Implementación MQTT del publicador de observaciones.
//
//  Responsabilidades:
//  - Mantener una conexión MQTT autenticada (opcionalmente cifrada TLS).
//  - Recibir ubicaciones ya autorizadas por el detector.
//  - Limitar la frecuencia de publicación.
//  - Serializar las observaciones como JSON.
//  - Publicarlas en un tópico asociado a una sesión anónima.
//
//  Este componente no decide si el usuario está dentro de un bus.
//  Esa responsabilidad pertenece a PassengerDetectionEngine.
//

import Foundation
import CoreLocation
import CocoaMQTT

/// Publica observaciones anónimas mediante MQTT.
///
/// Cada abordaje confirmado utiliza un `sessionID` diferente.
/// No se publican nombres, correos ni identificadores permanentes
/// del usuario o del dispositivo.
@MainActor
final class MQTTObservationPublisher:
    ObservationPublishing {

    /// Estado público de la conexión MQTT.
    private(set) var state:
        ObservationPublisherState = .inactive

    /// Observador de transiciones de estado.
    ///
    /// Se invoca exactamente una vez por cambio de estado, en el actor
    /// principal, para que la interfaz reaccione al instante sin sondear.
    var onStateChange:
        (@MainActor (ObservationPublisherState) -> Void)?

    /// Cliente MQTT proporcionado por CocoaMQTT.
    private let mqtt: CocoaMQTT

    /// Tiempo mínimo entre publicaciones consecutivas, en segundos.
    ///
    /// Cinco segundos permite observar el movimiento del vehículo
    /// sin transmitir cada lectura producida por el GPS.
    private let minimumPublishInterval:
        TimeInterval = 5

    /// Identificador temporal del viaje actual.
    private var sessionID: String?

    /// Línea GTFS asociada a la sesión actual.
    private var linea: String?

    /// Indica si existe una sesión activa de contribución.
    private var isActive = false

    /// Decide el ritmo de publicación (testeable sin red ni reloj real).
    private var throttle = ObservationPublishThrottle(
        minimumInterval: 5
    )

    /// Conserva temporalmente la muestra más reciente.
    ///
    /// Esto permite recibir una ubicación mientras MQTT todavía
    /// está conectándose y enviarla cuando la conexión sea aceptada.
    private var pendingObservation: PendingObservation?

    /// Reenvía la muestra pendiente aunque no lleguen lecturas nuevas.
    ///
    /// Mientras la sesión esté conectada, el GPS puede callarse unos
    /// segundos (túnel, techo del vehículo). Este temporizador publica
    /// la última muestra válida para que la baliza no desaparezca del
    /// mapa de los demás usuarios en esos huecos.
    private var flushTimer: Timer?

    /// Crea el publicador con una configuración externa.
    ///
    /// La dirección y las credenciales proceden de variables
    /// configuradas en el Scheme de Xcode, no del repositorio.
    init(configuration: MQTTConfiguration) {
        let clientID =
            "rutautp-observer-" + UUID().uuidString

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
        mqtt.enableSSL = configuration.useTLS

        configureCallbacks()
    }

    /// Inicia una sesión anónima y conecta con Mosquitto.
    ///
    /// Si el cliente ya está conectado, no crea una conexión duplicada.
    func start(
        sessionID: String,
        linea: String
    ) {
        self.sessionID = sessionID
        self.linea = linea
        self.isActive = true

        if state == .connected {
            publishPendingIfPossible(force: true)
            return
        }

        setState(.connecting)

        #if DEBUG
        print(
            "[MQTTObservationPublisher] " +
            "Conectando sesión \(sessionID)"
        )
        #endif

        _ = mqtt.connect()
    }

    /// Almacena y publica una ubicación aprobada por el detector.
    ///
    /// Una muestra con precisión negativa o superior a 50 metros
    /// se descarta para evitar transmitir datos poco fiables.
    func publish(
        location: CLLocation,
        routeID: String,
        activity: DetectedMotionActivity
    ) {
        guard isActive else {
            return
        }

        guard
            location.horizontalAccuracy.isFinite,
            location.horizontalAccuracy >= 0,
            location.horizontalAccuracy <= 50
        else {
            #if DEBUG
            print(
                "[MQTTObservationPublisher] " +
                "Muestra descartada por precisión: " +
                "\(location.horizontalAccuracy) m"
            )
            #endif

            return
        }

        // Coordenadas imposibles no deben salir nunca del teléfono,
        // ni siquiera proviniendo del hardware GPS.
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude

        guard
            latitude.isFinite,
            abs(latitude) <= 90,
            longitude.isFinite,
            abs(longitude) <= 180
        else {
            #if DEBUG
            print(
                "[MQTTObservationPublisher] " +
                "Muestra descartada por coordenada inválida"
            )
            #endif

            return
        }

        pendingObservation = PendingObservation(
            location: location,
            routeID: routeID,
            activity: activity
        )

        publishPendingIfPossible(force: false)
    }

    /// Detiene la contribución y elimina el estado de la sesión.
    func stop() {
        isActive = false
        sessionID = nil
        linea = nil
        pendingObservation = nil

        stopFlushTimer()
        throttle.reset()

        mqtt.disconnect()
        setState(.inactive)

        #if DEBUG
        print(
            "[MQTTObservationPublisher] " +
            "Sesión finalizada"
        )
        #endif
    }

    /// Configura las respuestas que CocoaMQTT ejecutará ante cambios
    /// de conexión, publicaciones y errores.
    private func configureCallbacks() {
        mqtt.didConnectAck = {
            [weak self] _, acknowledgment in

            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                guard acknowledgment == .accept else {
                    self.setState(
                        .failed(
                            "Conexión rechazada: \(acknowledgment)"
                        )
                    )

                    #if DEBUG
                    print(
                        "[MQTTObservationPublisher] " +
                        "Conexión rechazada: \(acknowledgment)"
                    )
                    #endif

                    return
                }

                self.setState(.connected)
                self.startFlushTimer()

                #if DEBUG
                print(
                    "[MQTTObservationPublisher] " +
                    "Conexión aceptada"
                )
                #endif

                // Envía la ubicación que pudo recibirse mientras
                // la conexión MQTT estaba en proceso.
                self.publishPendingIfPossible(
                    force: true
                )
            }
        }

        mqtt.didPublishMessage = {
            _, message, identifier in

            #if DEBUG
            print(
                "[MQTTObservationPublisher] " +
                "Mensaje \(identifier) enviado a " +
                message.topic
            )
            #endif
        }

        mqtt.didDisconnect = {
            [weak self] _, error in

            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                self.stopFlushTimer()

                // Una desconexión solicitada por stop() no debe
                // presentarse como un fallo.
                guard self.isActive else {
                    return
                }

                if let error {
                    self.setState(
                        .failed(error.localizedDescription)
                    )

                    #if DEBUG
                    print(
                        "[MQTTObservationPublisher] " +
                        "Desconectado con error: " +
                        error.localizedDescription
                    )
                    #endif
                } else {
                    // autoReconnect está activo: la sesión se
                    // está rearmando, no es un fallo definitivo.
                    self.setState(.connecting)
                }
            }
        }
    }

    /// Publica la muestra pendiente cuando la conexión y el intervalo
    /// mínimo permiten hacerlo.
    ///
    /// - Parameter force: Ignora el intervalo mínimo. Se utiliza al
    ///   terminar de establecer una conexión para no perder la primera
    ///   ubicación recibida.
    private func publishPendingIfPossible(
        force: Bool
    ) {
        guard
            isActive,
            state == .connected,
            let sessionID,
            let linea,
            let observation = pendingObservation
        else {
            return
        }

        let now = Date().timeIntervalSince1970

        guard throttle.canPublish(
            now: now,
            force: force
        ) else {
            return
        }

        let location = observation.location

        let payload = PassengerObservationPayload(
            schemaVersion: 1,
            sessionId: sessionID,
            routeId: observation.routeID,
            linea: linea,
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude,
            speed: sanitizedSpeed(location.speed),
            heading: sanitizedHeading(location.course),
            accuracy: location.horizontalAccuracy,
            motionActivity:
                observation.activity.rawValue,
            timestamp:
                location.timestamp.timeIntervalSince1970
        )

        do {
            let data = try JSONEncoder().encode(payload)

            guard let json = String(
                data: data,
                encoding: .utf8
            ) else {
                setState(
                    .failed(
                        "No se pudo convertir el JSON a texto"
                    )
                )
                return
            }

            let topic =
                "rutautp/observaciones/" +
                "\(sessionID)/posicion"

            mqtt.publish(
                topic,
                withString: json,
                qos: .qos1,
                retained: false
            )

            throttle.didPublish(at: now)
            pendingObservation = nil

            #if DEBUG
            print(
                "[MQTTObservationPublisher] " +
                "Observación publicada: \(json)"
            )
            #endif
        } catch {
            setState(
                .failed(error.localizedDescription)
            )

            #if DEBUG
            print(
                "[MQTTObservationPublisher] " +
                "Error de codificación: " +
                error.localizedDescription
            )
            #endif
        }
    }

    // MARK: - Sanitización numérica

    /// Velocidad válida para el contrato JSON.
    ///
    /// `-1` significa desconocida; valores absurdos (NaN, satélite
    /// defectuoso) no deben viajar por el canal público.
    private func sanitizedSpeed(
        _ value: Double
    ) -> Double {
        guard value.isFinite else {
            return -1
        }

        return min(max(value, -1), 100)
    }

    /// Rumbo válido para el contrato JSON.
    ///
    /// `-1` significa desconocido; se normaliza al rango [0, 360).
    private func sanitizedHeading(
        _ value: Double
    ) -> Double {
        guard value.isFinite, value >= 0 else {
            return -1
        }

        return value.truncatingRemainder(dividingBy: 360)
    }

    // MARK: - Estado y temporizador

    /// Actualiza el estado y notifica al observador.
    private func setState(
        _ newState: ObservationPublisherState
    ) {
        guard state != newState else {
            return
        }

        state = newState

        onStateChange?(newState)
    }

    /// Activa el reenvío periódico de la última muestra.
    private func startFlushTimer() {
        guard flushTimer == nil else {
            return
        }

        flushTimer = Timer.scheduledTimer(
            withTimeInterval: minimumPublishInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.publishPendingIfPossible(
                    force: false
                )
            }
        }
    }

    private func stopFlushTimer() {
        flushTimer?.invalidate()
        flushTimer = nil
    }
}

/// Información que permanece en memoria mientras espera publicación.
private struct PendingObservation {

    /// Lectura original del GPS.
    let location: CLLocation

    /// Ruta GTFS coincidente.
    let routeID: String

    /// Actividad detectada al capturar la ubicación.
    let activity: DetectedMotionActivity
}

/// Contrato JSON enviado al broker MQTT.
///
/// El modelo es interno para poder probar su codificación posteriormente.
/// No contiene información personal ni un identificador permanente.
struct PassengerObservationPayload: Codable, Equatable {

    /// Versión del formato del mensaje.
    let schemaVersion: Int

    /// Identificador anónimo válido solamente durante el viaje actual.
    let sessionId: String

    /// Identificador interno de la ruta GTFS candidata.
    let routeId: String

    /// Nombre público de la línea, por ejemplo `C-01`.
    let linea: String

    /// Latitud expresada en grados decimales.
    let lat: Double

    /// Longitud expresada en grados decimales.
    let lon: Double

    /// Velocidad GPS expresada en metros por segundo.
    let speed: Double

    /// Rumbo expresado en grados. `-1` indica que no está disponible.
    let heading: Double

    /// Precisión horizontal estimada, en metros.
    let accuracy: Double

    /// Actividad informada por Core Motion.
    let motionActivity: String

    /// Fecha de la lectura en formato UNIX, expresada en segundos.
    let timestamp: TimeInterval
}

/// Ritmo mínimo de publicación, aislado para poder probarlo con un
/// reloj controlado sin abrir conexiones ni esperar tiempo real.
struct ObservationPublishThrottle: Equatable {

    /// Segundos que deben pasar entre dos publicaciones.
    let minimumInterval: TimeInterval

    private(set) var lastPublishedAt: TimeInterval?

    init(minimumInterval: TimeInterval = 5) {
        self.minimumInterval = minimumInterval
    }

    /// Indica si es válido publicar en `now`.
    ///
    /// - Parameter force: Ignora el intervalo. Se usa al concretar la
    ///   conexión para no perder la primera ubicación ya recibida.
    func canPublish(
        now: TimeInterval,
        force: Bool
    ) -> Bool {
        guard !force, let lastPublishedAt else {
            return true
        }

        return now - lastPublishedAt >= minimumInterval
    }

    mutating func didPublish(at now: TimeInterval) {
        lastPublishedAt = now
    }

    mutating func reset() {
        lastPublishedAt = nil
    }
}
