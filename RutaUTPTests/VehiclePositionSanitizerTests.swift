//
//  VehiclePositionSanitizerTests.swift
//  RutaUTPTests
//
//  Verifica el filtro de posiciones que llegan por MQTT: el broker es
//  un canal compartido y el consumidor no debe aceptar coordenadas
//  imposibles, timestamps del futuro ni vehículos obsoletos.
//

import XCTest
import CoreLocation
@testable import RutaUTP

final class VehiclePositionSanitizerTests: XCTestCase {

    private var now: TimeInterval {
        1_760_000_000
    }

    /// Una posición razonable debe atravesar el filtro intacta,
    /// con speed y heading normalizados.
    func testPosicionValidaPasaFiltro() throws {
        let position = VehiclePosition(
            id: "baliza-1",
            linea: "10",
            lat: -8.107_722,
            lon: -79.032_589,
            heading: 90,
            speed: 11.4,
            timestamp: now - 3
        )

        let sanitized = try XCTUnwrap(
            VehiclePositionSanitizer.sanitize(
                position,
                now: now
            )
        )

        XCTAssertEqual(sanitized.id, "baliza-1")
        XCTAssertEqual(sanitized.linea, "10")
        XCTAssertEqual(sanitized.lat, -8.107_722)
        XCTAssertEqual(sanitized.lon, -79.032_589)
        XCTAssertEqual(sanitized.speed, 11.4)
        XCTAssertEqual(sanitized.heading, 90)
    }

    func testLatitudFueraDeRangoSeDescarta() {
        let position = VehiclePosition(
            id: "baliza-2",
            linea: "10",
            lat: 999,
            lon: -79.03,
            timestamp: now - 3
        )

        XCTAssertNil(
            VehiclePositionSanitizer.sanitize(
                position,
                now: now
            )
        )
    }

    func testLongitudNaNSeDescarta() {
        var position = VehiclePosition(
            id: "baliza-3",
            linea: "10",
            lat: -8.10,
            lon: -79.03,
            timestamp: now - 3
        )

        position.lon = .nan

        XCTAssertNil(
            VehiclePositionSanitizer.sanitize(
                position,
                now: now
            )
        )
    }

    /// Un mensaje con timestamp demasiado futuro no debe usarse:
    /// indica reloj mal ajustado o un mensaje manipulado.
    func testTimestampDelFuturoSeDescarta() {
        let position = VehiclePosition(
            id: "baliza-4",
            linea: "10",
            lat: -8.10,
            lon: -79.03,
            timestamp: now + 60
        )

        XCTAssertNil(
            VehiclePositionSanitizer.sanitize(
                position,
                now: now
            )
        )
    }

    /// Un pequeño desfase de reloj hacia adelante es tolerable.
    func testTimestampConSkewMenorAlToleradoPasa() throws {
        let position = VehiclePosition(
            id: "baliza-5",
            linea: "10",
            lat: -8.10,
            lon: -79.03,
            timestamp: now + 5
        )

        XCTAssertNotNil(
            VehiclePositionSanitizer.sanitize(
                position,
                now: now
            )
        )
    }

    /// Una baliza que dejó de transmitir hace más del límite no debe
    /// seguir dibujada: la obsolescencia evita vehículos fantasmas.
    func testPosicionObsoletaSeDescarta() {
        let position = VehiclePosition(
            id: "baliza-6",
            linea: "10",
            lat: -8.10,
            lon: -79.03,
            timestamp: now - VehiclePositionSanitizer.stalenessLimit - 1
        )

        XCTAssertNil(
            VehiclePositionSanitizer.sanitize(
                position,
                now: now
            )
        )
    }

    /// Una baliza dentro del límite de obsolescencia sigue válida.
    func testPosicionDentroDelLimiteDeObsolescenciaPasa() throws {
        let position = VehiclePosition(
            id: "baliza-7",
            linea: "10",
            lat: -8.10,
            lon: -79.03,
            timestamp: now - VehiclePositionSanitizer.stalenessLimit + 5
        )

        XCTAssertNotNil(
            VehiclePositionSanitizer.sanitize(
                position,
                now: now
            )
        )
    }

    /// NaN no es "desconocido": el contrato exige -1 para que el mapa
    /// y los cálculos puedan distinguirlo.
    func testVelocidadNaNSeReemplazaPorDesconocida() throws {
        var position = VehiclePosition(
            id: "baliza-8",
            linea: "10",
            lat: -8.10,
            lon: -79.03,
            timestamp: now - 3
        )

        position.speed = .nan

        let sanitized = try XCTUnwrap(
            VehiclePositionSanitizer.sanitize(
                position,
                now: now
            )
        )

        XCTAssertEqual(sanitized.speed, -1)
    }

