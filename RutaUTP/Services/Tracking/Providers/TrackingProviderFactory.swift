import Foundation

enum TrackingProviderFactory {

    static func makeDefault() -> VehicleTrackingProviding {
        guard let configuration =
                MQTTConfiguration.fromEnvironment() else {
            #if DEBUG
            print(
                "[TrackingProviderFactory] " +
                "Configuración MQTT ausente; usando simulación"
            )
            #endif

            return SimulatedTrackingProvider()
        }

        #if DEBUG
        print(
            "[TrackingProviderFactory] " +
            "Configuración MQTT encontrada; usando MQTT"
        )
        #endif

        return MQTTTrackingProvider(
            configuration: configuration
        )
    }
}
