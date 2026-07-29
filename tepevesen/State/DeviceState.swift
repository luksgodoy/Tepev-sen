import SwiftUI
import Combine
import AVFoundation
import UIKit

/// What the display is currently showing. The mode button walks this list and
/// nothing else changes it — one button, one job, no menus.
enum DisplayMode: Int, CaseIterable, Identifiable {
    case tape
    case level
    case speed
    case input
    case system

    var id: Int { rawValue }

    var legend: String {
        switch self {
        case .tape:   return "tape"
        case .level:  return "level"
        case .speed:  return "speed"
        case .input:  return "input"
        case .system: return "system"
        }
    }
}

/// The machine.
///
/// Holds the transport, the tapes, the jacks and the panel, and is the only
/// thing in the app that knows how all of those fit together. Views read it and
/// press its buttons; they never talk to the audio engine directly.
@MainActor
final class DeviceState: ObservableObject {

    // MARK: Parts

    let machine = AudioMachine()
    let library = TapeLibrary()
    let jacks = JackPanel()
    let transcriber = Transcriber()
    let motor = ReelMotor()
    let haptics = Haptics()

    // MARK: Panel state

    @Published var mode: DisplayMode = .tape
    @Published var finish: Finish {
        didSet { UserDefaults.standard.set(finish.rawValue, forKey: "finish") }
    }
    /// A transient line the display shows over everything else for a moment,
    /// the way hardware flashes a confirmation and then forgets it.
    @Published private(set) var toast: String?
    @Published private(set) var batteryLevel: Double = 1.0
    /// Set while a freshly stopped tape is being measured.
    @Published private(set) var isFiling = false
    /// Presented sheets.
    @Published var showingLibrary = false
    @Published var showingTranscript = false

    private var cancellables = Set<AnyCancellable>()
    private var toastTask: Task<Void, Never>?
    private var recordingStarted: Date?
    private var pendingURL: URL?
    private var pendingFileName: String?
    private var scrubTrack: ScrubTrack?

    // MARK: Init

    init() {
        let stored = UserDefaults.standard.string(forKey: "finish") ?? Finish.aluminum.rawValue
        finish = Finish(rawValue: stored) ?? .aluminum

        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryLevel = Double(max(UIDevice.current.batteryLevel, 0))

        // Re-publish the parts so a single view can observe the machine.
        machine.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        library.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        jacks.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        transcriber.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)
            .sink { [weak self] _ in
                self?.batteryLevel = Double(max(UIDevice.current.batteryLevel, 0))
            }
            .store(in: &cancellables)

