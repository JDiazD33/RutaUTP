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

    /// Catálogo completo del feed, necesario para resolver las líneas
    /// guardadas (que solo persistimos como `route_id`).
    @Published private(set) var lineasGTFS: [RutaOpcion] = []

    /// true cuando el feed ya se intentó cargar. Distingue "cargando" de
    /// "el feed no llegó", que antes se veían igual en el selector de líneas.
    @Published private(set) var catalogoCargado = false

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

    /// Índice donde insertar un lugar nuevo: justo después del primer lugar no
    /// fijo, con el tope del final de la lista.
    ///
    /// Se conserva la regla original para que un lugar nuevo no se adelante al
    /// campus, que es el único fijo.
    var indiceInsercion: Int {
        let primeroNoFijo = lugares.firstIndex { !$0.esFijo } ?? lugares.count
        return min(primeroNoFijo + 1, lugares.count)
    }

    /// Ids de las líneas ya guardadas, para marcarlas en el selector.
    var idsLineasGuardadas: Set<String> {
        Set(lineaRefs.map(\.routeId))
    }

    // MARK: - Carga

    /// Lugares y referencias de líneas desde el almacenamiento local.
    func cargar() {
        lugares = LugaresStore.cargar()
        if let data = UserDefaults.standard.data(forKey: Self.lineasKey),
           let refs = try? JSONDecoder().decode([LineaGuardadaRef].self, from: data) {
            lineaRefs = refs
        }
    }

    /// Catálogo del feed. Marca `catalogoCargado` incluso si llega vacío, para
    /// que la vista pueda distinguir "cargando" de "no hay datos".
    func cargarCatalogo() async {
        let feed = await GTFSRepository.shared.rutas()
        lineasGTFS = RutasViewModel.convertir(feed)
        catalogoCargado = true
    }

    // MARK: - Lugares

    func añadirLugar(_ nuevo: LugarGuardado) {
        lugares.insert(nuevo, at: indiceInsercion)
        LugaresStore.guardar(lugares)
    }

    func eliminarLugar(_ lugar: LugarGuardado) {
        lugares.removeAll { $0.id == lugar.id }
        LugaresStore.guardar(lugares)
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
            UserDefaults.standard.set(data, forKey: Self.lineasKey)
        }
    }
}
