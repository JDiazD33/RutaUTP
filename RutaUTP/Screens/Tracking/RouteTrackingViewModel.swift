//
//  RouteTrackingViewModel.swift
//  RutaUTP
//
//  ViewModel del Tracking Demo: banco de pruebas del módulo de tracking.
//  Integra TODO el stack actual:
//   - Ruteo con RUTAS REALES primero: línea del feed GTFS de Trujillo cuyo
//     recorrido pase por origen y destino (shape del tramo + ritmo real de
//     la línea según stop_times). Respaldo: RouteCalculationService
//     (transit → automobile → trazo directo) con aviso de "aproximada".
//   - El modo demo simula el avance A RITMO REAL de la ruta activa
//     (m/s derivados del ETA), con multiplicador 1× / 3× / 10×.
//   - Snap-to-road y progreso con PolylineMatching (mismos umbrales de
//     NavegacionRutaView: 60 m, anti-jitter de progreso, llegada < 120 m).
//   - Máquina de estados de navegación igual a NavegacionRutaView
//     (esperandoGPS / sinPermiso / listo / enRuta / fueraDeRuta /
//     cercaDestino / finalizado).
//   - Modo demo: simula el avance a lo largo de la ruta calculada
//     (mismo enfoque que NavegacionRutaView.modoDemo) para probar sin
//     moverse del sitio — imprescindible en simulador.
//   - Posiciones de vehículos vía VehicleTrackingProviding
//     (SimulatedTrackingProvider) con badge de fuente (DEMO / EN VIVO).
//   - Registro del viaje en un TripSession (puntos recorridos) listo para
//     el backend futuro.
//
//  Recibe `LocationServiceProtocol` por init para testear con mocks.
//

import Foundation
import Combine
import CoreLocation
import MapKit

@MainActor
final class RouteTrackingViewModel: ObservableObject {

    // MARK: - Destinos del demo (mismos chips fijos del Mapa)

    struct DestinoDemo: Identifiable, Equatable {
        let id: Int
        let label: String
        let icon: String
        let coordinate: CLLocationCoordinate2D

        static func == (lhs: DestinoDemo, rhs: DestinoDemo) -> Bool { lhs.id == rhs.id }
    }

    /// Propiedad de instancia (no `static`): se evalúa al crear el VM, que
    /// RootView reconstruye al cambiar el idioma (.id(codigo)), así el label
    /// sale siempre en el idioma activo. Mismas claves señables del Mapa.
    let destinos: [DestinoDemo] = [
        DestinoDemo(id: 1, label: L.signable("mapa.destino.utp", "UTP", "UTP"), icon: "graduationcap.fill",
                    coordinate: CLLocationCoordinate2D(latitude: -8.098247879173792, longitude: -79.03818104755645)),
        DestinoDemo(id: 2, label: L.signable("mapa.destino.centro", "Centro", "Downtown"), icon: "building.2.fill",
                    coordinate: CLLocationCoordinate2D(latitude: -8.1090, longitude: -79.0270)),
        DestinoDemo(id: 3, label: L.signable("mapa.destino.huanchaco", "Huanchaco", "Huanchaco"), icon: "water.waves",
                    coordinate: CLLocationCoordinate2D(latitude: -8.0825, longitude: -79.1197))
    ]

    // MARK: - Estado de navegación (igual a NavegacionRutaView)

    enum Estado: Equatable {
        case esperandoGPS
        case sinPermiso
        case listo                    // GPS OK, sin viaje iniciado
        case enRuta
        case fueraDeRuta(metros: Double)
        case cercaDestino
        case finalizado
    }

    // MARK: - Salida expuesta a la vista

    @Published private(set) var estado: Estado = .esperandoGPS
    @Published private(set) var posicion: CLLocationCoordinate2D?
    /// Se incrementa en cada fix; la vista lo observa para seguir la cámara
    /// (CLLocationCoordinate2D no conforma Equatable para .onChange).
    @Published private(set) var posicionTick: Int = 0
    @Published private(set) var progreso: Double = 0
    @Published private(set) var distanciaRestanteM: Double = 0
    @Published private(set) var etaTotalSeg: TimeInterval?      // de la ruta calculada
    @Published private(set) var recalculando: Bool = false
    @Published private(set) var tripInProgress: Bool = false
    @Published private(set) var destinoSeleccionado: DestinoDemo? = nil
    @Published private(set) var errorMessage: String? = nil
    @Published var authStatus: CLAuthorizationStatus = .notDetermined

