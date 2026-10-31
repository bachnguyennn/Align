import AlignCore
import XCTest
@testable import Sensors

final class MockSensorProviderTests: XCTestCase {
    /// Collects events until `stopWhen` returns true or `timeout` seconds pass, then returns
    /// what was collected. On timeout the provider is stopped so the stream ends.
    @MainActor
    private func collect(
        from stream: AsyncStream<SensorEvent>,
        provider: MockSensorProvider,
        timeout: Double = 5,
        stopWhen: ([SensorEvent]) -> Bool
    ) async -> [SensorEvent] {
        let watchdog = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if !Task.isCancelled {
                provider.stop()
            }
        }
        defer { watchdog.cancel() }
        var events: [SensorEvent] = []
        for await event in stream {
            events.append(event)
            if stopWhen(events) {
                break
            }
        }
        return events
    }

    private static func samples(in events: [SensorEvent]) -> [MotionSample] {
        events.compactMap { event in
            if case .sample(let sample) = event {
                return sample
            }
            return nil
        }
    }

    @MainActor
    func testUnavailableScenarioEmitsStateAndStaysOpenUntilStop() async {
        let provider = MockSensorProvider(scenario: .unavailable)
        XCTAssertFalse(provider.isMotionAvailable)
        XCTAssertEqual(provider.connectionState, .idle)

        let stream = provider.start()
        XCTAssertEqual(provider.connectionState, .unavailable(.motionNotSupported))
        provider.stop()
        XCTAssertEqual(provider.connectionState, .idle)

        var events: [SensorEvent] = []
        for await event in stream {
            events.append(event)
        }
        XCTAssertEqual(events, [
            .connectionChanged(.unavailable(.motionNotSupported)),
            .connectionChanged(.idle),
        ])
    }

    @MainActor
    func testPermissionDeniedScenarioReportsNotAuthorized() async {
        let provider = MockSensorProvider(scenario: .permissionDenied)
        XCTAssertEqual(provider.authorization, .denied)
        XCTAssertTrue(provider.isMotionAvailable)

        let stream = provider.start()
        provider.stop()
        var events: [SensorEvent] = []
        for await event in stream {
            events.append(event)
        }
        XCTAssertEqual(events, [
            .connectionChanged(.unavailable(.notAuthorized)),
            .connectionChanged(.idle),
        ])
    }

    @MainActor
    func testStreamingScenarioDeliversSamplesWithGravityAndMonotonicTimestamps() async {
        let startUptime = ProcessInfo.processInfo.systemUptime
        let provider = MockSensorProvider(scenario: .steadyNeutral, sampleRateHz: 50, timeScale: 10)
        XCTAssertEqual(provider.authorization, .authorized)

        let stream = provider.start()
        let events = await collect(from: stream, provider: provider) { events in
            Self.samples(in: events).count >= 10
        }
        provider.stop()

        XCTAssertEqual(events.first, .connectionChanged(.connected))
        let samples = Self.samples(in: events)
        XCTAssertEqual(samples.count, 10)
        guard let first = samples.first else { return }
        XCTAssertGreaterThanOrEqual(first.timestamp, startUptime)
        for (previous, next) in zip(samples, samples.dropFirst()) {
            // Simulated time advances by exactly 1 / sampleRateHz per sample.
            XCTAssertEqual(next.timestamp - previous.timestamp, 1.0 / 50, accuracy: 1e-9)
        }
        for sample in samples {
            XCTAssertNotNil(sample.gravity)
        }
    }

    @MainActor
    func testManualTiltIsReflectedInGravity() async {
        let provider = MockSensorProvider(scenario: .manual, sampleRateHz: 50, timeScale: 10)
        provider.setSimulatedTilt(forwardDegrees: 20, lateralDegrees: -5)
        let stream = provider.start()
        let events = await collect(from: stream, provider: provider) { events in
            Self.samples(in: events).count >= 3
        }
        provider.stop()

        guard let sample = Self.samples(in: events).last, let gravity = sample.gravity else {
            XCTFail("no sample received")
            return
        }
        let tilt = TiltReference.headTiltDegrees(gravity: gravity)
        XCTAssertEqual(tilt.forward, 20, accuracy: 1.5)
        XCTAssertEqual(tilt.lateral, -5, accuracy: 1.5)
    }

    @MainActor
    func testStartFinishesPreviousStream() async {
        let provider = MockSensorProvider(scenario: .unavailable)
        let first = provider.start()
        let second = provider.start()

        var firstEvents: [SensorEvent] = []
        for await event in first {
            firstEvents.append(event)
        }
        // The first stream ended without needing stop(), and without an .idle event.
        XCTAssertEqual(firstEvents, [.connectionChanged(.unavailable(.motionNotSupported))])

        provider.stop()
        var secondEvents: [SensorEvent] = []
        for await event in second {
            secondEvents.append(event)
        }
        XCTAssertEqual(secondEvents, [
            .connectionChanged(.unavailable(.motionNotSupported)),
            .connectionChanged(.idle),
        ])
    }

    @MainActor
    func testStopWithoutStartIsHarmless() async {
        let provider = MockSensorProvider()
        provider.stop()
        XCTAssertEqual(provider.connectionState, .idle)
    }

    @MainActor
    func testChangingScenarioWhileStreamingKeepsStreamAndReportsNewState() async {
        let provider = MockSensorProvider(scenario: .steadyNeutral, sampleRateHz: 50, timeScale: 10)
        let stream = provider.start()
        let events = await collect(from: stream, provider: provider) { events in
            if Self.samples(in: events).count == 2 {
                provider.scenario = .unavailable
            }
            return events.last == .connectionChanged(.unavailable(.motionNotSupported))
        }
        XCTAssertEqual(events.first, .connectionChanged(.connected))
        XCTAssertEqual(events.last, .connectionChanged(.unavailable(.motionNotSupported)))
        XCTAssertEqual(provider.connectionState, .unavailable(.motionNotSupported))
        provider.stop()
    }
}
