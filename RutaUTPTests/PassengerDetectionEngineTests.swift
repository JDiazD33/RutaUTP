import XCTest
@testable import RutaUTP

final class PassengerDetectionEngineTests: XCTestCase {

    func testCaminarCercaDelParaderoNoConfirmaAbordaje() {
        var engine = PassengerDetectionEngine()

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
        var engine = PassengerDetectionEngine()

        let result = engine.process(vehicleSample())

        XCTAssertEqual(result.state, .boardingCandidate)
        XCTAssertFalse(result.shouldPublish)
    }

    func testTresMuestrasVehicularesConfirmanAbordaje() {
        var engine = PassengerDetectionEngine()

        _ = engine.process(vehicleSample())
        _ = engine.process(vehicleSample())
        let result = engine.process(vehicleSample())

        XCTAssertEqual(result.state, .onboard)
        XCTAssertTrue(result.shouldPublish)
        XCTAssertTrue(result.didConfirmBoarding)
    }

    func testVehiculoAlejadoDeRutaNoConfirmaAbordaje() {
        var engine = PassengerDetectionEngine()

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
        var engine = PassengerDetectionEngine()

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

        let result = engine.process(
            sample(
                activity: .stationary,
                speed: 0,
                distanceToRoute: 5,
                headingDifference: 5,
                distanceToStop: 5
            )
        )

        XCTAssertEqual(result.state, .onboard)
        XCTAssertTrue(result.shouldPublish)
        XCTAssertFalse(result.didConfirmAlighting)
    }

    func testCuatroMuestrasCaminandoConfirmanDescenso() {
        var engine = onboardEngine()
        var result: PassengerDetectionDecision?

        for _ in 0..<4 {
            result = engine.process(
                sample(
                    activity: .walking,
                    speed: 1.3,
                    distanceToRoute: 15,
                    headingDifference: 30,
                    distanceToStop: 25
                )
            )
        }

        XCTAssertEqual(result?.state, .idle)
        XCTAssertFalse(result?.shouldPublish ?? true)
        XCTAssertTrue(result?.didConfirmAlighting ?? false)
    }

    func testUbicacionImprecisaNoSePublica() {
        var engine = onboardEngine()

        let result = engine.process(
            sample(
                activity: .automotive,
                speed: 10,
                distanceToRoute: 5,
                headingDifference: 5,
                distanceToStop: 30,
                accuracy: 120
            )
        )

        XCTAssertEqual(result.state, .onboard)
        XCTAssertFalse(result.shouldPublish)
    }

    private func onboardEngine() -> PassengerDetectionEngine {
        var engine = PassengerDetectionEngine()

        _ = engine.process(vehicleSample())
        _ = engine.process(vehicleSample())
        _ = engine.process(vehicleSample())

        return engine
    }

    private func vehicleSample() -> PassengerDetectionSample {
        sample(
            activity: .automotive,
            speed: 10,
            distanceToRoute: 10,
            headingDifference: 15,
            distanceToStop: 30
        )
    }

    private func sample(
        activity: DetectedMotionActivity,
        speed: Double,
        distanceToRoute: Double,
        headingDifference: Double,
        distanceToStop: Double,
        accuracy: Double = 10
    ) -> PassengerDetectionSample {
        PassengerDetectionSample(
            timestamp: Date().timeIntervalSince1970,
            speed: speed,
            horizontalAccuracy: accuracy,
            distanceToRoute: distanceToRoute,
            headingDifference: headingDifference,
            distanceToNearestStop: distanceToStop,
            motionActivity: activity
        )
    }
}
