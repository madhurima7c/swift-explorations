import SwiftUI

// MARK: - Paper texture

/// Multi-layer realistic paper: base tint + fibre speckles + soft
/// vignette.  The `vignette` flag lets callers opt OUT of the radial
/// darkening — important when the texture is masked to a small region
/// (like the back of a paper curl), because the vignette's outer ring
/// would otherwise show as a visible darker edge around the mask.
struct PaperTexture: View {
    var vignette: Bool = true

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let hSpacing: CGFloat = 2.05
            let vSpacing: CGFloat = 13.5
            let grainOpacity: CGFloat = 0.84
            let speckleOpacity: CGFloat = 0.64
            let m = min(size.width, size.height)

            ZStack {
            MailDesign.paper

            // Slight sheet tone variation (“tooth”) — avoids flat vector white.
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.99, green: 0.992, blue: 1.0).opacity(0.22), location: 0),
                    .init(color: .clear, location: 0.35),
                    .init(color: MailDesign.paperWarm.opacity(0.12), location: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.softLight)
            .opacity(0.60)

            // Horizontal linen grain — primary fibre direction.
            Canvas { ctx, size in
                var rng = SeededGenerator(seed: 7)
                let rows = Int(size.height / hSpacing)
                for r in 0..<rows {
                    let y = CGFloat(r) * hSpacing + CGFloat.random(in: -0.45...0.45, using: &rng)
                    let alpha = CGFloat.random(in: 0.008...0.022, using: &rng)
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(p, with: .color(.black.opacity(Double(alpha))),
                               style: StrokeStyle(lineWidth: 0.55))
                }
            }
            .blendMode(.multiply)
            .opacity(grainOpacity)

            // Vertical laid-paper striations.
            Canvas { ctx, size in
                var rng = SeededGenerator(seed: 93)
                let cols = Int(size.width / vSpacing)
                for c in 0..<cols {
                    let x = CGFloat(c) * vSpacing + CGFloat.random(in: -1...1, using: &rng)
                    let alpha = CGFloat.random(in: 0.0035...0.009, using: &rng)
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(p, with: .color(.black.opacity(Double(alpha))),
                               style: StrokeStyle(lineWidth: 0.45))
                }
            }
            .blendMode(.multiply)
            .opacity(0.45)

            // Fine fibre speckles.
            Canvas { context, size in
                let step: CGFloat = 4.2
                var rng = SeededGenerator(seed: 41)
                for x in Swift.stride(from: 0, to: size.width, by: step) {
                    for y in Swift.stride(from: 0, to: size.height, by: step) {
                        let jitterX = CGFloat.random(in: -1.0...1.0, using: &rng)
                        let jitterY = CGFloat.random(in: -1.0...1.0, using: &rng)
                        let alpha   = CGFloat.random(in: 0.012...0.030, using: &rng)
                        let r: CGFloat = CGFloat.random(in: 0.4...0.85, using: &rng)
                        var path = Path()
                        path.addEllipse(in: CGRect(x: x + jitterX, y: y + jitterY, width: r, height: r))
                        context.fill(path, with: .color(.black.opacity(Double(alpha))))
                    }
                }
            }
            .blendMode(.multiply)
            .opacity(speckleOpacity)

            // Short diagonal pulp flecks.
            Canvas { ctx, size in
                var rng = SeededGenerator(seed: 101)
                let count = Int((size.width * size.height) / 4200)
                for _ in 0..<max(24, count) {
                    let cx = CGFloat.random(in: 0...size.width, using: &rng)
                    let cy = CGFloat.random(in: 0...size.height, using: &rng)
                    let len = CGFloat.random(in: 2.2...5.5, using: &rng)
                    let ang = CGFloat.random(in: -0.35...0.35, using: &rng)
                    let alpha = CGFloat.random(in: 0.004...0.014, using: &rng)
                    var p = Path()
                    p.move(to: CGPoint(x: cx - cos(ang) * len, y: cy - sin(ang) * len))
                    p.addLine(to: CGPoint(x: cx + cos(ang) * len, y: cy + sin(ang) * len))
                    ctx.stroke(p, with: .color(.black.opacity(Double(alpha))),
                               style: StrokeStyle(lineWidth: 0.35, lineCap: .round))
                }
            }
            .blendMode(.multiply)
            .opacity(0.7)

            // Vignette — warm edge, cool centre.  Skipped when the
            // texture will be masked to a partial region of the paper.
            if vignette {
                RadialGradient(
                    colors: [.clear,
                             MailDesign.paperWarm.opacity(0.24)],
                    center: .center,
                    startRadius: m * 0.24,
                    endRadius: m * 0.66
                )
                .blendMode(.multiply)
                .allowsHitTesting(false)
            }
            }
            .frame(width: size.width, height: size.height)
        }
        .allowsHitTesting(false)
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0xDEADBEEF : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - Outside-only card shadow (no inward bleed through curl holes)

