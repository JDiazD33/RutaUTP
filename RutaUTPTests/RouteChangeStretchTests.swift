import XCTest
import CoreLocation
@testable import RutaUTP

/// Geometría de un cambio de ruta confirmado: qué tramo deja de atender la
/// línea y a qué recorridos afecta. No usa red, GPS ni el servicio MQTT.
@MainActor
final class RouteChangeStretchTests: XCTestCase {
    /// Recorrido recto hacia el norte: un vértice cada 0,01° (~1,1 km).
    private func recorrido(vertices: Int = 5) -> [CLLocationCoordinate2D] {
        (0..<vertices).map { CLLocationCoordinate2D(latitude: -8.10 + Double($0) * 0.01, longitude: -79.03) }
    }

    private func punto(_ latitud: Double, _ longitud: Double = -79.03) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitud, longitude: longitud)
    }

    private func aviso(_ motivo: MotivoCambioRuta, en inicio: CLLocationCoordinate2D,
                       hasta fin: CLLocationCoordinate2D? = nil, ruta: String = "A") -> RouteChangeAlert {
        RouteChangeAlert(id: "aviso", routeId: ruta, reason: motivo.rawValue,
                         lat: inicio.latitude, lon: inicio.longitude, place: "Av. de prueba",
                         confirmations: 3, expiresAt: 2_000_000_000,
                         endLat: fin?.latitude, endLon: fin?.longitude)
    }

    func testTramoSigueElOrdenDelRecorridoSinImportarElOrdenDeLosPuntos() throws {
        let shape = recorrido()
        for (inicio, fin) in [(punto(-8.085), punto(-8.065)), (punto(-8.065), punto(-8.085))] {
            let tramo = try XCTUnwrap(TramoCambioRuta.coordenadas(desde: inicio, hasta: fin, en: shape))
            XCTAssertEqual(tramo.count, 4)
            XCTAssertEqual(tramo.first?.latitude ?? 0, -8.085, accuracy: 1e-6)
            XCTAssertEqual(tramo[1].latitude, -8.08, accuracy: 1e-9)
            XCTAssertEqual(tramo[2].latitude, -8.07, accuracy: 1e-9)
            XCTAssertEqual(tramo.last?.latitude ?? 0, -8.065, accuracy: 1e-6)
            XCTAssertEqual(PolylineMatching.totalLengthMeters(tramo), 2_211, accuracy: 15)
        }
    }

    func testTramoDentroDeUnMismoSegmentoTieneSoloSusDosExtremos() throws {
        let tramo = try XCTUnwrap(TramoCambioRuta.coordenadas(
            desde: punto(-8.088), hasta: punto(-8.083), en: recorrido()))
        XCTAssertEqual(tramo.count, 2)
        XCTAssertEqual(tramo[0].latitude, -8.088, accuracy: 1e-6)
        XCTAssertEqual(tramo[1].latitude, -8.083, accuracy: 1e-6)
    }

    func testNoHayTramoSiUnPuntoQuedaLejosDelRecorrido() {
        // 0,01° de longitud son ~1,1 km: fuera de los 500 m admitidos.
        XCTAssertNil(TramoCambioRuta.coordenadas(
            desde: punto(-8.085), hasta: punto(-8.065, -79.02), en: recorrido()))
    }

    func testNoHayTramoSinPuntoFinalNiConRecorridoVacio() {
        XCTAssertNil(TramoCambioRuta.coordenadas(de: aviso(.desvio, en: punto(-8.085)), en: recorrido()))
        XCTAssertNil(TramoCambioRuta.coordenadas(desde: punto(-8.085), hasta: punto(-8.065), en: []))
    }

    func testUnTramoMayorQueElMaximoSeDescarta() {
        // Diez vértices: ~9,9 km entre los extremos.
        let shape = recorrido(vertices: 10)
        XCTAssertNil(TramoCambioRuta.coordenadas(desde: punto(-8.10), hasta: punto(-8.01), en: shape))
        XCTAssertNotNil(TramoCambioRuta.coordenadas(desde: punto(-8.10), hasta: punto(-8.05), en: shape))
    }

    func testTraficoYChoqueAfectanACualquierLineaQuePasePorElPunto() {
        let tramoABordo = [punto(-8.078), punto(-8.072)]
        for motivo in [MotivoCambioRuta.trafico, .choque] {
            XCTAssertTrue(TramoCambioRuta.afecta(aviso(motivo, en: punto(-8.075, -79.0295), ruta: "B"),
                                                 tramo: nil, recorrido: tramoABordo, mismaRuta: false))
            XCTAssertFalse(TramoCambioRuta.afecta(aviso(motivo, en: punto(-8.095), ruta: "B"),
                                                  tramo: nil, recorrido: tramoABordo, mismaRuta: false))
        }
    }

    func testUnDesvioSoloAfectaASuPropiaLinea() {
        let tramoABordo = [punto(-8.078), punto(-8.072)]
        let desvio = aviso(.desvio, en: punto(-8.075), ruta: "B")
        XCTAssertFalse(TramoCambioRuta.afecta(desvio, tramo: nil, recorrido: tramoABordo, mismaRuta: false))
        XCTAssertTrue(TramoCambioRuta.afecta(desvio, tramo: nil, recorrido: tramoABordo, mismaRuta: true))
    }

    func testUnViajeDentroDelTramoDesviadoQuedaAfectadoAunqueLosExtremosEstenLejos() throws {
        let shape = recorrido()
        let tramoABordo = [punto(-8.078), punto(-8.072)]
        let desvio = aviso(.desvio, en: punto(-8.095), hasta: punto(-8.062))
        let tramo = try XCTUnwrap(TramoCambioRuta.coordenadas(de: desvio, en: shape))
        XCTAssertTrue(TramoCambioRuta.afecta(desvio, tramo: tramo, recorrido: tramoABordo, mismaRuta: true))
        // El mismo desvío sin punto final solo se conoce por dónde empieza.
        XCTAssertFalse(TramoCambioRuta.afecta(aviso(.desvio, en: punto(-8.095)), tramo: nil,
                                              recorrido: tramoABordo, mismaRuta: true))
    }

    func testSoloTraficoYChoqueNoCambianElRecorrido() {
        XCTAssertEqual(MotivoCambioRuta.allCases.map(\.rawValue),
                       ["works", "closure", "detour", "traffic", "crash"])
        XCTAssertEqual(MotivoCambioRuta.allCases.filter { !$0.cambiaRecorrido }, [.trafico, .choque])
    }

    func testUnAvisoSinDetalleSeDecodificaSinViaNiPuntoFinal() throws {
        let json = #"{"id":"a","routeId":"r","reason":"works","lat":-8.1,"lon":-79.03,"place":"Av. X","confirmations":3,"expiresAt":10}"#
        let aviso = try JSONDecoder().decode(RouteChangeAlert.self, from: Data(json.utf8))
        XCTAssertNil(aviso.via)
        XCTAssertNil(aviso.textoVia)
        XCTAssertNil(aviso.coordenadaFin)
        XCTAssertEqual(aviso.motivo, .obras)
    }

    func testUnAvisoConDetalleConservaLaViaYElPuntoFinal() throws {
        let json = #"{"id":"a","routeId":"r","reason":"detour","lat":-8.1,"lon":-79.03,"place":"Av. X","confirmations":4,"expiresAt":10,"via":" Av. Valderrama ","endLat":-8.09,"endLon":-79.03}"#
        let aviso = try JSONDecoder().decode(RouteChangeAlert.self, from: Data(json.utf8))
        XCTAssertEqual(aviso.coordenadaFin?.latitude, -8.09)
        XCTAssertEqual(aviso.coordenadaFin?.longitude, -79.03)
        XCTAssertEqual(aviso.textoVia?.contains("Av. Valderrama"), true)
        XCTAssertEqual(aviso.textoVia?.contains(" Av. Valderrama "), false)
        XCTAssertEqual(aviso.motivo, .desvio)
    }

    func testUnaViaEnBlancoNoSeMuestra() {
        var aviso = aviso(.desvio, en: punto(-8.085))
        aviso.via = "   "
        XCTAssertNil(aviso.textoVia)
    }
}

