import XCTest
@testable import Sensors

final class SampleRateMeterTests: XCTestCase {
    func testEmptyAndSingleSampleReportNil() {
        var meter = SampleRateMeter()
        XCTAssertNil(meter.samplesPerSecond)
        XCTAssertNil(meter.largestGap)
        meter.record(100)
        XCTAssertNil(meter.samplesPerSecond)
        XCTAssertNil(meter.largestGap)
    }

    func testSteady25HzOverWindow() {
        var meter = SampleRateMeter(window: 5)
        for index in 0...250 { // 10 s at 25 Hz
            meter.record(1000 + Double(index) / 25)
        }
        XCTAssertEqual(meter.samplesPerSecond ?? 0, 25, accuracy: 0.01)
        XCTAssertEqual(meter.largestGap ?? 0, 0.04, accuracy: 1e-9)
        // Only the last 5 s (inclusive) are kept: 126 samples.
        XCTAssertEqual(meter.sampleCount, 126)
    }

    func testLargestGapAndWindowExpiry() {
        var meter = SampleRateMeter(window: 5)
        meter.record(0)
        meter.record(0.04)
        meter.record(0.54) // 0.5 s gap
        meter.record(0.58)
        XCTAssertEqual(meter.largestGap ?? 0, 0.5, accuracy: 1e-9)

        // Move the window past the gap with steady 0.1 s spacing.
        var t = 0.58
        while t < 7 {
            t += 0.1
            meter.record(t)
        }
        XCTAssertEqual(meter.largestGap ?? 0, 0.1, accuracy: 1e-6)
        XCTAssertEqual(meter.samplesPerSecond ?? 0, 10, accuracy: 0.01)
    }

    func testBackwardsTimestampResets() {
        var meter = SampleRateMeter()
        meter.record(50)
        meter.record(50.04)
        meter.record(10)
        XCTAssertEqual(meter.sampleCount, 1)
        XCTAssertNil(meter.samplesPerSecond)
    }

    func testIdenticalTimestampsHaveNoRate() {
        var meter = SampleRateMeter()
        meter.record(3)
        meter.record(3)
        XCTAssertNil(meter.samplesPerSecond)
        XCTAssertEqual(meter.largestGap, 0)
    }

    func testResetClears() {
        var meter = SampleRateMeter()
        meter.record(1)
        meter.record(2)
        meter.reset()
        XCTAssertEqual(meter.sampleCount, 0)
        XCTAssertNil(meter.samplesPerSecond)
    }

    func testNonPositiveWindowFallsBackToDefault() {
        let meter = SampleRateMeter(window: 0)
        XCTAssertEqual(meter.window, 5)
    }
}
