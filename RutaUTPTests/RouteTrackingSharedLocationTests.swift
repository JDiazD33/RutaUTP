import XCTest
import CoreLocation
import Combine
import SwiftUI
@testable import RutaUTP

/// El mismo GPS sirve a Tracking y a un segundo consumidor. Las continuaciones
/// permanecen retenidas hasta su cancelación, igual que en LocationService.
@MainActor
final class RouteTrackingSharedLocationTests: XCTestCase {
    func testRegistraLectorAntesDeIniciarYRecibePrimerFixSinCache() async {
        let gps = TrackingGPSMock()
        gps.primeraLectura = lectura(-8.101)
        let provider = TrackingVehiculosMock()
        let vm = modelo(gps, provider)
        defer { vm.stop() }
        let recibido = expectation(description: "primer fix inmediato")
        let observador = vm.$posicion.compactMap { $0 }.prefix(1).sink { _ in recibido.fulfill() }

        await vm.requestPermissionAndStart()
        await fulfillment(of: [recibido], timeout: 2)

        XCTAssertEqual(Array(gps.eventos.prefix(3)), ["permiso", "lector", "inicio"])
        XCTAssertEqual(vm.posicion?.latitude, -8.101)
        XCTAssertEqual(vm.estado, .listo)
        XCTAssertEqual(gps.paradasGlobales, 0)
        withExtendedLifetime(observador) {}
    }

    func testStopLiberaSoloTrackingYElConsumidorParaleloSigueRecibiendo() async {
        let liberado = expectation(description: "Tracking liberado")
        let gps = TrackingGPSMock()
        let externo = gps.currentLocation()
        gps.startUpdating()
        let provider = TrackingVehiculosMock()
        let vm = modelo(gps, provider)
        await vm.requestPermissionAndStart()
        XCTAssertEqual(gps.lectoresActivos, 2)
        gps.alLiberar = { liberado.fulfill() }

        vm.stop()
        await fulfillment(of: [liberado], timeout: 2)
        gps.alLiberar = nil

        XCTAssertEqual(gps.lectoresActivos, 1)
        XCTAssertTrue(gps.actualizando)
        XCTAssertEqual(gps.paradasGlobales, 0)
        gps.emitir(lectura(-8.102))
        var iterator = externo.makeAsyncIterator()
        let recibido = await iterator.next()
        XCTAssertEqual(recibido?.coordinate.latitude, -8.102)
        gps.finalizarLectores()
    }

    func testDeinitLiberaTrackingSinInterrumpirConsumidorParalelo() async {
        let liberado = expectation(description: "Tracking liberado en deinit")
        let gps = TrackingGPSMock()
        let externo = gps.currentLocation()
        gps.startUpdating()
        let provider = TrackingVehiculosMock()
        var vm: RouteTrackingViewModel? = modelo(gps, provider)
        await vm?.requestPermissionAndStart()
        weak let referencia = vm
        gps.alLiberar = { liberado.fulfill() }

        vm = nil
        await fulfillment(of: [liberado], timeout: 2)
        gps.alLiberar = nil

        XCTAssertNil(referencia)
        XCTAssertEqual(gps.lectoresActivos, 1)
        XCTAssertTrue(gps.actualizando)
        XCTAssertEqual(gps.paradasGlobales, 0)
        gps.emitir(lectura(-8.103))
        var iterator = externo.makeAsyncIterator()
        let recibido = await iterator.next()
        XCTAssertEqual(recibido?.coordinate.latitude, -8.103)
        gps.finalizarLectores()
    }

    func testStopDelUltimoConsumidorLiberaGPSYVehiculos() async {
        let gpsLiberado = expectation(description: "último GPS liberado")
        let busesLiberados = expectation(description: "vehículos liberados")
        let gps = TrackingGPSMock()
        let provider = TrackingVehiculosMock()
        let vm = modelo(gps, provider)
        await vm.requestPermissionAndStart()
        gps.alLiberar = { gpsLiberado.fulfill() }
        provider.alLiberar = { busesLiberados.fulfill() }

        vm.stop()
        await fulfillment(of: [gpsLiberado, busesLiberados], timeout: 2)

        XCTAssertEqual(gps.lectoresActivos, 0)
        XCTAssertFalse(gps.actualizando)
        XCTAssertEqual(gps.paradasGlobales, 0)
        XCTAssertEqual(provider.lectoresActivos, 0)
        XCTAssertFalse(provider.actualizando)
    }

