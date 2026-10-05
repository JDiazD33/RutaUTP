import XCTest
import CoreLocation
import Combine
import SwiftUI
@testable import RutaUTP

/// Lecturas puntuales con reloj fijo y un GPS compartido simulado. El mock
/// retiene continuaciones hasta onTermination, igual que LocationService.
@MainActor
final class RouteChangesLocationTests: XCTestCase {
    private let ahora = Date(timeIntervalSince1970: 1_800_000_000)

    func testAceptaLosLimitesInclusivosDeEdadYPrecision() {
        for edad in [-10.0, 0, 45] {
            for precision in [0.0, 50] {
                XCTAssertTrue(UbicacionPuntual.esValida(
                    lectura(edad: edad, precision: precision), ahora: ahora),
                    "edad=\(edad), precisión=\(precision)")
            }
        }
    }

    func testRechazaEdadFueraDelIntervaloYPrecisionInutilizable() {
        for edad in [-10.001, 45.001, 3_600] {
            XCTAssertFalse(UbicacionPuntual.esValida(lectura(edad: edad), ahora: ahora))
        }
        for precision in [-1.0, 50.001, .infinity, .nan] {
            XCTAssertFalse(UbicacionPuntual.esValida(
                lectura(precision: precision), ahora: ahora))
        }
    }

    func testRechazaCoordenadasInvalidasSinConfundirCeroConAusencia() {
        for punto in [CLLocationCoordinate2D(latitude: 91, longitude: 0),
                      CLLocationCoordinate2D(latitude: 0, longitude: -181),
                      CLLocationCoordinate2D(latitude: .nan, longitude: 0),
                      CLLocationCoordinate2D(latitude: 0, longitude: .infinity)] {
            XCTAssertFalse(UbicacionPuntual.esValida(lectura(punto: punto), ahora: ahora))
        }
        XCTAssertTrue(UbicacionPuntual.esValida(
            lectura(punto: CLLocationCoordinate2D(latitude: 0, longitude: 0)), ahora: ahora))
    }

    func testRegistraElLectorAntesDeIniciarYCapturaElPrimerFixSinCache() async {
        let liberado = expectation(description: "lector puntual liberado")
        let fix = lectura()
        let gps = GPSPuntualMock(alLiberar: { liberado.fulfill() })
        gps.primeraLecturaAlIniciar = fix

        let resultado = await obtener(gps)

        XCTAssertEqual(resultado?.timestamp, fix.timestamp)
        XCTAssertEqual(Array(gps.eventos.prefix(3)), ["permiso", "lector", "inicio"])
        await fulfillment(of: [liberado], timeout: 2)
        comprobarSinConsumidores(gps)
    }

    func testUsaCacheValidaYLiberalaSinEsperarOtraLectura() async {
        let liberado = expectation(description: "lector de caché liberado")
        let cache = lectura(edad: 15, punto: punto(-8.101, -79.031))
        let gps = GPSPuntualMock(alLiberar: { liberado.fulfill() })
        gps.cache = cache
        gps.primeraLecturaAlIniciar = lectura(punto: punto(-8.102, -79.032))

        let resultado = await obtener(gps)

        XCTAssertEqual(resultado?.coordinate.latitude, cache.coordinate.latitude)
        await fulfillment(of: [liberado], timeout: 2)
        comprobarSinConsumidores(gps)
    }

    func testCacheAntiguaYLecturasInvalidasEsperanUnaPosicionUtil() async {
        let iniciado = expectation(description: "GPS iniciado")
        let liberado = expectation(description: "lector liberado tras fix válido")
        let gps = GPSPuntualMock(alLiberar: { liberado.fulfill() })
        gps.cache = lectura(edad: 46)
        gps.alIniciar = { iniciado.fulfill() }
        let tarea = Task { await obtener(gps) }
        await fulfillment(of: [iniciado], timeout: 2)

        gps.emitir(lectura(precision: -1))
        gps.emitir(lectura(precision: 51))
        gps.emitir(lectura(edad: -11))
        gps.emitir(lectura(punto: punto(95, -79)))
        let valida = lectura(edad: 2, punto: punto(-8.104, -79.034))
        gps.emitir(valida)

        let resultado = await tarea.value
        XCTAssertEqual(resultado?.coordinate.latitude, valida.coordinate.latitude)
        XCTAssertEqual(resultado?.timestamp, valida.timestamp)
        await fulfillment(of: [liberado], timeout: 2)
        comprobarSinConsumidores(gps)
    }

