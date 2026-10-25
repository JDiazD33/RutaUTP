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

    private func map(_ provider: PresentationProvider) -> MapaViewModel {
        MapaViewModel(locationService: PresentationGPS(),
            repositorioGTFS: PresentationCatalog(feed: [route()]), crearProveedorReal: { provider })
    }

    private func tracking(_ provider: PresentationProvider) -> RouteTrackingViewModel {
        // Suite vacía exclusiva del test; no se escribe ningún valor persistente.
        let defaults = UserDefaults(suiteName: "RutaUTP.S08.\(UUID().uuidString)")!
        return RouteTrackingViewModel(locationService: PresentationGPS(), vehicleProvider: provider,
            repositorioGTFS: PresentationCatalog(feed: [route()]), defaults: defaults)
    }

    private func wait(_ description: String, _ condition: () -> Bool) async {
        for _ in 0..<400 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("No se completó: \(description)")
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

    func testTrackingDoceRecibidosSoloOchoMarcadores() async {
        let provider = PresentationProvider((0..<12).map { position("sim:\(run):bus-\($0)") })
        let vm = tracking(provider); defer { vm.stop() }
        await vm.requestPermissionAndStart()
        await wait("doce") { vm.vehiculos.count == 12 }
        XCTAssertEqual(vm.vehiculosEnMapa.count, 8)
        XCTAssertEqual(vm.vehiculos.count, 12)
    }
}

@MainActor
private final class PresentationProvider: VehicleTrackingProviding {
    let source: VehicleTrackingSource = .real
    var initialOnStart: [VehiclePosition]
    var allowSynthetic = true
    private(set) var currentPositions: [VehiclePosition] = []
    private(set) var starts = 0
    private(set) var presentationReads = 0
    private var stream: AsyncStream<[VehiclePosition]>?
    private var continuation: AsyncStream<[VehiclePosition]>.Continuation?

    init(_ initial: [VehiclePosition]) { initialOnStart = initial }
    func start() { starts += 1; currentPositions = initialOnStart; continuation?.yield(currentPositions) }
    func stop() {
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
