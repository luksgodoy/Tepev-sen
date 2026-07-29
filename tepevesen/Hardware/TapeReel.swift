import SwiftUI

/// The reel.
///
/// The largest thing on the machine, because it is the most important thing on
/// the machine. It is the position display, the transport, the scrub wheel and
/// the pause key, and it is all four at once without a mode. Put a hand on it
/// and the tape stops; turn it and the tape moves; let go with a flick and it
/// keeps running until the bearings give up.
struct TapeReel: View {
    @EnvironmentObject private var device: DeviceState
    @ObservedObject var motor: ReelMotor
    @Environment(\.finish) private var finish

    /// Progress around the rim, 0…1.
    var progress: Double

    @State private var lastAngle: Double?
    @State private var lastTime: Date = .now
    @State private var velocity: Double = 0

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let p = TE.palette(finish)

            ZStack {
                // The well the reel sits in.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [p.wellTop, p.wellBottom],
                            center: .center,
                            startRadius: side * 0.30,
                            endRadius: side * 0.52
                        )
                    )
                    .frame(width: side, height: side)

                // Position ring — the tape wound so far, drawn in the well so
                // it stays still while the reel turns.
                Circle()
                    .trim(from: 0, to: max(0.0005, progress.clamped(to: 0...1)))
                    .stroke(
                        (device.machine.isRecording ? TE.rec : TE.live).opacity(0.9),
                        style: StrokeStyle(lineWidth: side * 0.018, lineCap: .butt)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: side * 0.955, height: side * 0.955)

                // The reel itself.
                reelFace(side: side, palette: p)
                    .rotationEffect(.degrees(motor.angle))
                    .shadow(
                        color: .black.opacity(finish == .black ? 0.7 : 0.35),
                        radius: side * 0.02, x: 0, y: side * 0.006
                    )
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Circle())
            .gesture(drag(center: center, radius: side / 2))
            .accessibilityElement()
            .accessibilityLabel("tape reel")
            .accessibilityValue(TimeCode.short(device.machine.position))
            .accessibilityHint("drag around to scrub. hold to stop the tape.")
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 1.0 : -1.0
                device.machine.seek(to: device.machine.position + step)
            }
        }
    }

    // MARK: Face

    private func reelFace(side: CGFloat, palette p: TE.Palette) -> some View {
        let faceSide = side * 0.88

        return ZStack {
            BrushedMetal(finish: finish, grain: .radial, cornerRadius: faceSide / 2)
                .frame(width: faceSide, height: faceSide)
                .clipShape(Circle())
                .overlay {
                    Circle().strokeBorder(
                        LinearGradient(
                            colors: [p.edgeHighlight, p.edgeShadow],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                }

            // Three windows through the reel, at 120°. They are what makes
            // rotation legible at a glance — a plain disc spinning looks
            // identical to a plain disc at rest.
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(p.wellTop)
                    .frame(width: faceSide * 0.20, height: faceSide * 0.20)
                    .overlay {
                        Circle().strokeBorder(p.edgeShadow, lineWidth: 0.8)
                    }
                    .offset(y: -faceSide * 0.28)
                    .rotationEffect(.degrees(Double(i) * 120))
            }

            // Index mark: one milled notch at the rim.
            Capsule()
                .fill(p.legend.opacity(0.85))
                .frame(width: faceSide * 0.012, height: faceSide * 0.06)
                .offset(y: -faceSide * 0.44)

            // Hub and spindle.
            Circle()
                .fill(
                    LinearGradient(
                        colors: [p.capTop, p.capBottom],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: faceSide * 0.26, height: faceSide * 0.26)
                .overlay { Circle().strokeBorder(p.edgeShadow, lineWidth: 0.8) }
                .shadow(color: .black.opacity(0.25), radius: faceSide * 0.01, y: faceSide * 0.004)

            Circle()
                .fill(p.wellTop)
                .frame(width: faceSide * 0.075, height: faceSide * 0.075)
        }
        .frame(width: side, height: side)
    }

    // MARK: Gesture

    private func drag(center: CGPoint, radius: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let dx = value.location.x - center.x
                let dy = value.location.y - center.y
                let r = sqrt(dx * dx + dy * dy)
                // The hub is not a control surface. Too close to the centre
                // and a millimetre of finger travel is a whole revolution.
                guard r > radius * 0.22 else { return }

                let angle = atan2(dy, dx) * 180 / .pi
                let now = Date()

                guard let previous = lastAngle else {
                    lastAngle = angle
                    lastTime = now
                    velocity = 0
                    device.reelGrabbed()
                    return
                }

                var delta = angle - previous
                if delta > 180 { delta -= 360 }
                if delta < -180 { delta += 360 }

                let dt = max(now.timeIntervalSince(lastTime), 1.0 / 240.0)
                lastAngle = angle
                lastTime = now
                velocity = velocity * 0.6 + (delta / dt) * 0.4

                device.reelTurned(deltaDegrees: delta, dt: dt)
            }
            .onEnded { _ in
                let stale = Date().timeIntervalSince(lastTime) > 0.09
                // A throw carries; a finger that stopped before lifting does not.
                let flick = !stale && abs(velocity) > 220
                lastAngle = nil
                velocity = 0
                device.reelReleased(flick: flick)
            }
    }
}
