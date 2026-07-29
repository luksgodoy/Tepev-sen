import Foundation
import AVFoundation
import Combine

/// The transport. Everything the machine can be doing at a given moment.
enum Transport: Equatable {
    case stopped
    case playing
    case paused
    case recording
    /// Recording, but with a finger on the reel — the tape is still loaded and
    /// the machine is still armed, it just is not capturing.
    case recordHold
    /// The reel is being turned by hand.
    case scratching
    /// The rocker is held: shuttling forward or back at speed.
    case shuttling(Double)
}

/// The audio hardware, such as it is.
///
/// One `AVAudioEngine` carries three paths that never fight over the device:
/// the input tap that writes tape, the file player with its two time units,
/// and the scratch voice the reel drives. The machine records at the highest
/// rate and depth the phone will actually give it, and reports the rate it got
/// rather than the rate it wanted.
final class AudioMachine: ObservableObject {

    // MARK: Published state

    @Published private(set) var transport: Transport = .stopped
    /// Position on the current tape, in seconds.
    @Published private(set) var position: Double = 0
    /// Length of the current tape, in seconds.
    @Published private(set) var duration: Double = 0
    /// Elapsed capture time while recording.
    @Published private(set) var recordedDuration: Double = 0
    /// 0…1 RMS and peak, for the meters.
    @Published private(set) var level: Double = 0
    @Published private(set) var peak: Double = 0
    /// What the hardware actually handed us.
    @Published private(set) var actualSampleRate: Double = 0
    @Published private(set) var actualChannels: Int = 0
    @Published private(set) var lastError: String?

    /// Tape speed, 0.25×…4×. 1.0 is nominal.
    @Published var speed: Double = 1.0 {
        didSet { applySpeed() }
    }
    /// Off by default: on tape, speed and pitch are the same knob.
    @Published var pitchLock: Bool = false {
        didSet { applySpeed() }
    }
    /// Monitor the input through the selected output while recording.
    @Published var inputMonitoring: Bool = false {
        didSet { monitorMixer.outputVolume = inputMonitoring ? 1 : 0 }
    }

    // MARK: Requested format

    /// What the hardware asks for. 24-bit / 96 kHz, same as the machine this
    /// is a version of.
    static let preferredSampleRate: Double = 96_000
    static let bitDepth: Int = 24

    // MARK: Graph

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let varispeed = AVAudioUnitVarispeed()
    private let timePitch = AVAudioUnitTimePitch()
    private let monitorMixer = AVAudioMixerNode()
    private let scratchVoice = ScratchVoice()
    private var scratchNode: AVAudioSourceNode?

    // MARK: Files

    private var writeFile: AVAudioFile?
    private var playFile: AVAudioFile?
    private var seekOffsetFrames: AVAudioFramePosition = 0
    private var capturePaused = false
    private var recordedFrames: AVAudioFramePosition = 0
    private var isConfigured = false

    private var ticker: Timer?
    private var meterAccumulator = (rms: 0.0, peak: 0.0)

    // MARK: - Lifecycle

    init() {
        engine.attach(player)
        engine.attach(varispeed)
        engine.attach(timePitch)
        engine.attach(monitorMixer)

        let node = scratchVoice.makeSourceNode()
        engine.attach(node)
        scratchNode = node

        let stereo = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!

        // Tape path: player → varispeed → pitch → mixer.
        // Both time units are always in the chain; whichever is not in use sits
        // at unity, so switching pitch lock never rebuilds the graph.
        engine.connect(player, to: varispeed, format: stereo)
        engine.connect(varispeed, to: timePitch, format: stereo)
        engine.connect(timePitch, to: engine.mainMixerNode, format: stereo)

        // Reel path.
        engine.connect(node, to: engine.mainMixerNode, format: stereo)

        // Monitor path, wired in `configure()` once the input format is known.
        monitorMixer.outputVolume = 0

        applySpeed()
        observeInterruptions()
    }

    deinit {
        ticker?.invalidate()
    }

