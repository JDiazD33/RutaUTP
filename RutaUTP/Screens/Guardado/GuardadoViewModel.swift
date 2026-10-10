//
//  GuardadoViewModel.swift
//  RutaUTP
//
//  Estado y operaciones de la pestaña Guardado.
//
//  Antes todo esto vivía en `@State` dentro de `GuardadoView`: diez
//  propiedades más cinco métodos de persistencia mezclados con la maquetación,
//  así que no había forma de comprobar la regla de orden del campus, la
//  resolución de las líneas guardadas contra el feed ni la escritura en
//  `UserDefaults` sin levantar la interfaz entera.
//
//  Qué NO vive aquí: qué sheet está abierto y qué elemento está seleccionado.
//  Eso es estado de presentación y se queda en la vista — es justamente lo que
//  permite probar este ViewModel sin interfaz.
//

import Foundation
import Combine

@MainActor
final class GuardadoViewModel: ObservableObject {

    // MARK: - Estado

    /// Lugares guardados. El campus siempre va primero: lo garantiza
    /// `LugaresStore` al cargar y se respeta al insertar.
    @Published private(set) var lugares: [LugarGuardado] = []
    @Published private(set) var datosLugaresInvalidos = false

    private let almacen: AlmacenLugares
    private let repositorioGTFS: RutasGTFSProviding

    init(almacen: AlmacenLugares = LugaresStore.almacen,
         repositorioGTFS: RutasGTFSProviding = TransporteApp.repositorio) {
        self.almacen = almacen
        self.repositorioGTFS = repositorioGTFS
    }

    /// Catálogo completo del feed, necesario para resolver las líneas
    /// guardadas (que solo persistimos como `route_id`).
    @Published private(set) var lineasGTFS: [RutaOpcion] = []

    /// true cuando el feed ya se intentó cargar. Distingue "cargando" de
    /// "el feed no llegó", que antes se veían igual en el selector de líneas.
    @Published private(set) var catalogoCargado = false
    @Published private(set) var cargandoCatalogo = false
    @Published private(set) var errorCatalogo: FalloCargaGTFS?

    /// Referencias persistidas a líneas del feed (solo el `route_id`).
    @Published private(set) var lineaRefs: [LineaGuardadaRef] = []

    private static let lineasKey = "lineas.guardadas.v1"

    // MARK: - Derivados

    /// Líneas guardadas resueltas contra el catálogo, en el orden en que se
    /// guardaron. Una referencia cuyo `route_id` ya no exista en el feed se
    /// descarta en silencio en lugar de mostrar una fila vacía.
    var lineasGuardadas: [RutaOpcion] {
        let porId = Dictionary(lineasGTFS.map { ($0.id, $0) },
                               uniquingKeysWith: { primero, _ in primero })
        return lineaRefs.compactMap { porId[$0.routeId] }
    }

    /// Ids de las líneas ya guardadas, para marcarlas en el selector.
    var idsLineasGuardadas: Set<String> {
        Set(lineaRefs.map(\.routeId))
    }

    // MARK: - Carga

    /// Lugares y referencias de líneas desde el almacenamiento local.
    func cargar() {
        cargarLugares()
        if let data = almacen.defaults.data(forKey: Self.lineasKey),
           let refs = try? JSONDecoder().decode([LineaGuardadaRef].self, from: data) {
            lineaRefs = refs
        }
    }

    /// Catálogo del feed. Marca `catalogoCargado` incluso si llega vacío, para
    /// que la vista pueda distinguir "cargando" de "no hay datos".
    func cargarCatalogo(reintentar: Bool = false) async {
        guard !cargandoCatalogo, reintentar || !catalogoCargado else { return }
        cargandoCatalogo = true
        errorCatalogo = nil
        defer { cargandoCatalogo = false }
        do {
            let feed = try await repositorioGTFS.cargarRutas(reintentar: reintentar)
            guard !Task.isCancelled else { return }
            lineasGTFS = RutasViewModel.convertir(feed)
            catalogoCargado = true
        } catch {
            guard !Task.isCancelled else { return }
            errorCatalogo = (error as? FalloCargaGTFS) ?? FalloCargaGTFS(detalle: error.localizedDescription)
            catalogoCargado = true
        }
    }

    // MARK: - Lugares

    @discardableResult
    func añadirLugar(_ nuevo: LugarGuardado) -> Bool {
        // Leer la fuente actual evita sobrescribir lugares añadidos desde
        // otra pantalla mientras este ViewModel conservaba una lista vieja.
        var actuales = almacen.cargar()
        let primeroNoFijo = actuales.firstIndex { !$0.esFijo } ?? actuales.count
        actuales.insert(nuevo, at: min(primeroNoFijo + 1, actuales.count))
        let guardado = almacen.guardar(actuales)
        cargarLugares()
        return guardado
    }

    @discardableResult
    func eliminarLugar(_ lugar: LugarGuardado) -> Bool {
        let eliminado = almacen.eliminar(lugar)
        cargarLugares()
        return eliminado
    }

    func reintentarLecturaLugares() {
        almacen.invalidarCache()
        cargarLugares()
    }

    private func cargarLugares() {
        lugares = almacen.cargar()
        datosLugaresInvalidos = almacen.datosLocalesInvalidos
    }

    // MARK: - Líneas

    /// Idempotente: guardar dos veces la misma línea no duplica la fila.
    /// Antes el `append` se hacía sin comprobación y dependía de que el
    /// selector ocultara las ya guardadas.
    func añadirLinea(_ ruta: RutaOpcion) {
        guard !lineaRefs.contains(where: { $0.routeId == ruta.id }) else { return }
        lineaRefs.append(LineaGuardadaRef(routeId: ruta.id))
        persistirLineas()
    }

    func eliminarLinea(_ ruta: RutaOpcion) {
        lineaRefs.removeAll { $0.routeId == ruta.id }
        persistirLineas()
    }

    private func persistirLineas() {
        if let data = try? JSONEncoder().encode(lineaRefs) {
            almacen.defaults.set(data, forKey: Self.lineasKey)
        }
    }
}
