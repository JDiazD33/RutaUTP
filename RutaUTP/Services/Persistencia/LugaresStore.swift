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

    private static let candado = NSLock()
    private static var cache: [LugarGuardado]?

    // MARK: - Lectura

    /// Lugares guardados, ya normalizados (el campus UTP siempre presente y
    /// primero). La primera llamada del proceso lee de disco; el resto, de la
    /// caché.
    static func cargar() -> [LugarGuardado] {
        candado.lock()
        defer { candado.unlock() }
        if let cache { return cache }
        let cargados = leerYNormalizar()
        cache = cargados
        return cargados
    }

    // MARK: - Escritura

    static func guardar(_ lugares: [LugarGuardado]) {
        candado.lock()
        cache = lugares
        candado.unlock()
        escribirEnDisco(lugares)
    }

    static func eliminar(_ lugar: LugarGuardado) {
        guardar(cargar().filter { $0.id != lugar.id })
    }

    /// Descarta la caché para que la próxima lectura vuelva a disco.
    ///
    /// Existe por las pruebas: escriben y limpian `UserDefaults` directamente,
    /// así que sin esto verían la lista que dejó la prueba anterior. En la app
    /// no hace falta, porque toda mutación pasa por `guardar` o `eliminar`.
    static func invalidarCache() {
        candado.lock()
        cache = nil
        candado.unlock()
    }

    // MARK: - Sembrado

    static func lugarUTP() -> LugarGuardado {
        LugarGuardado(nombre: "UTP",
                      direccion: "Av. Nicolás de Piérola 1221, Trujillo",
                      categoria: .universidad, esFrecuente: true,
                      lat: -8.098247879173792, lon: -79.03818104755645,
                      esFijo: true)
    }

    // MARK: - Privado

    /// Lee de disco y aplica el sembrado y la normalización. Se ejecuta una
    /// sola vez por proceso, así que las escrituras de normalización de abajo
    /// tampoco se repiten.
    ///
    /// OJO: no puede llamar a `guardar` —`cargar` ya tiene el candado tomado y
    /// `NSLock` no es recursivo—, por eso escribe con `escribirEnDisco`.
    private static func leerYNormalizar() -> [LugarGuardado] {
        var resultado: [LugarGuardado]

        if let data = UserDefaults.standard.data(forKey: key),
           let decodificados = try? JSONDecoder().decode([LugarGuardado].self, from: data),
           !decodificados.isEmpty {
            resultado = decodificados
        } else {
            // Seed: UTP (fijo) + Plaza de Armas; el resto los agrega el usuario.
            resultado = [lugarUTP(),
                         LugarGuardado(nombre: "Plaza de Armas",
                                       direccion: "Centro Histórico de Trujillo",
                                       categoria: .plaza,
                                       lat: -8.1096, lon: -79.0287)]
            escribirEnDisco(resultado)
            return resultado
        }

        // Migración: los lugares guardados antes de que `esFijo` se persistiera
        // no traen el campo, así que decodifican como false y el bloque de
        // abajo insertaría un SEGUNDO campus. Se reconoce por nombre UNA sola
        // vez y se marca; a partir de ahí manda el campo persistido.
        if !resultado.contains(where: { $0.esFijo }),
           let indice = resultado.firstIndex(where: {
               $0.nombre.caseInsensitiveCompare("UTP") == .orderedSame
           }) {
            resultado[indice].esFijo = true
            escribirEnDisco(resultado)
        }

        // El campus UTP es un lugar fijo de la app: siempre presente y primero.
        if let indiceUTP = resultado.firstIndex(where: { $0.esFijo }) {
            if indiceUTP != 0 {
                let utp = resultado.remove(at: indiceUTP)
                resultado.insert(utp, at: 0)
                escribirEnDisco(resultado)
            }
        } else {
            resultado.insert(lugarUTP(), at: 0)
            escribirEnDisco(resultado)
        }

        return resultado
    }

    private static func escribirEnDisco(_ lugares: [LugarGuardado]) {
        if let data = try? JSONEncoder().encode(lugares) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
