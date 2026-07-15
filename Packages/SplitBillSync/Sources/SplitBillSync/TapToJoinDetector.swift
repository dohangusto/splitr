import Foundation

/// Pure "tap to join" gesture detection: distance samples in, gesture out.
/// No NearbyInteraction import — fully unit-testable without UWB hardware.
///
/// Built for real UWB behavior, where ±10 cm jitter between consecutive
/// samples is normal:
/// - samples pass through a median filter (`smoothingWindow`) so a single
///   spike can't lie about the distance, and
/// - progress *accumulates* while close and *decays* while far instead of
///   hard-resetting, so one noisy reading doesn't wipe the dwell. The UI
///   ring reads the same value, easing instead of snapping.
///
/// After firing, the detector latches and won't fire again until the
/// devices separate past `rearmDistance` (hysteresis against jitter).
public struct TapToJoinDetector: Sendable {

    // MARK: Tuning constants (adjust on-device here, nowhere else)

    /// Smoothed distance must be under this to build progress. Meters.
    /// Generous enough that a natural phone-tap (~20–30 cm) with ±10 cm
    /// jitter still reads as "close" after smoothing.
    public static let triggerDistance: Double = 0.40
    /// Continuous-close time to fire (progress rise time). Seconds.
    public static let dwellSeconds: TimeInterval = 1.0
    /// After firing, devices must separate past this before re-arming.
    /// Meters — deliberately above `triggerDistance`.
    public static let rearmDistance: Double = 0.60
    /// Median filter width, in samples (UWB updates arrive at several Hz).
    public static let smoothingWindow = 5
    /// Progress decays this many times faster than it rises, so a genuine
    /// approach-and-leave drains quickly but a noisy dip barely dents it.
    public static let decayMultiplier: Double = 2.0

    public struct Output: Equatable, Sendable {
        /// 0...1 — accumulated dwell (drives the UI ring).
        public let progress: Double
        /// True on exactly one sample per approach.
        public let didFire: Bool
    }

    private var window: [Double] = []
    private var progressValue: Double = 0
    private var lastTime: TimeInterval?
    private var isLatched = false

    public init() {}

    /// Feed one distance sample (meters) with its timestamp.
    public mutating func process(distance: Double, at time: TimeInterval) -> Output {
        window.append(distance)
        if window.count > Self.smoothingWindow {
            window.removeFirst()
        }
        let smoothed = window.sorted()[window.count / 2]

        let dt = lastTime.map { max(0, time - $0) } ?? 0
        lastTime = time

        if isLatched {
            if smoothed > Self.rearmDistance {
                isLatched = false
                progressValue = 0
                return Output(progress: 0, didFire: false)
            }
            return Output(progress: 1, didFire: false)
        }

        if smoothed < Self.triggerDistance {
            progressValue = min(1, progressValue + dt / Self.dwellSeconds)
        } else {
            progressValue = max(0, progressValue - dt * Self.decayMultiplier / Self.dwellSeconds)
        }

        if progressValue >= 1 {
            isLatched = true
            return Output(progress: 1, didFire: true)
        }
        return Output(progress: progressValue, didFire: false)
    }

    /// Back to a fresh, unarmed state.
    public mutating func reset() {
        window = []
        progressValue = 0
        lastTime = nil
        isLatched = false
    }
}
