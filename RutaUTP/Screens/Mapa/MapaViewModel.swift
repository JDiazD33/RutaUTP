//
//  MapaViewModel.swift
//  RutaUTP
//
//  ViewModel del Mapa. Maneja:
//   - region (zoom al destino)
//   - textoBusqueda (binding del TextField)
//   - destinoSeleccionado (chip activo)
//   - busesAnimados (buses simulados sobre shapes reales del feed GTFS)
//
//  El timer se inicia al seleccionar destino y se detiene al limpiar
//  o al desaparecer la vista.
//

import SwiftUI
import MapKit
import Combine
import Observation

// MARK: - ViewModel
@MainActor
@Observable
final class MapaViewModel: NSObject, MKLocalSearchCompleterDelegate {

    // MARK: - Radio de búsqueda de ruta
    /// Distancia máxima a la que se acepta un paradero como punto de subida o
    /// de bajada, medida desde el origen y el destino.
    ///
    /// Antes eran 800 m y en la práctica dejaban fuera medio mapa: la UTP está
    /// en el borde de Trujillo y muchas rutas panes bien junto al destino pero
    /// no lo bastante. 1 600 m cubre una caminada de unos 12-15 min, que es lo
    /// que alguien está dispuesto a hacer si de verdad no hay nada más cerca.
    ///
    /// Es una constante y no un número suelto porque el mismo valor aparece en
    /// la búsqueda de candidatos, en el filtro del plan y en el mensaje de
    /// error: si uno de los tres se desincroniza, el usuario ve "no encontramos
    /// ruta a menos de 1 600 m" junto a un plan que el filtro ya descartó, y no
    /// hay forma de saber cuál de los dos va bien.
    nonisolated static let radioBusquedaRuta: Double = 1600

    let busesUTPActivos = TransporteApp.busesUTPActivos
    private(set) var utpComoReferencia = TransporteApp.utpComoReferencia
    private(set) var sedeTrabajo = TransporteApp.sedeVisible

    /// La sede elegida es la referencia; sin ella se usa GPS o Trujillo.
    var coordenadaInicio: CLLocationCoordinate2D {
        if utpComoReferencia { return GTFSRepository.coordenadaUTP }
        return sedeTrabajo?.coordinate ?? userRealCoordinate ?? DestinosFijos.centroTrujillo
    }

    // El mapa nunca asigna una empresa o sede por su cuenta.
    var region: MKCoordinateRegion = MapaViewModel.regionDeReferencia(TransporteApp.referenciaInicio)

