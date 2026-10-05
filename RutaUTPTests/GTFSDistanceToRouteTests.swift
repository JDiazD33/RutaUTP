//
//  GTFSDistanceToRouteTests.swift
//  RutaUTPTests
//
//  E09: cercanía al recorrido completo, incluidos interiores de segmentos.
//  Geometrías locales sintéticas; sin sensores, feed externo ni persistencia.
//

import XCTest
import CoreLocation
import SwiftUI
@testable import RutaUTP

final class GTFSDistanceToRouteTests: XCTestCase {

    private let origen = CLLocationCoordinate2D(latitude: -8.10, longitude: -79.04)

    private func punto(norte: Double, este: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: origen.latitude + norte / 111_320,
            longitude: origen.longitude + este / (111_320 * cos(origen.latitude * .pi / 180))
        )
    }

    private func horizontal(norte: Double) -> [CLLocationCoordinate2D] {
        [punto(norte: norte, este: -1_000), punto(norte: norte, este: 1_000)]
    }

    /// La métrica GTFS anterior usa una esfera de radio 6 371 km.
    /// Esta forma atan2 evita depender de CLLocation o de la implementación
    /// productiva que usa asin.
    private func distanciaEsferica(_ a: CLLocationCoordinate2D,
                                   _ b: CLLocationCoordinate2D) -> Double {
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let latA = a.latitude * .pi / 180
        let latB = b.latitude * .pi / 180
        let h = min(1, max(0, pow(sin(dLat / 2), 2)
            + cos(latA) * cos(latB) * pow(sin(dLon / 2), 2)))
        return 6_371_000 * 2 * atan2(sqrt(h), sqrt(1 - h))
    }

    /// Proyección de referencia con diferencias relativas en grados. Evita
    /// reutilizar projectedPoint o match y no resta coordenadas absolutas
    /// convertidas a metros como hace el helper compartido.
    private func referencia(_ destino: CLLocationCoordinate2D,
                            sobre shape: [CLLocationCoordinate2D]) -> Double {
        guard !shape.isEmpty else { return .infinity }
        var distancias = shape.map { distanciaEsferica(destino, $0) }
        for (a, b) in zip(shape, shape.dropFirst()) {
            let escalaLon = cos(a.latitude * .pi / 180)
            let dx = (b.longitude - a.longitude) * escalaLon
            let dy = b.latitude - a.latitude
            let px = (destino.longitude - a.longitude) * escalaLon
            let py = destino.latitude - a.latitude
            let longitud2 = dx * dx + dy * dy
            let t = longitud2 > 0 ? min(1, max(0, (px * dx + py * dy) / longitud2)) : 0
            let proyectado = CLLocationCoordinate2D(
                latitude: a.latitude + t * (b.latitude - a.latitude),
                longitude: a.longitude + t * (b.longitude - a.longitude)
            )
            distancias.append(distanciaEsferica(destino, proyectado))
        }
        return distancias.min() ?? .infinity
    }

    private func ruta(_ id: String, shape: [CLLocationCoordinate2D]) -> RutaGTFS {
        RutaGTFS(
            id: id, linea: "C-01", variante: "B", recorrido: "A → B",
            empresa: "Empresa local", colorHex: "123456", color: .blue,
            shape: shape, paraderos: [], duracionMin: 25, headwayMin: 8,
            precio: 2.5, distanciaKm: 12.3, distanciaUTPMetros: 789
        )
    }

    func testCentroDeSegmentoLargoEsCercanoAunqueAmbosVerticesQuedenFuera() {
        let shape = horizontal(norte: 0)
        let destino = origen

        XCTAssertGreaterThan(distanciaEsferica(destino, shape[0]), 800)
        XCTAssertGreaterThan(distanciaEsferica(destino, shape[1]), 800)
        XCTAssertEqual(GTFSRepository.distanciaMinima(shape, a: destino), 0, accuracy: 0.001)
    }

    func testDistanciaPerpendicularSeMideAlInteriorDelSegmento() {
        let shape = horizontal(norte: 0)
        let destino = punto(norte: 450, este: 150)

        let esperado = distanciaEsferica(destino, punto(norte: 0, este: 150))
        XCTAssertEqual(GTFSRepository.distanciaMinima(shape, a: destino), esperado, accuracy: 0.000001)
    }

    func testProyeccionAnteriorAlInicioSeLimitaAlExtremoInicial() {
        let shape = [origen, punto(norte: 0, este: 1_000)]
        let destino = punto(norte: 80, este: -150)

        XCTAssertEqual(GTFSRepository.distanciaMinima(shape, a: destino), distanciaEsferica(destino, origen), accuracy: 0.000001)
    }

    func testProyeccionPosteriorAlFinalSeLimitaAlExtremoFinal() {
        let shape = [origen, punto(norte: 0, este: 1_000)]
        let destino = punto(norte: 120, este: 1_100)

        XCTAssertEqual(GTFSRepository.distanciaMinima(shape, a: destino), distanciaEsferica(destino, shape[1]), accuracy: 0.000001)
    }

    func testRecorridoEnLEligeElTramoCercanoYNoSusVertices() {
        let shape = [origen, punto(norte: 0, este: 1_000), punto(norte: 1_000, este: 1_000)]
        let destino = punto(norte: 30, este: 500)

        XCTAssertGreaterThan(shape.map { distanciaEsferica(destino, $0) }.min() ?? 0, 400)
        XCTAssertEqual(GTFSRepository.distanciaMinima(shape, a: destino), distanciaEsferica(destino, punto(norte: 0, este: 500)), accuracy: 0.000001)
    }

    func testSeEvaluaTambienUnTramoIntermedioDelRecorrido() {
        let shape = [
            punto(norte: 0, este: 0),
            punto(norte: 0, este: 1_000),
            punto(norte: 1_000, este: 1_000),
            punto(norte: 1_000, este: 0),
            punto(norte: 2_000, este: 0)
        ]
        let destino = punto(norte: 980, este: 300)

        XCTAssertEqual(PolylineMatching.match(point: destino, on: shape)?.segmentIndex, 2)
        XCTAssertEqual(GTFSRepository.distanciaMinima(shape, a: destino), distanciaEsferica(destino, punto(norte: 1_000, este: 300)), accuracy: 0.000001)
    }

    func testGeometriaVaciaDevuelveInfinito() {
        XCTAssertEqual(GTFSRepository.distanciaMinima([], a: origen), .infinity)
    }

    func testUnPuntoConservaSuDistanciaSinInventarUnSegmento() {
        let unico = punto(norte: 200, este: 100)
        let esperada = distanciaEsferica(origen, unico)

        XCTAssertGreaterThan(esperada, 0)
        XCTAssertEqual(GTFSRepository.distanciaMinima([unico], a: origen), esperada, accuracy: 0.000001)
    }

    func testVerticesRepetidosNoOcultanElSegmentoValido() {
        let a = punto(norte: 0, este: -1_000)
        let b = punto(norte: 0, este: 1_000)
        let destino = punto(norte: 123, este: 80)
        let normal = GTFSRepository.distanciaMinima([a, b], a: destino)
        let repetida = GTFSRepository.distanciaMinima([a, a, b, b], a: destino)

        XCTAssertEqual(normal, distanciaEsferica(destino, punto(norte: 0, este: 80)), accuracy: 0.000001)
        XCTAssertEqual(repetida, normal, accuracy: 0.000001)
    }

    func testTodosLosSegmentosDegeneradosConservanDistanciaFinita() {
        let unico = punto(norte: 200, este: -100)
        let esperada = distanciaEsferica(origen, unico)
        let distancia = GTFSRepository.distanciaMinima([unico, unico, unico], a: origen)

        XCTAssertTrue(distancia.isFinite)
        XCTAssertEqual(distancia, esperada, accuracy: 0.000001)
    }

    func testDistanciaCoincideConReferenciaExhaustivaYMetricaGTFS() {
        let shapes = [
            horizontal(norte: 50),
            [origen, punto(norte: 600, este: 500), punto(norte: 100, este: 1_000)],
            [origen, origen, punto(norte: 700, este: 0), punto(norte: 700, este: 900)]
        ]
        let destinos = [
            punto(norte: 0, este: 0),
            punto(norte: 300, este: 400),
            punto(norte: -200, este: -300),
            punto(norte: 1_000, este: 1_100)
        ]

        for (indice, shape) in shapes.enumerated() {
            for destino in destinos {
                XCTAssertEqual(
                    GTFSRepository.distanciaMinima(shape, a: destino),
                    referencia(destino, sobre: shape),
                    accuracy: 0.000001,
                    "Geometría \(indice)"
                )
            }
        }
    }

    func testInvertirElRecorridoConservaDistanciaDentroDeToleranciaLocal() {
        let shape = [origen, punto(norte: 500, este: 800), punto(norte: 1_000, este: 200)]
        let destino = punto(norte: 620, este: 620)
        let ida = GTFSRepository.distanciaMinima(shape, a: destino)
        let vuelta = GTFSRepository.distanciaMinima(Array(shape.reversed()), a: destino)

        // La proyección local usa la latitud del inicio del tramo; el cambio
        // de orientación tiene una diferencia ínfima en esta geometría urbana.
        XCTAssertEqual(ida, vuelta, accuracy: 0.1)
    }

    func testAgregarVerticesColinealesNoCambiaLaCercania() {
        let simple = horizontal(norte: 0)
        let densa = stride(from: -1_000.0, through: 1_000.0, by: 100).map {
            punto(norte: 0, este: $0)
        }
        let destino = punto(norte: 375, este: 425)

        XCTAssertEqual(
            GTFSRepository.distanciaMinima(simple, a: destino),
            GTFSRepository.distanciaMinima(densa, a: destino),
            accuracy: 0.000001
        )
    }

    func testCoordenadasInvalidasNoProducenUnTramoQueSaltaElHueco() {
        let invalido = CLLocationCoordinate2D(latitude: 91, longitude: -79)
        let conHueco = [punto(norte: 0, este: -1_000), invalido, punto(norte: 0, este: 1_000)]
        let distancia = GTFSRepository.distanciaMinima(conHueco, a: origen)

        XCTAssertTrue(distancia.isFinite)
        XCTAssertGreaterThan(distancia, 800, "Los extremos válidos no se unen atravesando una coordenada inválida")
        XCTAssertEqual(GTFSRepository.distanciaMinima([invalido, invalido], a: origen), .infinity)
        XCTAssertEqual(GTFSRepository.distanciaMinima(horizontal(norte: 0), a: invalido), .infinity)
        XCTAssertEqual(GTFSRepository.distanciaMinima(horizontal(norte: 0), a: CLLocationCoordinate2D(latitude: .nan, longitude: -79)), .infinity)
    }

    func testConsultaMantieneRadioDefault400YPermiteAmpliacion800() {
        let feed = [
            ruta("fuera800", shape: horizontal(norte: 803)),
            ruta("cerca800", shape: horizontal(norte: 798)),
            ruta("fuera400", shape: horizontal(norte: 402)),
            ruta("cerca400", shape: horizontal(norte: 399))
        ]

        XCTAssertEqual(GTFSRepository.rutasQuePasanPor(origen, en: feed).map(\.id), ["cerca400"])
        XCTAssertEqual(GTFSRepository.rutasQuePasanPor(origen, en: feed, radioMetros: 800).map(\.id), ["cerca400", "fuera400", "cerca800"])
    }

    func testRadioEsInclusivoParaLaDistanciaCalculadaYNoParaUnRadioMenor() {
        let unaRuta = ruta("frontera", shape: horizontal(norte: 400))
        let distancia = GTFSRepository.distanciaMinima(unaRuta.shape, a: origen)
        XCTAssertTrue(distancia.isFinite)
        XCTAssertGreaterThan(distancia, 0)

        XCTAssertEqual(GTFSRepository.rutasQuePasanPor(origen, en: [unaRuta], radioMetros: distancia).map(\.id), ["frontera"])
        XCTAssertTrue(GTFSRepository.rutasQuePasanPor(origen, en: [unaRuta], radioMetros: distancia - 0.0001).isEmpty)
        XCTAssertEqual(GTFSRepository.rutasQuePasanPor(origen, en: [unaRuta], radioMetros: distancia + 0.0001).map(\.id), ["frontera"])
    }

    func testConsultaOrdenaDistanciasYExcluyeGeometriaInsuficienteSinAlterarRutas() {
        let invalido = CLLocationCoordinate2D(latitude: 91, longitude: -79)
        let cerca = ruta("interior", shape: horizontal(norte: 0))
        let otra = ruta("a100", shape: horizontal(norte: 100))
        let feed = [
            ruta("vacia", shape: []),
            otra,
            ruta("punto", shape: [origen]),
            ruta("invalida", shape: [invalido, invalido]),
            cerca
        ]
        let coordenadasOriginales = cerca.shape.map { [$0.latitude, $0.longitude] }
        let longitudOriginal = PolylineMatching.totalLengthMeters(cerca.shape)
        let resultado = GTFSRepository.rutasQuePasanPor(origen, en: feed, radioMetros: .infinity)

        XCTAssertEqual(resultado.map(\.id), ["interior", "a100"])
        guard let primera = resultado.first else { return XCTFail("Debe conservar la ruta cercana") }
        XCTAssertEqual(primera.shape.map { [$0.latitude, $0.longitude] }, coordenadasOriginales)
        XCTAssertEqual(PolylineMatching.totalLengthMeters(primera.shape), longitudOriginal, accuracy: 0.000001)
        XCTAssertEqual(primera.linea, cerca.linea)
        XCTAssertEqual(primera.variante, cerca.variante)
        XCTAssertEqual(primera.recorrido, cerca.recorrido)
        XCTAssertEqual(primera.empresa, cerca.empresa)
        XCTAssertEqual(primera.precio, cerca.precio)
        XCTAssertEqual(primera.duracionMin, cerca.duracionMin)
        XCTAssertEqual(primera.headwayMin, cerca.headwayMin)
        XCTAssertEqual(primera.distanciaKm, cerca.distanciaKm)
        XCTAssertEqual(primera.distanciaUTPMetros, cerca.distanciaUTPMetros)
    }
}
