import Foundation

@MainActor
enum TrackingProviderFactory {

    static func makeDefault() -> VehicleTrackingProviding {
        // Sin recorridos institucionales no se conecta el canal de la flota urbana.
        if TransporteApp.rutasUTPPendientes { return SimulatedTrackingProvider() }
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
            configuration: configuration,
            // Transición del backend v1 actual, con productores apagados.
            // Al recibir enable se purga el legado y se exige v2.
            legacyCompatibility: .whileSimulationDisabled
        )
    }
}
