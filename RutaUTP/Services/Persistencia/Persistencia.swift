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
//  Este módulo centraliza las tres cosas: una versión de esquema única y
//  explícita, una lista ordenada de migraciones idempotentes y el inventario
//  de llaves que la app considera suyas.
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

    /// Versión instalada en este dispositivo. 0 = instalación nueva o
    /// anterior a que existiera el versionado.
    static var versionInstalada: Int {
        UserDefaults.standard.integer(forKey: llaveVersion)
    }

    // MARK: - Migración

    /// Aplica las migraciones pendientes y sella la versión actual.
    ///
    /// Idempotente: la segunda llamada no hace nada. Se invoca una sola vez,
    /// al arrancar la app, antes de que ninguna vista lea datos persistidos.
    @discardableResult
    static func migrarSiHaceFalta() -> Int {
        let instalada = versionInstalada
        guard instalada < versionEsquema else { return instalada }

        for migracion in migraciones where migracion.version > instalada {
            migracion.aplicar()
            #if DEBUG
            print("[Persistencia] esquema v\(instalada) → v\(migracion.version): \(migracion.descripcion)")
            #endif
        }

        UserDefaults.standard.set(versionEsquema, forKey: llaveVersion)
        return versionEsquema
    }

    /// Migraciones ordenadas por versión destino. Cada `aplicar` debe ser
    /// idempotente y tolerante a datos ausentes.
    private static let migraciones: [(version: Int, descripcion: String, aplicar: () -> Void)] = [
        (
            1,
            "declara el esquema versionado y aplica al arranque la migración de campo de los lugares guardados",
            {
                // La migración real de este paso vive en `LugaresStore.cargar()`
                // (el campo `esFijo`, que en datos anteriores no existía y se
                // deducía del nombre). Se fuerza una carga aquí para que se
                // aplique una sola vez, de forma determinista, en lugar de
                // esperar a que el usuario abra Guardado o el Mapa. La carga es
                // idempotente: si ya estaba migrado, no reescribe nada.
                _ = LugaresStore.cargar()
            }
        )
    ]

    // MARK: - Inventario

    /// Llaves de `UserDefaults` que la app considera suyas.
    ///
    /// Documentadas aquí para que una migración futura sepa qué tocar sin
    /// recorrer el proyecto entero. Es un inventario de lectura: no se usa
    /// para borrar ni para recorrer nada en ejecución.
    static let llavesConocidas: [String] = [
        llaveVersion,
        LugaresStore.key,
        "lineas.guardadas.v1",
        "negocios.cupones.guardados",
        "seguridad.tiles.v1",
        "seguridad.tiles.orden.v1",
        "idioma.app",
        "isDarkMode",
        "ciudadSeleccionada",
        "senias.modo.activado",
        PreferenciasApp.notificaciones,
        PreferenciasApp.compartirUbicacion,
        "perfil_telefono",
        "perfil_correoPersonal",
        "emergencia_nombre",
        "emergencia_parentesco",
        "emergencia_numero",
        "monedero.saldo.v1",
        "monedero.movimientos.v1",
        "tracking.radioParadero",
        "tracking.velocidadDemo"
    ]
}

/// Claves compartidas por Perfil y el menú. Conservan los valores ya guardados.
enum PreferenciasApp {
    static let notificaciones = "perfil_notificaciones"
    static let compartirUbicacion = "perfil_compartirUbicacion"
}
