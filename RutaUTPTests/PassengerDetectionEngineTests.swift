import XCTest
@testable import RutaUTP

final class PassengerDetectionEngineTests: XCTestCase {

    private let clock = DetectionTestClock()

    func testCaminarCercaDelParaderoNoConfirmaAbordaje() {
        var engine = makeEngine()

        let result = engine.process(
            sample(
                activity: .walking,
                speed: 1.2,
                distanceToRoute: 10,
                headingDifference: 20,
                distanceToStop: 15
            )
        )

        XCTAssertEqual(result.state, .approachingStop)
        XCTAssertFalse(result.shouldPublish)
        XCTAssertFalse(result.didConfirmBoarding)
    }

    func testUnaSolaMuestraVehicularNoConfirmaAbordaje() {
        var engine = makeEngine()

        let result = engine.process(vehicleSample())

        XCTAssertEqual(result.state, .boardingCandidate)
        XCTAssertFalse(result.shouldPublish)
    }

    func testTresMuestrasVehicularesConfirmanAbordaje() {
        var engine = makeEngine()

        _ = engine.process(vehicleSample())
        _ = engine.process(vehicleSample())
        let result = engine.process(vehicleSample())

        XCTAssertEqual(result.state, .onboard)
        XCTAssertTrue(result.shouldPublish)
        XCTAssertTrue(result.didConfirmBoarding)
    }

    func testVehiculoAlejadoDeRutaNoConfirmaAbordaje() {
        var engine = makeEngine()

        for _ in 0..<4 {
            _ = engine.process(
                sample(
                    activity: .automotive,
                    speed: 10,
                    distanceToRoute: 150,
                    headingDifference: 10,
                    distanceToStop: 200
                )
            )
        }

        XCTAssertEqual(engine.state, .idle)
    }

    func testVehiculoEnDireccionContrariaNoConfirmaAbordaje() {
        var engine = makeEngine()

        for _ in 0..<4 {
            _ = engine.process(
                sample(
                    activity: .automotive,
                    speed: 10,
                    distanceToRoute: 10,
                    headingDifference: 130,
                    distanceToStop: 30
                )
            )
        }

        XCTAssertNotEqual(engine.state, .onboard)
    }

    func testBusDetenidoNoSeInterpretaComoDescenso() {
        var engine = onboardEngine()

        let result = engine.process(stationarySample())

        XCTAssertEqual(result.state, .onboard)
        XCTAssertTrue(result.shouldPublish)
        XCTAssertFalse(result.didConfirmAlighting)
    }

    func testCuatroMuestrasCaminandoConfirmanDescenso() {
        var engine = onboardEngine()
        var result: PassengerDetectionDecision?

        for _ in 0..<4 {
            result = engine.process(walkingSample())
        }

        XCTAssertEqual(result?.state, .idle)
        XCTAssertFalse(result?.shouldPublish ?? true)
        XCTAssertTrue(result?.didConfirmAlighting ?? false)
    }

    func testUbicacionImprecisaNoSePublica() {
        var engine = onboardEngine()

        let result = engine.process(vehicleSample(accuracy: 120))

        XCTAssertEqual(result.state, .onboard)
        XCTAssertFalse(result.shouldPublish)
    }

    // E05: cada transición requiere ubicaciones nuevas, recientes y consecutivas.
    func testRepetirUnaUbicacionNoConfirmaAbordaje() {
        var engine = makeEngine()
        let repeated = vehicleSample()

        for _ in 0..<5 {
            let result = engine.process(repeated, routeID: "ruta-a")
            XCTAssertEqual(result.state, .boardingCandidate)
            XCTAssertFalse(result.shouldPublish)
            XCTAssertFalse(result.didConfirmBoarding)
        }

        XCTAssertEqual(engine.process(vehicleSample(), routeID: "ruta-a").state, .boardingCandidate)
        let confirmed = engine.process(vehicleSample(), routeID: "ruta-a")
        XCTAssertEqual(confirmed.state, .onboard)
        XCTAssertTrue(confirmed.didConfirmBoarding)
        XCTAssertTrue(confirmed.shouldPublish)
    }

