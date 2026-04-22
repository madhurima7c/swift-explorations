import SwiftUI

// MARK: - Dynamic page curl
//
// Four‑layer page curl driven by the user's touch position. The curl
// originates from wherever the finger contacts the card; the nearest corner
// anchors it. Layers, bottom‑to‑top:
//
//   1. Crease contact   — tight blur *only* along the fold (no full-pocket
//                        multiply, which tints the card below and reads as
//                        a flat grey box).
//   2. Card back        — roll shading + bright outer rim, like real paper.
//   3. Card front hole  — handled outside (`CardMinusCurlShape`).
//   4. Fold highlight   — specular along the crease.

/// Size of the curled corner, in points.
let kCurlSize: CGFloat = 118

enum CurlCorner {
    case topLeft, topRight, bottomLeft, bottomRight
}

// MARK: - Geometry
//
// A curl always anchors at the nearest corner of the card. The flap is an
// asymmetric region bounded by two slightly different edge lengths
// (`reachA` on the horizontal edge, `reachB` on the vertical edge) plus a
// quadratic fold‑line so the bend reads as a natural paper curve, not a
// sharp 45° triangle.  The card's rounded corner is preserved — the arc
// travels with the lifted corner onto the mirrored flap.

struct PageCurlGeometry {
    /// Finger / touch location in card‑local space.  `nil` → curl inactive.
    var origin: CGPoint?
    /// The anchor corner, captured on touch‑down and LOCKED for the
    /// duration of the drag so the curl never flips sides mid-gesture.
    /// `nil` means "fall back to nearest corner to `origin`".
    var lockedCorner: CurlCorner?
    var cardSize: CGSize
    var cornerRadius: CGFloat = 2
    var curlSize: CGFloat = kCurlSize
    /// 0 … 1. The curl grows with this value.
    var intensity: CGFloat

    var isActive: Bool {
        origin != nil && intensity > 0.02 && cardSize.width > 0
    }

    // MARK: Corner selection

    var cornerKind: CurlCorner {
        if let locked = lockedCorner { return locked }
        guard let o = origin else { return .bottomRight }
        let leftish = o.x < cardSize.width / 2
        let topish  = o.y < cardSize.height / 2
        switch (leftish, topish) {
        case (true,  true):  return .topLeft
        case (false, true):  return .topRight
        case (true,  false): return .bottomLeft
        case (false, false): return .bottomRight
        }
    }

    var corner: CGPoint {
        switch cornerKind {
        case .topLeft:     return .zero
        case .topRight:    return CGPoint(x: cardSize.width, y: 0)
        case .bottomLeft:  return CGPoint(x: 0, y: cardSize.height)
        case .bottomRight: return CGPoint(x: cardSize.width, y: cardSize.height)
        }
    }

    // MARK: Reach
    //
    // Size scales with `intensity` only. We deliberately do NOT rescale
    // based on finger XY relative to the corner — that made the flap
    // breathe/ripple as the finger moved, reading as jitter. A slight
    // built‑in asymmetry (reachA slightly longer than reachB) gives the
    // curl a natural hand‑lifted look without being noisy.
    var effective: CGFloat {
        let maxReach = min(cardSize.width, cardSize.height) * 0.55
        return min(maxReach, curlSize * min(1, max(0, intensity)))
    }

    var reachA: CGFloat { effective * 1.05 }   // horizontal edge — a touch longer
    var reachB: CGFloat { effective * 0.95 }   // vertical edge

    // MARK: Fold axis endpoints

    /// Axis endpoint on the horizontal edge adjacent to `corner`.
    var pA: CGPoint {
        switch cornerKind {
        case .topLeft:     return CGPoint(x: reachA, y: 0)
        case .topRight:    return CGPoint(x: cardSize.width - reachA, y: 0)
        case .bottomLeft:  return CGPoint(x: reachA, y: cardSize.height)
        case .bottomRight: return CGPoint(x: cardSize.width - reachA, y: cardSize.height)
        }
    }

    /// Axis endpoint on the vertical edge adjacent to `corner`.
    var pB: CGPoint {
        switch cornerKind {
        case .topLeft:     return CGPoint(x: 0, y: reachB)
        case .topRight:    return CGPoint(x: cardSize.width, y: reachB)
        case .bottomLeft:  return CGPoint(x: 0, y: cardSize.height - reachB)
        case .bottomRight: return CGPoint(x: cardSize.width, y: cardSize.height - reachB)
        }
    }