    /// Velocidades imposibles se acotan al techo del contrato.
    func testVelocidadAbsurdaSeAcota() throws {
        var position = VehiclePosition(
            id: "baliza-9",
            linea: "10",
            lat: -8.10,
            lon: -79.03,
            timestamp: now - 3
        )

        position.speed = 500

        let sanitized = try XCTUnwrap(
            VehiclePositionSanitizer.sanitize(
                position,
                now: now
            )
        )

        XCTAssertEqual(sanitized.speed, 100)
    }

    /// El rumbo se normaliza al rango [0, 360).
    func testRumboSeNormaliza() throws {
        var position = VehiclePosition(
            id: "baliza-10",
            linea: "10",
            lat: -8.10,
            lon: -79.03,
            timestamp: now - 3
        )

        position.heading = 405

        let sanitized = try XCTUnwrap(
            VehiclePositionSanitizer.sanitize(
                position,
                now: now
            )
        )

        XCTAssertEqual(sanitized.heading, 45)
    }

    /// Un vehículo que avanza hacia el punto consultado obtiene una ETA
    /// calculada sobre el shape, no por distancia en línea recta.
    func testETAVehiculoRealQueSeAcerca() throws {
        let route = testRoute()
        let position = VehiclePosition(
            id: "real-1",
            linea: "10",
            routeId: route.id,
            lat: 0,
            lon: 0.002,
            heading: 90,
            speed: 10,
            timestamp: now
        )

        let eta = VehicleETAEstimator.minutes(
            position: position,
            route: route,
            target: coordinate(0, 0.012)
        )

        XCTAssertEqual(eta, 2)
    }

    /// No se presenta una llegada engañosa cuando el rumbo indica que la
    /// unidad se aleja del destino en una ruta no circular.
    func testETAVehiculoRealQueSeAlejaNoDisponible() {
        let route = testRoute()
        let position = VehiclePosition(
            id: "real-2",
            linea: "10",
            routeId: route.id,
            lat: 0,
            lon: 0.002,
            heading: 270,
            speed: 10,
            timestamp: now
        )

        XCTAssertNil(
            VehicleETAEstimator.minutes(
                position: position,
                route: route,
                target: coordinate(0, 0.012)
            )
        )
    }

    /// Un punto lejano al corredor no debe recibir una ETA de esa línea.
    func testETADestinoFueraDeRutaNoDisponible() {
        let route = testRoute()
        let position = VehiclePosition(
            id: "real-3",
            linea: "10",
            routeId: route.id,
            lat: 0,
            lon: 0.002,
            heading: 90,
            speed: 10,
            timestamp: now
        )

        XCTAssertNil(
            VehicleETAEstimator.minutes(
                position: position,
                route: route,
                target: coordinate(0.02, 0.012)
            )
        )
    }

    func testETASinRumboNoInventaSentido() {
        XCTAssertNil(eta(speed: 10, heading: -1))
        XCTAssertNil(eta(speed: 10, heading: .nan))
    }

    func testETATraficoLentoRespetaVelocidadObservada() {
        // 1.11 km a 1 m/s: cerca de 19 min, no 4 min a velocidad programada.
        XCTAssertEqual(eta(speed: 1), 19)
    }

    func testETADetenidoNoUsaVelocidadProgramada() {
        XCTAssertNil(eta(speed: 0))
        XCTAssertNil(eta(speed: 0.2))
    }

    func testETAVelocidadDesconocidaUsaHorario() {
        XCTAssertEqual(eta(speed: -1), 4)
        XCTAssertNil(eta(speed: .nan))
    }

    func testETARecorridoInversoHaciaDestino() {
        XCTAssertEqual(eta(speed: 10, heading: 270, targetLongitude: 0), 1)
    }

    func testETAMayorDeDosHorasNoSeTrunca() {
        XCTAssertNil(eta(speed: 0.5, targetLongitude: 0.08, route: testRoute(endLongitude: 0.1)))
    }

    private func eta(
        speed: Double,
        heading: Double = 90,
        targetLongitude: Double = 0.012,
        route: RutaGTFS? = nil
    ) -> Int? {
        VehicleETAEstimator.minutes(
            position: VehiclePosition(id: "eta", linea: "10", lat: 0, lon: 0.002,
                                      heading: heading, speed: speed, timestamp: now),
            route: route ?? testRoute(),
            target: coordinate(0, targetLongitude)
        )
    }

    private func testRoute(endLongitude: Double = 0.02) -> RutaGTFS {
        RutaGTFS(
            id: "route-10",
            linea: "10",
            variante: "A",
            recorrido: "Inicio → Fin",
            empresa: "Prueba",
            colorHex: "00AA00",
            color: .green,
            shape: [
                coordinate(0, 0),
                coordinate(0, 0.01),
                coordinate(0, endLongitude)
            ],
            paraderos: [],
            duracionMin: 8,
            headwayMin: 10,
            precio: 2,
            distanciaKm: 2.2,
            distanciaUTPMetros: 0
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
