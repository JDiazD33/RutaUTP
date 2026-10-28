import XCTest
import SwiftUI
@testable import RutaUTP

final class Transportes3DCargaTests: XCTestCase {
    @MainActor
    func testUnAvisoPendienteNoSustituyeElModeloQueSeAcabaDeElegir() async {
        var recibidos: [EstadoTransporte3D] = []
        let coordinador = VisorTransporte3D.Coordinator(estado: Binding(
            get: { .cargando }, set: { recibidos.append($0) }))
        let anterior = UUID()
        coordinador.generacion = anterior
        let avisoAnterior = coordinador.publicar(.listo(.micro, .original), generacion: anterior)

        // Cambiar de opcion antes de que SwiftUI reciba la notificacion anterior.
        let actual = UUID()
        coordinador.generacion = actual
        let avisoActual = coordinador.publicar(.listo(.colectivo, .detallado), generacion: actual)
        await avisoAnterior.value
        await avisoActual.value

        XCTAssertEqual(recibidos, [.listo(.colectivo, .detallado)])
    }

    @MainActor
    func testCerrarElVisorDescartaLosAvisosYaEncolados() async {
        var recibidos: [EstadoTransporte3D] = []
        let coordinador = VisorTransporte3D.Coordinator(estado: Binding(
            get: { .cargando }, set: { recibidos.append($0) }))
        let carga = UUID()
        coordinador.generacion = carga
        let cargando = coordinador.publicar(.cargando, generacion: carga)
        let listo = coordinador.publicar(.listo(.combi, .detallado), generacion: carga)
        coordinador.generacion = nil
        await cargando.value
        await listo.value

        XCTAssertTrue(recibidos.isEmpty)
    }
}
