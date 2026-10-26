import XCTest
import CoreLocation
import Combine
import Observation
import SwiftUI
import UIKit
import MapKit
import CocoaMQTT
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
        let observador = ExpectativaObservada(recibido) { vm.posicion?.latitude == -8.101 }

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
        let observador = ExpectativaObservada(recibido) { vm.posicion?.latitude == -8.105 }
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
        let observador = ExpectativaObservada(recibido) { !vm.vehiculos.isEmpty }

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
        let observador = ExpectativaObservada(recibido) { vm.posicion?.latitude == -8.106 }
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
        let observador = ExpectativaObservada(recibido) { vm.posicion?.latitude == -8.107 }
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
        let observadorAnterior = ExpectativaObservada(anterior) { vm.vehiculos.first?.id == "anterior" }
        provider.emitir([vehiculo("anterior")])
        await fulfillment(of: [anterior], timeout: 2)

        // positions() cachea el stream hasta stop, como los providers reales.
        // Solo cancelar el primer task daría al segundo un stream terminado.
        await vm.requestPermissionAndStart()
        let nuevo = expectation(description: "flota de la segunda entrada")
        let observadorNuevo = ExpectativaObservada(nuevo) { vm.vehiculos.first?.id == "nuevo" }
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
                        _ provider: TrackingVehiculosMock? = nil,
                        _ catalogo: TrackingCatalogoMock = TrackingCatalogoMock()) -> RouteTrackingViewModel {
        RouteTrackingViewModel(locationService: gps, vehicleProvider: provider ?? TrackingVehiculosMock(),
                               repositorioGTFS: catalogo)
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

/// Observation notifica antes de la escritura. El salto a MainActor comprueba
/// el estado ya actualizado y vuelve a registrar si aún no cumple la condición.
/// Cada expectativa se satisface una vez y el callback no retiene al observador.
@MainActor
private final class ExpectativaObservada {
    private var expectativa: XCTestExpectation?
    private let condicion: @MainActor () -> Bool

    init(_ expectativa: XCTestExpectation, condicion: @escaping @MainActor () -> Bool) {
        self.expectativa = expectativa
        self.condicion = condicion
        comprobar()
    }

    private func comprobar() {
        guard let expectativa else { return }
        let cumple = withObservationTracking {
            condicion()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.comprobar() }
        }
        if cumple {
            self.expectativa = nil
            expectativa.fulfill()
        }
    }
}

/// Aloja las pestañas productivas: verifica la retención del mapa y la
/// liberación del GPS con los mismos eventos de aparición que usa la app.
@MainActor
final class MainTabNavigationTests: XCTestCase {
    func testAbrirYCerrarMenuConservaElEncuadreYLaAlturaDelMapa() async throws {
        let menu = MainTabsMenuTestState()
        let sesion = try MainTabsTestWindow(mapMenu: menu)
        defer { sesion.cerrar() }
        try await esperarEstado {
            sesion.mapaVisible != nil && sesion.bordeInferiorPestanas != nil &&
            sesion.gps.lectoresActivos == 1 && !sesion.barraNativaVisible
        }
        let mapa = try XCTUnwrap(sesion.mapaVisible)
        try await esperarEncuadreEstable(mapa, en: sesion.ventana)
        let encuadreInicial = MainTabsMapSnapshot(mapa, en: sesion.ventana)
        let bordeInicial = try XCTUnwrap(sesion.bordeInferiorPestanas)
        let iniciosGPS = sesion.gps.inicios
        let paradasGPS = sesion.gps.paradasGlobales

        // Comprobar también mientras está abierto: comparar solo antes y
        // después del cierre no detecta un mapa que crece y vuelve a encogerse.
        for abierto in [true, false, true, false] {
            menu.isOpen = abierto
            await siguienteActualizacionUI()
            try await esperarEncuadreEstable(mapa, en: sesion.ventana)
            let estado = abierto ? "con el menú abierto" : "tras cerrar el menú"
            let actual = MainTabsMapSnapshot(mapa, en: sesion.ventana)
            XCTAssertTrue(sesion.mapaVisible === mapa, "Debe conservar el mismo MKMapView \(estado)")
            XCTAssertTrue(actual.coincide(con: encuadreInicial), "El marco, la región y la cámara deben conservarse \(estado). Antes: \(encuadreInicial). Ahora: \(actual)")
            XCTAssertEqual(try XCTUnwrap(sesion.bordeInferiorPestanas), bordeInicial, accuracy: 0.5,
                           "El menú no debe retirar ni ampliar la fila inferior")
            XCTAssertFalse(sesion.barraNativaVisible, estado)
            XCTAssertEqual(sesion.gps.lectoresActivos, 1, estado)
            XCTAssertEqual(sesion.gps.inicios, iniciosGPS, "El menú no debe reiniciar el GPS")
            XCTAssertEqual(sesion.gps.paradasGlobales, paradasGPS, "El menú no debe detener el GPS")
        }

        menu.isOpen = true
        await siguienteActualizacionUI()
        sesion.router.navigate(to: .rutas)
        try await esperarEstado { !menu.isOpen && sesion.indiceVisible == 1 }
    }

