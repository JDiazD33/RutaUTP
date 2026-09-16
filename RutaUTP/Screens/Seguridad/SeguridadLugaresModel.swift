//
//  SeguridadLugaresModel.swift
//  RutaUTP
//
//  Estado y operaciones de los tiles de lugares guardados en Seguridad.
//
//  Estaba dentro de `SeguridadView`: cuatro propiedades de estado y cinco
//  métodos mezclados con la maquetación, así que la regla de orden de los
//  tiles —UTP fijo siempre primero, luego el orden que eligió el usuario— no
//  se podía comprobar sin levantar la pantalla entera.
//
//  Qué NO vive aquí: qué sheet está abierto y qué lugar está seleccionado.
//  Eso es estado de presentación y se queda en la vista; es justo lo que
//  permite probar este modelo sin interfaz.
//

import Foundation
import Combine

@MainActor
final class SeguridadLugaresModel: ObservableObject {

    // MARK: - Estado

    /// Lugares guardados tal como están en `LugaresStore`.
    @Published private(set) var lugares: [LugarGuardado] = []

    /// Tiles visibles: el fijo (UTP) primero y después los elegidos.
    ///
    /// Es asignable y no `private(set)` porque el delegado de arrastre lo
    /// reordena a través de un `Binding` (`$lugaresVM.tilesActuales`).
    @Published var tilesActuales: [LugarGuardado] = []

    /// Modo edición (estilo Springboard): jiggle, borrar y reordenar.
    @Published var modoEdicion = false

    /// Tile que se está arrastrando ahora mismo.
    @Published var arrastrando: LugarGuardado?

    private static let tilesKey = "seguridad.tiles.v1"
    private static let ordenKey = "seguridad.tiles.orden.v1"

    // MARK: - Carga

    /// Relee los lugares y recompone los tiles. Idempotente.
    func cargar() {
        lugares = LugaresStore.cargar()
        reconstruirTiles()
    }

    func alternarEdicion() {
        modoEdicion.toggle()
    }

    // MARK: - Lugares

    /// Quita un lugar de guardados, lo saca de los tiles y persiste el orden.
    func eliminar(_ lugar: LugarGuardado) {
        LugaresStore.eliminar(lugar)
        lugares = LugaresStore.cargar()
        tilesActuales.removeAll { $0.id == lugar.id }
        persistirOrden()
    }

    // MARK: - Tiles

    /// UTP fijo primero + extras en el orden guardado por el usuario.
    func reconstruirTiles(seleccion: Set<UUID>? = nil) {
        let utp = lugares.first(where: { $0.esFijo })
        let noFijos = lugares.filter { !$0.esFijo }

        let elegidos: [LugarGuardado]
        if let seleccion {
            guardarTilesSeleccion(seleccion)
            elegidos = noFijos.filter { seleccion.contains($0.id) }
        } else if let idsGuardados = idsTilesGuardados() {
            let porId = Dictionary(uniqueKeysWithValues: noFijos.map { ($0.id, $0) })
            elegidos = idsGuardados.compactMap { porId[$0] }
        } else {
            elegidos = Array(noFijos.prefix(2))
        }

        // Orden guardado por el usuario (arrastrar en modo edición)
        var resultado: [LugarGuardado] = []
        if let utp { resultado.append(utp) }
        if let orden = idsOrdenGuardados(), !orden.isEmpty {
            let porId = Dictionary(uniqueKeysWithValues: elegidos.map { ($0.id, $0) })
            var ordenados = orden.compactMap { porId[$0] }
            // Los que no tenían posición guardada van al final, en su orden natural.
            ordenados += elegidos.filter { s in !ordenados.contains(where: { $0.id == s.id }) }
            resultado += ordenados
        } else {
            resultado += elegidos
        }
        tilesActuales = resultado
    }

    private func idsTilesGuardados() -> [UUID]? {
        guard let data = UserDefaults.standard.data(forKey: Self.tilesKey),
              let ids = try? JSONDecoder().decode([UUID].self, from: data) else { return nil }
        return ids
    }

    private func idsOrdenGuardados() -> [UUID]? {
        guard let data = UserDefaults.standard.data(forKey: Self.ordenKey),
              let ids = try? JSONDecoder().decode([UUID].self, from: data) else { return nil }
        return ids
    }

    func persistirOrden() {
        let ids = tilesActuales.filter { !$0.esFijo }.map(\.id)
        if let data = try? JSONEncoder().encode(ids) {
            UserDefaults.standard.set(data, forKey: Self.ordenKey)
        }
    }

    private func guardarTilesSeleccion(_ ids: Set<UUID>) {
        // Se guarda en el ORDEN de `lugares`, no en el del `Set`.
        //
        // Un `Set` no tiene orden estable, así que persistir `Array(ids)` tal
        // cual hacía que los tiles salieran BARAJADOS al reabrir la app: la
        // selección se recordaba bien, pero en un orden distinto cada vez. Lo
        // destapó una prueba de la regla de orden (M-04), no un usuario.
        let ordenados = lugares.filter { ids.contains($0.id) }.map(\.id)
        if let data = try? JSONEncoder().encode(ordenados) {
            UserDefaults.standard.set(data, forKey: Self.tilesKey)
        }
    }
}
