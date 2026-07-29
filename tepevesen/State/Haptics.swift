import UIKit
import CoreHaptics

/// The machine's mechanical feel.
///
/// A recorder you operate without looking has to answer through your fingers.
/// Transport keys click, the reel cogs against detents, and while the motor is
/// running there is a low continuous hum under everything — the same three
/// sensations the hardware gives you, delivered by the only actuator a phone
/// has.
@MainActor
final class Haptics {

    enum Key { case play, stop, record }

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)

    private var engine: CHHapticEngine?
    private var motorHum: CHHapticAdvancedPatternPlayer?
    private var humRunning = false

    var enabled = true

    init() {
        light.prepare()
        rigid.prepare()
        heavy.prepare()
        prepareEngine()
    }

    private func prepareEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.playsHapticsOnly = true
        engine?.isAutoShutdownEnabled = true
        engine?.resetHandler = { [weak self] in
            try? self?.engine?.start()
        }
        try? engine?.start()
    }

    // MARK: Discrete

    func bump(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard enabled else { return }
        switch style {
        case .light: light.impactOccurred()
        case .rigid: rigid.impactOccurred()
        case .heavy: heavy.impactOccurred()
        default: light.impactOccurred()
        }
    }

    /// A transport key travelling down onto its stop.
    func transport(_ key: Key) {
        guard enabled else { return }
        switch key {
        case .play:   rigid.impactOccurred(intensity: 0.9)
        case .stop:   heavy.impactOccurred(intensity: 0.8)
        case .record: heavy.impactOccurred(intensity: 1.0)
        }
    }

    /// One detent of the reel.
    func detent() {
        guard enabled else { return }
        light.impactOccurred(intensity: 0.55)
    }

    // MARK: Motor hum

    /// Start the continuous hum, at an intensity proportional to tape speed.
    func startMotor(intensity: Float = 0.22) {
        guard enabled, let engine, motorHum == nil else { return }
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.15)
            ],
            relativeTime: 0,
            duration: 60 * 60
        )
        guard let pattern = try? CHHapticPattern(events: [event], parameters: []),
              let player = try? engine.makeAdvancedPlayer(with: pattern)
        else { return }
        player.loopEnabled = true
        motorHum = player
        try? player.start(atTime: CHHapticTimeImmediate)
        humRunning = true
    }

    func setMotor(intensity: Float) {
        guard humRunning, let motorHum else { return }
        let parameter = CHHapticDynamicParameter(
            parameterID: .hapticIntensityControl,
            value: max(0, min(1, intensity)),
            relativeTime: 0
        )
        try? motorHum.sendParameters([parameter], atTime: CHHapticTimeImmediate)
    }

    func stopMotor() {
        try? motorHum?.stop(atTime: CHHapticTimeImmediate)
        motorHum = nil
        humRunning = false
    }
}
