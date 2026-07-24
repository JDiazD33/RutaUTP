//
//  MapaViewModel.swift
//  RutaUTP
//
//  ViewModel del Mapa. Maneja:
//   - region (zoom al destino)
//   - textoBusqueda (binding del TextField)
//   - destinoSeleccionado (chip activo)
//   - busSimulados (6 puntos rojos animados alrededor del destino)
//
//  El timer se inicia al seleccionar destino y se detiene al limpiar
//  o al desaparecer la vista.
//

import SwiftUI
import MapKit
import Combine

// MARK: - Bus simulado
struct BusSimulado: Identifiable, Equatable {
    let id: Int
    var lat: Double
    var lon: Double
    let linea: String
    let colorBus: Color
    var angulo: Double
    let velocidad: Double
}

// MARK: - Bus animado sobre ruta real
struct BusAnimado: Identifiable, Equatable {
    let id: Int
    let linea: String        // "10", "4"
    let empresa: String      // "El Cortijo", "Salaverry"
    let tipo: String          // "Micro", "Combi"
    let placa: String         // "T1B-721"
    let minutosLlegada: Int   // 4, 12
    let color: Color          // .appPrimary, .secondary
    var lat: Double           // posición actual (animada)
    var lon: Double
    var heading: Double       // ángulo de dirección
    let rutaCoordenadas: [CLLocationCoordinate2D]  // waypoints

    var currentSegmentIndex: Int = 0
    var segmentProgress: Double = 0.0
    var isMovingForward: Bool = true

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
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
}

// MARK: - Anotación unificada para el mapa
enum TipoAnotacion: Equatable {
    case utp
    case usuario
    case usuarioReal
    case bus(String)
    case conductor(String)
    case busqueda(String)
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

    // GPS Real
    @Published var userRealCoordinate: CLLocationCoordinate2D? = nil
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    // Búsqueda MapKit
    @Published var sugerenciasBusqueda: [MKLocalSearchCompletion] = []
    @Published var busquedaResultado: (titulo: String, coordenada: CLLocationCoordinate2D)? = nil
    @Published var buscando: Bool = false

    // Tracking & Ruteo Real (igual a RouteTrackingDemoView)
    @Published var routePolyline: MKPolyline? = nil
    @Published var etaMinutos: Int? = nil
    @Published var distanciaKm: Double? = nil
    @Published var calculandoRuta: Bool = false

