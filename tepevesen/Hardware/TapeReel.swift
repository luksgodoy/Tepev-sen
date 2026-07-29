import SwiftUI

/// The reel.
///
/// The largest thing on the machine, because it is the most important thing on
/// the machine. It is the position display, the transport, the scrub wheel and
/// the pause key, and it is all four at once without a mode. Put a hand on it
/// and the tape stops; turn it and the tape moves; let go with a flick and it
/// keeps running until the bearings give up.
///
/// The look is built in three layers, and the order is the whole trick:
///
///   1. the well — fixed, with the pit's own shading and contact shadow
///   2. the face — turned metal, knurled rim, windows and hub; **this rotates**
///   3. the specular — anisotropic highlights; **this does not rotate**
///
/// Light does not spin with a disc. Rotating the highlight along with the metal
/// is what makes a drawn wheel read as a flat sticker; pinning it in place is
/// what makes this one read as a machined part catching a window.
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

            ZStack {
                well(side)
                positionRing(side)

                face(side)
                    .drawingGroup()
                    .rotationEffect(.degrees(motor.angle))
                    .shadow(
                        color: .black.opacity(finish == .black ? 0.75 : 0.30),
                        radius: side * 0.022, x: 0, y: side * 0.008
                    )

                specular(side)
                rimLight(side)
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

    // MARK: - 1. The well

    private func well(_ side: CGFloat) -> some View {
        let p = TE.palette(finish)
        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [p.wellBottom, p.wellTop],
                        center: .init(x: 0.5, y: 0.42),
                        startRadius: side * 0.30,
                        endRadius: side * 0.52
                    )
                )
                .frame(width: side, height: side)

            // Ambient occlusion where the pit wall meets the chassis: darkest
            // under the top lip, where light cannot reach.
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .black.opacity(finish == .black ? 0.75 : 0.42),
                            .black.opacity(0.05),
                            .white.opacity(finish == .black ? 0.06 : 0.22)
                        ],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: side * 0.035
                )
                .blur(radius: side * 0.018)
                .frame(width: side, height: side)
        }
    }

    // MARK: - 2. The position ring

    private func positionRing(_ side: CGFloat) -> some View {
        let recording = device.machine.isRecording
        let tint = recording ? TE.rec : TE.live
        return ZStack {
            // The unwound remainder, so the ring reads as a track rather than
            // a stray arc.
            Circle()
                .stroke(Color.black.opacity(0.22), lineWidth: side * 0.014)
                .frame(width: side * 0.945, height: side * 0.945)

            Circle()
                .trim(from: 0, to: max(0.0008, progress.clamped(to: 0...1)))
                .stroke(tint.opacity(0.95), style: StrokeStyle(lineWidth: side * 0.014, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: side * 0.945, height: side * 0.945)
                .shadow(color: tint.opacity(recording ? 0.55 : 0.20), radius: side * 0.012)
        }
    }

    // MARK: - 3. The face

    private func face(_ side: CGFloat) -> some View {
        let p = TE.palette(finish)
        let faceSide = side * 0.885

        return ZStack {
            // Base metal.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [p.capTop, p.capBottom],
                        center: .init(x: 0.38, y: 0.32),
                        startRadius: 0,
                        endRadius: faceSide * 0.72
                    )
                )
                .frame(width: faceSide, height: faceSide)

            // Turned finish: concentric grain, machining rings, knurled rim.
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2

                func ring(_ r: CGFloat, _ color: Color, _ width: CGFloat) {
                    ctx.stroke(
                        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                        with: .color(color),
                        lineWidth: width
                    )
                }

                // Lathe grain — deterministic, so it never shimmers between frames.
                var seed: UInt64 = 0xD1B54A32D192ED03
                var r = radius
                while r > radius * 0.06 {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    let n = Double((seed >> 33) & 0xFFFF) / 65535.0
                    ring(r, p.grain.opacity((n * 0.42 + 0.05) * p.grainOpacity), 0.5)
                    r -= 0.55 + CGFloat(n) * 0.85
                }

                // Four milled steps, the marks a tool leaves crossing the face.
                for f in [0.335, 0.505, 0.675, 0.815] as [CGFloat] {
                    ring(radius * f, Color.black.opacity(0.10), 0.9)
                    ring(radius * f + 0.8, Color.white.opacity(0.20), 0.7)
                }

                // Knurling: fine radial cuts around the rim, the part your
                // thumb would actually be gripping.
                let teeth = 168
                let inner = radius * 0.905
                let outer = radius * 0.972
                for i in 0..<teeth {
                    let a = Double(i) / Double(teeth) * 2 * .pi
                    let cosA = CGFloat(cos(a)), sinA = CGFloat(sin(a))
                    var path = Path()
                    path.move(to: CGPoint(x: c.x + cosA * inner, y: c.y + sinA * inner))
                    path.addLine(to: CGPoint(x: c.x + cosA * outer, y: c.y + sinA * outer))
                    // Alternating light and dark cuts read as a ridged surface.
                    let light = i % 2 == 0
                    ctx.stroke(
                        path,
                        with: .color(light
                            ? .white.opacity(finish == .black ? 0.16 : 0.42)
                            : .black.opacity(finish == .black ? 0.45 : 0.16)),
                        lineWidth: radius * 0.011
                    )
                }
            }
            .frame(width: faceSide, height: faceSide)
            .clipShape(Circle())

            // Chamfer at the outer edge.
            Circle()
                .strokeBorder(Color.black.opacity(0.30), lineWidth: faceSide * 0.008)
                .frame(width: faceSide, height: faceSide)

            windows(faceSide, palette: p)
            indexNotch(faceSide, palette: p)
            hub(faceSide, palette: p)
        }
        .frame(width: side, height: side)
    }

    /// Three windows through the reel, at 120°. They are what makes rotation
    /// legible at a glance — a plain disc spinning looks identical to a plain
    /// disc at rest.
    private func windows(_ faceSide: CGFloat, palette p: TE.Palette) -> some View {
        ForEach(0..<3, id: \.self) { i in
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.black.opacity(0.85), p.wellTop],
                            center: .init(x: 0.5, y: 0.35),
                            startRadius: 0,
                            endRadius: faceSide * 0.11
                        )
                    )
                // The cut edge: shadowed at the top lip, catching light at the
                // bottom of the bore.
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [.black.opacity(0.65), .white.opacity(0.30)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: faceSide * 0.006
                    )
            }
            .frame(width: faceSide * 0.185, height: faceSide * 0.185)
            .offset(y: -faceSide * 0.285)
            .rotationEffect(.degrees(Double(i) * 120 + 60))
        }
    }

    private func indexNotch(_ faceSide: CGFloat, palette p: TE.Palette) -> some View {
        Capsule()
            .fill(p.legend.opacity(0.9))
            .frame(width: faceSide * 0.014, height: faceSide * 0.055)
            .offset(y: -faceSide * 0.425)
    }

    /// A stepped hub: two machined levels down to the spindle bore.
    private func hub(_ faceSide: CGFloat, palette p: TE.Palette) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(colors: [p.capBottom, p.capTop], startPoint: .top, endPoint: .bottom)
                )
                .frame(width: faceSide * 0.30, height: faceSide * 0.30)
                .overlay {
                    Circle().strokeBorder(
                        LinearGradient(
                            colors: [.black.opacity(0.45), .white.opacity(0.25)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                }

            Circle()
                .fill(
                    LinearGradient(colors: [p.capTop, p.capBottom], startPoint: .top, endPoint: .bottom)
                )
                .frame(width: faceSide * 0.225, height: faceSide * 0.225)
                .shadow(color: .black.opacity(0.30), radius: faceSide * 0.008, y: faceSide * 0.004)

            // Spindle bore.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.black, p.wellTop],
                        center: .init(x: 0.5, y: 0.3),
                        startRadius: 0,
                        endRadius: faceSide * 0.045
                    )
                )
                .frame(width: faceSide * 0.075, height: faceSide * 0.075)
        }
    }

    // MARK: - 4. The light (fixed in place)

    /// Anisotropic specular: two opposing lobes, the signature of a surface
    /// turned on a lathe. Stays put while the reel spins under it.
    private func specular(_ side: CGFloat) -> some View {
        let faceSide = side * 0.885
        let strength = finish == .black ? 0.14 : 0.30

        return ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: .white.opacity(0), location: 0.00),
                            .init(color: .white.opacity(strength), location: 0.10),
                            .init(color: .white.opacity(0), location: 0.23),
                            .init(color: .white.opacity(0), location: 0.52),
                            .init(color: .white.opacity(strength * 0.8), location: 0.61),
                            .init(color: .white.opacity(0), location: 0.74),
                            .init(color: .white.opacity(0), location: 1.00)
                        ]),
                        center: .center,
                        angle: .degrees(-40)
                    )
                )
                .blendMode(.plusLighter)
                .blur(radius: side * 0.02)

            // The dark lobes between them, or the metal looks lit from everywhere.
            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: .black.opacity(0), location: 0.00),
                            .init(color: .black.opacity(0.16), location: 0.36),
                            .init(color: .black.opacity(0), location: 0.48),
                            .init(color: .black.opacity(0.16), location: 0.86),
                            .init(color: .black.opacity(0), location: 1.00)
                        ]),
                        center: .center,
                        angle: .degrees(-40)
                    )
                )
                .blendMode(.multiply)
                .blur(radius: side * 0.03)
        }
        .frame(width: faceSide, height: faceSide)
        .clipShape(Circle())
        .allowsHitTesting(false)
    }

    /// A bright hairline along the top edge and a dark one along the bottom —
    /// the chamfer catching the room.
    private func rimLight(_ side: CGFloat) -> some View {
        let faceSide = side * 0.885
        return Circle()
            .strokeBorder(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(finish == .black ? 0.35 : 0.70), location: 0.0),
                        .init(color: .white.opacity(0.05), location: 0.35),
                        .init(color: .black.opacity(0.12), location: 0.62),
                        .init(color: .black.opacity(0.38), location: 1.0)
                    ],
                    startPoint: .top, endPoint: .bottom
                ),
                lineWidth: 1.2
            )
            .frame(width: faceSide, height: faceSide)
            .allowsHitTesting(false)
    }

    // MARK: - Gesture

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
