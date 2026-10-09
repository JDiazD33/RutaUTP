//
//  Persistencia.swift
//  RutaUTP
//
//  Versionado del esquema de datos locales.
//
//  Antes, cada almacén llevaba su control de versión a mano dentro del nombre
//  de su llave ("lugares.guardados.v2", "lineas.guardadas.v1",
//  "seguridad.tiles.v1") y las migraciones vivían sueltas dentro del código
//  que cargaba los datos. Funcionaba, pero no había ningún sitio donde ver
//  QUÉ versión de esquema tiene instalada el dispositivo, ni en qué orden se
//  aplicaron los cambios, ni dónde escribir la siguiente migración.
//
//  Este módulo centraliza una versión de esquema única y explícita y una lista
//  ordenada de migraciones idempotentes. El inventario de llaves se documenta
//  en PERSISTENCIA.md, en la raíz del repositorio.
//
//  Reglas:
//   - Una migración NUNCA borra datos del usuario. Si algo no se puede
//     migrar, se deja como está y la app degrada a su valor por defecto.
//   - Las llaves existentes NO se renombran: renombrar "lugares.guardados.v2"
//     perdería los lugares ya guardados. El versionado se añade por encima,
//     no reescribiendo lo que ya hay.
//

import Foundation

enum Persistencia {

    // MARK: - Versión

    /// Versión del esquema de datos locales que entiende este binario.
    ///
    /// Historial:
    ///   1 — estado inicial versionado a posteriori. Los almacenes que ya
    ///       existían conservan sus llaves; esta versión los declara a todos
    ///       bajo un mismo esquema y aplica la migración de campo de los
    ///       lugares guardados al arrancar, en vez de en la primera visita.
    static let versionEsquema = 1

    /// Llave donde se guarda la versión instalada. Va SIN número en el nombre
    /// a propósito: es la que permite versionar a todas las demás.
    private static let llaveVersion = "persistencia.esquema.version"

    // MARK: - Migración

    /// Aplica las migraciones pendientes y sella la versión actual.
    ///
    /// Idempotente: la segunda llamada no hace nada. Se invoca una sola vez,
    /// al arrancar la app, antes de que ninguna vista lea datos persistidos.
    @discardableResult
    static func migrarSiHaceFalta(almacen: AlmacenLugares = LugaresStore.almacen) -> Int {
        let defaults = almacen.defaults
        let instalada = defaults.integer(forKey: llaveVersion)
        guard instalada < versionEsquema else { return instalada }

        var actual = instalada
        for migracion in migraciones where migracion.version > instalada {
            // No sellar un paso fallido: una versión compatible o una lectura
            // posterior deben poder reintentar sin perder los datos originales.
            guard migracion.aplicar(almacen) else { return actual }
            #if DEBUG
            print("[Persistencia] esquema v\(actual) → v\(migracion.version): \(migracion.descripcion)")
            #endif
            actual = migracion.version
            defaults.set(actual, forKey: llaveVersion)
        }

        return actual
    }

    /// Migraciones ordenadas por versión destino. Cada `aplicar` debe ser
    /// idempotente y tolerante a datos ausentes.
    private static let migraciones: [(version: Int, descripcion: String, aplicar: (AlmacenLugares) -> Bool)] = [
        (
            1,
            "declara el esquema versionado y aplica al arranque la migración de campo de los lugares guardados",
            { almacen in
                // La migración real de este paso vive en `LugaresStore.cargar()`
                // (el campo `esFijo`, que en datos anteriores no existía y se
                // deducía del nombre). Se fuerza una carga aquí para que se
                // aplique una sola vez, de forma determinista, en lugar de
                // esperar a que el usuario abra Guardado o el Mapa. La carga es
                // idempotente: si ya estaba migrado, no reescribe nada.
                _ = almacen.cargar()
                return !almacen.datosLocalesInvalidos
            }
        )
    ]

}

/// Claves compartidas por Perfil y el menú. Conservan los valores ya guardados.
enum PreferenciasApp {
    static let notificaciones = "perfil_notificaciones"
    static let compartirUbicacion = "perfil_compartirUbicacion"
}
