import XCTest
import CoreLocation
import MapKit
import Combine
@testable import RutaUTP

/// Integración preparada para iOS. Todas las dependencias de datos se capturan;
/// no usa MQTT, GPS, feed externo ni las preferencias estándar.
@MainActor
final class SimulationPresentationIntegrationTests: XCTestCase {
    private let run = "8e5dc699-60d4-4f58-8ced-638313365544"
    private let campus = GTFSRepository.coordenadaUTP

    private func position(_ id: String? = nil, origin: VehicleDataOrigin = .simulated,
                          revision: UInt64 = 3, heading: Double = 90,
                          speed: Double = 8) -> VehiclePosition {
        VehiclePosition(id: id ?? "sim:\(run):bus", linea: "T", routeId: "route",
            lat: campus.latitude, lon: campus.longitude - 0.015, heading: heading,
            speed: speed, dataOrigin: origin,
            simulationRunId: origin == .simulated ? run : nil,
            controlRevision: origin == .simulated ? revision : nil)
    }

    private func route() -> RutaGTFS {
        RutaGTFS(id: "route", linea: "T", variante: "A", recorrido: "Inicio → Fin",
            empresa: "Prueba", colorHex: "00CC00", color: .green,
            shape: (0...20).map {
                CLLocationCoordinate2D(latitude: campus.latitude,
                    longitude: campus.longitude - 0.02 + Double($0) * 0.002)
            }, paraderos: [], duracionMin: 10, headwayMin: 5, precio: 2,
            distanciaKm: 4.4, distanciaUTPMetros: 0)
    }

    private func map(_ provider: PresentationProvider, preferences: MapVehiclePreferences? = nil) -> MapaViewModel {
        let defaults = UserDefaults(suiteName: "RutaUTP.MapLimit.\(UUID().uuidString)")!
        return MapaViewModel(locationService: PresentationGPS(),
            repositorioGTFS: PresentationCatalog(feed: [route()]),
            mapVehiclePreferences: preferences ?? MapVehiclePreferences(defaults: defaults), crearProveedorReal: { provider })
    }

    private func tracking(_ provider: PresentationProvider, preferences: MapVehiclePreferences? = nil) -> RouteTrackingViewModel {
        // Suite vacía exclusiva del test; no se escribe ningún valor persistente.
        let defaults = UserDefaults(suiteName: "RutaUTP.S08.\(UUID().uuidString)")!
        return RouteTrackingViewModel(locationService: PresentationGPS(), vehicleProvider: provider,
            repositorioGTFS: PresentationCatalog(feed: [route()]), defaults: defaults,
            mapVehiclePreferences: preferences ?? MapVehiclePreferences(defaults: defaults))
    }

    private func wait(_ description: String, _ condition: () -> Bool) async {
        for _ in 0..<400 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("No se completó: \(description)")
    }

    func testOcupacionSePropagaActualizaFichaYNoAbreVotos() async throws {
        let base = position()
        func occupied(_ state: VehicleScenarioOccupancy) -> VehiclePosition {
            VehiclePosition(id: base.id, linea: base.linea, routeId: base.routeId,
                lat: base.lat, lon: base.lon, timestamp: base.timestamp, dataOrigin: .simulated,
                simulationRunId: run, controlRevision: 3, scenarioOccupancy: state)
        }
        let provider = PresentationProvider([occupied(.full)])
        let vm = map(provider); defer { vm.detener() }
        vm.iniciarSimulacionBuses()
        await wait("ocupación inicial") { vm.tarjetasDelPanel.first?.displayedScenarioOccupancy == .full }
        vm.busSeleccionado = vm.busesAnimados.first
        XCTAssertNil(vm.busSeleccionado?.occupancyVehicleID)
        provider.emit([occupied(.space)])
        await wait("ocupación actualizada") { vm.busSeleccionado?.displayedScenarioOccupancy == .space }
        XCTAssertEqual(vm.tarjetasDelPanel.first?.displayedScenarioOccupancy, .space)
        provider.emit([])
        await wait("retirada con ocupación") { vm.busesAnimados.isEmpty }
        XCTAssertNil(vm.busSeleccionado)
    }

