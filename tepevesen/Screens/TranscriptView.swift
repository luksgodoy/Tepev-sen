import SwiftUI

/// transcribe.
///
/// Open it, choose your language, press transcribe. The machine says up front
/// whether the job can be done without the tape leaving the phone, because
/// that is the difference between a tool a doctor or a journalist can use and
/// one they cannot.
struct TranscriptView: View {
    @EnvironmentObject private var device: DeviceState
    @Environment(\.finish) private var finish
    @Environment(\.dismiss) private var dismiss

    @State private var locale: Locale = .current
    @State private var showingLanguages = false

    private var tape: Tape? { device.library.selected }

    var body: some View {
        NavigationStack {
            ZStack {
                BrushedMetal(finish: finish, grain: .linear).ignoresSafeArea()

                if let tape {
                    content(tape)
                } else {
                    Legend(text: "no tape loaded", size: 12)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("text")
                        .font(TE.Type_.wordmark(15))
                        .foregroundStyle(TE.palette(finish).legend)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Legend(text: "close", size: 11) }
                }
            }
            .sheet(isPresented: $showingLanguages) {
                LanguagePicker(selection: $locale).environment(\.finish, finish)
            }
        }
        .onAppear {
            if let id = tape?.transcript?.localeIdentifier {
                locale = Locale(identifier: id)
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ tape: Tape) -> some View {
        let p = TE.palette(finish)

        VStack(spacing: 0) {
            header(tape)

            Rectangle().fill(p.legend.opacity(0.18)).frame(height: 0.5)

            if let transcript = tape.transcript {
                segments(transcript, tape: tape)
            } else if case .running(let progress) = device.transcriber.state {
                running(progress)
            } else {
                idle(tape)
            }
        }
    }

    private func header(_ tape: Tape) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(tape.name)
                    .font(TE.Type_.legend(14))
                    .foregroundStyle(TE.palette(finish).capLegend)
                Spacer()
                Text(TimeCode.short(tape.duration))
                    .font(TE.Type_.mono(12))
                    .foregroundStyle(TE.palette(finish).legend)
            }

            WaveformView(
                peaks: tape.peaks,
                progress: tape.duration > 0 ? device.machine.position / tape.duration : 0,
                marks: tape.marks.map { tape.duration > 0 ? $0 / tape.duration : 0 },
                accent: TE.palette(finish).capLegend,
                onScrub: { t in device.machine.seek(to: t * tape.duration) }
            )
            .frame(height: 40)

            HStack(spacing: 10) {
                Button { showingLanguages = true } label: {
                    HStack(spacing: 5) {
                        Legend(text: Transcriber.name(for: locale), size: 11)
                        Legend(text: "▾", size: 11)
                    }
                }

                Spacer()

                Legend(
                    text: Transcriber.canRunOnDevice(locale) ? "on-device" : "needs network",
                    size: 10
                )
            }
        }
        .padding(16)
    }

    private func idle(_ tape: Tape) -> some View {
        VStack(spacing: 16) {
            Spacer()

            if case .denied = device.transcriber.state {
                Legend(text: "speech recognition is off in settings", size: 11)
            } else if case .failed(let reason) = device.transcriber.state {
                Legend(text: reason, size: 11)
            }

            Button {
                device.transcribeSelected(locale: locale)
            } label: {
                Text("transcribe")
                    .font(TE.Type_.legend(13))
                    .tracking(1.0)
                    .foregroundStyle(TE.palette(finish).capLegend)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 13)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        TE.palette(finish).capTop,
                                        TE.palette(finish).capBottom
                                    ],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                    }
                    .milledEdge(finish, cornerRadius: 10)
            }
            .buttonStyle(.plain)

            if !Transcriber.canRunOnDevice(locale) {
                Legend(
                    text: "this language is recognized by apple's servers.",
                    size: 9
                )
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            }

            Spacer()
        }
    }

    private func running(_ progress: Double) -> some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView(value: progress)
                .tint(TE.palette(finish).capLegend)
                .frame(width: 180)
            Legend(text: "\(Int(progress * 100))%", size: 11)
            if !device.transcriber.partial.isEmpty {
                Text(device.transcriber.partial)
                    .font(TE.Type_.legend(12))
                    .foregroundStyle(TE.palette(finish).legend)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(.horizontal, 30)
            }
            Button { device.transcriber.cancel() } label: {
                Legend(text: "cancel", size: 11)
            }
            Spacer()
        }
    }

    private func segments(_ transcript: Transcript, tape: Tape) -> some View {
        let p = TE.palette(finish)
        let here = device.machine.position

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Words as a flowing paragraph, each one a seek point. A
                // transcript you cannot jump from is just a document.
                FlowLayout(spacing: 4, lineSpacing: 7) {
                    ForEach(transcript.segments) { segment in
                        let active = segment.start <= here
                            && here < segment.start + max(segment.duration, 0.2)
                        Text(segment.text)
                            .font(TE.Type_.legend(15))
                            .foregroundStyle(
                                active ? p.capLegend : p.legend.opacity(
                                    // Low-confidence words are visibly less
                                    // certain rather than silently wrong.
                                    0.45 + Double(segment.confidence) * 0.5
                                )
                            )
                            .padding(.horizontal, active ? 3 : 0)
                            .background {
                                if active {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(TE.rec.opacity(0.22))
                                }
                            }
                            .onTapGesture {
                                device.machine.seek(to: segment.start)
                                device.machine.play()
                            }
                    }
                }
                .padding(16)

                HStack(spacing: 12) {
                    Legend(text: transcript.localeName, size: 9)
                    Legend(text: transcript.onDevice ? "on-device" : "network", size: 9)
                    Spacer()
                    ShareLink(item: transcript.text) { Legend(text: "share", size: 10) }
                    Button {
                        device.library.setTranscript(nil, for: tape.id)
                    } label: {
                        Legend(text: "clear", size: 10)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }
}

// MARK: - Language picker

private struct LanguagePicker: View {
    @Binding var selection: Locale
    @Environment(\.finish) private var finish
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var locales: [Locale] {
        let all = Transcriber.supportedLocales
        guard !query.isEmpty else { return all }
        return all.filter { Transcriber.name(for: $0).contains(query.lowercased()) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BrushedMetal(finish: finish, grain: .linear).ignoresSafeArea()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(locales, id: \.identifier) { locale in
                            HStack {
                                Legend(text: Transcriber.name(for: locale), size: 13)
                                Spacer()
                                if Transcriber.canRunOnDevice(locale) {
                                    Legend(text: "on-device", size: 9)
                                }
                                if locale.identifier == selection.identifier {
                                    Circle().fill(TE.rec).frame(width: 6, height: 6)
                                }
                            }
                            .padding(.vertical, 13)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selection = locale
                                dismiss()
                            }
                            Rectangle()
                                .fill(TE.palette(finish).legend.opacity(0.15))
                                .frame(height: 0.5)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .searchable(text: $query, prompt: "language")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("language")
                        .font(TE.Type_.wordmark(15))
                        .foregroundStyle(TE.palette(finish).legend)
                }
            }
        }
    }
}

// MARK: - Flow layout

/// Wraps word chips across lines. Used so every recognized word stays its own
/// tappable seek point without turning the transcript into a table.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + lineHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
