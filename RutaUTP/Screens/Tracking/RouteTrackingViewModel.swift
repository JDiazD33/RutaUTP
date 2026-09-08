//
//  RouteTrackingViewModel.swift
//  RutaUTP
//
//  ViewModel del Tracking Demo: banco de pruebas del módulo de tracking.
//  Integra TODO el stack actual:
//   - Ruteo real con el MISMO pipeline del Mapa (RouteCalculationService:
//     transit → automobile → trazo directo de respaldo).
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

    static let destinos: [DestinoDemo] = [
        DestinoDemo(id: 1, label: "UTP", icon: "graduationcap.fill",
                    coordinate: CLLocationCoordinate2D(latitude: -8.098247879173792, longitude: -79.03818104755645)),
        DestinoDemo(id: 2, label: "Centro", icon: "building.2.fill",
                    coordinate: CLLocationCoordinate2D(latitude: -8.1090, longitude: -79.0270)),
        DestinoDemo(id: 3, label: "Huanchaco", icon: "water.waves",
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
            errorMessage = "Permiso de ubicación denegado. Actívalo en Ajustes para usar el tracking."
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

        // Llegó: cerrar la sesión de viaje (una sola vez).
        if estado == .finalizado, sesion?.estado != .completed {
            finalizarSesion(estado: .completed)
        }

        registrarPunto(coordenada, rumbo: rumbo)
    }

    // MARK: - Inicio de viaje

    func iniciar(destino: DestinoDemo) async {
        guard authStatus.isAuthorized else {
            errorMessage = "Sin permiso de ubicación. Concédelo en Ajustes."
            return
        }
        guard let origen = posicion else {
            errorMessage = "Aún no tenemos tu ubicación. Espera unos segundos."
            return
        }

        errorMessage = nil
        destinoSeleccionado = destino
        tripInProgress = true
        progreso = 0
        consecutiveOffRoute = 0

        sesion = TripSession(
            linea: destino.label,
            empresa: "Tracking Demo",
            origen: TrackingPoint(lat: origen.latitude, lon: origen.longitude),
            destino: TrackingPoint(lat: destino.coordinate.latitude, lon: destino.coordinate.longitude),
            estado: .inProgress,
            startedAt: Date().timeIntervalSince1970
        )

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

    /// Pipeline de ruteo REAL del Mapa: transit → automobile → trazo directo.
    private func calcularRuta(desde origen: CLLocationCoordinate2D,
                              hacia destino: CLLocationCoordinate2D) async {
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
            routePolyline = ruta.polyline
            etaTotalSeg = ruta.expectedTravelTime
            instalarShape(PolylineMatching.coordinates(from: ruta.polyline))
        } else {
            // Sin respuesta de MKDirections (sin red, sin cobertura): trazo
            // directo para que SIEMPRE haya ruta visible, igual que el Mapa.
            #if DEBUG
            print("[TrackingDemo] sin respuesta de MKDirections → trazo directo")
            #endif
            routePolyline = MKPolyline(coordinates: [origen, destino], count: 2)
            let metros = PolylineMatching.distanceMeters(origen, destino)
            etaTotalSeg = metros / 83.0 * 60   // ~5 km/h, mismo criterio del Mapa
            instalarShape([origen, destino])
        }
    }

    /// Prepara shape decimado + distancias acumuladas (una vez por ruta).
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
                self.demoProgreso = min(1.0, self.demoProgreso + 1.0 / 900.0)   // ~72 s todo el viaje
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
            for await positions in self.vehicleProvider.positions() {
                guard !Task.isCancelled else { break }
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