    func testMuestraDesordenadaNoInterrumpeEvidenciaNiCambiaRutaCandidata() {
        var engine = makeEngine()
        let first = vehicleSample()
        _ = engine.process(first, routeID: "ruta-a")
        _ = engine.process(vehicleSample(), routeID: "ruta-a")

        let rejected = engine.process(
            vehicleSample(timestamp: first.timestamp - 1),
            routeID: "ruta-b"
        )
        XCTAssertEqual(rejected.state, .boardingCandidate)
        XCTAssertFalse(rejected.shouldPublish)
        XCTAssertFalse(rejected.didConfirmBoarding)

        let confirmed = engine.process(vehicleSample(), routeID: "ruta-a")
        XCTAssertEqual(confirmed.state, .onboard)
        XCTAssertTrue(confirmed.didConfirmBoarding)
    }

    func testUbicacionDuplicadaABordoNoSeVuelveAPublicar() {
        var engine = onboardEngine()
        let fresh = vehicleSample()
        XCTAssertTrue(engine.process(fresh).shouldPublish)

        let duplicate = engine.process(fresh)
        XCTAssertEqual(duplicate.state, .onboard)
        XCTAssertFalse(duplicate.shouldPublish)
        XCTAssertFalse(duplicate.didConfirmBoarding)
        XCTAssertFalse(duplicate.didConfirmAlighting)
        XCTAssertTrue(engine.process(vehicleSample()).shouldPublish)
    }

    func testMuestraCaminandoDuplicadaNoConfirmaDescenso() {
        var engine = onboardEngine()
        let repeated = walkingSample()

        for _ in 0..<5 {
            let result = engine.process(repeated)
            XCTAssertEqual(result.state, .alightingCandidate)
            XCTAssertFalse(result.shouldPublish)
            XCTAssertFalse(result.didConfirmAlighting)
        }

        for _ in 0..<2 {
            XCTAssertEqual(engine.process(walkingSample()).state, .alightingCandidate)
        }
        let confirmed = engine.process(walkingSample())
        XCTAssertEqual(confirmed.state, .idle)
        XCTAssertTrue(confirmed.didConfirmAlighting)
    }

    func testFechasViejasYFuturasNoSumanEvidenciaNiAdelantanLaMarcaTemporal() {
        var engine = makeEngine()
        let first = vehicleSample()
        _ = engine.process(first, routeID: "ruta-a")
        let now = clock.time

        for timestamp in [now - 46, now + 11] {
            let rejected = engine.process(vehicleSample(timestamp: timestamp), routeID: "ruta-b")
            XCTAssertEqual(rejected.state, .boardingCandidate)
            XCTAssertFalse(rejected.shouldPublish)
            XCTAssertFalse(rejected.didConfirmBoarding)
        }

        XCTAssertEqual(engine.process(vehicleSample(), routeID: "ruta-a").state, .boardingCandidate)
        let confirmed = engine.process(vehicleSample(), routeID: "ruta-a")
        XCTAssertEqual(confirmed.state, .onboard)
        XCTAssertTrue(confirmed.didConfirmBoarding)
    }

    func testFechaNoFinitaNoCuentaComoUbicacionVehicular() {
        var engine = makeEngine()
        _ = engine.process(vehicleSample())

        for timestamp in [TimeInterval.nan, .infinity, -.infinity] {
            let rejected = engine.process(vehicleSample(timestamp: timestamp))
            XCTAssertEqual(rejected.state, .boardingCandidate)
            XCTAssertFalse(rejected.shouldPublish)
            XCTAssertFalse(rejected.didConfirmBoarding)
        }

        XCTAssertEqual(engine.process(vehicleSample()).state, .boardingCandidate)
        XCTAssertTrue(engine.process(vehicleSample()).didConfirmBoarding)
    }

