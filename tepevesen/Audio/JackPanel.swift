import Foundation
import AVFoundation
import Combine

/// The hardware carries three two-way 3.5 mm jacks and one 1/4" output. A
/// phone has no jacks, but it has exactly the same idea: a set of physical
/// paths audio can arrive on and leave by, each of which is either plugged in
/// or it is not.
///
/// So the jack strip is not a drawing. Each jack is bound to a real route, it
/// lights when that route is genuinely available, and tapping it selects it.
enum JackID: String, CaseIterable, Identifiable, Codable {
    /// The machine's own mic and speaker — the jack that is always plugged in.
    case internalIO
    /// Anything on the wire: headset, lavalier, USB-C interface.
    case wired
    /// Bluetooth, either A2DP out or a headset with a mic.
    case bluetooth
    /// The 1/4" monitor out — where the machine is currently listening back.
    case monitorOut

    var id: String { rawValue }

    /// Silkscreen legend, in the hardware's lowercase.
    var legend: String {
        switch self {
        case .internalIO: return "int"
        case .wired:      return "1/8"
        case .bluetooth:  return "bt"
        case .monitorOut: return "1/4"
        }
    }

    /// Two-way jacks carry signal in both directions; the 1/4" is out only.
    var isTwoWay: Bool { self != .monitorOut }
}

struct JackStatus: Identifiable, Equatable {
    let id: JackID
    var connected: Bool
    var selected: Bool
    /// What is actually on the other end, e.g. "usb-c", "airpods pro".
    var detail: String
}

/// Watches the audio session and keeps the jack strip truthful.
@MainActor
final class JackPanel: ObservableObject {
    @Published private(set) var jacks: [JackStatus] = JackID.allCases.map {
        JackStatus(id: $0, connected: $0 == .internalIO, selected: $0 == .internalIO, detail: "")
    }

    /// Sample rate and channel count the hardware is really giving us. The
    /// machine claims nothing it is not currently doing.
    @Published private(set) var inputSampleRate: Double = 0
    @Published private(set) var inputChannels: Int = 0
    @Published private(set) var outputName: String = "speaker"

    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        refresh()
    }

    func refresh() {
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute
        let available = session.availableInputs ?? []
        let selectedInput = session.preferredInput ?? available.first { $0.uid == route.inputs.first?.uid }

        inputSampleRate = session.sampleRate
        inputChannels = session.inputNumberOfChannels
        outputName = route.outputs.first?.portName.lowercased() ?? "speaker"

        func port(matching kinds: Set<AVAudioSession.Port>) -> AVAudioSessionPortDescription? {
            available.first { kinds.contains($0.portType) }
        }

        let wiredKinds: Set<AVAudioSession.Port> = [.headsetMic, .usbAudio, .lineIn, .carAudio]
        let btKinds: Set<AVAudioSession.Port> = [.bluetoothHFP, .bluetoothLE]

        let wiredPort = port(matching: wiredKinds)
        let btPort = port(matching: btKinds)
        let outPorts = route.outputs
        let wiredOutKinds: Set<AVAudioSession.Port> = [.headphones, .usbAudio, .lineOut, .carAudio]
        let btOutKinds: Set<AVAudioSession.Port> = [.bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .airPlay]
        let wiredOutPort = outPorts.first { wiredOutKinds.contains($0.portType) }
        let btOutPort = outPorts.first { btOutKinds.contains($0.portType) }

        jacks = JackID.allCases.map { id in
            switch id {
            case .internalIO:
                return JackStatus(
                    id: id,
                    connected: true,
                    selected: selectedInput?.portType == .builtInMic || selectedInput == nil,
                    detail: "mic + speaker"
                )
            case .wired:
                return JackStatus(
                    id: id,
                    connected: wiredPort != nil || wiredOutPort != nil,
                    selected: wiredKinds.contains(selectedInput?.portType ?? .builtInMic),
                    detail: (wiredPort?.portName ?? wiredOutPort?.portName ?? "").lowercased()
                )
            case .bluetooth:
                return JackStatus(
                    id: id,
                    connected: btPort != nil || btOutPort != nil,
                    selected: btKinds.contains(selectedInput?.portType ?? .builtInMic),
                    detail: (btPort?.portName ?? btOutPort?.portName ?? "").lowercased()
                )
            case .monitorOut:
                return JackStatus(
                    id: id,
                    connected: true,
                    selected: false,
                    detail: outputName
                )
            }
        }
    }

    /// Patch the input to a jack. Two-way jacks only — you cannot record from
    /// an output, on this machine or any other.
    func select(_ id: JackID) {
        guard id.isTwoWay else { return }
        let session = AVAudioSession.sharedInstance()
        let available = session.availableInputs ?? []

        let wanted: AVAudioSessionPortDescription?
        switch id {
        case .internalIO:
            wanted = available.first { $0.portType == .builtInMic }
        case .wired:
            wanted = available.first {
                [.headsetMic, .usbAudio, .lineIn, .carAudio].contains($0.portType)
            }
        case .bluetooth:
            wanted = available.first {
                [.bluetoothHFP, .bluetoothLE].contains($0.portType)
            }
        case .monitorOut:
            wanted = nil
        }

        guard let wanted else { return }
        try? session.setPreferredInput(wanted)
        refresh()
    }
}
