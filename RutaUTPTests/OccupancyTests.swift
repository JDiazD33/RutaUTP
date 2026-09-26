import XCTest
@testable import RutaUTP

final class OccupancyTests: XCTestCase {
    private let now: TimeInterval = 1_790_000_000

    func testBackendReadingDecodesAndIsValid() throws {
        let json = """
        {"vehicleId":"bus-1","state":"full","confirmations":2,
         "updatedAt":1790000000,"expiresAt":1790000180}
        """
        let reading = try JSONDecoder().decode(OccupancyReading.self, from: Data(json.utf8))
        XCTAssertEqual(reading.state, .full)
        XCTAssertEqual(reading.id, "bus-1")
        XCTAssertTrue(reading.isValid(at: now))
        XCTAssertFalse(reading.isValid(at: now + 180))
    }

    func testSingleReportIsNotPresentedAsConfirmed() {
        XCTAssertFalse(reading(confirmations: 1).isValid(at: now))
    }

    func testFutureAndStaleReadingsAreRejected() {
        XCTAssertFalse(reading(updatedAt: now + 11).isValid(at: now))
        XCTAssertFalse(reading(updatedAt: now - 181).isValid(at: now))
        XCTAssertFalse(reading(expiresAt: now + 181).isValid(at: now))
        XCTAssertFalse(reading(expiresAt: .infinity).isValid(at: now))
    }

    func testUnknownStateIsRejected() {
        let json = """
        {"vehicleId":"bus-1","state":"fake","confirmations":2,
         "updatedAt":1790000000,"expiresAt":1790000180}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(OccupancyReading.self, from: Data(json.utf8)))
    }

    private func reading(confirmations: Int = 2, updatedAt: TimeInterval? = nil,
                         expiresAt: TimeInterval? = nil) -> OccupancyReading {
        OccupancyReading(vehicleId: "bus-1", state: .empty, confirmations: confirmations,
                         updatedAt: updatedAt ?? now, expiresAt: expiresAt ?? now+180)
    }
}
