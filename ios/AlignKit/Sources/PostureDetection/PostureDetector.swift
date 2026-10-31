import Foundation
import AlignCore

/// Posture state machine, applied to the smoothed tilt of each processed sample.
/// Mirrors `PostureDetector` in `analytics/align-tools`.
///
/// - neutral → deviating(d) when some direction's component reaches its threshold; `d` is the
///   direction with the largest component/threshold ratio. The direction is then locked for the
///   rest of that deviation (no mid-episode switching, which avoids flicker).
/// - deviating → sustainedTilt once `sustainedDuration` has elapsed since onset.
/// - deviating/sustainedTilt → neutral once d's component drops below `threshold − hysteresis`.
///   If another direction is over its own threshold on that sample, a new deviation starts there.
/// - Leaving sustainedTilt (or `interrupt`) produces a `PostureEpisode`.
public struct PostureDetector: Sendable {
    public enum Phase: Sendable {
        case neutral
        case deviating
        case sustained
    }

    public struct Output: Equatable, Sendable {
        public var state: PostureState
        /// True on the single update where the deviation became sustained.
        public var becameSustained: Bool
        public var completedEpisode: PostureEpisode?

        public init(state: PostureState, becameSustained: Bool, completedEpisode: PostureEpisode?) {
            self.state = state
            self.becameSustained = becameSustained
            self.completedEpisode = completedEpisode
        }
    }

    /// Thresholds at or below this are treated as this value (avoids division by zero).
    public static let minimumThresholdDegrees: Double = 1e-6
    /// Evaluation order for direction precedence (the first wins on an exact ratio tie).
    public static let directionOrder: [TiltDirection] = [.forward, .backward, .left, .right]

    public private(set) var phase: Phase = .neutral
    public private(set) var direction: TiltDirection?
    /// Onset of the current deviation.
    public private(set) var since: TimeInterval?
    /// Largest component (degrees, in `direction`) seen during the current deviation.
    public private(set) var peakDegrees: Double = 0
    public private(set) var reminderTriggered = false

    public init() {}

    public var state: PostureState {
        switch phase {
        case .neutral:
            return .neutral
        case .deviating:
            guard let d = direction, let s = since else { return .neutral }
            return .deviating(direction: d, since: s)
        case .sustained:
            guard let d = direction, let s = since else { return .neutral }
            return .sustainedTilt(direction: d, since: s)
        }
    }

    /// Signed tilt in `direction` (degrees): positive means tilted that way.
    public static func component(_ tilt: TiltEstimate, _ direction: TiltDirection) -> Double {
        switch direction {
        case .forward:
            return tilt.forwardDegrees
        case .backward:
            return -tilt.forwardDegrees
        case .right:
            return tilt.lateralDegrees
        case .left:
            return -tilt.lateralDegrees
        }
    }

    public static func threshold(_ direction: TiltDirection, _ configuration: PostureConfiguration) -> Double {
        let t: Double
        switch direction {
        case .forward:
            t = configuration.forwardThresholdDegrees
        case .backward:
            t = configuration.backwardThresholdDegrees
        case .left, .right:
            t = configuration.lateralThresholdDegrees
        }
        return max(t, minimumThresholdDegrees)
    }

    /// The direction whose component/threshold ratio is largest among those at or over threshold.
    public static func dominantDirection(_ tilt: TiltEstimate, configuration: PostureConfiguration) -> TiltDirection? {
        var best: TiltDirection?
        var bestRatio = 0.0
        for candidate in directionOrder {
            let ratio = component(tilt, candidate) / threshold(candidate, configuration)
            if ratio >= 1.0 && ratio > bestRatio {
                best = candidate
                bestRatio = ratio
            }
        }
        return best
    }

    public mutating func reset() {
        phase = .neutral
        direction = nil
        since = nil
        peakDegrees = 0
        reminderTriggered = false
    }

    public mutating func markReminderTriggered() {
        reminderTriggered = true
    }

    /// Closes a sustained episode (if any) at `timestamp` and resets to neutral.
    public mutating func interrupt(at timestamp: TimeInterval) -> PostureEpisode? {
        let episode = phase == .sustained ? makeEpisode(end: timestamp) : nil
        reset()
        return episode
    }

    public mutating func update(_ tilt: TiltEstimate, configuration: PostureConfiguration) -> Output {
        let t = tilt.timestamp
        var completed: PostureEpisode?
        var becameSustained = false

        if phase != .neutral {
            if let d = direction, let start = since {
                let value = PostureDetector.component(tilt, d)
                let release = PostureDetector.threshold(d, configuration) - configuration.hysteresisDegrees
                if value < release {
                    if phase == .sustained {
                        completed = makeEpisode(end: t)
                    }
                    reset()
                } else {
                    if value > peakDegrees {
                        peakDegrees = value
                    }
                    let elapsed = t - start + PostureDetectionConstants.timeEpsilon
                    if phase == .deviating && elapsed >= configuration.sustainedDuration {
                        phase = .sustained
                        becameSustained = true
                    }
                }
            } else {
                reset()
            }
        }

        if phase == .neutral {
            if let d = PostureDetector.dominantDirection(tilt, configuration: configuration) {
                phase = .deviating
                direction = d
                since = t
                peakDegrees = PostureDetector.component(tilt, d)
                reminderTriggered = false
                if configuration.sustainedDuration <= PostureDetectionConstants.timeEpsilon {
                    phase = .sustained
                    becameSustained = true
                }
            }
        }

        return Output(state: state, becameSustained: becameSustained, completedEpisode: completed)
    }

    private func makeEpisode(end: TimeInterval) -> PostureEpisode? {
        guard let d = direction, let start = since else { return nil }
        return PostureEpisode(
            direction: d,
            startTimestamp: start,
            endTimestamp: end,
            peakDeviationDegrees: peakDegrees,
            reminderTriggered: reminderTriggered
        )
    }
}
