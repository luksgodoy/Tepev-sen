import SwiftUI
import UIKit

/// A 64 × 32 monochrome dot matrix — the same panel the hardware carries.
///
/// Everything the machine has to say fits in 2048 dots. That constraint is not
/// decoration: it is what keeps the interface honest. If a state cannot be
/// expressed in 64 × 32 dots, the machine does not have that state.
struct DotBitmap: Equatable {
    static let width = TE.Metric.displayDots.w   // 64
    static let height = TE.Metric.displayDots.h  // 32

    private(set) var dots: [Bool]

    init() {
        dots = Array(repeating: false, count: Self.width * Self.height)
    }

    // MARK: Primitives

    @inline(__always)
    mutating func set(_ x: Int, _ y: Int, _ on: Bool = true) {
        guard x >= 0, x < Self.width, y >= 0, y < Self.height else { return }
        dots[y * Self.width + x] = on
    }

    @inline(__always)
    func at(_ x: Int, _ y: Int) -> Bool {
        guard x >= 0, x < Self.width, y >= 0, y < Self.height else { return false }
        return dots[y * Self.width + x]
    }

    mutating func fill(x: Int, y: Int, w: Int, h: Int, on: Bool = true) {
        guard w > 0, h > 0 else { return }
        for yy in y..<(y + h) {
            for xx in x..<(x + w) { set(xx, yy, on) }
        }
    }

    mutating func frame(x: Int, y: Int, w: Int, h: Int) {
        guard w > 1, h > 1 else { return }
        for xx in x..<(x + w) { set(xx, y); set(xx, y + h - 1) }
        for yy in y..<(y + h) { set(x, yy); set(x + w - 1, yy) }
    }

    mutating func hLine(x: Int, y: Int, w: Int) { fill(x: x, y: y, w: w, h: 1) }
    mutating func vLine(x: Int, y: Int, h: Int) { fill(x: x, y: y, w: 1, h: h) }

    /// A dotted rule — every other dot, for separators that shouldn't shout.
    mutating func dottedRule(y: Int, from x0: Int = 0, to x1: Int = DotBitmap.width) {
        var x = x0
        while x < x1 { set(x, y); x += 2 }
    }

    // MARK: Composed elements

    enum HAlign { case left, center, right }

    /// Draw a line of text. Any script the phone can render, because the
    /// glyphs are rasterized by the system and then thresholded to dots —
    /// which is what makes transcription in most languages possible on a
    /// panel this small.
    mutating func text(
        _ string: String,
        x: Int = 0,
        y: Int = 0,
        size: CGFloat = 11,
        weight: UIFont.Weight = .medium,
        align: HAlign = .left,
        maxWidth: Int = DotBitmap.width
    ) {
        guard !string.isEmpty else { return }
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        guard let stamp = DotRasterizer.shared.raster(string, font: font, maxWidth: maxWidth) else { return }

        let ox: Int
        switch align {
        case .left:   ox = x
        case .center: ox = x + (maxWidth - stamp.width) / 2
        case .right:  ox = x + (maxWidth - stamp.width)
        }

        for yy in 0..<stamp.height {
            for xx in 0..<stamp.width where stamp.bits[yy * stamp.width + xx] {
                set(ox + xx, y + yy)
            }
        }
    }

    /// A horizontal progress bar. `value` is 0…1.
    mutating func bar(x: Int, y: Int, w: Int, h: Int, value: Double) {
        frame(x: x, y: y, w: w, h: h)
        let inner = w - 4
        guard inner > 0, h > 4 else { return }
        let filled = Int((Double(inner) * value.clamped(to: 0...1)).rounded())
        if filled > 0 { fill(x: x + 2, y: y + 2, w: filled, h: h - 4) }
    }

    /// A peak-hold level meter, drawn as vertical ticks like the hardware's.
    mutating func meter(x: Int, y: Int, w: Int, h: Int, level: Double, peak: Double) {
        let lit = Int((Double(w) * level.clamped(to: 0...1)).rounded())
        var i = 0
        while i < w {
            let on = i < lit
            // Segments get taller toward the right so clipping is unmistakable.
            let segH = max(1, Int((Double(h) * (0.45 + 0.55 * Double(i) / Double(max(w - 1, 1)))).rounded()))
            if on { fill(x: x + i, y: y + h - segH, w: 1, h: segH) }
            i += 2
        }
        let peakX = x + Int((Double(w - 1) * peak.clamped(to: 0...1)).rounded())
        vLine(x: peakX, y: y, h: h)
    }

    /// The tape position ruler: a full-width scale with a playhead caret.
    mutating func ruler(y: Int, position: Double) {
        hLine(x: 0, y: y + 3, w: Self.width)
        var x = 0
        while x < Self.width {
            vLine(x: x, y: y + (x % 20 == 0 ? 0 : 1), h: x % 20 == 0 ? 4 : 3)
            x += 4
        }
        let px = Int((Double(Self.width - 1) * position.clamped(to: 0...1)).rounded())
        vLine(x: px, y: y, h: 7)
        set(px - 1, y + 6); set(px + 1, y + 6)
    }