/// Calle nueva de un desvío: trazo grabado a bordo, su codificación y cuándo
/// se dibuja. No usa red, GPS real ni el servicio MQTT.
@MainActor
final class CalleNuevaDesvioTests: XCTestCase {
    /// Recorrido recto hacia el norte de ~4,4 km.
    private let recorrido = (0..<5).map {
        CLLocationCoordinate2D(latitude: -8.10 + Double($0) * 0.01, longitude: -79.03)
    }
    /// 300 m al este del recorrido, a la latitud de prueba.
    private let este = -79.03 + 300 / (111_320 * cos(8.09 * .pi / 180))

    private func lectura(_ lat: Double, _ lon: Double, segundo: Int,
                         precision: Double = 5) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), altitude: 0,
                   horizontalAccuracy: precision, verticalAccuracy: 5, course: 0, speed: 8,
                   timestamp: Date(timeIntervalSince1970: 1_790_000_000 + TimeInterval(segundo)))
    }

    /// Recorre una lista de puntos cada 3 s y devuelve el primer desvío cerrado.
    private func recorrer(_ puntos: [(Double, Double)], precision: Double = 5,
                          trazador: inout TrazadorDesvio) -> TrazadorDesvio.Desvio? {
        var encontrado: TrazadorDesvio.Desvio?
        for (indice, punto) in puntos.enumerated() {
            let resultado = trazador.procesar(lectura(punto.0, punto.1, segundo: indice * 3, precision: precision),
                                              recorrido: recorrido, routeID: "A")
            if encontrado == nil { encontrado = resultado }
        }
        return encontrado
    }

    /// Tramo recto entre dos puntos, sin incluir el primero.
    private func tramo(de a: (Double, Double), a b: (Double, Double), pasos: Int) -> [(Double, Double)] {
        (1...pasos).map { i in
            let t = Double(i) / Double(pasos)
            return (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t)
        }
    }

    /// Sale 300 m al este en -8.090, sube 660 m y retoma la ruta en -8.084.
    private var desvioCompleto: [(Double, Double)] {
        let antes = tramo(de: (-8.096, -79.03), a: (-8.090, -79.03), pasos: 24)
        let ida = tramo(de: (-8.090, -79.03), a: (-8.090, este), pasos: 14)
        let paralela = tramo(de: (-8.090, este), a: (-8.084, este), pasos: 30)
        let vuelta = tramo(de: (-8.084, este), a: (-8.084, -79.03), pasos: 14)
        let despues = tramo(de: (-8.084, -79.03), a: (-8.080, -79.03), pasos: 16)
        return antes + ida + paralela + vuelta + despues
    }

    func testPolilineaCoincideConElEjemploDeReferencia() throws {
        let texto = "_p~iF~ps|U_ulLnnqC_mqNvxq`@"
        let puntos = try XCTUnwrap(PolilineaCodificada.decodificar(texto))
        let esperados = [(38.5, -120.2), (40.7, -120.95), (43.252, -126.453)]
        XCTAssertEqual(puntos.count, esperados.count)
        for (punto, esperado) in zip(puntos, esperados) {
            XCTAssertEqual(punto.latitude, esperado.0, accuracy: 1e-9)
            XCTAssertEqual(punto.longitude, esperado.1, accuracy: 1e-9)
        }
        XCTAssertEqual(PolilineaCodificada.codificar(puntos), texto)
    }

    func testPolilineaIncompletaOInvalidaSeRechaza() {
        for texto in ["", "?", "_p~iF", "_p~iF~ps|U_", String(repeating: "~", count: 50), "a b"] {
            XCTAssertNil(PolilineaCodificada.decodificar(texto), texto)
        }
    }

    func testDesvioSeCierraAlRetomarLaRutaConExtremosSobreElRecorrido() throws {
        var trazador = TrazadorDesvio()
        let desvio = try XCTUnwrap(recorrer(desvioCompleto, trazador: &trazador))
        XCTAssertEqual(desvio.routeID, "A")
        XCTAssertEqual(desvio.inicio.longitude, -79.03, accuracy: 1e-6)
        XCTAssertEqual(desvio.inicio.latitude, -8.090, accuracy: 0.0005)
        XCTAssertEqual(desvio.fin.longitude, -79.03, accuracy: 1e-6)
        XCTAssertEqual(desvio.fin.latitude, -8.084, accuracy: 0.0005)
        XCTAssertEqual(desvio.masLejano.longitude, este, accuracy: 1e-6)
        XCTAssertEqual(desvio.longitud, 1_260, accuracy: 120)
        XCTAssertFalse(trazador.grabando)
        // El trazo enviado empieza y termina en los extremos, cabe en el
        // servidor y no salta más de lo que este admite.
        let trazo = desvio.trazo
        XCTAssertGreaterThanOrEqual(trazo.count, 3)
        XCTAssertLessThanOrEqual(trazo.count, 120)
        let primero = try XCTUnwrap(trazo.first)
        let ultimo = try XCTUnwrap(trazo.last)
        XCTAssertLessThan(PolylineMatching.distanceMeters(primero, desvio.inicio), 1)
        XCTAssertLessThan(PolylineMatching.distanceMeters(ultimo, desvio.fin), 1)
        for (a, b) in zip(trazo, trazo.dropFirst()) {
            XCTAssertLessThanOrEqual(PolylineMatching.distanceMeters(a, b), TrazoDesvio.pasoMaximo + 1)
        }
        let codificado = PolilineaCodificada.codificar(trazo)
        XCTAssertLessThanOrEqual(codificado.utf8.count, 1_400)
        XCTAssertEqual(PolilineaCodificada.decodificar(codificado)?.count, trazo.count)
    }

    func testRuidoCortoNoAbreUnDesvio() {
        var trazador = TrazadorDesvio()
        let puntos = tramo(de: (-8.096, -79.03), a: (-8.090, -79.03), pasos: 20)
            + [(-8.0898, este), (-8.0896, este)]
            + tramo(de: (-8.0894, -79.03), a: (-8.085, -79.03), pasos: 20)
        XCTAssertNil(recorrer(puntos, trazador: &trazador))
        XCTAssertFalse(trazador.grabando)
    }

    func testVolverDetrasDeLaSalidaNoEsDesvio() {
        var trazador = TrazadorDesvio()
        let puntos = tramo(de: (-8.096, -79.03), a: (-8.090, -79.03), pasos: 24)
            + tramo(de: (-8.090, -79.03), a: (-8.090, este), pasos: 14)
            + tramo(de: (-8.090, este), a: (-8.094, este), pasos: 20)
            + tramo(de: (-8.094, este), a: (-8.094, -79.03), pasos: 14)
            + tramo(de: (-8.094, -79.03), a: (-8.093, -79.03), pasos: 4)
        XCTAssertNil(recorrer(puntos, trazador: &trazador))
    }

    func testLecturasImprecisasNoGraban() {
        var trazador = TrazadorDesvio()
        XCTAssertNil(recorrer(desvioCompleto, precision: 80, trazador: &trazador))
        XCTAssertFalse(trazador.grabando)
    }

    func testTrazoRectoLargoSeRellenaSinSaltosGrandes() {
        let recta = (0...1_000).map { CLLocationCoordinate2D(latitude: -8.10 + Double($0) * 0.000018, longitude: -79.03) }
        let preparado = TrazoDesvio.preparar(recta)
        XCTAssertEqual(preparado.count, 6)
        for (a, b) in zip(preparado, preparado.dropFirst()) {
            XCTAssertLessThanOrEqual(PolylineMatching.distanceMeters(a, b), TrazoDesvio.pasoMaximo + 1)
        }
    }

    func testCalleNuevaSoloSeDibujaEnCambiosDeRecorrido() {
        let path = PolilineaCodificada.codificar([
            CLLocationCoordinate2D(latitude: -8.090, longitude: -79.03),
            CLLocationCoordinate2D(latitude: -8.087, longitude: este),
            CLLocationCoordinate2D(latitude: -8.084, longitude: -79.03)])
        func aviso(_ motivo: MotivoCambioRuta, path: String?) -> RouteChangeAlert {
            RouteChangeAlert(id: motivo.rawValue, routeId: "A", reason: motivo.rawValue, lat: -8.090, lon: -79.03,
                             place: "Av. de prueba", confirmations: 2, expiresAt: 2_000_000_000,
                             endLat: -8.084, endLon: -79.03, path: path)
        }
        XCTAssertEqual(aviso(.desvio, path: path).calleNueva.count, 3)
        XCTAssertEqual(aviso(.obras, path: path).calleNueva.count, 3)
        XCTAssertTrue(aviso(.trafico, path: path).calleNueva.isEmpty)
        XCTAssertTrue(aviso(.desvio, path: nil).calleNueva.isEmpty)
        XCTAssertTrue(aviso(.desvio, path: "no válida").calleNueva.isEmpty)
    }
}