/// Blurred fills are masked so alpha exists **only outside** the rounded
/// card silhouette — same idea as a contact shadow in design tools.
/// Critical when `CardMinusCurlShape` cuts a hole: inner shadow spill
/// cannot appear because we never draw shadow inside the rect at all.
///
/// Exposed (not private) so the stack can render every card's shadow in
/// a single layer above, and apply one collective mask that punches the
/// top sheet's curl pocket out of every lower sheet's shadow.
struct LetterCardOutsideShadow: View {
    let size: CGSize
    let cornerRadius: CGFloat
    /// When set and active, the pocket under the curl (plus a blur halo)
    /// is punched out of the shadow mask so the **perimeter** shadow ring
    /// cannot bleed into the lifted corner like a grey slab.
    var curlPunchOut: PageCurlGeometry?
    /// >1 when 2+ letters are stacked (see `LetterCardView.stackCount`).
    var opacityScale: Double = 1.0

    var body: some View {
        let s = min(opacityScale, 1.25)
        ZStack(alignment: .topLeading) {
            layer(
                opacity: MailDesign.cardOutsideShadowTightOpacity * s,
                blur: MailDesign.cardOutsideShadowTightBlur,
                offsetY: MailDesign.cardOutsideShadowTightY
            )
            layer(
                opacity: MailDesign.cardOutsideShadowMidOpacity * s,
                blur: MailDesign.cardOutsideShadowMidBlur,
                offsetY: MailDesign.cardOutsideShadowMidY
            )
            layer(
                opacity: MailDesign.cardOutsideShadowSoftOpacity * s,
                blur: MailDesign.cardOutsideShadowSoftBlur,
                offsetY: MailDesign.cardOutsideShadowSoftY
            )
        }
    }

    private func layer(opacity: Double, blur: CGFloat, offsetY: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.black.opacity(opacity))
            .frame(width: size.width, height: size.height)
            .blur(radius: blur)
            .offset(y: offsetY)
            .compositingGroup()
            .mask(shadowMask)
    }

    private var shadowMask: some View {
        let layoutRect = CGRect(origin: .zero, size: size)
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.black)
                .frame(width: size.width + 120, height: size.height + 120)
                .offset(x: -60, y: -60)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black)
                .frame(width: size.width, height: size.height)
                .scaleEffect(1.0035, anchor: .center)
                .blendMode(.destinationOut)

            if let c = curlPunchOut, c.isActive {
                // Blurred `destinationOut` punch must not be **layout-clipped** to
                // the card rect before the blur: that truncates the feather at
                // the top/edge (esp. top-left curl) and can leave a vertical
                // band of **leftover ring mask** in the sky — a “mystery shadow”.
                // Padding → blur → padding gives the filter room (standard SwiftUI).
                let b = MailDesign.cardShadowCurlPunchBlur
                c.curlShadowExclusionPath(in: layoutRect)
                    .fill(Color.black)
                    .padding(-b)
                    .blur(radius: b)
                    .padding(b)
                    .blendMode(.destinationOut)
            }
        }
        .frame(width: size.width, height: size.height)
        .compositingGroup()
    }
}

// MARK: - Subtle “desk lamp” on the face (stops the sheet reading as a flat swatch)