    func testTomarRutaOcultaLaFilaInferiorYLaRecuperaAlTerminar() async throws {
        let defaults = UserDefaults.standard
        let consentimiento = "rutautp.passive-tracking-consent"
        let claves = [consentimiento, BoardingPlaceStore.key]
        let anteriores = claves.reduce(into: [String: Any]()) { guardados, clave in
            guardados[clave] = defaults.object(forKey: clave)
        }
        defaults.set(true, forKey: consentimiento)
        defer {
            for clave in claves {
                if let anterior = anteriores[clave] { defaults.set(anterior, forKey: clave) }
                else { defaults.removeObject(forKey: clave) }
            }
        }

        let publicador = MainTabsObservationPublisherMock()
        let sesion = try MainTabsTestWindow(observationPublisher: publicador)
        defer { sesion.cerrar() }
        try await esperarEstado { sesion.mapaVisible != nil && sesion.bordeInferiorPestanas != nil }
        let bordeNormal = try XCTUnwrap(sesion.bordeInferiorPestanas)
        let bordeVentana = sesion.ventana.bounds.maxY
        XCTAssertLessThan(bordeNormal, bordeVentana - 20, "La navegación normal ocupa su propia fila")

        let ruta = DetectionRouteGeometry(id: "test-footer-trip", linea: "Prueba",
            shape: [CLLocationCoordinate2D(latitude: -8.10, longitude: -79.04),
                    CLLocationCoordinate2D(latitude: -8.10, longitude: -79.02)], stops: [])
        sesion.coordinador.beginTrip(route: ruta, occupancy: nil)
        XCTAssertEqual(sesion.coordinador.selectedTripRoute?.id, ruta.id)
        try await esperarEstado {
            guard let borde = sesion.bordeInferiorPestanas else { return false }
            return abs(borde - bordeVentana) <= 1
        }
        let mapa = try XCTUnwrap(sesion.mapaVisible)
        XCTAssertEqual(mapa.convert(mapa.bounds, to: sesion.ventana).maxY, bordeVentana, accuracy: 1)
        XCTAssertFalse(sesion.barraNativaVisible)
        XCTAssertEqual(publicador.inicios, 0, "Elegir la ruta no publica ni abre una conexión")
        await adjuntarCaptura(sesion, nombre: "Viaje-sin-fila-inferior")

        sesion.coordinador.endTrip()
        try await esperarEstado {
            guard let borde = sesion.bordeInferiorPestanas else { return false }
            return abs(borde - bordeNormal) <= 1
        }
        XCTAssertFalse(sesion.barraNativaVisible)
        await adjuntarCaptura(sesion, nombre: "Mapa-tras-finalizar-viaje")
    }