        // The reel is geared to the transport: what the tape is doing, the
        // reel is doing, at all times and without being asked.
        motor.rateProvider = { [weak self] in
            guard let self else { return 0 }
            switch self.machine.transport {
            case .playing:            return self.machine.speed
            case .recording:          return 1.0
            case .shuttling(let m):   return m
            case .recordHold, .paused, .stopped, .scratching:
                return 0
            }
        }
        motor.onHandRate = { [weak self] rate in
            guard let self else { return }
            if case .scratching = self.machine.transport {
                self.machine.scratch(rate: rate)
                self.haptics.setMotor(intensity: Float(min(abs(rate) * 0.18, 0.5)))
            }
        }
        motor.onDetent = { [weak self] in self?.haptics.detent() }
        motor.onSettle = { [weak self] in self?.reelSettled() }
        motor.start()
    }

    // MARK: - The reel
    //
    // A hand on the reel means one thing at a time, and which thing depends
    // only on what the transport was already doing. While recording it is a
    // brake on capture; otherwise it is the tape itself.

    private var wasPlayingBeforeScratch = false

    func reelGrabbed() {
        motor.grab()
        if machine.isRecording {
            machine.holdCapture(true)
            haptics.bump(.rigid)
            return
        }
        wasPlayingBeforeScratch = machine.transport == .playing
        machine.beginScratch()
        haptics.bump(.light)
        haptics.startMotor(intensity: 0.12)
    }

    /// Called for every increment of hand movement.
    func reelTurned(deltaDegrees: Double, dt: Double) {
        motor.turn(by: deltaDegrees, over: dt)
        switch machine.transport {
        case .scratching, .recordHold:
            // Handled by the motor's rate callback, or deliberately inert.
            break
        default:
            // No scrub copy for this tape yet: the reel still moves the tape,
            // it just does not make a sound doing it.
            let seconds = deltaDegrees / ReelMotor.degreesPerSecondAt1x
            machine.seek(to: machine.position + seconds)
        }
    }

    func reelReleased(flick: Bool) {
        if case .recordHold = machine.transport {
            machine.holdCapture(false)
            motor.release(carryMomentum: false)
            haptics.bump(.rigid)
            return
        }
        motor.release(carryMomentum: flick)
    }

    private func reelSettled() {
        haptics.stopMotor()
        guard case .scratching = machine.transport else { return }
        machine.endScratch(resumePlaying: wasPlayingBeforeScratch)
    }

    // MARK: - The rocker
    //
    // Press the top edge to run forward, the bottom to run back. Hold and it
    // winds up: 2×, then 4×, then 8×. Let go and it drops straight back to
    // where the tape was.

    func shuttleBegan(forward: Bool) {
        haptics.bump(.light)
        machine.shuttle(forward ? 2 : -2)
    }

    func shuttleHeld(forward: Bool, seconds: Double) {
        let multiplier: Double = seconds > 2.5 ? 8 : (seconds > 1.0 ? 4 : 2)
        machine.shuttle(forward ? multiplier : -multiplier)
    }

    func shuttleEnded() {
        machine.endShuttle()
        haptics.bump(.light)
    }

    // MARK: Power-on

    func powerOn() {
        machine.configure()
        jacks.refresh()
        library.refreshStorage()
        if let tape = library.selected { loadForPlayback(tape) }
    }

    // MARK: - Memo
    //
    // One press. The machine wakes and is already recording. There is no
    // "new recording" screen because a moment you have to navigate to is a
    // moment you have already lost.

    func memo() {
        guard !machine.isRecording else {
            flash("already rolling")
            haptics.bump(.rigid)
            return
        }
        startRecording()
    }

    // MARK: - Transport

    func recordButton() {
        if machine.isRecording {
            finishRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        Task {
            guard await requestMicrophone() else {
                flash("no mic access")
                return
            }
            let slot = library.newTapeURL()
            guard let format = machine.startRecording(to: slot.url) else {
                flash(machine.lastError ?? "input error")
                return
            }
            pendingURL = slot.url
            pendingFileName = slot.fileName
            recordingStarted = Date()
            mode = .tape
            haptics.transport(.record)
            flash("rec \(Int(format.sampleRate / 1000))k")
        }
    }

    private func finishRecording() {
        // Read before stopping — stopRecording clears them.
        let stalled = machine.inputStalled
        let stallReason = machine.stallReason
        let duration = machine.stopRecording()
        haptics.transport(.stop)
        guard let url = pendingURL, let fileName = pendingFileName else { return }
        pendingURL = nil
        pendingFileName = nil

        guard duration > 0.25 else {
            // Too short to be a thought. Throw it away rather than clutter the
            // reel — but never call a dead input "too short", which is the one
            // message that sends you looking in the wrong place entirely.
            try? FileManager.default.removeItem(at: url)
            flash(stalled ? (stallReason ?? "no input") : "too short")
            return
        }

        let started = recordingStarted ?? Date()
        recordingStarted = nil
        let rate = machine.actualSampleRate
        let channels = machine.actualChannels
        isFiling = true

        Task.detached(priority: .userInitiated) {
            let scrub = try? ScrubTrack.build(from: url)
            let peaks = scrub.map { Waveform.peaks(from: $0) } ?? []
            await MainActor.run {
                let tape = Tape(
                    name: Tape.autoName(started),
                    createdAt: started,
                    duration: duration,
                    sampleRate: rate,
                    channels: channels,
                    fileName: fileName,
                    peaks: peaks
                )
                self.scrubTrack = scrub
                self.library.add(tape)
                self.machine.load(url: url, scrub: scrub)
                self.isFiling = false
                self.flash(TimeCode.short(duration))
            }
        }
    }

    func playButton() {
        switch machine.transport {
        case .playing:
            machine.pause()
            haptics.transport(.stop)
        case .recording, .recordHold:
            finishRecording()
        default:
            guard library.selected != nil else {
                flash("no tape")
                return
            }
            machine.play()
            haptics.transport(.play)
        }
    }

    func stopButton() {
        if machine.isRecording {
            finishRecording()
            return
        }
        machine.stop()
        haptics.transport(.stop)
    }

    /// Long-press on stop steps to the next tape — the machine's only list
    /// navigation that does not need the screen.
    func nextTape() {
        guard let tape = library.step(1) else { return }
        loadForPlayback(tape)
        flash(tape.name)
        haptics.detent()
    }

    func previousTape() {
        guard let tape = library.step(-1) else { return }
        loadForPlayback(tape)
        flash(tape.name)
        haptics.detent()
    }

    func loadForPlayback(_ tape: Tape) {
        library.select(tape.id)
        let url = library.url(for: tape)
        machine.load(url: url, scrub: nil)
        // The scrub copy is built off the main thread; until it lands the reel
        // seeks silently instead of scratching.
        Task.detached(priority: .utility) {
            let scrub = try? ScrubTrack.build(from: url)
            await MainActor.run {
                guard self.library.selectedID == tape.id else { return }
                self.scrubTrack = scrub
                self.machine.load(url: url, scrub: scrub)
            }
        }
    }

    // MARK: - Mode

    func cycleMode() {
        let all = DisplayMode.allCases
        let i = all.firstIndex(of: mode) ?? 0
        mode = all[(i + 1) % all.count]
        haptics.detent()
    }

    // MARK: - Marks

    func mark() {
        guard let tape = library.selected else { return }
        let t = machine.isRecording ? machine.recordedDuration : machine.position
        library.addMark(to: tape, at: t)
        haptics.bump(.rigid)
        flash("mark \(TimeCode.short(t))")
    }

    // MARK: - Toast

    func flash(_ message: String) {
        toastTask?.cancel()
        toast = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: - Permission

    private func requestMicrophone() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }

    // MARK: - Transcription

    func transcribeSelected(locale: Locale) {
        guard let tape = library.selected else {
            flash("no tape")
            return
        }
        let url = library.url(for: tape)
        Task {
            if let transcript = await transcriber.transcribe(
                url: url, locale: locale, duration: tape.duration
            ) {
                library.setTranscript(transcript, for: tape.id)
                flash(transcript.onDevice ? "on-device" : "transcribed")
            }
        }
    }
}
