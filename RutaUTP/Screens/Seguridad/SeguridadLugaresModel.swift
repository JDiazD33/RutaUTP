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
    @Published private(set) var datosLugaresInvalidos = false
    @Published private(set) var datosTilesInvalidos = false

    private let almacen: AlmacenLugares

    init(almacen: AlmacenLugares = LugaresStore.almacen) {
        self.almacen = almacen
    }

    /// Tiles visibles: el fijo (UTP) primero y después los elegidos.
    ///
    /// La vista conserva acceso al orden; el movimiento se centraliza en `mover`.
    @Published var tilesActuales: [LugarGuardado] = []

    /// Modo edición (estilo Springboard): jiggle, borrar y reordenar.
    @Published var modoEdicion = false

    /// Tile que se está arrastrando ahora mismo.
    @Published var arrastrando: LugarGuardado?

    private static let tilesKey = "seguridad.tiles.v1"
    private static let ordenKey = "seguridad.tiles.orden.v1"
    private enum ErrorConfiguracion: Error { case datosInvalidos }

    // MARK: - Carga

    /// Relee los lugares y recompone los tiles. Idempotente.
    func cargar() {
        lugares = almacen.cargar()
        datosLugaresInvalidos = almacen.datosLocalesInvalidos
        reconstruirTiles()
    }

    func alternarEdicion() {
        guard !almacen.datosLocalesInvalidos, leerConfiguracion() != nil else { return }
        arrastrando = nil
        modoEdicion.toggle()
    }

    // MARK: - Lugares

    /// Quita un lugar de guardados, lo saca de los tiles y persiste el orden.
    @discardableResult
    func eliminar(_ lugar: LugarGuardado) -> Bool {
        guard leerConfiguracion() != nil else { return false }
        guard almacen.eliminar(lugar) else {
            cargar()
            return false
        }
        lugares = almacen.cargar()
        tilesActuales.removeAll { $0.id == lugar.id }
        persistirOrden()
        return true
    }

    // MARK: - Tiles

    /// Movimiento local: después del destino al avanzar y antes al retroceder.
    @discardableResult
    func mover(_ origen: UUID, sobre destino: UUID) -> Bool {
        guard modoEdicion, !almacen.datosLocalesInvalidos, origen != destino,
              let desde = tilesActuales.firstIndex(where: { $0.id == origen }),
              let hasta = tilesActuales.firstIndex(where: { $0.id == destino }),
              !tilesActuales[desde].esFijo, !tilesActuales[hasta].esFijo else { return false }
        var nuevoOrden = tilesActuales
        let tile = nuevoOrden.remove(at: desde)
        guard let nuevoDestino = nuevoOrden.firstIndex(where: { $0.id == destino }) else { return false }
        nuevoOrden.insert(tile, at: desde < hasta ? nuevoDestino + 1 : nuevoDestino)
        guard guardarOrden(nuevoOrden) else { return false }
        tilesActuales = nuevoOrden
        return true
    }

    /// UTP fijo primero + extras en el orden guardado por el usuario.
    @discardableResult
    func reconstruirTiles(seleccion: Set<UUID>? = nil) -> Bool {
        datosLugaresInvalidos = almacen.datosLocalesInvalidos
        guard !datosLugaresInvalidos else {
            tilesActuales = []
            modoEdicion = false
            arrastrando = nil
            return false
        }
        guard let configuracion = leerConfiguracion() else {
            tilesActuales = []
            return false
        }
        let utp = lugares.first(where: { $0.esFijo })
        let noFijos = lugares.filter { !$0.esFijo }

        let elegidos: [LugarGuardado]
        if let seleccion {
            guard guardarTilesSeleccion(seleccion) else { return false }
            elegidos = noFijos.filter { seleccion.contains($0.id) }
        } else if let idsGuardados = configuracion.seleccion {
            let porId = Dictionary(uniqueKeysWithValues: noFijos.map { ($0.id, $0) })
            elegidos = idsGuardados.compactMap { porId[$0] }
        } else {
            elegidos = Array(noFijos.prefix(2))
        }

        // Orden guardado por el usuario (arrastrar en modo edición)
        var resultado: [LugarGuardado] = []
        if let utp { resultado.append(utp) }
        if let orden = configuracion.orden, !orden.isEmpty {
            let porId = Dictionary(uniqueKeysWithValues: elegidos.map { ($0.id, $0) })
            var ordenados = orden.compactMap { porId[$0] }
            // Los que no tenían posición guardada van al final, en su orden natural.
            ordenados += elegidos.filter { s in !ordenados.contains(where: { $0.id == s.id }) }
            resultado += ordenados
        } else {
            resultado += elegidos
        }
        tilesActuales = resultado
        return true
    }

    private func idsGuardados(para clave: String) throws -> [UUID]? {
        guard let original = almacen.defaults.object(forKey: clave) else { return nil }
        guard let data = original as? Data,
              let ids = try? JSONDecoder().decode([UUID].self, from: data),
              Set(ids).count == ids.count else { throw ErrorConfiguracion.datosInvalidos }
        return ids
    }

    /// La ausencia usa los valores iniciales; un original ilegible bloquea
    /// todas las escrituras de selección/orden, también desde una vista abierta.
    private func leerConfiguracion() -> (seleccion: [UUID]?, orden: [UUID]?)? {
        do {
            let seleccion = try idsGuardados(para: Self.tilesKey)
            let orden = try idsGuardados(para: Self.ordenKey)
            datosTilesInvalidos = false
            return (seleccion, orden)
        } catch {
            datosTilesInvalidos = true
            modoEdicion = false
            arrastrando = nil
            return nil
        }
    }

    /// Restablece la selección inicial y su orden, sin modificar los lugares.
    func respaldarYReiniciarTiles(crearRespaldo: ((Data) throws -> URL)? = nil) throws -> URL? {
        guard leerConfiguracion() == nil else { return nil }
        let archivo = try RecuperacionPreferencias.reiniciar(
            claves: [Self.tilesKey, Self.ordenKey], valoresNuevos: [:], nombre: "accesos",
            defaults: almacen.defaults, crearRespaldo: crearRespaldo)
        modoEdicion = false
        arrastrando = nil
        cargar()
        return archivo
    }

    @discardableResult
    func persistirOrden() -> Bool { guardarOrden(tilesActuales) }

    private func guardarOrden(_ tiles: [LugarGuardado]) -> Bool {
        guard !almacen.datosLocalesInvalidos, leerConfiguracion() != nil else { return false }
        let ids = tiles.filter { !$0.esFijo }.map(\.id)
        guard let data = try? JSONEncoder().encode(ids) else { return false }
        almacen.defaults.set(data, forKey: Self.ordenKey)
        return true
    }

    private func guardarTilesSeleccion(_ ids: Set<UUID>) -> Bool {
        guard !almacen.datosLocalesInvalidos, leerConfiguracion() != nil else { return false }
        // Se guarda en el ORDEN de `lugares`, no en el del `Set`.
        //
        // Un `Set` no tiene orden estable, así que persistir `Array(ids)` tal
        // cual hacía que los tiles salieran BARAJADOS al reabrir la app: la
        // selección se recordaba bien, pero en un orden distinto cada vez. Lo
        // destapó una prueba de la regla de orden (M-04), no un usuario.
        let ordenados = lugares.filter { ids.contains($0.id) }.map(\.id)
        guard let data = try? JSONEncoder().encode(ordenados) else { return false }
        almacen.defaults.set(data, forKey: Self.tilesKey)
        return true
    }
}