    func testPermisoDenegadoORestringidoNoRegistraLectorNiEnciendeGPS() async {
        for permiso in [CLAuthorizationStatus.denied, .restricted] {
            let gps = GPSPuntualMock(permiso: permiso)
            let resultado = await obtener(gps)
            XCTAssertNil(resultado)
            XCTAssertEqual(gps.eventos, ["permiso"])
            comprobarSinConsumidores(gps)
        }
    }

    func testPermisoAlwaysTambienPermiteLaLecturaPuntual() async {
        let gps = GPSPuntualMock(permiso: .authorizedAlways)
        gps.primeraLecturaAlIniciar = lectura()
        let resultado = await obtener(gps)
        XCTAssertNotNil(resultado)
        comprobarSinConsumidores(gps)
    }

    func testTimeoutInvalidoNoPidePermisoNiCreaConsumidores() async {
        for timeout in [0.0, -1, .infinity, .nan] {
            let gps = GPSPuntualMock()
            let resultado = await obtener(gps, timeout: timeout)
            XCTAssertNil(resultado)
            XCTAssertTrue(gps.eventos.isEmpty)
            comprobarSinConsumidores(gps)
        }
    }

    func testTimeoutLiberaLectorPropioSinDetenerElServicioGlobal() async {
        let liberado = expectation(description: "lector liberado por timeout")
        let gps = GPSPuntualMock(alLiberar: { liberado.fulfill() })

        let resultado = await obtener(gps, timeout: 0.02)

        XCTAssertNil(resultado)
        XCTAssertEqual(gps.inicios, 1)
        await fulfillment(of: [liberado], timeout: 2)
        comprobarSinConsumidores(gps)
    }

    func testCancelarLaEsperaLiberaLectorYPermisos() async {
        let iniciado = expectation(description: "lector esperando GPS")
        let liberado = expectation(description: "lector cancelado liberado")
        let gps = GPSPuntualMock(alLiberar: { liberado.fulfill() })
        gps.alIniciar = { iniciado.fulfill() }
        let tarea = Task { await obtener(gps) }
        await fulfillment(of: [iniciado], timeout: 2)

        tarea.cancel()
        let resultado = await tarea.value

        XCTAssertNil(resultado)
        await fulfillment(of: [liberado], timeout: 2)
        comprobarSinConsumidores(gps)
    }

    func testUnStreamQueFinalizaSinFixNoQuedaEsperandoHastaTimeout() async {
        let iniciado = expectation(description: "lector registrado")
        let liberado = expectation(description: "stream finalizado liberado")
        let gps = GPSPuntualMock(alLiberar: { liberado.fulfill() })
        gps.alIniciar = { iniciado.fulfill() }
        let tarea = Task { await obtener(gps, timeout: 10) }
        await fulfillment(of: [iniciado], timeout: 2)

        gps.finalizarLectores()
        let resultado = await tarea.value

        XCTAssertNil(resultado)
        await fulfillment(of: [liberado], timeout: 2)
        comprobarSinConsumidores(gps)
    }

    func testRevocarPermisoLiberaLectorAunqueElGPSNoFinaliceSuStream() async {
        let iniciado = expectation(description: "lector esperando")
        let liberado = expectation(description: "lector revocado liberado")
        let gps = GPSPuntualMock(alLiberar: { liberado.fulfill() })
        gps.alIniciar = { iniciado.fulfill() }
        let tarea = Task { await obtener(gps, timeout: 10) }
        await fulfillment(of: [iniciado], timeout: 2)

        // El mock solo publica el permiso: comprueba el vigilante de permisos
        // sin apoyarse en el forceStopUpdating del servicio concreto.
        gps.cambiarPermiso(.denied)
        let resultado = await tarea.value

        XCTAssertNil(resultado)
        await fulfillment(of: [liberado], timeout: 2)
        comprobarSinConsumidores(gps)
    }

