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

    init(repositorioGTFS: RutasGTFSProviding = GTFSRepository.shared) {
        self.repositorioGTFS = repositorioGTFS
    }

    /// Filtro "rutas que pasan cerca de X" (activado desde Guardado).
    @Published var filtroCerca: DestinoPendiente?
    @Published private(set) var distanciaALugar: [String: Double] = [:]

    static let radioCercaMetros: Double = 300

    var rutasFiltradas: [RutaOpcion] {
        if filtroCerca != nil {
            return rutas
                .filter { (distanciaALugar[$0.id] ?? .infinity) <= Self.radioCercaMetros }
                .sorted { (distanciaALugar[$0.id] ?? .infinity) < (distanciaALugar[$1.id] ?? .infinity) }
        }
        let t = textoBusqueda.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return rutas }
        return rutas.filter {
            $0.linea.localizedCaseInsensitiveContains(t)
            || $0.empresa.localizedCaseInsensitiveContains(t)
            || $0.recorrido.localizedCaseInsensitiveContains(t)
            || $0.variante.localizedCaseInsensitiveContains(t)
        }
    }

    /// Texto "a X m del lugar" para la card bajo el filtro.
    func distanciaTexto(ruta: RutaOpcion) -> String? {
        guard filtroCerca != nil, let d = distanciaALugar[ruta.id] else { return nil }
        return d < 1000 ? L.t("a \(Int((d / 10).rounded() * 10)) m del lugar", "\(Int((d / 10).rounded() * 10)) m from place")
                        : L.t(String(format: "a %.1f km del lugar", d / 1000),
                             String(format: "%.1f km from place", d / 1000))
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
            rutas = Self.convertir(feed)
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
                paradaInicio: ruta.paraderos.first?.nombre ?? L.t("Paradero inicial", "First stop"),
                paradaFin: ruta.paraderos.last?.nombre ?? L.t("Paradero final", "Last stop"),
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

