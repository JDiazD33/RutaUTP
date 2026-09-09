import Foundation

struct MQTTConfiguration {
    let host: String
    let port: UInt16
    let username: String
    let password: String

    /// Cifrado TLS (8883). Sin TLS las credenciales y las ubicaciones
    /// viajan en texto plano por la red, así que cualquier despliegue
    /// accesible desde internet debe activarlo.
    let useTLS: Bool

    init(
        host: String,
        port: UInt16,
        username: String,
        password: String,
        useTLS: Bool = false
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.useTLS = useTLS
    }

    /// Variables reconocidas en el Scheme de Xcode:
    ///   MQTT_HOST, MQTT_USERNAME, MQTT_PASSWORD (obligatorias)
    ///   MQTT_PORT (opcional, por defecto 1883)
    ///   MQTT_TLS (opcional, "1"/"true" habilita TLS)
    static func fromEnvironment() -> MQTTConfiguration? {
        let environment = ProcessInfo.processInfo.environment

        guard
            let host = environment["MQTT_HOST"],
            !host.isEmpty,
            let username = environment["MQTT_USERNAME"],
            !username.isEmpty,
            let password = environment["MQTT_PASSWORD"],
            !password.isEmpty
        else {
            return nil
        }

        let port = UInt16(environment["MQTT_PORT"] ?? "1883") ?? 1883

        let tlsFlags = ["1", "true", "yes"]

        let useTLS = tlsFlags.contains(
            (environment["MQTT_TLS"] ?? "").lowercased()
        )

        return MQTTConfiguration(
            host: host,
            port: port,
            username: username,
            password: password,
            useTLS: useTLS
        )
    }
}
