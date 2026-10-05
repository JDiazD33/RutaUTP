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
import UIKit
@testable import RutaUTP

/// Verifica el ciclo de vida de una sesión de observaciones.
///
/// La clase se ejecuta en `MainActor` porque tanto
/// `PassiveTrackingCoordinator` como `ObservationPublishing` están
/// aislados en el actor principal.
@MainActor
final class PassiveTrackingCoordinatorTests:
    XCTestCase {

    private let reloj = RelojDeteccionPrueba()

    func testRestauraConsentimientoConPublicadorCreadoDesdeConfiguracion() {
        withStoredConsent(true) {
            let coordinator = PassiveTrackingCoordinator(
                locationService: MockLocationService(),
                configurationProvider: {
                    MQTTConfiguration(host: "localhost", port: 1883,
                                      username: "test-device", password: "test-only")
                }
            )
            XCTAssertTrue(coordinator.isPublisherConfigured)
            XCTAssertTrue(coordinator.isEnabled)
            XCTAssertTrue(UserDefaults.standard.bool(forKey: "rutautp.passive-tracking-consent"))
            XCTAssertFalse(coordinator.isRunning)
        }
    }

    func testConfiguracionNoActivaContribucionSinConsentimiento() {
        withStoredConsent(false) {
            let coordinator = PassiveTrackingCoordinator(
                locationService: MockLocationService(),
                configurationProvider: {
                    MQTTConfiguration(host: "localhost", port: 1883,
                                      username: "test-device", password: "test-only")
                }
            )
            XCTAssertTrue(coordinator.isPublisherConfigured)
            XCTAssertFalse(coordinator.isEnabled)
        }
    }

    func testSinConfiguracionNoActivaSensoresNiPublicacion() {
        withStoredConsent(true) {
            let coordinator = PassiveTrackingCoordinator(
                locationService: MockLocationService(), configurationProvider: { nil }
            )
            XCTAssertFalse(coordinator.isPublisherConfigured)
            XCTAssertFalse(coordinator.isEnabled)
            XCTAssertFalse(coordinator.isRunning)
            XCTAssertEqual(coordinator.statusMessage, "Canal MQTT no configurado")
        }
    }

    func testElegirLineaEnCasaNoIniciaPublicacion() {
        withStoredConsent(true) {
            let publisher = MockObservationPublisher()
            let coordinator = makeCoordinator(publisher: publisher)
            coordinator.beginTrip(route: testRoute(), occupancy: nil)
            for _ in 0..<5 {
                coordinator.process(location(speed: 0, course: 90), activity: .stationary)
            }
            XCTAssertEqual(coordinator.selectedTripRoute?.id, "route-10")
            XCTAssertNotNil(coordinator.tripStartedAt)
            XCTAssertFalse(coordinator.shouldPublish)
            XCTAssertTrue(publisher.startCalls.isEmpty)
        }
    }

    func testLineaElegidaDesambiguaRecorridosSuperpuestos() {
        withStoredConsent(true) {
            let publisher = MockObservationPublisher()
            let coordinator = makeCoordinator(publisher: publisher)
            let original = testRoute()
            let selected = DetectionRouteGeometry(id: "route-20", linea: "20",
                shape: original.shape, stops: original.stops)
            coordinator.beginTrip(route: selected, occupancy: nil)
            processBoardingSamples(with: coordinator)
            XCTAssertEqual(coordinator.confirmedLine, "20")
            XCTAssertEqual(publisher.publishCalls.first?.routeID, "route-20")
            coordinator.endTrip()
            let count = publisher.publishCalls.count
            processBoardingSamples(with: coordinator)
            XCTAssertEqual(publisher.publishCalls.count, count)
            XCTAssertNil(coordinator.selectedTripRoute)
            XCTAssertFalse(coordinator.shouldPublish)
            XCTAssertTrue(coordinator.isEnabled)
            coordinator.beginTrip(route: original, occupancy: nil)
            processBoardingSamples(with: coordinator)
            XCTAssertEqual(coordinator.confirmedLine, "10")
        }
    }

    func testNoIniciaViajeDeclaradoSinConsentimiento() {
        withStoredConsent(false) {
            let publisher = MockObservationPublisher()
            let coordinator = makeCoordinator(publisher: publisher, consent: false)
            coordinator.beginTrip(route: testRoute(), occupancy: nil)
            XCTAssertNil(coordinator.selectedTripRoute)
            XCTAssertNil(coordinator.tripStartedAt)
        }
    }

    func testPuntoDeSubidaSeGuardaSinExigirTexto() throws {
        let suite = "rutautp.boarding-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let point = try XCTUnwrap(BoardingPoint(coordinate: coordinate(-8.1, -79.03)))
        BoardingPlaceStore.save(routeID: "route-10", line: "10", place: "  ", point: point, defaults: defaults)
        let note = try XCTUnwrap(BoardingPlaceStore.notes(defaults: defaults).first)
        XCTAssertEqual(note.point, point)
        XCTAssertEqual(note.place, "")
        XCTAssertEqual(note.routeID, "route-10")
        BoardingPlaceStore.save(routeID: "route-10", line: "10", place: "  ", defaults: defaults)
        XCTAssertEqual(BoardingPlaceStore.notes(defaults: defaults).count, 1)
        XCTAssertNil(BoardingPoint(coordinate: coordinate(100, -79)))
    }

    func testReferenciasAnterioresSinCoordenadasSeConservan() throws {
        let suite = "rutautp.boarding-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacy: [[String: Any]] = [["id": UUID().uuidString, "routeID": "route-10",
                                      "line": "10", "place": "Frente al campus", "recordedAt": 0]]
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: BoardingPlaceStore.key)
        let before = try XCTUnwrap(BoardingPlaceStore.notes(defaults: defaults).first)
        XCTAssertEqual(before.place, "Frente al campus")
        XCTAssertNil(before.point)
        BoardingPlaceStore.save(routeID: "route-20", line: "20", place: "Mercado", defaults: defaults)
        XCTAssertEqual(BoardingPlaceStore.notes(defaults: defaults).count, 2)
    }

    private func withStoredConsent<Resultado>(_ enabled: Bool, body: () throws -> Resultado) rethrows -> Resultado {
        let key = "rutautp.passive-tracking-consent"
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.set(enabled, forKey: key)
        return try body()
    }

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
    /// crear una sesión de viaje e iniciar la primera publicación.
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
    /// plano se reanuda la misma sesión de viaje sin esperar un nuevo
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

    // MARK: - Reanudación durante un posible descenso (E04)

    func testPosibleDescensoReanudaMismaSesionConLaNuevaMuestraAutorizada() throws {
        let publisher = MockObservationPublisher()
        let coordinator = makeCoordinator(publisher: publisher)
        processBoardingSamples(with: coordinator)
        let original = try XCTUnwrap(publisher.startCalls.first)
        coordinator.process(walkingLocation(), activity: .walking)
        XCTAssertEqual(coordinator.detectionState, .alightingCandidate)
        let publicaciones = publisher.publishCalls.count
        coordinator.pauseObservationSessionForBackground()
        coordinator.resumeObservationSessionIfNeeded()
        XCTAssertEqual(publisher.startCalls.count, 1)
        XCTAssertEqual(coordinator.observationPublisherState, .inactive)
        let nueva = vehicleLocation()
        coordinator.process(nueva, activity: .automotive)
        XCTAssertEqual(coordinator.detectionState, .onboard)
        XCTAssertEqual(publisher.startCalls.count, 2)
        XCTAssertEqual(publisher.startCalls.last?.sessionID, original.sessionID)
        XCTAssertEqual(publisher.startCalls.last?.linea, original.linea)
        XCTAssertEqual(publisher.publishCalls.count, publicaciones + 1)
        XCTAssertEqual(publisher.publishCalls.last?.routeID, "route-10")
        XCTAssertEqual(publisher.publishCalls.last?.location.timestamp, nueva.timestamp)
        XCTAssertEqual(publisher.ignoredPublishCount, 0)
        XCTAssertEqual(coordinator.observationPublisherState, .connected)
        coordinator.process(vehicleLocation(), activity: .automotive)
        XCTAssertEqual(publisher.startCalls.count, 2)
    }

    func testForegroundRepetidoNoDuplicaInicioNiReenviaLaUltimaUbicacion() throws {
        let publisher = MockObservationPublisher()
        let coordinator = makeCoordinator(publisher: publisher)
        processBoardingSamples(with: coordinator)
        let original = try XCTUnwrap(publisher.startCalls.first)
        let publicaciones = publisher.publishCalls.count
        coordinator.pauseObservationSessionForBackground()
        coordinator.pauseObservationSessionForBackground()
        XCTAssertEqual(publisher.stopCallCount, 1)
        for _ in 0..<5 { coordinator.resumeObservationSessionIfNeeded() }
        XCTAssertEqual(publisher.startCalls.count, 2)
        XCTAssertEqual(publisher.startCalls.last?.sessionID, original.sessionID)
        XCTAssertEqual(publisher.publishCalls.count, publicaciones)
        for _ in 0..<3 { coordinator.process(vehicleLocation(), activity: .automotive) }
        XCTAssertEqual(publisher.startCalls.count, 2)
        XCTAssertEqual(publisher.publishCalls.count, publicaciones + 3)
    }

    func testPosibleDescensoEsperaEvidenciaValidaAunqueForegroundSeRepita() {
        let publisher = MockObservationPublisher()
        let coordinator = makeCoordinator(publisher: publisher)
        processBoardingSamples(with: coordinator)
        coordinator.process(walkingLocation(), activity: .walking)
        coordinator.pauseObservationSessionForBackground()
        for _ in 0..<4 { coordinator.resumeObservationSessionIfNeeded() }
        coordinator.process(location(speed: 10, course: 90, accuracy: -1), activity: .automotive)
        coordinator.process(walkingLocation(), activity: .walking)
        XCTAssertEqual(coordinator.detectionState, .alightingCandidate)
        XCTAssertEqual(publisher.startCalls.count, 1)
        XCTAssertFalse(coordinator.shouldPublish)
        coordinator.process(vehicleLocation(), activity: .automotive)
        XCTAssertEqual(publisher.startCalls.count, 2)
        XCTAssertTrue(coordinator.shouldPublish)
    }

    func testMuestrasEnBackgroundNoReanudanNiPublicanAunqueVuelvaAOnboard() {
        let publisher = MockObservationPublisher()
        let coordinator = makeCoordinator(publisher: publisher)
        processBoardingSamples(with: coordinator)
        coordinator.process(walkingLocation(), activity: .walking)
        let publicaciones = publisher.publishCalls.count
        coordinator.pauseObservationSessionForBackground()
        coordinator.process(vehicleLocation(), activity: .automotive)
        coordinator.process(vehicleLocation(), activity: .automotive)
        XCTAssertEqual(coordinator.detectionState, .onboard)
        XCTAssertFalse(coordinator.shouldPublish)
        XCTAssertEqual(publisher.startCalls.count, 1)
        XCTAssertEqual(publisher.publishCalls.count, publicaciones)
        XCTAssertEqual(publisher.ignoredPublishCount, 0)
        coordinator.resumeObservationSessionIfNeeded()
        XCTAssertEqual(publisher.startCalls.count, 2)
        XCTAssertEqual(publisher.publishCalls.count, publicaciones)
        coordinator.process(vehicleLocation(), activity: .automotive)
        XCTAssertEqual(publisher.publishCalls.count, publicaciones + 1)
    }

    func testAbordajeDetectadoEnBackgroundEsperaForegroundParaAbrirCanal() {
        let publisher = MockObservationPublisher()
        let coordinator = makeCoordinator(publisher: publisher)
        coordinator.pauseObservationSessionForBackground()
        processBoardingSamples(with: coordinator)
        XCTAssertEqual(coordinator.detectionState, .onboard)
        XCTAssertTrue(publisher.startCalls.isEmpty)
        XCTAssertTrue(publisher.publishCalls.isEmpty)
        coordinator.resumeObservationSessionIfNeeded()
        XCTAssertEqual(publisher.startCalls.count, 1)
        XCTAssertTrue(publisher.publishCalls.isEmpty)
        coordinator.process(vehicleLocation(), activity: .automotive)
        XCTAssertEqual(publisher.publishCalls.count, 1)
    }

    func testDescensoConfirmadoCancelaReanudacionPendiente() {
        let publisher = MockObservationPublisher()
        let coordinator = makeCoordinator(publisher: publisher)
        processBoardingSamples(with: coordinator)
        coordinator.process(walkingLocation(), activity: .walking)
        coordinator.pauseObservationSessionForBackground()
        coordinator.resumeObservationSessionIfNeeded()
        for _ in 0..<3 { coordinator.process(walkingLocation(), activity: .walking) }
        coordinator.resumeObservationSessionIfNeeded()
        XCTAssertEqual(coordinator.detectionState, .idle)
        XCTAssertNil(coordinator.confirmedLine)
        XCTAssertEqual(publisher.startCalls.count, 1)
        XCTAssertEqual(publisher.publishCalls.count, 1)
        XCTAssertEqual(coordinator.observationPublisherState, .inactive)
    }

    func testRevocarConsentimientoCancelaLaSesionPausadaYLasMuestrasPosteriores() {
        withStoredConsent(true) {
            let publisher = MockObservationPublisher()
            let coordinator = makeCoordinator(publisher: publisher)
            processBoardingSamples(with: coordinator)
            coordinator.process(walkingLocation(), activity: .walking)
            coordinator.pauseObservationSessionForBackground()
            coordinator.setContributionEnabled(false)
            coordinator.resumeObservationSessionIfNeeded()
            processBoardingSamples(with: coordinator)
            XCTAssertFalse(coordinator.isEnabled)
            XCTAssertEqual(coordinator.detectionState, .idle)
            XCTAssertEqual(publisher.startCalls.count, 1)
            XCTAssertEqual(publisher.publishCalls.count, 1)
            XCTAssertEqual(coordinator.observationPublisherState, .inactive)
        }
    }

    func testTerminarViajeDeclaradoNoReabreSesionPausada() {
        let publisher = MockObservationPublisher()
        let coordinator = makeCoordinator(publisher: publisher)
        coordinator.beginTrip(route: testRoute(), occupancy: nil)
        processBoardingSamples(with: coordinator)
        coordinator.process(walkingLocation(), activity: .walking)
        coordinator.pauseObservationSessionForBackground()
        coordinator.endTrip()
        coordinator.resumeObservationSessionIfNeeded()
        processBoardingSamples(with: coordinator)
        XCTAssertEqual(publisher.startCalls.count, 1)
        XCTAssertNil(coordinator.selectedTripRoute)
        XCTAssertEqual(coordinator.detectionState, .idle)
        XCTAssertEqual(coordinator.observationPublisherState, .inactive)
    }

    func testNuevoViajeNoReutilizaLaSesionPausadaDelAnterior() throws {
        let publisher = MockObservationPublisher()
        let coordinator = makeCoordinator(publisher: publisher)
        coordinator.beginTrip(route: testRoute(), occupancy: nil)
        processBoardingSamples(with: coordinator)
        let anterior = try XCTUnwrap(publisher.startCalls.first?.sessionID)
        coordinator.process(walkingLocation(), activity: .walking)
        coordinator.pauseObservationSessionForBackground()
        let nuevaRuta = DetectionRouteGeometry(id: "route-20", linea: "20", shape: testRoute().shape, stops: testRoute().stops)
        coordinator.beginTrip(route: nuevaRuta, occupancy: nil)
        coordinator.resumeObservationSessionIfNeeded()
        XCTAssertEqual(publisher.startCalls.count, 1)
        processBoardingSamples(with: coordinator)
        XCTAssertEqual(publisher.startCalls.count, 2)
        XCTAssertNotEqual(publisher.startCalls.last?.sessionID, anterior)
        XCTAssertEqual(publisher.startCalls.last?.linea, "20")
        XCTAssertEqual(publisher.publishCalls.last?.routeID, "route-20")
    }

    func testReanudarConservaRutaConfirmadaAunqueCambieLaCandidataMasCercana() throws {
        let publisher = MockObservationPublisher()
        let paralela = DetectionRouteGeometry(id: "route-20", linea: "20",
            shape: [coordinate(-8.101, -79.04), coordinate(-8.101, -79.02)], stops: [coordinate(-8.101, -79.03)])
        let coordinator = makeCoordinator(publisher: publisher, routes: [testRoute(), paralela])
        processBoardingSamples(with: coordinator)
        let sesion = try XCTUnwrap(publisher.startCalls.first?.sessionID)
        coordinator.process(walkingLocation(), activity: .walking)
        coordinator.pauseObservationSessionForBackground()
        coordinator.resumeObservationSessionIfNeeded()
        coordinator.process(location(speed: 10, course: 90, latitude: -8.101), activity: .automotive)
        XCTAssertEqual(publisher.startCalls.last?.sessionID, sesion)
        XCTAssertEqual(publisher.startCalls.last?.linea, "10")
        XCTAssertEqual(publisher.publishCalls.last?.routeID, "route-10")
        XCTAssertEqual(coordinator.confirmedLine, "10")
    }

    func testOcupacionPendienteEsperaMuestraAutorizadaYSeLimpiaAlTerminarViaje() {
        var intentosOcupacion = 0
        let occupancy = OccupancyService(configurationProvider: { intentosOcupacion += 1; return nil })
        let publisher = MockObservationPublisher()
        let coordinator = makeCoordinator(publisher: publisher, occupancy: occupancy)
        coordinator.beginTrip(route: testRoute(), occupancy: .space)
        processBoardingSamples(with: coordinator)
        XCTAssertEqual(intentosOcupacion, 1)
        coordinator.process(walkingLocation(), activity: .walking)
        coordinator.pauseObservationSessionForBackground()
        coordinator.resumeObservationSessionIfNeeded()
        XCTAssertTrue(occupancy.hasPendingTripReport)
        XCTAssertEqual(intentosOcupacion, 1)
        coordinator.process(vehicleLocation(), activity: .automotive)
        XCTAssertEqual(intentosOcupacion, 2)
        XCTAssertTrue(occupancy.hasPendingTripReport)
        coordinator.endTrip()
        XCTAssertFalse(occupancy.hasPendingTripReport)
        coordinator.resumeObservationSessionIfNeeded()
        XCTAssertEqual(intentosOcupacion, 2)
    }

    func testCanalConectandoNoSeReiniciaConCadaMuestraOForeground() {
        let publisher = MockObservationPublisher()
        publisher.estadoAlIniciar = .connecting
        let coordinator = makeCoordinator(publisher: publisher)
        processBoardingSamples(with: coordinator)
        coordinator.process(walkingLocation(), activity: .walking)
        coordinator.pauseObservationSessionForBackground()
        coordinator.resumeObservationSessionIfNeeded()
        for _ in 0..<3 {
            coordinator.process(vehicleLocation(), activity: .automotive)
            coordinator.resumeObservationSessionIfNeeded()
        }
        XCTAssertEqual(publisher.startCalls.count, 2)
        XCTAssertEqual(coordinator.observationPublisherState, .connecting)
    }

    func testSinConsentimientoNoCreaSesionNiReanudaTrasForeground() {
        let publisher = MockObservationPublisher()
        let coordinator = makeCoordinator(publisher: publisher, consent: false)
        processBoardingSamples(with: coordinator)
        coordinator.pauseObservationSessionForBackground()
        coordinator.resumeObservationSessionIfNeeded()
        processBoardingSamples(with: coordinator)
        XCTAssertEqual(coordinator.detectionState, .idle)
        XCTAssertTrue(publisher.startCalls.isEmpty)
        XCTAssertTrue(publisher.publishCalls.isEmpty)
    }

    func testNotificacionesDeLifecycleReanudanPosibleDescensoEnLaSiguienteMuestra() async {
        let publisher = MockObservationPublisher()
        let coordinator = makeCoordinator(publisher: publisher)
        defer { coordinator.stop() }
        await coordinator.startIfConsented()
        XCTAssertTrue(coordinator.isRunning)
        processBoardingSamples(with: coordinator)
        coordinator.process(walkingLocation(), activity: .walking)
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(coordinator.observationPublisherState, .inactive)
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(publisher.startCalls.count, 1)
        coordinator.process(vehicleLocation(), activity: .automotive)
        XCTAssertEqual(publisher.startCalls.count, 2)
        XCTAssertEqual(publisher.publishCalls.count, 2)
    }

    // MARK: - Continuidad temporal de las muestras (E05)

    func testDuplicarUnFixNoAbreSesionHastaRecibirDosLecturasNuevas() {
        let publisher = MockObservationPublisher()
        let coordinator = makeCoordinator(publisher: publisher)
        let repetida = vehicleLocation()
        for _ in 0..<5 { coordinator.process(repetida, activity: .automotive) }
        XCTAssertEqual(coordinator.detectionState, .boardingCandidate)
        XCTAssertTrue(publisher.startCalls.isEmpty)
        XCTAssertTrue(publisher.publishCalls.isEmpty)
        coordinator.process(vehicleLocation(), activity: .automotive)
        XCTAssertTrue(publisher.startCalls.isEmpty)
        let nueva = vehicleLocation()
        coordinator.process(nueva, activity: .automotive)
        XCTAssertEqual(publisher.startCalls.count, 1)
        XCTAssertEqual(publisher.publishCalls.count, 1)
        XCTAssertEqual(publisher.publishCalls.last?.location.timestamp, nueva.timestamp)
    }

    func testRepetirFixCaminandoNoCierraSesionConfirmada() {
        let publisher = MockObservationPublisher()
        let coordinator = makeCoordinator(publisher: publisher)
        processBoardingSamples(with: coordinator)
        let repetida = walkingLocation()
        for _ in 0..<5 { coordinator.process(repetida, activity: .walking) }
        XCTAssertEqual(coordinator.detectionState, .alightingCandidate)
        XCTAssertEqual(publisher.stopCallCount, 0)
        XCTAssertEqual(coordinator.confirmedLine, "10")
        for _ in 0..<3 { coordinator.process(walkingLocation(), activity: .walking) }
        XCTAssertEqual(coordinator.detectionState, .idle)
        XCTAssertEqual(publisher.stopCallCount, 1)
    }

    func testLecturaViejaDeOtraRutaNoBorraEvidenciaDeLaRutaActual() {
        let publisher = MockObservationPublisher()
        let paralela = DetectionRouteGeometry(id: "route-20", linea: "20",
            shape: [coordinate(-8.101, -79.04), coordinate(-8.101, -79.02)], stops: [coordinate(-8.101, -79.03)])
        let coordinator = makeCoordinator(publisher: publisher, routes: [testRoute(), paralela])
        let primera = vehicleLocation()
        coordinator.process(primera, activity: .automotive)
        coordinator.process(vehicleLocation(), activity: .automotive)
        let atrasada = location(speed: 10, course: 90, timestamp: primera.timestamp, latitude: -8.101)
        for _ in 0..<3 { coordinator.process(atrasada, activity: .automotive) }
        XCTAssertTrue(publisher.startCalls.isEmpty)
        coordinator.process(vehicleLocation(), activity: .automotive)
        XCTAssertEqual(publisher.startCalls.count, 1)
        XCTAssertEqual(coordinator.confirmedLine, "10")
        XCTAssertEqual(publisher.publishCalls.last?.routeID, "route-10")
    }

    func testRutaNuevaNecesitaSuPropiaSecuenciaDeLecturasNuevas() {
        let publisher = MockObservationPublisher()
        let paralela = DetectionRouteGeometry(id: "route-20", linea: "20",
            shape: [coordinate(-8.101, -79.04), coordinate(-8.101, -79.02)], stops: [coordinate(-8.101, -79.03)])
        let coordinator = makeCoordinator(publisher: publisher, routes: [testRoute(), paralela])
        for _ in 0..<2 { coordinator.process(vehicleLocation(), activity: .automotive) }
        for _ in 0..<2 { coordinator.process(location(speed: 10, course: 90, latitude: -8.101), activity: .automotive) }
        XCTAssertTrue(publisher.startCalls.isEmpty)
        coordinator.process(location(speed: 10, course: 90, latitude: -8.101), activity: .automotive)
        XCTAssertEqual(publisher.startCalls.count, 1)
        XCTAssertEqual(coordinator.confirmedLine, "20")
        XCTAssertEqual(publisher.publishCalls.last?.routeID, "route-20")
    }

    func testCacheCaducadaYFechaFuturaNoCreanSesionNiBloqueanLecturasActuales() {
        let publisher = MockObservationPublisher()
        let coordinator = makeCoordinator(publisher: publisher)
        for desplazamiento in [-46.0, 11.0] {
            let rechazada = location(speed: 10, course: 90,
                timestamp: Date(timeIntervalSince1970: reloj.ahora + desplazamiento))
            for _ in 0..<3 { coordinator.process(rechazada, activity: .automotive) }
        }
        XCTAssertEqual(coordinator.detectionState, .idle)
        XCTAssertTrue(publisher.startCalls.isEmpty)
        processBoardingSamples(with: coordinator)
        XCTAssertEqual(publisher.startCalls.count, 1)
        XCTAssertEqual(publisher.publishCalls.count, 1)
    }

    func testHuecoYPrecisionInvalidaInterrumpenAbordajeSinAbrirCanal() {
        let publisher = MockObservationPublisher()
        let coordinator = makeCoordinator(publisher: publisher)
        for _ in 0..<2 { coordinator.process(vehicleLocation(), activity: .automotive) }
        reloj.ahora += 31
        coordinator.process(vehicleLocation(), activity: .automotive)
        coordinator.process(vehicleLocation(), activity: .automotive)
        XCTAssertTrue(publisher.startCalls.isEmpty)
        coordinator.process(location(speed: 10, course: 90, accuracy: -1), activity: .automotive)
        XCTAssertEqual(coordinator.detectionState, .idle)
        for _ in 0..<2 { coordinator.process(vehicleLocation(), activity: .automotive) }
        XCTAssertTrue(publisher.startCalls.isEmpty)
        coordinator.process(vehicleLocation(), activity: .automotive)
        XCTAssertEqual(publisher.startCalls.count, 1)
    }

    func testReanudacionE04EsperaFechaNuevaYConservaSesionTrasUnHueco() throws {
        let publisher = MockObservationPublisher()
        let coordinator = makeCoordinator(publisher: publisher)
        processBoardingSamples(with: coordinator)
        let original = try XCTUnwrap(publisher.startCalls.first?.sessionID)
        let anterior = try XCTUnwrap(publisher.publishCalls.last?.location)
        coordinator.process(walkingLocation(), activity: .walking)
        coordinator.pauseObservationSessionForBackground()
        coordinator.resumeObservationSessionIfNeeded()
        coordinator.process(anterior, activity: .automotive)
        coordinator.process(location(speed: 10, course: 90,
            timestamp: Date(timeIntervalSince1970: reloj.ahora + 11)), activity: .automotive)
        XCTAssertEqual(publisher.startCalls.count, 1)
        XCTAssertEqual(publisher.publishCalls.count, 1)
        XCTAssertEqual(coordinator.detectionState, .alightingCandidate)
        reloj.ahora += 60
        let nueva = vehicleLocation()
        coordinator.process(nueva, activity: .automotive)
        XCTAssertEqual(publisher.startCalls.count, 2)
        XCTAssertEqual(publisher.startCalls.last?.sessionID, original)
        XCTAssertEqual(publisher.publishCalls.last?.location.timestamp, nueva.timestamp)
        XCTAssertEqual(publisher.publishCalls.last?.routeID, "route-10")
    }

    func testMuestrasRechazadasNoActivanOcupacionYParadaConservaViaje() throws {
        var intentos = 0
        let occupancy = OccupancyService(configurationProvider: { intentos += 1; return nil })
        let publisher = MockObservationPublisher()
        let coordinator = makeCoordinator(publisher: publisher, occupancy: occupancy)
        coordinator.beginTrip(route: testRoute(), occupancy: .space)
        processBoardingSamples(with: coordinator)
        let sesion = try XCTUnwrap(publisher.startCalls.first?.sessionID)
        let repetida = try XCTUnwrap(publisher.publishCalls.last?.location)
        coordinator.process(repetida, activity: .walking)
        coordinator.process(location(speed: 10, course: 90, accuracy: 120), activity: .automotive)
        coordinator.process(location(speed: 10, course: 90,
            timestamp: Date(timeIntervalSince1970: reloj.ahora - 46)), activity: .automotive)
        XCTAssertEqual(intentos, 1)
        XCTAssertEqual(publisher.publishCalls.count, 1)
        XCTAssertEqual(coordinator.detectionState, .onboard)
        reloj.ahora += 60
        coordinator.process(location(speed: 0, course: 90), activity: .stationary)
        XCTAssertEqual(intentos, 2)
        XCTAssertTrue(occupancy.hasPendingTripReport)
        XCTAssertEqual(publisher.startCalls.count, 1)
        XCTAssertEqual(publisher.startCalls.last?.sessionID, sesion)
        XCTAssertEqual(publisher.stopCallCount, 1) // beginTrip limpia cualquier canal previo.
        XCTAssertEqual(coordinator.confirmedLine, "10")
        XCTAssertEqual(coordinator.selectedTripRoute?.id, "route-10")
        XCTAssertTrue(coordinator.shouldPublish)
    }

    func testCacheEntregadaPorStreamYArranqueCuentaUnaSolaVez() async {
        let publisher = MockObservationPublisher()
        let cache = vehicleLocation()
        let coordinator = makeCoordinator(publisher: publisher,
            locationService: CacheReplayLocationService(location: cache))
        defer { coordinator.stop() }
        await coordinator.startIfConsented()
        coordinator.resumeObservationSessionIfNeeded()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(coordinator.detectionState, .boardingCandidate)
        XCTAssertTrue(publisher.startCalls.isEmpty)
        coordinator.process(vehicleLocation(), activity: .automotive)
        XCTAssertTrue(publisher.startCalls.isEmpty)
        coordinator.process(vehicleLocation(), activity: .automotive)
        XCTAssertEqual(publisher.startCalls.count, 1)
        XCTAssertEqual(publisher.publishCalls.count, 1)
    }

    /// Construye un coordinador con dependencias controladas.
    private func makeCoordinator(
        publisher: MockObservationPublisher,
        consent: Bool = true,
        routes: [DetectionRouteGeometry]? = nil,
        occupancy: OccupancyService = OccupancyService(configurationProvider: { nil }),
        locationService: LocationServiceProtocol = MockLocationService()
    ) -> PassiveTrackingCoordinator {
        withStoredConsent(consent) {
            PassiveTrackingCoordinator(
                locationService: locationService,
                motionService: MockMotionActivityService(),
                initialRoutes: routes ?? [testRoute()],
                observationPublisher: publisher,
                tripOccupancy: occupancy,
                detectionClock: { [reloj] in reloj.ahora }
            )
        }
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
        course: CLLocationDirection,
        accuracy: CLLocationAccuracy = 5,
        timestamp: Date? = nil,
        latitude: CLLocationDegrees = -8.1000
    ) -> CLLocation {
        // Cada fix nuevo avanza el reloj; una fecha explícita permite reproducir
        // caché, entregas repetidas/desordenadas y desfases sin esperas reales.
        let fecha: Date
        if let timestamp {
            fecha = timestamp
        } else {
            reloj.ahora += 1
            fecha = Date(timeIntervalSince1970: reloj.ahora)
        }
        return CLLocation(
            coordinate: coordinate(
                latitude,
                -79.0300
            ),
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: 5,
            course: course,
            speed: speed,
            timestamp: fecha
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

private final class RelojDeteccionPrueba {
    var ahora: TimeInterval = 1_800_000_000
}

/// Reproduce las dos entregas de caché que hace el servicio compartido:
/// una al registrar el stream y otra al solicitar actualizaciones.
private final class CacheReplayLocationService: LocationServiceProtocol {
    let authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    private let location: CLLocation
    private var continuation: AsyncStream<CLLocation>.Continuation?

    init(location: CLLocation) { self.location = location }
    var authorizationPublisher: AnyPublisher<CLAuthorizationStatus, Never> {
        Just(authorizationStatus).eraseToAnyPublisher()
    }
    func requestPermission() async -> CLAuthorizationStatus { authorizationStatus }
    func currentLocation() -> AsyncStream<CLLocation> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(location)
        }
    }
    func startUpdating() {
        continuation?.yield(location)
        continuation?.finish()
    }
    func stopUpdating() { continuation?.finish() }
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
    private(set) var ignoredPublishCount = 0
    var estadoAlIniciar: ObservationPublisherState = .connected

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

        state = estadoAlIniciar
        onStateChange?(state)
    }

    func publish(
        location: CLLocation,
        routeID: String,
        activity: DetectedMotionActivity
    ) {
        guard state != .inactive else { ignoredPublishCount += 1; return }
        publishCalls.append(
            PublishCall(
                location: location,
                routeID: routeID,
                activity: activity
            )
        )
    }

    func stop() {
        stopCallCount += 1
        state = .inactive
        onStateChange?(state)
    }

    struct PublishCall {
        let location: CLLocation
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
