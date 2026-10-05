//
//  LugaresStore.swift
//  RutaUTP
//
//  Almacén de los lugares guardados (UserDefaults).
//
//  Estaba dentro de `Models/LugarGuardado.swift`, que mezclaba el MODELO con
//  su almacén. Se separa para que el archivo del modelo contenga el modelo.
//
//  La lista se cachea en MEMORIA. Antes, cada `cargar()` decodificaba el JSON
//  de `UserDefaults` en el hilo principal, y había sitios que la llamaban dos
//  y tres veces seguidas: marcar un paradero como guardado en Seguridad hacía
//  tres lecturas completas por toque. Ahora se decodifica una sola vez por
//  proceso y las escrituras mantienen la caché al día.
//

import Foundation

/// Fuente única de lugares guardados. La usan Guardado, Seguridad, Mapa y
/// Paraderos iluminados para leer y escribir los mismos datos.
enum LugaresStore {

    static let key = "lugares.guardados.v2"
    static let respaldoKey = "lugares.guardados.v2.respaldo"

    /// La app comparte una instancia; las pruebas usan un dominio aislado.
    static let almacen = AlmacenLugares(defaults: .standard)

    static var datosLocalesInvalidos: Bool { almacen.datosLocalesInvalidos }

    // MARK: - Lectura

    /// Lugares guardados, ya normalizados (el campus UTP siempre presente y
    /// primero). La primera llamada del proceso lee de disco; el resto, de la
    /// caché.
    static func cargar() -> [LugarGuardado] {
        almacen.cargar()
    }

    // MARK: - Escritura

    @discardableResult
    static func guardar(_ lugares: [LugarGuardado]) -> Bool {
        almacen.guardar(lugares)
    }

    @discardableResult
    static func eliminar(_ lugar: LugarGuardado) -> Bool {
        almacen.eliminar(lugar)
    }

    /// Descarta la caché para que la próxima lectura vuelva a disco.
    ///
    /// Existe por las pruebas: escriben y limpian `UserDefaults` directamente,
    /// así que sin esto verían la lista que dejó la prueba anterior. En la app
    /// no hace falta, porque toda mutación pasa por `guardar` o `eliminar`.
    static func invalidarCache() {
        almacen.invalidarCache()
    }

    // MARK: - Sembrado

    static func lugarUTP() -> LugarGuardado {
        LugarGuardado(nombre: "UTP",
                      direccion: "Av. Nicolás de Piérola 1221, Trujillo",
                      categoria: .universidad, esFrecuente: true,
                      lat: -8.098247879173792, lon: -79.03818104755645,
                      esFijo: true)
    }

}

/// Conserva los originales cuando no puede interpretarlos. Una carga fallida
/// bloquea también las escrituras posteriores; devolver solo una lista vacía
/// permitiría que una pantalla la guardara encima de los datos del usuario.
final class AlmacenLugares {
    let defaults: UserDefaults

    private struct Carga {
        let lugares: [LugarGuardado]
        let datosInvalidos: Bool
    }

    private let candado = NSLock()
    private var cache: Carga?

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var datosLocalesInvalidos: Bool {
        candado.lock()
        defer { candado.unlock() }
        return cargarBajoCandado().datosInvalidos
    }

    func cargar() -> [LugarGuardado] {
        candado.lock()
        defer { candado.unlock() }
        return cargarBajoCandado().lugares
    }

    @discardableResult
    func guardar(_ lugares: [LugarGuardado]) -> Bool {
        candado.lock()
        defer { candado.unlock() }
        guard !cargarBajoCandado().datosInvalidos else { return false }
        return escribirBajoCandado(lugares)
    }

    @discardableResult
    func eliminar(_ lugar: LugarGuardado) -> Bool {
        candado.lock()
        defer { candado.unlock() }
        let carga = cargarBajoCandado()
        guard !carga.datosInvalidos else { return false }
        return escribirBajoCandado(carga.lugares.filter { $0.id != lugar.id })
    }

    func invalidarCache() {
        candado.lock()
        defer { candado.unlock() }
        cache = nil
    }

    private func cargarBajoCandado() -> Carga {
        if let cache { return cache }
        let carga = leerYNormalizar()
        cache = carga
        return carga
    }

    /// Lee de disco y aplica el sembrado y la normalización. Se ejecuta una
    /// sola vez por proceso, así que las escrituras de normalización de abajo
    /// tampoco se repiten.
    ///
    /// Se llama con el candado tomado: no debe invocar métodos públicos.
    private func leerYNormalizar() -> Carga {
        guard let objeto = defaults.object(forKey: LugaresStore.key) else {
            // Seed: UTP (fijo) + Plaza de Armas; el resto los agrega el usuario.
            let semillas = [LugaresStore.lugarUTP(),
                         LugarGuardado(nombre: "Plaza de Armas",
                                       direccion: "Centro Histórico de Trujillo",
                                       categoria: .plaza,
                                       lat: -8.1096, lon: -79.0287)]
            _ = escribirBajoCandado(semillas)
            return Carga(lugares: semillas, datosInvalidos: false)
        }

        // Un tipo distinto de Data también es un dato existente, nunca una
        // primera instalación. No escribir semillas ni borrar el original.
        guard let data = objeto as? Data,
              let decodificados = try? JSONDecoder().decode([LugarGuardado].self, from: data) else {
            return Carga(lugares: [], datosInvalidos: true)
        }
        var resultado = decodificados

        // Migración: los lugares guardados antes de que `esFijo` se persistiera
        // no traen el campo, así que decodifican como false y el bloque de
        // abajo insertaría un SEGUNDO campus. Se reconoce por nombre UNA sola
        // vez y se marca; a partir de ahí manda el campo persistido.
        if !resultado.contains(where: { $0.esFijo }),
           let indice = resultado.firstIndex(where: {
               $0.nombre.caseInsensitiveCompare("UTP") == .orderedSame
            }) {
            resultado[indice].esFijo = true
        }

        // El campus UTP es un lugar fijo de la app: siempre presente y primero.
        if let indiceUTP = resultado.firstIndex(where: { $0.esFijo }) {
            if indiceUTP != 0 {
                let utp = resultado.remove(at: indiceUTP)
                resultado.insert(utp, at: 0)
            }
        } else {
            resultado.insert(LugaresStore.lugarUTP(), at: 0)
        }

        if resultado != decodificados {
            guard let normalizados = try? JSONEncoder().encode(resultado) else {
                return Carga(lugares: decodificados, datosInvalidos: true)
            }
            // Una sola copia del original, antes de la normalización. No se
            // acumulan versiones ni se reemplaza el respaldo al releer datos
            // ya migrados. Los UUID y las referencias permanecen intactos.
            defaults.set(data, forKey: LugaresStore.respaldoKey)
            defaults.set(normalizados, forKey: LugaresStore.key)
        }
        return Carga(lugares: resultado, datosInvalidos: false)
    }

    private func escribirBajoCandado(_ lugares: [LugarGuardado]) -> Bool {
        guard let data = try? JSONEncoder().encode(lugares) else { return false }
        defaults.set(data, forKey: LugaresStore.key)
        cache = Carga(lugares: lugares, datosInvalidos: false)
        return true
    }
}
