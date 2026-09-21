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
/// usa la velocidad observada. Si el vehículo está detenido o la velocidad no
/// está disponible, cae a la velocidad media programada de la ruta. No devuelve
/// ETA cuando vehículo/destino están fuera del recorrido o la unidad se aleja.
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
            let targetMatch = PolylineMatching.match(
                point: target,
                on: route.shape,
                thresholdMeters: 800
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
        if position.heading >= 0, forwardHeading >= 0 {
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

        if let movingForward {
            if isCircular {
                if movingForward, progressDelta < 0 { progressDelta += 1 }
                if !movingForward, progressDelta > 0 { progressDelta -= 1 }
            } else {
                guard movingForward ? progressDelta >= 0 : progressDelta <= 0 else {
                    return nil
                }
            }
        }

        let remainingMeters = abs(progressDelta) * routeLength
        guard remainingMeters.isFinite else { return nil }

        let scheduledSpeed: Double = {
            guard route.duracionMin > 0 else { return 7 }
            return routeLength / (Double(route.duracionMin) * 60)
        }()
        let observedSpeed = position.speed >= 2
            ? position.speed
            : scheduledSpeed
        let effectiveSpeed = min(max(observedSpeed, 3), 15)

        let estimate = Int(ceil(remainingMeters / effectiveSpeed / 60))
        return min(max(estimate, 1), 120)
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
    @Published var busSeleccionado: BusAnimado? = nil
    @Published private(set) var fuenteFlota: VehicleTrackingSource = .simulated
    /// Movimiento mínimo (m) para publicar una nueva instantánea. A 20 Hz cada
    /// tick avanza unos centímetros, así que casi todas las publicaciones no
    /// cambiaban nada visible pero rehacían el cuerpo de `MapaView` completo
    /// —mapa, anotaciones, buscador y panel de tarjetas—. Con este umbral se
    /// publica ~7 veces por segundo a velocidad urbana.
    private static let metrosMinimosParaPublicar: Double = 1.5
    /// True mientras se consulta el feed por las líneas del punto actual.
    @Published private(set) var cargandoLineas: Bool = false
    private var busSimulationTask: Task<Void, Never>?
    private var lineasTask: Task<Void, Never>?

    /// Proveedor de posiciones vehiculares reales. Solo se crea cuando hay
    /// configuración de broker; sin ella el mapa sigue con su propia flota.
    private var vehicleProvider: VehicleTrackingProviding?

    /// Consumo del stream de posiciones del proveedor.
    private var vehicleTrackingTask: Task<Void, Never>?

    /// Catálogo GTFS indexado por `route_id`, para resolver empresa, color y
    /// variante de un vehículo real. `VehiclePosition` viaja con `routeId`,
    /// que es único; `linea` no lo es (dos ramales la comparten).
    private var rutasPorId: [String: RutaGTFS] = [:]
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
    private let routeService: RouteCalculationService
    private let completer = MKLocalSearchCompleter()
    private var locationTask: Task<Void, Never>?

    init(
        locationService: LocationServiceProtocol = LocationService(),
        routeService: RouteCalculationService = RouteCalculationService()
    ) {
        self.locationService = locationService
        self.routeService = routeService
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
        lineasTask?.cancel()
        lineasTask = nil
        anclaLineas = nil
        cargandoLineas = false
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
        // Esta comprobación va ANTES de `recargarLineas`, y no después: esa
        // función lanza una tarea que reescribe `busesAnimados` con la flota
        // simulada, así que si arrancara también, su resultado podría llegar
        // después del primer mensaje del broker y pisar los vehículos reales.
        if iniciarFlotaReal() { return }

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
    /// El contador del panel ("N líneas operando ahora") pasa a reflejar
    /// cuántas líneas del feed REALMENTE pasan por ese punto.
    func recargarLineas(cercaDe ancla: CLLocationCoordinate2D?) {
        let punto = ancla ?? GTFSRepository.coordenadaUTP
        let clave = (lat: punto.latitude, lon: punto.longitude)
        if let previa = anclaLineas,
           abs(previa.lat - clave.lat) < 1e-9,
           abs(previa.lon - clave.lon) < 1e-9 { return }
        anclaLineas = clave

        lineasTask?.cancel()
        cargandoLineas = true
        lineasTask = Task { @MainActor [weak self] in
            // 400 m cubre "pasa por la puerta"; si el punto quedó algo
            // alejado del recorrido se amplía a 800 m antes de declarar
            // que no pasa ninguna línea.
            var feed = await GTFSRepository.shared.rutasQuePasanPor(punto, radioMetros: 400)
            guard !Task.isCancelled else { return }
            if feed.isEmpty {
                feed = await GTFSRepository.shared.rutasQuePasanPor(punto, radioMetros: 800)
            }
            // El usuario pudo cambiar de destino mientras consultaba.
            guard !Task.isCancelled, let self, self.anclaLineas?.lat == clave.lat,
                  self.anclaLineas?.lon == clave.lon else { return }

            self.flotaBuses = Self.busesDesde(feed, ancla: punto)
            self.busesAnimados = self.flotaBuses
            self.busSeleccionado = nil
            self.cargandoLineas = false
            self.lineasTask = nil
        }
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
        busSimulationTask?.cancel()
        busSimulationTask = nil
        ultimoTickBuses = nil

        // El canal real se cierra con la pantalla. Sin esto, salir del mapa
        // dejaría la suscripción MQTT viva consumiendo batería y red.
        vehicleTrackingTask?.cancel()
        vehicleTrackingTask = nil
        vehicleProvider?.stop()
        vehicleProvider = nil
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
        guard MQTTConfiguration.fromEnvironment() != nil else { return false }

        let provider = TrackingProviderFactory.makeDefault()
        guard provider.source == .real else { return false }

        vehicleProvider = provider
        fuenteFlota = .real
        cargandoLineas = true

        vehicleTrackingTask = Task { @MainActor [weak self] in
            // El catálogo completo, no solo las líneas cercanas al ancla: un
            // vehículo observado puede venir de cualquiera de las 102 rutas.
            let feed = await GTFSRepository.shared.rutas()
            guard !Task.isCancelled, let self else { return }

            self.rutasPorId = Dictionary(
                feed.map { ($0.id, $0) },
                uniquingKeysWith: { primera, _ in primera }
            )

            provider.start()

            for await posiciones in provider.positions() {
                guard !Task.isCancelled else { break }
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
        cargandoLineas = false

        // Si el vehículo abierto en el popup sigue existiendo, refrescarlo.
        if let seleccionado = busSeleccionado {
            busSeleccionado = flotaBuses.first { $0.id == seleccionado.id }
        }
    }

    private func actualizarPosicionBuses() {
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
            let feed = await GTFSRepository.shared.rutas()
            guard let self, !Task.isCancelled, self.routeRevision == revision else { return }
            defer {
                if self.routeRevision == revision { self.calculandoItinerario = false }
            }
            // Misma política del Tracking: hasta 800 m a pie en cada extremo.
            let candidates = await TransitPlanner.shared.candidates(in: feed, origin: origen,
                destination: destinoCoord, radius: 800)
            guard !Task.isCancelled, self.routeRevision == revision else { return }
            for candidate in candidates.prefix(4) {
                let plan = await candidate.withWalkingDirections(using: self.routeService)
                guard !Task.isCancelled, self.routeRevision == revision else { return }
                guard plan.walkToBoardMeters <= 800, plan.walkToDestinationMeters <= 800 else { continue }
                self.itinerario = plan
                self.routePolyline = MKPolyline(coordinates: plan.coordinates, count: plan.coordinates.count)
                self.etaMinutos = max(1, Int(ceil(plan.totalSeconds / 60)))
                self.distanciaKm = (plan.walkToBoardMeters + plan.busMeters + plan.walkToDestinationMeters) / 1000
                self.itinerarioFocusTick += 1
                return
            }
            self.mensajeRuta = L.t("No encontramos una línea directa con paraderos a menos de 800 m de ambos extremos. Prueba otro destino.",
                                   "No direct line has stops within 800 m of both ends. Try another destination.")
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
