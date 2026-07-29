import Foundation

enum Waveform {
    /// Reduce the scrub copy to a fixed number of peaks.
    ///
    /// Derived from the low-rate mono track that already exists, so drawing a
    /// tape costs one file pass, not two. `count` is fixed rather than
    /// proportional to length: a waveform is a shape, and a shape does not get
    /// more informative by being longer than the screen.
    static func peaks(from scrub: ScrubTrack, count: Int = 480) -> [Float] {
        let samples = scrub.samples
        guard !samples.isEmpty, count > 0 else { return [] }

        var out = [Float](repeating: 0, count: count)
        let bucket = Double(samples.count) / Double(count)

        for i in 0..<count {
            let lo = Int(Double(i) * bucket)
            let hi = min(samples.count, max(lo + 1, Int(Double(i + 1) * bucket)))
            var peak: Float = 0
            var j = lo
            while j < hi {
                let a = abs(samples[j])
                if a > peak { peak = a }
                j += 1
            }
            out[i] = peak
        }

        // Normalize to the loudest moment on the tape, so a whispered memo and
        // a live band both fill the window.
        if let loudest = out.max(), loudest > 0.0001 {
            for i in 0..<count { out[i] = min(1, out[i] / loudest) }
        }
        return out
    }

    /// Sample the peak array at a normalized position, for drawing at any width.
    static func value(_ peaks: [Float], at position: Double) -> Float {
        guard !peaks.isEmpty else { return 0 }
        let i = Int((position.clamped(to: 0...1) * Double(peaks.count - 1)).rounded())
        return peaks[i]
    }
}
