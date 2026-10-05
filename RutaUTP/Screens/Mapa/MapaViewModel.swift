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

// MARK: - Bus animado sobre ruta real
// Se conserva la flota propia del mapa: usa shapes reducidos y publicación
// por desplazamiento visible. Tracking usa los vértices originales y su
// protocolo de posiciones. Unificarlos cambiaría esos ciclos; compartimos
// la geometría del rumbo en PolylineMatching para evitar fórmulas divergentes.
struct BusAnimado: Identifiable, Equatable {
    let id: String
    let linea: String        // "10", "4"
    let rutaId: String       // route_id GTFS: enlaza con el detalle de RutasView
    let empresa: String      // "El Cortijo", "Salaverry"
    let tipo: String          // "Micro", "Combi"
    /// Variante original del feed, sin traducir ni confundirla con una matrícula.
    let variante: String

    /// Se resuelve al mostrar: cambiar ES/EN no requiere reconstruir la flota.
    var ramalTexto: String {
        variante.isEmpty ? L.t("S/D", "N/A") : L.t("Ramal \(variante)", "Branch \(variante)")
    }
    let minutosLlegada: Int?   // 4, 12 — o nil si no hay estimación
    let color: Color          // .appPrimary, .secondary
    var lat: Double           // posición actual (animada)
    var lon: Double
    var heading: Double       // ángulo de dirección
    let rutaCoordenadas: [CLLocationCoordinate2D]  // waypoints

    // Simulación tipo flota real: la posición se lleva por DISTANCIA
    // recorrida sobre el shape, no por fracción de segmento.
    /// Distancia acumulada (m) de cada waypoint desde el inicio del shape.
    let acumulados: [Double]
    /// Metros recorridos a lo largo del shape (0...longitudRutaM).
    var distanciaM: Double = 0
    /// Velocidad crucero propia del vehículo (m/s).
    var velocidadMS: Double = 8
    var isMovingForward: Bool = true
    /// Tramo [i, i+1] donde cayó la última interpolación (cache).
    var tramoActual: Int = 0

    /// De dónde procede la posición de este vehículo.
    ///
    /// `.simulated` es la flota que el mapa anima sobre los shapes del feed,
    /// que es lo que se ve cuando no hay broker configurado. `.real` es una
    /// posición publicada por el backend por el canal MQTT a partir de las
    /// observaciones de los pasajeros a bordo.
    ///
    /// Un vehículo real no trae geometría propia: `rutaCoordenadas` y
    /// `acumulados` van vacíos, así que `actualizarPosicion()` no hace nada y
    /// la posición la fija cada mensaje del broker, no la animación local.
    var fuente: VehicleTrackingSource = .simulated

    /// Texto de la llegada para la interfaz.
    ///
    /// Las posiciones reales muestran `~` porque su llegada se estima con la
    /// posición, rumbo y velocidad disponibles sobre el recorrido GTFS. Si el
    /// vehículo se aleja del punto consultado o faltan datos fiables, se evita
    /// inventar un valor y se muestra "SIN ETA".
    var etiquetaLlegada: String {
        guard let minutosLlegada else {
            return L.t("SIN ETA", "NO ETA")
        }

        return fuente == .real
            ? "~\(minutosLlegada) MIN"
            : "\(minutosLlegada) MIN"
    }

    var longitudRutaM: Double { acumulados.last ?? 0 }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Coloca lat/lon/heading en el punto del shape que corresponde a
    /// `distanciaM` metros del inicio. Los buses avanzan pocos metros por
    /// tick, así que el índice de tramo se ajusta incrementalmente en vez
    /// de buscar desde cero.
    mutating func actualizarPosicion() {
        guard acumulados.count == rutaCoordenadas.count,
              rutaCoordenadas.count >= 2 else { return }

        var i = min(max(tramoActual, 0), rutaCoordenadas.count - 2)
        while i > 0 && distanciaM < acumulados[i] { i -= 1 }
        while i < rutaCoordenadas.count - 2 && distanciaM > acumulados[i + 1] { i += 1 }

        let a = rutaCoordenadas[i]
        let b = rutaCoordenadas[i + 1]
        let largo = acumulados[i + 1] - acumulados[i]
        let f = largo > 0.5 ? min(1, max(0, (distanciaM - acumulados[i]) / largo)) : 0

        lat = a.latitude + (b.latitude - a.latitude) * f
        lon = a.longitude + (b.longitude - a.longitude) * f
        heading = PolylineMatching.headingDegrees(from: a, to: b,
                                                   movingForward: isMovingForward)
        tramoActual = i
    }

    static func == (lhs: BusAnimado, rhs: BusAnimado) -> Bool {
        lhs.id == rhs.id &&
        lhs.lat == rhs.lat &&
        lhs.lon == rhs.lon &&
        lhs.heading == rhs.heading
    }
}

// MARK: - ETA aproximada de vehículos reales

/// Estima la llegada de una posición MQTT al punto consultado en el mapa.
///
/// El cálculo sigue el shape GTFS, respeta el sentido indicado por el rumbo y
/// usa la velocidad observada, incluso en tráfico lento. Solo si la velocidad
/// es desconocida usa la media programada. Sin rumbo o con el bus detenido no
/// puede anticipar la llegada; tampoco cuando está fuera de ruta o se aleja.
enum VehicleETAEstimator {

