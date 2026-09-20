//
//  RutaUTPApp.swift
//  RutaUTP
//
//  Punto de entrada de la aplicación.
//  - Modo oscuro/claro persistido con @AppStorage; se APLICA en RootView
//    (@AppStorage dentro del App no siempre invalida la escena).
//  - Idioma ES/EN vía IdiomaManager. NO se usa `.id(idioma.codigo)`: el gestor
//    es `@Observable`, así que cada vista que llama a `L.t()` en su body
//    registra la dependencia y se actualiza sola. Reconstruir el árbol tenía
//    un efecto secundario que se notaba: al recrear `RootView` se recreaba
//    también su `AppRouter`, y cambiar de idioma devolvía al usuario a
//    Bienvenida.
//

import SwiftUI

@main
struct RutaUTPApp: App {
    /// Servicio de ubicación COMPARTIDO por la app.
    ///
    /// Lo usan el mapa y el rastreo pasivo a la vez, y `LocationService` está
    /// escrito para eso: apaga `CLLocationManager` solo cuando se va el último
    /// consumidor. Con una instancia por pantalla habría dos gestores de
    /// ubicación en paralelo pidiendo la misma precisión.
    private let locationService: LocationService

    /// Coordinador del rastreo pasivo (la baliza del pasajero).
    ///
    /// Se crea aquí y no dentro del mapa para que sobreviva a la navegación:
    /// un viaje detectado no debe perderse porque el usuario cambie de
    /// pantalla. Solo publica si el usuario dio su consentimiento.
    @StateObject private var trackingCoordinator: PassiveTrackingCoordinator

    init() {
        // Versionado del esquema de datos locales. Va aquí, antes de que
        // exista ninguna vista, para que las migraciones se apliquen una sola
        // vez y de forma determinista, y ningún almacén lea datos a medio
        // migrar. Ver `Services/Persistencia/Persistencia.swift`.
        Persistencia.migrarSiHaceFalta()

        let compartido = LocationService()
        self.locationService = compartido
        _trackingCoordinator = StateObject(
            wrappedValue: PassiveTrackingCoordinator(locationService: compartido)
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView(locationService: locationService)
                .environmentObject(trackingCoordinator)
                // Si el usuario ya había dado su consentimiento, la baliza se
                // reanuda al arrancar. `startIfConsented` no hace nada cuando
                // el consentimiento está revocado o no existe.
                .task {
                    await trackingCoordinator.startIfConsented()
                }
                // El tema claro/oscuro se aplica en RootView (ver comentario
                // ahí): @AppStorage dentro del App no invalida la escena de
                // forma confiable y dejaba el tema "pegado" al volver a claro.
                .tint(.appPrimary)
                .background(Color.appBackground.ignoresSafeArea())
        }
    }
}
