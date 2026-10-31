import AlignCore
import Foundation

/// A simulated head pose, in degrees.
///
/// `forwardDegrees` and `lateralDegrees` use the same sign convention as `TiltEstimate`
/// (positive = chin toward chest / right ear toward right shoulder). `headingDegrees` turns the
/// head left/right about the world vertical and must not affect tilt.
struct MockHeadPose: Equatable, Sendable {
    var forwardDegrees: Double
    var lateralDegrees: Double
    var headingDegrees: Double

    init(forwardDegrees: Double = 0, lateralDegrees: Double = 0, headingDegrees: Double = 0) {
        self.forwardDegrees = forwardDegrees
        self.lateralDegrees = lateralDegrees
        self.headingDegrees = headingDegrees
    }

    static let neutral = MockHeadPose()
}

/// Pure, deterministic sample generation for `MockSensorProvider`.
///
/// Everything here is a function of (scenario, seed, simulated time), with no clocks and no
/// mutable random state, so tests can query any instant without sleeping.
///
/// ## Frames (assumption, documented for the Algorithm agent)
/// - World frame: Z up, gravity = (0, 0, −1) g. The neutral head frame coincides with the
///   world frame (head +Z up, matching Apple's headphone axis illustration where +Z points up
///   out of the head when worn).
/// - `attitude` maps head-frame vectors to world-frame vectors: `world = attitude.rotate(head)`.
/// - A pose is the head rotation whose rotation vector (in the neutral frame) is
///   `forwardAxis·forward + lateralAxis·lateral`, followed by a heading turn about world Z.
/// - Gravity in the head frame = `attitude.conjugate.rotate((0, 0, −1))`.
///
/// So with `HeadAxisConvention.airPodsDefault` (forwardAxis = +X) a +20° forward pose is a +20°
/// rotation of the head about +X, and the head-frame gravity becomes (0, −sin 20°, −cos 20°).
/// Heading changes the attitude but not the head-frame gravity.
///
/// Whether `CMAttitude.quaternion` uses the same head→world direction is UNVERIFIED (S-05);
/// the posture pipeline uses gravity only (D-005), so the mock is consistent for it either way.
///
/// The mock follows whatever `axes` says, even if that convention is physically impossible.
/// Note: in a right-handed frame with +Z up, the chin-down axis × the right-ear-down axis
/// must point DOWN, but `airPodsDefault` gives +X × +Y = +Z (up), so one of its two signs
/// cannot match real hardware. See docs/research/airpods-motion-feasibility.md §5.
struct MockMotionGenerator: Sendable {
    var scenario: MockScenario
    var sampleRateHz: Double
    var axes: HeadAxisConvention
    var seed: UInt64
    /// 0 disables all noise (useful in tests); 1 is the default realistic level.
    var noiseScale: Double
    /// Pose used by `.manual`.
    var manualPose: MockHeadPose

    init(
        scenario: MockScenario,
        sampleRateHz: Double = 25,
        axes: HeadAxisConvention = .airPodsDefault,
        seed: UInt64 = 0x5EED_A11C,
        noiseScale: Double = 1
    ) {
        self.scenario = scenario
        self.sampleRateHz = sampleRateHz > 0 ? sampleRateHz : 25
        self.axes = axes
        self.seed = seed
        self.noiseScale = noiseScale
        self.manualPose = .neutral
    }

    // MARK: - Timeline

    /// Simulated time of sample `index`.
    func time(ofSample index: Int) -> TimeInterval {
        Double(index) / sampleRateHz
    }

    /// Connection state at simulated time `t`.
    func connectionState(at t: TimeInterval) -> SensorConnectionState {
        switch scenario {
        case .unavailable:
            return .unavailable(.motionNotSupported)
        case .permissionDenied:
            return .unavailable(.notAuthorized)
        case .disconnectMidSession:
            if t >= 20 && t < 30 {
                return .waitingForHeadphones
            }
            return .connected
        case .manual, .steadyNeutral, .gradualForwardSlouch, .briefGlanceDown, .lateralTilt:
            return .connected
        }
    }

    /// Whether the scenario ever produces samples (and so needs a timer).
    var producesSamples: Bool {
        switch scenario {
        case .unavailable, .permissionDenied:
            return false
        case .manual, .steadyNeutral, .gradualForwardSlouch, .briefGlanceDown, .lateralTilt, .disconnectMidSession:
            return true
        }
    }