    func testDeinitPuedeLiberarseConAmbosStreamsEsperandoDatos() async {
        let gpsLiberado = expectation(description: "GPS sin datos liberado")
        let busesLiberados = expectation(description: "buses sin datos liberados")
        let gps = TrackingGPSMock()
        let provider = TrackingVehiculosMock()
        var vm: RouteTrackingViewModel? = modelo(gps, provider)
        await vm?.requestPermissionAndStart()
        weak let referencia = vm
        gps.alLiberar = { gpsLiberado.fulfill() }
        provider.alLiberar = { busesLiberados.fulfill() }

        vm = nil
        await fulfillment(of: [gpsLiberado, busesLiberados], timeout: 2)

        XCTAssertNil(referencia)
        XCTAssertEqual(gps.lectoresActivos, 0)
        XCTAssertEqual(provider.lectoresActivos, 0)
        XCTAssertEqual(gps.paradasGlobales, 0)
    }

    func testProveedorPorDefectoConservaLaFuenteSimulada() {
        // Sin arrancarlo: no crea timers ni carga el catálogo real.
        let vm = RouteTrackingViewModel(locationService: TrackingGPSMock(),
                                        repositorioGTFS: TrackingCatalogoMock())
        XCTAssertEqual(vm.fuenteVehiculos, .simulated)
        XCTAssertTrue(vm.vehiculos.isEmpty)
    }

    func testModoDemoSinViajeSeRechazaYGPSContinua() async {
        let gps = TrackingGPSMock()
        let vm = modelo(gps)
        defer { vm.stop() }
        await vm.requestPermissionAndStart()
        vm.modoDemo = true
        // El comportamiento previo exige un viaje con geometría para activar
        // demo. Intentarlo antes no debe reemplazar ni apagar el GPS compartido.
        XCTAssertFalse(vm.modoDemo)
        let recibido = expectation(description: "GPS continúa sin viaje demo")
        let observador = vm.$posicion.compactMap { $0 }
            .filter { $0.latitude == -8.105 }.prefix(1).sink { _ in recibido.fulfill() }
        gps.emitir(lectura(-8.105))
        await fulfillment(of: [recibido], timeout: 2)
        XCTAssertEqual(vm.posicion?.latitude, -8.105)
        XCTAssertEqual(vm.estado, .listo)
        XCTAssertEqual(gps.lectoresActivos, 1)
        XCTAssertEqual(gps.paradasGlobales, 0)
        withExtendedLifetime(observador) {}
    }

    func testPermisoDenegadoNoUsaGPSYConservaFlotaDemo() async {
        let gps = TrackingGPSMock(permiso: .denied)
        let provider = TrackingVehiculosMock()
        provider.primeraEmision = [vehiculo("demo")]
        let vm = modelo(gps, provider)
        defer { vm.stop() }
        let recibido = expectation(description: "flota demo sin GPS")
        let observador = vm.$vehiculos.filter { !$0.isEmpty }.prefix(1).sink { _ in recibido.fulfill() }

        await vm.requestPermissionAndStart()
        await fulfillment(of: [recibido], timeout: 2)

        XCTAssertEqual(vm.estado, .sinPermiso)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertEqual(gps.eventos, ["permiso"])
        XCTAssertEqual(gps.lectoresActivos, 0)
        XCTAssertEqual(vm.vehiculos.map(\.id), ["demo"])
        XCTAssertEqual(vm.fuenteVehiculos, .simulated)
        XCTAssertEqual(Array(provider.eventos.suffix(2)), ["lector", "inicio"])
        withExtendedLifetime(observador) {}
    }