    /// Where the physical corner lands once the paper flips across the fold
    /// axis.  (Reflection of `corner` across pA↔pB.)
    var mirroredCorner: CGPoint {
        // Simple reflection across the line through (pA, pB).
        let ax = pB.x - pA.x, ay = pB.y - pA.y
        let len2 = max(0.0001, ax * ax + ay * ay)
        let vx = corner.x - pA.x, vy = corner.y - pA.y
        let t  = (vx * ax + vy * ay) / len2
        let projX = pA.x + t * ax
        let projY = pA.y + t * ay
        return CGPoint(x: 2 * projX - corner.x, y: 2 * projY - corner.y)
    }

    /// Midpoint of the fold axis.
    var foldMid: CGPoint {
        CGPoint(x: (pA.x + pB.x) / 2, y: (pA.y + pB.y) / 2)
    }

    /// Control point that bows the fold axis toward the lifted corner so
    /// the bend reads as a natural curve (not a straight 45° line).
    /// Kept *very* subtle to avoid flap jitter.
    var foldControl: CGPoint {
        CGPoint(
            x: foldMid.x + (corner.x - foldMid.x) * 0.22,
            y: foldMid.y + (corner.y - foldMid.y) * 0.22
        )
    }

    /// Unit vector from the fold axis toward the mirrored tip.
    var mirrorDirection: CGVector {
        let dx = mirroredCorner.x - foldMid.x
        let dy = mirroredCorner.y - foldMid.y
        let m  = max(0.0001, sqrt(dx * dx + dy * dy))
        return CGVector(dx: dx / m, dy: dy / m)
    }

    // MARK: Paths

    /// Region of the card that has been lifted — this is the HOLE.
    ///
    /// Traces along the horizontal edge from pA, arcs around the card's
    /// rounded corner, continues along the vertical edge to pB, then bows
    /// back to pA along the (curved) fold axis.  Keeps the rounded corner
    /// silhouette intact.
    var flapPath: Path {
        var p = Path()
        let r = min(cornerRadius, min(reachA, reachB) * 0.5)

        switch cornerKind {
        case .topLeft:
            p.move(to: pA)                                          // on top edge
            p.addLine(to: CGPoint(x: r, y: 0))
            p.addArc(
                center: CGPoint(x: r, y: r),
                radius: r,
                startAngle: .degrees(270),
                endAngle:   .degrees(180),
                clockwise:  true
            )
            p.addLine(to: pB)                                       // down left edge
        case .topRight:
            p.move(to: pA)
            p.addLine(to: CGPoint(x: cardSize.width - r, y: 0))
            p.addArc(
                center: CGPoint(x: cardSize.width - r, y: r),
                radius: r,
                startAngle: .degrees(270),
                endAngle:   .degrees(0),
                clockwise:  false
            )
            p.addLine(to: pB)
        case .bottomLeft:
            p.move(to: pA)
            p.addLine(to: CGPoint(x: r, y: cardSize.height))
            p.addArc(
                center: CGPoint(x: r, y: cardSize.height - r),
                radius: r,
                startAngle: .degrees(90),
                endAngle:   .degrees(180),
                clockwise:  false
            )
            p.addLine(to: pB)
        case .bottomRight:
            p.move(to: pA)
            p.addLine(to: CGPoint(x: cardSize.width - r, y: cardSize.height))
            p.addArc(
                center: CGPoint(x: cardSize.width - r, y: cardSize.height - r),
                radius: r,
                startAngle: .degrees(90),
                endAngle:   .degrees(0),
                clockwise:  true
            )
            p.addLine(to: pB)
        }

        // Close along the (bowed) fold axis.
        p.addQuadCurve(to: pA, control: foldControl)
        return p
    }

    /// The mirrored flap — what you see as the back of the curl.
    ///
    /// Built by rotating the original corner + two edges 180° across the
    /// fold axis. The rounded corner is preserved on the tip of the lifted
    /// flap → the silhouette of the curl stays rounded.
    var mirrorPath: Path {
        // Mirrored anchor points of the card-corner arc's tangents.
        let r = min(cornerRadius, min(reachA, reachB) * 0.5)

        let tangentEdgeA: CGPoint  // where the straight edge meets the arc
        let tangentEdgeB: CGPoint  // same on the other adjacent edge
        switch cornerKind {
        case .topLeft:
            tangentEdgeA = CGPoint(x: r, y: 0)
            tangentEdgeB = CGPoint(x: 0, y: r)
        case .topRight:
            tangentEdgeA = CGPoint(x: cardSize.width - r, y: 0)
            tangentEdgeB = CGPoint(x: cardSize.width, y: r)
        case .bottomLeft:
            tangentEdgeA = CGPoint(x: r, y: cardSize.height)
            tangentEdgeB = CGPoint(x: 0, y: cardSize.height - r)
        case .bottomRight:
            tangentEdgeA = CGPoint(x: cardSize.width - r, y: cardSize.height)
            tangentEdgeB = CGPoint(x: cardSize.width, y: cardSize.height - r)
        }

        let mTangentA = reflect(point: tangentEdgeA)
        let mTangentB = reflect(point: tangentEdgeB)
        let mCorner   = mirroredCorner

        var p = Path()
        p.move(to: pA)
        p.addQuadCurve(to: pB, control: foldControl)   // bowed fold axis
        p.addLine(to: mTangentB)

        // Arc that was the card's original rounded corner — now on the tip
        // of the lifted flap. We approximate it as a quadratic curve with
        // control at the mirrored corner.
        p.addQuadCurve(to: mTangentA, control: mCorner)
        p.addLine(to: pA)
        p.closeSubpath()
        _ = r
        return p
    }