    func testCancelacionDuranteDialogoDePermisoNoIniciaGPSAlAceptar() async {
        let solicitado = expectation(description: "diálogo pendiente")
        let gps = GPSPuntualMock(permiso: .notDetermined)
        gps.suspenderPermiso = true
        gps.alPedirPermiso = { solicitado.fulfill() }
        let tarea = Task { await obtener(gps, timeout: 0.01) }
        await fulfillment(of: [solicitado], timeout: 2)
        XCTAssertEqual(gps.eventos, ["permiso"])

        tarea.cancel()
        gps.resolverPermiso(.authorizedWhenInUse)
        let resultado = await tarea.value

        XCTAssertNil(resultado)
        XCTAssertEqual(gps.eventos, ["permiso"])
        comprobarSinConsumidores(gps)
    }

    func testCancelarAntesDeCargarNoPidePermiso() async {
        let gps = GPSPuntualMock()
        let tarea = Task { () -> CLLocation? in
            withUnsafeCurrentTask { $0?.cancel() }
            return await obtener(gps)
        }
        let resultado = await tarea.value
        XCTAssertNil(resultado)
        XCTAssertTrue(gps.eventos.isEmpty)
        comprobarSinConsumidores(gps)
    }

    func testDenegarDialogoPendienteNoRegistraUnLector() async {
        let solicitado = expectation(description: "permiso pendiente")
        let gps = GPSPuntualMock(permiso: .notDetermined)
        gps.suspenderPermiso = true
        gps.alPedirPermiso = { solicitado.fulfill() }
        let tarea = Task { await obtener(gps) }
        await fulfillment(of: [solicitado], timeout: 2)

        gps.resolverPermiso(.restricted)
        let resultado = await tarea.value

        XCTAssertNil(resultado)
        XCTAssertEqual(gps.eventos, ["permiso"])
        comprobarSinConsumidores(gps)
    }

    func testLecturaPuntualNoInterrumpeConsumidorParaleloYLiberanElUltimo() async {
        let iniciado = expectation(description: "GPS compartido iniciado")
        let dosLecturas = expectation(description: "consumidor paralelo recibe después del reporte")
        dosLecturas.expectedFulfillmentCount = 2
        let liberados = expectation(description: "ambos lectores liberados")
        liberados.expectedFulfillmentCount = 2
        let gps = GPSPuntualMock(alLiberar: { liberados.fulfill() })
        let streamParalelo = gps.currentLocation()
        let consumidor = Task {
            for await _ in streamParalelo {
                dosLecturas.fulfill()
            }
        }
        gps.alIniciar = { iniciado.fulfill() }
        let puntual = Task { await obtener(gps) }
        await fulfillment(of: [iniciado], timeout: 2)
        XCTAssertEqual(gps.lectoresActivos, 2)

        gps.emitir(lectura())
        let resultado = await puntual.value
        XCTAssertNotNil(resultado)
        XCTAssertEqual(gps.lectoresActivos, 1)
        XCTAssertTrue(gps.actualizando)
        XCTAssertEqual(gps.paradasGlobales, 0)
        gps.emitir(lectura(edad: 1))
        await fulfillment(of: [dosLecturas], timeout: 2)

        consumidor.cancel()
        await consumidor.value
        await fulfillment(of: [liberados], timeout: 2)
        comprobarSinConsumidores(gps)
    }

    func testTimeoutDeUnReporteNoInterrumpeOtroLector() async {
        let liberados = expectation(description: "timeout y consumidor liberados")
        liberados.expectedFulfillmentCount = 2
        let recibido = expectation(description: "otro lector sigue recibiendo")
        let gps = GPSPuntualMock(alLiberar: { liberados.fulfill() })
        let stream = gps.currentLocation()
        let consumidor = Task {
            for await _ in stream { recibido.fulfill() }
        }

        let resultado = await obtener(gps, timeout: 0.02)
        XCTAssertNil(resultado)
        XCTAssertEqual(gps.lectoresActivos, 1)
        XCTAssertTrue(gps.actualizando)
        gps.emitir(lectura())
        await fulfillment(of: [recibido], timeout: 2)

        consumidor.cancel()
        await consumidor.value
        await fulfillment(of: [liberados], timeout: 2)
        comprobarSinConsumidores(gps)
    }

