import Foundation
import AlignCore

/// Guided-nod axis calibration (D-017, docs/agents/sensor-contracts.md "Axis calibration").
/// Mirrors `AxisCalibrationService` in `analytics/align-tools`.
///
/// After `begin()`, each smoothed gravity sample is turned into the head rotation vector relative
/// to the baseline gravity `g0`, exactly as the tilt estimate does (`head = -rotationVector(g0, g)`).
/// It is perpendicular to `g0`, so heading never contributes. Samples whose rotation is at least
/// `axisCalibrationMotionFloorDegrees` are kept.
///
/// The attempt finishes on the first sample at which the head is back within
/// `axisCalibrationReturnDegrees` of neutral after a peak of at least
/// `axisCalibrationMinimumNodDegrees`, or once `axisCalibrationDuration` has elapsed since the
/// first sample. Without such a peak it fails with `.noNodDetected`. Otherwise the forward axis
/// line is the principal axis of the kept rotation vectors in the baseline plane, using the basis
/// `e1` = configured forward axis projected onto the plane and `e2` = normalized(`g0 × e1`): angle
/// `0.5·atan2(2·Sab, Saa − Sbb)` from `e1`, which lies in (−90°, 90°], so the learned forward axis
/// has a non-negative dot product with `e1` (a nod down or up both work). Lateral =
/// normalized(`g0 × forward`); for the defaults with `g0 = (0, 0, −1)` that is forward (−1, 0, 0),
/// lateral (0, 1, 0). Rejected with `.inconsistentMotion` if the angle exceeds
/// `axisCalibrationMaxYawDegrees` or the off-axis ratio Σ|v·lateral| ÷ Σ|v·forward| exceeds
/// `axisCalibrationMaxOffAxisRatio`.
public struct AxisCalibrationService: Sendable {
    public enum Step: Equatable, Sendable {
        case inProgress(progress: Double)
        case succeeded(HeadAxisConvention)
        case failed(AxisCalibrationFailure)
    }

    /// A fitted axis line: `axes` (nil if the basis is degenerate), its signed angle from the
    /// configured forward axis in the baseline plane (positive toward `g0 × e1`), and the off-axis
    /// ratio over the `samplesUsed` rotation vectors.
    public struct Fit: Equatable, Sendable {
        public var axes: HeadAxisConvention?
        public var yawDegrees: Double
        public var offAxisRatio: Double
        public var samplesUsed: Int

        public init(axes: HeadAxisConvention?, yawDegrees: Double, offAxisRatio: Double, samplesUsed: Int) {
            self.axes = axes
            self.yawDegrees = yawDegrees
            self.offAxisRatio = offAxisRatio
            self.samplesUsed = samplesUsed
        }
    }

    public private(set) var isActive = false
    public private(set) var startTimestamp: TimeInterval?
    public private(set) var lastTimestamp: TimeInterval?
    /// Largest rotation from neutral seen in the current attempt (degrees).
    public private(set) var peakDegrees: Double = 0
    private var rotations: [Vector3] = []

    public init() {}

    public mutating func begin() {
        isActive = true
        startTimestamp = nil
        lastTimestamp = nil
        peakDegrees = 0
        rotations = []
    }

    public mutating func cancel() {
        isActive = false
        startTimestamp = nil
        lastTimestamp = nil
        peakDegrees = 0
        rotations = []
    }

    /// 0...1 while active; 0 before the first sample.
    public func progress(duration: TimeInterval) -> Double {
        guard isActive, let start = startTimestamp, let last = lastTimestamp else {
            return 0
        }
        if duration <= 0 {
            return 1
        }
        let p = (last - start) / duration
        return min(1, max(0, p))
    }

    /// Motion floor actually used: the constant, at most half the minimum nod.
    public static func floorDegrees(minimumNodDegrees: Double) -> Double {
        min(PostureDetectionConstants.axisCalibrationMotionFloorDegrees, 0.5 * minimumNodDegrees)
    }

    /// Return-to-neutral level actually used: the constant, at most half the minimum nod.
    public static func returnDegrees(minimumNodDegrees: Double) -> Double {
        min(PostureDetectionConstants.axisCalibrationReturnDegrees, 0.5 * minimumNodDegrees)
    }

