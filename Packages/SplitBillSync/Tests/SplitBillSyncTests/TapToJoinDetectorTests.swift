import Foundation
import Testing
@testable import SplitBillSync

@Suite("TapToJoinDetector")
struct TapToJoinDetectorTests {

    private let close = 0.25 // a natural phone-tap distance
    private let far = TapToJoinDetector.rearmDistance + 0.3
    private let dwell = TapToJoinDetector.dwellSeconds
    private let hz = 10.0

    /// Feeds samples at 10 Hz starting from `start`; returns (fired, lastOutput).
    private func feed(
        _ detector: inout TapToJoinDetector,
        distances: [Double],
        from start: TimeInterval
    ) -> (fired: Bool, last: TapToJoinDetector.Output) {
        var fired = false
        var last = TapToJoinDetector.Output(progress: 0, didFire: false)
        for (index, distance) in distances.enumerated() {
            last = detector.process(distance: distance, at: start + Double(index) / hz)
            if last.didFire { fired = true }
        }
        return (fired, last)
    }

    @Test("Fires on sustained close distance")
    func firesOnSustainedProximity() {
        var detector = TapToJoinDetector()
        let samples = Array(repeating: close, count: Int(dwell * hz) + 3)
        #expect(feed(&detector, distances: samples, from: 0).fired)
    }

    @Test("Fires despite jitter spikes above the threshold (the ±10 cm reality)")
    func firesDespiteJitter() {
        var detector = TapToJoinDetector()
        // Every 4th sample spikes to 0.55 m — median filtering must absorb
        // it; the old hard-reset dwell never fired on this stream.
        let samples = (0..<(Int(dwell * hz) + 10)).map { index in
            index % 4 == 3 ? 0.55 : close
        }
        #expect(feed(&detector, distances: samples, from: 0).fired)
    }

    @Test("Does NOT fire on a genuine brief approach-and-leave")
    func briefApproachDoesNotFire() {
        var detector = TapToJoinDetector()
        // Close for only 40% of the dwell, then walk away.
        let approach = Array(repeating: close, count: Int(dwell * hz * 0.4))
        let leave = Array(repeating: far, count: Int(dwell * hz * 2))
        let result = feed(&detector, distances: approach + leave, from: 0)
        #expect(!result.fired)
        // Progress fully decayed after the separation.
        #expect(result.last.progress == 0)
    }

    @Test("Progress decays gradually on separation instead of snapping to zero")
    func progressDecays() {
        var detector = TapToJoinDetector()
        let approach = Array(repeating: close, count: Int(dwell * hz * 0.6))
        _ = feed(&detector, distances: approach, from: 0)
        let start = Double(approach.count) / hz
        // One far sample: the median (still mostly close) keeps progress;
        // it must not crash to zero. It may even tick up briefly — that IS
        // the noise immunity.
        let afterOne = detector.process(distance: far, at: start)
        #expect(afterOne.progress > 0.4)
        // Once the median flips to far (half the window), decay is
        // monotonic and smooth down to zero.
        let flipTicks = TapToJoinDetector.smoothingWindow / 2 + 1
        var previous = 1.0
        for tick in 1...(flipTicks + Int(dwell * hz)) {
            let output = detector.process(distance: far, at: start + Double(tick) / hz)
            if tick > flipTicks {
                #expect(output.progress <= previous)
            }
            previous = output.progress
        }
        #expect(previous == 0)
    }

    @Test("Does not double-fire while the devices stay close")
    func noDoubleFire() {
        var detector = TapToJoinDetector()
        let samples = Array(repeating: close, count: Int(dwell * hz) + 3)
        #expect(feed(&detector, distances: samples, from: 0).fired)
        // Staying close: latched at 1, no more fires.
        let more = Array(repeating: close, count: 50)
        let result = feed(&detector, distances: more, from: dwell + 1)
        #expect(!result.fired)
        #expect(result.last.progress == 1)
    }

    @Test("Re-arms only after separating past the rearm distance")
    func rearmsAfterSeparation() {
        var detector = TapToJoinDetector()
        _ = feed(&detector, distances: Array(repeating: close, count: Int(dwell * hz) + 3), from: 0)

        // Jitter above trigger but below rearm: still latched.
        let jitter = Array(repeating: TapToJoinDetector.triggerDistance + 0.05, count: 20)
        let jittered = feed(&detector, distances: jitter, from: dwell + 1)
        #expect(!jittered.fired)
        #expect(jittered.last.progress == 1)

        // Real separation unlatches (needs enough samples to move the median)…
        let separated = feed(&detector, distances: Array(repeating: far, count: 10), from: dwell + 4)
        #expect(separated.last.progress == 0)

        // …and a fresh approach fires a second time.
        let second = feed(
            &detector,
            distances: Array(repeating: close, count: Int(dwell * hz) + 6),
            from: dwell + 6
        )
        #expect(second.fired)
    }

    @Test("reset() returns to a fresh state")
    func resetClearsEverything() {
        var detector = TapToJoinDetector()
        #expect(feed(&detector, distances: Array(repeating: close, count: Int(dwell * hz) + 3), from: 0).fired)
        detector.reset()
        let after = detector.process(distance: close, at: 100)
        #expect(!after.didFire)
        #expect(after.progress < 0.1)
    }

    @Test("Constants stay in a sane deliberate-gesture range")
    func constantsSanity() {
        #expect(TapToJoinDetector.triggerDistance >= 0.3)
        #expect(TapToJoinDetector.triggerDistance <= 0.6)
        #expect(TapToJoinDetector.dwellSeconds >= 0.5)
        #expect(TapToJoinDetector.dwellSeconds <= 2.0)
        #expect(TapToJoinDetector.rearmDistance > TapToJoinDetector.triggerDistance)
        #expect(TapToJoinDetector.smoothingWindow >= 3)
        #expect(TapToJoinDetector.decayMultiplier >= 1)
    }
}