    /// Scripted pose at simulated time `t`, without noise.
    func basePose(at t: TimeInterval) -> MockHeadPose {
        switch scenario {
        case .manual:
            return manualPose
        case .steadyNeutral:
            // Slow left/right head turns; these must not register as tilt.
            return MockHeadPose(headingDegrees: 20 * sin(2 * Double.pi * t / 40))
        case .gradualForwardSlouch:
            let c = cycleTime(t, period: 120)
            let forward: Double
            if c < 20 {
                forward = 0
            } else if c < 30 {
                forward = 25 * Self.smoothstep(20, 30, c)
            } else if c < 90 {
                forward = 25
            } else if c < 95 {
                forward = 25 * (1 - Self.smoothstep(90, 95, c))
            } else {
                forward = 0
            }
            return MockHeadPose(forwardDegrees: forward)
        case .briefGlanceDown:
            let period = 15.0
            let cycleIndex = Int((max(t, 0) / period).rounded(.down))
            let c = cycleTime(t, period: period)
            let glanceStart = 8.0
            let glanceDuration = 3.0 + Double(cycleIndex % 3) // 3, 4, 5 s
            let ramp = 0.5
            let glanceEnd = glanceStart + glanceDuration
            let forward: Double
            if c < glanceStart || c >= glanceEnd {
                forward = 0
            } else if c < glanceStart + ramp {
                forward = 30 * Self.smoothstep(glanceStart, glanceStart + ramp, c)
            } else if c < glanceEnd - ramp {
                forward = 30
            } else {
                forward = 30 * (1 - Self.smoothstep(glanceEnd - ramp, glanceEnd, c))
            }
            return MockHeadPose(forwardDegrees: forward)
        case .lateralTilt:
            let c = cycleTime(t, period: 90)
            let lateral: Double
            if c < 15 {
                lateral = 0
            } else if c < 18 {
                lateral = 20 * Self.smoothstep(15, 18, c)
            } else if c < 63 {
                lateral = 20
            } else if c < 66 {
                lateral = 20 * (1 - Self.smoothstep(63, 66, c))
            } else {
                lateral = 0
            }
            return MockHeadPose(lateralDegrees: lateral)
        case .disconnectMidSession, .unavailable, .permissionDenied:
            return .neutral
        }
    }

    /// Base pose plus slow postural sway (smooth, deterministic).
    func smoothPose(at t: TimeInterval) -> MockHeadPose {
        var pose = basePose(at: t)
        guard noiseScale != 0 else { return pose }
        pose.forwardDegrees += noiseScale * sway(t, channel: 1, amplitude: 0.6)
        pose.lateralDegrees += noiseScale * sway(t, channel: 2, amplitude: 0.4)
        pose.headingDegrees += noiseScale * sway(t, channel: 3, amplitude: 1.5)
        return pose
    }

    /// Smooth pose plus small per-sample jitter (deterministic for a given `t`).
    func pose(at t: TimeInterval) -> MockHeadPose {
        var pose = smoothPose(at: t)
        guard noiseScale != 0 else { return pose }
        let key = Self.timeKey(t)
        pose.forwardDegrees += noiseScale * 0.15 * Self.unitNoise(seed: seed, key: key, channel: 11)
        pose.lateralDegrees += noiseScale * 0.15 * Self.unitNoise(seed: seed, key: key, channel: 12)
        pose.headingDegrees += noiseScale * 0.15 * Self.unitNoise(seed: seed, key: key, channel: 13)
        return pose
    }

    // MARK: - Samples

    /// The sample for `index`, timestamped `startTimestamp + index / sampleRateHz`.
    /// Nil while the scenario is not `.connected` at that time.
    func sample(index: Int, startTimestamp: TimeInterval) -> MotionSample? {
        let t = time(ofSample: index)
        guard connectionState(at: t) == .connected else { return nil }
        return sample(at: t, timestamp: startTimestamp + t)
    }