private struct PaperFaceLighting: View {
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        // Layered, reference-style depth: one broad diagonal + a specular
        // puddle (top-left) and a very soft far-corner falloff — all kept
        // inside the card so we don’t add extra global shadows / mask risk.
        return ZStack {
            shape
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.40), location: 0.0),
                            .init(color: Color.white.opacity(0.11), location: 0.18),
                            .init(color: .clear, location: 0.48),
                            .init(color: Color.black.opacity(0.04), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.softLight)
            shape
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.24),
                            Color.white.opacity(0.06),
                            .clear
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .blendMode(.softLight)
            shape
                .fill(
                    RadialGradient(
                        colors: [
                            .clear,
                            Color.black.opacity(0.05)
                        ],
                        center: .bottomTrailing,
                        startRadius: 40,
                        endRadius: 220
                    )
                )
                .blendMode(.multiply)
                .opacity(0.85)
            shape
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0.55), location: 0.0),
                                    .init(color: .clear, location: 0.5),
                                    .init(color: .black.opacity(0.055), location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Contact shade from the sheet above (stack depth)

private struct StackUpperSheetShade: View {
    let cornerRadius: CGFloat
    /// Slightly >1 when several sheets are visible so the step reads.
    var strength: CGFloat = 1.0

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                // Tight band under the **overlap** — like light blocked where the
                // higher sheet actually rests, not a broad wash over the page.
                RadialGradient(
                    stops: [
                        .init(color: .black.opacity(0.05 * strength), location: 0),
                        .init(color: .black.opacity(0.02 * strength), location: 0.22),
                        .init(color: .clear, location: 1)
                    ],
                    center: .top,
                    startRadius: 0,
                    endRadius: 78
                )
            )
            .blendMode(.multiply)
            .allowsHitTesting(false)
    }
}

// MARK: - Letter card

struct LetterCardView: View {
    let letter: Letter
    var isInteractive: Bool
    var translation: CGSize
    var fingerLocal: CGPoint?
    /// Corner captured at touch-down. Stable for the duration of the
    /// drag so the curl never flips sides mid-gesture.
    var lockedCurlCorner: CurlCorner?
    var stackIndexFromTop: Int
    /// Inbox’s current letter count — used to add depth when 2+ sheets overlap.
    var stackCount: Int = 1
    var cardLayoutSize: CGSize
    var fadeProgress: CGFloat = 0
    /// When false, the outside stack shadow is omitted so the parent
    /// can render every card's shadow together in one masked layer.
    /// Necessary to punch the top sheet's curl pocket out of lower
    /// sheets' shadows without also erasing their bodies.
    var drawsOutsideShadow: Bool = true

    private var stackDepthScale: Double {
        stackCount > 1 ? 1.14 : 1.0
    }

    private var upperSheetShadeStrength: CGFloat {
        stackCount > 1 && stackIndexFromTop > 0 ? 1.22 : 1.0
    }

    /// The curl is only active on the top card while a finger is down.
    private var curl: PageCurlGeometry {
        guard stackIndexFromTop == 0 else {
            return PageCurlGeometry(
                origin: nil,
                lockedCorner: nil,
                cardSize: cardLayoutSize,
                cornerRadius: MailDesign.cardCorner,
                intensity: 0
            )
        }
        // Intensity grows with the drag magnitude, but we show a hint of
        // curl as soon as the finger touches so the lift feels responsive.
        let drag = min(1, max(0, hypot(translation.width, translation.height) / 160))
        let intensity: CGFloat = fingerLocal == nil ? 0 : (0.42 + 0.58 * drag)
        return PageCurlGeometry(
            origin: fingerLocal,
            lockedCorner: lockedCurlCorner,
            cardSize: cardLayoutSize,
            cornerRadius: MailDesign.cardCorner,
            intensity: intensity
        )
    }