    func testRecorrerLasCincoPestanasConservaMapaYLiberaGPSEnLasOcultas() async throws {
        let sesion = try MainTabsTestWindow()
        defer { sesion.cerrar() }
        try await esperarEstado { sesion.indiceVisible == 0 && sesion.gps.lectoresActivos == 1 && sesion.mapaVisible != nil && !sesion.barraNativaVisible }
        XCTAssertFalse(sesion.barraNativaVisible, "La barra nativa no debe superponerse a la navegación de RutaUTP")
        let mapaInicial = try XCTUnwrap(sesion.mapaVisible)
        await adjuntarCaptura(sesion, nombre: "MainTabs-Mapa")

        let recorrido: [(AppScreen, Int, String)] = [
            (.rutas, 1, "Rutas"), (.guardado, 2, "Guardado"),
            (.seguridad, 3, "Seguridad"), (.perfil, 4, "Perfil")
        ]
        for vuelta in 0..<2 {
            for (pantalla, indice, nombre) in recorrido {
                sesion.router.navigate(to: pantalla)
                try await esperarEstado { sesion.indiceVisible == indice && sesion.gps.lectoresActivos == 0 && !sesion.barraNativaVisible }
                XCTAssertFalse(sesion.barraNativaVisible, nombre)
                XCTAssertFalse(sesion.gps.actualizando, nombre)
                if vuelta == 0 { await adjuntarCaptura(sesion, nombre: "MainTabs-\(nombre)") }
            }
            sesion.router.navigate(to: .mapaPrincipal)
            try await esperarEstado { sesion.indiceVisible == 0 && sesion.gps.lectoresActivos == 1 && sesion.mapaVisible != nil && !sesion.barraNativaVisible }
            XCTAssertFalse(sesion.barraNativaVisible, "Volver al mapa conserva una sola barra de navegación")
            XCTAssertTrue(sesion.mapaVisible === mapaInicial, "Volver al mapa debe reutilizar el mismo MKMapView")
        }
        XCTAssertEqual(sesion.gps.paradasGlobales, 0, "Salir de una pestaña cancela su lector, sin apagar otros consumidores")
    }

    func testLosDestinosPendientesSeConsumenSoloAlAbrirSuPestana() async throws {
        let sesion = try MainTabsTestWindow()
        defer { sesion.cerrar() }
        try await esperarEstado { sesion.indiceVisible == 0 && sesion.gps.lectoresActivos == 1 }
        sesion.router.navigate(to: .guardado)
        try await esperarEstado { sesion.indiceVisible == 2 && sesion.gps.lectoresActivos == 0 }

        let destino = DestinoPendiente(titulo: "Destino de integración", lat: -8.10, lon: -79.04)
        sesion.router.destinoPendiente = destino
        sesion.router.lugarCercanoPendiente = destino
        // Dejar que SwiftUI entregue onChange a las vistas conservadas antes
        // de comprobar que ninguna pestaña oculta consumió la petición.
        await siguienteActualizacionUI()
        await siguienteActualizacionUI()
        XCTAssertEqual(sesion.router.destinoPendiente, destino)
        XCTAssertEqual(sesion.router.lugarCercanoPendiente, destino)

        sesion.router.navigate(to: .rutas)
        try await esperarEstado { sesion.indiceVisible == 1 && sesion.router.lugarCercanoPendiente == nil }
        XCTAssertEqual(sesion.router.destinoPendiente, destino)
        XCTAssertEqual(sesion.gps.lectoresActivos, 0)

        sesion.router.navigate(to: .mapaPrincipal)
        try await esperarEstado { sesion.indiceVisible == 0 && sesion.router.destinoPendiente == nil && sesion.gps.lectoresActivos == 1 }
    }

    private func esperarEstado(archivo: StaticString = #filePath, linea: UInt = #line,
                               _ condicion: () -> Bool) async throws {
        let limite = ContinuousClock.now.advanced(by: .seconds(3))
        while !condicion() {
            guard ContinuousClock.now < limite else {
                XCTFail("La interfaz no alcanzó el estado esperado", file: archivo, line: linea)
                throw ErrorNavegacion.agotado
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func siguienteActualizacionUI() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60.0) { continuation.resume() }
        }
    }

    private func esperarEncuadreEstable(_ mapa: MKMapView, en ventana: UIWindow) async throws {
        let limite = ContinuousClock.now.advanced(by: .seconds(3))
        var anterior = MainTabsMapSnapshot(mapa, en: ventana)
        var estableDesde = ContinuousClock.now
        while ContinuousClock.now < limite {
            await siguienteActualizacionUI()
            let actual = MainTabsMapSnapshot(mapa, en: ventana)
            if !actual.coincide(con: anterior) {
                estableDesde = .now
                anterior = actual
            }
            if estableDesde.duration(to: .now) >= .milliseconds(450) { return }
        }
        XCTFail("El mapa no terminó de ajustar su encuadre inicial")
        throw ErrorNavegacion.agotado
    }