    func testMapaPropagaMetadatosHastaPanelYNoAbreOcupacionSintetica() async throws {
        let value = position(heading: -1)
        let provider = PresentationProvider([value])
        let vm = map(provider); defer { vm.detener() }
        vm.iniciarSimulacionBuses()
        await wait("flota y panel") { vm.tarjetasDelPanel.count == 1 }
        let bus = try XCTUnwrap(vm.busesAnimados.first)
        let card = try XCTUnwrap(vm.tarjetasDelPanel.first)
        XCTAssertEqual(bus.fuente, .real)
        XCTAssertEqual(bus.dataOrigin, .simulated)
        XCTAssertEqual(bus.simulationRunId, run)
        XCTAssertEqual(bus.controlRevision, 3)
        XCTAssertEqual(bus.heading, -1)
        XCTAssertEqual(bus.backendVehicleID, value.id)
        XCTAssertNil(bus.occupancyVehicleID)
        XCTAssertEqual(card.dataOrigin, .simulated)
        XCTAssertEqual(card.simulationRunId, run)
        XCTAssertEqual(card.controlRevision, 3)
    }

    func testRetiradaMapaLimpiaSeleccionYETASinBorrarDestinoRutaNiObservados() async throws {
        let observed = position("observed", origin: .observed)
        let provider = PresentationProvider([position(), observed])
        let vm = map(provider); defer { vm.detener() }
        vm.iniciarSimulacionBuses()
        await wait("mezcla") { vm.tarjetasDelPanel.count == 2 }
        vm.busSeleccionado = try XCTUnwrap(vm.busesAnimados.first { $0.dataOrigin == .simulated })
        let path = MKPolyline(coordinates: route().shape, count: route().shape.count)
        vm.routePolyline = path
        vm.etaMinutos = 17
        vm.busquedaResultado = ("Destino conservado", campus)

        provider.emit([observed])
        await wait("retirada") { vm.busesAnimados.count == 1 }
        XCTAssertNil(vm.busSeleccionado)
        XCTAssertEqual(vm.tarjetasDelPanel.map(\.id), ["real-observed"])
        XCTAssertEqual(vm.busesAnimados.first?.occupancyVehicleID, "observed")
        XCTAssertTrue(vm.routePolyline === path)
        XCTAssertEqual(vm.etaMinutos, 17)
        XCTAssertEqual(vm.busquedaResultado?.titulo, "Destino conservado")
        XCTAssertEqual(vm.rutasCercanas.map(\.id), ["route"])
    }

    func testRevisionNuevaMismaPosicionCierraFichaYActualizaPanel() async {
        let provider = PresentationProvider([position()])
        let vm = map(provider); defer { vm.detener() }
        vm.iniciarSimulacionBuses()
        await wait("primero") { vm.tarjetasDelPanel.count == 1 }
        vm.busSeleccionado = vm.busesAnimados.first
        provider.emit([position(revision: 4)])
        await wait("revisión") { vm.tarjetasDelPanel.first?.controlRevision == 4 }
        XCTAssertNil(vm.busSeleccionado)
        XCTAssertEqual(vm.busesAnimados.first?.controlRevision, 4)
    }

    func testMapaRevalidaAntesDeUsarSnapshotEntregadoAntiguo() async {
        let values = [position()]
        let provider = PresentationProvider(values)
        let vm = map(provider); defer { vm.detener() }
        vm.iniciarSimulacionBuses()
        await wait("primero") { vm.busesAnimados.count == 1 }
        vm.busSeleccionado = vm.busesAnimados.first
        provider.allowSynthetic = false
        let reads = provider.presentationReads
        provider.yieldStale(values)
        await wait("revalidación") { provider.presentationReads > reads }
        XCTAssertTrue(vm.busesAnimados.isEmpty)
        XCTAssertTrue(vm.tarjetasDelPanel.isEmpty)
        XCTAssertNil(vm.busSeleccionado)
    }

    func testMapaReentradaRevalidaSinEsperarOtroMensaje() async {
        let provider = PresentationProvider([position()])
        let vm = map(provider); defer { vm.detener() }
        vm.iniciarSimulacionBuses()
        await wait("primero") { vm.busesAnimados.count == 1 }
        provider.allowSynthetic = false
        vm.actualizarActividadVisual(true)
        XCTAssertTrue(vm.busesAnimados.isEmpty)
        XCTAssertNil(vm.busSeleccionado)
        XCTAssertEqual(vm.fuenteFlota, .real)
    }