    /// Modo demo: simula el avance por la ruta calculada (ignora el GPS real).
    @Published var modoDemo: Bool = false {
        didSet { modoDemo ? iniciarDemoSimulado() : detenerDemoSimulado() }
    }

    // Vehículos en el mapa vía provider (badge DEMO / EN VIVO en la UI).
    @Published private(set) var vehiculos: [VehiclePosition] = []
    @Published private(set) var fuenteVehiculos: VehicleTrackingSource = .simulated

    // Sesión del viaje en curso (modelo de datos del módulo, listo para backend).
    @Published private(set) var sesion: TripSession?

    @Published private(set) var routePolyline: MKPolyline?
    /// Ruta dividida por el avance: tramo recorrido (tenue) y restante (vivo).
    @Published private(set) var rutaRecorrida: MKPolyline? = nil
    @Published private(set) var rutaRestante: MKPolyline? = nil
    /// True cuando MKDirections no respondió y la ruta es un trazo directo.
    @Published private(set) var rutaAproximada: Bool = false
    /// Línea REAL del feed GTFS usada para el viaje (nil = MapKit/respaldo).
    /// El shape del tramo y el ritmo de simulación salen de esta línea.
    @Published private(set) var rutaGTFS: RutaGTFS?
    /// True mientras corre el pipeline de ruteo (spinner del botón Iniciar).
    @Published private(set) var calculandoRuta: Bool = false
    /// Rumbo actual en grados (-1 desconocido): orienta la cámara y el marcador.
    @Published private(set) var rumbo: Double = -1
    /// Multiplicador del modo demo (1× / 2× / 4×).
    @Published var velocidadDemo: Double = 1
    /// Velocidad estimada por vehículo (m/s), calculada entre snapshots del
    /// provider para el popup en vivo.
    @Published private(set) var velocidadesVehiculos: [String: Double] = [:]

    /// Métricas del viaje terminado (las muestra la card de llegada).
    struct ResumenViaje: Equatable {
        let duracionS: TimeInterval
        let distanciaM: Double
        let puntos: Int
        let velocidadKmh: Double
    }
    @Published private(set) var resumen: ResumenViaje?

    // MARK: - Dependencias

    private let locationService: LocationServiceProtocol
    private let routeService: RouteCalculationService
    private let vehicleProvider: VehicleTrackingProviding

    // Shape decimado para matching + distancias acumuladas (como NavegacionRutaView).
    private var polyCoords: [CLLocationCoordinate2D] = []
    private var distanciasAcumuladas: [Double] = []
    private var distanciaTotalM: Double = 0

    private var consecutiveOffRoute: Int = 0
    private var locationTask: Task<Void, Never>?
    private var vehiculoTask: Task<Void, Never>?
    private var demoTimer: Timer?
    private var demoProgreso: Double = 0
    private var ultimoFraccionPolyline: Double = 0
    /// Ritmo real de simulación en m/s (de la línea GTFS o del ETA de MapKit).
    private var velocidadSimMs: Double = 6.0
    private var snapshotVehiculosAnterior: [String: (coord: CLLocationCoordinate2D, t: TimeInterval)] = [:]

    private var authCancellable: AnyCancellable?

    // MARK: - Init