    func testCerrarDurantePermisoImpideArranqueTardio() async {
        let pedido = expectation(description: "permiso pendiente")
        let gps = TrackingGPSMock()
        gps.suspenderPermiso = true
        gps.alPedirPermiso = { _ in pedido.fulfill() }
        let provider = TrackingVehiculosMock()
        let catalogo = TrackingCatalogoMock()
        let vm = modelo(gps, provider, catalogo)
        let tarea = Task { await vm.requestPermissionAndStart() }
        await fulfillment(of: [pedido], timeout: 2)

        vm.stop()
        gps.resolverPermiso(0, como: .authorizedWhenInUse)
        await tarea.value

        XCTAssertEqual(gps.lectoresActivos, 0)
        XCTAssertEqual(gps.inicios, 0)
        XCTAssertEqual(provider.inicios, 0)
        let consultas = await catalogo.consultas
        XCTAssertEqual(consultas, 0)
        XCTAssertEqual(gps.paradasGlobales, 0)
    }

    func testTareaCanceladaAntesDeEntrarNoSolicitaPermiso() async {
        let gps = TrackingGPSMock()
        let provider = TrackingVehiculosMock()
        let vm = modelo(gps, provider)
        let tarea = Task { await vm.requestPermissionAndStart() }
        tarea.cancel()
        await tarea.value
        XCTAssertTrue(gps.eventos.isEmpty)
        XCTAssertEqual(provider.inicios, 0)
    }

    func testCancelarDurantePermisoImpideArranqueAunqueLlegaAutorizado() async {
        let pedido = expectation(description: "permiso pendiente")
        let gps = TrackingGPSMock()
        gps.suspenderPermiso = true
        gps.alPedirPermiso = { _ in pedido.fulfill() }
        let provider = TrackingVehiculosMock()
        let vm = modelo(gps, provider)
        let tarea = Task { await vm.requestPermissionAndStart() }
        await fulfillment(of: [pedido], timeout: 2)

        tarea.cancel()
        gps.resolverPermiso(0, como: .authorizedWhenInUse)
        await tarea.value

        XCTAssertEqual(gps.inicios, 0)
        XCTAssertEqual(gps.lectoresActivos, 0)
        XCTAssertEqual(provider.inicios, 0)
        XCTAssertEqual(gps.paradasGlobales, 0)
    }

    func testCancelarMientrasCargaFeedLiberaRecursosYaIniciados() async {
        let consultado = expectation(description: "feed pendiente")
        let gpsLiberado = expectation(description: "GPS cancelado")
        let busesLiberados = expectation(description: "vehículos cancelados")
        let gps = TrackingGPSMock()
        let provider = TrackingVehiculosMock()
        let catalogo = TrackingCatalogoMock(bloquear: true, alConsultar: { _ in consultado.fulfill() })
        let vm = modelo(gps, provider, catalogo)
        let tarea = Task { await vm.requestPermissionAndStart() }
        await fulfillment(of: [consultado], timeout: 2)
        XCTAssertEqual(gps.lectoresActivos, 1)
        XCTAssertEqual(provider.lectoresActivos, 1)
        gps.alLiberar = { gpsLiberado.fulfill() }
        provider.alLiberar = { busesLiberados.fulfill() }

        tarea.cancel()
        await catalogo.resolver(0, con: [ruta("obsoleta", color: "FF0000")])
        await tarea.value
        await fulfillment(of: [gpsLiberado, busesLiberados], timeout: 2)

        XCTAssertEqual(gps.lectoresActivos, 0)
        XCTAssertEqual(provider.lectoresActivos, 0)
        XCTAssertTrue(vm.coloresPorLinea.isEmpty)
        XCTAssertEqual(gps.paradasGlobales, 0)
    }

