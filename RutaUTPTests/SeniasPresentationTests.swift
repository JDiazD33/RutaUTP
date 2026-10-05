import XCTest
@testable import RutaUTP

/// El reloj y la ventana se capturan en memoria: estas pruebas no cambian
/// preferencias, no abren ventanas y no esperan la duración de un video.
@MainActor
final class SeniasPresentationTests: XCTestCase {
    private let claveNormal = "rutas.guia"

    func testActivacionConModoApagadoNoMuestraVideo() {
        let escenario = Escenario(modoActivo: false)

        escenario.presenter.mostrarActivacionDelModo()

        XCTAssertNil(escenario.presenter.claveVisible)
        XCTAssertFalse(escenario.presenter.esActivacionDelModo)
        XCTAssertFalse(escenario.visibilidad.contains(true))
        XCTAssertTrue(escenario.esperas.isEmpty)
    }

    func testActivacionMuestraElClipDelModoSinTemporizadorDeTresSegundos() {
        let escenario = Escenario()
        let idAnterior = escenario.presenter.idPresentacion

        escenario.presenter.mostrarActivacionDelModo()
        let id = escenario.presenter.idPresentacion
        escenario.presenter.tarjetaPresentada(
            clave: SeniasService.claveActivacionModo, id: id)

        XCTAssertEqual(escenario.presenter.claveVisible, SeniasService.claveActivacionModo)
        XCTAssertTrue(escenario.presenter.esActivacionDelModo)
        XCTAssertNotEqual(id, idAnterior)
        XCTAssertEqual(escenario.visibilidad.last, true)
        XCTAssertTrue(escenario.esperas.isEmpty,
                      "La introducción debe esperar el final real del video.")
    }

    func testFinalDeActivacionCierraVideoYConservaModoActivo() {
        let escenario = Escenario()
        escenario.presenter.mostrarActivacionDelModo()
        let id = escenario.presenter.idPresentacion

        escenario.presenter.videoFinalizado(id: id)

        XCTAssertNil(escenario.presenter.claveVisible)
        XCTAssertFalse(escenario.presenter.esActivacionDelModo)
        XCTAssertTrue(escenario.modoActivo)
        XCTAssertEqual(escenario.visibilidad.last, false)
        let cambios = escenario.visibilidad.count
        escenario.presenter.videoFinalizado(id: id)
        XCTAssertEqual(escenario.visibilidad.count, cambios)
    }

    func testCierreManualDeActivacionConservaModoActivo() {
        let escenario = Escenario()
        escenario.presenter.mostrarActivacionDelModo()
        let id = escenario.presenter.idPresentacion

        escenario.presenter.ocultar()
        escenario.presenter.videoFinalizado(id: id)

        XCTAssertNil(escenario.presenter.claveVisible)
        XCTAssertFalse(escenario.presenter.esActivacionDelModo)
        XCTAssertTrue(escenario.modoActivo)
    }

    func testCadaNuevaActivacionPuedeReproducirseOtraVez() {
        let escenario = Escenario()
        escenario.presenter.mostrarActivacionDelModo()
        let primera = escenario.presenter.idPresentacion
        escenario.presenter.videoFinalizado(id: primera)

        escenario.presenter.mostrarActivacionDelModo()
        let segunda = escenario.presenter.idPresentacion

        XCTAssertNotEqual(primera, segunda)
        XCTAssertEqual(escenario.presenter.claveVisible, SeniasService.claveActivacionModo)
        XCTAssertTrue(escenario.presenter.esActivacionDelModo)
        escenario.presenter.videoFinalizado(id: segunda)
        XCTAssertNil(escenario.presenter.claveVisible)
    }

    func testFinalTardioNoCierraUnaNuevaActivacionDeLaMismaClave() {
        let escenario = Escenario()
        escenario.presenter.mostrarActivacionDelModo()
        let primera = escenario.presenter.idPresentacion
        escenario.presenter.mostrarActivacionDelModo()
        let segunda = escenario.presenter.idPresentacion

        escenario.presenter.videoFinalizado(id: primera)

        XCTAssertEqual(escenario.presenter.idPresentacion, segunda)
        XCTAssertEqual(escenario.presenter.claveVisible, SeniasService.claveActivacionModo)
        XCTAssertTrue(escenario.presenter.esActivacionDelModo)
    }

    func testFinalTardioNoCierraElClipQueSustituyoLaActivacion() {
        let escenario = Escenario()
        escenario.presenter.mostrarActivacionDelModo()
        let introduccion = escenario.presenter.idPresentacion
        escenario.presenter.mostrar(clave: claveNormal)
        let actual = escenario.presenter.idPresentacion

        escenario.presenter.videoFinalizado(id: introduccion)

        XCTAssertEqual(escenario.presenter.idPresentacion, actual)
        XCTAssertEqual(escenario.presenter.claveVisible, claveNormal)
        XCTAssertFalse(escenario.presenter.esActivacionDelModo)
    }

