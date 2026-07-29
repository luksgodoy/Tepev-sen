import Foundation

/// Everything the machine has to say, in 64 × 32 dots.
///
/// One layout rule, borrowed from the hardware: the top strip always says
/// *which tape* and *what the transport is doing*, and never changes meaning.
/// The area below it belongs to whichever mode you last pressed the mode
/// button into. You can look away mid-take and look back knowing where you are.
extension DeviceState {

    var displayBitmap: DotBitmap {
        var d = DotBitmap()

        drawTopStrip(&d)
        d.dottedRule(y: 8)

        if let toast {
            d.text(toast, y: 13, size: 11, weight: .semibold, align: .center)
            return d
        }

        if isFiling {
            d.text("filing…", y: 13, size: 11, align: .center)
            return d
        }

        switch mode {
        case .tape:   drawTape(&d)
        case .level:  drawLevel(&d)
        case .speed:  drawSpeed(&d)
        case .input:  drawInput(&d)
        case .system: drawSystem(&d)
        }

        return d
    }

    // MARK: Top strip

    private func drawTopStrip(_ d: inout DotBitmap) {
        let title: String = {
            if machine.isRecording { return "rec" }
            return library.selected?.name ?? "no tape"
        }()
        d.text(title, x: 1, y: 0, size: 8, maxWidth: 50)
        drawTransportGlyph(&d, x: 55, y: 1)
    }

    private func drawTransportGlyph(_ d: inout DotBitmap, x: Int, y: Int) {
        switch machine.transport {
        case .recording:
            d.disc(cx: x + 3, cy: y + 3, r: 3)
        case .recordHold:
            // Armed but not capturing: the ring without the fill.
            d.ring(cx: x + 3, cy: y + 3, r: 3)
        case .playing:
            d.playTriangle(x: x + 1, y: y, size: 7)
        case .paused:
            d.fill(x: x + 1, y: y, w: 2, h: 7)
            d.fill(x: x + 5, y: y, w: 2, h: 7)
        case .stopped:
            d.fill(x: x + 1, y: y + 1, w: 5, h: 5)
        case .scratching:
            d.ring(cx: x + 3, cy: y + 3, r: 3)
            d.set(x + 3, y + 3)
        case .shuttling(let m):
            if m > 0 {
                d.playTriangle(x: x, y: y, size: 7)
                d.playTriangle(x: x + 4, y: y, size: 7)
            } else {
                d.playTriangleLeft(x: x, y: y, size: 7)
                d.playTriangleLeft(x: x + 4, y: y, size: 7)
            }
        }
    }

    // MARK: tape

    private func drawTape(_ d: inout DotBitmap) {
        let elapsed = machine.isRecording ? machine.recordedDuration : machine.position
        d.text(TimeCode.counter(elapsed), y: 9, size: 12, weight: .medium, align: .center)

        let total = machine.isRecording ? max(elapsed, 1) : max(machine.duration, 0.001)
        d.ruler(y: 25, position: elapsed / total)

        // Marks sit above the rule, as ticks you can aim the reel at.
        if let tape = library.selected, machine.duration > 0 {
            for mark in tape.marks {
                let px = Int((Double(DotBitmap.width - 1) * (mark / machine.duration).clamped(to: 0...1)).rounded())
                d.set(px, 24)
            }
        }
    }

    // MARK: level

    private func drawLevel(_ d: inout DotBitmap) {
        d.text("l", x: 0, y: 9, size: 8)
        d.meter(x: 7, y: 10, w: 56, h: 7, level: machine.level, peak: machine.peak)
        d.text("r", x: 0, y: 18, size: 8)
        d.meter(x: 7, y: 19, w: 56, h: 7, level: machine.level, peak: machine.peak)

        let db = machine.peak > 0.001
            ? Int((machine.peak * 54) - 54)
            : -60
        d.text(db <= -60 ? "-∞ db" : "\(db) db", y: 26, size: 8, align: .left, maxWidth: 40)
        if machine.inputMonitoring {
            d.text("mon", x: 44, y: 26, size: 8, maxWidth: 20)
        }
        // Clipping is the one thing a recorder must never let you miss.
        if machine.peak > 0.985 {
            d.invert(x: 0, y: 9, w: 64, h: 18)
        }
    }

    // MARK: speed