    public mutating func add(
        gravity: Vector3,
        timestamp: TimeInterval,
        baselineGravity: Vector3,
        configuration: PostureConfiguration
    ) -> Step {
        if startTimestamp == nil {
            startTimestamp = timestamp
        }
        lastTimestamp = timestamp
        let g0 = baselineGravity.normalized
        let head = -TiltEstimator.rotationVector(from: g0, to: gravity)
        let angle = head.length * PostureDetectionConstants.degreesPerRadian
        let minimumNod = configuration.axisCalibrationMinimumNodDegrees
        if angle >= AxisCalibrationService.floorDegrees(minimumNodDegrees: minimumNod) {
            rotations.append(head)
        }
        if angle > peakDegrees {
            peakDegrees = angle
        }
        let validPeak = peakDegrees >= minimumNod
        let returned = validPeak && angle <= AxisCalibrationService.returnDegrees(minimumNodDegrees: minimumNod)
        let elapsed = timestamp - (startTimestamp ?? timestamp)
        let duration = configuration.axisCalibrationDuration
        if !returned && elapsed + PostureDetectionConstants.timeEpsilon < duration {
            return .inProgress(progress: progress(duration: duration))
        }

        let used = rotations
        cancel()
        if !validPeak || used.isEmpty {
            return .failed(.noNodDetected)
        }
        let fit = AxisCalibrationService.fit(used, baseline: g0, reference: configuration.axes)
        guard let axes = fit.axes,
              abs(fit.yawDegrees) <= configuration.axisCalibrationMaxYawDegrees,
              fit.offAxisRatio <= configuration.axisCalibrationMaxOffAxisRatio else {
            return .failed(.inconsistentMotion)
        }
        return .succeeded(axes)
    }

    /// The baseline-plane basis: `e1` = projected reference forward axis, `e2` = normalized(`g0 × e1`).
    private static func basis(baseline: Vector3, reference: HeadAxisConvention) -> (e1: Vector3, e2: Vector3) {
        let e1 = TiltEstimator.baselinePlaneAxis(reference.forwardAxis, baseline: baseline)
        let e2 = baseline.cross(e1).normalized
        return (e1, e2)
    }

    /// Fits the forward axis line (principal axis) to non-empty `rotations` (head rotation
    /// vectors, radians) around unit `baseline` gravity.
    public static func fit(_ rotations: [Vector3], baseline: Vector3, reference: HeadAxisConvention) -> Fit {
        let b = basis(baseline: baseline, reference: reference)
        let e1 = b.e1
        let e2 = b.e2
        if e2.length == 0 {
            return Fit(axes: nil, yawDegrees: 90, offAxisRatio: .infinity, samplesUsed: rotations.count)
        }
        var saa = 0.0
        var sbb = 0.0
        var sab = 0.0
        for v in rotations {
            let a = v.dot(e1)
            let c = v.dot(e2)
            saa += a * a
            sbb += c * c
            sab += a * c
        }
        let angle = 0.5 * atan2(2.0 * sab, saa - sbb)
        let forward = (e1 * cos(angle) + e2 * sin(angle)).normalized
        let lateral = baseline.cross(forward).normalized
        var along = 0.0
        var across = 0.0
        for v in rotations {
            along += abs(v.dot(forward))
            across += abs(v.dot(lateral))
        }
        let ratio = along > 0 ? across / along : Double.infinity
        return Fit(
            axes: HeadAxisConvention(forwardAxis: forward, lateralAxis: lateral),
            yawDegrees: angle * PostureDetectionConstants.degreesPerRadian,
            offAxisRatio: ratio,
            samplesUsed: rotations.count
        )
    }

    /// Signed angle (degrees) of `forwardAxis` from the reference forward axis, both projected onto
    /// the baseline plane; positive toward `g0 × e1` (the default lateral axis), i.e. a right-hand
    /// rotation about the baseline gravity (down).
    public static func signedYawDegrees(
        forwardAxis: Vector3,
        baselineGravity: Vector3,
        reference: HeadAxisConvention
    ) -> Double {
        let g0 = baselineGravity.normalized
        let b = basis(baseline: g0, reference: reference)
        let f = TiltEstimator.baselinePlaneAxis(forwardAxis, baseline: g0)
        return atan2(f.dot(b.e2), f.dot(b.e1)) * PostureDetectionConstants.degreesPerRadian
    }
}
