import SwiftUI

/// The hover treatment, shared by anything that can be pointed at: the surface
/// rises off the canvas, keeps its beige, and a pink glitter diffusion blooms
/// around its edges.
///
/// Applied to cards and to sidebar rows, so hovering feels identical
/// everywhere rather than being reinvented per surface.
public struct HoverGlow: ViewModifier {
    private let isActive: Bool
    private let cornerRadius: CGFloat
    private let lift: CGFloat

    public init(isActive: Bool, cornerRadius: CGFloat, lift: CGFloat = 6) {
        self.isActive = isActive
        self.cornerRadius = cornerRadius
        self.lift = lift
    }

    public func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    // The soft bloom: a blurred pink field bleeding out past
                    // the edges.
                    RoundedRectangle(cornerRadius: cornerRadius + 8, style: .continuous)
                        .fill(Chamfer.Palette.pink)
                        .blur(radius: 30)
                        // Kept deliberately soft: a stronger bloom drowns the
                        // specks and the diffusion stops reading as glitter.
                        .opacity(isActive ? 0.30 : 0)
                        .scaleEffect(isActive ? 1.02 : 0.95)
                    // The glitter: individual specks twinkling in that field.
                    if isActive {
                        GlitterHalo()
                    }
                }
                .padding(-Self.halo)
                .allowsHitTesting(false)
            }
            .offset(y: isActive ? -lift : 0)
            .shadow(
                color: .black.opacity(isActive ? 0.22 : 0.06),
                radius: isActive ? 26 : 7,
                y: isActive ? 16 : 3
            )
            .shadow(
                color: Chamfer.Palette.pink.opacity(isActive ? 0.30 : 0),
                radius: 20,
                y: 8
            )
            .animation(Chamfer.Motion.lift, value: isActive)
    }

    /// How far the diffusion reaches past the edge of the surface.
    static let halo: CGFloat = 30
}

public extension View {
    /// Rises, shadows and blooms pink while `isActive`.
    func chamferHoverGlow(isActive: Bool, cornerRadius: CGFloat, lift: CGFloat = 6) -> some View {
        modifier(HoverGlow(isActive: isActive, cornerRadius: cornerRadius, lift: lift))
    }
}

/// Specks of pink scattered in the band just outside the surface, each
/// twinkling on its own clock.
private struct GlitterHalo: View {
    private let count = 110

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { graphics, size in
                let time = context.date.timeIntervalSinceReferenceDate
                let inset = HoverGlow.halo
                let inner = CGRect(
                    x: inset,
                    y: inset,
                    width: max(0, size.width - inset * 2),
                    height: max(0, size.height - inset * 2)
                )

                for index in 0..<count {
                    let point = CGPoint(
                        x: noise(index, 1) * size.width,
                        y: noise(index, 2) * size.height
                    )
                    // Only the band outside the surface glitters; the card
                    // face itself stays clean beige.
                    guard !inner.insetBy(dx: -1, dy: -1).contains(point) else { continue }

                    let radius = 0.8 + noise(index, 3) * 2.4
                    let speed = 1.1 + noise(index, 4) * 2.6
                    let phase = noise(index, 5) * 6.283
                    let twinkle = 0.25 + 0.75 * abs(sin(time * speed + phase))
                    let distance = distanceOutside(point, from: inner)
                    // Fade with distance so the diffusion has an edge.
                    let falloff = max(0, 1 - distance / inset)
                    // A minority of specks burn brighter, which is what reads
                    // as glitter rather than as a flat pink mist.
                    let isHot = noise(index, 6) > 0.72

                    let dot = CGRect(
                        x: point.x - radius,
                        y: point.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    graphics.fill(
                        Path(ellipseIn: dot),
                        with: .color(
                            (isHot ? Chamfer.Palette.pinkSoft : Chamfer.Palette.pink)
                                .opacity(twinkle * falloff * (isHot ? 1 : 0.8))
                        )
                    )
                }
            }
            .blur(radius: 0.35)
        }
    }

    private func distanceOutside(_ point: CGPoint, from rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return sqrt(dx * dx + dy * dy)
    }

    /// Deterministic pseudo-random so specks do not jump between frames.
    private func noise(_ index: Int, _ salt: Int) -> CGFloat {
        var value = UInt64(bitPattern: Int64(index &* 374_761_393 &+ salt &* 668_265_263))
        value ^= value >> 13
        value = value &* 1_274_126_177
        value ^= value >> 16
        return CGFloat(value % 10_000) / 10_000
    }
}
