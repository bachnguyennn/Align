import Foundation

/// A repeating tick source for `SampleWatchdog`. Injected so tests can fire ticks by hand.
@MainActor
protocol WatchdogTimer: AnyObject {
    var isRunning: Bool { get }
    /// Starts calling `tick` every `interval` seconds, replacing any earlier schedule.
    func start(interval: TimeInterval, tick: @escaping @MainActor () -> Void)
    func stop()
}

/// `WatchdogTimer` backed by a main-actor `Task` that sleeps between ticks. Exists only while
/// started, so nothing runs when the watchdog is disarmed.
@MainActor
final class TaskWatchdogTimer: WatchdogTimer {
    private var task: Task<Void, Never>?

    var isRunning: Bool { task != nil }

    func start(interval: TimeInterval, tick: @escaping @MainActor () -> Void) {
        stop()
        let nanoseconds = UInt64(max(interval, 0.05) * 1_000_000_000)
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                } catch {
                    return
                }
                // Ends the loop if the timer was released without stop().
                guard self != nil, !Task.isCancelled else { return }
                tick()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

/// Notices when a connected sensor stops delivering samples (D-017 (c)).
///
/// `PostureMonitor` only sees a gap when the next sample arrives, so without this a silent
/// stream would leave an episode open and the UI showing the last tilt. The controller calls
/// `sampleArrived` for every sample while streaming and connected; the watchdog then ticks and,
/// once no sample has arrived for more than `maxSampleGap + margin` seconds (measured with the
/// injected clock at arrival, not with sample timestamps), calls `onStall` once and disarms.
/// The next sample re-arms it. `disarm()` stops the timer (disconnect, stream stop).
@MainActor
final class SampleWatchdog {
    typealias Clock = () -> TimeInterval

    /// Extra time on top of `maxSampleGap` before a stall is reported, to absorb delivery jitter.
    static let margin: TimeInterval = 0.5
    /// How often the armed watchdog checks the time since the last sample.
    static let tickInterval: TimeInterval = 0.25

    var onStall: (@MainActor () -> Void)?

    private let timer: any WatchdogTimer
    private let clock: Clock
    private var lastArrival: TimeInterval?
    private var maxGap: TimeInterval = 1

    /// - Parameters:
    ///   - timer: tick source; `TaskWatchdogTimer` when nil.
    ///   - clock: monotonic seconds; `ProcessInfo.systemUptime` when nil (SystemBootTime 35F9.1).
    init(timer: (any WatchdogTimer)? = nil, clock: Clock? = nil) {
        self.timer = timer ?? TaskWatchdogTimer()
        if let clock {
            self.clock = clock
        } else {
            self.clock = { ProcessInfo.processInfo.systemUptime }
        }
    }

    /// Whether the watchdog is waiting for the next sample (its timer is running).
    var isArmed: Bool { timer.isRunning }

    func sampleArrived(maxSampleGap: TimeInterval) {
        lastArrival = clock()
        maxGap = maxSampleGap
        if !timer.isRunning {
            timer.start(interval: SampleWatchdog.tickInterval) { [weak self] in
                self?.check()
            }
        }
    }

    func disarm() {
        lastArrival = nil
        timer.stop()
    }

    /// Called on every tick (internal so tests can drive it directly).
    func check() {
        guard let last = lastArrival else {
            timer.stop()
            return
        }
        if clock() - last > maxGap + SampleWatchdog.margin {
            disarm()
            onStall?()
        }
    }
}
