import Foundation
import Observation

@MainActor @Observable
final class PreferenciasNotificacionesStore {
    static let llave = "notificaciones.config.v1"
    private let defaults: UserDefaults
    private(set) var configuracion = ConfiguracionNotificaciones()
    private(set) var activadas = true
    private(set) var datosInvalidos = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recargar()
    }

    func recargar() {
        activadas = PreferenciasApp.boolGuardado(para: PreferenciasApp.notificaciones, defaults: defaults) ?? true
        guard let original = defaults.object(forKey: Self.llave) else {
            configuracion = ConfiguracionNotificaciones()
            datosInvalidos = false
            return
        }
        guard let data = original as? Data,
              let config = try? JSONDecoder().decode(ConfiguracionNotificaciones.self, from: data), config.esValida else {
            // No sobrescribir datos corruptos o de una version futura.
            datosInvalidos = true
            return
        }
        configuracion = config
        datosInvalidos = false
    }

    func activar(_ valor: Bool) {
        activadas = valor
        defaults.set(valor, forKey: PreferenciasApp.notificaciones)
    }

    @discardableResult
    func guardar(_ config: ConfiguracionNotificaciones) -> Bool {
        recargar()
        guard !datosInvalidos, config.esValida,
              let data = try? JSONEncoder().encode(config) else { return false }
        defaults.set(data, forKey: Self.llave)
        configuracion = config
        return true
    }
}
