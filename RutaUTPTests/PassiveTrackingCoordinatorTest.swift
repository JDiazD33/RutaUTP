//
//  PassiveTrackingCoordinatorTests.swift
//  RutaUTPTests
//
//  Pruebas de la coordinación entre detección de pasajero y publicación.
//
//  Estas pruebas no utilizan GPS, Core Motion ni Mosquitto reales.
//  Emplean geometrías y muestras controladas para verificar exactamente
//  cuándo se inicia, utiliza y detiene una sesión de observaciones.
//

import XCTest
import CoreLocation
import Combine
@testable import RutaUTP

/// Verifica el ciclo de vida de una sesión de observaciones.
///
/// La clase se ejecuta en `MainActor` porque tanto
/// `PassiveTrackingCoordinator` como `ObservationPublishing` están
/// aislados en el actor principal.
@MainActor
final class PassiveTrackingCoordinatorTests:
    XCTestCase {

    /// Dos muestras vehiculares todavía no deben iniciar ni publicar
    /// una sesión, porque el umbral vigente exige tres muestras.
    func testNoPublicaAntesDeConfirmarAbordaje() {
        let publisher = MockObservationPublisher()
        let coordinator = makeCoordinator(
            publisher: publisher
        )

        coordinator.process(
            vehicleLocation(),
            activity: .automotive
        )

        coordinator.process(
            vehicleLocation(),
            activity: .automotive
        )

        XCTAssertEqual(
            coordinator.detectionState,
            .boardingCandidate
        )
        XCTAssertFalse(coordinator.shouldPublish)
        XCTAssertEqual(publisher.startCalls.count, 0)
        XCTAssertEqual(publisher.publishCalls.count, 0)
    }

    /// La tercera muestra vehicular compatible debe confirmar el viaje,
    /// crear una sesión anónima e iniciar la primera publicación.
    func testConfirmarAbordajeIniciaSesionYPublica() throws {
        let publisher = MockObservationPublisher()
        let coordinator = makeCoordinator(
            publisher: publisher
        )

        processBoardingSamples(
            with: coordinator
        )

        XCTAssertEqual(
            coordinator.detectionState,
            .onboard
        )
        XCTAssertTrue(coordinator.shouldPublish)
        XCTAssertEqual(coordinator.confirmedLine, "10")
        XCTAssertEqual(publisher.startCalls.count, 1)
        XCTAssertEqual(publisher.publishCalls.count, 1)

        let startCall = try XCTUnwrap(
            publisher.startCalls.first
        )

        XCTAssertEqual(startCall.linea, "10")

        // El UUID debe estar normalizado en minúsculas y existir solo
        // durante esta sesión temporal.
        XCTAssertEqual(
            startCall.sessionID,
            startCall.sessionID.lowercased()
        )

        let publishCall = try XCTUnwrap(
            publisher.publishCalls.first
        )

        XCTAssertEqual(
            publishCall.routeID,
            "route-10"
        )
        XCTAssertEqual(
            publishCall.activity,
            .automotive
        )
    }

    /// Cuatro muestras caminando después de estar a bordo deben confirmar
    /// el descenso, detener MQTT y limpiar la línea confirmada.
    func testConfirmarDescensoDetieneSesion() {
        let publisher = MockObservationPublisher()
        let coordinator = makeCoordinator(
            publisher: publisher
        )

        processBoardingSamples(
            with: coordinator
        )

        for _ in 0..<4 {
            coordinator.process(
                walkingLocation(),
                activity: .walking
            )
        }

        XCTAssertEqual(
            coordinator.detectionState,
            .idle
        )
        XCTAssertFalse(coordinator.shouldPublish)
        XCTAssertNil(coordinator.confirmedLine)
        XCTAssertEqual(publisher.stopCallCount, 1)
        XCTAssertEqual(
            coordinator.observationPublisherState,
            .inactive
        )
    }

    /// Al pasar a segundo plano con un viaje a bordo, la publicación se
    /// corta de forma limpia conservando la sesión; al volver a primer
    /// plano se reanuda el mismo viaje anónimo sin esperar un nuevo
    /// abordaje y la siguiente muestra vuelve a transmitirse.
    func testSegundoPlanoPausaYForegroundReanudaMismaSesion() throws {
        let publisher = MockObservationPublisher()
        let coordinator = makeCoordinator(
            publisher: publisher
        )

        processBoardingSamples(
            with: coordinator
        )

        let originalStart = try XCTUnwrap(
            publisher.startCalls.first
        )

        let publishCountBefore = publisher.publishCalls.count

        coordinator.pauseObservationSessionForBackground()

        XCTAssertEqual(publisher.stopCallCount, 1)
        XCTAssertEqual(
            coordinator.observationPublisherState,
            .inactive
        )
        XCTAssertEqual(
            coordinator.statusMessage,
            "Publicación pausada: app en segundo plano"
        )

        coordinator.resumeObservationSessionIfNeeded()

        XCTAssertEqual(publisher.startCalls.count, 2)

        // La reanudación pertenece al mismo viaje: mismo sessionID.
        XCTAssertEqual(
            publisher.startCalls.last?.sessionID,
            originalStart.sessionID
        )

        XCTAssertEqual(
            coordinator.observationPublisherState,
            .connected
        )

        // La siguiente muestra se transmite sin nuevo abordaje.
        coordinator.process(
            vehicleLocation(),
            activity: .automotive
        )

        XCTAssertEqual(
            publisher.publishCalls.count,
            publishCountBefore + 1
        )
    }

    /// Construye un coordinador con dependencias controladas.
    private func makeCoordinator(
        publisher: MockObservationPublisher
    ) -> PassiveTrackingCoordinator {
        PassiveTrackingCoordinator(
            locationService: MockLocationService(),
            motionService: MockMotionActivityService(),
            initialRoutes: [testRoute()],
            observationPublisher: publisher
        )
    }

    /// Entrega las tres muestras requeridas para confirmar el abordaje.
    private func processBoardingSamples(
        with coordinator: PassiveTrackingCoordinator
    ) {
        for _ in 0..<3 {
            coordinator.process(
                vehicleLocation(),
                activity: .automotive
            )
        }
    }

    /// Ruta recta hacia el este utilizada por todas las pruebas.
    ///
    /// Su tamaño reducido evita cargar el GTFS real y mantiene las
    /// comprobaciones rápidas y reproducibles.
    private func testRoute() -> DetectionRouteGeometry {
        DetectionRouteGeometry(
            id: "route-10",
            linea: "10",
            shape: [
                coordinate(-8.1000, -79.0400),
                coordinate(-8.1000, -79.0200)
            ],
            stops: [
                coordinate(-8.1000, -79.0300)
            ]
        )
    }

    /// Muestra vehicular válida: 10 m/s, rumbo este y precisión de 5 m.
    private func vehicleLocation() -> CLLocation {
        location(
            speed: 10,
            course: 90
        )
    }

    /// Muestra peatonal usada para confirmar el descenso.
    private func walkingLocation() -> CLLocation {
        location(
            speed: 1.2,
            course: 90
        )
    }

    /// Construye una lectura GPS sobre el shape de prueba.
    private func location(
        speed: CLLocationSpeed,
        course: CLLocationDirection
    ) -> CLLocation {
        CLLocation(
            coordinate: coordinate(
                -8.1000,
                -79.0300
            ),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: course,
            speed: speed,
            timestamp: Date()
        )
    }

    /// Construye una coordenada expresada en grados decimales.
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

/// Publicador simulado que registra llamadas sin abrir una conexión.
///
/// Permite comprobar la orquestación sin depender de Mosquitto, Wi-Fi,
/// credenciales, intervalos de publicación ni callbacks asíncronos.
@MainActor
private final class MockObservationPublisher:
    ObservationPublishing {

    private(set) var state:
        ObservationPublisherState = .inactive

    var onStateChange:
        (@MainActor (ObservationPublisherState) -> Void)?

    private(set) var startCalls:
        [(sessionID: String, linea: String)] = []

    private(set) var publishCalls:
        [PublishCall] = []

    private(set) var stopCallCount = 0

    func start(
        sessionID: String,
        linea: String
    ) {
        startCalls.append(
            (
                sessionID: sessionID,
                linea: linea
            )
        )

        state = .connected
    }

    func publish(
        location: CLLocation,
        routeID: String,
        activity: DetectedMotionActivity
    ) {
        publishCalls.append(
            PublishCall(
                routeID: routeID,
                activity: activity
            )
        )
    }

    func stop() {
        stopCallCount += 1
        state = .inactive
    }

    struct PublishCall {
        let routeID: String
        let activity: DetectedMotionActivity
    }
}

/// Servicio GPS mínimo requerido para construir el coordinador.
///
/// Las pruebas introducen las ubicaciones directamente en `process`, por
/// lo que este mock no inicia sensores ni emite posiciones.
private final class MockLocationService:
    LocationServiceProtocol {

    let authorizationStatus:
        CLAuthorizationStatus = .authorizedWhenInUse

    var authorizationPublisher:
        AnyPublisher<CLAuthorizationStatus, Never> {
        Just(authorizationStatus)
            .eraseToAnyPublisher()
    }

    func currentLocation() -> AsyncStream<CLLocation> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func requestPermission() async
        -> CLAuthorizationStatus {
        authorizationStatus
    }

    func startUpdating() {}

    func stopUpdating() {}
}

/// Servicio de movimiento vacío utilizado para evitar Core Motion real.
private final class MockMotionActivityService:
    MotionActivityProviding {

    private(set) var currentActivity:
        DetectedMotionActivity = .unknown

    func start() {}

    func stop() {}

    func activities()
        -> AsyncStream<DetectedMotionActivity> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