    static func minutes(
        position: VehiclePosition,
        route: RutaGTFS,
        target: CLLocationCoordinate2D
    ) -> Int? {
        guard route.shape.count >= 2 else { return nil }

        guard
            let vehicleMatch = PolylineMatching.match(
                point: position.coordinate,
                on: route.shape,
                thresholdMeters: 120
            ),
            vehicleMatch.isOnRoute,
            // El destino puede estar hasta `radioBusquedaRuta` del recorrido
            // (es lo que se acepta como bajada). Con el umbral viejo en 800,
            // una ruta válida a 1 000 m de la calle habría llegado aquí sin
            // ETA: el plan se aceptaba, pero el tiempo hasta llegar se negaba
            // en silencio. El mismo umbral evita esa contradicción.
            let targetMatch = PolylineMatching.match(
                point: target,
                on: route.shape,
                thresholdMeters: MapaViewModel.radioBusquedaRuta
            ),
            targetMatch.isOnRoute
        else {
            return nil
        }

        let routeLength = PolylineMatching.totalLengthMeters(route.shape)
        guard routeLength > 0 else { return nil }

        var progressDelta = targetMatch.progressFraction
            - vehicleMatch.progressFraction

        let segmentIndex = min(
            vehicleMatch.segmentIndex,
            route.shape.count - 2
        )
        let forwardHeading = PolylineMatching.headingDegrees(
            from: route.shape[segmentIndex],
            to: route.shape[segmentIndex + 1],
            movingForward: true
        )

        let movingForward: Bool?
        if position.heading.isFinite, position.heading >= 0, forwardHeading >= 0 {
            movingForward = angularDifference(
                position.heading,
                forwardHeading
            ) <= 90
        } else {
            movingForward = nil
        }

        let isCircular = PolylineMatching.distanceMeters(
            route.shape[0],
            route.shape[route.shape.count - 1]
        ) <= 200

        guard let movingForward else { return nil }
        if isCircular {
            if movingForward, progressDelta < 0 { progressDelta += 1 }
            if !movingForward, progressDelta > 0 { progressDelta -= 1 }
        } else {
            guard movingForward ? progressDelta >= 0 : progressDelta <= 0 else {
                return nil
            }
        }

        let remainingMeters = abs(progressDelta) * routeLength
        guard remainingMeters.isFinite else { return nil }

        let scheduledSpeed: Double = {
            guard route.duracionMin > 0 else { return 7 }
            return routeLength / (Double(route.duracionMin) * 60)
        }()
        // Estar detenido no equivale a circular a la velocidad programada.
        // El umbral de 0.5 m/s evita extrapolar el ruido de un GPS inmóvil.
        guard position.speed.isFinite else { return nil }
        if position.speed >= 0, position.speed < 0.5 { return nil }
        let effectiveSpeed = position.speed >= 0.5
            ? min(position.speed, 15)
            : min(max(scheduledSpeed, 0.5), 15)

        let estimate = ceil(remainingMeters / effectiveSpeed / 60)
        // No convertir una espera superior a dos horas en exactamente 120 min.
        guard estimate.isFinite, estimate <= 120 else { return nil }
        return max(Int(estimate), 1)
    }

    private static func angularDifference(_ lhs: Double, _ rhs: Double) -> Double {
        let difference = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }
}

// MARK: - Destino chip
struct DestinoChip: Identifiable, Equatable {
    let id: Int
    let label: String
    let icon: String
    let lat: Double
    let lon: Double
    /// Clave estable del Modo Señas (nil = el chip no es señable).
    let claveSenia: String?

    init(id: Int, label: String, icon: String, lat: Double, lon: Double, claveSenia: String? = nil) {
        self.id = id
        self.label = label
        self.icon = icon
        self.lat = lat
        self.lon = lon
        self.claveSenia = claveSenia
    }
}

// MARK: - Anotación unificada para el mapa (usada por RutasView)
enum TipoAnotacion: Equatable {
    case utp
    case usuario
}

struct MapaAnotacion: Identifiable, Equatable {
    let id: Int
    let lat: Double
    let lon: Double
    let tipo: TipoAnotacion

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

// MARK: - ViewModel
final class MapaViewModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {

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
    static let radioBusquedaRuta: Double = 1600

