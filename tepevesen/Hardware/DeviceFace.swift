import SwiftUI

/// The machine, laid out.
///
/// The hardware is 96 × 68 mm and lands in a palm sideways. A phone is the
/// same object turned upright, so the layout is turned with it — but the
/// relationships are kept exactly: connectors on the edge you plug into, the
/// display where your eyes land first, the reel occupying the middle and most
/// of the face, the transport under your thumb at the bottom, the rocker on
/// the side where a thumb already rests, and memo alone in the top corner so
/// it is never pressed by accident and never hunted for.
struct DeviceFace: View {
    @EnvironmentObject private var device: DeviceState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let finish = device.finish

        ZStack {
            BrushedMetal(finish: finish, grain: .linear, cornerRadius: 0)
                .ignoresSafeArea()

            VStack(spacing: TE.Metric.gutter) {

                // MARK: connector edge
                JackStrip()
                    .padding(.top, 2)

                dottedRule(finish)

                // MARK: identity
                HStack(alignment: .firstTextBaseline) {
                    Text("tepevësen")
                        .font(TE.Type_.wordmark(14))
                        .tracking(0.4)
                        .foregroundStyle(TE.palette(finish).legend)
                    Spacer()
                    Legend(text: formatLine, size: 8)
                }

                // MARK: display + memo
                HStack(alignment: .top, spacing: TE.Metric.gutter) {
                    DotMatrixDisplay(
                        bitmap: device.displayBitmap,
                        finish: finish,
                        brightness: brightness
                    )
                    .aspectRatio(2, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .onTapGesture { device.flash(device.mode.legend) }

                    MemoButton()
                }
                .frame(maxHeight: 118)

                // MARK: rocker + reel
                HStack(spacing: TE.Metric.gutter) {
                    ShuttleRocker()
                        .frame(width: 30)

                    TapeReel(motor: device.motor, progress: reelProgress)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .aspectRatio(1, contentMode: .fit)

                    // Balances the rocker so the reel stays optically centred.
                    Color.clear.frame(width: 30)
                }
                .frame(maxHeight: .infinity)

                // MARK: transport
                TransportKeys()

                // MARK: mode row
                HStack(spacing: TE.Metric.gutter) {
                    ModeButton()

                    KeyCap(
                        height: 34,
                        radius: 9,
                        label: "tapes",
                        action: { device.showingLibrary = true }
                    ) {
                        Legend(text: "\(device.library.tapes.count)", size: 10,
                               color: TE.palette(finish).capLegend)
                    }

                    KeyCap(
                        height: 34,
                        radius: 9,
                        isLit: device.library.selected?.transcript != nil,
                        label: "text",
                        action: { device.showingTranscript = true }
                    ) {
                        Legend(text: "abc", size: 9,
                               color: TE.palette(finish).capLegend)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
        .environment(\.finish, finish)
        .preferredColorScheme(finish == .black ? .dark : .light)
        .onAppear { device.powerOn() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { device.jacks.refresh() }
        }
        .sheet(isPresented: $device.showingLibrary) {
            TapeListView().environment(\.finish, finish)
        }
        .sheet(isPresented: $device.showingTranscript) {
            TranscriptView().environment(\.finish, finish)
        }
    }

    // MARK: Derived

    private var formatLine: String {
        let rate = device.machine.actualSampleRate
        guard rate > 0 else { return "field recorder" }
        let k = rate / 1000
        let rateText = k == k.rounded() ? "\(Int(k))k" : String(format: "%.1fk", k)
        return "\(rateText) · \(AudioMachine.bitDepth) bit"
    }

    private var reelProgress: Double {
        if device.machine.isRecording {
            // While recording there is no end to progress toward, so the ring
            // shows the minute hand instead — where you are inside this minute.
            return (device.machine.recordedDuration.truncatingRemainder(dividingBy: 60)) / 60
        }
        guard device.machine.duration > 0 else { return 0 }
        return device.machine.position / device.machine.duration
    }

    /// The panel dims to standby when nothing is moving, like every piece of
    /// hardware that expects to sit on a table for an hour between takes.
    private var brightness: Double {
        switch device.machine.transport {
        case .stopped, .paused: return 0.78
        default:                return 1.0
        }
    }

    private func dottedRule(_ finish: Finish) -> some View {
        Rectangle()
            .fill(TE.palette(finish).legend.opacity(0.35))
            .frame(height: 0.5)
            .mask {
                HStack(spacing: 2) {
                    ForEach(0..<60, id: \.self) { _ in
                        Rectangle().frame(width: 2)
                    }
                }
            }
    }
}
