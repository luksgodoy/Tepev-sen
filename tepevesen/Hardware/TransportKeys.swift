import SwiftUI

/// A raised control cap.
///
/// Every button on the machine is the same object at a different size: a
/// milled cap that sits above the chassis, travels about a millimetre, and
/// carries its symbol cut into the top face rather than printed beside it.
struct KeyCap<Symbol: View>: View {
    @Environment(\.finish) private var finish

    var width: CGFloat?
    var height: CGFloat = TE.Metric.capHeight
    var radius: CGFloat = TE.Metric.capRadius
    /// The single accent, used only by record.
    var accent: Color?
    var isLit: Bool = false
    var label: String?
    var action: () -> Void
    var longPressAction: (() -> Void)?
    @ViewBuilder var symbol: () -> Symbol

    @State private var pressed = false

    var body: some View {
        let p = TE.palette(finish)

        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: pressed
                                ? [p.capBottom, p.capBottom]
                                : [p.capTop, p.capBottom],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [p.edgeHighlight, p.edgeShadow],
                                    startPoint: .top, endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(
                        color: .black.opacity(finish == .black ? 0.55 : 0.25),
                        radius: pressed ? 1 : 4,
                        x: 0,
                        y: pressed ? 0.5 : 3
                    )

                symbol()
                    .foregroundStyle(isLit ? (accent ?? TE.live) : p.capLegend)
            }
            .frame(width: width, height: height)
            .offset(y: pressed ? 1.2 : 0)
            .animation(.easeOut(duration: 0.06), value: pressed)

            if let label {
                Legend(text: label, size: 8)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement()
        .accessibilityLabel(label ?? "key")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !pressed { pressed = true } }
                .onEnded { value in
                    pressed = false
                    // Released off the cap: the key did not close, exactly like
                    // sliding off a physical button.
                    let inside = abs(value.translation.width) < 40
                        && abs(value.translation.height) < 40
                    if inside { action() }
                }
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.55)
                .onEnded { _ in longPressAction?() }
        )
    }
}

/// rec · play · stop, in the order they sit on the hardware.
struct TransportKeys: View {
    @EnvironmentObject private var device: DeviceState
    @Environment(\.finish) private var finish

    var body: some View {
        HStack(spacing: TE.Metric.gutter) {
            KeyCap(
                accent: TE.rec,
                isLit: device.machine.isRecording,
                label: "rec",
                action: { device.recordButton() },
                longPressAction: { device.mark() }
            ) {
                Circle()
                    .fill(device.machine.isRecording ? TE.rec : TE.palette(finish).capLegend)
                    .frame(width: 15, height: 15)
                    .opacity(recordBlink)
            }

            KeyCap(
                isLit: isPlaying,
                label: "play",
                action: { device.playButton() }
            ) {
                PlayGlyph()
                    .frame(width: 15, height: 17)
            }

            KeyCap(
                isLit: false,
                label: "stop",
                action: { device.stopButton() },
                longPressAction: { device.nextTape() }
            ) {
                if case .paused = device.machine.transport {
                    PauseGlyph().frame(width: 14, height: 15)
                } else {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .frame(width: 14, height: 14)
                }
            }
        }
    }

    private var isPlaying: Bool {
        if case .playing = device.machine.transport { return true }
        return false
    }

    /// Recording blinks; on hold it goes steady-dim. You can tell across a room.
    private var recordBlink: Double {
        switch device.machine.transport {
        case .recording:  return 1.0
        case .recordHold: return 0.35
        default:          return 1.0
        }
    }
}

// MARK: - Glyphs

struct PlayGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

struct PauseGlyph: View {
    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1, style: .continuous).frame(width: 5)
            RoundedRectangle(cornerRadius: 1, style: .continuous).frame(width: 5)
        }
    }
}