    func testPermisosSolapadosIgnoranLaRespuestaAnterior() async {
        let primerPedido = expectation(description: "primer permiso pendiente")
        let segundoPedido = expectation(description: "segundo permiso pendiente")
        let gps = TrackingGPSMock()
        gps.suspenderPermiso = true
        gps.alPedirPermiso = { ($0 == 0 ? primerPedido : segundoPedido).fulfill() }
        let provider = TrackingVehiculosMock()
        let catalogo = TrackingCatalogoMock()
        let vm = modelo(gps, provider, catalogo)
        defer { vm.stop() }
        let primera = Task { await vm.requestPermissionAndStart() }
        await fulfillment(of: [primerPedido], timeout: 2)
        let segunda = Task { await vm.requestPermissionAndStart() }
        await fulfillment(of: [segundoPedido], timeout: 2)

        gps.resolverPermiso(1, como: .authorizedWhenInUse)
        await segunda.value
        // La autorización global permanece concedida, pero el await viejo
        // devuelve denied para detectar si llega a escribir en el modelo.
        gps.resolverPermiso(0, como: .denied, cambiarEstado: false)
        await primera.value

        XCTAssertEqual(vm.authStatus, .authorizedWhenInUse)
        XCTAssertNotEqual(vm.estado, .sinPermiso)
        XCTAssertEqual(gps.inicios, 1)
        XCTAssertEqual(gps.lectoresActivos, 1)
        XCTAssertEqual(provider.inicios, 1)
        let consultas = await catalogo.consultas
        XCTAssertEqual(consultas, 1)
    }

    func testFeedsSolapadosNoSobrescribenCatalogoNuevoYReemplazanLectores() async {
        let primeraConsulta = expectation(description: "primer catálogo pendiente")
        let segundaConsulta = expectation(description: "segundo catálogo pendiente")
        let lectorViejo = expectation(description: "lector antiguo liberado")
        let gps = TrackingGPSMock()
        let provider = TrackingVehiculosMock()
        let catalogo = TrackingCatalogoMock(bloquear: true, alConsultar: {
            ($0 == 0 ? primeraConsulta : segundaConsulta).fulfill()
        })
        let vm = modelo(gps, provider, catalogo)
        defer { vm.stop() }
        let primera = Task { await vm.requestPermissionAndStart() }
        await fulfillment(of: [primeraConsulta], timeout: 2)
        gps.alLiberar = { lectorViejo.fulfill() }
        let segunda = Task { await vm.requestPermissionAndStart() }
        await fulfillment(of: [segundaConsulta, lectorViejo], timeout: 2)
        gps.alLiberar = nil
        await catalogo.resolver(1, con: [ruta("nueva", color: "00FF00")])
        await segunda.value
        await catalogo.resolver(0, con: [ruta("vieja", color: "FF0000")])
        await primera.value

        XCTAssertEqual(vm.coloresPorLinea, ["nueva": "00FF00"])
        XCTAssertEqual(gps.lectoresActivos, 1)
        XCTAssertEqual(provider.lectoresActivos, 1)
        XCTAssertEqual(gps.paradasGlobales, 0)
    }

    func testCompletarTareaAnteriorCanceladaNoDetieneNuevaEntrada() async {
        let primeraConsulta = expectation(description: "primer catálogo pendiente")
        let segundaConsulta = expectation(description: "segundo catálogo pendiente")
        let gps = TrackingGPSMock()
        let provider = TrackingVehiculosMock()
        let catalogo = TrackingCatalogoMock(bloquear: true, alConsultar: {
            ($0 == 0 ? primeraConsulta : segundaConsulta).fulfill()
        })
        let vm = modelo(gps, provider, catalogo)
        defer { vm.stop() }
        let primera = Task { await vm.requestPermissionAndStart() }
        await fulfillment(of: [primeraConsulta], timeout: 2)
        primera.cancel()
        let segunda = Task { await vm.requestPermissionAndStart() }
        await fulfillment(of: [segundaConsulta], timeout: 2)
        await catalogo.resolver(1, con: [])
        await segunda.value
        let paradasAntes = provider.paradas
        await catalogo.resolver(0, con: [])
        await primera.value

        let recibido = expectation(description: "nueva entrada recibe ubicación")
        let observador = vm.$posicion.compactMap { $0 }.prefix(1).sink { _ in recibido.fulfill() }
        gps.emitir(lectura(-8.106))
        await fulfillment(of: [recibido], timeout: 2)
        XCTAssertEqual(vm.posicion?.latitude, -8.106)
        XCTAssertEqual(gps.lectoresActivos, 1)
        XCTAssertEqual(provider.lectoresActivos, 1)
        XCTAssertEqual(provider.paradas, paradasAntes)
        XCTAssertTrue(provider.actualizando)
        withExtendedLifetime(observador) {}
    }

