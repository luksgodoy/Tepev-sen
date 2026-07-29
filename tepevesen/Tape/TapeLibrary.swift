import Foundation
import Combine

/// The 128 GB inside the machine.
///
/// Tapes are plain 24-bit WAV files in a visible folder with an index beside
/// them. Nothing is in a database, nothing is in a proprietary container, and
/// the Files app can see all of it. A recording you cannot get back out is not
/// a recording, it is a hostage.
@MainActor
final class TapeLibrary: ObservableObject {

    @Published private(set) var tapes: [Tape] = []
    @Published private(set) var selectedID: Tape.ID?

    /// Free space on the volume, in bytes — the machine's remaining tape.
    @Published private(set) var freeBytes: Int64 = 0
    @Published private(set) var usedBytes: Int64 = 0

    private let fm = FileManager.default

    let tapesDirectory: URL
    private let indexURL: URL

    init() {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        tapesDirectory = docs.appendingPathComponent("tapes", isDirectory: true)
        indexURL = docs.appendingPathComponent("index.json")
        try? fm.createDirectory(at: tapesDirectory, withIntermediateDirectories: true)
        load()
        refreshStorage()
    }

    var selected: Tape? {
        guard let selectedID else { return nil }
        return tapes.first { $0.id == selectedID }
    }

    var selectedIndex: Int? {
        guard let selectedID else { return nil }
        return tapes.firstIndex { $0.id == selectedID }
    }

    func url(for tape: Tape) -> URL {
        tapesDirectory.appendingPathComponent(tape.fileName)
    }

    // MARK: Selection

    func select(_ id: Tape.ID?) {
        selectedID = id
    }

    /// Step through the reel of tapes. Wraps, because a machine with a finite
    /// list and no wrap is a machine that dead-ends.
    func step(_ delta: Int) -> Tape? {
        guard !tapes.isEmpty else { return nil }
        let current = selectedIndex ?? 0
        var next = (current + delta) % tapes.count
        if next < 0 { next += tapes.count }
        selectedID = tapes[next].id
        return tapes[next]
    }

    // MARK: Writing

    /// Reserve a file for a new tape before capture starts.
    func newTapeURL(at date: Date = Date()) -> (url: URL, fileName: String) {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        var name = "tape-\(f.string(from: date)).wav"
        var n = 2
        while fm.fileExists(atPath: tapesDirectory.appendingPathComponent(name).path) {
            name = "tape-\(f.string(from: date))-\(n).wav"
            n += 1
        }
        return (tapesDirectory.appendingPathComponent(name), name)
    }

    func add(_ tape: Tape) {
        tapes.insert(tape, at: 0)
        selectedID = tape.id
        save()
        refreshStorage()
    }

    func update(_ tape: Tape) {
        guard let i = tapes.firstIndex(where: { $0.id == tape.id }) else { return }
        tapes[i] = tape
        save()
    }

    func rename(_ tape: Tape, to name: String) {
        var t = tape
        t.name = name.isEmpty ? Tape.autoName(tape.createdAt) : name
        update(t)
    }

    func toggleStar(_ tape: Tape) {
        var t = tape
        t.starred.toggle()
        update(t)
    }

    func addMark(to tape: Tape, at time: Double) {
        var t = tape
        t.marks.append(time)
        t.marks.sort()
        update(t)
    }

    func delete(_ tape: Tape) {
        try? fm.removeItem(at: url(for: tape))
        tapes.removeAll { $0.id == tape.id }
        if selectedID == tape.id { selectedID = tapes.first?.id }
        save()
        refreshStorage()
    }

    func setTranscript(_ transcript: Transcript?, for tapeID: Tape.ID) {
        guard let i = tapes.firstIndex(where: { $0.id == tapeID }) else { return }
        tapes[i].transcript = transcript
        save()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var stored = try? decoder.decode([Tape].self, from: data) else { return }
        // Drop entries whose audio has gone missing — the index follows the
        // files, never the other way round.
        stored.removeAll { !fm.fileExists(atPath: tapesDirectory.appendingPathComponent($0.fileName).path) }
        tapes = stored.sorted { $0.createdAt > $1.createdAt }
        selectedID = tapes.first?.id
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(tapes) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    // MARK: Storage

    func refreshStorage() {
        usedBytes = tapes.reduce(into: Int64(0)) { total, tape in
            let path = tapesDirectory.appendingPathComponent(tape.fileName).path
            if let attributes = try? fm.attributesOfItem(atPath: path),
               let size = attributes[.size] as? NSNumber {
                total += size.int64Value
            }
        }
        if let values = try? tapesDirectory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ) {
            freeBytes = Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        }
    }

    /// How much tape is left, in seconds, at the format currently in use.
    func remainingSeconds(sampleRate: Double, channels: Int) -> Double {
        let bytesPerSecond = sampleRate * Double(channels) * Double(AudioMachine.bitDepth / 8)
        guard bytesPerSecond > 0 else { return 0 }
        return Double(freeBytes) / bytesPerSecond
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useMB]
        f.countStyle = .file
        return f.string(fromByteCount: bytes).lowercased()
    }
}
