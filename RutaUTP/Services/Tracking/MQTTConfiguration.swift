import Foundation

struct MQTTConfiguration {
    let host: String
    let port: UInt16
    let username: String
    let password: String

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

        return MQTTConfiguration(
            host: host,
            port: port,
            username: username,
            password: password
        )
    }
}
