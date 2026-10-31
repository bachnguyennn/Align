import Foundation

/// Which earbud produced a sample, mirroring `CMDeviceMotion.SensorLocation`.
public enum SensorLocation: String, Codable, Sendable {
    case unknown
    case headphoneLeft
    case headphoneRight
}

/// One head-motion reading. All vectors are in the headphone (head) body frame.
public struct MotionSample: Equatable, Codable, Sendable {
    /// Seconds on the monotonic clock used by `CMLogItem.timestamp` (time since boot,
    /// same base as `ProcessInfo.systemUptime`). Not wall-clock time.
    public var timestamp: TimeInterval
    /// Head attitude (`CMAttitude.quaternion`). Its reference frame's heading is arbitrary
    /// and may change between streaming sessions, so never compare attitudes across sessions.
    public var attitude: Quaternion
    /// Gravity in the head frame, in g. Real and mock providers must populate this.
    public var gravity: Vector3?
    /// Rotation rate in the head frame, rad/s.
    public var rotationRate: Vector3?
    /// User acceleration (gravity removed) in the head frame, in g.
    public var userAcceleration: Vector3?
    public var sensorLocation: SensorLocation

    public init(
        timestamp: TimeInterval,
        attitude: Quaternion,
        gravity: Vector3? = nil,
        rotationRate: Vector3? = nil,
        userAcceleration: Vector3? = nil,
        sensorLocation: SensorLocation = .unknown
    ) {
        self.timestamp = timestamp
        self.attitude = attitude
        self.gravity = gravity
        self.rotationRate = rotationRate
        self.userAcceleration = userAcceleration
        self.sensorLocation = sensorLocation
    }
}

/// Mirrors `CMAuthorizationStatus` for headphone motion.
public enum SensorAuthorization: String, Codable, Sendable {
    case notDetermined
    case restricted
    case denied
    case authorized
}

public enum SensorUnavailableReason: String, Codable, Sendable {
    /// This device/OS cannot provide headphone motion (e.g. the simulator).
    case motionNotSupported
    /// The user denied, or a policy restricts, motion access.
    case notAuthorized
}

public enum SensorConnectionState: Equatable, Sendable {
    /// Not started.
    case idle
    case unavailable(SensorUnavailableReason)
    /// Streaming was requested but no compatible headphones are connected.
    case waitingForHeadphones
    /// Compatible headphones are connected; samples are expected.
    case connected
    /// Core Motion reported an error; streaming has stopped.
    case failed(message: String)
}

public enum SensorEvent: Equatable, Sendable {
    case connectionChanged(SensorConnectionState)
    case sample(MotionSample)
}

/// A source of head-motion samples. Implemented by `RealAirPodsSensorProvider` and
/// `MockSensorProvider` in the Sensors module. See docs/agents/sensor-contracts.md.
@MainActor
public protocol SensorProvider: AnyObject {
    var connectionState: SensorConnectionState { get }
    var authorization: SensorAuthorization { get }
    /// Whether this device/OS can provide headphone motion at all.
    var isMotionAvailable: Bool { get }
    /// Starts streaming and returns a new event stream; any previous stream is finished.
    /// The first event is always the current `connectionChanged` state.
    func start() -> AsyncStream<SensorEvent>
    /// Stops streaming, emits `.connectionChanged(.idle)` and finishes the current stream.
    func stop()
}