    var body: some View {
        let curl = self.curl
        let cornerRadius = MailDesign.cardCorner

        // The front of the card is the rounded rect MINUS the curl region →
        // that area becomes a hole so the next card / background is revealed
        // behind the curled paper.
        let bodyShape = CardMinusCurlShape(curl: curl, cornerRadius: cornerRadius)

        // Every card casts its own native path-following drop shadow so the
        // stack reads as real paper: each sheet shadows onto the one below,
        // and the back-most sheet shadows onto the sky.
        ZStack(alignment: .topLeading) {
            // Outside-only shadow — never paints inside the card rect. When a
            // curl is active, we also punch pocket ∪ flap (blurred) out of the
            // mask so the edge shadow ring cannot bleed behind the fold.
            // Skipped when the parent is rendering shadows itself in a
            // separately-masked layer (see `MailInboxScreen.outsideShadowLayer`).
            if drawsOutsideShadow {
                LetterCardOutsideShadow(
                    size: cardLayoutSize,
                    cornerRadius: cornerRadius,
                    curlPunchOut: (stackIndexFromTop == 0 && curl.isActive) ? curl : nil,
                    opacityScale: stackDepthScale
                )
            }

            // The actual paper body — cut by the flap, TRULY transparent
            // where the curl lifts so the next card shows through.
            bodyShape
                .fill(MailDesign.paper)

            PaperFaceLighting(cornerRadius: cornerRadius)
                .clipShape(bodyShape)
                .allowsHitTesting(false)

            PaperTexture(vignette: true)
                .clipShape(bodyShape)
                .allowsHitTesting(false)

            if stackIndexFromTop > 0 {
                StackUpperSheetShade(
                    cornerRadius: cornerRadius,
                    strength: upperSheetShadeStrength
                )
                .clipShape(bodyShape)
                .allowsHitTesting(false)
            }

            // Hairline outline — applied to EVERY card so the stack
            // reads as distinct layered sheets instead of one card
            // floating above a shadow ghost.  Clipped to `bodyShape`
            // (card silhouette minus the curl flap) so the stroke
            // can never draw past the card's own edge, which
            // prevents the lower cards from painting stray lines
            // outside the top card's silhouette.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(MailDesign.cardOutlineColor, lineWidth: 1)
                .clipShape(bodyShape)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 10) {
                // 1. Subject (bold, largest line on the page)
                Text(letter.subject)
                    .font(LetterTypography.letterSemibold(15))
                    .foregroundStyle(MailDesign.ink)
                    .fixedSize(horizontal: false, vertical: true)

                // 2. From: email … day  (single row, baseline-aligned)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(letter.fromLabel)
                        .font(LetterTypography.letterRegular(13))
                        .foregroundStyle(MailDesign.secondary)

                    Text(letter.fromEmail)
                        .font(LetterTypography.letterRegular(13))
                        .foregroundStyle(MailDesign.link)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 8)

                    Text(letter.dateLabel)
                        .font(LetterTypography.letterRegular(13))
                        .foregroundStyle(MailDesign.secondary)
                }

                // 3. Separator under the From row — very light hairline; the
                // 10% black previously read as a hard rule.
                Rectangle()
                    .fill(.black.opacity(0.055))
                    .frame(height: 1)
                    .padding(.top, 12)

                // 4. Body copy — fills the remaining vertical space and
                // truncates with "…" if the letter is too long to fit.
                Text(letter.body)
                    .font(LetterTypography.letterRegular(13))
                    .foregroundStyle(MailDesign.ink)
                    .lineSpacing(2.5)
                    .multilineTextAlignment(.leading)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity,
                           maxHeight: .infinity,
                           alignment: .topLeading)
                    .padding(.top, 16)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity,
                   maxHeight: .infinity,
                   alignment: .topLeading)
            .clipShape(bodyShape)            // text disappears where the flap lifts

            // Curl renderer — shadow + card back + fold highlight. Drawn on
            // top so it sits above the card content.
            PageCurlView(curl: curl)
        }
        .frame(width: cardLayoutSize.width, height: cardLayoutSize.height)
        // No rotation3DEffect here — that was making the text appear to
        // "slide" between lines during the drag.  The paper only
        // translates and rotates (2D) from the parent view.  The curl
        // itself is the only local deformation of the paper surface.
        .opacity(1 - min(max(fadeProgress, 0), 1))
        .allowsHitTesting(isInteractive)
    }
}
