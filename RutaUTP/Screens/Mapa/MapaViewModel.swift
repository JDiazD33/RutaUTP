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
struct BusAnimado: Identifiable, Equatable {
    let id: Int
    let linea: String        // "10", "4"
    let rutaId: String       // route_id GTFS: enlaza con el detalle de RutasView
    let empresa: String      // "El Cortijo", "Salaverry"
    let tipo: String          // "Micro", "Combi"
    let placa: String         // "T1B-721"
    let minutosLlegada: Int   // 4, 12
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
        heading = atan2(b.longitude - a.longitude, b.latitude - a.latitude) * 180 / .pi
        tramoActual = i
    }

    static func == (lhs: BusAnimado, rhs: BusAnimado) -> Bool {
        lhs.id == rhs.id &&
        lhs.lat == rhs.lat &&
        lhs.lon == rhs.lon &&
        lhs.heading == rhs.heading
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
    @Published var busesAnimados: [BusAnimado] = []
    @Published var busSeleccionado: BusAnimado? = nil
    /// True mientras se consulta el feed por las líneas del punto actual.
    @Published private(set) var cargandoLineas: Bool = false
    private var busSimulationTimer: Timer?
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
        let nombresFijos = Set(destinosFijos.map { $0.label.lowercased() })

        let guardados = LugaresStore.cargar()
            .filter { lugar in
                // Solo lugares con coordenadas y que no dupliquen un chip fijo.
                guard lugar.coordinate != nil else { return false }
                return !nombresFijos.contains(lugar.nombre.lowercased())
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

        destinos = destinosFijos + guardados

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
        locationService.stopUpdating()
        detenerSimulacionBuses()
    }

    // MARK: - Ubicación GPS Real
    func iniciarGPS() {
        locationTask?.cancel()
        locationTask = Task { @MainActor in
            let status = await locationService.requestPermission()
            if status.isAuthorized {
                locationService.startUpdating()
                for await location in locationService.currentLocation() {
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
        // Sin destino: líneas que pasan por el campus (comportamiento
        // original del panel "Transportes cercanos").
        recargarLineas(cercaDe: nil)

        guard busSimulationTimer == nil else { return }
        ultimoTickBuses = nil
        busSimulationTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
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

        cargandoLineas = true
        Task { @MainActor [weak self] in
            // 400 m cubre "pasa por la puerta"; si el punto quedó algo
            // alejado del recorrido se amplía a 800 m antes de declarar
            // que no pasa ninguna línea.
            var feed = await GTFSRepository.shared.rutasQuePasanPor(punto, radioMetros: 400)
            if feed.isEmpty {
                feed = await GTFSRepository.shared.rutasQuePasanPor(punto, radioMetros: 800)
            }
            // El usuario pudo cambiar de destino mientras consultaba.
            guard let self, self.anclaLineas?.lat == clave.lat,
                  self.anclaLineas?.lon == clave.lon else { return }

            self.busesAnimados = Self.busesDesde(feed, ancla: punto)
            self.busSeleccionado = nil
            self.cargandoLineas = false
        }
    }

    /// Construye un bus animado por ruta del feed.
    private static func busesDesde(_ feed: [RutaGTFS],
                                   ancla: CLLocationCoordinate2D) -> [BusAnimado] {
        let n = max(feed.count, 1)
        return feed.enumerated().map { index, ruta in
            var waypoints = decimarCoordenadas(ruta.shape, maximoPuntos: 240)
            if waypoints.count < 2 { waypoints = RutaCoordenadas.linea10 }
            let acumulados = distanciasAcumuladas(waypoints)

            var bus = BusAnimado(
                id: index + 1,
                linea: ruta.linea,
                rutaId: ruta.id,
                empresa: ruta.empresa,
                tipo: "Bus",
                placa: ruta.variante.isEmpty ? "S/D" : "Ramal \(ruta.variante)",
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
        busSimulationTimer?.invalidate()
        busSimulationTimer = nil
        ultimoTickBuses = nil
    }

    private func actualizarPosicionBuses() {
        // dt real entre ticks: la velocidad no depende de la cadencia del
        // timer ni de eventuales tirones del hilo principal.
        let ahora = Date()
        let dt: Double = ultimoTickBuses.map { min(ahora.timeIntervalSince($0), 1.0) } ?? 0
        ultimoTickBuses = ahora

        for i in busesAnimados.indices {
            var bus = busesAnimados[i]
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
            bus.distanciaM = d
            bus.actualizarPosicion()
            busesAnimados[i] = bus
        }
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

    /// Chips FIJOS de la app: puntos de referencia conocidos de Trujillo.
    /// Casa/Trabajo ya no son fijos: si el usuario los guarda, aparecen solos.
    private let destinosFijos: [DestinoChip] = [
        DestinoChip(id: 1, label: L.signable("mapa.destino.utp", "UTP", "UTP"), icon: "graduationcap.fill", lat: -8.098247879173792, lon: -79.03818104755645, claveSenia: "mapa.destino.utp"),
        DestinoChip(id: 2, label: L.signable("mapa.destino.centro", "Centro", "Downtown"), icon: "building.2.fill", lat: -8.1090, lon: -79.0270, claveSenia: "mapa.destino.centro"),
        DestinoChip(id: 3, label: L.signable("mapa.destino.huanchaco", "Huanchaco", "Huanchaco"), icon: "water.waves", lat: -8.0825, lon: -79.1197, claveSenia: "mapa.destino.huanchaco")
    ]

    /// Chips visibles: fijos primero, luego los lugares que el usuario guardó
    /// en la pestaña Guardado (vía LugaresStore), hasta un total de 6.
    @Published private(set) var destinos: [DestinoChip] = []

    // MARK: - Búsqueda en tiempo real
    func actualizarTextoBusqueda(_ nuevoTexto: String) {
        textoBusqueda = nuevoTexto
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