    func testUbicacionViejaOFuturaABordoNoSePublica() {
        var engine = onboardEngine()
        clock.time += 60
        let now = clock.time

        // La fecha vieja es posterior a la última ubicación aceptada: no basta
        // con comprobar orden; también debe comprobarse su antigüedad real.
        for timestamp in [now - 46, now + 11] {
            let rejected = engine.process(vehicleSample(timestamp: timestamp))
            XCTAssertEqual(rejected.state, .onboard)
            XCTAssertFalse(rejected.shouldPublish)
            XCTAssertFalse(rejected.didConfirmAlighting)
        }
        XCTAssertTrue(engine.process(vehicleSample()).shouldPublish)
    }

    func testRelojNoFinitoNoAutorizaPublicarNiAcumulaEvidencia() {
        for invalidNow in [TimeInterval.nan, .infinity, -.infinity] {
            clock.time = 1_000_000
            var engine = makeEngine()
            let location = vehicleSample()
            let validNow = clock.time
            clock.time = invalidNow

            let rejected = engine.process(location)
            XCTAssertEqual(rejected.state, .idle)
            XCTAssertFalse(rejected.shouldPublish)

            // La misma fecha sigue disponible cuando el reloj vuelve a ser válido.
            clock.time = validNow
            XCTAssertEqual(engine.process(location).state, .boardingCandidate)
            XCTAssertEqual(engine.process(vehicleSample()).state, .boardingCandidate)
            XCTAssertTrue(engine.process(vehicleSample()).didConfirmBoarding)
        }
    }

    func testLimitesDeAntiguedadYAdelantoAceptanEvidenciaValida() {
        clock.time = 1_000_000
        let now = clock.time

        for firstTimestamp in [now - 45, now + 8] {
            var engine = makeEngine()
            _ = engine.process(vehicleSample(timestamp: firstTimestamp))
            _ = engine.process(vehicleSample(timestamp: firstTimestamp + 1))
            let confirmed = engine.process(vehicleSample(timestamp: firstTimestamp + 2))
            XCTAssertEqual(confirmed.state, .onboard)
            XCTAssertTrue(confirmed.shouldPublish)
            XCTAssertTrue(confirmed.didConfirmBoarding)
        }
    }

    func testPrecisionInvalidaRompeLaSecuenciaDeAbordaje() {
        for accuracy in [-1.0, 51, .nan, .infinity] {
            var engine = makeEngine()
            _ = engine.process(vehicleSample())
            _ = engine.process(vehicleSample())

            let rejected = engine.process(vehicleSample(accuracy: accuracy))
            XCTAssertEqual(rejected.state, .idle)
            XCTAssertFalse(rejected.shouldPublish)
            XCTAssertFalse(rejected.didConfirmBoarding)

            _ = engine.process(vehicleSample())
            XCTAssertEqual(engine.process(vehicleSample()).state, .boardingCandidate)
            XCTAssertTrue(engine.process(vehicleSample()).didConfirmBoarding)
        }
    }

    func testPrecisionInvalidaConFechaDuplicadaNoBorraLaEvidenciaAceptada() {
        var engine = makeEngine()
        _ = engine.process(vehicleSample(), routeID: "ruta-a")
        let second = vehicleSample()
        _ = engine.process(second, routeID: "ruta-a")

        let rejected = engine.process(
            vehicleSample(accuracy: -1, timestamp: second.timestamp),
            routeID: "ruta-b"
        )
        XCTAssertEqual(rejected.state, .boardingCandidate)
        XCTAssertFalse(rejected.shouldPublish)

        let confirmed = engine.process(vehicleSample(), routeID: "ruta-a")
        XCTAssertEqual(confirmed.state, .onboard)
        XCTAssertTrue(confirmed.didConfirmBoarding)
    }

    func testPrecisionInvalidaRompeDescensoSinPublicarNiConfirmarlo() {
        for accuracy in [-1.0, 51, .nan, .infinity] {
            var engine = onboardEngine()
            for _ in 0..<3 {
                _ = engine.process(walkingSample())
            }

            let rejected = engine.process(walkingSample(accuracy: accuracy))
            XCTAssertEqual(rejected.state, .alightingCandidate)
            XCTAssertFalse(rejected.shouldPublish)
            XCTAssertFalse(rejected.didConfirmAlighting)

            for _ in 0..<3 {
                let result = engine.process(walkingSample())
                XCTAssertEqual(result.state, .alightingCandidate)
                XCTAssertFalse(result.didConfirmAlighting)
            }
            XCTAssertTrue(engine.process(walkingSample()).didConfirmAlighting)
        }
    }

