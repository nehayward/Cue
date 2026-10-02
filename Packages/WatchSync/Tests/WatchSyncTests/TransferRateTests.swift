import XCTest
@testable import WatchSync

final class TransferRateMeterTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    func testNoRateUntilTheMinimumSpan() {
        var meter = TransferRateMeter(window: 5, minimumSpan: 1)
        XCTAssertNil(meter.bytesPerSecond)
        meter.record(total: 0, at: at(0))
        meter.record(total: 500, at: at(0.5))
        XCTAssertNil(meter.bytesPerSecond)
        meter.record(total: 1_000, at: at(1))
        XCTAssertEqual(meter.bytesPerSecond, 1_000)
    }

    func testRateCoversOnlyTheWindow() {
        var meter = TransferRateMeter(window: 2, minimumSpan: 1)
        // A fast start, then a crawl: the rate should reflect the crawl.
        meter.record(total: 0, at: at(0))
        meter.record(total: 10_000_000, at: at(1))
        meter.record(total: 10_000_100, at: at(2))
        meter.record(total: 10_000_200, at: at(3))
        meter.record(total: 10_000_300, at: at(4))
        XCTAssertEqual(meter.bytesPerSecond, 100)
    }

    func testAStallBringsTheRateDown() {
        var meter = TransferRateMeter(window: 4, minimumSpan: 1)
        meter.record(total: 0, at: at(0))
        meter.record(total: 4_000_000, at: at(2))
        for second in 3 ... 8 {
            meter.record(total: 4_000_000, at: at(TimeInterval(second)))
        }
        XCTAssertEqual(meter.bytesPerSecond, 0)
    }

    func testATotalThatGoesBackStartsOver() {
        var meter = TransferRateMeter(window: 5, minimumSpan: 1)
        meter.record(total: 5_000, at: at(0))
        meter.record(total: 6_000, at: at(1))
        meter.record(total: 100, at: at(2))
        XCTAssertNil(meter.bytesPerSecond)
        meter.record(total: 300, at: at(3))
        XCTAssertEqual(meter.bytesPerSecond, 200)
    }
}

final class RouteEstimatorTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    func testMeasuresUntilThereIsARate() {
        var estimator = RouteEstimator()
        XCTAssertEqual(estimator.update(bytesPerSecond: nil, at: at(0)), .measuring)
        XCTAssertEqual(estimator.update(bytesPerSecond: nil, at: at(10)), .measuring)
    }

    func testAPlainlyFastTransferIsWiFiAtOnce() {
        var estimator = RouteEstimator()
        XCTAssertEqual(estimator.update(bytesPerSecond: 2_000_000, at: at(1)), .wifi)
    }

    func testASlowTransferIsOnlyCalledSlowOnceSettled() {
        var estimator = RouteEstimator()
        XCTAssertEqual(estimator.update(bytesPerSecond: 60_000, at: at(0)), .measuring)
        XCTAssertEqual(estimator.update(bytesPerSecond: 60_000, at: at(3)), .measuring)
        XCTAssertEqual(estimator.update(bytesPerSecond: 60_000, at: at(RouteEstimator.settleTime)), .throughPhone)
    }

    func testBetweenTheThresholdsTheVerdictHolds() {
        var estimator = RouteEstimator()
        estimator.update(bytesPerSecond: 3_000_000, at: at(0))
        XCTAssertEqual(estimator.update(bytesPerSecond: 300_000, at: at(10)), .wifi)
        XCTAssertEqual(estimator.update(bytesPerSecond: 100_000, at: at(11)), .throughPhone)
        XCTAssertEqual(estimator.update(bytesPerSecond: 300_000, at: at(12)), .throughPhone)
        XCTAssertEqual(estimator.update(bytesPerSecond: 1_500_000, at: at(13)), .wifi)
    }

    func testAMiddlingRateSettlesAsWiFi() {
        var estimator = RouteEstimator()
        XCTAssertEqual(estimator.update(bytesPerSecond: 300_000, at: at(0)), .measuring)
        XCTAssertEqual(estimator.update(bytesPerSecond: 300_000, at: at(6)), .wifi)
    }

    func testResetStartsMeasuringAgain() {
        var estimator = RouteEstimator()
        estimator.update(bytesPerSecond: 50_000, at: at(0))
        estimator.update(bytesPerSecond: 50_000, at: at(6))
        XCTAssertEqual(estimator.route, .throughPhone)
        estimator.reset()
        XCTAssertEqual(estimator.route, .measuring)
        XCTAssertEqual(estimator.update(bytesPerSecond: 50_000, at: at(7)), .measuring)
    }
}