    func testReentrarTrasStopsRepetidosNoDejaLectoresYRecibeFixNuevo() async {
        let gps = TrackingGPSMock()
        let provider = TrackingVehiculosMock()
        let vm = modelo(gps, provider)
        defer { vm.stop() }
        await vm.requestPermissionAndStart()
        let liberado = expectation(description: "primer lector liberado")
        gps.alLiberar = { liberado.fulfill() }
        vm.stop()
        vm.stop()
        await fulfillment(of: [liberado], timeout: 2)
        gps.alLiberar = nil
        XCTAssertEqual(gps.lectoresActivos, 0)
        XCTAssertEqual(provider.lectoresActivos, 0)

        gps.primeraLectura = lectura(-8.107)
        let recibido = expectation(description: "primer fix tras reentrada")
        let observador = vm.$posicion.compactMap { $0 }.prefix(1).sink { _ in recibido.fulfill() }
        await vm.requestPermissionAndStart()
        await fulfillment(of: [recibido], timeout: 2)
        XCTAssertEqual(vm.posicion?.latitude, -8.107)
        XCTAssertEqual(gps.lectoresActivos, 1)
        XCTAssertEqual(provider.lectoresActivos, 1)
        XCTAssertEqual(gps.paradasGlobales, 0)
        withExtendedLifetime(observador) {}
    }

    func testSegundaEntradaSinStopRenuevaStreamDeVehiculosYRecibeFlotaNueva() async {
        let gps = TrackingGPSMock()
        let provider = TrackingVehiculosMock()
        let vm = modelo(gps, provider)
        defer { vm.stop() }
        await vm.requestPermissionAndStart()
        let anterior = expectation(description: "primera flota")
        let observadorAnterior = vm.$vehiculos.filter { $0.first?.id == "anterior" }
            .prefix(1).sink { _ in anterior.fulfill() }
        provider.emitir([vehiculo("anterior")])
        await fulfillment(of: [anterior], timeout: 2)

        // positions() cachea el stream hasta stop, como los providers reales.
        // Solo cancelar el primer task daría al segundo un stream terminado.
        await vm.requestPermissionAndStart()
        let nuevo = expectation(description: "flota de la segunda entrada")
        let observadorNuevo = vm.$vehiculos.filter { $0.first?.id == "nuevo" }
            .prefix(1).sink { _ in nuevo.fulfill() }
        provider.emitir([vehiculo("nuevo")])
        await fulfillment(of: [nuevo], timeout: 2)

        XCTAssertEqual(vm.vehiculos.map(\.id), ["nuevo"])
        XCTAssertEqual(provider.lectoresActivos, 1)
        XCTAssertEqual(gps.lectoresActivos, 1)
        XCTAssertEqual(gps.paradasGlobales, 0)
        withExtendedLifetime((observadorAnterior, observadorNuevo)) {}
    }

    func testNuevaEntradaLiberaGPSAnteriorAntesDeEsperarOtroPermiso() async {
        let gps = TrackingGPSMock()
        let provider = TrackingVehiculosMock()
        let vm = modelo(gps, provider)
        defer { vm.stop() }
        await vm.requestPermissionAndStart()
        let liberado = expectation(description: "GPS anterior cancelado")
        let pedido = expectation(description: "segundo permiso pendiente")
        gps.alLiberar = { liberado.fulfill() }
        gps.suspenderPermiso = true
        gps.alPedirPermiso = { _ in pedido.fulfill() }
        let segunda = Task { await vm.requestPermissionAndStart() }
        await fulfillment(of: [liberado, pedido], timeout: 2)
        gps.alLiberar = nil

        XCTAssertEqual(gps.lectoresActivos, 0)
        XCTAssertFalse(gps.actualizando)
        XCTAssertEqual(provider.lectoresActivos, 0)
        XCTAssertEqual(gps.paradasGlobales, 0)
        gps.emitir(lectura(-8.108))
        gps.resolverPermiso(1, como: .authorizedWhenInUse)
        await segunda.value
        XCTAssertNil(vm.posicion)
        XCTAssertEqual(gps.lectoresActivos, 1)
        XCTAssertEqual(provider.lectoresActivos, 1)
    }

