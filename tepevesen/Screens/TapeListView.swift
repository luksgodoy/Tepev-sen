import SwiftUI

/// The tapes.
///
/// The one screen the machine itself does not have, because 64 × 32 dots
/// cannot hold a list. It stays deliberately plain: the machine is the
/// interface, and this is a drawer you open to find a tape and then close.
struct TapeListView: View {
    @EnvironmentObject private var device: DeviceState
    @Environment(\.finish) private var finish
    @Environment(\.dismiss) private var dismiss

    @State private var renaming: Tape?
    @State private var draftName = ""
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                BrushedMetal(finish: finish, grain: .linear).ignoresSafeArea()

                if device.library.tapes.isEmpty {
                    empty
                } else {
                    list
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("tapes")
                        .font(TE.Type_.wordmark(15))
                        .foregroundStyle(TE.palette(finish).legend)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Legend(text: "setup", size: 11)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Legend(text: "close", size: 11)
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView().environment(\.finish, finish)
            }
            .alert("rename", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )) {
                TextField("name", text: $draftName)
                Button("cancel", role: .cancel) { renaming = nil }
                Button("save") {
                    if let tape = renaming { device.library.rename(tape, to: draftName) }
                    renaming = nil
                }
            }
        }
    }

    // MARK: List

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(device.library.tapes) { tape in
                    row(tape)
                    Rectangle()
                        .fill(TE.palette(finish).legend.opacity(0.18))
                        .frame(height: 0.5)
                }

                footer
            }
            .padding(.horizontal, 16)
        }
    }

    private func row(_ tape: Tape) -> some View {
        let selected = device.library.selectedID == tape.id
        let p = TE.palette(finish)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if tape.starred {
                    Circle().fill(TE.rec).frame(width: 5, height: 5)
                        .offset(y: -2)
                }
                Text(tape.name)
                    .font(TE.Type_.legend(14))
                    .foregroundStyle(selected ? p.capLegend : p.legend)
                Spacer()
                Text(TimeCode.short(tape.duration))
                    .font(TE.Type_.mono(12))
                    .foregroundStyle(p.legend)
            }

            WaveformView(
                peaks: tape.peaks,
                progress: selected ? playProgress : 0,
                marks: tape.marks.map { tape.duration > 0 ? $0 / tape.duration : 0 },
                accent: selected ? p.capLegend : p.legend.opacity(0.75)
            )
            .frame(height: 34)

            HStack(spacing: 10) {
                Legend(text: tape.formatLine, size: 9)
                if let transcript = tape.transcript {
                    Legend(
                        text: transcript.onDevice ? "text · on-device" : "text",
                        size: 9
                    )
                }
                Spacer()
                Legend(text: relative(tape.createdAt), size: 9)
            }
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture {
            device.loadForPlayback(tape)
            device.haptics.detent()
            dismiss()
        }
        .contextMenu {
            Button("rename") {
                draftName = tape.name
                renaming = tape
            }
            Button(tape.starred ? "unstar" : "star") {
                device.library.toggleStar(tape)
            }
            Button("transcribe") {
                device.loadForPlayback(tape)
                device.showingTranscript = true
                dismiss()
            }
            ShareLink(item: device.library.url(for: tape)) {
                Text("share wav")
            }
            Divider()
            Button("delete", role: .destructive) { device.library.delete(tape) }
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Legend(
                text: "\(device.library.tapes.count) tapes · \(TapeLibrary.formatBytes(device.library.usedBytes))",
                size: 10
            )
            Legend(
                text: "\(TapeLibrary.formatBytes(device.library.freeBytes)) free",
                size: 10
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Circle()
                .strokeBorder(TE.palette(finish).legend.opacity(0.4), lineWidth: 1.5)
                .frame(width: 46, height: 46)
            Legend(text: "no tapes yet", size: 12)
            Legend(text: "press memo", size: 10)
        }
    }

    private var playProgress: Double {
        guard device.machine.duration > 0 else { return 0 }
        return device.machine.position / device.machine.duration
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date()).lowercased()
    }
}