    /// Acercamiento suave al abrir el mapa, conservando la sede de referencia.
    static func regionDeReferencia(_ centro: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(center: centro,
                           span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03))
    }

    /// El mismo zoom se aplica al GPS inicial y al botón de ubicación.
    static func regionDePersona(_ centro: CLLocationCoordinate2D,
                                duranteViaje: Bool = false) -> MKCoordinateRegion {
        let metros: CLLocationDistance = duranteViaje ? 850 : 1200
        return MKCoordinateRegion(center: centro, latitudinalMeters: metros, longitudinalMeters: metros)
    }

    var textoBusqueda: String = ""
    var destinoSeleccionado: DestinoChip? = nil
    var destinoFocusTick = 0
    @ObservationIgnored var selectionRevision = UUID()
    @ObservationIgnored var routeRevision = UUID()
    @ObservationIgnored var routeTask: Task<Void, Never>?
    @ObservationIgnored var activeSearch: MKLocalSearch?

    func invalidarSeleccionAnterior() {
        selectionRevision = UUID()
        routeRevision = UUID()
        activeSearch?.cancel()
        activeSearch = nil
        routeTask?.cancel()
        routeTask = nil
        buscando = false
        routePolyline = nil
        itinerarioInstalado = nil
        alternativasItinerario = []
        rutasDestacadas = []
        catalogoAlternativas = nil
        seleccionandoAlternativa = nil
        mensajeAlternativa = nil
        mensajeRuta = nil
        calculandoItinerario = false
        etaMinutos = nil
        busSeleccionado = nil
        completer.queryFragment = ""
        sugerenciasBusqueda = []
    }

    // GPS Real
    var userRealCoordinate: CLLocationCoordinate2D? = nil

    // Búsqueda MapKit
    var sugerenciasBusqueda: [MKLocalSearchCompletion] = []
    var busquedaResultado: (titulo: String, coordenada: CLLocationCoordinate2D)? = nil
    var buscando: Bool = false

    // Tracking & Ruteo Real (igual a RouteTrackingDemoView)
    var routePolyline: MKPolyline? = nil
    var itinerarioInstalado: InstalledTransitItinerary?
    var itinerario: TransitItinerary? { itinerarioInstalado?.plan }
    var alternativasItinerario: [TransitItinerary] = []
    var rutasDestacadas: [TransitRouteHighlight] = []
    /// Hasta tres tarjetas; una elección desde la lista ocupa una de ellas.
    var opcionesResumen: [TransitItinerary] {
        guard let installed = itinerario else { return [] }
        let principales = rutasDestacadas.map(\.plan)
        guard !principales.contains(where: { $0.optionID == installed.optionID }) else { return principales }
        return [installed] + principales.prefix(2)
    }
    func categorias(de plan: TransitItinerary) -> [TransitRouteCategory] {
        rutasDestacadas.first { $0.plan.optionID == plan.optionID }?.categories ?? []
    }
    var seleccionandoAlternativa: [String]?
    var mensajeAlternativa: String?
    @ObservationIgnored var catalogoAlternativas: GTFSRouteCatalog?
    var calculandoItinerario = false
    var buscandoItinerarioInicial: Bool { calculandoItinerario && seleccionandoAlternativa == nil }
    var mensajeRuta: String?
    var itinerarioFocusTick = 0
    var etaMinutos: Int? = nil

    // Buses Animados en Tiempo Real
    /// Estado VIVO de la simulación: avanza en cada tick (10 Hz) y NO se
    /// publica. La instantánea para la UI se actualiza solo cuando el avance
    /// acumulado supera el umbral o el bus cambia de sentido.
    @ObservationIgnored var flotaBuses: [BusAnimado] = []
    /// Instantánea publicada para la UI. Se refresca solo cuando algún bus se
    /// ha movido lo suficiente para que se note.
    var busesAnimados: [BusAnimado] = [] {
        didSet { refrescarPresentacionFlota() }
    }
    @ObservationIgnored private let mapVehiclePreferences: MapVehiclePreferences
    var busesEnMapa: [BusAnimado] {
        mapVehiclePreferences.limit.displayed(busesAnimados, selectedID: busSeleccionado?.id)
    }
    /// Encuadre explícito de la flota vigente; no mueve la cámara al recibir posiciones.
    var encuadreDeMicros: MKMapRect? {
        let points = busesEnMapa.map { MKMapPoint($0.coordinate) }
        guard let first = points.first else { return nil }
        var rect = MKMapRect(origin: first, size: MKMapSize(width: 1, height: 1))
        for point in points.dropFirst() {
            rect = rect.union(MKMapRect(origin: point, size: MKMapSize(width: 1, height: 1)))
        }
        // Margen para marcadores y paneles superior/inferior del mapa.
        return rect.insetBy(dx: -max(rect.width * 0.30, 1500),
                            dy: -max(rect.height * 0.65, 2000))
    }
    /// Catálogo del ancla vigente. La flota global permanece disponible en
    /// el mapa; el panel solo puede atribuirle unidades de estas rutas.
    var rutasCercanas: [RutaGTFS] = [] {
        didSet { refrescarPresentacionFlota() }
    }

    /// Una proyección de presentación: no duplica coordenadas ni geometría.
    /// Solo se reemplaza si cambian los valores que muestra el panel.
    private(set) var tarjetasDelPanel: [BusPanelItem] = []
    private var hayDatosRecientesDeFlota = false

    private func refrescarPresentacionFlota() {
        let tarjetas = busesDelPanel.map(BusPanelItem.init)
        if tarjetas != tarjetasDelPanel { tarjetasDelPanel = tarjetas }
        let hayDatos = !flotaBuses.isEmpty
            && flotaBuses.allSatisfy { $0.fuente == .real }
        if hayDatos != hayDatosRecientesDeFlota { hayDatosRecientesDeFlota = hayDatos }
    }

    func seleccionarBus(id: String) {
        busSeleccionado = busesAnimados.first { $0.id == id }
    }

    var busesDelPanel: [BusAnimado] {
        let ids = Set(rutasCercanas.map(\.id))
        return busesAnimados.filter { ids.contains($0.rutaId) }
    }

    var cantidadLineasDelPanel: Int {
        Set(tarjetasDelPanel.map(\.rutaId)).count
    }

    var esperandoPosicionesReales: Bool {
        fuenteFlota == .real && ultimasPosicionesReales == nil
    }

    var mensajePanelSinBuses: String {
        if TransporteApp.rutasUTPPendientes { return TransporteApp.mensajePendiente }
        if let error = errorLineas { return error.mensajeUsuario }
        if rutasCercanas.isEmpty {
            return L.t("No encontramos líneas cerca de este punto",
                       "No lines were found near this point")
        }
        return fuenteFlota == .real
            ? L.t("Aún no hay posiciones recientes para estas líneas",
                  "There are no recent positions for these lines yet")
            : L.t("No hay buses de demostración disponibles", "No demo buses are available")
    }

    var textoEstadoLineas: String {
        if TransporteApp.rutasUTPPendientes { return L.t("Rutas próximamente", "Routes coming soon") }
        if cargandoLineas { return L.t("Buscando líneas…", "Finding lines…") }
        let cantidad = cantidadLineasDelPanel
        guard cantidad > 0 else { return mensajePanelSinBuses }
        if let destino = busquedaResultado {
            return cantidad == 1
                ? L.f("1 línea pasa por {0}", "1 line passes by {0}", [destino.titulo])
                : L.f("{0} líneas pasan por {1}", "{0} lines pass by {1}", ["\(cantidad)", destino.titulo])
        }
        let referencia = utpComoReferencia ? L.t("Campus UTP Trujillo", "UTP Trujillo campus")
            : sedeTrabajo?.nombre ?? L.t("este punto", "this point")
        return cantidad == 1
            ? L.f("1 línea cerca de {0}", "1 line near {0}", [referencia])
            : L.f("{0} líneas cerca de {1}", "{0} lines near {1}", ["\(cantidad)", referencia])
    }

    var busSeleccionado: BusAnimado? = nil
    var fuenteFlota: VehicleTrackingSource = .simulated

    var hayPosicionesRealesRecientes: Bool {
        fuenteFlota == .real && hayDatosRecientesDeFlota
    }
    /// Movimiento mínimo (m) para publicar una nueva instantánea.
    /// La simulación avanza por tiempo real y acumula los desplazamientos
    /// menores al umbral desde la última instantánea visible. Los cambios
    /// de sentido también se publican. Observation y los componentes
    /// delimitan quién lee cada cambio.
    static let metrosMinimosParaPublicar: Double = 1.5
    /// True mientras se consulta el feed por las líneas del punto actual.
    var cargandoLineas: Bool = false
    var errorLineas: FalloCargaGTFS?
    @ObservationIgnored var busSimulationTask: Task<Void, Never>?
    @ObservationIgnored var actividadVisual = true
    @ObservationIgnored var simulacionBusesIniciada = false
    @ObservationIgnored var lineasTask: Task<Void, Never>?
    @ObservationIgnored var lineasRevision = UUID()
    @ObservationIgnored var flotaRevision = UUID()

    /// Proveedor de posiciones vehiculares reales. Solo se crea cuando hay
    /// configuración de broker; sin ella el mapa sigue con su propia flota.
    @ObservationIgnored var vehicleProvider: VehicleTrackingProviding?

    /// Consumo del stream de posiciones del proveedor.
    @ObservationIgnored var vehicleTrackingTask: Task<Void, Never>?

    /// Catálogo GTFS indexado por `route_id`, para resolver empresa, color y
    /// variante de un vehículo real. `VehiclePosition` viaja con `routeId`,
    /// que es único; `linea` no lo es (dos ramales la comparten).
    @ObservationIgnored var etaRealCache = VehicleETACache()
    var rutasPorId: [String: RutaGTFS] = [:] {
        didSet { etaRealCache.install(catalog: rutasPorId) }
    }
    /// nil mientras esperamos el primer snapshot; [] es un snapshot vacío.
    /// Cambiar de destino recalcula ETA sin inventar unidades ni reiniciar MQTT.
    var ultimasPosicionesReales: [VehiclePosition]?
    /// Último tick del timer: para mover los buses por tiempo transcurrido
    /// real (metros = velocidad × dt) y no por pasos fijos de segmento.
    @ObservationIgnored var ultimoTickBuses: Date?
    /// Punto de interés actual del panel (destino, sede o ubicación disponible).
    /// Evita relanzar la consulta GTFS si el ancla no cambió y permite
    /// descartar resultados obsoletos si el usuario cambió de destino.
    var anclaLineas: (lat: Double, lon: Double)? = nil

    /// Se incrementa cada vez que el usuario pide recentrar; la vista lo
    /// observa para mover la cámara aunque la región no haya cambiado de
    /// valor (el usuario puede haber arrastrado el mapa sin pasar por aquí).
    var recentrarToken = 0

    private let locationService: LocationServiceProtocol
    /// El mismo servicio compartido, expuesto para las pantallas que lo
    /// necesitan sin instanciar un segundo `CLLocationManager` (el reporte de
    /// cambios de ruta lo usa para colocar el pin en la posición actual).
    var sharedLocationService: LocationServiceProtocol { locationService }

    let routeService: RouteCalculationService
    let repositorioGTFS: RutasGTFSProviding
    let crearProveedorReal: @MainActor () -> VehicleTrackingProviding?
    let completer = MKLocalSearchCompleter()
    @ObservationIgnored private var locationTask: Task<Void, Never>?

    init(
        locationService: LocationServiceProtocol? = nil,
        routeService: RouteCalculationService = RouteCalculationService(),
        repositorioGTFS: RutasGTFSProviding = TransporteApp.repositorio,
        mapVehiclePreferences: MapVehiclePreferences? = nil,
        crearProveedorReal: @escaping @MainActor () -> VehicleTrackingProviding? = {
            guard !TransporteApp.rutasUTPPendientes else { return nil }
            guard MQTTConfiguration.fromEnvironment() != nil else { return nil }
            return TrackingProviderFactory.makeDefault()
        }
    ) {
        self.locationService = locationService ?? LocationService()
        self.routeService = routeService
        self.repositorioGTFS = repositorioGTFS
        self.crearProveedorReal = crearProveedorReal
        self.mapVehiclePreferences = mapVehiclePreferences ?? .shared
        super.init()

        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
        completer.region = MKCoordinateRegion(
            center: DestinosFijos.centroTrujillo,
            span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
        )

        refrescarDestinos()
    }

    /// Cambiar la referencia de inicio no sustituye un viaje ya elegido.
    func actualizarSedeTrabajo() {
        let nueva = TransporteApp.sedeVisible
        let campus = TransporteApp.utpComoReferencia
        guard sedeTrabajo?.id != nueva?.id || utpComoReferencia != campus else { return }
        sedeTrabajo = nueva
        utpComoReferencia = campus
        guard busquedaResultado == nil else { return }
        region = Self.regionDeReferencia(coordenadaInicio)
        recentrarToken += 1
        recargarLineas(cercaDe: nil)
    }

    deinit {
        locationTask?.cancel()
        routeTask?.cancel()
        lineasTask?.cancel()
        activeSearch?.cancel()
        busSimulationTask?.cancel()
        vehicleTrackingTask?.cancel()
        if let provider = vehicleProvider {
            Task { @MainActor in provider.stop() }
        }
    }

    /// Libera el trabajo de esta pantalla aunque el ViewModel siga en memoria.
    func detener() {
        locationTask?.cancel()
        locationTask = nil
        if vehicleProvider?.keepsConnectionWhileMapHidden != true {
            if fuenteFlota == .real {
                detenerSimulacionBuses()
            } else {
                pausarSimulacionBuses()
            }
        }
        invalidarSeleccionAnterior()
        // Al volver, el primer fix recalcula el destino que siga seleccionado.
        userRealCoordinate = nil
    }

    /// Pausa la flota simulada sin borrar el catálogo ni las posiciones.
    ///
    /// Si al volver al mapa el ancla sigue siendo la misma, `recargarLineas`
    /// no vuelve a consultar y la simulación reanuda donde quedó. Así el
    /// panel conserva sus tarjetas y los buses no saltan a posiciones nuevas
    /// durante la entrada a la pestaña.
    private func pausarSimulacionBuses() {
        simulacionBusesIniciada = false
        busSimulationTask?.cancel()
        busSimulationTask = nil
        ultimoTickBuses = nil
    }

    // MARK: - Ubicación GPS Real
    func iniciarGPS() {
        locationTask?.cancel()
        let locationService = locationService
        locationTask = Task { @MainActor [weak self] in
            let status = await locationService.requestPermission()
            guard !Task.isCancelled, self != nil else { return }
            if status.isAuthorized {
                let stream = locationService.currentLocation(requirement: .mapDisplay)
                locationService.startUpdating()
                for await location in stream {
                    // Retener la pantalla solo mientras se procesa este fix,
                    // nunca durante la espera del siguiente.
                    guard !Task.isCancelled, let self else { return }
                    guard UbicacionPuntual.esValida(location, ahora: Date()) else { continue }
                    let isInitialFix = (self.userRealCoordinate == nil)
                    self.userRealCoordinate = location.coordinate
                    if isInitialFix {
                        if self.busquedaResultado == nil, self.sedeTrabajo == nil, !self.utpComoReferencia {
                            self.recenterOnUser()
                            self.recargarLineas(cercaDe: nil)
                        }

                        // Un destino puede elegirse antes del primer fix:
                        // calcular su itinerario al recibir la ubicación real.
                        if let destino = self.busquedaResultado {
                            #if DEBUG
                            print("[Ruta] primer fix GPS real → recalculando desde (\(location.coordinate.latitude), \(location.coordinate.longitude)) hacia \(destino.titulo)")
                            #endif
                            self.calcularRutaHacia(destino.coordenada)
                        }
                    }
                }
            }
        }
        iniciarSimulacionBuses()
    }

    func recenterOnUser() {
        if let userCoord = userRealCoordinate {
            // Token: garantiza que la vista mueva la cámara aunque la
            // región ya tuviera ese valor (tras arrastrar el mapa, la
            // cámara local cambia pero `region` no se entera).
            recentrarToken += 1
            withAnimation(.spring(response: 0.5)) {
                region = Self.regionDePersona(userCoord)
            }
        } else {
            iniciarGPS()
        }
    }

    /// Lugares guardados leídos de disco. Se cachean aquí para que `destinos`
    /// pueda ser calculada sin tocar `UserDefaults` en cada render.
    /// Observation permite que refrescar la lista actualice sus chips.
    var lugaresParaChips: [LugarGuardado] = []

}