    func testClipDelModoAbiertoComoSeniaNormalNoSeCierraAlTerminar() {
        let escenario = Escenario()
        escenario.presenter.mostrar(clave: SeniasService.claveActivacionModo)
        let id = escenario.presenter.idPresentacion

        escenario.presenter.videoFinalizado(id: id)

        XCTAssertEqual(escenario.presenter.claveVisible, SeniasService.claveActivacionModo)
        XCTAssertFalse(escenario.presenter.esActivacionDelModo)
        XCTAssertEqual(escenario.presenter.idPresentacion, id)
    }

    func testSeniaInformativaMantieneElComportamientoNormalSinEspera() {
        let escenario = Escenario()
        escenario.presenter.mostrar(clave: claveNormal)
        let id = escenario.presenter.idPresentacion
        escenario.presenter.tarjetaPresentada(clave: claveNormal, id: id)

        escenario.presenter.videoFinalizado(id: id)

        XCTAssertEqual(escenario.presenter.claveVisible, claveNormal)
        XCTAssertFalse(escenario.presenter.esActivacionDelModo)
        XCTAssertTrue(escenario.esperas.isEmpty)
    }

    func testSeniaNormalConModoApagadoNoAbreVentana() {
        let escenario = Escenario(modoActivo: false)

        escenario.presenter.mostrar(clave: claveNormal)

        XCTAssertNil(escenario.presenter.claveVisible)
        XCTAssertFalse(escenario.visibilidad.contains(true))
    }

    func testAccionConModoApagadoSeEjecutaInmediatamenteUnaVez() {
        let escenario = Escenario(modoActivo: false)
        var ejecuciones = 0

        escenario.presenter.ejecutarTrasVerSenia(clave: claveNormal) { ejecuciones += 1 }
        escenario.presenter.ocultar()

        XCTAssertEqual(ejecuciones, 1)
        XCTAssertNil(escenario.presenter.claveVisible)
        XCTAssertTrue(escenario.esperas.isEmpty)
    }

    func testAccionSinClaveCancelaLaAnteriorYContinuaInmediatamente() {
        let escenario = Escenario()
        var anterior = 0
        var nueva = 0
        escenario.presenter.ejecutarTrasVerSenia(clave: claveNormal) { anterior += 1 }
        escenario.presentarTarjetaActual()
        let esperaAnterior = escenario.esperas[0].trabajo

        escenario.presenter.ejecutarTrasVerSenia { nueva += 1 }
        esperaAnterior.perform()
        escenario.presenter.ocultar()

        XCTAssertEqual(anterior, 0)
        XCTAssertEqual(nueva, 1)
        XCTAssertNil(escenario.presenter.claveVisible)
        XCTAssertTrue(esperaAnterior.isCancelled)
    }

    func testAccionNormalEmpiezaLaEsperaSoloCuandoLaTarjetaSePresenta() {
        let escenario = Escenario()
        var ejecuciones = 0
        escenario.presenter.ejecutarTrasVerSenia(clave: claveNormal) { ejecuciones += 1 }

        XCTAssertEqual(escenario.presenter.claveVisible, claveNormal)
        XCTAssertFalse(escenario.presenter.esActivacionDelModo)
        XCTAssertEqual(ejecuciones, 0)
        XCTAssertTrue(escenario.esperas.isEmpty)

        escenario.presentarTarjetaActual()
        XCTAssertEqual(escenario.esperas.count, 1)
        XCTAssertEqual(escenario.esperas[0].duracion, 3)
        escenario.esperas[0].trabajo.perform()
        XCTAssertEqual(ejecuciones, 1)
        XCTAssertNil(escenario.presenter.claveVisible)
    }

    func testTarjetaDeOtraSolicitudOClaveNoEmpiezaLaEspera() {
        let escenario = Escenario()
        escenario.presenter.ejecutarTrasVerSenia(clave: claveNormal) {}
        let id = escenario.presenter.idPresentacion

        escenario.presenter.tarjetaPresentada(clave: claveNormal, id: UUID())
        escenario.presenter.tarjetaPresentada(clave: "inicio.boton_planear", id: id)

        XCTAssertTrue(escenario.esperas.isEmpty)
        XCTAssertEqual(escenario.presenter.claveVisible, claveNormal)
        escenario.presentarTarjetaActual()
        XCTAssertEqual(escenario.esperas.count, 1)
    }

