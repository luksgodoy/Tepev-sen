import SwiftUI

/// The chassis surface: a single milled block of aluminum.
///
/// Three layers, in order — a vertical value gradient for the form, a fine
/// directional grain for the brushing, and a soft specular sweep so the metal
/// reads as metal when the phone tilts under a light.
struct BrushedMetal: View {
    var finish: Finish
    /// `.linear` for flat panels, `.radial` for the reel face.
    var grain: Grain = .linear
    var cornerRadius: CGFloat = 0
    /// 0…1, moves the specular highlight. Driven by the device motion sensor.
    var specular: Double = 0.5

    enum Grain { case linear, radial, none }

    var body: some View {
        let p = TE.palette(finish)

        ZStack {
            LinearGradient(
                colors: [p.bodyTop, p.bodyBottom],
                startPoint: .top,
                endPoint: .bottom
            )

            grainLayer(p)

            // Specular sweep — a wide, very soft band of light.
            GeometryReader { geo in
                let w = geo.size.width
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.00), location: 0.00),
                        .init(color: .white.opacity(finish == .black ? 0.06 : 0.16), location: 0.45),
                        .init(color: .white.opacity(0.00), location: 0.90)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: w * 1.8)
                .offset(x: (specular - 0.5) * w * 1.2 - w * 0.4)
                .blur(radius: 24)
                .blendMode(.plusLighter)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func grainLayer(_ p: TE.Palette) -> some View {
        switch grain {
        case .none:
            EmptyView()

        case .linear:
            // Horizontal brushing: the machine is brushed along its width.
            Canvas { ctx, size in
                var y: CGFloat = 0
                var seed: UInt64 = 0x9E3779B97F4A7C15
                while y < size.height {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    let r = Double((seed >> 33) & 0xFFFF) / 65535.0
                    let alpha = (r * 0.55 + 0.10) * p.grainOpacity
                    let step = 0.6 + r * 1.1
                    ctx.fill(
                        Path(CGRect(x: 0, y: y, width: size.width, height: 0.5)),
                        with: .color(p.grain.opacity(alpha))
                    )
                    y += step
                }
            }
            .blendMode(.overlay)

        case .radial:
            // The reel face is turned on a lathe, so its grain is circular.
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxR = min(size.width, size.height) / 2
                var r: CGFloat = maxR
                var seed: UInt64 = 0xD1B54A32D192ED03
                while r > 0 {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    let n = Double((seed >> 33) & 0xFFFF) / 65535.0
                    let alpha = (n * 0.50 + 0.08) * p.grainOpacity
                    var path = Path()
                    path.addEllipse(in: CGRect(
                        x: c.x - r, y: c.y - r, width: r * 2, height: r * 2
                    ))
                    ctx.stroke(path, with: .color(p.grain.opacity(alpha)), lineWidth: 0.5)
                    r -= 0.7 + CGFloat(n) * 1.0
                }
            }
            .blendMode(.overlay)
        }
    }
}

// MARK: - Milled edges

/// A machined edge: light catches the top chamfer, shadow pools at the bottom.
struct MilledEdge: ViewModifier {
    var finish: Finish
    var cornerRadius: CGFloat
    var lineWidth: CGFloat = 1

    func body(content: Content) -> some View {
        let p = TE.palette(finish)
        content.overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [p.edgeHighlight, p.edgeShadow],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: lineWidth
                )
        }
    }
}

/// A recess cut into the chassis: shadow at the top lip, light bounced off
/// the bottom of the pit.
struct Recessed: ViewModifier {
    var finish: Finish
    var cornerRadius: CGFloat
    var depth: CGFloat = 3

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(finish == .black ? 0.85 : 0.42),
                                Color.white.opacity(finish == .black ? 0.10 : 0.45)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: depth * 0.55
                    )
                    .blur(radius: depth * 0.25)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    func milledEdge(_ finish: Finish, cornerRadius: CGFloat, lineWidth: CGFloat = 1) -> some View {
        modifier(MilledEdge(finish: finish, cornerRadius: cornerRadius, lineWidth: lineWidth))
    }

    func recessed(_ finish: Finish, cornerRadius: CGFloat, depth: CGFloat = 3) -> some View {
        modifier(Recessed(finish: finish, cornerRadius: cornerRadius, depth: depth))
    }
}