    /// Invert a region — the machine's only way of saying "this one".
    mutating func invert(x: Int, y: Int, w: Int, h: Int) {
        for yy in y..<(y + h) {
            for xx in x..<(x + w) { set(xx, yy, !at(xx, yy)) }
        }
    }
}

// MARK: - Rasterizer

/// Turns system-rendered glyphs into hard on/off dots.
///
/// Antialiasing and font smoothing are switched off and the result is
/// thresholded, so what lands on the panel is a true bilevel bitmap rather
/// than grey mush pretending to be one.
final class DotRasterizer {
    static let shared = DotRasterizer()

    struct Stamp {
        let width: Int
        let height: Int
        let bits: [Bool]
    }

    private var cache: [String: Stamp] = [:]
    private let colorSpace = CGColorSpaceCreateDeviceGray()
    /// Anything at or above this grey counts as a lit dot.
    private let threshold: UInt8 = 110

    func raster(_ string: String, font: UIFont, maxWidth: Int) -> Stamp? {
        let key = "\(string)|\(font.fontName)|\(font.pointSize)|\(maxWidth)"
        if let hit = cache[key] { return hit }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white,
            .kern: NSNumber(value: 0.0)
        ]
        let measured = (string as NSString).size(withAttributes: attrs)
        let w = min(maxWidth, max(1, Int(measured.width.rounded(.up))))
        let h = max(1, min(DotBitmap.height, Int(measured.height.rounded(.up))))

        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setShouldAntialias(false)
        ctx.setShouldSmoothFonts(false)
        ctx.setAllowsAntialiasing(false)
        ctx.setAllowsFontSmoothing(false)

        // Core Graphics is y-up, UIKit text drawing is y-down.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)

        UIGraphicsPushContext(ctx)
        (string as NSString).draw(
            with: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)),
            options: [.usesLineFragmentOrigin],
            attributes: attrs,
            context: nil
        )
        UIGraphicsPopContext()

        guard let base = ctx.data else { return nil }
        let rowBytes = ctx.bytesPerRow
        var bits = [Bool](repeating: false, count: w * h)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<h {
            for x in 0..<w {
                bits[y * w + x] = bytes[y * rowBytes + x] >= threshold
            }
        }

        let stamp = Stamp(width: w, height: h, bits: bits)
        if cache.count > 400 { cache.removeAll(keepingCapacity: true) }
        cache[key] = stamp
        return stamp
    }
}

// MARK: - The panel

/// The physical display: a recessed well, glass, and 2048 square dots.
struct DotMatrixDisplay: View {
    let bitmap: DotBitmap
    var finish: Finish = .aluminum
    /// Dims to standby brightness when the machine is idle.
    var brightness: Double = 1.0

    var body: some View {
        GeometryReader { geo in
            let dot = min(
                geo.size.width / CGFloat(DotBitmap.width),
                geo.size.height / CGFloat(DotBitmap.height)
            )
            let gridW = dot * CGFloat(DotBitmap.width)
            let gridH = dot * CGFloat(DotBitmap.height)
            let ox = (geo.size.width - gridW) / 2
            let oy = (geo.size.height - gridH) / 2
            // A hairline gap between dots — this is a matrix, not a screen.
            let inset = max(dot * 0.12, 0.35)

            Canvas(rendersAsynchronously: false) { ctx, _ in
                // Unlit dots first: the panel is visible even when it is off.
                var off = Path()
                var on = Path()
                for y in 0..<DotBitmap.height {
                    for x in 0..<DotBitmap.width {
                        let r = CGRect(
                            x: ox + CGFloat(x) * dot + inset,
                            y: oy + CGFloat(y) * dot + inset,
                            width: dot - inset * 2,
                            height: dot - inset * 2
                        )
                        if bitmap.at(x, y) { on.addRect(r) } else { off.addRect(r) }
                    }
                }
                ctx.fill(off, with: .color(TE.phosphorOff.opacity(0.55)))
                ctx.fill(on, with: .color(TE.phosphor.opacity(brightness)))
                // Emission bleeding into the glass.
                ctx.addFilter(.blur(radius: dot * 0.55))
                ctx.fill(on, with: .color(TE.phosphor.opacity(0.22 * brightness)))
            }
        }
        .background(TE.displayGlass)
        .recessed(finish, cornerRadius: 4, depth: 4)
        .overlay {
            // Glass: one soft reflection across the top third.
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.10), location: 0.0),
                    .init(color: .white.opacity(0.02), location: 0.32),
                    .init(color: .clear, location: 0.42)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}