    func testHuecoMayorAlPermitidoReiniciaElAbordajeConLaMuestraActual() {
        var engine = makeEngine()
        _ = engine.process(vehicleSample())
        let second = vehicleSample()
        _ = engine.process(second)
        clock.time = second.timestamp + 31

        let afterGap = engine.process(vehicleSample())
        XCTAssertEqual(afterGap.state, .boardingCandidate)
        XCTAssertFalse(afterGap.didConfirmBoarding)
        XCTAssertFalse(afterGap.shouldPublish)
        XCTAssertEqual(engine.process(vehicleSample()).state, .boardingCandidate)
        XCTAssertTrue(engine.process(vehicleSample()).didConfirmBoarding)
    }

    func testIntervaloExactamenteEnElLimiteConservaLaEvidencia() {
        var engine = makeEngine()
        let firstTimestamp = clock.time

        for index in 0..<2 {
            clock.time = firstTimestamp + TimeInterval(index * 30)
            let result = engine.process(vehicleSample(timestamp: clock.time))
            XCTAssertEqual(result.state, .boardingCandidate)
            XCTAssertFalse(result.didConfirmBoarding)
        }
        clock.time = firstTimestamp + 60
        let confirmed = engine.process(vehicleSample(timestamp: clock.time))
        XCTAssertEqual(confirmed.state, .onboard)
        XCTAssertTrue(confirmed.didConfirmBoarding)
    }

    func testHuecoEnDescensoExigeCuatroMuestrasNuevasSinPerderElViaje() {
        var engine = onboardEngine()
        _ = engine.process(walkingSample())
        _ = engine.process(walkingSample())
        let third = walkingSample()
        _ = engine.process(third)
        clock.time = third.timestamp + 31

        for _ in 0..<3 {
            let result = engine.process(walkingSample())
            XCTAssertEqual(result.state, .alightingCandidate)
            XCTAssertFalse(result.didConfirmAlighting)
            XCTAssertFalse(result.shouldPublish)
        }
        let confirmed = engine.process(walkingSample())
        XCTAssertEqual(confirmed.state, .idle)
        XCTAssertTrue(confirmed.didConfirmAlighting)
    }

    func testBusDetenidoDespuesDeHuecoConservaAbordajeSinDescensoFalso() {
        var engine = onboardEngine()
        clock.time += 120

        let stopped = engine.process(stationarySample())
        XCTAssertEqual(stopped.state, .onboard)
        XCTAssertTrue(stopped.shouldPublish)
        XCTAssertFalse(stopped.didConfirmBoarding)
        XCTAssertFalse(stopped.didConfirmAlighting)
        XCTAssertTrue(engine.process(vehicleSample()).shouldPublish)
    }

    func testCambioDeRutaCandidataExigeTresMuestrasDeLaNuevaRuta() {
        var engine = makeEngine()
        _ = engine.process(vehicleSample(), routeID: "ruta-a")
        _ = engine.process(vehicleSample(), routeID: "ruta-a")

        for _ in 0..<2 {
            let result = engine.process(vehicleSample(), routeID: "ruta-b")
            XCTAssertEqual(result.state, .boardingCandidate)
            XCTAssertFalse(result.didConfirmBoarding)
            XCTAssertFalse(result.shouldPublish)
        }
        let confirmed = engine.process(vehicleSample(), routeID: "ruta-b")
        XCTAssertEqual(confirmed.state, .onboard)
        XCTAssertTrue(confirmed.didConfirmBoarding)
    }

