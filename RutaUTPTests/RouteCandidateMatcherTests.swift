import XCTest
import CoreLocation
@testable import RutaUTP

final class RouteCandidateMatcherTests: XCTestCase {

    func testDevuelveNilSinRutas() {
        let result = RouteCandidateMatcher.closestMatch(
            for: location(),
            routes: []
        )

        XCTAssertNil(result)
    }

    /// Devuelve la ruta más cercana aunque esté a kilómetros.
    ///
    /// El matcher **no** filtra por umbral: informa de la distancia y deja que
    /// `PassengerDetectionEngine` decida con su propio
    /// `maximumDistanceToRoute`. Fijarlo aquí evita que alguien "arregle" el
    /// matcher para que devuelva `nil` fuera de rango: el motor dejaría de
    /// recibir muestras y la detección se quedaría congelada sin ningún error.
    func testDevuelveLaRutaMasCercanaAunqueEsteLejos() throws {
        let result = try XCTUnwrap(
            RouteCandidateMatcher.closestMatch(
                for: location(
                    latitude: -8.2000,
                    longitude: -79.0300
                ),
                routes: [
                    route(
                        id: "route-lejos",
                        linea: "10",
                        latitude: -8.1000
                    )
                ]
            )
        )

        XCTAssertEqual(result.routeID, "route-lejos")
        XCTAssertGreaterThan(result.distanceToRoute, 5000)
    }

    func testSeleccionaLaRutaMasCercana() throws {
        let nearbyRoute = route(
            id: "near",
            linea: "C-01",
            latitude: -8.1000
        )

        let distantRoute = route(
            id: "far",
            linea: "H",
            latitude: -8.1200
        )

        let result = try XCTUnwrap(
            RouteCandidateMatcher.closestMatch(
                for: location(
                    latitude: -8.1001,
                    longitude: -79.0300
                ),
                routes: [
                    distantRoute,
                    nearbyRoute
                ]
            )
        )

        XCTAssertEqual(result.routeID, "near")
        XCTAssertEqual(result.linea, "C-01")
    }

    func testCalculaDistanciaCercanaAlShape() throws {
        let result = try XCTUnwrap(
            RouteCandidateMatcher.closestMatch(
                for: location(
                    latitude: -8.1000,
                    longitude: -79.0300
                ),
                routes: [
                    route(
                        id: "route-1",
                        linea: "10",
                        latitude: -8.1000
                    )
                ]
            )
        )

        XCTAssertLessThan(
            result.distanceToRoute,
            2
        )
    }

    func testRumboEsteCoincideConRutaEste() throws {
        let result = try XCTUnwrap(
            RouteCandidateMatcher.closestMatch(
                for: location(
                    latitude: -8.1000,
                    longitude: -79.0300,
                    course: 90
                ),
                routes: [
                    route(
                        id: "route-east",
                        linea: "10",
                        latitude: -8.1000
                    )
                ]
            )
        )

        XCTAssertLessThan(
            result.headingDifference,
            5
        )
    }

    func testDetectaDireccionContraria() throws {
        let result = try XCTUnwrap(
            RouteCandidateMatcher.closestMatch(
                for: location(
                    latitude: -8.1000,
                    longitude: -79.0300,
                    course: 270
                ),
                routes: [
                    route(
                        id: "route-east",
                        linea: "10",
                        latitude: -8.1000
                    )
                ]
            )
        )

        XCTAssertGreaterThan(
            result.headingDifference,
            170
        )
    }

    /// El descarte por caja envolvente no debe cambiar el resultado.
    ///
    /// La optimización salta las rutas cuya caja ya está más lejos que la mejor
    /// candidata encontrada. Si el orden de entrada alterara la elegida, sería
    /// una aproximación y no un descarte exacto.
    func testElDescartePorCajaNoCambiaElResultado() throws {
        let cercana = route(id: "cerca", linea: "C-01", latitude: -8.1000)
        let media = route(id: "media", linea: "H", latitude: -8.1200)
        let lejana = route(id: "lejos", linea: "M", latitude: -8.3000)

        let punto = location(latitude: -8.1001, longitude: -79.0300)

        let deFrente = try XCTUnwrap(
            RouteCandidateMatcher.closestMatch(
                for: punto,
                routes: [cercana, media, lejana]
            )
        )

        let invertido = try XCTUnwrap(
            RouteCandidateMatcher.closestMatch(
                for: punto,
                routes: [lejana, media, cercana]
            )
        )

        XCTAssertEqual(deFrente.routeID, "cerca")
        XCTAssertEqual(invertido.routeID, deFrente.routeID)
        XCTAssertEqual(
            invertido.distanceToRoute,
            deFrente.distanceToRoute,
            accuracy: 0.001
        )
    }

    func testCalculaDistanciaAlParaderoMasCercano() throws {
        let route = DetectionRouteGeometry(
            id: "route-stop",
            linea: "10",
            shape: [
                coordinate(-8.1000, -79.0400),
                coordinate(-8.1000, -79.0200)
            ],
            stops: [
                coordinate(-8.1000, -79.0300),
                coordinate(-8.1000, -79.0200)
            ]
        )

        let result = try XCTUnwrap(
            RouteCandidateMatcher.closestMatch(
                for: location(
                    latitude: -8.1000,
                    longitude: -79.0300
                ),
                routes: [route]
            )
        )

        XCTAssertLessThan(
            result.distanceToNearestStop,
            2
        )
    }

    private func route(
        id: String,
        linea: String,
        latitude: Double
    ) -> DetectionRouteGeometry {
        DetectionRouteGeometry(
            id: id,
            linea: linea,
            shape: [
                coordinate(latitude, -79.0400),
                coordinate(latitude, -79.0200)
            ],
            stops: [
                coordinate(latitude, -79.0350),
                coordinate(latitude, -79.0250)
            ]
        )
    }

    private func location(
        latitude: Double = -8.1000,
        longitude: Double = -79.0300,
        course: Double = 90
    ) -> CLLocation {
        CLLocation(
            coordinate: coordinate(
                latitude,
                longitude
            ),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: course,
            speed: 10,
            timestamp: Date()
        )
    }

    private func coordinate(
        _ latitude: Double,
        _ longitude: Double
    ) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: latitude,
            longitude: longitude
        )
    }
}