    private func adjuntarCaptura(_ sesion: MainTabsTestWindow, nombre: String) async {
        await siguienteActualizacionUI()
        sesion.ventana.layoutIfNeeded()
        let imagen = UIGraphicsImageRenderer(bounds: sesion.ventana.bounds).image { _ in
            sesion.ventana.drawHierarchy(in: sesion.ventana.bounds, afterScreenUpdates: true)
        }
        let adjunto = XCTAttachment(image: imagen)
        adjunto.name = nombre
        adjunto.lifetime = .keepAlways
        add(adjunto)
    }

    private enum ErrorNavegacion: Error { case agotado }
}

@MainActor
private final class MainTabsTestWindow {
    let gps = TrackingGPSMock()
    let router = AppRouter()
    let ventana: UIWindow
    let coordinador: PassiveTrackingCoordinator
    private let ventanaAnterior: UIWindow?

    init(pantalla: AppScreen = .mapaPrincipal, observationPublisher: ObservationPublishing? = nil,
         mapMenu: MainTabsMenuTestState? = nil) throws {
        let escena = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        ventanaAnterior = escena.windows.first(where: \.isKeyWindow)
        ventana = UIWindow(windowScene: escena)
        ventana.frame = escena.coordinateSpace.bounds
        coordinador = PassiveTrackingCoordinator(locationService: gps, observationPublisher: observationPublisher,
                                                tripOccupancy: OccupancyService(configurationProvider: { nil }),
                                                configurationProvider: { nil },
                                                preserveStoredConsentWhenUnconfigured: true)
        router.currentScreen = pantalla
        let menuBinding = mapMenu.map { menu in
            Binding(get: { menu.isOpen }, set: { menu.isOpen = $0 })
        }
        let contenido = RootView(locationService: gps, router: router, mapMenu: menuBinding)
            .environmentObject(coordinador)
            .environment(\.scenePhase, .active)
        ventana.rootViewController = UIHostingController(rootView: contenido)
        ventana.makeKeyAndVisible()
        ventana.layoutIfNeeded()
    }

    var indiceVisible: Int? { controladorPestanas(ventana.rootViewController)?.selectedIndex }

    var barraNativaVisible: Bool {
        guard let barra = controladorPestanas(ventana.rootViewController)?.tabBar,
              barra.window === ventana, !barra.bounds.isEmpty else { return false }
        var actual: UIView? = barra
        while let vista = actual {
            if vista.isHidden || vista.alpha <= 0.01 { return false }
            actual = vista.superview
        }
        return barra.convert(barra.bounds, to: ventana).intersects(ventana.bounds)
    }

    var mapaVisible: MKMapView? { buscarMapa(en: ventana) }

    var bordeInferiorPestanas: CGFloat? {
        guard let vista = controladorPestanas(ventana.rootViewController)?.view else { return nil }
        return vista.convert(vista.bounds, to: ventana).maxY
    }

    func cerrar() {
        ventana.isHidden = true
        ventana.rootViewController = nil
        coordinador.stop()
        gps.finalizarLectores()
        ventanaAnterior?.makeKey()
    }

    private func controladorPestanas(_ controlador: UIViewController?) -> UITabBarController? {
        guard let controlador else { return nil }
        if let pestanas = controlador as? UITabBarController { return pestanas }
        for hijo in controlador.children {
            if let pestanas = controladorPestanas(hijo) { return pestanas }
        }
        return nil
    }

    private func buscarMapa(en vista: UIView) -> MKMapView? {
        guard !vista.isHidden, vista.alpha > 0 else { return nil }
        if let mapa = vista as? MKMapView { return mapa }
        for hija in vista.subviews {
            if let mapa = buscarMapa(en: hija) { return mapa }
        }
        return nil
    }
}

@Observable
private final class MainTabsMenuTestState {
    var isOpen = false
}

@MainActor
private struct MainTabsMapSnapshot {
    let frame: CGRect
    let region: MKCoordinateRegion
    let altitude: CLLocationDistance
    let heading: CLLocationDirection
    let pitch: CGFloat

    init(_ mapa: MKMapView, en ventana: UIWindow) {
        frame = mapa.convert(mapa.bounds, to: ventana)
        region = mapa.region
        altitude = mapa.camera.altitude
        heading = mapa.camera.heading
        pitch = mapa.camera.pitch
    }

