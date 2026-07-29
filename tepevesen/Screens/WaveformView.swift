import SwiftUI

/// A tape, drawn.
///
/// Centre-mirrored bars at a fixed count, so a ten-second memo and a two-hour
/// interview are the same shape on screen and you learn to read them the same
/// way. Played-through is solid, ahead is faint, marks are full-height ticks.
struct WaveformView: View {
    @Environment(\.finish) private var finish

    var peaks: [Float]
    /// 0…1
    var progress: Double = 0
    var marks: [Double] = []
    var accent: Color = TE.rec
    /// Called with a normalized position when the strip is scrubbed.
    var onScrub: ((Double) -> Void)?

    var body: some View {
        GeometryReader { geo in
            let p = TE.palette(finish)
            let w = geo.size.width
            let h = geo.size.height
            let barW: CGFloat = 2
            let gap: CGFloat = 1
            let count = max(1, Int(w / (barW + gap)))

            Canvas { ctx, size in
                var behind = Path()
                var ahead = Path()
                let headX = size.width * CGFloat(progress.clamped(to: 0...1))

                for i in 0..<count {
                    let t = Double(i) / Double(max(count - 1, 1))
                    let v = CGFloat(Waveform.value(peaks, at: t))
                    // A floor, so silence is still a line rather than a gap.
                    let barH = max(1.5, v * size.height * 0.92)
                    let x = CGFloat(i) * (barW + gap)
                    let rect = CGRect(
                        x: x,
                        y: (size.height - barH) / 2,
                        width: barW,
                        height: barH
                    )
                    if x <= headX { behind.addRect(rect) } else { ahead.addRect(rect) }
                }

                ctx.fill(ahead, with: .color(p.legend.opacity(0.35)))
                ctx.fill(behind, with: .color(accent))

                for mark in marks {
                    let x = size.width * CGFloat(mark.clamped(to: 0...1))
                    ctx.fill(
                        Path(CGRect(x: x, y: 0, width: 1, height: size.height)),
                        with: .color(p.legend.opacity(0.9))
                    )
                }
            }
            .frame(width: w, height: h)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard let onScrub else { return }
                        onScrub(Double(value.location.x / max(w, 1)).clamped(to: 0...1))
                    }
            )
        }
    }
}