    func testCerrarYReabrirMapaNoRestauraFlotaAnterior() async {
        let provider = PresentationProvider([position()])
        let vm = map(provider); defer { vm.detener() }
        vm.iniciarSimulacionBuses()
        await wait("primero") { vm.busesAnimados.count == 1 }
        vm.busSeleccionado = vm.busesAnimados.first
        vm.detenerSimulacionBuses()
        XCTAssertTrue(vm.busesAnimados.isEmpty)
        XCTAssertTrue(vm.tarjetasDelPanel.isEmpty)
        XCTAssertNil(vm.busSeleccionado)
        provider.initialOnStart = []
        vm.iniciarSimulacionBuses()
        await wait("reabierto") { provider.starts == 2 && !vm.esperandoPosicionesReales }
        XCTAssertTrue(vm.busesAnimados.isEmpty)
        XCTAssertEqual(vm.fuenteFlota, .real)
    }

    func testPresentacionConservaConexionEntrePestanasYAplicaSnapshotActualAlVolver() async throws {
        let provider = PresentationProvider([position()])
        provider.keepsConnectionWhileMapHidden = true
        let vm = map(provider); defer { vm.detenerSimulacionBuses() }
        vm.iniciarSimulacionBuses()
        await wait("primero") { vm.busesAnimados.count == 1 }
        vm.actualizarActividadVisual(false)
        vm.detener()
        XCTAssertEqual(provider.stops, 0)
        var updated = position(); updated.lat += 0.001; updated.timestamp += 1
        provider.emit([updated])
        await Task.yield()
        vm.actualizarActividadVisual(true)
        vm.iniciarSimulacionBuses()
        XCTAssertEqual(provider.starts, 1)
        XCTAssertEqual(vm.busesAnimados.first?.lat, updated.lat)
        vm.actualizarActividadVisual(false)
        provider.emit([])
        await wait("OFF aun oculto") { vm.busesAnimados.isEmpty }
        vm.actualizarActividadVisual(true)
        XCTAssertTrue(vm.busesAnimados.isEmpty)
    }

    func testPresentacionNoRetieneViewModelAlDestruirLaPantalla() async {
        let provider = PresentationProvider([position()]); provider.keepsConnectionWhileMapHidden = true
        var vm: MapaViewModel? = map(provider)
        weak var released = vm
        vm?.iniciarSimulacionBuses()
        await wait("iniciado") { provider.starts == 1 }
        vm?.actualizarActividadVisual(false); vm?.detener()
        vm = nil
        await wait("liberado") { released == nil && provider.stops == 1 }
    }

    func testOcupacionDesconocidaYLegadaNoUsanTransporteComoProcedencia() async {
        let provider = PresentationProvider([position("unknown", origin: .unknown),
            position("legacy", origin: .legacyUnknown), position("observed", origin: .observed)])
        let vm = map(provider); defer { vm.detener() }
        vm.iniciarSimulacionBuses()
        await wait("tres") { vm.busesAnimados.count == 3 }
        XCTAssertEqual(vm.busesAnimados.compactMap(\.occupancyVehicleID), ["observed"])
    }

    func testTrackingRetiradaInmediataLimpiaFichaYVelocidad() async {
        let observed = position("observed", origin: .observed)
        let provider = PresentationProvider([position(), observed])
        let vm = tracking(provider); defer { vm.stop() }
        await vm.requestPermissionAndStart()
        await wait("primero") { vm.vehiculos.count == 2 }
        vm.vehiculoSeleccionadoID = position().id
        provider.emit([observed])
        await wait("retirada sin throttle") { vm.vehiculos.count == 1 }
        XCTAssertNil(vm.vehiculoSeleccionadoID)
        XCTAssertNil(vm.vehiculoSeleccionado)
        XCTAssertEqual(Set(vm.velocidadesVehiculos.keys), ["observed"])
        provider.emit([])
        await wait("último vacío") { vm.vehiculos.isEmpty }
        XCTAssertTrue(vm.velocidadesVehiculos.isEmpty)
        XCTAssertEqual(vm.fuenteVehiculos, .real)
    }

    func testTrackingCambioRevisionCierraFichaAunqueNoCambienCoordenadas() async {
        let provider = PresentationProvider([position()])
        let vm = tracking(provider); defer { vm.stop() }
        await vm.requestPermissionAndStart()
        await wait("primero") { vm.vehiculos.count == 1 }
        vm.vehiculoSeleccionadoID = position().id
        provider.emit([position(revision: 4)])
        await wait("revisión") { vm.vehiculos.first?.controlRevision == 4 }
        XCTAssertNil(vm.vehiculoSeleccionadoID)
        XCTAssertNil(vm.vehiculoSeleccionado)
    }