    private func reflect(point q: CGPoint) -> CGPoint {
        let ax = pB.x - pA.x, ay = pB.y - pA.y
        let len2 = max(0.0001, ax * ax + ay * ay)
        let vx = q.x - pA.x, vy = q.y - pA.y
        let t  = (vx * ax + vy * ay) / len2
        let projX = pA.x + t * ax
        let projY = pA.y + t * ay
        return CGPoint(x: 2 * projX - q.x, y: 2 * projY - q.y)
    }
}

// MARK: - Layout-space paths (critical for masks / subtracting)

extension PageCurlGeometry {
    /// Maps a path defined in `cardSize` coordinates into `rect` (SwiftUI
    /// `Shape.path(in:)` often uses a `rect` that is not 0,0,cardSize).
    private func pathInLayout(_ path: Path, rect: CGRect) -> Path {
        let sx = rect.width / max(cardSize.width, 1)
        let sy = rect.height / max(cardSize.height, 1)
        var t = CGAffineTransform(a: sx, b: 0, c: 0, d: sy, tx: rect.minX, ty: rect.minY)
        guard let cg = path.cgPath.copy(using: &t) else { return Path() }
        return Path(cg)
    }

    func flapPath(in rect: CGRect) -> Path {
        pathInLayout(flapPath, rect: rect)
    }

    func mirroredFlapPath(in rect: CGRect) -> Path {
        pathInLayout(mirrorPath, rect: rect)
    }

    /// Pocket + lifted flap in layout space — used to soften-erase card
    /// shadow in the curl region (filled + blurred, not stroked).
    func curlShadowExclusionPath(in rect: CGRect) -> Path {
        let cg = CGMutablePath()
        cg.addPath(flapPath(in: rect).cgPath)
        cg.addPath(mirroredFlapPath(in: rect).cgPath)
        return Path(cg)
    }
}

// MARK: - Card minus curl shape
//
// Clips the card's front so the curl area is a transparent hole — the next
// card in the stack / the page background shows through where the paper is
// lifted.

struct CardMinusCurlShape: Shape {
    var curl: PageCurlGeometry
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var card = Path()
        card.addRoundedRect(
            in: rect,
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
        )
        guard curl.isActive else { return card }
        let flapInRect = curl.flapPath(in: rect)
        if #available(iOS 16.0, *) {
            return Path(card.cgPath.subtracting(flapInRect.cgPath))
        }
        return card
    }
}

/// The rounded‑rect card silhouette — used for clipping shadows & texture
/// to the card bounds so nothing leaks outside the paper.
struct CardOuterShape: Shape {
    var cornerRadius: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRoundedRect(in: rect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
        return p
    }
}

// MARK: - Renderer

struct PageCurlView: View {
    var curl: PageCurlGeometry

    var body: some View {
        ZStack {
            if curl.isActive {
                creaseContactLayer
            }

            // The flap itself — solid paper, volumetric shading, edge
            // outline. No compositing-group shadow here because that was
            // causing the blurred shadow to bleed through the flap
            // interior and turn the back black.
            backLayer
                .clipShape(CardOuterShape(cornerRadius: curl.cornerRadius))

            // Thin edge + fold highlight last so they sit on top of shading.
            highlightLayer
                .clipShape(CardOuterShape(cornerRadius: curl.cornerRadius))
        }
        .allowsHitTesting(false)
    }