    func coincide(con otro: Self) -> Bool {
        abs(frame.minX - otro.frame.minX) <= 0.5 &&
        abs(frame.minY - otro.frame.minY) <= 0.5 &&
        abs(frame.width - otro.frame.width) <= 0.5 &&
        abs(frame.height - otro.frame.height) <= 0.5 &&
        abs(region.center.latitude - otro.region.center.latitude) <= 0.000001 &&
        abs(region.center.longitude - otro.region.center.longitude) <= 0.000001 &&
        abs(region.span.latitudeDelta - otro.region.span.latitudeDelta) <= 0.000001 &&
        abs(region.span.longitudeDelta - otro.region.span.longitudeDelta) <= 0.000001 &&
        abs(altitude - otro.altitude) <= 0.5 &&
        abs(heading - otro.heading) <= 0.01 &&
        abs(pitch - otro.pitch) <= 0.01
    }
}

@MainActor
private final class MainTabsObservationPublisherMock: ObservationPublishing {
    var state: ObservationPublisherState = .inactive
    var onStateChange: (@MainActor (ObservationPublisherState) -> Void)?
    private(set) var inicios = 0

    func start(sessionID: String, linea: String) { inicios += 1 }
    func publish(location: CLLocation, routeID: String, activity: DetectedMotionActivity) {}
    func stop() {}
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


@MainActor
final class PreferenciasTrackingTests: XCTestCase {
    private func conPreferencias(_ comprobar: (UserDefaults) throws -> Void) throws {
        let suite = "RutaUTPTests.TrackingPreferencias.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try comprobar(defaults)
    }

    private func modelo(_ defaults: UserDefaults) -> RouteTrackingViewModel {
        RouteTrackingViewModel(locationService: TrackingGPSMock(),
            vehicleProvider: TrackingVehiculosMock(), defaults: defaults)
    }

    func testValoresInvalidosNoCambianEstadoNiPreferencias() throws {
        try conPreferencias { defaults in
            defaults.set(3.0, forKey: "tracking.velocidadDemo")
            defaults.set(800.0, forKey: "tracking.radioParadero")
            let vm = modelo(defaults)
            for valor in [0.0, -1, 2, Double.nan, .infinity, -.infinity] {
                vm.velocidadDemo = valor
                vm.radioParadero = valor
                XCTAssertEqual(vm.velocidadDemo, 3)
                XCTAssertEqual(vm.radioParadero, 800)
                XCTAssertEqual(defaults.double(forKey: "tracking.velocidadDemo"), 3)
                XCTAssertEqual(defaults.double(forKey: "tracking.radioParadero"), 800)
            }
        }
    }

    func testOpcionesPermitidasPersistenYElCambioSigueSiendoObservable() throws {
        try conPreferencias { defaults in
            let vm = modelo(defaults)
            let cambio = expectation(description: "Cambio observado del multiplicador")
            withObservationTracking { _ = vm.velocidadDemo } onChange: { cambio.fulfill() }
            vm.velocidadDemo = 3
            wait(for: [cambio], timeout: 1)
            for velocidad in RouteTrackingViewModel.Preferencia.velocidad.valoresPermitidos {
                vm.velocidadDemo = velocidad
                XCTAssertEqual(modelo(defaults).velocidadDemo, velocidad)
            }
            for radio in RouteTrackingViewModel.Preferencia.radio.valoresPermitidos {
                vm.radioParadero = radio
                XCTAssertEqual(modelo(defaults).radioParadero, radio)
            }
        }
    }

    func testOriginalIncompatibleNoSeSobrescribeAlLeerYSeConfirmaExplicitamente() throws {
        try conPreferencias { defaults in
            defaults.set(true, forKey: "tracking.velocidadDemo")
            defaults.set("radio futuro", forKey: "tracking.radioParadero")
            let vm = modelo(defaults)
            XCTAssertEqual(vm.velocidadDemo, 1)
            XCTAssertEqual(vm.radioParadero, 500)
            XCTAssertEqual(PreferenciasApp.boolGuardado(para: "tracking.velocidadDemo", defaults: defaults), true)
            XCTAssertEqual(defaults.string(forKey: "tracking.radioParadero"), "radio futuro")
            vm.velocidadDemo = 1
            vm.radioParadero = 500
            XCTAssertNil(PreferenciasApp.boolGuardado(para: "tracking.velocidadDemo", defaults: defaults))
            XCTAssertEqual(defaults.double(forKey: "tracking.velocidadDemo"), 1)
            XCTAssertEqual(defaults.double(forKey: "tracking.radioParadero"), 500)
        }
    }
}


/// Clientes reales con conexión sustituida: no se abre un socket ni se usa un broker.
@MainActor
final class MQTTTrackingCicloTests: XCTestCase {
    private let configuracion = MQTTConfiguration(host: "localhost", port: 1883,
        username: "dispositivo-prueba", password: "prueba-local")