    init(locationService: LocationServiceProtocol = LocationService(),
         routeService: RouteCalculationService = RouteCalculationService(),
         vehicleProvider: VehicleTrackingProviding = SimulatedTrackingProvider()) {
        self.locationService = locationService
        self.routeService = routeService
        self.vehicleProvider = vehicleProvider
        self.fuenteVehiculos = vehicleProvider.source

        authCancellable = locationService.authorizationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.authStatus = status
            }
    }

    deinit {
        locationTask?.cancel()
        vehiculoTask?.cancel()
        vehicleProvider.stop()
        locationService.stopUpdating()
    }

    // MARK: - Permisos y arranque

    func requestPermissionAndStart() async {
        let status = await locationService.requestPermission()
        authStatus = status
        if status.isAuthorized {
            startObservingLocation()
            locationService.startUpdating()
        } else {
            estado = .sinPermiso
            errorMessage = L.t("Permiso de ubicación denegado. Actívalo en Ajustes para usar el tracking.",
                               "Location permission denied. Enable it in Settings to use tracking.")
        }
        iniciarVehiculos()
    }

    private func startObservingLocation() {
        locationTask?.cancel()
        locationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await location in self.locationService.currentLocation() {
                guard !Task.isCancelled else { break }
                if self.modoDemo { continue }   // el demo simulado toma el control
                self.procesar(coordenada: location.coordinate, rumbo: location.course)
            }
        }
    }

    // MARK: - Procesamiento de fixes (mismos umbrales de NavegacionRutaView)

    private func procesar(coordenada: CLLocationCoordinate2D, rumbo: Double) {
        posicion = coordenada
        posicionTick += 1
        self.rumbo = rumbo

        // Sin viaje en curso: GPS listo, a la espera de destino.
        guard tripInProgress, !polyCoords.isEmpty else {
            if estado == .esperandoGPS || estado == .sinPermiso { estado = .listo }
            return
        }

        guard let match = PolylineMatching.match(point: coordenada, on: polyCoords,
                                                 thresholdMeters: 60) else { return }

        // Anti-jitter: el progreso no retrocede por saltos pequeños de GPS.
        let nuevo = match.progressFraction
        if nuevo >= progreso || (progreso - nuevo) > 0.03 {
            progreso = nuevo
        }

        distanciaRestanteM = max(0, distanciaTotalM * (1 - progreso))
        refrescarPolylinesProgreso()

        // Recalculo por desvío sostenido (misma política del módulo).
        if match.isOnRoute {
            consecutiveOffRoute = 0
        } else {
            consecutiveOffRoute += 1
        }
        if PolylineMatching.shouldRecalculate(lastMatch: match,
                                              consecutiveOffRouteCount: consecutiveOffRoute,
                                              thresholdCount: 3),
           !recalculando {
            Task { await recalcular(desde: coordenada) }
        }

        if progreso >= 0.985 || distanciaRestanteM < 120 {
            estado = progreso >= 0.985 ? .finalizado : .cercaDestino
        } else if !match.isOnRoute {
            estado = .fueraDeRuta(metros: match.distanceToRoute)
        } else {
            estado = .enRuta
        }

        // Llegó: cerrar la sesión (una sola vez) y frenar la simulación demo
        // para no seguir tick-eando sobre el destino.
        if estado == .finalizado {
            if sesion?.estado != .completed {
                finalizarSesion(estado: .completed)
            }
            if modoDemo { modoDemo = false }
        }

        registrarPunto(coordenada, rumbo: rumbo)
    }

    // MARK: - Inicio de viaje

    func iniciar(destino: DestinoDemo) async {
        guard !calculandoRuta else { return }
        guard authStatus.isAuthorized else {
            errorMessage = L.t("Sin permiso de ubicación. Concédelo en Ajustes.",
                               "No location permission. Grant it in Settings.")
            return
        }
        guard let origen = posicion else {
            errorMessage = L.t("Aún no tenemos tu ubicación. Espera unos segundos.",
                               "We don't have your location yet. Wait a few seconds.")
            return
        }

        errorMessage = nil
        destinoSeleccionado = destino
        tripInProgress = true
        progreso = 0
        consecutiveOffRoute = 0
        resumen = nil

        sesion = TripSession(
            linea: destino.label,
            empresa: "Tracking Demo",
            origen: TrackingPoint(lat: origen.latitude, lon: origen.longitude),
            destino: TrackingPoint(lat: destino.coordinate.latitude, lon: destino.coordinate.longitude),
            estado: .inProgress,
            startedAt: Date().timeIntervalSince1970
        )

        // Demo: reubica los vehículos simulados a mitad del recorrido para
        // cruzarse con ellos durante el viaje.
        if let simulado = vehicleProvider as? SimulatedTrackingProvider {
            simulado.setCenter(lat: (origen.latitude + destino.coordinate.latitude) / 2,
                               lon: (origen.longitude + destino.coordinate.longitude) / 2)
        }

        calculandoRuta = true
        defer { calculandoRuta = false }
        await calcularRuta(desde: origen, hacia: destino.coordinate)

        if routePolyline != nil {
            estado = .enRuta
            distanciaRestanteM = distanciaTotalM
        } else {
            tripInProgress = false
            destinoSeleccionado = nil
            estado = .listo
        }
    }

    /// Recalcular desde la posición actual hacia el destino guardado.
    private func recalcular(desde origen: CLLocationCoordinate2D) async {
        guard let destino = destinoSeleccionado else { return }
        recalculando = true
        sesion?.estado = .recalculating

        await calcularRuta(desde: origen, hacia: destino.coordinate)

        recalculando = false
        consecutiveOffRoute = 0
        if sesion?.estado == .recalculating { sesion?.estado = .inProgress }
    }

    /// Pipeline de ruteo: 1) línea REAL del feed GTFS (micros de Trujillo)
    /// que pase por origen y destino → 2) transit → 3) automobile →
    /// 4) trazo directo de respaldo.
    private func calcularRuta(desde origen: CLLocationCoordinate2D,
                              hacia destino: CLLocationCoordinate2D) async {
        // 1) Ruta real: el shape del micro entre tu posición y el destino,
        //    con el ritmo real de la línea (stop_times del GTFS).
        if let real = await rutaGTFSDesde(origen, hacia: destino) {
            rutaGTFS = real.ruta
            rutaAproximada = false
            routePolyline = MKPolyline(coordinates: real.coords, count: real.coords.count)
            etaTotalSeg = real.segundos
            instalarShape(real.coords)
            return
        }
        rutaGTFS = nil

        var ruta: CalculatedRoute? = nil
        do {
            ruta = try await routeService.calculateRoute(from: origen, to: destino,
                                                         transportType: .transit)
        } catch {
            #if DEBUG
            print("[TrackingDemo] transit falló: \(error.localizedDescription)")
            #endif
        }
        if ruta == nil {
            do {
                ruta = try await routeService.calculateRoute(from: origen, to: destino,
                                                             transportType: .automobile)
            } catch {
                #if DEBUG
                print("[TrackingDemo] automobile falló: \(error.localizedDescription)")
                #endif
            }
        }

        if let ruta {
            rutaAproximada = false
            routePolyline = ruta.polyline
            etaTotalSeg = ruta.expectedTravelTime
            instalarShape(PolylineMatching.coordinates(from: ruta.polyline))
        } else {
            // Sin respuesta de MKDirections (sin red, sin cobertura): trazo
            // directo para que SIEMPRE haya ruta visible, igual que el Mapa.
            #if DEBUG
            print("[TrackingDemo] sin respuesta de MKDirections → trazo directo")
            #endif
            rutaAproximada = true
            routePolyline = MKPolyline(coordinates: [origen, destino], count: 2)
            let metros = PolylineMatching.distanceMeters(origen, destino)
            etaTotalSeg = metros / 83.0 * 60   // ~5 km/h, mismo criterio del Mapa
            instalarShape([origen, destino])
        }
    }

    /// Busca una línea real del GTFS cuyo recorrido pase cerca del origen Y
    /// del destino, y arma el tramo del shape entre ambos puntos (con una
    /// piernita a pie al inicio y al final). Prefiere líneas cuyo sentido
    /// (orden del shape) vaya del origen hacia el destino.
    private func rutaGTFSDesde(_ origen: CLLocationCoordinate2D,
                               hacia destino: CLLocationCoordinate2D)
        async -> (ruta: RutaGTFS, coords: [CLLocationCoordinate2D], segundos: TimeInterval)? {
        let porDestino = await GTFSRepository.shared.rutasQuePasanPor(destino, radioMetros: 450)
        guard !porDestino.isEmpty else { return nil }

        // Candidatas: las que además pasan cerca del origen.
        let porOrigen = await GTFSRepository.shared.rutasQuePasanPor(origen, radioMetros: 350)
        let idsOrigen = Set(porOrigen.map(\.id))
        let candidatas = porDestino.filter { idsOrigen.contains($0.id) }
        guard !candidatas.isEmpty else { return nil }

        // Mejor candidata: primera cuyo shape va del origen al destino en
        // orden; si ninguna, la primera (tramo invertido ≈ sentido de retorno).
        var elegida: (ruta: RutaGTFS, coords: [CLLocationCoordinate2D], segundos: TimeInterval, sentidoCorrecto: Bool)? = nil
        for ruta in candidatas {
            guard let tramo = tramoShape(ruta.shape,
                                         desde: origen,
                                         hacia: destino,
                                         duracionLineaSeg: TimeInterval(ruta.duracionMin * 60)) else { continue }
            if tramo.sentidoCorrecto {
                elegida = (ruta, tramo.coords, tramo.segundos, true)
                break
            }
            if elegida == nil {
                elegida = (ruta, tramo.coords, tramo.segundos, false)
            }
        }
        guard let resultado = elegida else { return nil }
        #if DEBUG
        print("[TrackingDemo] ruta GTFS: \(resultado.ruta.linea) (sentido \(resultado.sentidoCorrecto ? "de ida" : "de retorno"))")
        #endif
        return (resultado.ruta, resultado.coords, resultado.segundos)
    }

    /// Trama el slice del shape entre los puntos más cercanos a origen y
    /// destino, más la caminata de conexión en ambos extremos.
    private func tramoShape(_ shape: [CLLocationCoordinate2D],
                            desde origen: CLLocationCoordinate2D,
                            hacia destino: CLLocationCoordinate2D,
                            duracionLineaSeg: TimeInterval)
        -> (coords: [CLLocationCoordinate2D], segundos: TimeInterval, sentidoCorrecto: Bool)? {
        guard shape.count >= 2,
              let iOrigen = indiceMasCercano(shape, a: origen),
              let iDestino = indiceMasCercano(shape, a: destino) else { return nil }

        let sentidoCorrecto = iOrigen < iDestino
        let tramo: [CLLocationCoordinate2D] = sentidoCorrecto
            ? Array(shape[iOrigen...iDestino])
            : Array(shape[iDestino...iOrigen]).reversed()
        guard tramo.count >= 2, let primerParadero = tramo.first, let ultimoParadero = tramo.last else {
            return nil
        }

        var coords = [origen]
        coords.append(contentsOf: tramo)
        coords.append(destino)

        // Ritmo real: el tramo dura lo que dice el stop_times de la línea,
        // proporcional a la fracción del shape recorrido.
        let metrosTramo = PolylineMatching.totalLengthMeters(tramo)
        let metrosTotales = max(PolylineMatching.totalLengthMeters(shape), 1)
        let segundosBus = duracionLineaSeg > 0
            ? duracionLineaSeg * (metrosTramo / metrosTotales)
            : metrosTramo / 6.0
        // Caminatas de conexión (origen → paradero y paradero → destino) a paso humano.
        let metrosCaminata = PolylineMatching.distanceMeters(origen, primerParadero)
                          + PolylineMatching.distanceMeters(ultimoParadero, destino)
        let segundos = segundosBus + metrosCaminata / 1.4

        return (coords, segundos, sentidoCorrecto)
    }

    /// Índice del punto del array más cercano a `objetivo`.
    private func indiceMasCercano(_ puntos: [CLLocationCoordinate2D],
                                  a objetivo: CLLocationCoordinate2D) -> Int? {
        guard !puntos.isEmpty else { return nil }
        var mejor = 0
        var mejorDistancia = Double.greatestFiniteMagnitude
        for (i, punto) in puntos.enumerated() {
            let d = PolylineMatching.distanceMeters(punto, objetivo)
            if d < mejorDistancia {
                mejorDistancia = d
                mejor = i
            }
        }
        return mejor
    }
    private func instalarShape(_ coords: [CLLocationCoordinate2D]) {
        let decimada = PolylineMatching.decimate(coords, maxPoints: 240)
        polyCoords = decimada.count >= 2 ? decimada : coords
        distanciaTotalM = PolylineMatching.totalLengthMeters(polyCoords)

        distanciasAcumuladas = [0]
        for i in 1..<polyCoords.count {
            distanciasAcumuladas.append(
                distanciasAcumuladas[i - 1] + PolylineMatching.distanceMeters(polyCoords[i - 1], polyCoords[i])
            )
        }
        demoProgreso = progreso
        ultimoFraccionPolyline = 0
        rutaRecorrida = nil
        rutaRestante = routePolyline
        // Ritmo real de simulación: distancia total / ETA de la ruta
        // (línea GTFS o MapKit). Es "a como vamos": micro urbano ≈ 20-25 km/h.
        if let eta = etaTotalSeg, eta > 10 {
            velocidadSimMs = max(1.2, distanciaTotalM / eta)
        } else {
            velocidadSimMs = 6.0
        }
    }

    /// Divide la polyline en tramo recorrido / restante según `progreso`.
    /// Se refresca cada ~0.5% de avance (o al 100%) para no reconstruir
    /// MKPolylines en cada tick del GPS/demo.
    private func refrescarPolylinesProgreso() {
        guard polyCoords.count >= 2,
              let total = distanciasAcumuladas.last, total > 0 else { return }
        guard progreso >= 0.999 || abs(progreso - ultimoFraccionPolyline) >= 0.005 else { return }
        ultimoFraccionPolyline = progreso

        let objetivo = total * min(max(progreso, 0), 1)
        var bajo = 0, alto = distanciasAcumuladas.count - 1
        while bajo < alto - 1 {
            let medio = (bajo + alto) / 2
            if distanciasAcumuladas[medio] <= objetivo { bajo = medio } else { alto = medio }
        }
        let longSeg = distanciasAcumuladas[alto] - distanciasAcumuladas[bajo]
        let t = longSeg > 0 ? (objetivo - distanciasAcumuladas[bajo]) / longSeg : 0
        let a = polyCoords[bajo], b = polyCoords[alto]
        let punto = CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                           longitude: a.longitude + (b.longitude - a.longitude) * t)

        var recorridas = Array(polyCoords[0...bajo])
        recorridas.append(punto)
        rutaRecorrida = recorridas.count >= 2
            ? MKPolyline(coordinates: recorridas, count: recorridas.count) : nil

        var restantes = [punto]
        restantes.append(contentsOf: polyCoords[alto...])
        rutaRestante = restantes.count >= 2
            ? MKPolyline(coordinates: restantes, count: restantes.count) : nil
    }

    // MARK: - Salidas formateadas (mismo estilo de NavegacionRutaView)

    var minutosRestantes: Int {
        guard let total = etaTotalSeg else { return 0 }
        return max(0, Int((total / 60.0 * (1 - progreso)).rounded()))
    }

    var distanciaRestanteTexto: String {
        distanciaRestanteM >= 1000
            ? String(format: "%.1f km", distanciaRestanteM / 1000)
            : "\(Int(distanciaRestanteM)) m"
    }

    /// Ritmo real de la ruta activa, para el caption del selector 1×/3×/10×.
    var velocidadSimKmh: Int {
        Int((velocidadSimMs * 3.6).rounded())
    }

    // MARK: - Modo demo (simulación de avance sobre la ruta calculada)

    private func iniciarDemoSimulado() {
        guard tripInProgress, polyCoords.count >= 2 else {
            modoDemo = false
            return
        }
        detenerDemoSimulado()
        demoProgreso = progreso
        demoTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Avance por METROS reales: velocidad real de la ruta (m/s)
                // × multiplicador elegido. 1× = ritmo real de la línea.
                guard let total = self.distanciasAcumuladas.last, total > 1 else { return }
                let deltaMetros = self.velocidadSimMs * self.velocidadDemo * 0.08
                self.demoProgreso = min(1.0, self.demoProgreso + deltaMetros / total)
                let coord = self.coordenadaEnFraccion(self.demoProgreso)
                let siguiente = self.coordenadaEnFraccion(min(1.0, self.demoProgreso + 0.002))
                let rumbo = atan2(siguiente.longitude - coord.longitude,
                                  siguiente.latitude - coord.latitude) * 180 / .pi
                self.procesar(coordenada: coord, rumbo: rumbo)
            }
        }
    }

    private func detenerDemoSimulado() {
        demoTimer?.invalidate()
        demoTimer = nil
    }

    /// Coordenada sobre el shape a una fracción 0...1 (búsqueda binaria).
    private func coordenadaEnFraccion(_ fraccion: Double) -> CLLocationCoordinate2D {
        guard polyCoords.count >= 2,
              let ultima = distanciasAcumuladas.last else {
            return posicion ?? CLLocationCoordinate2D()
        }
        let objetivo = max(0, min(1, fraccion)) * ultima
        var bajo = 0, alto = distanciasAcumuladas.count - 1
        while bajo < alto - 1 {
            let medio = (bajo + alto) / 2
            if distanciasAcumuladas[medio] <= objetivo { bajo = medio } else { alto = medio }
        }
        let longitudSeg = distanciasAcumuladas[alto] - distanciasAcumuladas[bajo]
        let t = longitudSeg > 0 ? (objetivo - distanciasAcumuladas[bajo]) / longitudSeg : 0
        let a = polyCoords[bajo], b = polyCoords[alto]
        return CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * t,
            longitude: a.longitude + (b.longitude - a.longitude) * t
        )
    }

    // MARK: - Vehículos (VehicleTrackingProviding)

    private func iniciarVehiculos() {
        vehicleProvider.start()
        vehiculoTask?.cancel()
        vehiculoTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var ultimaActualizacion = 0.0
            for await positions in self.vehicleProvider.positions() {
                guard !Task.isCancelled else { break }
                // El provider ticka a 20 Hz: la UI se refresca a 4 Hz, de sobra
                // para que los buses se muevan fluidos sin re-renderizar el
                // mapa a cada instante.
                let ahora = Date().timeIntervalSince1970
                guard ahora - ultimaActualizacion >= 0.25 else { continue }
                ultimaActualizacion = ahora

                var velocidades = self.velocidadesVehiculos
                for vehiculo in positions {
                    if let previa = self.snapshotVehiculosAnterior[vehiculo.id] {
                        let dt = vehiculo.timestamp - previa.t
                        if dt > 0.2 {
                            velocidades[vehiculo.id] = max(0,
                                PolylineMatching.distanceMeters(previa.coord, vehiculo.coordinate) / dt)
                        }
                    }
                    self.snapshotVehiculosAnterior[vehiculo.id] = (vehiculo.coordinate, vehiculo.timestamp)
                }
                self.velocidadesVehiculos = velocidades
                self.vehiculos = positions
            }
        }
    }

    // MARK: - Registro de la sesión (TripSession)

    private func registrarPunto(_ coord: CLLocationCoordinate2D, rumbo: Double) {
        guard var sesion else { return }
        // Muestreo con separación mínima de 3 m para no inundar el historial.
        if let ultimo = sesion.puntosRecorridos.last,
           PolylineMatching.distanceMeters(ultimo.coordinate, coord) < 3 { return }
        sesion.puntosRecorridos.append(
            TrackingPoint(lat: coord.latitude, lon: coord.longitude,
                          heading: max(0, rumbo))
        )
        self.sesion = sesion
    }

    private func finalizarSesion(estado nuevo: TripState) {
        // Resumen con las métricas del viaje para la card de llegada.
        let inicio = sesion?.startedAt ?? Date().timeIntervalSince1970
        let duracion = max(0, Date().timeIntervalSince1970 - inicio)
        let distancia = distanciaTotalM * progreso
        let puntos = sesion?.puntosRecorridos.count ?? 0
        resumen = ResumenViaje(
            duracionS: duracion,
            distanciaM: distancia,
            puntos: puntos,
            velocidadKmh: duracion > 0 ? (distancia / duracion) * 3.6 : 0
        )
        sesion?.estado = nuevo
        sesion?.endedAt = Date().timeIntervalSince1970
    }

    // MARK: - Cancelación

    func cancelTrip() {
        if tripInProgress { finalizarSesion(estado: .cancelled) }
        tripInProgress = false
        modoDemo = false
        destinoSeleccionado = nil
        routePolyline = nil
        etaTotalSeg = nil
        sesion = nil
        polyCoords.removeAll()
        distanciasAcumuladas.removeAll()
        distanciaTotalM = 0
        progreso = 0
        distanciaRestanteM = 0
        consecutiveOffRoute = 0
        recalculando = false
        resumen = nil
        rutaRecorrida = nil
        rutaRestante = nil
        rutaAproximada = false
        rutaGTFS = nil
        velocidadSimMs = 6.0
        ultimoFraccionPolyline = 0
        estado = posicion != nil ? .listo : .esperandoGPS
    }

    func stop() {
        cancelTrip()
        locationTask?.cancel()
        vehiculoTask?.cancel()
        vehicleProvider.stop()
        locationService.stopUpdating()
    }
}
