import Foundation
import Speech
import Combine

/// Turns a tape into text.
///
/// Choose a language, press transcribe. Where the phone can do it on-device the
/// machine insists on it, and says so — a dentist's patient notes and a
/// journalist's source have no business leaving the device to become a
/// transcript. Where the language is only available over the network, the
/// machine says that too, before it sends anything.
@MainActor
final class Transcriber: ObservableObject {

    enum State: Equatable {
        case idle
        case denied
        case running(progress: Double)
        case failed(String)
        case done
    }

    @Published private(set) var state: State = .idle
    /// Text as it arrives, so the display has something to say while it works.
    @Published private(set) var partial: String = ""

    /// Languages this phone can recognize, sorted by name, with the current
    /// one first.
    static var supportedLocales: [Locale] {
        let all = SFSpeechRecognizer.supportedLocales().map { Locale(identifier: $0.identifier) }
        let currentID = Locale.current.identifier
        return all.sorted { a, b in
            if a.identifier == currentID { return true }
            if b.identifier == currentID { return false }
            return name(for: a) < name(for: b)
        }
    }

    static func name(for locale: Locale) -> String {
        (Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
            .lowercased()
    }

    /// Whether the whole job can be done without the tape leaving the phone.
    static func canRunOnDevice(_ locale: Locale) -> Bool {
        SFSpeechRecognizer(locale: locale)?.supportsOnDeviceRecognition ?? false
    }

    private var task: SFSpeechRecognitionTask?

    // MARK: Permission

    func requestAuthorization() async -> Bool {
        let status = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        if status != .authorized { state = .denied }
        return status == .authorized
    }

    // MARK: Run

    func cancel() {
        task?.cancel()
        task = nil
        if case .running = state { state = .idle }
    }

    /// `duration` is only used to turn segment timings into a progress figure.
    func transcribe(url: URL, locale: Locale, duration: Double) async -> Transcript? {
        guard await requestAuthorization() else { return nil }

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            state = .failed("\(Self.name(for: locale)) unavailable")
            return nil
        }

        let onDevice = recognizer.supportsOnDeviceRecognition
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = onDevice
        request.addsPunctuation = true
        request.taskHint = .dictation

        partial = ""
        state = .running(progress: 0)

        let result: SFSpeechRecognitionResult?
        do {
            result = try await withCheckedThrowingContinuation { continuation in
                var finished = false
                self.task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                    guard !finished else { return }

                    if let error {
                        finished = true
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let result else { return }

                    if result.isFinal {
                        finished = true
                        continuation.resume(returning: result)
                    } else {
                        let text = result.bestTranscription.formattedString
                        let reached = result.bestTranscription.segments.last
                            .map { $0.timestamp + $0.duration } ?? 0
                        Task { @MainActor in
                            guard let self else { return }
                            self.partial = text
                            let p = duration > 0 ? (reached / duration).clamped(to: 0...1) : 0
                            self.state = .running(progress: p)
                        }
                    }
                }
            }
        } catch {
            state = .failed(error.localizedDescription.lowercased())
            task = nil
            return nil
        }

        task = nil
        guard let result else {
            state = .failed("no speech found")
            return nil
        }

        let best = result.bestTranscription
        let segments = best.segments.map {
            TranscriptSegment(
                text: $0.substring,
                start: $0.timestamp,
                duration: $0.duration,
                confidence: $0.confidence
            )
        }

        state = .done
        partial = best.formattedString

        return Transcript(
            localeIdentifier: locale.identifier,
            segments: segments,
            text: best.formattedString,
            onDevice: onDevice,
            createdAt: Date()
        )
    }
}