    func testModeloProponeUbicacionEnLaRutaActualSiNoHayPin() async {
        let modelo = await modeloConUbicacion()
        let propuesto = modelo.puntoAutomatico(para: ruta(), puntoActual: nil,
                                               editadoAMano: false, mapaAmpliadoAbierto: false)
        XCTAssertEqual(propuesto?.latitude, -8.100)
        XCTAssertEqual(propuesto?.longitude, -79.030)
    }

    func testModeloNoReemplazaPinManualConLecturaTardia() async {
        let modelo = await modeloConUbicacion()
        let manual = punto(-8.099, -79.029)
        XCTAssertNil(modelo.puntoAutomatico(para: ruta(), puntoActual: manual,
                                          editadoAMano: true, mapaAmpliadoAbierto: false))
        XCTAssertNil(modelo.puntoAutomatico(para: ruta(), puntoActual: nil,
                                          editadoAMano: true, mapaAmpliadoAbierto: false))
    }

    func testModeloNoReemplazaElPinDeUnaAlertaSeleccionada() async {
        let modelo = await modeloConUbicacion()
        // Seleccionar una alerta pone un punto existente sin marcarlo manual.
        XCTAssertNil(modelo.puntoAutomatico(para: ruta(), puntoActual: punto(-8.099, -79.030),
                                          editadoAMano: false, mapaAmpliadoAbierto: false))
    }

    func testModeloNoModificaUnBorradorAbiertoEnElMapaAmpliado() async {
        let modelo = await modeloConUbicacion()
        XCTAssertNil(modelo.puntoAutomatico(para: ruta(), puntoActual: nil,
                                          editadoAMano: false, mapaAmpliadoAbierto: true))
        XCTAssertNotNil(modelo.puntoAutomatico(para: ruta(), puntoActual: nil,
                                             editadoAMano: false, mapaAmpliadoAbierto: false))
    }

    func testModeloEvaluaLaRutaElegidaAhoraYSoloProponeSiEsCoherente() async {
        let modelo = await modeloConUbicacion()
        let rutaLejana = ruta(id: "otra", shape: [punto(-8.200, -79.030), punto(-8.201, -79.030)])
        XCTAssertNil(modelo.puntoAutomatico(para: rutaLejana, puntoActual: nil,
                                          editadoAMano: false, mapaAmpliadoAbierto: false))
        XCTAssertNotNil(modelo.puntoAutomatico(para: ruta(), puntoActual: nil,
                                             editadoAMano: false, mapaAmpliadoAbierto: false))
    }

    func testModeloNoColocaPinSinSeleccionRutaNiGeometriaMedible() async {
        let modelo = await modeloConUbicacion()
        for candidata in [nil, ruta(shape: []), ruta(shape: [punto(-8.100, -79.030)])] {
            XCTAssertNil(modelo.puntoAutomatico(para: candidata, puntoActual: nil,
                                              editadoAMano: false, mapaAmpliadoAbierto: false))
        }
    }

    func testModeloSinLecturaUtilNoProponeUnaCoordenada() async {
        let modelo = RouteChangesLocationModel()
        let gps = GPSPuntualMock(permiso: .denied)
        await modelo.cargar(desde: gps, ahora: { self.ahora })
        XCTAssertNil(modelo.coordenada)
        XCTAssertNil(modelo.puntoAutomatico(para: ruta(), puntoActual: nil,
                                          editadoAMano: false, mapaAmpliadoAbierto: false))
    }

    func testResultadoCanceladoNoBorraNiReemplazaLaCoordenadaAnterior() async {
        let modelo = await modeloConUbicacion()
        let solicitado = expectation(description: "segunda solicitud pendiente")
        let gps = GPSPuntualMock(permiso: .notDetermined)
        gps.suspenderPermiso = true
        gps.cache = lectura(punto: punto(-8.105, -79.035))
        gps.alPedirPermiso = { solicitado.fulfill() }
        let tarea = Task { await modelo.cargar(desde: gps, ahora: { self.ahora }) }
        await fulfillment(of: [solicitado], timeout: 2)

        tarea.cancel()
        gps.resolverPermiso(.authorizedWhenInUse)
        await tarea.value

        XCTAssertEqual(modelo.coordenada?.latitude, -8.100)
        XCTAssertEqual(gps.inicios, 0)
        comprobarSinConsumidores(gps)
    }