    func testRutaAusenteNoUneEvidenciaDeDosCandidatas() {
        var engine = makeEngine()
        _ = engine.process(vehicleSample(), routeID: "ruta-a")
        _ = engine.process(vehicleSample(), routeID: "ruta-a")
        XCTAssertEqual(engine.process(vehicleSample(), routeID: nil).state, .boardingCandidate)

        for _ in 0..<2 {
            let result = engine.process(vehicleSample(), routeID: "ruta-a")
            XCTAssertEqual(result.state, .boardingCandidate)
            XCTAssertFalse(result.didConfirmBoarding)
        }
        XCTAssertTrue(engine.process(vehicleSample(), routeID: "ruta-a").didConfirmBoarding)
    }

    func testCambioDeCandidataABordoNoConfirmaUnSegundoAbordaje() {
        var engine = makeEngine()
        for _ in 0..<3 {
            _ = engine.process(vehicleSample(), routeID: "ruta-a")
        }

        let result = engine.process(vehicleSample(), routeID: "ruta-b")
        XCTAssertEqual(result.state, .onboard)
        XCTAssertTrue(result.shouldPublish)
        XCTAssertFalse(result.didConfirmBoarding)
        XCTAssertFalse(result.didConfirmAlighting)
    }

    func testResetPermiteFechasAnterioresSinReutilizarEvidenciaDelViajePrevio() {
        var engine = makeEngine()
        clock.time = 1_000_200
        _ = engine.process(vehicleSample(), routeID: "ruta-a")
        _ = engine.process(vehicleSample(), routeID: "ruta-a")
        engine.reset()
        XCTAssertEqual(engine.state, .idle)
        clock.time = 1_000_000

        for _ in 0..<2 {
            let result = engine.process(vehicleSample(), routeID: "ruta-b")
            XCTAssertEqual(result.state, .boardingCandidate)
            XCTAssertFalse(result.shouldPublish)
            XCTAssertFalse(result.didConfirmBoarding)
        }
        let confirmed = engine.process(vehicleSample(), routeID: "ruta-b")
        XCTAssertEqual(confirmed.state, .onboard)
        XCTAssertTrue(confirmed.didConfirmBoarding)
    }

    private func makeEngine() -> PassengerDetectionEngine {
        PassengerDetectionEngine(now: { [clock] in clock.time })
    }

    private func onboardEngine() -> PassengerDetectionEngine {
        var engine = makeEngine()
        _ = engine.process(vehicleSample())
        _ = engine.process(vehicleSample())
        _ = engine.process(vehicleSample())
        return engine
    }

    private func vehicleSample(
        accuracy: Double = 10,
        timestamp: TimeInterval? = nil
    ) -> PassengerDetectionSample {
        sample(
            activity: .automotive,
            speed: 10,
            distanceToRoute: 10,
            headingDifference: 15,
            distanceToStop: 30,
            accuracy: accuracy,
            timestamp: timestamp
        )
    }

    private func walkingSample(accuracy: Double = 10) -> PassengerDetectionSample {
        sample(
            activity: .walking,
            speed: 1.3,
            distanceToRoute: 15,
            headingDifference: 30,
            distanceToStop: 25,
            accuracy: accuracy
        )
    }

    private func stationarySample() -> PassengerDetectionSample {
        sample(
            activity: .stationary,
            speed: 0,
            distanceToRoute: 5,
            headingDifference: 5,
            distanceToStop: 5
        )
    }

    private func sample(
        activity: DetectedMotionActivity,
        speed: Double,
        distanceToRoute: Double,
        headingDifference: Double,
        distanceToStop: Double,
        accuracy: Double = 10,
        timestamp: TimeInterval? = nil
    ) -> PassengerDetectionSample {
        let sampleTime = timestamp ?? clock.time
        if timestamp == nil {
            clock.time += 1
        }
        return PassengerDetectionSample(
            timestamp: sampleTime,
            speed: speed,
            horizontalAccuracy: accuracy,
            distanceToRoute: distanceToRoute,
            headingDifference: headingDifference,
            distanceToNearestStop: distanceToStop,
            motionActivity: activity
        )
    }
}

private final class DetectionTestClock {
    var time: TimeInterval = 1_000_000
}
