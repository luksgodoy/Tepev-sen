import SwiftUI

/// The memo key.
///
/// It sits on its own, away from the transport, and does exactly one thing:
/// wake the machine and start a new tape. No confirmation, no picker, no
/// screen in between. The whole reason a field recorder still exists in a
/// world of phones is that this key is always in the same place and always
/// means the same thing.
struct MemoButton: View {
    @EnvironmentObject private var device: DeviceState
    @Environment(\.finish) private var finish

    var diameter: CGFloat = 48

    @State private var pressed = false

    var body: some View {
        let p = TE.palette(finish)
        let armed = device.machine.isRecording

        VStack(spacing: 5) {
            ZStack {
                // A recess, so the key cannot be pressed by a pocket.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [p.wellTop, p.wellBottom],
                            center: .center,
                            startRadius: diameter * 0.1,
                            endRadius: diameter * 0.55
                        )
                    )
                    .frame(width: diameter, height: diameter)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: pressed ? [p.capBottom, p.capBottom] : [p.capTop, p.capBottom],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: diameter * 0.78, height: diameter * 0.78)
                    .overlay {
                        Circle().strokeBorder(
                            LinearGradient(
                                colors: [p.edgeHighlight, p.edgeShadow],
                                startPoint: .top, endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                    }
                    .shadow(
                        color: .black.opacity(finish == .black ? 0.5 : 0.22),
                        radius: pressed ? 0.5 : 2.5,
                        y: pressed ? 0.3 : 1.8
                    )
                    .offset(y: pressed ? 1 : 0)

                Circle()
                    .fill(armed ? TE.rec : p.capLegend.opacity(0.55))
                    .frame(width: diameter * 0.18, height: diameter * 0.18)
                    .offset(y: pressed ? 1 : 0)
            }
            .animation(.easeOut(duration: 0.06), value: pressed)

            Legend(text: "memo", size: 8)
        }
        .contentShape(Rectangle())
        .accessibilityElement()
        .accessibilityLabel("memo")
        .accessibilityHint("starts a new recording immediately")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { device.memo() }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !pressed { pressed = true } }
                .onEnded { value in
                    pressed = false
                    let inside = abs(value.translation.width) < 36
                        && abs(value.translation.height) < 36
                    if inside { device.memo() }
                }
        )
    }
}

/// The mode key: walks the display through its five pages and does nothing
/// else. Pressing it can never lose you a take.
struct ModeButton: View {
    @EnvironmentObject private var device: DeviceState
    @Environment(\.finish) private var finish

    var body: some View {
        KeyCap(
            width: 54,
            height: 34,
            radius: 9,
            label: "mode",
            action: {
                device.cycleMode()
                device.flash(device.mode.legend)
            },
            longPressAction: { device.showingLibrary = true }
        ) {
            Legend(text: device.mode.legend, size: 9, color: TE.palette(finish).capLegend)
        }
    }
}