    func testDobleToqueNoReiniciaLaEsperaNiReemplazaLaAccion() {
        let escenario = Escenario()
        var primera = 0
        var duplicada = 0
        escenario.presenter.ejecutarTrasVerSenia(clave: claveNormal) { primera += 1 }
        escenario.presentarTarjetaActual()
        let id = escenario.presenter.idPresentacion

        escenario.presenter.ejecutarTrasVerSenia(clave: claveNormal) { duplicada += 1 }
        escenario.presentarTarjetaActual()

        XCTAssertEqual(escenario.presenter.idPresentacion, id)
        XCTAssertEqual(escenario.esperas.count, 1)
        escenario.esperas[0].trabajo.perform()
        XCTAssertEqual(primera, 1)
        XCTAssertEqual(duplicada, 0)
    }

    func testNotificarDosVecesLaTarjetaNoProgramaDosAcciones() {
        let escenario = Escenario()
        var ejecuciones = 0
        escenario.presenter.ejecutarTrasVerSenia(clave: claveNormal) { ejecuciones += 1 }

        escenario.presentarTarjetaActual()
        escenario.presentarTarjetaActual()

        XCTAssertEqual(escenario.esperas.count, 1)
        escenario.esperas[0].trabajo.perform()
        escenario.presenter.ocultar()
        XCTAssertEqual(ejecuciones, 1)
    }

    func testCerrarUnaAccionPendienteLaEjecutaUnaVezYCancelaLaEspera() {
        let escenario = Escenario()
        var ejecuciones = 0
        escenario.presenter.ejecutarTrasVerSenia(clave: claveNormal) { ejecuciones += 1 }
        escenario.presentarTarjetaActual()
        let espera = escenario.esperas[0].trabajo

        escenario.presenter.ocultar()
        espera.perform()
        escenario.presenter.ocultar()

        XCTAssertEqual(ejecuciones, 1)
        XCTAssertTrue(espera.isCancelled)
        XCTAssertNil(escenario.presenter.claveVisible)
    }

    func testCancelarAntesDeOcultarNoEjecutaLaAccionPendiente() {
        let escenario = Escenario()
        var ejecuciones = 0
        escenario.presenter.ejecutarTrasVerSenia(clave: claveNormal) { ejecuciones += 1 }
        escenario.presentarTarjetaActual()
        let espera = escenario.esperas[0].trabajo
        let id = escenario.presenter.idPresentacion

        escenario.modoActivo = false
        escenario.presenter.cancelarAccionPendiente()
        escenario.presenter.ocultar()
        espera.perform()
        escenario.presenter.videoFinalizado(id: id)

        XCTAssertEqual(ejecuciones, 0)
        XCTAssertTrue(espera.isCancelled)
        XCTAssertNotEqual(escenario.presenter.idPresentacion, id)
        XCTAssertNil(escenario.presenter.claveVisible)
    }

    func testCambiarDeSeniaCancelaLaAccionYSuTemporizador() {
        let escenario = Escenario()
        var ejecuciones = 0
        escenario.presenter.ejecutarTrasVerSenia(clave: claveNormal) { ejecuciones += 1 }
        escenario.presentarTarjetaActual()
        let espera = escenario.esperas[0].trabajo

        escenario.presenter.mostrar(clave: "perfil.privacidad")
        let idActual = escenario.presenter.idPresentacion
        espera.perform()

        XCTAssertEqual(ejecuciones, 0)
        XCTAssertTrue(espera.isCancelled)
        XCTAssertEqual(escenario.presenter.claveVisible, "perfil.privacidad")
        XCTAssertEqual(escenario.presenter.idPresentacion, idActual)
    }

    func testTemporizadorViejoNoCierraUnaNuevaAccionDeLaMismaClave() {
        let escenario = Escenario()
        var anterior = 0
        var actual = 0
        escenario.presenter.ejecutarTrasVerSenia(clave: claveNormal) { anterior += 1 }
        escenario.presentarTarjetaActual()
        let esperaAnterior = escenario.esperas[0].trabajo
        escenario.presenter.cancelarAccionPendiente()

        escenario.presenter.ejecutarTrasVerSenia(clave: claveNormal) { actual += 1 }
        escenario.presentarTarjetaActual()
        let idActual = escenario.presenter.idPresentacion
        let esperaActual = escenario.esperas.last!.trabajo
        esperaAnterior.perform()

        XCTAssertEqual(anterior, 0)
        XCTAssertEqual(actual, 0)
        XCTAssertEqual(escenario.presenter.claveVisible, claveNormal)
        XCTAssertEqual(escenario.presenter.idPresentacion, idActual)
        XCTAssertFalse(esperaActual.isCancelled)
        esperaActual.perform()
        XCTAssertEqual(actual, 1)
        XCTAssertEqual(anterior, 0)
    }