    private func drawSpeed(_ d: inout DotBitmap) {
        d.text(String(format: "%.2f×", machine.speed), y: 9, size: 12, weight: .medium, align: .center)
        // 0.25…4.0 laid out logarithmically, so 1× sits in the middle where
        // your thumb expects it.
        let t = (log2(machine.speed) + 2) / 4
        d.bar(x: 2, y: 24, w: 60, h: 7, value: t)
        // Nominal mark at 1×.
        d.set(32, 22); d.set(32, 23)
        if machine.pitchLock {
            d.text("lock", x: 44, y: 9, size: 8, maxWidth: 20)
        }
    }

    // MARK: input

    private func drawInput(_ d: inout DotBitmap) {
        let selected = jacks.jacks.first { $0.selected } ?? jacks.jacks[0]
        let name = selected.detail.isEmpty ? selected.id.legend : selected.detail
        d.text(name, y: 9, size: 10, align: .center)

        let rate = jacks.inputSampleRate
        let k = rate >= 1000 ? String(format: "%.4g", rate / 1000) + "k" : "\(Int(rate))"
        let ch = jacks.inputChannels >= 2 ? "st" : "mo"
        d.text("\(k) · \(AudioMachine.bitDepth)b · \(ch)", y: 20, size: 8, align: .center)

        // Four sockets along the bottom: filled means something is in it,
        // outlined with a dot means that is the one we are listening to.
        let n = JackID.allCases.count
        for (i, jack) in jacks.jacks.enumerated() {
            let x = 6 + i * (52 / max(n - 1, 1))
            if jack.connected {
                d.disc(cx: x, cy: 29, r: 2)
            } else {
                d.ring(cx: x, cy: 29, r: 2)
            }
            if jack.selected { d.hLine(x: x - 2, y: 31, w: 5) }
        }
    }

    // MARK: system

    private func drawSystem(_ d: inout DotBitmap) {
        d.text("\(TapeLibrary.formatBytes(library.freeBytes)) free", x: 1, y: 9, size: 8, maxWidth: 62)

        let capacity = Double(library.freeBytes + library.usedBytes)
        let used = capacity > 0 ? Double(library.usedBytes) / capacity : 0
        d.bar(x: 1, y: 19, w: 40, h: 7, value: used)

        // Battery, as a cell with pips.
        d.frame(x: 46, y: 19, w: 15, h: 7)
        d.fill(x: 61, y: 21, w: 1, h: 3)
        let pips = Int((batteryLevel * 11).rounded())
        if pips > 0 { d.fill(x: 48, y: 21, w: pips, h: 3) }

        let remaining = library.remainingSeconds(
            sampleRate: max(machine.actualSampleRate, 44_100),
            channels: max(machine.actualChannels, 1)
        )
        d.text("\(TimeCode.short(remaining)) of tape", x: 1, y: 24, size: 8, maxWidth: 62)
    }
}

// MARK: - Glyph primitives

extension DotBitmap {
    mutating func disc(cx: Int, cy: Int, r: Int) {
        let rr = Double(r) + 0.35
        for y in (cy - r)...(cy + r) {
            for x in (cx - r)...(cx + r) {
                let dx = Double(x - cx), dy = Double(y - cy)
                if dx * dx + dy * dy <= rr * rr { set(x, y) }
            }
        }
    }

    mutating func ring(cx: Int, cy: Int, r: Int) {
        let outer = Double(r) + 0.35
        let inner = Double(r) - 0.75
        for y in (cy - r)...(cy + r) {
            for x in (cx - r)...(cx + r) {
                let dx = Double(x - cx), dy = Double(y - cy)
                let d2 = dx * dx + dy * dy
                if d2 <= outer * outer && d2 >= inner * inner { set(x, y) }
            }
        }
    }

    mutating func playTriangle(x: Int, y: Int, size: Int) {
        let half = size / 2
        for row in 0..<size {
            let w = half + 1 - abs(row - half)
            guard w > 0 else { continue }
            fill(x: x, y: y + row, w: w, h: 1)
        }
    }

    mutating func playTriangleLeft(x: Int, y: Int, size: Int) {
        let half = size / 2
        for row in 0..<size {
            let w = half + 1 - abs(row - half)
            guard w > 0 else { continue }
            fill(x: x + (half + 1 - w), y: y + row, w: w, h: 1)
        }
    }
}