    // Región por defecto centrada en Trujillo / UTP
    @Published var region: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: -8.098247879173792, longitude: -79.03818104755645),
        span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
    )

    @Published var textoBusqueda: String = ""
    @Published var destinoSeleccionado: DestinoChip? = nil
    @Published private(set) var destinoFocusTick = 0
    private var selectionRevision = UUID()
    private var routeRevision = UUID()
    private var routeTask: Task<Void, Never>?
    private var activeSearch: MKLocalSearch?

    private func invalidarSeleccionAnterior() {
        selectionRevision = UUID()
        routeRevision = UUID()
        activeSearch?.cancel()
        activeSearch = nil
        routeTask?.cancel()
        routeTask = nil
        buscando = false
        routePolyline = nil
        itinerario = nil
        mensajeRuta = nil
        calculandoItinerario = false
        etaMinutos = nil
        distanciaKm = nil
        busSeleccionado = nil
        completer.queryFragment = ""
        sugerenciasBusqueda = []
    }

    // GPS Real
    @Published var userRealCoordinate: CLLocationCoordinate2D? = nil

    // Búsqueda MapKit
    @Published var sugerenciasBusqueda: [MKLocalSearchCompletion] = []
    @Published var busquedaResultado: (titulo: String, coordenada: CLLocationCoordinate2D)? = nil
    @Published var buscando: Bool = false

    // Tracking & Ruteo Real (igual a RouteTrackingDemoView)
    @Published var routePolyline: MKPolyline? = nil
    @Published private(set) var itinerario: TransitItinerary?
    @Published private(set) var calculandoItinerario = false
    @Published private(set) var mensajeRuta: String?
    @Published private(set) var itinerarioFocusTick = 0
    @Published var etaMinutos: Int? = nil
    @Published var distanciaKm: Double? = nil

    // Buses Animados en Tiempo Real
    /// Estado VIVO de la simulación: avanza en cada tick (20 Hz) y NO se
    /// publica. Mantenerlo separado es lo que evita redibujar el mapa entero
    /// 20 veces por segundo.
    private var flotaBuses: [BusAnimado] = []
    /// Instantánea publicada para la UI. Se refresca solo cuando algún bus se
    /// ha movido lo suficiente para que se note.
    @Published var busesAnimados: [BusAnimado] = []
    /// Catálogo del ancla vigente. La flota global permanece disponible en
    /// el mapa; el panel solo puede atribuirle unidades de estas rutas.
    @Published private(set) var rutasCercanas: [RutaGTFS] = []

    var busesDelPanel: [BusAnimado] {
        let ids = Set(rutasCercanas.map(\.id))
        return busesAnimados.filter { ids.contains($0.rutaId) }
    }

    var cantidadLineasDelPanel: Int {
        Set(busesDelPanel.map(\.rutaId)).count
    }

    var esperandoPosicionesReales: Bool {
        fuenteFlota == .real && ultimasPosicionesReales == nil
    }

    var mensajePanelSinBuses: String {
        if let error = errorLineas { return error.mensajeUsuario }
        if rutasCercanas.isEmpty {
            return L.t("No encontramos líneas cerca de este punto",
                       "No lines were found near this point")
        }
        return fuenteFlota == .real
            ? L.t("Aún no hay buses confirmados para estas líneas",
                  "There are no confirmed buses for these lines yet")
            : L.t("No hay buses de demostración disponibles", "No demo buses are available")
    }

    var textoEstadoLineas: String {
        if cargandoLineas { return L.t("Buscando líneas…", "Finding lines…") }
        let cantidad = cantidadLineasDelPanel
        guard cantidad > 0 else { return mensajePanelSinBuses }
        if let destino = busquedaResultado {
            return cantidad == 1
                ? String(format: L.t("1 línea pasa por %@", "1 line passes by %@"), destino.titulo)
                : String(format: L.t("%d líneas pasan por %@", "%d lines pass by %@"), cantidad, destino.titulo)
        }
        return cantidad == 1
            ? L.t("1 línea cerca del campus", "1 line near campus")
            : String(format: L.t("%d líneas cerca del campus", "%d lines near campus"), cantidad)
    }

    @Published var busSeleccionado: BusAnimado? = nil
    @Published private(set) var fuenteFlota: VehicleTrackingSource = .simulated

    var hayPosicionesRealesRecientes: Bool {
        fuenteFlota == .real && !flotaBuses.isEmpty
            && flotaBuses.allSatisfy { $0.fuente == .real }
    }
    /// Movimiento mínimo (m) para publicar una nueva instantánea. A 20 Hz cada
    /// tick avanza unos centímetros, así que casi todas las publicaciones no
    /// cambiaban nada visible pero rehacían el cuerpo de `MapaView` completo
    /// —mapa, anotaciones, buscador y panel de tarjetas—. Con este umbral se
    /// publica ~7 veces por segundo a velocidad urbana.
    private static let metrosMinimosParaPublicar: Double = 1.5
    /// True mientras se consulta el feed por las líneas del punto actual.
    @Published private(set) var cargandoLineas: Bool = false
    @Published private(set) var errorLineas: FalloCargaGTFS?
    private var busSimulationTask: Task<Void, Never>?
    private var lineasTask: Task<Void, Never>?
    private var lineasRevision = UUID()
    private var flotaRevision = UUID()

    /// Proveedor de posiciones vehiculares reales. Solo se crea cuando hay
    /// configuración de broker; sin ella el mapa sigue con su propia flota.
    private var vehicleProvider: VehicleTrackingProviding?

    /// Consumo del stream de posiciones del proveedor.
    private var vehicleTrackingTask: Task<Void, Never>?

    /// Catálogo GTFS indexado por `route_id`, para resolver empresa, color y
    /// variante de un vehículo real. `VehiclePosition` viaja con `routeId`,
    /// que es único; `linea` no lo es (dos ramales la comparten).
    private var rutasPorId: [String: RutaGTFS] = [:]
    /// nil mientras esperamos el primer snapshot; [] es un snapshot vacío.
    /// Cambiar de destino recalcula ETA sin inventar unidades ni reiniciar MQTT.
    private var ultimasPosicionesReales: [VehiclePosition]?
    /// Último tick del timer: para mover los buses por tiempo transcurrido
    /// real (metros = velocidad × dt) y no por pasos fijos de segmento.
    private var ultimoTickBuses: Date?
    /// Punto de interés actual del panel (destino elegido o campus UTP).
    /// Evita relanzar la consulta GTFS si el ancla no cambió y permite
    /// descartar resultados obsoletos si el usuario cambió de destino.
    private var anclaLineas: (lat: Double, lon: Double)? = nil

    /// Se incrementa cada vez que el usuario pide recentrar; la vista lo
    /// observa para mover la cámara aunque la región no haya cambiado de
    /// valor (el usuario puede haber arrastrado el mapa sin pasar por aquí).
    @Published var recentrarToken = 0

    private let locationService: LocationServiceProtocol
    /// El mismo servicio compartido, expuesto para las pantallas que lo
    /// necesitan sin instanciar un segundo `CLLocationManager` (el reporte de
    /// cambios de ruta lo usa para colocar el pin en la posición actual).
    var sharedLocationService: LocationServiceProtocol { locationService }

    private let routeService: RouteCalculationService
    private let repositorioGTFS: RutasGTFSProviding
    private let crearProveedorReal: () -> VehicleTrackingProviding?
    private let completer = MKLocalSearchCompleter()
    private var locationTask: Task<Void, Never>?

    init(
        locationService: LocationServiceProtocol = LocationService(),
        routeService: RouteCalculationService = RouteCalculationService(),
        repositorioGTFS: RutasGTFSProviding = GTFSRepository.shared,
        crearProveedorReal: @escaping () -> VehicleTrackingProviding? = {
            guard MQTTConfiguration.fromEnvironment() != nil else { return nil }
            return TrackingProviderFactory.makeDefault()
        }
    ) {
        self.locationService = locationService
        self.routeService = routeService
        self.repositorioGTFS = repositorioGTFS
        self.crearProveedorReal = crearProveedorReal
        super.init()

        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -8.098247879173792, longitude: -79.03818104755645),
            span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
        )

        refrescarDestinos()
    }

    /// Reconstruye los chips: fijos + lugares guardados por el usuario.
    ///
    /// Llamar al aparecer la pantalla (onAppear): si el usuario guardó o
    /// eliminó un lugar en la pestaña Guardado, el chip aparece/desaparece
    /// aquí sin reiniciar la app. LugaresStore es la misma fuente que
    /// GuardadoView, así ambos siempre ven lo mismo.
    func refrescarDestinos() {
        lugaresParaChips = LugaresStore.cargar()

        // Si el destino seleccionado era un chip guardado que ya no existe,
        // limpiarlo para no mostrar una ruta hacia un lugar eliminado.
        if let seleccionado = destinoSeleccionado,
           seleccionado.id >= 100,
           !destinos.contains(where: { $0.id == seleccionado.id && $0.label == seleccionado.label }) {
            destinoSeleccionado = nil
            busquedaResultado = nil
            invalidarSeleccionAnterior()
        }
    }

    deinit {
        locationTask?.cancel()
        routeTask?.cancel()
        lineasTask?.cancel()
        activeSearch?.cancel()
        locationService.stopUpdating()
        detenerSimulacionBuses()
    }

    /// Libera el trabajo de esta pantalla aunque el ViewModel siga en memoria.
    func detener() {
        locationTask?.cancel()
        locationTask = nil
        locationService.stopUpdating()
        detenerSimulacionBuses()
        invalidarSeleccionAnterior()
        // Al volver, el primer fix recalcula el destino que siga seleccionado.
        userRealCoordinate = nil
    }

    // MARK: - Ubicación GPS Real
    func iniciarGPS() {
        locationTask?.cancel()
        let locationService = locationService
        locationTask = Task { @MainActor [weak self] in
            let status = await locationService.requestPermission()
            guard !Task.isCancelled, self != nil else { return }
            if status.isAuthorized {
                locationService.startUpdating()
                for await location in locationService.currentLocation() {
                    // Retener la pantalla solo mientras se procesa este fix,
                    // nunca durante la espera del siguiente.
                    guard !Task.isCancelled, let self else { return }
                    let isInitialFix = (self.userRealCoordinate == nil)
                    self.userRealCoordinate = location.coordinate
                    if isInitialFix {
                        if self.busquedaResultado == nil { self.recenterOnUser() }

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

    // MARK: - Simulación de Buses Animados
    //
    // Los recorridos (shapes) son REALES del feed GTFS embebido; las
    // posiciones son SIMULADAS porque el feed estático no incluye GPS.
    // La simulación imita una flota real: vehículos repartidos por sus
    // corredores, con dirección y velocidad propias (25–43 km/h), que
    // avanzan metros reales sobre el shape según el tiempo transcurrido.
    func iniciarSimulacionBuses() {
        // Con broker configurado, el mapa muestra vehículos OBSERVADOS; sin él,
        // la flota que el propio mapa anima. Nunca las dos a la vez: cada línea
        // aparecería duplicada en el mapa.
        //
        // Cada consulta también verifica su fuente al completar: una tarea
        // iniciada antes de conectar MQTT no puede sustituir la flota real.
        if iniciarFlotaReal() { return }

        if fuenteFlota != .simulated {
            invalidarConsultaLineas()
            flotaBuses = []
            busesAnimados = []
            busSeleccionado = nil
            ultimasPosicionesReales = nil
        }
        fuenteFlota = .simulated

        // Al volver a la pantalla, conservar el destino elegido si lo hay.
        recargarLineas(cercaDe: busquedaResultado?.coordenada)

        guard busSimulationTask == nil else { return }
        ultimoTickBuses = nil
        // Bucle de simulación aislado al hilo principal. Antes era un `Timer`
        // que despachaba un bloque a la cola principal en cada tick — veinte
        // por segundo — sin aislamiento verificable ni cancelación estructurada.
        busSimulationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard !Task.isCancelled, let self else { return }
                self.actualizarPosicionBuses()
            }
        }
    }

    /// Recarga las líneas del panel según un punto de interés: el destino
    /// seleccionado (chip, Guardado, búsqueda) o, por defecto, el campus.
    /// Solo la demo genera unidades desde el feed. En modo real el catálogo
    /// describe recorridos, y las posiciones provienen exclusivamente del canal.
    func recargarLineas(cercaDe ancla: CLLocationCoordinate2D?, reintentar: Bool = false) {
        let punto = ancla ?? GTFSRepository.coordenadaUTP
        let clave = (lat: punto.latitude, lon: punto.longitude)
        if !reintentar, let previa = anclaLineas,
           abs(previa.lat - clave.lat) < 1e-9,
           abs(previa.lon - clave.lon) < 1e-9 { return }
        anclaLineas = clave

        lineasTask?.cancel()
        lineasTask = nil
        let revision = UUID()
        lineasRevision = revision
        // Retirar el filtro anterior mientras se consulta el nuevo destino.
        // Un snapshot recibido durante esta espera solo actualiza la flota.
        rutasCercanas = []
        if fuenteFlota == .real {
            if let posiciones = ultimasPosicionesReales {
                aplicarFlotaReal(posiciones)
            }
        }

        let fuenteConsulta = fuenteFlota
        let repositorio = repositorioGTFS
        cargandoLineas = true
        errorLineas = nil
        lineasTask = Task { @MainActor [weak self] in
            // 400 m cubre "pasa por la puerta"; si el punto quedó algo
            // alejado del recorrido se amplía a 800 m antes de declarar
            // que no pasa ninguna línea.
            //
            // OJO: este 800 NO es `radioBusquedaRuta`. Aquí se pregunta qué
            // líneas pasan por el punto (la lista de transportes cercanos);
            // allí se pregunta qué paraderos sirven para un viaje concreto.
            // Subir este valor sí tendría efecto, pero llenaría el panel de
            // líneas cercanas con rutas que no pasan por donde está la persona.
            let feed: [RutaGTFS]
            var catalogoRecuperado: [RutaGTFS]?
            do {
                var cercanas = try await repositorio.consultarRutasQuePasanPor(
                    punto, radioMetros: 400, reintentar: reintentar)
                guard !Task.isCancelled else { return }
                if cercanas.isEmpty {
                    cercanas = try await repositorio.consultarRutasQuePasanPor(
                        punto, radioMetros: 800)
                }
                feed = cercanas
                if reintentar, fuenteConsulta == .real {
                    catalogoRecuperado = try await repositorio.cargarRutas()
                }
            } catch {
                guard !Task.isCancelled, let self, self.lineasRevision == revision,
                      self.fuenteFlota == fuenteConsulta, self.anclaLineas?.lat == clave.lat,
                      self.anclaLineas?.lon == clave.lon else { return }
                self.errorLineas = (error as? FalloCargaGTFS) ?? FalloCargaGTFS(detalle: error.localizedDescription)
                self.cargandoLineas = false
                self.lineasTask = nil
                return
            }
            // El usuario pudo cambiar de destino mientras consultaba.
            guard !Task.isCancelled, let self, self.lineasRevision == revision,
                  self.fuenteFlota == fuenteConsulta, self.anclaLineas?.lat == clave.lat,
                  self.anclaLineas?.lon == clave.lon else { return }

            var ids = Set<String>()
            self.rutasCercanas = feed.filter { !$0.id.isEmpty && $0.shape.count >= 2 && ids.insert($0.id).inserted }
            if let catalogo = catalogoRecuperado {
                self.rutasPorId = Dictionary(catalogo.map { ($0.id, $0) },
                                            uniquingKeysWith: { primera, _ in primera })
                if let posiciones = self.ultimasPosicionesReales { self.aplicarFlotaReal(posiciones) }
            }
            if fuenteConsulta == .simulated {
                self.flotaBuses = Self.busesDesde(self.rutasCercanas, ancla: punto)
                self.busesAnimados = self.flotaBuses
                self.busSeleccionado = nil
            }
            self.cargandoLineas = false
            self.lineasTask = nil
        }
    }

    func reintentarCatalogo() {
        let ancla = anclaLineas.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        recargarLineas(cercaDe: ancla, reintentar: true)
    }

    private func invalidarConsultaLineas() {
        lineasRevision = UUID()
        lineasTask?.cancel()
        lineasTask = nil
        anclaLineas = nil
        rutasCercanas = []
        cargandoLineas = false
        errorLineas = nil
    }

    /// Construye un bus animado por ruta del feed.
    private static func busesDesde(_ feed: [RutaGTFS],
                                   ancla: CLLocationCoordinate2D) -> [BusAnimado] {
        let n = max(feed.count, 1)
        return feed.enumerated().compactMap { index, ruta in
            // Sin geometría suficiente no hay nada que animar. Antes se caía a
            // un trazado de demostración, así que el mapa mostraba un bus
            // recorriendo una línea que no era la suya.
            let waypoints = decimarCoordenadas(ruta.shape, maximoPuntos: 240)
            guard waypoints.count >= 2 else { return nil }
            let acumulados = distanciasAcumuladas(waypoints)

            var bus = BusAnimado(
                id: "simulated-\(ruta.id)",
                linea: ruta.linea,
                rutaId: ruta.id,
                empresa: ruta.empresa,
                tipo: "Bus",
                variante: ruta.variante,
                minutosLlegada: max(1, 2 + index * max(1, ruta.headwayMin / n)),
                color: ruta.color,
                lat: waypoints[0].latitude,
                lon: waypoints[0].longitude,
                heading: 0,
                rutaCoordenadas: waypoints,
                acumulados: acumulados
            )

            // Nacimiento REPARTIDO por el corredor: se toma el tramo del
            // shape más cercano al punto consultado y cada vehículo arranca
            // de un punto distinto a su alrededor (±1.8 km), con dirección y
            // velocidad propias. Si varias líneas comparten avenida, quedan
            // escalonadas a lo largo de ella y no amontonadas en un punto.
            let idxAncla = waypointMasCercano(waypoints, a: ancla)
            let distanciaAnclaM = acumulados.isEmpty ? 0 : acumulados[idxAncla]
            // Fracciones de Fibonacci (0.618) escalonan los arranques de
            // forma determinista (~38% del rango entre vecinos); el jitter
            // aleatorio evita que dos recargas se vean idénticas.
            let fraccion = fmod(Double(index) * 0.6180339887, 1.0)
            let offsetM = fraccion * 3600 - 1800 + Double.random(in: -120...120)
            // Se envuelve módulo la longitud del recorrido (un vehículo en
            // otro ciclo de la línea) en vez de amontonar en los extremos.
            var d = distanciaAnclaM + offsetM
            let total = bus.longitudRutaM
            if total > 0 {
                d = d.truncatingRemainder(dividingBy: total)
                if d < 0 { d += total }
            }
            bus.distanciaM = d
            bus.velocidadMS = Double.random(in: 7...12)   // 25–43 km/h
            bus.isMovingForward = Bool.random()
            bus.actualizarPosicion()
            return bus
        }
    }

    /// Distancia acumulada (metros) de cada waypoint respecto al inicio.
    private static func distanciasAcumuladas(_ pts: [CLLocationCoordinate2D]) -> [Double] {
        guard !pts.isEmpty else { return [] }
        var acc: [Double] = [0]
        acc.reserveCapacity(pts.count)
        for j in 1..<pts.count {
            acc.append(acc[j - 1] + PolylineMatching.distanceMeters(pts[j - 1], pts[j]))
        }
        return acc
    }

    /// Índice del waypoint más cercano a un punto (distancia planar:
    /// solo sirve para elegir un índice, no para medir).
    private static func waypointMasCercano(_ puntos: [CLLocationCoordinate2D],
                                           a destino: CLLocationCoordinate2D) -> Int {
        var mejor = 0
        var mejorD = Double.greatestFiniteMagnitude
        for (i, p) in puntos.enumerated() {
            let d = (p.latitude - destino.latitude) * (p.latitude - destino.latitude)
                  + (p.longitude - destino.longitude) * (p.longitude - destino.longitude)
            if d < mejorD { mejorD = d; mejor = i }
        }
        return mejor
    }

    /// Reduce la densidad de un shape conservando el orden (perf del timer).
    private static func decimarCoordenadas(_ puntos: [CLLocationCoordinate2D],
                                           maximoPuntos: Int) -> [CLLocationCoordinate2D] {
        guard puntos.count > maximoPuntos else { return puntos }
        let paso = Double(puntos.count) / Double(maximoPuntos)
        var resultado: [CLLocationCoordinate2D] = []
        resultado.reserveCapacity(maximoPuntos)
        for j in 0..<maximoPuntos {
            resultado.append(puntos[min(Int(Double(j) * paso), puntos.count - 1)])
        }
        if let ultima = puntos.last, resultado.last?.latitude != ultima.latitude
                                                || resultado.last?.longitude != ultima.longitude {
            resultado.append(ultima)
        }
        return resultado
    }

    func detenerSimulacionBuses() {
        invalidarConsultaLineas()
        flotaRevision = UUID()
        busSimulationTask?.cancel()
        busSimulationTask = nil
        ultimoTickBuses = nil

        // El canal real se cierra con la pantalla. Sin esto, salir del mapa
        // dejaría la suscripción MQTT viva consumiendo batería y red.
        vehicleTrackingTask?.cancel()
        vehicleTrackingTask = nil
        vehicleProvider?.stop()
        vehicleProvider = nil
        ultimasPosicionesReales = nil
    }

    // MARK: - Flota real (canal MQTT)

    /// Arranca el consumo de posiciones observadas si hay broker configurado.
    ///
    /// Devuelve `true` si tomó el control de la flota, en cuyo caso el mapa no
    /// debe animar su propia simulación. Sin `MQTT_HOST`, `MQTT_USERNAME` y
    /// `MQTT_PASSWORD` no hay canal, y el mapa se comporta exactamente como
    /// antes: su flota animada sobre los shapes del feed.
    private func iniciarFlotaReal() -> Bool {
        guard vehicleProvider == nil else { return true }
        guard let provider = crearProveedorReal(), provider.source == .real else { return false }

        invalidarConsultaLineas()
        busSimulationTask?.cancel()
        busSimulationTask = nil
        ultimoTickBuses = nil
        let revision = UUID()
        flotaRevision = revision
        vehicleProvider = provider
        fuenteFlota = .real
        ultimasPosicionesReales = nil
        flotaBuses = []
        busesAnimados = []
        busSeleccionado = nil
        cargandoLineas = true
        recargarLineas(cercaDe: busquedaResultado?.coordenada)

        let repositorio = repositorioGTFS
        let revisionConsultaCatalogo = lineasRevision
        vehicleTrackingTask = Task { @MainActor [weak self] in
            // El catálogo completo, no solo las líneas cercanas al ancla: un
            // vehículo observado puede venir de cualquiera de las 102 rutas.
            let feed: [RutaGTFS]?
            do {
                feed = try await repositorio.cargarRutas()
            } catch {
                guard !Task.isCancelled, let self, self.flotaRevision == revision,
                      self.fuenteFlota == .real else { return }
                if self.lineasRevision == revisionConsultaCatalogo {
                    self.errorLineas = (error as? FalloCargaGTFS) ?? FalloCargaGTFS(detalle: error.localizedDescription)
                }
                // Las posiciones observadas conservan su canal incluso si
                // no tenemos metadatos; no sustituirlas por una flota demo.
                feed = nil
            }
            guard !Task.isCancelled, let self, self.flotaRevision == revision,
                  self.fuenteFlota == .real else { return }

            if let feed {
                self.rutasPorId = Dictionary(
                    feed.map { ($0.id, $0) },
                    uniquingKeysWith: { primera, _ in primera }
                )
            }

            provider.start()

            for await posiciones in provider.positions() {
                guard !Task.isCancelled, self.flotaRevision == revision,
                      self.fuenteFlota == .real else { break }
                self.aplicarFlotaReal(posiciones)
            }
        }

        return true
    }

    /// Sustituye la flota del mapa por las posiciones que llegan del broker.
    ///
    /// Solo cambia `lat`, `lon` y `heading` respecto a la flota simulada: el
    /// resto de campos se rellenan para que la tarjeta del mapa se dibuje
    /// igual, y `fuente` distingue el origen. La geometría va vacía a propósito
    /// —un vehículo observado no trae shape— y por eso `actualizarPosicion()`
    /// no lo mueve: su posición la fija cada mensaje.
    private func aplicarFlotaReal(_ posiciones: [VehiclePosition]) {
        guard fuenteFlota == .real else { return }
        ultimasPosicionesReales = posiciones
        let anclaETA: CLLocationCoordinate2D = {
            if let anclaLineas {
                return CLLocationCoordinate2D(
                    latitude: anclaLineas.lat,
                    longitude: anclaLineas.lon
                )
            }
            return busquedaResultado?.coordenada
                ?? GTFSRepository.coordenadaUTP
        }()

        flotaBuses = posiciones.map { posicion in
            let ruta = rutasPorId[posicion.routeId]
            let eta = ruta.flatMap {
                VehicleETAEstimator.minutes(
                    position: posicion,
                    route: $0,
                    target: anclaETA
                )
            }

            return BusAnimado(
                id: "real-\(posicion.id)",
                linea: posicion.linea,
                rutaId: posicion.routeId,
                empresa: ruta?.empresa ?? L.t("Empresa no disponible", "Carrier unavailable"),
                tipo: "Bus",
                variante: ruta?.variante ?? "",
                minutosLlegada: eta,
                color: ruta?.color ?? .appPrimary,
                lat: posicion.lat,
                lon: posicion.lon,
                heading: posicion.heading >= 0 ? posicion.heading : 0,
                rutaCoordenadas: [],
                acumulados: [],
                velocidadMS: posicion.speed >= 0 ? posicion.speed : 0,
                fuente: .real
            )
        }

        busesAnimados = flotaBuses

        // Si el vehículo abierto en el popup sigue existiendo, refrescarlo.
        if let seleccionado = busSeleccionado {
            busSeleccionado = flotaBuses.first { $0.id == seleccionado.id }
        }
    }

    private func actualizarPosicionBuses() {
        guard fuenteFlota == .simulated else { return }
        // dt real entre ticks: la velocidad no depende de la cadencia del
        // timer ni de eventuales tirones del hilo principal.
        let ahora = Date()
        let dt: Double = ultimoTickBuses.map { min(ahora.timeIntervalSince($0), 1.0) } ?? 0
        ultimoTickBuses = ahora

        var huboCambioVisible = false

        for i in flotaBuses.indices {
            var bus = flotaBuses[i]
            let totalM = bus.longitudRutaM
            guard totalM > 10 else { continue }

            // Avance en METROS reales: velocidad crucero propia × tiempo.
            let avance = bus.velocidadMS * dt
            var d = bus.distanciaM + (bus.isMovingForward ? avance : -avance)

            // Extremo del recorrido: el vehículo regresa por el mismo
            // corredor (ida y vuelta), sin saltos en el mapa.
            if d >= totalM {
                d = totalM
                bus.isMovingForward = false
            } else if d <= 0 {
                d = 0
                bus.isMovingForward = true
            }
            // Medir desde la última instantánea visible, no desde el tick
            // anterior: los pasos menores de 1,5 m también deben acumularse.
            if busesAnimados.indices.contains(i), busesAnimados[i].rutaId == bus.rutaId {
                let publicado = busesAnimados[i]
                if abs(d - publicado.distanciaM) >= Self.metrosMinimosParaPublicar
                    || bus.isMovingForward != publicado.isMovingForward {
                    huboCambioVisible = true
                }
            } else {
                huboCambioVisible = true
            }
            bus.distanciaM = d
            bus.actualizarPosicion()
            flotaBuses[i] = bus
        }

        // La simulación avanza siempre; el estado publicado —y con él el
        // redibujado del mapa— solo cuando el movimiento acumulado se nota.
        guard huboCambioVisible else { return }
        busesAnimados = flotaBuses
    }

    func recenterOnUser() {
        if let userCoord = userRealCoordinate {
            // Token: garantiza que la vista mueva la cámara aunque la
            // región ya tuviera ese valor (tras arrastrar el mapa, la
            // cámara local cambia pero `region` no se entera).
            recentrarToken += 1
            withAnimation(.spring(response: 0.5)) {
                region = MKCoordinateRegion(
                    center: userCoord,
                    span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
                )
            }
        } else {
            iniciarGPS()
        }
    }

    // Máximo de chips visibles en el panel del mapa (fijos + guardados).
    static let maxDestinos = 6

    /// Nombres en español de los chips fijos, para no duplicar un lugar
    /// guardado que ya es un chip. Se derivan de `DestinosFijos` (fuente única).
    private static let nombresFijosEstables: Set<String> = DestinosFijos.nombresEstables

    /// Chips FIJOS de la app: puntos de referencia conocidos de Trujillo.
    /// Casa/Trabajo ya no son fijos: si el usuario los guarda, aparecen solos.
    ///
    /// El dato (coordenadas, icono y clave señable) vive en `DestinosFijos`,
    /// compartido con el módulo de tracking: antes estaba escrito literalmente
    /// en los dos sitios. Aquí solo se adapta al tipo de esta pantalla.
    ///
    /// Calculada y no almacenada: el `label` sale en el idioma activo en cada
    /// lectura. Con el texto congelado en un `let`, cambiar de idioma dejaría
    /// los chips en el idioma anterior (son tres elementos: coste nulo).
    private var destinosFijos: [DestinoChip] {
        DestinosFijos.todos.map {
            DestinoChip(id: $0.id, label: $0.label, icon: $0.icono,
                        lat: $0.lat, lon: $0.lon, claveSenia: $0.claveSenia)
        }
    }

    /// Lugares guardados leídos de disco. Se cachean aquí para que `destinos`
    /// pueda ser calculada sin tocar `UserDefaults` en cada render.
    /// Es `@Published` para que refrescar la lista repinte los chips.
    @Published private var lugaresParaChips: [LugarGuardado] = []

    /// Chips visibles: fijos primero, luego los lugares que el usuario guardó
    /// en la pestaña Guardado (vía LugaresStore), hasta un total de 6.
    ///
    /// CALCULADA, no almacenada: la etiqueta de los chips fijos se resuelve en
    /// el idioma activo en cada lectura. Antes era un `@Published` que se
    /// construía una sola vez, así que al cambiar de idioma los chips se
    /// quedaban en el idioma anterior («Centro» en vez de «Downtown»).
    var destinos: [DestinoChip] {
        let guardados = lugaresParaChips
            .filter { lugar in
                // Solo lugares con coordenadas y que no dupliquen un chip fijo.
                guard lugar.coordinate != nil else { return false }
                return !Self.nombresFijosEstables.contains(lugar.nombre.lowercased())
            }
            .prefix(Self.maxDestinos - destinosFijos.count)
            .enumerated()
            .map { indice, lugar in
                DestinoChip(id: 100 + indice,
                            label: lugar.nombre,
                            icon: lugar.categoria.icono,
                            lat: lugar.lat ?? 0,
                            lon: lugar.lon ?? 0)
            }
        return destinosFijos + guardados
    }

    // MARK: - Búsqueda en tiempo real
    //
    // NO vuelve a asignar `textoBusqueda`: el TextField ya está enlazado a esa
    // propiedad. Reasignarla desde aquí creaba un doble camino sobre el mismo
    // estado y lanzaba consultas de autocompletado incluso cuando el texto lo
    // había puesto el propio código (al elegir un chip o un resultado). El
    // filtro por foco lo aplica la vista, que es quien lo conoce.
    func actualizarTextoBusqueda(_ nuevoTexto: String) {
        let t = nuevoTexto.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            sugerenciasBusqueda = []
            completer.queryFragment = ""
        } else {
            completer.queryFragment = t
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async {
            self.sugerenciasBusqueda = completer.results
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        #if DEBUG
        print("[MapaViewModel] MKLocalSearchCompleter error: \(error.localizedDescription)")
        #endif
    }

    // MARK: - Selección y Búsqueda de Destino
    func seleccionar(destino: DestinoChip) {
        invalidarSeleccionAnterior()
        sugerenciasBusqueda = []
        destinoSeleccionado = destino
        let destCoord = CLLocationCoordinate2D(latitude: destino.lat, longitude: destino.lon)
        busquedaResultado = (titulo: destino.label, coordenada: destCoord)
        textoBusqueda = destino.label

        withAnimation(.spring(response: 0.5)) {
            region = MKCoordinateRegion(
                center: destCoord,
                span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
            )
        }
        destinoFocusTick += 1
        calcularRutaHacia(destCoord)
        recargarLineas(cercaDe: destCoord)
    }

    func seleccionarSugerencia(_ completion: MKLocalSearchCompletion) {
        invalidarSeleccionAnterior()
        let revision = selectionRevision
        sugerenciasBusqueda = []
        textoBusqueda = completion.title
        buscando = true

        let searchRequest = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: searchRequest)
        activeSearch = search

        search.start { [weak self] response, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard self.selectionRevision == revision else { return }
                self.activeSearch = nil
                self.buscando = false
                if let mapItem = response?.mapItems.first {
                    self.seleccionarLugar(
                        titulo: mapItem.name ?? completion.title,
                        coordenada: mapItem.placemark.coordinate
                    )
                }
            }
        }
    }

    func buscarTexto(_ texto: String) {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        sugerenciasBusqueda = []

        if let match = destinos.first(where: {
            $0.label.compare(t, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            seleccionar(destino: match)
            return
        }

        invalidarSeleccionAnterior()
        let revision = selectionRevision
        buscando = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = t
        request.region = region

        let search = MKLocalSearch(request: request)
        activeSearch = search
        search.start { [weak self] response, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard self.selectionRevision == revision else { return }
                self.activeSearch = nil
                self.buscando = false
                if let mapItem = response?.mapItems.first {
                    self.seleccionarLugar(
                        titulo: mapItem.name ?? t,
                        coordenada: mapItem.placemark.coordinate
                    )
                }
            }
        }
    }

    func seleccionarLugar(titulo: String, coordenada: CLLocationCoordinate2D) {
        invalidarSeleccionAnterior()
        textoBusqueda = titulo
        destinoSeleccionado = nil
        busquedaResultado = (titulo: titulo, coordenada: coordenada)

        withAnimation(.spring(response: 0.5)) {
            region = MKCoordinateRegion(
                center: coordenada,
                span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
            )
        }
        destinoFocusTick += 1
        calcularRutaHacia(coordenada)
        recargarLineas(cercaDe: coordenada)
    }

    // MARK: - Caminata + recorrido GTFS + caminata al destino
    func calcularRutaHacia(_ destinoCoord: CLLocationCoordinate2D) {
        routeTask?.cancel()
        let revision = UUID()
        routeRevision = revision
        itinerario = nil
        routePolyline = nil
        etaMinutos = nil
        distanciaKm = nil
        mensajeRuta = nil
        calculandoItinerario = false
        guard let origen = userRealCoordinate else {
            mensajeRuta = L.t("Necesitamos tu ubicación para encontrar dónde subir. Activa el GPS y permite el acceso a la ubicación.",
                              "We need your location to find a boarding stop. Enable GPS and allow location access.")
            return
        }

        calculandoItinerario = true
        routeTask = Task { @MainActor [weak self] in
            let feed: [RutaGTFS]
            do {
                feed = try await GTFSRepository.shared.cargarRutas(reintentar: true)
            } catch {
                guard !Task.isCancelled, let self, self.routeRevision == revision else { return }
                self.mensajeRuta = ((error as? FalloCargaGTFS)
                    ?? FalloCargaGTFS(detalle: error.localizedDescription)).mensajeUsuario
                self.calculandoItinerario = false
                return
            }
            guard let self, !Task.isCancelled, self.routeRevision == revision else { return }
            defer {
                if self.routeRevision == revision { self.calculandoItinerario = false }
            }
            // Misma política del Tracking: hasta `radioBusquedaRuta` a pie en
            // cada extremo.
            let radio = Self.radioBusquedaRuta
            let candidates = await TransitPlanner.shared.candidates(in: feed, origin: origen,
                destination: destinoCoord, radius: radio)
            guard !Task.isCancelled, self.routeRevision == revision else { return }
            for candidate in candidates.prefix(4) {
                let plan = await candidate.withWalkingDirections(using: self.routeService)
                guard !Task.isCancelled, self.routeRevision == revision else { return }
                guard plan.walkToBoardMeters <= radio, plan.walkToDestinationMeters <= radio, plan.walkingWithinTransferLimit else { continue }
                self.itinerario = plan
                self.routePolyline = MKPolyline(coordinates: plan.coordinates, count: plan.coordinates.count)
                self.etaMinutos = max(1, Int(ceil(plan.totalSeconds / 60)))
                self.distanciaKm = (plan.walkToBoardMeters + plan.busMeters + plan.transferWalkMeters + plan.walkToDestinationMeters) / 1000
                self.itinerarioFocusTick += 1
                return
            }
            self.mensajeRuta = L.t("No encontramos una ruta directa ni con un transbordo con paraderos a menos de \(Int(radio)) m de ambos extremos. Prueba otro destino.",
                                   "No direct or one-transfer route has stops within \(Int(radio)) m of both ends. Try another destination.")
        }
    }

    func limpiar() {
        invalidarSeleccionAnterior()
        textoBusqueda = ""
        destinoSeleccionado = nil
        busquedaResultado = nil
        sugerenciasBusqueda = []
        completer.queryFragment = ""
        routePolyline = nil
        etaMinutos = nil
        distanciaKm = nil
        // Sin destino: el panel vuelve a las líneas del campus.
        recargarLineas(cercaDe: nil)

        withAnimation(.spring(response: 0.5)) {
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: -8.098247879173792, longitude: -79.03818104755645),
                span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035)
            )
        }
    }
}
