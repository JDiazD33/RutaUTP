import Foundation
import Observation

/// Sede seleccionada para el mapa; UTP es el inicio sin una elección previa.
/// Conserva solo el ID estable; no lee disco en cada render ni abre el GPS.
final class SedeTrabajoStore: Observable {
    static let shared = SedeTrabajoStore()
    static let llave = "inicio.sede.trabajo.id.v1"
    static let llaveReferenciaUTP = "inicio.referencia.utp.v1"

    private let defaults: UserDefaults
    private let observacion = ObservationRegistrar()
    private let candado = NSLock()
    private var valor: SedeTrabajo?
    private var valorReferenciaUTP: Bool

    var sede: SedeTrabajo? {
        observacion.access(self, keyPath: \.sede)
        candado.lock()
        defer { candado.unlock() }
        return valor
    }

    var utpComoReferencia: Bool {
        observacion.access(self, keyPath: \.utpComoReferencia)
        candado.lock()
        defer { candado.unlock() }
        return valorReferenciaUTP
    }

    private init() {
        defaults = .standard
        let idGuardado = defaults.string(forKey: Self.llave)
        let sedeGuardada = idGuardado.flatMap(CatalogoSedesTrabajo.sede(id:))
        let referenciaGuardada = defaults.object(forKey: Self.llaveReferenciaUTP) == nil
            ? nil : defaults.bool(forKey: Self.llaveReferenciaUTP)
        // Mantener sedes y elecciones explícitas anteriores. Un regreso a UTP
        // de la versión previa se refleja también en la sede mostrada.
        let usarUTP = (referenciaGuardada ?? (idGuardado == nil)) || sedeGuardada?.empresa == .utp
        valor = usarUTP ? CatalogoSedesTrabajo.campusUTP : sedeGuardada
        valorReferenciaUTP = usarUTP
    }

    @MainActor
    func seleccionar(id: String?) {
        let nueva = id.flatMap(CatalogoSedesTrabajo.sede(id:))
        // Una entrada desconocida no sustituye la elección existente.
        guard id == nil || nueva != nil else { return }
        configurarReferenciaUTP(nueva?.empresa == .utp)
        guard sede?.id != nueva?.id else {
            // Canonizar la elección solo tras una acción del usuario, también
            // cuando UTP ya era el valor por defecto en memoria.
            guardarSede(nueva)
            return
        }
        observacion.withMutation(of: self, keyPath: \.sede) {
            candado.lock()
            valor = nueva
            candado.unlock()
            guardarSede(nueva)
        }
    }

    @MainActor
    func usarCampusUTP() {
        seleccionar(id: CatalogoSedesTrabajo.campusUTP.id)
    }

    private func guardarSede(_ sede: SedeTrabajo?) {
        if let sede {
            defaults.set(sede.id, forKey: Self.llave)
        } else {
            defaults.removeObject(forKey: Self.llave)
        }
    }

    @MainActor
    private func configurarReferenciaUTP(_ activa: Bool) {
        guard utpComoReferencia != activa else {
            defaults.set(activa, forKey: Self.llaveReferenciaUTP)
            return
        }
        observacion.withMutation(of: self, keyPath: \.utpComoReferencia) {
            candado.lock()
            valorReferenciaUTP = activa
            candado.unlock()
            defaults.set(activa, forKey: Self.llaveReferenciaUTP)
        }
    }
}