    func testTrackingCeroYDesconocidoNoSeCalculanConRuidoGPS() async {
        let stopped = position(speed: 0)
        let provider = PresentationProvider([stopped])
        let vm = tracking(provider); defer { vm.stop() }
        await vm.requestPermissionAndStart()
        await wait("detenido") { vm.vehiculos.count == 1 }
        var noisy = stopped; noisy.lat += 0.001; noisy.timestamp += 5
        provider.emit([noisy])
        vm.actualizarActividadVisual(true)
        XCTAssertEqual(vm.velocidadesVehiculos[stopped.id], 0)
        noisy.speed = -1
        provider.emit([noisy])
        vm.actualizarActividadVisual(true)
        XCTAssertNil(vm.velocidadesVehiculos[stopped.id])
    }

    func testTrackingSnapshotAntiguoYReaperturaNoRevivenVehiculo() async {
        let values = [position()]
        let provider = PresentationProvider(values)
        let vm = tracking(provider); defer { vm.stop() }
        await vm.requestPermissionAndStart()
        await wait("primero") { vm.vehiculos.count == 1 }
        vm.vehiculoSeleccionadoID = values[0].id
        provider.allowSynthetic = false
        let reads = provider.presentationReads
        provider.yieldStale(values)
        await wait("revalidación") { provider.presentationReads > reads }
        XCTAssertTrue(vm.vehiculos.isEmpty)
        XCTAssertNil(vm.vehiculoSeleccionadoID)
        vm.suspenderPantalla()
        XCTAssertTrue(vm.velocidadesVehiculos.isEmpty)
        provider.initialOnStart = []
        await vm.requestPermissionAndStart()
        XCTAssertTrue(vm.vehiculos.isEmpty)
        XCTAssertEqual(vm.fuenteVehiculos, .real)
    }

    func testMapaQuinceMicrosEncuadreIncluyeTodaLaFlotaYOFFLoRetira() async throws {
        let values = (0..<15).map { index -> VehiclePosition in
            let base = position("sim:\(run):bus-\(index)")
            return VehiclePosition(id: base.id, linea: base.linea, routeId: base.routeId,
                lat: campus.latitude + Double(index) * 0.001,
                lon: campus.longitude - Double(index) * 0.002,
                timestamp: base.timestamp, dataOrigin: .simulated,
                simulationRunId: run, controlRevision: 3)
        }
        let provider = PresentationProvider(values)
        let vm = map(provider); defer { vm.detener() }
        XCTAssertNil(vm.encuadreDeMicros)
        vm.iniciarSimulacionBuses()
        await wait("quince micros") { vm.busesAnimados.count == 15 }
        let rect = try XCTUnwrap(vm.encuadreDeMicros)
        for bus in vm.busesAnimados { XCTAssertTrue(rect.contains(MKMapPoint(bus.coordinate))) }
        provider.allowSynthetic = false
        provider.yieldStale(values)
        await wait("OFF") { vm.busesAnimados.isEmpty }
        XCTAssertNil(vm.encuadreDeMicros)
    }

    func testLimiteVisibleConservaFlotaSeleccionYNoReiniciaProveedor() async {
        let defaults = UserDefaults(suiteName: "RutaUTP.MapLimit.\(UUID().uuidString)")!
        let preferences = MapVehiclePreferences(defaults: defaults)
        preferences.setLimit(.five)
        let provider = PresentationProvider((0..<15).map { position("sim:\(run):bus-\($0)") })
        let vm = map(provider, preferences: preferences); defer { vm.detener() }
        vm.iniciarSimulacionBuses()
        await wait("flota completa") { vm.busesAnimados.count == 15 }
        XCTAssertEqual(vm.busesEnMapa.count, 5)
        await wait("panel completo") { vm.busesDelPanel.count == 15 }
        XCTAssertEqual(vm.busesDelPanel.count, 15)
        vm.busSeleccionado = vm.busesAnimados.last
        XCTAssertEqual(vm.busesEnMapa.count, 5)
        XCTAssertTrue(vm.busesEnMapa.contains { $0.id == vm.busSeleccionado?.id })
        preferences.setLimit(.ten)
        XCTAssertEqual(vm.busesEnMapa.count, 10)
        XCTAssertEqual(vm.busesAnimados.count, 15)
        XCTAssertEqual(provider.starts, 1)
        provider.allowSynthetic = false
        provider.yieldStale(provider.currentPositions)
        await wait("retirada total") { vm.busesAnimados.isEmpty }
        XCTAssertTrue(vm.busesEnMapa.isEmpty)
        XCTAssertNil(vm.encuadreDeMicros)
    }