    func testActivarModoCancelaLaAccionAnteriorSinEjecutarla() {
        let escenario = Escenario()
        var ejecuciones = 0
        escenario.presenter.ejecutarTrasVerSenia(clave: claveNormal) { ejecuciones += 1 }
        escenario.presentarTarjetaActual()
        let espera = escenario.esperas[0].trabajo

        escenario.presenter.mostrarActivacionDelModo()
        let id = escenario.presenter.idPresentacion
        espera.perform()
        escenario.presenter.videoFinalizado(id: id)

        XCTAssertEqual(ejecuciones, 0)
        XCTAssertTrue(espera.isCancelled)
        XCTAssertNil(escenario.presenter.claveVisible)
        XCTAssertTrue(escenario.modoActivo)
    }

    func testVideoDeActivacionNoDisponibleCierraTrasUnaEsperaBreve() {
        let escenario = Escenario()
        escenario.presenter.mostrarActivacionDelModo()
        let id = escenario.presenter.idPresentacion

        escenario.presenter.videoNoDisponible(id: id)

        XCTAssertEqual(escenario.esperas.count, 1)
        XCTAssertEqual(escenario.esperas[0].duracion, 3)
        XCTAssertEqual(escenario.presenter.claveVisible, SeniasService.claveActivacionModo)
        escenario.esperas[0].trabajo.perform()
        XCTAssertNil(escenario.presenter.claveVisible)
        XCTAssertTrue(escenario.modoActivo)
    }

    func testErrorRepetidoDelMismoVideoNoReiniciaElCierreDeRespaldo() {
        let escenario = Escenario()
        escenario.presenter.mostrarActivacionDelModo()
        let id = escenario.presenter.idPresentacion

        escenario.presenter.videoNoDisponible(id: id)
        escenario.presenter.videoNoDisponible(id: id)

        XCTAssertEqual(escenario.esperas.count, 1)
        XCTAssertFalse(escenario.esperas[0].trabajo.isCancelled)
    }

    func testErrorTardioNoProgramaUnCierreParaElClipSustituto() {
        let escenario = Escenario()
        escenario.presenter.mostrarActivacionDelModo()
        let introduccion = escenario.presenter.idPresentacion
        escenario.presenter.mostrar(clave: claveNormal)

        escenario.presenter.videoNoDisponible(id: introduccion)

        XCTAssertTrue(escenario.esperas.isEmpty)
        XCTAssertEqual(escenario.presenter.claveVisible, claveNormal)
    }

    func testEsperaDeVideoNoDisponibleNoCierraLaSiguienteActivacion() {
        let escenario = Escenario()
        escenario.presenter.mostrarActivacionDelModo()
        let primera = escenario.presenter.idPresentacion
        escenario.presenter.videoNoDisponible(id: primera)
        let espera = escenario.esperas[0].trabajo
        escenario.presenter.mostrarActivacionDelModo()
        let segunda = escenario.presenter.idPresentacion

        espera.perform()

        XCTAssertTrue(espera.isCancelled)
        XCTAssertEqual(escenario.presenter.idPresentacion, segunda)
        XCTAssertEqual(escenario.presenter.claveVisible, SeniasService.claveActivacionModo)
    }

    func testFinDeIntroduccionViejaNoAdelantaUnaAccionNueva() {
        let escenario = Escenario()
        var ejecuciones = 0
        escenario.presenter.mostrarActivacionDelModo()
        let introduccion = escenario.presenter.idPresentacion
        escenario.presenter.ejecutarTrasVerSenia(clave: claveNormal) { ejecuciones += 1 }
        escenario.presentarTarjetaActual()

        escenario.presenter.videoFinalizado(id: introduccion)

        XCTAssertEqual(ejecuciones, 0)
        XCTAssertEqual(escenario.presenter.claveVisible, claveNormal)
        XCTAssertEqual(escenario.esperas.count, 1)
        escenario.esperas[0].trabajo.perform()
        XCTAssertEqual(ejecuciones, 1)
    }

    @MainActor
    private final class Escenario {
        struct Espera {
            let duracion: TimeInterval
            let trabajo: DispatchWorkItem
        }

        var modoActivo: Bool
        var visibilidad: [Bool] = []
        var esperas: [Espera] = []

        lazy var presenter = SeniasPresenter(
            modoActivo: { [weak self] in self?.modoActivo ?? false },
            actualizarVentana: { [weak self] visible in
                self?.visibilidad.append(visible)
            },
            programarEspera: { [weak self] duracion, trabajo in
                self?.esperas.append(Espera(duracion: duracion, trabajo: trabajo))
            })

        init(modoActivo: Bool = true) {
            self.modoActivo = modoActivo
        }

        func presentarTarjetaActual() {
            guard let clave = presenter.claveVisible else {
                XCTFail("Se esperaba una tarjeta visible.")
                return
            }
            presenter.tarjetaPresentada(clave: clave, id: presenter.idPresentacion)
        }
    }
}