    /// The sample at simulated time `t`, ignoring connection state.
    func sample(at t: TimeInterval, timestamp: TimeInterval) -> MotionSample {
        let attitude = Self.attitude(for: pose(at: t), axes: axes)
        let gravity = Self.gravity(forAttitude: attitude)

        // Rotation rate in the head frame from the smooth pose (finite difference over one
        // sample period), plus a little gyro noise.
        let dt = 1 / sampleRateHz
        let previous = Self.attitude(for: smoothPose(at: t - dt), axes: axes)
        let current = Self.attitude(for: smoothPose(at: t), axes: axes)
        let delta = previous.conjugate * current
        let key = Self.timeKey(t)
        let gyroNoise = Vector3(
            x: Self.unitNoise(seed: seed, key: key, channel: 21),
            y: Self.unitNoise(seed: seed, key: key, channel: 22),
            z: Self.unitNoise(seed: seed, key: key, channel: 23)
        ) * (0.01 * noiseScale)
        let rotationRate = Self.rotationVector(of: delta) * (1 / dt) + gyroNoise

        let userAcceleration = Vector3(
            x: Self.unitNoise(seed: seed, key: key, channel: 31),
            y: Self.unitNoise(seed: seed, key: key, channel: 32),
            z: Self.unitNoise(seed: seed, key: key, channel: 33)
        ) * (0.005 * noiseScale)

        return MotionSample(
            timestamp: timestamp,
            attitude: attitude,
            gravity: gravity,
            rotationRate: rotationRate,
            userAcceleration: userAcceleration,
            sensorLocation: sensorLocation(at: t)
        )
    }

    func sensorLocation(at t: TimeInterval) -> SensorLocation {
        if scenario == .disconnectMidSession && t >= 30 {
            return .headphoneRight
        }
        return .headphoneLeft
    }

    // MARK: - Geometry

    /// Head attitude (head → world) for a pose under `axes`.
    static func attitude(for pose: MockHeadPose, axes: HeadAxisConvention) -> Quaternion {
        let degreesToRadians = Double.pi / 180
        let forwardPart: Vector3 = axes.forwardAxis.normalized * (pose.forwardDegrees * degreesToRadians)
        let lateralPart: Vector3 = axes.lateralAxis.normalized * (pose.lateralDegrees * degreesToRadians)
        let rotationVector: Vector3 = forwardPart + lateralPart
        let angle = rotationVector.length
        let tilt = angle > 0 ? Quaternion(axis: rotationVector, angleRadians: angle) : Quaternion.identity
        let heading = Quaternion(axis: Vector3(x: 0, y: 0, z: 1), angleRadians: pose.headingDegrees * degreesToRadians)
        return (heading * tilt).normalized
    }

    /// Gravity in the head frame (g) for a head → world attitude in a Z-up world.
    static func gravity(forAttitude attitude: Quaternion) -> Vector3 {
        attitude.conjugate.rotate(Vector3(x: 0, y: 0, z: -1))
    }

    /// Rotation vector (axis · angle, radians) of a unit quaternion, angle in [0, π].
    static func rotationVector(of quaternion: Quaternion) -> Vector3 {
        var q = quaternion.normalized
        if q.w < 0 {
            q = Quaternion(x: -q.x, y: -q.y, z: -q.z, w: -q.w)
        }
        let s = q.vector.length
        guard s > 1e-12 else { return q.vector * 2 }
        let angle = 2 * atan2(s, q.w)
        return q.vector * (angle / s)
    }

    static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        guard edge1 > edge0 else { return x >= edge1 ? 1 : 0 }
        let u = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return u * u * (3 - 2 * u)
    }

    // MARK: - Deterministic noise

    private func cycleTime(_ t: TimeInterval, period: Double) -> Double {
        let c = t.truncatingRemainder(dividingBy: period)
        return c < 0 ? c + period : c
    }

    /// Sum of two slow sinusoids with seeded phases; peak magnitude ≤ `amplitude`.
    private func sway(_ t: TimeInterval, channel: UInt64, amplitude: Double) -> Double {
        let phase1 = Double.pi * (Self.unitNoise(seed: seed, key: 0, channel: channel * 100 + 1) + 1)
        let phase2 = Double.pi * (Self.unitNoise(seed: seed, key: 0, channel: channel * 100 + 2) + 1)
        let a = sin(2 * Double.pi * 0.07 * t + phase1)
        let b = sin(2 * Double.pi * 0.19 * t + phase2)
        return amplitude * (0.6 * a + 0.4 * b)
    }

    /// Millisecond key for per-instant noise.
    static func timeKey(_ t: TimeInterval) -> Int64 {
        Int64((t * 1000).rounded())
    }

    /// SplitMix64 finalizer.
    static func mix(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Deterministic uniform noise in [−1, 1) for (seed, key, channel).
    static func unitNoise(seed: UInt64, key: Int64, channel: UInt64) -> Double {
        let hashed = mix(seed ^ mix(UInt64(bitPattern: key) &+ channel &* 0x632B_E59B_D9B4_E019))
        let unit = Double(hashed >> 11) / 9_007_199_254_740_992.0 // 2^53
        return unit * 2 - 1
    }
}