    /// Bring up the session and the engine. Safe to call repeatedly.
    func configure() {
        guard !isConfigured else { return }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.allowBluetooth, .allowBluetoothA2DP, .allowAirPlay, .defaultToSpeaker]
            )
            // Ask for the machine's rated format. The phone decides what it can
            // actually deliver, and we record at whatever that turns out to be.
            try session.setPreferredSampleRate(Self.preferredSampleRate)
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            lastError = "audio session: \(error.localizedDescription)"
        }

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        if inputFormat.sampleRate > 0 {
            engine.connect(input, to: monitorMixer, format: inputFormat)
            engine.connect(monitorMixer, to: engine.mainMixerNode, format: nil)
        }

        actualSampleRate = session.sampleRate
        actualChannels = max(1, session.inputNumberOfChannels)

        engine.prepare()
        do {
            try engine.start()
            isConfigured = true
        } catch {
            lastError = "engine: \(error.localizedDescription)"
        }

        startTicker()
    }

    private func restartEngineIfNeeded() {
        guard isConfigured, !engine.isRunning else { return }
        do { try engine.start() } catch {
            lastError = "engine restart: \(error.localizedDescription)"
        }
    }

    private func observeInterruptions() {
        let center = NotificationCenter.default
        center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            switch type {
            case .began:
                // A call is a call. Stop cleanly rather than losing the tape.
                if case .recording = self.transport { _ = self.stopRecording() }
                self.pause()
            case .ended:
                try? AVAudioSession.sharedInstance().setActive(true)
                self.restartEngineIfNeeded()
            @unknown default:
                break
            }
        }
        center.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine, queue: .main
        ) { [weak self] _ in
            self?.restartEngineIfNeeded()
        }
    }

    // MARK: - Recording

    /// Start a new tape. Returns the format actually being captured.
    @discardableResult
    func startRecording(to url: URL) -> (sampleRate: Double, channels: Int)? {
        configure()
        restartEngineIfNeeded()

        let input = engine.inputNode
        let tapFormat = input.outputFormat(forBus: 0)
        guard tapFormat.sampleRate > 0 else {
            lastError = "no input"
            return nil
        }

        // Write 24-bit linear PCM at the rate we are genuinely receiving. The
        // file the tap hands us is float32, and AVAudioFile converts on write.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: tapFormat.sampleRate,
            AVNumberOfChannelsKey: tapFormat.channelCount,
            AVLinearPCMBitDepthKey: Self.bitDepth,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        do {
            writeFile = try AVAudioFile(
                forWriting: url,
                settings: settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            lastError = "tape: \(error.localizedDescription)"
            return nil
        }

        capturePaused = false
        recordedFrames = 0

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.measure(buffer)
            guard !self.capturePaused, let file = self.writeFile else { return }
            do {
                try file.write(from: buffer)
                self.recordedFrames += AVAudioFramePosition(buffer.frameLength)
            } catch {
                DispatchQueue.main.async { self.lastError = "write: \(error.localizedDescription)" }
            }
        }

        actualSampleRate = tapFormat.sampleRate
        actualChannels = Int(tapFormat.channelCount)
        transport = .recording
        return (tapFormat.sampleRate, Int(tapFormat.channelCount))
    }

    /// Stop capture and close the tape. Returns its duration in seconds.
    @discardableResult
    func stopRecording() -> Double {
        engine.inputNode.removeTap(onBus: 0)
        let rate = writeFile?.processingFormat.sampleRate ?? 1
        let seconds = Double(recordedFrames) / max(rate, 1)
        writeFile = nil
        capturePaused = false
        recordedFrames = 0
        recordedDuration = 0
        transport = .stopped
        level = 0
        peak = 0
        return seconds
    }

    /// A finger on the reel: still armed, no longer capturing.
    func holdCapture(_ hold: Bool) {
        guard writeFile != nil else { return }
        capturePaused = hold
        transport = hold ? .recordHold : .recording
    }

    var isRecording: Bool { writeFile != nil }

    // MARK: - Playback

    func load(url: URL, scrub: ScrubTrack?) {
        player.stop()
        seekOffsetFrames = 0
        position = 0
        do {
            let file = try AVAudioFile(forReading: url)
            playFile = file
            duration = Double(file.length) / file.processingFormat.sampleRate
        } catch {
            playFile = nil
            duration = 0
            lastError = "load: \(error.localizedDescription)"
        }
        scratchVoice.load(scrub)
        transport = .stopped
    }

    func unload() {
        player.stop()
        playFile = nil
        duration = 0
        position = 0
        scratchVoice.load(nil)
        transport = .stopped
    }

    func play() {
        guard playFile != nil else { return }
        restartEngineIfNeeded()
        if case .paused = transport {
            player.play()
        } else {
            schedule(from: position)
            player.play()
        }
        installPlaybackMeter()
        transport = .playing
    }

    func pause() {
        guard case .playing = transport else {
            if case .scratching = transport { transport = .paused }
            return
        }
        position = currentTime()
        player.pause()
        transport = .paused
    }

    func stop() {
        player.stop()
        engine.mainMixerNode.removeTap(onBus: 0)
        position = 0
        seekOffsetFrames = 0
        level = 0
        peak = 0
        transport = .stopped
    }

    func seek(to seconds: Double) {
        let target = seconds.clamped(to: 0...max(duration, 0))
        position = target
        scratchVoice.seconds = target
        switch transport {
        case .playing:
            schedule(from: target)
            player.play()
        default:
            player.stop()
        }
    }

    private func schedule(from seconds: Double) {
        guard let file = playFile else { return }
        let sr = file.processingFormat.sampleRate
        let start = AVAudioFramePosition((seconds * sr).rounded())
        let remaining = file.length - start
        guard remaining > 0 else {
            transport = .stopped
            return
        }
        seekOffsetFrames = start
        player.stop()
        player.scheduleSegment(
            file,
            startingFrame: start,
            frameCount: AVAudioFrameCount(remaining),
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, case .playing = self.transport else { return }
                self.position = self.duration
                self.player.stop()
                self.transport = .stopped
            }
        }
    }

    private func currentTime() -> Double {
        guard let file = playFile,
              let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime),
              playerTime.sampleRate > 0
        else { return position }
        let sr = file.processingFormat.sampleRate
        let elapsed = Double(playerTime.sampleTime) / playerTime.sampleRate
        return (Double(seekOffsetFrames) / sr + elapsed).clamped(to: 0...max(duration, 0))
    }

    private func applySpeed() {
        let s = speed.clamped(to: 0.25...4.0)
        if pitchLock {
            varispeed.rate = 1.0
            timePitch.rate = Float(s)
            timePitch.pitch = 0
        } else {
            varispeed.rate = Float(s)
            timePitch.rate = 1.0
            timePitch.pitch = 0
        }
    }

    // MARK: - Shuttle

    /// The side rocker. Positive shuttles forward, negative back. Playback
    /// keeps sounding so you can hear where you are, exactly like riding the
    /// rocker on the hardware.
    func shuttle(_ multiplier: Double) {
        guard playFile != nil else { return }
        guard multiplier != 0 else {
            endShuttle()
            return
        }
        transport = .shuttling(multiplier)
        if multiplier > 0 {
            speed = multiplier.clamped(to: 1...4)
            if !player.isPlaying { play() }
        } else {
            // Backwards is the reel's job — the player cannot run in reverse.
            beginScratch()
            scratchVoice.drive(rate: multiplier, gain: 0.85)
        }
    }

    func endShuttle() {
        if case .shuttling(let m) = transport, m < 0 {
            endScratch(resumePlaying: false)
        }
        speed = 1.0
        if player.isPlaying {
            transport = .playing
        } else {
            transport = .paused
        }
    }

    // MARK: - The reel

    /// A hand lands on the reel: playback yields, the scratch voice takes over
    /// from exactly where the playhead was.
    func beginScratch() {
        guard playFile != nil, scratchVoice.isLoaded else { return }
        let here = currentTime()
        position = here
        scratchVoice.seconds = here
        player.pause()
        scratchVoice.drive(rate: 0, gain: 1.0)
        transport = .scratching
    }

    /// Signed tape-speed the reel is currently being turned at.
    func scratch(rate: Double) {
        guard case .scratching = transport else { return }
        scratchVoice.drive(rate: rate.clamped(to: -16...16), gain: 1.0)
        position = scratchVoice.seconds.clamped(to: 0...max(duration, 0))
    }

    /// The hand comes off. Either the machine picks up playing from the new
    /// position, or it stays where it was put.
    func endScratch(resumePlaying: Bool) {
        scratchVoice.drive(rate: 0, gain: 0)
        let landed = scratchVoice.seconds.clamped(to: 0...max(duration, 0))
        position = landed
        if resumePlaying {
            schedule(from: landed)
            player.play()
            transport = .playing
        } else {
            player.stop()
            transport = .paused
        }
    }

    // MARK: - Metering

    private func installPlaybackMeter() {
        let mixer = engine.mainMixerNode
        mixer.removeTap(onBus: 0)
        mixer.installTap(onBus: 0, bufferSize: 2048, format: nil) { [weak self] buffer, _ in
            self?.measure(buffer)
        }
    }

    private func measure(_ buffer: AVAudioPCMBuffer) {
        guard let ch = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        let n = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        var sum: Float = 0
        var pk: Float = 0
        for c in 0..<channels {
            let data = ch[c]
            for i in 0..<n {
                let v = data[i]
                sum += v * v
                let a = abs(v)
                if a > pk { pk = a }
            }
        }
        let rms = sqrt(sum / Float(n * max(channels, 1)))
        // Meters are read, not measured — a decibel scale with a floor at
        // -54 dB puts the useful range where the eye can see it.
        let rmsNorm = Self.normalize(rms)
        let pkNorm = Self.normalize(pk)
        meterAccumulator.rms = max(meterAccumulator.rms, Double(rmsNorm))
        meterAccumulator.peak = max(meterAccumulator.peak, Double(pkNorm))
    }

    private static func normalize(_ amplitude: Float) -> Float {
        guard amplitude > 0.0001 else { return 0 }
        let db = 20 * log10(amplitude)
        // Written out rather than via `clamped`: the stdlib has a
        // package-protected `clamped` on Float that wins overload resolution
        // and is then unusable.
        return min(max((db + 54) / 54, 0), 1)
    }

    // MARK: - Tick

    private func startTicker() {
        ticker?.invalidate()
        // 30 Hz: fast enough that the reel and the meters look continuous,
        // slow enough that it costs nothing.
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func tick() {
        // Meters decay rather than snap, the way a needle does.
        level = max(meterAccumulator.rms, level * 0.72)
        peak = max(meterAccumulator.peak, peak * 0.94)
        meterAccumulator = (0, 0)

        switch transport {
        case .playing:
            position = currentTime()
        case .recording:
            recordedDuration = Double(recordedFrames) / max(actualSampleRate, 1)
        case .recordHold:
            break
        case .scratching:
            position = scratchVoice.seconds.clamped(to: 0...max(duration, 0))
        case .shuttling(let m) where m < 0:
            position = scratchVoice.seconds.clamped(to: 0...max(duration, 0))
        default:
            break
        }
    }
}