    // Buses Animados en Tiempo Real
    @Published var busesAnimados: [BusAnimado] = []
    @Published var busSeleccionado: BusAnimado? = nil
    private var busSimulationTimer: Timer?

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
    }

    deinit {
        locationTask?.cancel()
        locationService.stopUpdating()
        detenerSimulacionBuses()
    }

    // MARK: - Ubicación GPS Real
    func iniciarGPS() {
        locationTask?.cancel()
        locationTask = Task { @MainActor in
            let status = await locationService.requestPermission()
            self.authorizationStatus = status
            if status.isAuthorized {
                locationService.startUpdating()
                for await location in locationService.currentLocation() {
                    let isInitialFix = (self.userRealCoordinate == nil)
                    self.userRealCoordinate = location.coordinate
                    if isInitialFix {
                        self.recenterOnUser()
                    }
                }
            }
        }
        iniciarSimulacionBuses()
    }

    // MARK: - Simulación de Buses Animados
    func iniciarSimulacionBuses() {
        guard busSimulationTimer == nil else { return }

        let coords10 = RutaCoordenadas.linea10
        let coords4 = RutaCoordenadas.linea4

        guard !coords10.isEmpty, !coords4.isEmpty else { return }

        let bus10 = BusAnimado(
            id: 1,
            linea: "10",
            empresa: "El Cortijo",
            tipo: "Micro",
            placa: "T1B-721",
            minutosLlegada: 4,
            color: .appPrimary,
            lat: coords10.first!.latitude,
            lon: coords10.first!.longitude,
            heading: 0,
            rutaCoordenadas: coords10
        )

        let bus4 = BusAnimado(
            id: 2,
            linea: "4",
            empresa: "Salaverry",
            tipo: "Combi",
            placa: "A6N-450",
            minutosLlegada: 12,
            color: .secondary,
            lat: coords4.first!.latitude,
            lon: coords4.first!.longitude,
            heading: 0,
            rutaCoordenadas: coords4
        )

        busesAnimados = [bus10, bus4]

        busSimulationTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.actualizarPosicionBuses()
            }
        }
    }

    func detenerSimulacionBuses() {
        busSimulationTimer?.invalidate()
        busSimulationTimer = nil
    }

    private func actualizarPosicionBuses() {
        for i in busesAnimados.indices {
            var bus = busesAnimados[i]
            let waypoints = bus.rutaCoordenadas
            guard waypoints.count >= 2 else { continue }

            let step: Double = 0.012

            bus.segmentProgress += step
            if bus.segmentProgress >= 1.0 {
                bus.segmentProgress = 0.0
                if bus.isMovingForward {
                    if bus.currentSegmentIndex + 1 < waypoints.count - 1 {
                        bus.currentSegmentIndex += 1
                    } else {
                        bus.isMovingForward = false
                    }
                } else {
                    if bus.currentSegmentIndex > 0 {
                        bus.currentSegmentIndex -= 1
                    } else {
                        bus.isMovingForward = true
                    }
                }
            }

            let idxA = bus.currentSegmentIndex
            let idxB = idxA + 1
            guard idxB < waypoints.count else { continue }

            let pA = waypoints[idxA]
            let pB = waypoints[idxB]

            let fromCoord = bus.isMovingForward ? pA : pB
            let toCoord = bus.isMovingForward ? pB : pA

            bus.lat = fromCoord.latitude + (toCoord.latitude - fromCoord.latitude) * bus.segmentProgress
            bus.lon = fromCoord.longitude + (toCoord.longitude - fromCoord.longitude) * bus.segmentProgress

            let dLat = toCoord.latitude - fromCoord.latitude
            let dLon = toCoord.longitude - fromCoord.longitude
            bus.heading = atan2(dLon, dLat) * 180 / .pi

            busesAnimados[i] = bus
        }
    }

    func recenterOnUser() {
        if let userCoord = userRealCoordinate {
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

    // Destinos conocidos (Coordenadas UTP actualizadas a Av. Nicolás de Piérola 1221, Trujillo)
    let destinos: [DestinoChip] = [
        DestinoChip(id: 1, label: "Casa",      icon: "house.fill",         lat: -8.1180, lon: -79.0350),
        DestinoChip(id: 2, label: "UTP",       icon: "graduationcap.fill", lat: -8.098247879173792, lon: -79.03818104755645),
        DestinoChip(id: 3, label: "Trabajo",   icon: "briefcase.fill",     lat: -8.1050, lon: -79.0200),
        DestinoChip(id: 4, label: "Centro",    icon: "building.2.fill",    lat: -8.1090, lon: -79.0270),
        DestinoChip(id: 5, label: "Huanchaco", icon: "water.waves",        lat: -8.0825, lon: -79.1197)
    ]

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
        if destinoSeleccionado?.id == destino.id { return }

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
        calcularRutaHacia(destCoord)
    }

    func seleccionarSugerencia(_ completion: MKLocalSearchCompletion) {
        sugerenciasBusqueda = []
        textoBusqueda = completion.title
        buscando = true

        let searchRequest = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: searchRequest)

        search.start { [weak self] response, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
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
            $0.label.lowercased().contains(t.lowercased())
        }) {
            seleccionar(destino: match)
            return
        }

        buscando = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = t
        request.region = region

        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
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

    private func seleccionarLugar(titulo: String, coordenada: CLLocationCoordinate2D) {
        destinoSeleccionado = nil
        busquedaResultado = (titulo: titulo, coordenada: coordenada)

        withAnimation(.spring(response: 0.5)) {
            region = MKCoordinateRegion(
                center: coordenada,
                span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
            )
        }
        calcularRutaHacia(coordenada)
    }

    // MARK: - Ruteo Real (Polilínea MKDirections)
    func calcularRutaHacia(_ destinoCoord: CLLocationCoordinate2D) {
        let origen = userRealCoordinate ?? CLLocationCoordinate2D(latitude: -8.1180, longitude: -79.0350)
        calculandoRuta = true

        Task { @MainActor in
            do {
                let route: CalculatedRoute
                do {
                    route = try await self.routeService.calculateRoute(from: origen, to: destinoCoord, transportType: .transit)
                } catch {
                    route = try await self.routeService.calculateRoute(from: origen, to: destinoCoord, transportType: .automobile)
                }
                self.routePolyline = route.polyline
                self.etaMinutos = Int(ceil(route.expectedTravelTime / 60.0))
                self.distanciaKm = Double(round(10 * (route.distance / 1000.0)) / 10)
                self.calculandoRuta = false
            } catch {
                #if DEBUG
                print("[MapaViewModel] Error calculando ruta: \(error.localizedDescription)")
                #endif
                self.calculandoRuta = false
            }
        }
    }

    func limpiar() {
        textoBusqueda = ""
        destinoSeleccionado = nil
        busquedaResultado = nil
        sugerenciasBusqueda = []
        completer.queryFragment = ""
        routePolyline = nil
        etaMinutos = nil
        distanciaKm = nil

        withAnimation(.spring(response: 0.5)) {
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: -8.098247879173792, longitude: -79.03818104755645),
                span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035)
            )
        }
    }

    // MARK: - Anotaciones para el mapa
    func anotaciones() -> [MapaAnotacion] {
        var items: [MapaAnotacion] = []

        // Marcador del campus UTP
        items.append(MapaAnotacion(id: -1, lat: -8.098247879173792, lon: -79.03818104755645, tipo: .utp))

        // Marcador de usuario GPS Real o Peatón Mock
        if let userCoord = userRealCoordinate {
            items.append(MapaAnotacion(id: -2, lat: userCoord.latitude, lon: userCoord.longitude, tipo: .usuarioReal))
        } else {
            items.append(MapaAnotacion(id: -2, lat: -8.1180, lon: -79.0350, tipo: .usuario))
        }

        // Marcador del destino buscado (ej. UPAO, Casa, Mall)
        if let res = busquedaResultado, res.titulo != "UTP" {
            items.append(MapaAnotacion(
                id: -3,
                lat: res.coordenada.latitude,
                lon: res.coordenada.longitude,
                tipo: .busqueda(res.titulo)
            ))
        }

        return items
    }
}