    func testSolicitudViejaQueTerminaDespuesNoSobrescribeLaNueva() async {
        let modelo = RouteChangesLocationModel()
        let solicitado = expectation(description: "solicitud vieja suspendida")
        let viejo = GPSPuntualMock(permiso: .notDetermined)
        viejo.suspenderPermiso = true
        viejo.cache = lectura(punto: punto(-8.110, -79.040))
        viejo.alPedirPermiso = { solicitado.fulfill() }
        let anterior = Task { await modelo.cargar(desde: viejo, ahora: { self.ahora }) }
        await fulfillment(of: [solicitado], timeout: 2)
        let nuevo = GPSPuntualMock()
        nuevo.cache = lectura(punto: punto(-8.101, -79.031))

        await modelo.cargar(desde: nuevo, ahora: { self.ahora })
        viejo.resolverPermiso(.authorizedWhenInUse)
        await anterior.value

        XCTAssertEqual(modelo.coordenada?.latitude, -8.101)
        XCTAssertEqual(modelo.coordenada?.longitude, -79.031)
        comprobarSinConsumidores(viejo)
        comprobarSinConsumidores(nuevo)
    }

    private func obtener(_ gps: GPSPuntualMock, timeout: TimeInterval = 2) async -> CLLocation? {
        await UbicacionPuntual.obtener(desde: gps, timeout: timeout, ahora: { self.ahora })
    }

    private func modeloConUbicacion() async -> RouteChangesLocationModel {
        let gps = GPSPuntualMock()
        gps.cache = lectura()
        let modelo = RouteChangesLocationModel()
        await modelo.cargar(desde: gps, ahora: { self.ahora })
        comprobarSinConsumidores(gps)
        return modelo
    }

    private func comprobarSinConsumidores(_ gps: GPSPuntualMock,
                                         file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(gps.lectoresActivos, 0, file: file, line: line)
        XCTAssertFalse(gps.actualizando, file: file, line: line)
        XCTAssertEqual(gps.paradasGlobales, 0, file: file, line: line)
        XCTAssertEqual(gps.suscriptoresPermiso, 0, file: file, line: line)
    }

    private func lectura(edad: TimeInterval = 0, precision: CLLocationAccuracy = 5,
                         punto: CLLocationCoordinate2D? = nil) -> CLLocation {
        CLLocation(coordinate: punto ?? self.punto(-8.100, -79.030), altitude: 0,
                   horizontalAccuracy: precision, verticalAccuracy: 5,
                   timestamp: ahora.addingTimeInterval(-edad))
    }

    private func punto(_ lat: Double, _ lon: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private func ruta(id: String = "actual", shape: [CLLocationCoordinate2D]? = nil) -> RutaGTFS {
        RutaGTFS(id: id, linea: "C-01", variante: "A", recorrido: "Inicio → Fin",
                 empresa: "Prueba", colorHex: "0000FF", color: .blue,
                 shape: shape ?? [punto(-8.099, -79.030), punto(-8.101, -79.030)],
                 paraderos: [], duracionMin: 20, headwayMin: 10, precio: 2,
                 distanciaKm: 3, distanciaUTPMetros: 0)
    }
}

/// El permiso y los métodos del protocolo se usan desde MainActor. Solo
/// onTermination y los callbacks de Combine pueden llegar desde otro ejecutor;
/// todo el registro que tocan queda protegido en RegistroGPSPuntual.
private final class GPSPuntualMock: LocationServiceProtocol, @unchecked Sendable {
    private let permisos: CurrentValueSubject<CLAuthorizationStatus, Never>
    private let registro: RegistroGPSPuntual
    private var permisoPendiente: CheckedContinuation<CLAuthorizationStatus, Never>?
    var cache: CLLocation?
    var primeraLecturaAlIniciar: CLLocation?
    var suspenderPermiso = false
    var alIniciar: (() -> Void)?
    var alPedirPermiso: (() -> Void)?

    init(permiso: CLAuthorizationStatus = .authorizedWhenInUse,
         alLiberar: @escaping () -> Void = {}) {
        permisos = CurrentValueSubject(permiso)
        registro = RegistroGPSPuntual(alLiberar: alLiberar)
    }

