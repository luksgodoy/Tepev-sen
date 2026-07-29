import SwiftUI

/// setup.
///
/// The things that would be a jumper, a switch or a sticker on the chassis.
/// Deliberately short — every setting here is one the hardware would also have
/// had to physically make room for.
struct SettingsView: View {
    @EnvironmentObject private var device: DeviceState
    @Environment(\.finish) private var finish
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                BrushedMetal(finish: finish, grain: .linear).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        section("finish") {
                            HStack(spacing: 10) {
                                ForEach(Finish.allCases) { option in
                                    FinishChip(option: option, selected: device.finish == option) {
                                        device.finish = option
                                        device.haptics.detent()
                                    }
                                }
                            }
                        }

                        section("tape") {
                            toggle("pitch follows speed", isOn: Binding(
                                get: { !device.machine.pitchLock },
                                set: { device.machine.pitchLock = !$0 }
                            ))
                            note("on tape, running faster raises the pitch. turn this off and speed changes leave the pitch where it was.")
                        }

                        section("input") {
                            toggle("monitor input", isOn: Binding(
                                get: { device.machine.inputMonitoring },
                                set: { device.machine.inputMonitoring = $0 }
                            ))
                            note("hear what you are recording through the selected output. use headphones — a speaker will feed back.")
                        }

                        section("feel") {
                            toggle("haptics", isOn: Binding(
                                get: { device.haptics.enabled },
                                set: {
                                    device.haptics.enabled = $0
                                    if !$0 { device.haptics.stopMotor() }
                                }
                            ))
                        }

                        section("format") {
                            row("requested", "\(Int(AudioMachine.preferredSampleRate / 1000))k · \(AudioMachine.bitDepth) bit")
                            row("actual", actualFormat)
                            row("input", device.jacks.jacks.first { $0.selected }?.detail ?? "—")
                            row("output", device.jacks.outputName)
                            note("the machine records at whatever the phone will actually give it, and tells you which that was.")
                        }

                        section("storage") {
                            row("tapes", "\(device.library.tapes.count)")
                            row("used", TapeLibrary.formatBytes(device.library.usedBytes))
                            row("free", TapeLibrary.formatBytes(device.library.freeBytes))
                            row(
                                "remaining",
                                TimeCode.short(device.library.remainingSeconds(
                                    sampleRate: max(device.machine.actualSampleRate, 44_100),
                                    channels: max(device.machine.actualChannels, 1)
                                ))
                            )
                            note("tapes are plain 24-bit wav files in the app's documents folder. open the files app to copy them off.")
                        }

                        if let error = device.machine.lastError {
                            section("last error") { note(error) }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Legend(text: "tepevësen", size: 11)
                            Legend(text: "a field recorder, after the tp–7 by teenage engineering.", size: 9)
                            Legend(text: "an independent tribute. not affiliated with or endorsed by teenage engineering.", size: 9)
                        }
                        .padding(.top, 10)
                        .padding(.bottom, 40)
                    }
                    .padding(20)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("setup")
                        .font(TE.Type_.wordmark(15))
                        .foregroundStyle(TE.palette(finish).legend)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Legend(text: "close", size: 11) }
                }
            }
        }
    }

    private var actualFormat: String {
        let rate = device.machine.actualSampleRate
        guard rate > 0 else { return "—" }
        let k = rate / 1000
        let rateText = k == k.rounded() ? "\(Int(k))k" : String(format: "%.1fk", k)
        return "\(rateText) · \(device.machine.actualChannels >= 2 ? "stereo" : "mono")"
    }

    // MARK: Pieces

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Legend(text: title, size: 10, tracking: 1.6)
            content()
        }
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Legend(text: title, size: 13, color: TE.palette(finish).capLegend, tracking: 0.4)
        }
        .tint(TE.rec)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Legend(text: label, size: 12)
            Spacer()
            Text(value)
                .font(TE.Type_.mono(12))
                .foregroundStyle(TE.palette(finish).capLegend)
        }
    }

    private func note(_ text: String) -> some View {
        Legend(text: text, size: 9, tracking: 0.3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct FinishChip: View {
    @Environment(\.finish) private var current
    let option: Finish
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                BrushedMetal(finish: option, grain: .linear, cornerRadius: 8)
                    .frame(width: 62, height: 40)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                selected ? TE.rec : TE.palette(current).legend.opacity(0.35),
                                lineWidth: selected ? 1.6 : 0.8
                            )
                    }
                Legend(text: option.title, size: 9)
            }
        }
        .buttonStyle(.plain)
    }
}
