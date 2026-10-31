import Foundation

/// Measures the delivered sample rate over a sliding time window, for diagnostics.
///
/// Feed it `MotionSample.timestamp` values in arrival order. Only samples whose timestamp is
/// within `window` seconds of the newest sample are kept. A timestamp that goes backwards
/// (for example a new streaming session) clears the history before it is recorded.
public struct SampleRateMeter: Sendable {
    /// Length of the sliding window in seconds.
    public let window: TimeInterval

    /// Timestamps inside the window, oldest first.
    private var timestamps: [TimeInterval] = []

    public init(window: TimeInterval = 5) {
        self.window = window > 0 ? window : 5
    }

    public mutating func record(_ timestamp: TimeInterval) {
        guard timestamp.isFinite else { return }
        if let last = timestamps.last, timestamp < last {
            timestamps.removeAll(keepingCapacity: true)
        }
        timestamps.append(timestamp)
        let cutoff = timestamp - window
        var firstKept = 0
        while firstKept < timestamps.count && timestamps[firstKept] < cutoff {
            firstKept += 1
        }
        if firstKept > 0 {
            timestamps.removeFirst(firstKept)
        }
    }

    /// Clears all recorded samples.
    public mutating func reset() {
        timestamps.removeAll()
    }

    /// Number of samples currently inside the window.
    public var sampleCount: Int { timestamps.count }

    /// Average rate over the window: (samples − 1) / time spanned. Nil with fewer than two
    /// samples or when all samples share one timestamp.
    public var samplesPerSecond: Double? {
        guard timestamps.count >= 2, let first = timestamps.first, let last = timestamps.last else {
            return nil
        }
        let span = last - first
        guard span > 0 else { return nil }
        return Double(timestamps.count - 1) / span
    }

    /// Largest interval between consecutive samples inside the window. Nil with fewer than
    /// two samples.
    public var largestGap: TimeInterval? {
        guard timestamps.count >= 2 else { return nil }
        var largest: TimeInterval = 0
        for index in 1..<timestamps.count {
            let gap = timestamps[index] - timestamps[index - 1]
            if gap > largest {
                largest = gap
            }
        }
        return largest
    }
}
