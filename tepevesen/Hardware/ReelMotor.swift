import SwiftUI
import QuartzCore

/// The brushless motor behind the reel.
///
/// On the hardware the reel is not a dial that happens to spin — it is
/// mechanically the tape. It turns whenever the tape moves, at the speed the
/// tape is moving, forwards or backwards, and when you put a hand on it the
/// tape stops. Everything below exists to make that one relationship true.
@MainActor
final class ReelMotor: NSObject, ObservableObject {

    /// At 1× the reel makes half a turn per second — one full revolution is
    /// two seconds of tape. Slow enough to read, fast enough to feel driven.
    static let revolutionsPerSecondAt1x: Double = 0.5
    static let degreesPerSecondAt1x: Double = revolutionsPerSecondAt1x * 360

    /// Current angle in degrees. Unbounded, so it can be handed straight to a
    /// rotation effect without ever snapping across the 360 seam.
    @Published private(set) var angle: Double = 0
    /// True while a finger is on the reel.
    @Published private(set) var isHeld = false

    /// Signed tape speed the transport wants the reel to run at.
    var rateProvider: () -> Double = { 0 }
    /// Called on every detent crossed while the reel is turned by hand.
    var onDetent: (() -> Void)?
    /// Signed tape speed the hand is currently imposing. Keeps firing through
    /// the freewheel after release, so a flick keeps scanning.
    var onHandRate: ((Double) -> Void)?
    /// The reel has come to rest and the transport can take it back.
    var onSettle: (() -> Void)?

    /// Twenty-four detents per revolution — the cogging you feel through a
    /// good motor, and fine enough to trim a word.
    private static let detentsPerRevolution: Double = 24
    private static let degreesPerDetent: Double = 360 / detentsPerRevolution

    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var handVelocity: Double = 0      // degrees / second
    private var detentAccumulator: Double = 0
    private var freewheel: Double = 0         // degrees / second, decaying

    func start() {
        guard link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(step(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    // MARK: Hand

    func grab() {
        isHeld = true
        handVelocity = 0
        freewheel = 0
        detentAccumulator = 0
    }

    /// Turn the reel by hand. `deltaDegrees` is signed; positive is forward.
    func turn(by deltaDegrees: Double, over dt: Double) {
        angle += deltaDegrees
        if dt > 0 {
            // Smooth the velocity, or every jitter in a fingertip becomes a
            // scratch transient.
            let instantaneous = deltaDegrees / dt
            handVelocity = handVelocity * 0.6 + instantaneous * 0.4
        }
        onHandRate?(handVelocity / Self.degreesPerSecondAt1x)

        detentAccumulator += abs(deltaDegrees)
        while detentAccumulator >= Self.degreesPerDetent {
            detentAccumulator -= Self.degreesPerDetent
            onDetent?()
        }
    }

    /// Let go. `carryMomentum` keeps the reel freewheeling from the throw,
    /// which is how a heavy reel behaves and how a flick-to-scan should feel.
    func release(carryMomentum: Bool) {
        isHeld = false
        freewheel = carryMomentum ? handVelocity : 0
        handVelocity = 0
        if abs(freewheel) <= 1 {
            freewheel = 0
            onHandRate?(0)
            onSettle?()
        }
    }

    // MARK: Tick

    @objc private func step(_ link: CADisplayLink) {
        let now = link.timestamp
        defer { lastTimestamp = now }
        guard lastTimestamp > 0 else { return }
        let dt = min(now - lastTimestamp, 1.0 / 15.0)
        guard dt > 0, !isHeld else { return }

        if abs(freewheel) > 1 {
            angle += freewheel * dt
            // Bearing drag. Enough to settle in about a second.
            freewheel *= pow(0.12, dt)
            onHandRate?(freewheel / Self.degreesPerSecondAt1x)
            if abs(freewheel) <= 1 {
                freewheel = 0
                onHandRate?(0)
                onSettle?()
            }
            return
        }

        let rate = rateProvider()
        guard rate != 0 else { return }
        angle += rate * Self.degreesPerSecondAt1x * dt
    }
}