    var authorizationStatus: CLAuthorizationStatus { permisos.value }
    var authorizationPublisher: AnyPublisher<CLAuthorizationStatus, Never> {
        permisos.handleEvents(
            receiveSubscription: { [registro] _ in registro.suscribirPermiso() },
            receiveCancel: { [registro] in registro.cancelarPermiso() }
        ).eraseToAnyPublisher()
    }
    var eventos: [String] { registro.instantanea.eventos }
    var lectoresActivos: Int { registro.instantanea.lectores }
    var actualizando: Bool { registro.instantanea.actualizando }
    var inicios: Int { eventos.filter { $0 == "inicio" }.count }
    var paradasGlobales: Int { eventos.filter { $0 == "stopUpdating" }.count }
    var suscriptoresPermiso: Int { registro.instantanea.suscriptoresPermiso }

    func requestPermission() async -> CLAuthorizationStatus {
        registro.evento("permiso")
        if suspenderPermiso {
            return await withCheckedContinuation { continuation in
                permisoPendiente = continuation
                alPedirPermiso?()
            }
        }
        alPedirPermiso?()
        return authorizationStatus
    }

    func resolverPermiso(_ permiso: CLAuthorizationStatus) {
        cambiarPermiso(permiso)
        let pendiente = permisoPendiente
        permisoPendiente = nil
        pendiente?.resume(returning: permiso)
    }

    func cambiarPermiso(_ permiso: CLAuthorizationStatus) { permisos.send(permiso) }

    func currentLocation() -> AsyncStream<CLLocation> {
        let id = UUID()
        return AsyncStream { [registro, cache] continuation in
            continuation.onTermination = { [weak registro] _ in registro?.liberar(id) }
            registro.registrar(continuation, id: id)
            if let cache { continuation.yield(cache) }
        }
    }

    func startUpdating() {
        registro.iniciar()
        if let primeraLecturaAlIniciar { emitir(primeraLecturaAlIniciar) }
        alIniciar?()
    }

    func stopUpdating() { registro.evento("stopUpdating") }
    func emitir(_ location: CLLocation) { registro.emitir(location) }
    func finalizarLectores() { registro.finalizar() }
}

private final class RegistroGPSPuntual: @unchecked Sendable {
    struct Instantanea {
        let eventos: [String]
        let lectores: Int
        let actualizando: Bool
        let suscriptoresPermiso: Int
    }
    private let candado = NSLock()
    private var continuaciones: [UUID: AsyncStream<CLLocation>.Continuation] = [:]
    private var eventos: [String] = []
    private var actualizando = false
    private var suscriptoresPermiso = 0
    private let alLiberar: () -> Void

    init(alLiberar: @escaping () -> Void) { self.alLiberar = alLiberar }

    var instantanea: Instantanea {
        candado.lock()
        defer { candado.unlock() }
        return Instantanea(eventos: eventos, lectores: continuaciones.count,
                           actualizando: actualizando, suscriptoresPermiso: suscriptoresPermiso)
    }

    func evento(_ nombre: String) {
        candado.lock()
        eventos.append(nombre)
        candado.unlock()
    }

    func registrar(_ continuation: AsyncStream<CLLocation>.Continuation, id: UUID) {
        candado.lock()
        continuaciones[id] = continuation
        eventos.append("lector")
        candado.unlock()
    }

    func liberar(_ id: UUID) {
        candado.lock()
        let existia = continuaciones.removeValue(forKey: id) != nil
        if continuaciones.isEmpty { actualizando = false }
        candado.unlock()
        if existia { alLiberar() }
    }

    func iniciar() {
        candado.lock()
        eventos.append("inicio")
        actualizando = true
        candado.unlock()
    }

    func suscribirPermiso() {
        candado.lock()
        suscriptoresPermiso += 1
        candado.unlock()
    }

    func cancelarPermiso() {
        candado.lock()
        suscriptoresPermiso -= 1
        candado.unlock()
    }

    private var activas: [AsyncStream<CLLocation>.Continuation] {
        candado.lock()
        defer { candado.unlock() }
        return Array(continuaciones.values)
    }

    func emitir(_ location: CLLocation) {
        // yield/finish pueden ejecutar onTermination; nunca bajo el candado.
        activas.forEach { $0.yield(location) }
    }

    func finalizar() { activas.forEach { $0.finish() } }
}
