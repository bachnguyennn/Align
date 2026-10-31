import Foundation

/// Shared numeric constants of the posture pipeline. The executable specification is the Java
/// reference in `analytics/align-tools`; keep both in sync.
public enum PostureDetectionConstants {
    /// Tolerance used when comparing elapsed times with durations, so that e.g. `32.05 - 2.05`
    /// (= 29.999999999999996 in IEEE doubles) counts as 30 s.
    public static let timeEpsilon: TimeInterval = 1e-9

    /// Tolerance of the decimation schedule (`PostureConfiguration.maxProcessingRateHz`).
    public static let decimationEpsilon: TimeInterval = 1e-6

    public static let degreesPerRadian: Double = 180.0 / Double.pi
}
