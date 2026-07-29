import SwiftUI

/// The connector edge, reduced to what is true.
///
/// Two sockets, neither of them a choice: the input, which is always the
/// built-in mic, and the output, which follows whatever you are listening on.
/// A row of sockets you cannot select would be decoration, and there is no
/// decoration on this machine — so the ones that remain are readouts, and they
/// are readouts of things that actually change.
struct JackStrip: View {
    @EnvironmentObject private var device: DeviceState

    var body: some View {
        HStack(spacing: 0) {
            Socket(
                legend: "mic",
                detail: device.jacks.inputName,
                filled: device.jacks.inputAvailable,
                lit: true,
                diameter: 17
            )
            .frame(maxWidth: .infinity)
            .onTapGesture {
                device.flash(device.jacks.inputAvailable ? "built-in mic" : "no input")
            }

            Socket(
                legend: "out",
                detail: device.jacks.outputName,
                filled: device.jacks.outputIsExternal,
                lit: false,
                diameter: 22
            )
            .frame(maxWidth: .infinity)
            .onTapGesture { device.flash(device.jacks.outputName) }
        }
    }
}

private struct Socket: View {
    @Environment(\.finish) private var finish

    let legend: String
    let detail: String
    /// Something is in it.
    let filled: Bool
    /// This is the live path.
    let lit: Bool
    let diameter: CGFloat

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

                if filled {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [p.capTop, p.capBottom],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: diameter * 0.46, height: diameter * 0.46)
                }

                if lit {
                    Circle()
                        .strokeBorder(TE.live.opacity(0.85), lineWidth: 1.4)
                        .frame(width: diameter + 6, height: diameter + 6)
                }
            }
            .frame(height: 28)

            Legend(text: legend, size: 7, tracking: 0.6)
        }
        .contentShape(Rectangle())
        .accessibilityElement()
        .accessibilityLabel("\(legend) jack")
        .accessibilityValue(detail)
    }
}
