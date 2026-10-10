import Foundation
import CoreLocation

/// Selección común para rutas, paraderos, itinerarios y seguimiento.
/// El catálogo urbano y el institucional mantienen cachés e identidades separadas.
enum TransporteApp {
    /// La temática y la sede deben pertenecer a UTP para ofrecer sus buses.
    /// No usar `sedeSeleccionada`: el propio modo de buses fuerza el campus.
    static var busesUTPDisponibles: Bool {
        TematicaEmpresaStore.shared.seleccion == .utp
            && SedeTrabajoStore.shared.utpComoReferencia
    }

    static var busesUTPActivos: Bool {
        busesUTPDisponibles && UserDefaults.standard.bool(forKey: PreferenciasApp.busesUTP)
    }

    static var repositorio: GTFSRepository {
        busesUTPActivos ? repositorioUTP : GTFSRepository.shared
    }

    /// El campus puede ser referencia también con las rutas urbanas.
    static var utpComoReferencia: Bool {
        busesUTPActivos || SedeTrabajoStore.shared.utpComoReferencia
    }

    static var referenciaInicio: CLLocationCoordinate2D {
        utpComoReferencia ? GTFSRepository.coordenadaUTP
            : SedeTrabajoStore.shared.sede?.coordinate ?? DestinosFijos.centroTrujillo
    }

    static var sedeVisible: SedeTrabajo? {
        utpComoReferencia ? nil : SedeTrabajoStore.shared.sede
    }

    /// Sede activa para los selectores, incluido el campus del modo Buses UTP.
    static var sedeSeleccionada: SedeTrabajo? {
        utpComoReferencia ? CatalogoSedesTrabajo.campusUTP : SedeTrabajoStore.shared.sede
    }

    @MainActor
    static func usarSedeTrabajo(_ sede: SedeTrabajo) {
        guard let valida = CatalogoSedesTrabajo.sede(id: sede.id) else { return }
        seleccionarEmpresa(valida.empresa)
        SedeTrabajoStore.shared.seleccionar(id: valida.id)
    }

    @MainActor
    static func seleccionarEmpresa(_ empresa: TematicaEmpresa) {
        // Cambiar de empresa vuelve al catálogo urbano, incluso sin una sede
        // disponible (Popeyes) o al volver a tocar la misma temática.
        if empresa != .utp {
            UserDefaults.standard.set(false, forKey: PreferenciasApp.busesUTP)
        }
        TematicaEmpresaStore.shared.seleccionar(empresa)
    }

    static var rutasUTPPendientes: Bool { busesUTPActivos && !hayFeedUTP }

    static var mensajePendiente: String {
        L.t("Las rutas de los buses UTP estarán disponibles próximamente.",
            "UTP bus routes will be available soon.")
    }

    /// La carpeta ya pertenece a Resources. Incorporar aquí el GTFS institucional
    /// permitirá reutilizar el planificador y los controles sin sustituir el feed urbano.
    private static let carpetaUTP = "gtfs-utp"
    private static let hayFeedUTP = Bundle.main.url(forResource: "routes", withExtension: "txt",
                                                   subdirectory: carpetaUTP) != nil
    private static let repositorioUTP = GTFSRepository(cargador: {
        guard hayFeedUTP else { return [] }
        return try GTFSRepository.parsearFeed(tabla: tablaUTP)
    })

    private static func tablaUTP(_ nombre: String) throws -> GTFSTable {
        // Nunca consultar GTFS_BUNDLE_DIR ni buscar archivos urbanos como fallback.
        guard let url = Bundle.main.url(forResource: nombre, withExtension: "txt",
                                       subdirectory: carpetaUTP) else {
            throw FalloCargaGTFS(detalle: "Falta gtfs-utp/\(nombre).txt")
        }
        let tabla = GTFSCSV.parsear(texto: try String(contentsOf: url, encoding: .utf8))
        var columnas = tabla.columns
        // Evita colisiones con favoritos, paraderos, reportes y cachés urbanos.
        for clave in ["agency_id", "route_id", "trip_id", "shape_id", "stop_id", "fare_id"] {
            if let valores = columnas[clave] {
                columnas[clave] = valores.map { $0.isEmpty ? "" : "utp:" + $0 }
            }
        }
        return GTFSTable(columns: columnas, rowCount: tabla.rowCount)
    }
}
