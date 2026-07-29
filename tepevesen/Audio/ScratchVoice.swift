import Foundation
import AVFoundation
import os

/// A low-resolution mono copy of a tape, kept in memory purely so the reel has
/// something to drag.
///
/// Scrubbing does not need fidelity — the hardware's reel sounds like tape
/// dragged across a head, and that is a lo-fi sound by nature. 22.05 kHz mono
/// costs about 1.3 MB per minute, so an hour-long tape is scrubbable for the
/// price of a photograph, while full-rate playback keeps streaming from disk.
final class ScrubTrack {
    static let sampleRate: Double = 22_050

    let samples: [Float]
    /// Duration of the original tape, in seconds.
    let duration: Double

    init(samples: [Float], duration: Double) {
        self.samples = samples
        self.duration = duration
    }

    /// Build the scrub copy by streaming the file once, downmixing to mono and
    /// box-averaging down to 22.05 kHz.
    static func build(from url: URL) throws -> ScrubTrack {
        let file = try AVAudioFile(forReading: url)
        let fmt = file.processingFormat
        let total = file.length
        guard total > 0 else { return ScrubTrack(samples: [], duration: 0) }

        let ratio = fmt.sampleRate / sampleRate
        let outCount = max(1, Int(Double(total) / ratio))
        var out = [Float]()
        out.reserveCapacity(outCount)

        let chunk: AVAudioFrameCount = 65_536
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: chunk) else {
            return ScrubTrack(samples: [], duration: 0)
        }

        var acc: Float = 0
        var accN: Double = 0
        let channels = Int(fmt.channelCount)

        while file.framePosition < total {
            try file.read(into: buf, frameCount: chunk)
            let n = Int(buf.frameLength)
            if n == 0 { break }
            guard let ch = buf.floatChannelData else { break }

            for i in 0..<n {
                var mono: Float = 0
                for c in 0..<channels { mono += ch[c][i] }
                mono /= Float(channels)

                acc += mono
                accN += 1
                if accN >= ratio {
                    out.append(acc / Float(accN))
                    acc = 0
                    accN = 0
                }
            }
        }
        if accN > 0 { out.append(acc / Float(accN)) }

        return ScrubTrack(samples: out, duration: Double(total) / fmt.sampleRate)
    }
}

/// The sound of the reel being turned by hand.
///
/// A single interpolating read head over the scrub track, driven by a signed
/// rate. Negative rate plays backwards, which is the whole point — you cannot
/// scratch a recording you can only step forward through.
final class ScratchVoice {
    /// Output format the source node is created with. The engine converts to
    /// whatever the hardware is actually running at.
    static let outputSampleRate: Double = 48_000

    private let lock: UnsafeMutablePointer<os_unfair_lock>
    private var track: ScrubTrack?

    /// Signed playback rate in tape-speed units. Written from the UI thread.
    private var _rate: Double = 0
    /// 0…1. Faded rather than switched, so grabbing the reel is not a click.
    private var _gain: Float = 0
    /// Read position, in scrub-track samples. Owned by the render thread while
    /// scratching; read back by the UI to move the playhead.
    private var _position: Double = 0

    init() {
        lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock_s())
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    // MARK: Control surface (UI thread)

    func load(_ track: ScrubTrack?) {
        os_unfair_lock_lock(lock)
        self.track = track
        _position = 0
        os_unfair_lock_unlock(lock)
    }

    var isLoaded: Bool {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return (track?.samples.isEmpty == false)
    }

    /// Set the signed rate and the wet gain in one lock.
    func drive(rate: Double, gain: Float) {
        os_unfair_lock_lock(lock)
        _rate = rate
        _gain = gain
        os_unfair_lock_unlock(lock)
    }

    /// Current head position, in seconds of the original tape.
    var seconds: Double {
        get {
            os_unfair_lock_lock(lock)
            defer { os_unfair_lock_unlock(lock) }
            return _position / ScrubTrack.sampleRate
        }
        set {
            os_unfair_lock_lock(lock)
            _position = max(0, newValue * ScrubTrack.sampleRate)
            os_unfair_lock_unlock(lock)
        }
    }

    // MARK: Render (audio thread)

    func makeSourceNode() -> AVAudioSourceNode {
        let format = AVAudioFormat(
            standardFormatWithSampleRate: Self.outputSampleRate,
            channels: 2
        )!

        return AVAudioSourceNode(format: format) { [weak self] silence, _, frameCount, ablPointer in
            let abl = UnsafeMutableAudioBufferListPointer(ablPointer)
            guard let self else {
                silence.pointee = true
                return noErr
            }

            // Never block the render thread. If the UI happens to be swapping
            // the track this instant, emit silence for one buffer.
            guard os_unfair_lock_trylock(self.lock) else {
                silence.pointee = true
                for buffer in abl {
                    memset(buffer.mData, 0, Int(buffer.mDataByteSize))
                }
                return noErr
            }
            defer { os_unfair_lock_unlock(self.lock) }

            guard let samples = self.track?.samples, samples.count > 1, self._gain > 0.0001 else {
                silence.pointee = true
                for buffer in abl {
                    memset(buffer.mData, 0, Int(buffer.mDataByteSize))
                }
                return noErr
            }

            let step = self._rate * ScrubTrack.sampleRate / Self.outputSampleRate
            let gain = self._gain
            var pos = self._position
            let last = Double(samples.count - 2)

            // Render the head into the first channel, then copy across. No
            // allocation, no bridging: this runs on the audio thread.
            guard abl.count > 0, let leftRaw = abl[0].mData else {
                silence.pointee = true
                return noErr
            }
            let left = leftRaw.assumingMemoryBound(to: Float.self)

            samples.withUnsafeBufferPointer { src in
                for frame in 0..<Int(frameCount) {
                    var s: Float = 0
                    if pos >= 0, pos <= last {
                        let i = Int(pos)
                        let f = Float(pos - Double(i))
                        s = src[i] * (1 - f) + src[i + 1] * f
                    }
                    left[frame] = s * gain
                    pos += step
                    if pos < 0 { pos = 0 }
                    if pos > last { pos = last }
                }
            }

            if abl.count > 1 {
                let bytes = Int(abl[0].mDataByteSize)
                for channel in 1..<abl.count {
                    if let dst = abl[channel].mData {
                        memcpy(dst, leftRaw, min(bytes, Int(abl[channel].mDataByteSize)))
                    }
                }
            }

            self._position = pos
            return noErr
        }
    }
}
