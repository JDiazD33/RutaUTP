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

// MARK: - Representación visual de un vehículo
struct BusAnimado: Identifiable, Equatable {
    let id: String
    let linea: String
    let empresa: String
    let tipo: String
    let placa: String
    let minutosLlegada: Int
    let color: Color

    var lat: Double
    var lon: Double
    var heading: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: lat,
            longitude: lon
        )
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
    
    // Posiciones recibidas desde VehicleTrackingProviding.
    // Durante el Paso 1.2 se reciben en paralelo, pero todavía no reemplazan
    // los buses GTFS que actualmente dibuja el mapa.
    @Published private(set) var posicionesProveedor: [VehiclePosition] = []
    private var rutasGTFSPorLinea: [String: RutaGTFS] = [:]

    /// Se incrementa cada vez que el usuario pide recentrar; la vista lo
    /// observa para mover la cámara aunque la región no haya cambiado de
    /// valor (el usuario puede haber arrastrado el mapa sin pasar por aquí).
    @Published var recentrarToken = 0

    private let locationService: LocationServiceProtocol
    private let routeService: RouteCalculationService
    private let vehicleTrackingProvider: VehicleTrackingProviding

    private let completer = MKLocalSearchCompleter()

    private var locationTask: Task<Void, Never>?
    private var vehicleTrackingTask: Task<Void, Never>?
    

    init(
        locationService: LocationServiceProtocol = LocationService(),
        routeService: RouteCalculationService = RouteCalculationService(),
        vehicleTrackingProvider: VehicleTrackingProviding = SimulatedTrackingProvider()
    ) {
        self.locationService = locationService
        self.routeService = routeService
        self.vehicleTrackingProvider = vehicleTrackingProvider
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
        vehicleTrackingTask?.cancel()

        locationService.stopUpdating()
        vehicleTrackingProvider.stop()
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

                        // Si ya había un destino trazado desde el origen mock
                        // (el usuario llegó antes que el primer fix del GPS),
                        // recalcular la ruta desde la posición REAL del teléfono.
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
    }
    
    // MARK: - Proveedor de posiciones de vehículos

    func iniciarProveedorTracking() {
        vehicleTrackingTask?.cancel()

        vehicleTrackingTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let rutas = await GTFSRepository.shared.rutasCercaDeUTP(n: 4)

            self.rutasGTFSPorLinea = Dictionary(
                rutas.map { ($0.linea, $0) },
                uniquingKeysWith: { primera, _ in primera }
            )

            guard !Task.isCancelled else { return }

            self.vehicleTrackingProvider.start()

            for await posiciones in self.vehicleTrackingProvider.positions() {
                guard !Task.isCancelled else { break }

                self.posicionesProveedor = posiciones
                self.actualizarBusesDesdeProveedor(posiciones)

                #if DEBUG
                print(
                    "[TrackingProvider] Fuente: \(self.vehicleTrackingProvider.source.rawValue), " +
                    "vehículos recibidos: \(posiciones.count)"
                )
                #endif
            }
        }
    }

    func detenerProveedorTracking() {
        vehicleTrackingTask?.cancel()
        vehicleTrackingTask = nil

        vehicleTrackingProvider.stop()

        posicionesProveedor = []
        busesAnimados = []
        busSeleccionado = nil
    }
    
    @MainActor
    private func actualizarBusesDesdeProveedor(
        _ posiciones: [VehiclePosition]
    ) {
        let cantidad = max(posiciones.count, 1)

        busesAnimados = posiciones.enumerated().map { index, posicion in
            let ruta = rutasGTFSPorLinea[posicion.linea]

            return BusAnimado(
                id: posicion.id,
                linea: posicion.linea,
                empresa: ruta?.empresa ?? "Empresa no disponible",
                tipo: "Bus",
                placa: ruta?.variante.isEmpty == false
                    ? "Ramal \(ruta?.variante ?? "")"
                    : "S/D",
                minutosLlegada: max(
                    1,
                    2 + index * max(
                        1,
                        (ruta?.headwayMin ?? 4) / cantidad
                    )
                ),
                color: ruta?.color ?? .appPrimary,
                lat: posicion.lat,
                lon: posicion.lon,
                heading: posicion.heading >= 0
                    ? posicion.heading
                    : 0
            )
        }

        if let seleccionado = busSeleccionado {
            busSeleccionado = busesAnimados.first {
                $0.id == seleccionado.id
            }
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

    // Destinos conocidos (Coordenadas UTP actualizadas a Av. Nicolás de Piérola 1221, Trujillo)
    let destinos: [DestinoChip] = [
        DestinoChip(id: 1, label: L.t("Casa", "Home"),      icon: "house.fill",         lat: -8.1180, lon: -79.0350),
        DestinoChip(id: 2, label: "UTP",       icon: "graduationcap.fill", lat: -8.098247879173792, lon: -79.03818104755645),
        DestinoChip(id: 3, label: L.t("Trabajo", "Work"),   icon: "briefcase.fill",     lat: -8.1050, lon: -79.0200),
        DestinoChip(id: 4, label: L.t("Centro", "Downtown"),    icon: "building.2.fill",    lat: -8.1090, lon: -79.0270),
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

    func seleccionarLugar(titulo: String, coordenada: CLLocationCoordinate2D) {
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

        #if DEBUG
        print("[Ruta] calculando desde (\(origen.latitude), \(origen.longitude)) hacia (\(destinoCoord.latitude), \(destinoCoord.longitude))")
        #endif

        Task { @MainActor in
            var route: CalculatedRoute? = nil
            do {
                route = try await self.routeService.calculateRoute(from: origen, to: destinoCoord, transportType: .transit)
            } catch {
                #if DEBUG
                print("[Ruta] transit falló: \(error.localizedDescription)")
                #endif
            }
            if route == nil {
                do {
                    route = try await self.routeService.calculateRoute(from: origen, to: destinoCoord, transportType: .automobile)
                } catch {
                    #if DEBUG
                    print("[Ruta] automobile falló: \(error.localizedDescription)")
                    #endif
                }
            }

            if let route {
                #if DEBUG
                print("[Ruta] OK por calles: \(Int(route.distance)) m, \(Int(route.expectedTravelTime/60)) min")
                #endif
                self.routePolyline = route.polyline
                self.etaMinutos = Int(ceil(route.expectedTravelTime / 60.0))
                self.distanciaKm = Double(round(10 * (route.distance / 1000.0)) / 10)
            } else {
                // Fallback: MKDirections sin respuesta (sin red, región sin
                // cobertura, etc). Trazamos la línea directa para que el
                // usuario SIEMPRE vea origen → destino en el mapa.
                #if DEBUG
                print("[Ruta] sin respuesta de MKDirections → trazo directo")
                #endif
                var coords = [origen, destinoCoord]
                self.routePolyline = MKPolyline(coordinates: &coords, count: 2)
                let metros = PolylineMatching.distanceMeters(origen, destinoCoord)
                self.distanciaKm = Double(round(10 * (metros / 1000.0)) / 10)
                self.etaMinutos = Int(ceil(metros / 83.0))   // ~5 km/h caminando
            }
            self.calculandoRuta = false
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