    private func mensaje(_ id: String) throws -> CocoaMQTTMessage {
        let datos = try JSONSerialization.data(withJSONObject: [
            "vehicleId": id, "routeId": "ruta-prueba", "linea": "10",
            "lat": -8.1, "lon": -79.03, "heading": 90, "speed": 4,
            "timestamp": Date().timeIntervalSince1970,
            "schemaVersion": 2, "dataOrigin": "observed",
            "simulationRunId": NSNull(), "controlRevision": NSNull()
        ])
        return CocoaMQTTMessage(topic: "rutautp/vehiculos/\(id)/posicion",
            string: try XCTUnwrap(String(data: datos, encoding: .utf8)))
    }

    func testPublicadorPuedeReintentarLaMismaSesionTrasFalloInicial() {
        var clientes: [CocoaMQTT] = []
        let publisher = MQTTObservationPublisher(configuration: configuracion) { client in
            clientes.append(client)
            return clientes.count > 1
        }
        defer { publisher.stop() }
        publisher.start(sessionID: "sesion-prueba", linea: "10")
        if case .failed = publisher.state {} else { XCTFail("El fallo de socket debe ser visible") }
        XCTAssertEqual(clientes.count, 1)
        XCTAssertFalse(clientes[0].autoReconnect)
        publisher.start(sessionID: "sesion-prueba", linea: "10")
        XCTAssertEqual(clientes.count, 2)
        XCTAssertEqual(publisher.state, .connecting)
        publisher.start(sessionID: "sesion-prueba", linea: "10")
        XCTAssertEqual(clientes.count, 2)
    }

    func testStartPuedeReintentarSiElSocketNoAceptoElIntento() {
        var clientes: [CocoaMQTT] = []
        let provider = MQTTTrackingProvider(configuration: configuracion, loadCheckpoint: { nil }, saveCheckpoint: { _ in }) { client in
            clientes.append(client)
            return clientes.count > 1
        }
        defer { provider.stop() }
        provider.start()
        XCTAssertEqual(clientes.count, 1)
        XCTAssertFalse(clientes[0].autoReconnect)
        provider.start()
        XCTAssertEqual(clientes.count, 2)
        provider.start()
        XCTAssertEqual(clientes.count, 2)
    }

    func testMensajeDeClienteAnteriorNoEntraEnLaNuevaSesion() async throws {
        var clientes: [CocoaMQTT] = []
        let provider = MQTTTrackingProvider(configuration: configuracion, loadCheckpoint: { nil }, saveCheckpoint: { _ in }) { client in
            clientes.append(client)
            return true
        }
        defer { provider.stop() }
        provider.start()
        let anterior = try XCTUnwrap(clientes.first)
        anterior.didReceiveMessage(anterior, try mensaje("anterior"), 1)
        provider.stop()
        XCTAssertFalse(anterior.autoReconnect)
        provider.start()
        let actual = try XCTUnwrap(clientes.last)
        XCTAssertFalse(anterior === actual)
        let recibido = expectation(description: "Snapshot solo de la nueva sesión")
        let stream = provider.positions()
        let lector = Task { @MainActor in
            for await posiciones in stream {
                if posiciones.map(\.id) == ["actual"] { recibido.fulfill(); break }
            }
        }
        defer { lector.cancel() }
        actual.didReceiveMessage(actual, try mensaje("actual"), 1)
        await fulfillment(of: [recibido], timeout: 1)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(provider.currentPositions.map(\.id), ["actual"])
    }

    func testMensajeEncoladoAntesDeStopNoRepueblaSnapshot() async throws {
        var clientes: [CocoaMQTT] = []
        let provider = MQTTTrackingProvider(configuration: configuracion, loadCheckpoint: { nil }, saveCheckpoint: { _ in }) { client in
            clientes.append(client)
            return true
        }
        provider.start()
        let client = try XCTUnwrap(clientes.first)
        client.didReceiveMessage(client, try mensaje("tardio"), 1)
        provider.stop()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(provider.currentPositions.isEmpty)
        XCTAssertFalse(client.autoReconnect)
    }
}