    private func modelo(_ gps: TrackingGPSMock,
                        _ provider: TrackingVehiculosMock = TrackingVehiculosMock(),
                        _ catalogo: TrackingCatalogoMock = TrackingCatalogoMock()) -> RouteTrackingViewModel {
        RouteTrackingViewModel(locationService: gps, vehicleProvider: provider, repositorioGTFS: catalogo)
    }

    private func lectura(_ latitude: Double) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: -79.03),
                   altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                   course: 90, speed: 4, timestamp: Date())
    }

    private func vehiculo(_ id: String) -> VehiclePosition {
        VehiclePosition(id: id, linea: "demo", lat: -8.10, lon: -79.03)
    }

    private func ruta(_ linea: String, color: String) -> RutaGTFS {
        RutaGTFS(id: linea, linea: linea, variante: "", recorrido: "Prueba", empresa: "Prueba",
                 colorHex: color, color: .green, shape: [], paraderos: [], duracionMin: 1,
                 headwayMin: 1, precio: 1, distanciaKm: 1, distanciaUTPMetros: 0)
    }
}

private final class TrackingGPSMock: LocationServiceProtocol {
    private let permisos: CurrentValueSubject<CLAuthorizationStatus, Never>
    private let registro = RegistroTracking<CLLocation>()
    private var pendientes: [Int: CheckedContinuation<CLAuthorizationStatus, Never>] = [:]
    private var numeroPermisos = 0
    var suspenderPermiso = false
    var primeraLectura: CLLocation?
    var alPedirPermiso: ((Int) -> Void)?

    init(permiso: CLAuthorizationStatus = .authorizedWhenInUse) {
        permisos = CurrentValueSubject(permiso)
    }
    var authorizationStatus: CLAuthorizationStatus { permisos.value }
    var authorizationPublisher: AnyPublisher<CLAuthorizationStatus, Never> { permisos.eraseToAnyPublisher() }
    var eventos: [String] { registro.instantanea.eventos }
    var lectoresActivos: Int { registro.instantanea.lectores }
    var actualizando: Bool { registro.instantanea.actualizando }
    var inicios: Int { eventos.filter { $0 == "inicio" }.count }
    var paradasGlobales: Int { eventos.filter { $0 == "parada" }.count }
    var alLiberar: (() -> Void)? {
        get { registro.alLiberar }
        set { registro.alLiberar = newValue }
    }
    func requestPermission() async -> CLAuthorizationStatus {
        registro.evento("permiso")
        let indice = numeroPermisos
        numeroPermisos += 1
        guard suspenderPermiso else { return authorizationStatus }
        return await withCheckedContinuation { continuation in
            pendientes[indice] = continuation
            alPedirPermiso?(indice)
        }
    }
    func resolverPermiso(_ indice: Int, como permiso: CLAuthorizationStatus, cambiarEstado: Bool = true) {
        if cambiarEstado { permisos.send(permiso) }
        pendientes.removeValue(forKey: indice)?.resume(returning: permiso)
    }
    func currentLocation() -> AsyncStream<CLLocation> { registro.stream() }
    func startUpdating() {
        registro.iniciar()
        if let primeraLectura { registro.emitir(primeraLectura) }
    }
    func stopUpdating() { registro.parar() }
    func emitir(_ location: CLLocation) { registro.emitir(location) }
    func finalizarLectores() { registro.finalizar() }
}

