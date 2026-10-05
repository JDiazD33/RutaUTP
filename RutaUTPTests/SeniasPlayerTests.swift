import XCTest
import AVFoundation
@testable import RutaUTP

@MainActor
final class SeniasPlayerTests: XCTestCase {
    private func clip(_ archivo: String = "modo_senias", idioma: String = "es") throws -> URL {
        try XCTUnwrap(Bundle.main.url(forResource: archivo, withExtension: "mp4",
                                      subdirectory: "senias/clips/\(idioma)"))
    }

    private func player(_ vista: SeniasPlayerUIView) throws -> AVQueuePlayer {
        let capa = try XCTUnwrap(vista.layer.sublayers?.first as? AVPlayerLayer)
        return try XCTUnwrap(capa.player as? AVQueuePlayer)
    }

    func testActivacionConservaEncuadreCompletoYNoPreparaUnBucle() throws {
        let vista = SeniasPlayerUIView(frame: CGRect(x: 0, y: 0, width: 350, height: 360))
        defer { vista.limpiar() }
        vista.configurar(url: try clip(), id: UUID(), repetir: false)
        let capa = try XCTUnwrap(vista.layer.sublayers?.first as? AVPlayerLayer)
        XCTAssertEqual(capa.videoGravity, .resizeAspect)
        XCTAssertEqual(try player(vista).items().count, 1)
        XCTAssertTrue(try player(vista).isMuted)
    }

    func testMismoClipYMismaSolicitudNoReiniciaReproductor() throws {
        let vista = SeniasPlayerUIView()
        defer { vista.limpiar() }
        let url = try clip(), id = UUID()
        vista.configurar(url: url, id: id, repetir: false)
        let primero = try player(vista)
        vista.configurar(url: url, id: id, repetir: false)
        XCTAssertTrue(try player(vista) === primero)
    }

    func testNuevaActivacionDelMismoClipReemplazaYPausaAnterior() throws {
        let vista = SeniasPlayerUIView()
        defer { vista.limpiar() }
        let url = try clip()
        vista.configurar(url: url, id: UUID(), repetir: false)
        let primero = try player(vista)
        vista.configurar(url: url, id: UUID(), repetir: false)
        XCTAssertFalse(try player(vista) === primero)
        XCTAssertEqual(primero.rate, 0)
    }

    func testFinDelIdiomaAnteriorNoFinalizaElIdiomaNuevo() throws {
        let vista = SeniasPlayerUIView()
        defer { vista.limpiar() }
        let id = UUID()
        var finalesES = 0, finalesEN = 0
        vista.configurar(url: try clip(), id: id, repetir: false, alFinalizar: { finalesES += 1 })
        let anterior = try XCTUnwrap(try player(vista).currentItem)
        vista.configurar(url: try clip(idioma: "en"), id: id, repetir: false,
                         alFinalizar: { finalesEN += 1 })
        let actual = try XCTUnwrap(try player(vista).currentItem)
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: anterior)
        XCTAssertEqual(finalesES, 0)
        XCTAssertEqual(finalesEN, 0)
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: actual)
        XCTAssertEqual(finalesEN, 1)
    }

    func testNotificacionesDuplicadasEntreganElResultadoUnaVez() throws {
        let vista = SeniasPlayerUIView()
        defer { vista.limpiar() }
        var finales = 0, errores = 0
        vista.configurar(url: try clip(), id: UUID(), repetir: false,
                         alFinalizar: { finales += 1 }, alFallar: { errores += 1 })
        let item = try XCTUnwrap(try player(vista).currentItem)
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: item)
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: item)
        NotificationCenter.default.post(name: .AVPlayerItemFailedToPlayToEndTime, object: item)
        XCTAssertEqual(finales, 1)
        XCTAssertEqual(errores, 0)
    }

    func testLimpiarLiberaCapaYPausaVideoSinCallbackTardio() throws {
        let vista = SeniasPlayerUIView()
        var finales = 0
        vista.configurar(url: try clip(), id: UUID(), repetir: false, alFinalizar: { finales += 1 })
        let anterior = try player(vista)
        let item = try XCTUnwrap(anterior.currentItem)
        vista.limpiar()
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: item)
        XCTAssertEqual(anterior.rate, 0)
        XCTAssertTrue(vista.layer.sublayers?.isEmpty ?? true)
        XCTAssertEqual(finales, 0)
    }

    func testConsultaNormalSigueEnBucleYNoLlamaAlCierreAutomatico() throws {
        let vista = SeniasPlayerUIView()
        defer { vista.limpiar() }
        var finales = 0
        vista.configurar(url: try clip("guia_paso_a_paso"), id: UUID(), repetir: true,
                         encuadreCompleto: true,
                         alFinalizar: { finales += 1 })
        let capa = try XCTUnwrap(vista.layer.sublayers?.first as? AVPlayerLayer)
        XCTAssertEqual(capa.videoGravity, .resizeAspect)
        let item = try XCTUnwrap(try player(vista).currentItem)
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: item)
        XCTAssertGreaterThan(try player(vista).items().count, 1)
        XCTAssertEqual(finales, 0)
    }

    func testArchivoIlegibleEntregaErrorRealDeAVFoundation() async {
        let vista = SeniasPlayerUIView()
        defer { vista.limpiar() }
        let error = expectation(description: "AVPlayerItem rechaza archivo ausente")
        var errores = 0
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).mp4")
        vista.configurar(url: url, id: UUID(), repetir: false, alFallar: {
            errores += 1
            error.fulfill()
        })
        await fulfillment(of: [error], timeout: 5)
        XCTAssertEqual(errores, 1)
    }

    func testVideoModoESFinalizaRealmenteYCierraPresentacion() async throws {
        try await reproducirActivacionHastaElFinal(idioma: "es")
    }

    func testVideoModoENFinalizaRealmenteYCierraPresentacion() async throws {
        try await reproducirActivacionHastaElFinal(idioma: "en")
    }

    private func reproducirActivacionHastaElFinal(idioma: String) async throws {
        let vista = SeniasPlayerUIView()
        defer { vista.limpiar() }
        let presenter = SeniasPresenter(modoActivo: { true }, actualizarVentana: { _ in },
                                       programarEspera: { _, _ in XCTFail("No debe usar los 3 s") })
        presenter.mostrarActivacionDelModo()
        let id = presenter.idPresentacion
        let fin = expectation(description: "Fin real del video \(idioma)")
        vista.configurar(url: try clip(idioma: idioma), id: id, repetir: false, alFinalizar: {
            presenter.videoFinalizado(id: id)
            fin.fulfill()
        }, alFallar: { XCTFail("No se pudo reproducir el clip incluido") })
        await fulfillment(of: [fin], timeout: 10)
        XCTAssertNil(presenter.claveVisible)
        XCTAssertFalse(presenter.esActivacionDelModo)
    }

    func testLasDosGuiasIncluidasSonVideoReproducibleConDuracionCompleta() async throws {
        for (idioma, duracion) in [("es", 7.2072), ("en", 6.473133)] {
            let asset = AVURLAsset(url: try clip("guia_paso_a_paso", idioma: idioma))
            let pistas = try await asset.loadTracks(withMediaType: .video)
            XCTAssertEqual(pistas.count, 1)
            let reproducible = try await asset.load(.isPlayable)
            XCTAssertTrue(reproducible)
            let segundos = try await asset.load(.duration).seconds
            XCTAssertEqual(segundos, duracion, accuracy: 0.04)
        }
    }
}