    func testLimiteCompartidoActualizaSeguimientoSinPerderSeleccion() async {
        let defaults = UserDefaults(suiteName: "RutaUTP.MapLimit.\(UUID().uuidString)")!
        let preferences = MapVehiclePreferences(defaults: defaults)
        let provider = PresentationProvider((0..<15).map { position("sim:\(run):bus-\($0)") })
        let vm = tracking(provider, preferences: preferences); defer { vm.stop() }
        await vm.requestPermissionAndStart()
        await wait("quince") { vm.vehiculos.count == 15 }
        vm.vehiculoSeleccionadoID = vm.vehiculos.last?.id
        preferences.setLimit(.five)
        XCTAssertEqual(vm.vehiculosEnMapa.count, 5)
        XCTAssertTrue(vm.vehiculosEnMapa.contains { $0.id == vm.vehiculoSeleccionadoID })
        XCTAssertEqual(vm.vehiculos.count, 15)
        preferences.setLimit(.all)
        XCTAssertEqual(vm.vehiculosEnMapa.count, 15)
    }

    func testTrackingQuinceRecibidosConservaTodaLaFlotaEnMapa() async {
        let provider = PresentationProvider((0..<15).map { position("sim:\(run):bus-\($0)") })
        let vm = tracking(provider); defer { vm.stop() }
        await vm.requestPermissionAndStart()
        await wait("quince") { vm.vehiculos.count == 15 }
        XCTAssertEqual(vm.vehiculosEnMapa.map(\.id), vm.vehiculos.map(\.id))
        XCTAssertEqual(vm.vehiculosEnMapa.count, 15)
    }
}

@MainActor
private final class PresentationProvider: VehicleTrackingProviding {
    let source: VehicleTrackingSource = .real
    var initialOnStart: [VehiclePosition]
    var allowSynthetic = true
    var keepsConnectionWhileMapHidden = false
    private(set) var currentPositions: [VehiclePosition] = []
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var presentationReads = 0
    private var stream: AsyncStream<[VehiclePosition]>?
    private var continuation: AsyncStream<[VehiclePosition]>.Continuation?

    init(_ initial: [VehiclePosition]) { initialOnStart = initial }
    func start() { starts += 1; currentPositions = initialOnStart; continuation?.yield(currentPositions) }
    func stop() {
        stops += 1
        currentPositions = []
        continuation?.finish(); continuation = nil; stream = nil
    }
    func positions() -> AsyncStream<[VehiclePosition]> {
        if let stream { return stream }
        let new = AsyncStream<[VehiclePosition]>(bufferingPolicy: .bufferingNewest(1)) { continuation = $0 }
        stream = new
        continuation?.yield(currentPositions)
        return new
    }
    func positionsForPresentation() -> [VehiclePosition] {
        presentationReads += 1
        return allowSynthetic ? currentPositions : currentPositions.filter { $0.dataOrigin != .simulated }
    }
    func emit(_ values: [VehiclePosition]) { currentPositions = values; continuation?.yield(values) }
    func yieldStale(_ values: [VehiclePosition]) { continuation?.yield(values) }
}

private actor PresentationCatalog: RutasGTFSProviding {
    let feed: [RutaGTFS]
    init(feed: [RutaGTFS]) { self.feed = feed }
    func rutas() async -> [RutaGTFS] { feed }
    func rutasQuePasanPor(_ punto: CLLocationCoordinate2D, radioMetros: Double) async -> [RutaGTFS] { feed }
}

@MainActor
private final class PresentationGPS: LocationServiceProtocol {
    let authorizationStatus: CLAuthorizationStatus = .denied
    var authorizationPublisher: AnyPublisher<CLAuthorizationStatus, Never> {
        Just(authorizationStatus).eraseToAnyPublisher()
    }
    func currentLocation() -> AsyncStream<CLLocation> { AsyncStream { $0.finish() } }
    func requestPermission() async -> CLAuthorizationStatus { authorizationStatus }
    func startUpdating() { }
    func stopUpdating() { }
}