    /// Tight contact shadow *only* at the fold — adds pocket depth without
    /// a rectangle of multiply that bleeds over the next card in the stack.
    @ViewBuilder
    private var creaseContactLayer: some View {
        if curl.isActive {
            let fold: Path = {
                var p = Path()
                p.move(to: curl.pA)
                p.addQuadCurve(to: curl.pB, control: curl.foldControl)
                return p
            }()
            Canvas { ctx, _ in
                ctx.stroke(
                    fold,
                    with: .color(.black.opacity(0.22)),
                    lineWidth: 1.2
                )
            }
            .frame(width: curl.cardSize.width, height: curl.cardSize.height)
            .blur(radius: 4.5)
            .blendMode(.multiply)
            .mask(
                ZStack(alignment: .topLeading) {
                    Color.black
                    curl.mirrorPath
                        .fill(Color.black)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
            )
            .clipShape(CardOuterShape(cornerRadius: curl.cornerRadius))
        }
    }

    // 1. Card back — white paper with controlled curvature shading:
    //    subtle crease darkening + soft belly highlight (no dark-tip band).
    @ViewBuilder
    private var backLayer: some View {
        if curl.isActive {
            let sz = curl.cardSize
            let dx = curl.mirroredCorner.x - curl.foldMid.x
            let dy = curl.mirroredCorner.y - curl.foldMid.y
            let start = CGPoint(x: curl.foldMid.x + dx * 0.05,
                                y: curl.foldMid.y + dy * 0.05)
            let end   = CGPoint(x: curl.foldMid.x + dx * 0.95,
                                y: curl.foldMid.y + dy * 0.95)

            ZStack {
                Canvas { ctx, _ in
                    // (a) Paper base — cool white (underside of sheet).
                    ctx.fill(curl.mirrorPath,
                             with: .color(Color(red: 0.988, green: 0.988, blue: 0.985)))

                    // (b) Deeper at the crease, opening toward the outer roll (volume).
                    ctx.fill(
                        curl.mirrorPath,
                        with: .linearGradient(
                            Gradient(stops: [
                                .init(color: .black.opacity(0.20), location: 0.00),
                                .init(color: .black.opacity(0.07),  location: 0.28),
                                .init(color: .black.opacity(0.04),  location: 0.55),
                                .init(color: .black.opacity(0.02),  location: 0.82),
                                .init(color: .clear,               location: 1.00),
                            ]),
                            startPoint: start,
                            endPoint: end
                        )
                    )

                    // (c) Rim light at the **outer** arc — real paper is brightest
                    // on the edge that catches the light (reference), not a flat slab.
                    let tip = curl.mirroredCorner
                    let tipR = max(18, min(curl.reachA, curl.reachB) * 0.5)
                    ctx.fill(
                        curl.mirrorPath,
                        with: .radialGradient(
                            Gradient(stops: [
                                .init(color: .white.opacity(0.62), location: 0.0),
                                .init(color: .white.opacity(0.20), location: 0.32),
                                .init(color: .clear,               location: 0.72),
                            ]),
                            center: tip,
                            startRadius: 0,
                            endRadius: tipR
                        )
                    )

                    // (d) Radial “tube” between crease and tip — body of the roll.
                    let rollCenter = CGPoint(
                        x: curl.foldMid.x + dx * 0.30,
                        y: curl.foldMid.y + dy * 0.30
                    )
                    let rollR = max(30, hypot(dx, dy) * 0.50)
                    ctx.fill(
                        curl.mirrorPath,
                        with: .radialGradient(
                            Gradient(stops: [
                                .init(color: .clear,               location: 0.0),
                                .init(color: .white.opacity(0.40), location: 0.40),
                                .init(color: .white.opacity(0.10), location: 0.82),
                                .init(color: .clear,               location: 1.0),
                            ]),
                            center: rollCenter,
                            startRadius: 2,
                            endRadius: rollR
                        )
                    )

                    // (e) Tight specular along the roll axis.
                    ctx.fill(
                        curl.mirrorPath,
                        with: .linearGradient(
                            Gradient(stops: [
                                .init(color: .clear,               location: 0.10),
                                .init(color: .white.opacity(0.64), location: 0.46),
                                .init(color: .white.opacity(0.20), location: 0.74),
                                .init(color: .clear,               location: 1.00),
                            ]),
                            startPoint: start,
                            endPoint: end
                        )
                    )

                    // (f) Edge — separates roll from the hole; slightly darker helps depth.
                    ctx.stroke(curl.mirrorPath,
                               with: .color(.black.opacity(0.14)),
                               lineWidth: 0.55)
                }

                // Same fibre treatment as the face — reads as one sheet.
                PaperTexture(vignette: false)
                    .mask(curl.mirrorPath)
                    .opacity(0.48)
                    .allowsHitTesting(false)
            }
            .frame(width: sz.width, height: sz.height)
            .allowsHitTesting(false)
        }
    }

    // 2. Fold highlight — crease ridge catch-light.
    @ViewBuilder
    private var highlightLayer: some View {
        if curl.isActive {
            Canvas { ctx, _ in
                let fold = Path { p in
                    p.move(to: curl.pA)
                    p.addQuadCurve(to: curl.pB, control: curl.foldControl)
                }
                ctx.stroke(
                    fold,
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: .clear,                location: 0.00),
                            .init(color: .white.opacity(0.50), location: 0.50),
                            .init(color: .clear,                location: 1.00),
                        ]),
                        startPoint: curl.pA,
                        endPoint:   curl.pB
                    ),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
                )
            }
        }
    }
}
