import Foundation

/// One recording. The machine calls them tapes because that is what the reel
/// is turning, and because "tape" is a thing you can hold and hand to someone,
/// which is the point of a field recorder.
struct Tape: Identifiable, Codable, Equatable {
    let id: UUID
    /// Auto-named on capture, renameable after. The hardware's convention:
    /// the moment it happened, nothing else.
    var name: String
    var createdAt: Date
    var duration: Double
    var sampleRate: Double
    var channels: Int
    var bitDepth: Int
    /// File name inside the tapes directory.
    var fileName: String
    /// A few hundred normalized peaks, enough to draw the tape at any size.
    var peaks: [Float]
    var transcript: Transcript?
    /// Marked while recording — the hardware's way of putting a finger on a
    /// moment you know you will want to find again.
    var marks: [Double]
    var starred: Bool

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        duration: Double,
        sampleRate: Double,
        channels: Int,
        bitDepth: Int = AudioMachine.bitDepth,
        fileName: String,
        peaks: [Float] = [],
        transcript: Transcript? = nil,
        marks: [Double] = [],
        starred: Bool = false
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.duration = duration
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitDepth = bitDepth
        self.fileName = fileName
        self.peaks = peaks
        self.transcript = transcript
        self.marks = marks
        self.starred = starred
    }

    /// "96k · 24 bit · stereo" — what the tape actually is, not what was asked for.
    var formatLine: String {
        let rate: String
        if sampleRate >= 1000 {
            let k = sampleRate / 1000
            rate = k == k.rounded() ? "\(Int(k))k" : String(format: "%.1fk", k)
        } else {
            rate = "\(Int(sampleRate))"
        }
        let ch = channels >= 2 ? "stereo" : "mono"
        return "\(rate) · \(bitDepth) bit · \(ch)"
    }

    static func autoName(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM.dd HH:mm"
        return f.string(from: date)
    }
}

// MARK: - Transcript

struct TranscriptSegment: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var text: String
    /// Seconds into the tape.
    var start: Double
    var duration: Double
    /// The recognizer's own confidence, 0…1. Shown, not hidden — a machine
    /// that guesses should say when it is guessing.
    var confidence: Float
}

struct Transcript: Codable, Equatable {
    var localeIdentifier: String
    var segments: [TranscriptSegment]
    var text: String
    /// True when the whole thing was recognized on the phone and no audio left it.
    var onDevice: Bool
    var createdAt: Date

    var localeName: String {
        Locale.current.localizedString(forIdentifier: localeIdentifier)?.lowercased()
            ?? localeIdentifier.lowercased()
    }

    /// The segment under the playhead, for following along.
    func segment(at time: Double) -> TranscriptSegment? {
        segments.last { $0.start <= time }
    }
}

// MARK: - Formatting

enum TimeCode {
    /// h:mm:ss for long tapes, m:ss for short ones. No leading zero hour.
    static func short(_ seconds: Double) -> String {
        let s = max(0, seconds)
        let total = Int(s)
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%d:%02d", m, sec)
    }

    /// mm:ss.t — the display's counter, with tenths, because a field recorder
    /// is a stopwatch as often as it is a microphone.
    static func counter(_ seconds: Double) -> String {
        let s = max(0, seconds)
        let total = Int(s)
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        let tenths = Int((s - Double(total)) * 10)
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%02d:%02d.%d", m, sec, tenths)
    }
}
