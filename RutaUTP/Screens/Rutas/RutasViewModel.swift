import Foundation
import Combine
import CoreLocation

// MARK: - ViewModel (carga GTFS)
@MainActor
final class RutasViewModel: ObservableObject {
    @Published private(set) var rutas: [RutaOpcion] = []
    @Published private(set) var cargando: Bool = true
    /// Vacío válido, separado tanto de un fallo de lectura como de una
    /// búsqueda sin coincidencias dentro de un catálogo cargado.
    @Published private(set) var feedVacio: Bool = false
    @Published private(set) var errorCarga: FalloCargaGTFS?
    @Published var textoBusqueda: String = ""
    private let repositorioGTFS: RutasGTFSProviding
    private var cargaEnCurso = false
    private var catalogoSolicitado = false
    private var indicesBusqueda: [String: IndiceBusquedaRuta] = [:]
    private var letrasCatalogo: Set<String> = []

    init(repositorioGTFS: RutasGTFSProviding = TransporteApp.repositorio) {
        self.repositorioGTFS = repositorioGTFS
    }

    /// Filtro "rutas que pasan cerca de X" (activado desde Guardado).
    @Published var filtroCerca: DestinoPendiente?
    @Published private(set) var distanciaALugar: [String: Double] = [:]

    static let radioCercaMetros: Double = 300

    var rutasFiltradas: [RutaOpcion] {
        let consulta = ConsultaRuta(textoBusqueda, letras: letrasCatalogo)
        let filtradas = rutas.filter { ruta in
            let cerca = filtroCerca == nil || (distanciaALugar[ruta.id] ?? .infinity) <= Self.radioCercaMetros
            return cerca && (indicesBusqueda[ruta.id]?.coincide(con: consulta) ?? false)
        }
        guard filtroCerca != nil else { return filtradas }
        return filtradas.sorted { (distanciaALugar[$0.id] ?? .infinity) < (distanciaALugar[$1.id] ?? .infinity) }
    }

    /// Texto "a X m del lugar" para la card bajo el filtro.
    func distanciaTexto(ruta: RutaOpcion) -> String? {
        guard filtroCerca != nil, let d = distanciaALugar[ruta.id] else { return nil }
        return d < 1000 ? L.f("a {0} m del lugar", "{0} m from place", ["\(Int((d / 10).rounded() * 10))"])
                        : L.f("a {0} km del lugar", "{0} km from place", [(d / 1000).formatted(.number.precision(.fractionLength(1)).locale(FormatoFecha.localeActivo))])
    }

    func cargar(reintentar: Bool = false) async {
        guard !cargaEnCurso, reintentar || !catalogoSolicitado else { return }
        cargaEnCurso = true
        cargando = true
        errorCarga = nil
        defer { cargando = false; cargaEnCurso = false }
        do {
            let feed = try await repositorioGTFS.cargarRutas(reintentar: reintentar)
            guard !Task.isCancelled else { return }
            let catalogo = Self.convertir(feed)
            indicesBusqueda = catalogo.reduce(into: [:]) { $0[$1.id] = IndiceBusquedaRuta(ruta: $1) }
            letrasCatalogo = Set(indicesBusqueda.values.map(\.letra).filter { !$0.isEmpty })
            rutas = catalogo
            feedVacio = rutas.isEmpty
            catalogoSolicitado = true
            if let destino = filtroCerca { activarFiltroCerca(destino: destino) }
        } catch {
            guard !Task.isCancelled else { return }
            errorCarga = (error as? FalloCargaGTFS) ?? FalloCargaGTFS(detalle: error.localizedDescription)
            feedVacio = false
            catalogoSolicitado = true
        }
    }

    /// Convierte el feed GTFS en el modelo de lista. Reutilizado por
    /// GuardadoView para las líneas guardadas.
    static func convertir(_ feed: [RutaGTFS]) -> [RutaOpcion] {
        feed.map { ruta in
            RutaOpcion(
                id: ruta.id,
                linea: ruta.linea,
                empresa: ruta.empresa,
                recorrido: ruta.recorrido,
                frecuenciaMin: ruta.headwayMin,
                duracionMin: ruta.duracionMin,
                costo: ruta.precioTexto,
                numParaderos: ruta.paraderos.count,
                distanciaKm: ruta.distanciaKm,
                colorLinea: ruta.color,
                shape: ruta.shape,
                paraderos: ruta.paraderos,
                paradaInicio: ruta.paraderos.first?.nombre ?? "",
                paradaFin: ruta.paraderos.last?.nombre ?? "",
                variante: ruta.variante
            )
        }
    }

    /// Busca paraderos donde se puede abordar, reutilizando la distancia de
    /// cada parada compartida. Ordena por la más cercana de cada línea.
    func activarFiltroCerca(destino: DestinoPendiente) {
        filtroCerca = destino
        var distancias: [String: Double] = [:]
        var distanciasPorParadero: [String: Double] = [:]
        let coordinate = destino.coordinate
        for ruta in rutas {
            var minima = Double.infinity
            for paradero in ruta.paraderos {
                let distancia: Double
                if let cached = distanciasPorParadero[paradero.id] {
                    distancia = cached
                } else {
                    distancia = PolylineMatching.distanceMeters(paradero.coordinate, coordinate)
                    distanciasPorParadero[paradero.id] = distancia
                }
                minima = min(minima, distancia)
            }
            distancias[ruta.id] = minima
        }
        distanciaALugar = distancias
    }

    func limpiarFiltroCerca() {
        filtroCerca = nil
        distanciaALugar = [:]
    }
}
