#if os(iOS)
import AlignCore
import CoreMotion
import Foundation

/// Streams head motion from motion-capable headphones (AirPods Pro etc.) through
/// `CMHeadphoneMotionManager`.
///
/// - Requires `NSMotionUsageDescription` in the app's Info.plist; without it the system
///   terminates the app when updates start.
/// - Updates and delegate callbacks are delivered on the main queue.
/// - Nothing runs while idle: Core Motion updates are started in `start()` and stopped in
///   `stop()`, when a newer stream replaces the current one, or when the consumer stops
///   iterating the stream.
/// - Background / locked-screen delivery is NOT guaranteed and is unverified (see
///   docs/research/airpods-motion-feasibility.md).
@MainActor
public final class RealAirPodsSensorProvider: SensorProvider {
    public private(set) var connectionState: SensorConnectionState = .idle

    public var authorization: SensorAuthorization {
        Self.mapAuthorization(CMHeadphoneMotionManager.authorizationStatus())
    }

    public var isMotionAvailable: Bool {
        manager.isDeviceMotionAvailable
    }

    private let manager: CMHeadphoneMotionManager
    private let delegateProxy: HeadphoneMotionDelegateProxy
    private var continuation: AsyncStream<SensorEvent>.Continuation?
    /// Identifies the current stream so a late termination of an old stream is ignored.
    private var streamID = 0
    private var isReceivingUpdates = false

    private static let bufferLimit = 500

    public init() {
        manager = CMHeadphoneMotionManager()
        delegateProxy = HeadphoneMotionDelegateProxy()
        delegateProxy.onConnect = { [weak self] in
            self?.headphonesDidConnect()
        }
        delegateProxy.onDisconnect = { [weak self] in
            self?.headphonesDidDisconnect()
        }
        manager.delegate = delegateProxy
    }

    public func start() -> AsyncStream<SensorEvent> {
        finishCurrentStream()
        streamID += 1
        let currentStreamID = streamID

        var created: AsyncStream<SensorEvent>.Continuation?
        let stream = AsyncStream<SensorEvent>(bufferingPolicy: .bufferingNewest(Self.bufferLimit)) { continuation in
            created = continuation
        }
        guard let continuation = created else { return stream }
        continuation.onTermination = { [weak self] _ in
            guard let provider = self else { return }
            Task { @MainActor in
                provider.streamTerminated(streamID: currentStreamID)
            }
        }
        self.continuation = continuation
        beginStreaming()
        return stream
    }

    public func stop() {
        stopUpdates()
        streamID += 1
        connectionState = .idle
        guard let continuation else { return }
        self.continuation = nil
        continuation.yield(.connectionChanged(.idle))
        continuation.finish()
    }

    // MARK: - Streaming

    private func beginStreaming() {
        // The first event of a stream is always the current state, so every path below
        // emits exactly one state before any sample.
        guard manager.isDeviceMotionAvailable else {
            emit(.unavailable(.motionNotSupported))
            return
        }
        switch CMHeadphoneMotionManager.authorizationStatus() {
        case .denied, .restricted:
            emit(.unavailable(.notAuthorized))
            return
        case .notDetermined, .authorized:
            // .notDetermined: starting updates makes the system ask for permission.
            break
        @unknown default:
            break
        }

        // There is no API to ask whether headphones are connected right now. Assume not;
        // the first sample or a didConnect callback moves the state to .connected.
        emit(.waitingForHeadphones)
        isReceivingUpdates = true
        manager.startDeviceMotionUpdates(to: OperationQueue.main) { [weak self] motion, error in
            // Delivered on the main queue (OperationQueue.main).
            MainActor.assumeIsolated { () -> Void in
                self?.handleUpdate(motion: motion, error: error)
            }
        }
    }

