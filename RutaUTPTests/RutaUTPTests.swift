import XCTest
import CoreLocation
@testable import RutaUTP

final class RutaUTPTests: XCTestCase {

    // MARK: - Validación de entrada

    func testMatchDevuelveNilConPolylineVacia() {
        let punto = CLLocationCoordinate2D(
            latitude: -8.0982,
            longitude: -79.0381
        )

        let resultado = PolylineMatching.match(
            point: punto,
            on: []
        )

        XCTAssertNil(resultado)
    }

    func testMatchDevuelveNilConUnSoloPunto() {
        let punto = CLLocationCoordinate2D(
            latitude: -8.0982,
            longitude: -79.0381
        )

        let resultado = PolylineMatching.match(
            point: punto,
            on: [punto]
        )

        XCTAssertNil(resultado)
    }

    // MARK: - Proyección sobre una ruta

    func testMatchDetectaPuntoSobreRuta() throws {
        let ruta = [
            CLLocationCoordinate2D(
                latitude: -8.1000,
                longitude: -79.0400
            ),
            CLLocationCoordinate2D(
                latitude: -8.1000,
                longitude: -79.0200
            )
        ]

        let puntoCentral = CLLocationCoordinate2D(
            latitude: -8.1000,
            longitude: -79.0300
        )

        let resultado = try XCTUnwrap(
            PolylineMatching.match(
                point: puntoCentral,
                on: ruta,
                thresholdMeters: 20
            )
        )

        XCTAssertTrue(resultado.isOnRoute)
        XCTAssertEqual(resultado.segmentIndex, 0)
        XCTAssertEqual(
            resultado.progressFraction,
            0.5,
            accuracy: 0.02
        )
        XCTAssertLessThan(resultado.distanceToRoute, 1)
    }

    func testMatchDetectaPuntoFueraDeRuta() throws {
        let ruta = [
            CLLocationCoordinate2D(
                latitude: -8.1000,
                longitude: -79.0400
            ),
            CLLocationCoordinate2D(
                latitude: -8.1000,
                longitude: -79.0200
            )
        ]

        let puntoAlejado = CLLocationCoordinate2D(
            latitude: -8.0900,
            longitude: -79.0300
        )

        let resultado = try XCTUnwrap(
            PolylineMatching.match(
                point: puntoAlejado,
                on: ruta,
                thresholdMeters: 20
            )
        )

        XCTAssertFalse(resultado.isOnRoute)
        XCTAssertGreaterThan(
            resultado.distanceToRoute,
            20
        )
    }

    // MARK: - Decimación

    func testDecimateReduceCantidadDePuntos() {
        let puntos = (0..<100).map { indice in
            CLLocationCoordinate2D(
                latitude: -8.1000,
                longitude: -79.0400 + Double(indice) * 0.0001
            )
        }

        let resultado = PolylineMatching.decimate(
            puntos,
            maxPoints: 10
        )

        XCTAssertEqual(resultado.count, 10)
    }

    func testDecimateConservaPrimerYUltimoPunto() throws {
        let puntos = (0..<100).map { indice in
            CLLocationCoordinate2D(
                latitude: -8.1000 + Double(indice) * 0.0001,
                longitude: -79.0400 + Double(indice) * 0.0001
            )
        }

        let resultado = PolylineMatching.decimate(
            puntos,
            maxPoints: 10
        )

        let primero = try XCTUnwrap(resultado.first)
        let ultimo = try XCTUnwrap(resultado.last)
        let primeroOriginal = try XCTUnwrap(puntos.first)
        let ultimoOriginal = try XCTUnwrap(puntos.last)

        XCTAssertEqual(
            primero.latitude,
            primeroOriginal.latitude,
            accuracy: 0.0000001
        )
        XCTAssertEqual(
            primero.longitude,
            primeroOriginal.longitude,
            accuracy: 0.0000001
        )
        XCTAssertEqual(
            ultimo.latitude,
            ultimoOriginal.latitude,
            accuracy: 0.0000001
        )
        XCTAssertEqual(
            ultimo.longitude,
            ultimoOriginal.longitude,
            accuracy: 0.0000001
        )
    }

    func testDecimateNoModificaUnaListaPequena() {
        let puntos = [
            CLLocationCoordinate2D(
                latitude: -8.1000,
                longitude: -79.0400
            ),
            CLLocationCoordinate2D(
                latitude: -8.1000,
                longitude: -79.0300
            ),
            CLLocationCoordinate2D(
                latitude: -8.1000,
                longitude: -79.0200
            )
        ]

        let resultado = PolylineMatching.decimate(
            puntos,
            maxPoints: 10
        )

        XCTAssertEqual(resultado.count, puntos.count)
    }

    // MARK: - Detección de desvíos

    func testShouldRecalculateDespuesDeTresDesvios() {
        let debeRecalcular = PolylineMatching.shouldRecalculate(
            lastMatch: nil,
            consecutiveOffRouteCount: 3,
            thresholdCount: 3
        )

        XCTAssertTrue(debeRecalcular)
    }
    func testShouldRecalculateAlAlcanzarUmbral() throws {
        let ruta = [
            CLLocationCoordinate2D(
                latitude: -8.1000,
                longitude: -79.0400
            ),
            CLLocationCoordinate2D(
                latitude: -8.1000,
                longitude: -79.0200
            )
        ]

        let resultado = try XCTUnwrap(
            PolylineMatching.match(
                point: ruta[0],
                on: ruta
            )
        )

        XCTAssertFalse(
            PolylineMatching.shouldRecalculate(
                lastMatch: resultado,
                consecutiveOffRouteCount: 2,
                thresholdCount: 3
            )
        )

        XCTAssertTrue(
            PolylineMatching.shouldRecalculate(
                lastMatch: resultado,
                consecutiveOffRouteCount: 3,
                thresholdCount: 3
            )
        )
    }
}