private final class TrackingVehiculosMock: VehicleTrackingProviding {
    let source: VehicleTrackingSource = .simulated
    private let registro = RegistroTracking<[VehiclePosition]>()
    private var streamCacheado: AsyncStream<[VehiclePosition]>?
    private(set) var currentPositions: [VehiclePosition] = []
    var primeraEmision: [VehiclePosition]?
    var eventos: [String] { registro.instantanea.eventos }
    var inicios: Int { eventos.filter { $0 == "inicio" }.count }
    var paradas: Int { eventos.filter { $0 == "parada" }.count }
    var lectoresActivos: Int { registro.instantanea.lectores }
    var actualizando: Bool { registro.instantanea.actualizando }
    var alLiberar: (() -> Void)? {
        get { registro.alLiberar }
        set { registro.alLiberar = newValue }
    }
    func positions() -> AsyncStream<[VehiclePosition]> {
        if let streamCacheado { return streamCacheado }
        let stream = registro.stream()
        streamCacheado = stream
        return stream
    }
    func start() {
        registro.iniciar()
        if let primeraEmision {
            currentPositions = primeraEmision
            registro.emitir(primeraEmision)
        }
    }
    func stop() {
        registro.parar()
        streamCacheado = nil
    }
    func emitir(_ posiciones: [VehiclePosition]) {
        currentPositions = posiciones
        registro.emitir(posiciones)
    }
}

/// Un catálogo controlado que termina incluso si su caller fue cancelado.
/// Esto obliga al consumidor a rechazar por sí mismo las respuestas tardías.
private actor TrackingCatalogoMock: RutasGTFSProviding {
    private let bloquear: Bool
    private let alConsultar: (Int) -> Void
    private var pendientes: [Int: CheckedContinuation<[RutaGTFS], Never>] = [:]
    private(set) var consultas = 0

    init(bloquear: Bool = false, alConsultar: @escaping (Int) -> Void = { _ in }) {
        self.bloquear = bloquear
        self.alConsultar = alConsultar
    }
    func rutas() async -> [RutaGTFS] {
        let indice = consultas
        consultas += 1
        guard bloquear else { return [] }
        return await withCheckedContinuation { continuation in
            pendientes[indice] = continuation
            alConsultar(indice)
        }
    }
    func resolver(_ indice: Int, con rutas: [RutaGTFS]) {
        pendientes.removeValue(forKey: indice)?.resume(returning: rutas)
    }
    func rutasQuePasanPor(_ punto: CLLocationCoordinate2D, radioMetros: Double) async -> [RutaGTFS] { [] }
}

/// onTermination puede llegar desde el ejecutor del consumidor: el registro
/// se protege con un lock y nunca hace yield/finish ni callbacks bajo ese lock.
private final class RegistroTracking<Element>: @unchecked Sendable {
    struct Instantanea {
        let eventos: [String]
        let lectores: Int
        let actualizando: Bool
    }
    private let candado = NSLock()
    private var continuaciones: [UUID: AsyncStream<Element>.Continuation] = [:]
    private var eventos: [String] = []
    private var actualizando = false
    private var callbackLiberar: (() -> Void)?

    var instantanea: Instantanea {
        candado.lock()
        defer { candado.unlock() }
        return Instantanea(eventos: eventos, lectores: continuaciones.count, actualizando: actualizando)
    }
    var alLiberar: (() -> Void)? {
        get {
            candado.lock()
            defer { candado.unlock() }
            return callbackLiberar
        }
        set {
            candado.lock()
            callbackLiberar = newValue
            candado.unlock()
        }
    }
    func evento(_ nombre: String) {
        candado.lock()
        eventos.append(nombre)
        candado.unlock()
    }
    func stream() -> AsyncStream<Element> {
        let id = UUID()
        return AsyncStream { continuation in
            continuation.onTermination = { [weak self] _ in self?.liberar(id) }
            candado.lock()
            continuaciones[id] = continuation
            eventos.append("lector")
            candado.unlock()
        }
    }
    private func liberar(_ id: UUID) {
        candado.lock()
        let existia = continuaciones.removeValue(forKey: id) != nil
        if continuaciones.isEmpty { actualizando = false }
        let callback = callbackLiberar
        candado.unlock()
        if existia { callback?() }
    }
    func iniciar() {
        candado.lock()
        actualizando = true
        eventos.append("inicio")
        candado.unlock()
    }
    func parar() {
        candado.lock()
        actualizando = false
        eventos.append("parada")
        candado.unlock()
        finalizar()
    }
    private var activas: [AsyncStream<Element>.Continuation] {
        candado.lock()
        defer { candado.unlock() }
        return Array(continuaciones.values)
    }
    func emitir(_ element: Element) { activas.forEach { $0.yield(element) } }
    func finalizar() { activas.forEach { $0.finish() } }
}
