import SwiftUI

/// The finish of the chassis. The hardware ships in brushed aluminum and
/// black anodized aluminum; so does this.
enum Finish: String, CaseIterable, Codable, Identifiable {
    case aluminum
    case black

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aluminum: return "aluminum"
        case .black:    return "black"
        }
    }
}

/// Every colour, metric and type ramp in the machine.
///
/// The rule the whole design follows: the chassis is one continuous piece of
/// metal, everything sitting on it is either a recess (darker, inner shadow)
/// or a raised control (lighter top edge, shadow below). There is exactly one
/// saturated colour in the entire product and it means "recording".
enum TE {

    // MARK: - Chassis

    struct Palette {
        let bodyTop: Color
        let bodyBottom: Color
        /// The fine directional grain of the brushed surface.
        let grain: Color
        let grainOpacity: Double
        /// Engraved silkscreen legends.
        let legend: Color
        /// Milled edges catching light.
        let edgeHighlight: Color
        let edgeShadow: Color
        /// Raised control caps.
        let capTop: Color
        let capBottom: Color
        let capLegend: Color
        /// Recessed wells (display bezel, jacks, reel pit).
        let wellTop: Color
        let wellBottom: Color
    }

    static func palette(_ finish: Finish) -> Palette {
        switch finish {
        case .aluminum:
            return Palette(
                bodyTop:       Color(hex: 0xD8DAD6),
                bodyBottom:    Color(hex: 0xB6B9B4),
                grain:         .white,
                grainOpacity:  0.30,
                legend:        Color(hex: 0x6E7370),
                edgeHighlight: Color.white.opacity(0.75),
                edgeShadow:    Color.black.opacity(0.22),
                capTop:        Color(hex: 0xF0F1EE),
                capBottom:     Color(hex: 0xCFD1CC),
                capLegend:     Color(hex: 0x5A5F5C),
                wellTop:       Color(hex: 0x8E918C),
                wellBottom:    Color(hex: 0xB0B3AE)
            )
        case .black:
            return Palette(
                bodyTop:       Color(hex: 0x24262A),
                bodyBottom:    Color(hex: 0x121316),
                grain:         .white,
                grainOpacity:  0.11,
                legend:        Color(hex: 0x8A8F93),
                edgeHighlight: Color.white.opacity(0.20),
                edgeShadow:    Color.black.opacity(0.60),
                capTop:        Color(hex: 0x3A3D42),
                capBottom:     Color(hex: 0x1E2024),
                capLegend:     Color(hex: 0xC8CCCF),
                wellTop:       Color(hex: 0x08090A),
                wellBottom:    Color(hex: 0x1A1C1F)
            )
        }
    }

    // MARK: - The one colour

    /// Record. Nothing else in the product is allowed to be this colour.
    static let rec = Color(hex: 0xFF4A17)
    /// The display's lit dots.
    static let phosphor = Color(hex: 0xF2F4EF)
    /// The display's dark, unlit dots.
    static let phosphorOff = Color(hex: 0x101112)
    /// Glass over the display well.
    static let displayGlass = Color(hex: 0x0A0B0C)
    /// A control that is live but not recording (armed, connected, playing).
    static let live = Color(hex: 0xEAECE8)

    // MARK: - Metrics

    enum Metric {
        /// Corner radius of the chassis itself.
        static let chassisRadius: CGFloat = 30
        /// Radius of the raised transport caps.
        static let capRadius: CGFloat = 12
        /// The gap the whole layout is built on.
        static let gutter: CGFloat = 14
        /// Height of a transport cap.
        static let capHeight: CGFloat = 62
        /// The display is 64 × 32 dots. Everything else is measured against it.
        static let displayDots = (w: 64, h: 32)
    }

    // MARK: - Type
    //
    // The hardware is silkscreened in a lowercase geometric grotesk at two
    // sizes: a legend size for control labels and a slightly larger size for
    // the product name. There is no third size and there are no capitals.

    enum Type_ {
        static func legend(_ size: CGFloat = 9) -> Font {
            .system(size: size, weight: .medium, design: .default)
        }
        static func mono(_ size: CGFloat = 11) -> Font {
            .system(size: size, weight: .medium, design: .monospaced)
        }
        static func wordmark(_ size: CGFloat = 13) -> Font {
            .system(size: size, weight: .semibold, design: .default)
        }
    }
}

// MARK: - Silkscreen

/// An engraved legend on the chassis: lowercase, wide-tracked, low contrast.
struct Legend: View {
    let text: String
    var size: CGFloat = 9
    var color: Color?
    var tracking: CGFloat = 1.1

    @Environment(\.finish) private var finish

    var body: some View {
        Text(text.lowercased())
            .font(TE.Type_.legend(size))
            .tracking(tracking)
            .foregroundStyle(color ?? TE.palette(finish).legend)
    }
}

// MARK: - Environment

private struct FinishKey: EnvironmentKey {
    static let defaultValue: Finish = .aluminum
}

extension EnvironmentValues {
    var finish: Finish {
        get { self[FinishKey.self] }
        set { self[FinishKey.self] = newValue }
    }
}

// MARK: - Helpers

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >>  8) & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
