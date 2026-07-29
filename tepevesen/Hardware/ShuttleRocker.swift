import SwiftUI

/// The side rocker.
///
/// Press the top edge to run forward, the bottom edge to run back. It is a
/// single piece of metal on a pivot, so there is no ambiguity about what it is
/// or which way it goes — and it is on the side, where a thumb already is
/// when the machine is in your palm.
///
/// Hold and it winds up: 2× for the first second, 4× to two and a half, 8×
/// after that. Release and it drops instantly back to where the tape was.
struct ShuttleRocker: View {
    @EnvironmentObject private var device: DeviceState
    @Environment(\.finish) private var finish

    var width: CGFloat = 30
    var height: CGFloat = 132

    @State private var side: Side?
    @State private var pressedAt: Date?
    @State private var ticker: Timer?

    private enum Side { case forward, back }

    var body: some View {
        let p = TE.palette(finish)

        ZStack {
            // The pivot slot the rocker sits in.
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [p.wellTop, p.wellBottom],
                        startPoint: .leading, endPoint: .trailing
                    )
                )

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [p.capTop, p.capBottom],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .padding(2.5)
                .overlay {
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [p.edgeHighlight, p.edgeShadow],
                                startPoint: .top, endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                        .padding(2.5)
                }
                // The whole cap tilts on its pivot rather than sliding.
                .rotation3DEffect(
                    .degrees(side == .forward ? -7 : (side == .back ? 7 : 0)),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: .center,
                    perspective: 0.6
                )
                .animation(.easeOut(duration: 0.07), value: side)

            VStack {
                ChevronPair(up: true)
                    .frame(width: width * 0.42, height: width * 0.42)
                    .foregroundStyle(side == .forward ? TE.live : p.capLegend)
                Spacer()
                // A single milled rib marks the pivot line.
                Capsule()
                    .fill(p.edgeShadow)
                    .frame(width: width * 0.5, height: 1)
                Spacer()
                ChevronPair(up: false)
                    .frame(width: width * 0.42, height: width * 0.42)
                    .foregroundStyle(side == .back ? TE.live : p.capLegend)
            }
            .padding(.vertical, height * 0.10)
        }
        .frame(width: width, height: height)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard side == nil else { return }
                    let forward = value.startLocation.y < height / 2
                    begin(forward ? .forward : .back)
                }
                .onEnded { _ in end() }
        )
        .accessibilityElement()
        .accessibilityLabel("shuttle")
        .accessibilityHint("press the top to run forward, the bottom to rewind")
        .accessibilityAdjustableAction { direction in
            let step: Double = direction == .increment ? 5 : -5
            device.machine.seek(to: device.machine.position + step)
        }
        .onDisappear { end() }
    }

    private func begin(_ s: Side) {
        side = s
        pressedAt = Date()
        device.shuttleBegan(forward: s == .forward)

        ticker?.invalidate()
        // Added to the main run loop below, so this fires on the main thread.
        let t = Timer(timeInterval: 0.15, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard let pressedAt, let side else { return }
                device.shuttleHeld(
                    forward: side == .forward,
                    seconds: Date().timeIntervalSince(pressedAt)
                )
            }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func end() {
        guard side != nil else { return }
        ticker?.invalidate()
        ticker = nil
        side = nil
        pressedAt = nil
        device.shuttleEnded()
    }
}

private struct ChevronPair: View {
    var up: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { p in
                for i in 0..<2 {
                    let offset = CGFloat(i) * h * 0.46
                    let top = up ? offset : h - offset
                    let bottom = up ? offset + h * 0.42 : h - offset - h * 0.42
                    p.move(to: CGPoint(x: 0, y: bottom))
                    p.addLine(to: CGPoint(x: w / 2, y: top))
                    p.addLine(to: CGPoint(x: w, y: bottom))
                }
            }
            .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
    }
}
