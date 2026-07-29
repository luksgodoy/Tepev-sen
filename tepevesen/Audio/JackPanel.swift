import Foundation
import AVFoundation
import Combine

/// The machine has one input, and it is the built-in microphone.
///
/// The hardware carries three two-way jacks because it is a box on a desk with
/// room for them. A phone has one microphone worth pointing at something, so
/// offering a choice would mean offering a way to get it wrong — an input
/// silently changing mid-take because a headset was plugged in is the kind of
/// failure you only discover afterwards. The input is pinned, and the machine
/// says so rather than pretending there is a decision to make.
///
/// The *output* still moves around, because that is the listener's business and
/// changing it costs nothing. So this reports where sound is going, and where
/// it is coming from is a constant.
@MainActor
final class JackPanel: ObservableObject {

    /// Always the built-in mic. Named for the display.
    let inputName = "built-in mic"

    /// Sample rate and channel count the hardware is really giving us.
    @Published private(set) var inputSampleRate: Double = 0
    @Published private(set) var inputChannels: Int = 0

    /// Where playback is currently going — speaker, headphones, a pair of
    /// AirPods by name.
    @Published private(set) var outputName: String = "speaker"
    /// True when something other than the machine's own speaker is listening.
    @Published private(set) var outputIsExternal: Bool = false
    /// False when iOS reports no usable input at all, which is worth saying
    /// out loud rather than discovering at the end of a take.
    @Published private(set) var inputAvailable: Bool = true

    private var observers: [NSObjectProtocol] = []

    init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        refresh()
    }

    func refresh() {
        let session = AVAudioSession.sharedInstance()

        // Re-pin every time the route changes. Plugging in a headset must not
        // move the source out from under a running take.
        pinToBuiltInMic()

        inputSampleRate = session.sampleRate
        inputChannels = session.inputNumberOfChannels
        inputAvailable = session.isInputAvailable

        let outputs = session.currentRoute.outputs
        outputName = outputs.first?.portName.lowercased() ?? "speaker"
        outputIsExternal = outputs.contains { $0.portType != .builtInSpeaker }
    }

    /// Force the session's input to the built-in microphone.
    ///
    /// `availableInputs` is only meaningful once the session is active, so this
    /// is a no-op before then and is called again on every route change.
    func pinToBuiltInMic() {
        let session = AVAudioSession.sharedInstance()
        guard let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }),
              session.preferredInput?.uid != builtIn.uid
        else { return }
        try? session.setPreferredInput(builtIn)
    }
}
