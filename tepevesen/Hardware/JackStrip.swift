import SwiftUI

/// The connector edge.
///
/// The hardware puts three two-way 3.5 mm jacks and a 1/4" output along one
/// edge, and the reason it can get away with that many is that every one of
/// them is visibly either plugged in or not. This strip keeps that promise: a
/// socket is filled when the route behind it genuinely exists, and tapping a
/// two-way socket patches the input to it. Nothing here is decorative.
struct JackStrip: View {
    @EnvironmentObject private var device: DeviceState

    var body: some View {
        HStack(spacing: 0) {
            ForEach(device.jacks.jacks) { jack in
                Socket(jack: jack)
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        guard jack.id.isTwoWay else {
                            device.flash(jack.detail.isEmpty ? "out" : jack.detail)
                            return
                        }
                        guard jack.connected else {
                            device.flash("nothing in \(jack.id.legend)")
                            return
                        }
                        device.jacks.select(jack.id)
                        device.haptics.detent()
                        device.flash(jack.detail.isEmpty ? jack.id.legend : jack.detail)
                    }
            }
        }
    }
}

private struct Socket: View {
    @Environment(\.finish) private var finish
    let jack: JackStatus

    private var diameter: CGFloat { jack.id == .monitorOut ? 22 : 17 }

    var body: some View {
        let p = TE.palette(finish)

        VStack(spacing: 4) {
            ZStack {
                // The barrel: a hole in the chassis, dark all the way down.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.black, p.wellTop],
                            center: .center,
                            startRadius: 0,
                            endRadius: diameter * 0.55
                        )
                    )
                    .frame(width: diameter, height: diameter)
                    .overlay {
                        Circle().strokeBorder(
                            LinearGradient(
                                colors: [p.edgeShadow, p.edgeHighlight],
                                startPoint: .top, endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                    }

                // The tip of a plug, when there is one.
                if jack.connected {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [p.capTop, p.capBottom],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: diameter * 0.46, height: diameter * 0.46)
                }

                // The selected input carries the one lit ring on the machine.
                if jack.selected {
                    Circle()
                        .strokeBorder(TE.live.opacity(0.85), lineWidth: 1.4)
                        .frame(width: diameter + 6, height: diameter + 6)
                }
            }
            .frame(height: 28)

            Legend(text: jack.id.legend, size: 7, tracking: 0.6)
        }
        .contentShape(Rectangle())
        .accessibilityElement()
        .accessibilityLabel("\(jack.id.legend) jack")
        .accessibilityValue(
            jack.connected
                ? (jack.detail.isEmpty ? "connected" : jack.detail)
                : "empty"
        )
    }
}