    private func handleUpdate(motion: CMDeviceMotion?, error: Error?) {
        guard isReceivingUpdates, let continuation else { return }
        if let error {
            stopUpdates()
            let status = CMHeadphoneMotionManager.authorizationStatus()
            if status == .denied || status == .restricted {
                updateState(.unavailable(.notAuthorized))
            } else {
                updateState(.failed(message: error.localizedDescription))
            }
            return
        }
        guard let motion else { return }
        if connectionState != .connected {
            updateState(.connected)
        }
        continuation.yield(.sample(Self.makeSample(from: motion)))
    }

    private func headphonesDidConnect() {
        guard isReceivingUpdates else { return }
        updateState(.connected)
    }

    private func headphonesDidDisconnect() {
        guard isReceivingUpdates else { return }
        updateState(.waitingForHeadphones)
    }

    private func stopUpdates() {
        guard isReceivingUpdates else { return }
        isReceivingUpdates = false
        manager.stopDeviceMotionUpdates()
    }

    // MARK: - State and stream helpers

    /// Sets and always emits `state`.
    private func emit(_ state: SensorConnectionState) {
        connectionState = state
        continuation?.yield(.connectionChanged(state))
    }

    /// Sets and emits `state` only if it changed.
    private func updateState(_ state: SensorConnectionState) {
        guard state != connectionState else { return }
        emit(state)
    }

    /// Ends the current stream without emitting `.idle` (used when a new stream replaces it).
    private func finishCurrentStream() {
        stopUpdates()
        guard let continuation else { return }
        self.continuation = nil
        continuation.finish()
    }

    /// The consumer stopped listening (e.g. its task was cancelled): stop Core Motion.
    private func streamTerminated(streamID terminatedStreamID: Int) {
        guard terminatedStreamID == streamID, continuation != nil else { return }
        stopUpdates()
        streamID += 1
        continuation = nil
        connectionState = .idle
    }

    // MARK: - Mapping

    nonisolated static func makeSample(from motion: CMDeviceMotion) -> MotionSample {
        let q = motion.attitude.quaternion
        let gravity = motion.gravity
        let rotationRate = motion.rotationRate
        let userAcceleration = motion.userAcceleration
        return MotionSample(
            timestamp: motion.timestamp,
            attitude: Quaternion(x: q.x, y: q.y, z: q.z, w: q.w),
            gravity: Vector3(x: gravity.x, y: gravity.y, z: gravity.z),
            rotationRate: Vector3(x: rotationRate.x, y: rotationRate.y, z: rotationRate.z),
            userAcceleration: Vector3(x: userAcceleration.x, y: userAcceleration.y, z: userAcceleration.z),
            sensorLocation: mapSensorLocation(motion.sensorLocation)
        )
    }

    nonisolated static func mapSensorLocation(_ location: CMDeviceMotion.SensorLocation) -> SensorLocation {
        switch location {
        case .headphoneLeft:
            return .headphoneLeft
        case .headphoneRight:
            return .headphoneRight
        case .default:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    nonisolated static func mapAuthorization(_ status: CMAuthorizationStatus) -> SensorAuthorization {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .authorized:
            return .authorized
        @unknown default:
            return .notDetermined
        }
    }
}

/// `CMHeadphoneMotionManagerDelegate` inherits from `NSObjectProtocol`, so the delegate must
/// be an `NSObject`. This proxy forwards callbacks to main-actor closures on the main queue.
private final class HeadphoneMotionDelegateProxy: NSObject, CMHeadphoneMotionManagerDelegate {
    var onConnect: (@MainActor @Sendable () -> Void)?
    var onDisconnect: (@MainActor @Sendable () -> Void)?

    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        let handler = onConnect
        DispatchQueue.main.async {
            MainActor.assumeIsolated { () -> Void in
                handler?()
            }
        }
    }

    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        let handler = onDisconnect
        DispatchQueue.main.async {
            MainActor.assumeIsolated { () -> Void in
                handler?()
            }
        }
    }
}
#endif
