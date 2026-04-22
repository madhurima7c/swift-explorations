import SwiftUI

// MARK: - PRNG

private struct PRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0xC0FFEE : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - Crumpling snapshot
//
// Progressive visible crumpling of the card snapshot. Six rotated/translated
// copies blended with `.multiply` create folded regions; a Canvas layer adds
// random dark/light creases; a radial pit darkens the centre as the paper
// collapses. All parameters animate with `progress` (0 = flat, 1 = ball).
struct CrumplingImage: View {
    let image: UIImage
    var progress: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                layer(index: i)
            }
            creases
            // Progressive darkening as the sheet balls up.
            Color.black
                .opacity(Double(progress) * 0.22)
                .blendMode(.multiply)
                .allowsHitTesting(false)
        }
    }

    private func layer(index i: Int) -> some View {
        let phase = Double(i) / 8.0
        let p = Double(progress)
        // Front-loaded easing so meaningful deformation starts at ~p = 0.15
        // rather than accumulating linearly.  You actually SEE crumpling
        // before the ball takes over.
        let pf = CGFloat(pow(p, 0.65))

        let rot = sin(phase * .pi * 2 + p * 3.4) * 52 * Double(pf)
        let dx  = cos(phase * .pi * 2 + p * 1.3) * 24 * pf
        let dy  = sin(phase * .pi * 2 + p * 1.7) * 22 * pf
        let s   = 1 - 0.42 * pf - 0.08 * CGFloat(i) * pf
        let alpha: Double = i == 0
            ? 1
            : max(0.0, 0.78 - Double(i) * 0.08) * Double(pf)

        return Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .rotationEffect(.degrees(rot))
            .scaleEffect(s)
            .offset(x: dx, y: dy)
            .opacity(alpha)
            .blendMode(i == 0 ? .normal : .multiply)
    }

    private var creases: some View {
        Canvas { ctx, size in
            guard progress > 0.05 else { return }
            let p = Double(progress)
            var rng = PRNG(seed: 0x5EEDA)

            let darkCount = Int(28 * p)
            for _ in 0..<darkCount {
                let x1 = CGFloat.random(in: 0...size.width, using: &rng)
                let y1 = CGFloat.random(in: 0...size.height, using: &rng)
                let len: CGFloat = CGFloat.random(in: 30...105, using: &rng)
                let ang: CGFloat = CGFloat.random(in: 0...(2 * .pi), using: &rng)
                var path = Path()
                path.move(to: CGPoint(x: x1, y: y1))
                path.addLine(to: CGPoint(x: x1 + cos(ang) * len, y: y1 + sin(ang) * len))
                ctx.stroke(path,
                           with: .color(.black.opacity(0.16 * p)),
                           style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
            }

            let lightCount = Int(16 * p)
            for _ in 0..<lightCount {
                let x1 = CGFloat.random(in: 0...size.width, using: &rng)
                let y1 = CGFloat.random(in: 0...size.height, using: &rng)
                let len: CGFloat = CGFloat.random(in: 18...52, using: &rng)
                let ang: CGFloat = CGFloat.random(in: 0...(2 * .pi), using: &rng)
                var path = Path()
                path.move(to: CGPoint(x: x1, y: y1))
                path.addLine(to: CGPoint(x: x1 + cos(ang) * len, y: y1 + sin(ang) * len))
                ctx.stroke(path,
                           with: .color(.white.opacity(0.32 * p)),
                           style: StrokeStyle(lineWidth: 0.5, lineCap: .round))
            }

            let r = min(size.width, size.height) * 0.48
            let centre = CGRect(x: size.width / 2 - r, y: size.height / 2 - r,
                                width: r * 2, height: r * 2)
            let pit = Path(ellipseIn: centre)
            ctx.fill(
                pit,
                with: .radialGradient(
                    Gradient(colors: [.black.opacity(0.28 * p), .clear]),
                    center: CGPoint(x: centre.midX, y: centre.midY),
                    startRadius: 0,
                    endRadius: r
                )
            )
        }
        .blendMode(.multiply)
    }
}

// MARK: - Live crumple (no snapshot required)
//
// Equivalent visual to `CrumplingImage` but operates on an arbitrary SwiftUI
// view rather than a UIImage. Used as a fallback when `ImageRenderer` fails
// to capture a static snapshot.
struct CrumplingView<Content: View>: View {
    var progress: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        let built = content()
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                layer(built: built, index: i)
            }
            creases
            Color.black
                .opacity(Double(progress) * 0.22)
                .blendMode(.multiply)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func layer(built: Content, index i: Int) -> some View {
        let phase = Double(i) / 8.0
        let p = Double(progress)
        let pf = CGFloat(pow(p, 0.65))
        let rot = sin(phase * .pi * 2 + p * 3.4) * 52 * Double(pf)
        let dx = cos(phase * .pi * 2 + p * 1.3) * 24 * pf
        let dy = sin(phase * .pi * 2 + p * 1.7) * 22 * pf
        let s = 1 - 0.42 * pf - 0.08 * CGFloat(i) * pf
        let alpha: Double = i == 0
            ? 1
            : max(0.0, 0.78 - Double(i) * 0.08) * Double(pf)

        built
            .rotationEffect(.degrees(rot))
            .scaleEffect(s)
            .offset(x: dx, y: dy)
            .opacity(alpha)
            .blendMode(i == 0 ? .normal : .multiply)
    }

    private var creases: some View {
        Canvas { ctx, size in
            guard progress > 0.05 else { return }
            let p = Double(progress)
            var rng = PRNG(seed: 0x5EEDA)
            let darkCount = Int(28 * p)
            for _ in 0..<darkCount {
                let x1 = CGFloat.random(in: 0...size.width, using: &rng)
                let y1 = CGFloat.random(in: 0...size.height, using: &rng)
                let len: CGFloat = CGFloat.random(in: 30...105, using: &rng)
                let ang: CGFloat = CGFloat.random(in: 0...(2 * .pi), using: &rng)
                var path = Path()
                path.move(to: CGPoint(x: x1, y: y1))
                path.addLine(to: CGPoint(x: x1 + cos(ang) * len, y: y1 + sin(ang) * len))
                ctx.stroke(path,
                           with: .color(.black.opacity(0.16 * p)),
                           style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
            }
            let lightCount = Int(16 * p)
            for _ in 0..<lightCount {
                let x1 = CGFloat.random(in: 0...size.width, using: &rng)
                let y1 = CGFloat.random(in: 0...size.height, using: &rng)
                let len: CGFloat = CGFloat.random(in: 18...52, using: &rng)
                let ang: CGFloat = CGFloat.random(in: 0...(2 * .pi), using: &rng)
                var path = Path()
                path.move(to: CGPoint(x: x1, y: y1))
                path.addLine(to: CGPoint(x: x1 + cos(ang) * len, y: y1 + sin(ang) * len))
                ctx.stroke(path,
                           with: .color(.white.opacity(0.32 * p)),
                           style: StrokeStyle(lineWidth: 0.5, lineCap: .round))
            }
            let r = min(size.width, size.height) * 0.48
            let centre = CGRect(x: size.width / 2 - r, y: size.height / 2 - r,
                                width: r * 2, height: r * 2)
            let pit = Path(ellipseIn: centre)
            ctx.fill(
                pit,
                with: .radialGradient(
                    Gradient(colors: [.black.opacity(0.28 * p), .clear]),
                    center: CGPoint(x: centre.midX, y: centre.midY),
                    startRadius: 0,
                    endRadius: r
                )
            )
        }
        .blendMode(.multiply)
    }
}

// MARK: - Simplified snapshot view
//
// A deliberately simple representation of a letter for the trash crumple —
// just the paper colour, subject, and body text. Using this for
// `ImageRenderer` guarantees we get a valid UIImage (Canvas content
// sometimes doesn't make it through the renderer) and it gives the crumple
// enough visible "paper detail" to read as a real letter being crushed.
struct SimpleLetterSnapshot: View {
    let letter: Letter
    let size: CGSize
    var cornerRadius: CGFloat = MailDesign.cardCorner

    var body: some View {
        // IMPORTANT: this layout MUST mirror `LetterCardView`'s internal
        // VStack — same order, same fonts — otherwise the trash crumple
        // renders a letter whose hierarchy suddenly flips (subject below
        // the From row) the moment the sheet is snapshotted.
        //
        //   1 · Subject  (15 pt semibold)
        //   2 · From row (13 pt, email link, date right-aligned)
        //   3 · 1 pt separator
        //   4 · Body     (13 pt)
        VStack(alignment: .leading, spacing: 10) {
            Text(letter.subject)
                .font(LetterTypography.letterSemibold(15))
                .foregroundStyle(MailDesign.ink)
                .fixedSize(horizontal: false, vertical: true)

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

            Rectangle()
                .fill(.black.opacity(0.10))
                .frame(height: 1)
                .padding(.top, 2)

            Text(letter.body)
                .font(LetterTypography.letterRegular(13))
                .foregroundStyle(MailDesign.ink)
                .lineSpacing(2.5)
                .multilineTextAlignment(.leading)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity,
                       maxHeight: .infinity,
                       alignment: .topLeading)
                .padding(.top, 6)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 28)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(MailDesign.paper)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(MailDesign.cardOutlineColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - PaperCrumple (fully procedural)
//
// A single-sheet crumple rendered entirely in code — no PNG assets.
// The view composes:
//   1. A morphing silhouette polygon (rounded rectangle → irregular
//      "balled-up" polygon) driven by progress.
//   2. A volumetric light gradient across the silhouette so the paper
//      as a whole reads as a 3-D object lit from the upper-left.
//   3. A deterministic field of "fold features" — shadow valleys,
//      highlight ridges, crease lines, and specular streaks — whose
//      positions/angles/sizes are seeded once but whose size &
//      opacity scale smoothly with progress.
//   4. A radial ambient-occlusion darkening near the silhouette edge.
//   5. A thin rim stroke so the paper silhouette reads cleanly
//      against the background.
//
// Because every random value is produced from the same seed in the
// same order every frame, the pattern is perfectly stable — nothing
// flickers, and the paper *grows* its crumple rather than reshuffling
// it as progress increases.
//
// Letter content is drawn underneath (fading out as the crumple
// fades in) so the real text is what you see at low progress and
// the procedural crumple is what you see once the paper is crushed.
struct PaperCrumple: View {
    let letter: Letter
    let size: CGSize
    /// 0 = pristine sheet, 1 = fully formed paper ball.
    var progress: CGFloat

    var body: some View {
        let p = min(max(progress, 0), 1)

        // The letter is now baked into the 3-D mesh's diffuse
        // texture, so text creases and deforms with every fold —
        // no separate overlay, no double text, no crossfade to
        // hide.  A very short opacity ramp is applied so the view
        // doesn't "pop" if it's mounted mid-gesture.
        Paper3DCrumpleView(
            letter: letter,
            size: size,
            progress: p
        )
        .frame(width: size.width, height: size.height)
        // Single drop shadow travels with the sheet — no halo, no
        // double shadows.  Intensifies as the paper balls up.
        .shadow(
            color: .black.opacity(0.10 + 0.14 * Double(p)),
            radius: 6 + 4 * Double(p),
            x: 0,
            y: 3 + 4 * Double(p)
        )
    }

    // MARK: - Canvas drawing

    private func drawCrumple(ctx: GraphicsContext,
                             size: CGSize,
                             progress p: CGFloat) {
        var rng = PRNG(seed: 0xBADF00D_CAFE_C0DE)

        // --- 1 · Silhouette morph: rounded-rect → irregular ball ----
        let vertexCount = 26
        let corner: CGFloat = MailDesign.cardCorner
        let ballRadius = min(size.width, size.height) / 2 * 0.84
        let cx = size.width / 2
        let cy = size.height / 2

        // Pre-generate per-vertex jitter so the ball polygon is the
        // same every frame.
        let jitter: [CGFloat] = (0..<vertexCount).map { _ in
            CGFloat.random(in: 0.78...1.08, using: &rng)
        }

        var silhouette: [CGPoint] = []
        for i in 0..<vertexCount {
            let t = Double(i) / Double(vertexCount) * 2 * .pi
            let ux = CGFloat(cos(t))
            let uy = CGFloat(sin(t))

            // Rest position — point on the rounded-rect perimeter at
            // angle t (ray-cast from centre, clamped to corners).
            let rest = roundedRectPerimeter(angle: t,
                                            halfW: size.width / 2,
                                            halfH: size.height / 2,
                                            corner: corner)

            // Balled position — inside a circle of radius `ballRadius`
            // with per-vertex jitter for organic irregularity.
            let ball = CGPoint(x: cx + ux * ballRadius * jitter[i],
                               y: cy + uy * ballRadius * jitter[i])

            let pt = CGPoint(x: rest.x + (ball.x - rest.x) * p,
                             y: rest.y + (ball.y - rest.y) * p)
            silhouette.append(pt)
        }

        // Build the silhouette path (use quadratic midpoints for a
        // slightly smoother outline rather than hard polygonal edges).
        var silPath = Path()
        silPath.move(to: midpoint(silhouette[vertexCount - 1], silhouette[0]))
        for i in 0..<vertexCount {
            let curr = silhouette[i]
            let next = silhouette[(i + 1) % vertexCount]
            silPath.addQuadCurve(to: midpoint(curr, next), control: curr)
        }
        silPath.closeSubpath()

        // --- 2 · Paper base fill -----------------------------------
        ctx.fill(silPath, with: .color(MailDesign.paper))

        // --- 3 · Volumetric light gradient (upper-left → lower-right)
        // Gives the whole sheet a sense of dimensional shading even
        // before the fold features are drawn on top.
        ctx.fill(silPath, with: .linearGradient(
            Gradient(stops: [
                .init(color: .white.opacity(0.16 * Double(p) + 0.03),
                      location: 0.00),
                .init(color: .clear, location: 0.48),
                .init(color: .black.opacity(0.18 * Double(p) + 0.02),
                      location: 1.00)
            ]),
            startPoint: CGPoint(x: size.width * 0.18, y: size.height * 0.12),
            endPoint:   CGPoint(x: size.width * 0.86, y: size.height * 0.92)
        ))

        // --- 4 · Fold features (shadows, highlights, creases, spec) -
        // All features are drawn inside a clip to the silhouette so
        // anything that falls outside (as the paper balls up) is
        // cleanly masked off.
        ctx.drawLayer { layer in
            layer.clip(to: silPath)

            drawShadowBlobs(ctx: layer, size: size, progress: p, rng: &rng)
            drawHighlightBlobs(ctx: layer, size: size, progress: p, rng: &rng)
            drawCreases(ctx: layer, size: size, progress: p, rng: &rng)
            drawSpecularStreaks(ctx: layer, size: size, progress: p, rng: &rng)
        }

        // --- 5 · Rim darkening (ambient occlusion at the edges) -----
        // Radial gradient from clear centre to dark edge, clipped to
        // silhouette so the "shadow" follows the paper's shape.
        ctx.drawLayer { layer in
            layer.clip(to: silPath)
            layer.fill(
                Rectangle().path(in: CGRect(origin: .zero, size: size)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: .clear, location: 0.00),
                        .init(color: .clear, location: 0.52),
                        .init(color: .black.opacity(0.24 * Double(p)),
                              location: 1.00)
                    ]),
                    center: CGPoint(x: cx, y: cy),
                    startRadius: 0,
                    endRadius: min(size.width, size.height) * 0.58
                )
            )
        }

        // --- 6 · Rim stroke ----------------------------------------
        ctx.stroke(silPath,
                   with: .color(.black.opacity(0.18 + 0.08 * Double(p))),
                   style: StrokeStyle(lineWidth: 0.8, lineJoin: .round))
    }

    // MARK: · Fold feature passes

    /// Dark elongated gradient blobs — the valleys between folds.
    private func drawShadowBlobs(ctx: GraphicsContext,
                                 size: CGSize,
                                 progress p: CGFloat,
                                 rng: inout PRNG) {
        let count = 18
        for i in 0..<count {
            let cx = size.width  * CGFloat.random(in: 0.08...0.92, using: &rng)
            let cy = size.height * CGFloat.random(in: 0.08...0.92, using: &rng)
            let angle = CGFloat.random(in: 0...(2 * .pi), using: &rng)
            let minDim = min(size.width, size.height)
            let len = CGFloat.random(in: 0.16...0.42, using: &rng) * minDim
            let wid = len * CGFloat.random(in: 0.24...0.42, using: &rng)
            // Bias shadows slightly toward the lower-right (light from UL).
            let bias = 0.6 + 0.4 * (CGFloat(cx / size.width)
                                   + CGFloat(cy / size.height)) / 2
            let intensity = CGFloat.random(in: 0.14...0.28, using: &rng)
                * p * bias
            // Size & intensity grow with progress; this is what makes
            // the crumple visibly DEEPEN as the user drags further.
            let sizeGain = 0.35 + 0.85 * p

            drawOrientedEllipseGradient(
                ctx: ctx,
                centre: CGPoint(x: cx, y: cy),
                length: len * sizeGain,
                width: wid * sizeGain,
                angle: angle,
                inner: .black.opacity(Double(intensity)),
                outer: .clear
            )
            _ = i
        }
    }

    /// Bright elongated gradient blobs — the ridges catching light.
    private func drawHighlightBlobs(ctx: GraphicsContext,
                                    size: CGSize,
                                    progress p: CGFloat,
                                    rng: inout PRNG) {
        let count = 14
        for _ in 0..<count {
            let cx = size.width  * CGFloat.random(in: 0.10...0.90, using: &rng)
            let cy = size.height * CGFloat.random(in: 0.08...0.90, using: &rng)
            let angle = CGFloat.random(in: 0...(2 * .pi), using: &rng)
            let minDim = min(size.width, size.height)
            let len = CGFloat.random(in: 0.10...0.28, using: &rng) * minDim
            let wid = len * CGFloat.random(in: 0.22...0.38, using: &rng)
            // Bias highlights toward the upper-left.
            let bias = 0.6 + 0.4 * (1 - (CGFloat(cx / size.width)
                                         + CGFloat(cy / size.height)) / 2)
            let intensity = CGFloat.random(in: 0.26...0.48, using: &rng)
                * p * bias
            let sizeGain = 0.4 + 0.9 * p

            drawOrientedEllipseGradient(
                ctx: ctx,
                centre: CGPoint(x: cx, y: cy),
                length: len * sizeGain,
                width: wid * sizeGain,
                angle: angle,
                inner: .white.opacity(Double(intensity)),
                outer: .clear
            )
        }
    }

    /// Hairline dark creases — short pencil-like strokes across the
    /// surface, grouped into clusters to mimic real fold patterns.
    private func drawCreases(ctx: GraphicsContext,
                             size: CGSize,
                             progress p: CGFloat,
                             rng: inout PRNG) {
        let clusters = 6
        for _ in 0..<clusters {
            let ox = size.width  * CGFloat.random(in: 0.15...0.85, using: &rng)
            let oy = size.height * CGFloat.random(in: 0.15...0.85, using: &rng)
            let baseAngle = CGFloat.random(in: 0...(2 * .pi), using: &rng)
            let strokeCount = Int.random(in: 2...4, using: &rng)
            for _ in 0..<strokeCount {
                let a = baseAngle + CGFloat.random(in: -0.35...0.35, using: &rng)
                let len = CGFloat.random(in: 18...55, using: &rng)
                    * (0.4 + 0.9 * p)
                let x1 = ox + CGFloat.random(in: -14...14, using: &rng)
                let y1 = oy + CGFloat.random(in: -14...14, using: &rng)
                var path = Path()
                path.move(to: CGPoint(x: x1, y: y1))
                path.addLine(to: CGPoint(x: x1 + cos(a) * len,
                                         y: y1 + sin(a) * len))
                ctx.stroke(
                    path,
                    with: .color(.black.opacity(0.16 * Double(p))),
                    style: StrokeStyle(lineWidth: 0.85, lineCap: .round)
                )
            }
        }
    }

    /// Narrow bright streaks along ridge tops — the "specular" pop
    /// that makes folded paper look glossy at the right angle.
    private func drawSpecularStreaks(ctx: GraphicsContext,
                                     size: CGSize,
                                     progress p: CGFloat,
                                     rng: inout PRNG) {
        let count = 9
        for _ in 0..<count {
            let cx = size.width  * CGFloat.random(in: 0.14...0.86, using: &rng)
            let cy = size.height * CGFloat.random(in: 0.12...0.88, using: &rng)
            let angle = CGFloat.random(in: 0...(2 * .pi), using: &rng)
            let len = CGFloat.random(in: 14...34, using: &rng) * (0.5 + 0.7 * p)
            let w   = CGFloat.random(in: 1.4...2.6, using: &rng)

            let bias = 0.4 + 0.6 * (1 - (CGFloat(cx / size.width)
                                          + CGFloat(cy / size.height)) / 2)

            var path = Path()
            path.move(to: CGPoint(x: cx, y: cy))
            path.addLine(to: CGPoint(x: cx + cos(angle) * len,
                                     y: cy + sin(angle) * len))
            ctx.stroke(
                path,
                with: .color(.white.opacity(0.55 * Double(p) * Double(bias))),
                style: StrokeStyle(lineWidth: w, lineCap: .round)
            )
        }
    }

    // MARK: · Helpers

    /// Draws an oriented ellipse filled with a radial gradient from
    /// `inner` → `outer`.  Used for both shadow and highlight blobs.
    private func drawOrientedEllipseGradient(
        ctx: GraphicsContext,
        centre c: CGPoint,
        length: CGFloat,
        width: CGFloat,
        angle: CGFloat,
        inner: Color,
        outer: Color
    ) {
        let rect = CGRect(x: c.x - length / 2,
                          y: c.y - width / 2,
                          width: length,
                          height: width)
        var xf = CGAffineTransform(translationX: c.x, y: c.y)
        xf = xf.rotated(by: angle)
        xf = xf.translatedBy(x: -c.x, y: -c.y)
        let p = Path(ellipseIn: rect).applying(xf)
        ctx.fill(p, with: .radialGradient(
            Gradient(colors: [inner, outer]),
            center: c,
            startRadius: 0,
            endRadius: length / 2
        ))
    }

    /// Intersects a ray from the centre of a rounded rectangle
    /// (`2·halfW × 2·halfH`, corner radius `corner`) at angle `t`
    /// with the rectangle's rounded perimeter.
    private func roundedRectPerimeter(angle t: Double,
                                      halfW: CGFloat,
                                      halfH: CGFloat,
                                      corner: CGFloat) -> CGPoint {
        // Fast approximation: get the straight-rect hit, then nudge
        // inward near corners so the polygon follows the rounded
        // shape instead of the sharp corner.
        let ux = CGFloat(cos(t))
        let uy = CGFloat(sin(t))
        let rx = abs(ux) > 1e-9 ? halfW / abs(ux) : .greatestFiniteMagnitude
        let ry = abs(uy) > 1e-9 ? halfH / abs(uy) : .greatestFiniteMagnitude
        let r = min(rx, ry)
        let hit = CGPoint(x: ux * r, y: uy * r)

        // Corner smoothing: if the hit is in the corner region,
        // project it onto a quarter-circle of radius `corner`.
        let ax = halfW - corner
        let ay = halfH - corner
        if abs(hit.x) > ax && abs(hit.y) > ay {
            let sx: CGFloat = hit.x >= 0 ? 1 : -1
            let sy: CGFloat = hit.y >= 0 ? 1 : -1
            let cornerCentre = CGPoint(x: sx * ax, y: sy * ay)
            let dx = hit.x - cornerCentre.x
            let dy = hit.y - cornerCentre.y
            let d = hypot(dx, dy)
            if d > 0 {
                let scale = corner / d
                return CGPoint(x: halfW + cornerCentre.x + dx * scale,
                               y: halfH + cornerCentre.y + dy * scale)
            }
        }
        return CGPoint(x: halfW + hit.x, y: halfH + hit.y)
    }

    private func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
}

/// Classic `smoothstep(x, a, b)` — 0 below `a`, 1 above `b`, cubic
/// ease between.  Used for graceful crossfades across progress.
private func smoothstep(_ x: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat {
    let t = max(0, min(1, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)
}

// MARK: - Paper ball
//
// Dedicated "crumpled paper ball" graphic that fades in as the crumple
// progresses past ~0.5. Independent of the snapshot (which might not render
// Canvas content reliably via ImageRenderer) so the ball is *always* a
// recognisable paper ball at the end of the flight.
struct PaperBall: View {
    var diameter: CGFloat
    /// 0 = invisible, 1 = fully formed ball.
    var progress: CGFloat
    /// Base paper colour.
    var paper: Color = MailDesign.paper
    var warm: Color  = MailDesign.paperWarm

    var body: some View {
        Canvas { ctx, size in
            guard progress > 0.001 else { return }
            let alpha = Double(min(max(progress, 0), 1))
            var rng = PRNG(seed: 0xBA11C0DE)

            let cx = size.width / 2
            let cy = size.height / 2
            let R  = min(size.width, size.height) / 2

            // 1) Base irregular polygon — 18 vertices around a circle with
            //    jittered radii. Gives the crumpled silhouette.
            let n = 18
            var ring: [CGPoint] = []
            for i in 0..<n {
                let t = Double(i) / Double(n) * .pi * 2
                let jitter = CGFloat.random(in: 0.86...1.02, using: &rng)
                ring.append(CGPoint(x: cx + cos(t) * R * jitter,
                                    y: cy + sin(t) * R * jitter))
            }
            var silhouette = Path()
            silhouette.move(to: ring[0])
            for p in ring.dropFirst() { silhouette.addLine(to: p) }
            silhouette.closeSubpath()

            ctx.fill(silhouette, with: .color(paper.opacity(alpha)))

            // 2) Facets — random triangles with varied shading to read as
            //    folded paper surfaces catching / losing light.
            let facetCount = 14
            for _ in 0..<facetCount {
                let a = Int.random(in: 0..<n, using: &rng)
                let b = (a + Int.random(in: 1...4, using: &rng)) % n
                let inner = CGPoint(
                    x: cx + CGFloat.random(in: -R * 0.35 ... R * 0.35, using: &rng),
                    y: cy + CGFloat.random(in: -R * 0.35 ... R * 0.35, using: &rng)
                )
                var tri = Path()
                tri.move(to: ring[a])
                tri.addLine(to: ring[b])
                tri.addLine(to: inner)
                tri.closeSubpath()

                let shade = Double.random(in: -0.18...0.18, using: &rng)
                let col: Color = shade >= 0
                    ? Color.white.opacity(shade * alpha * 0.85)
                    : Color.black.opacity(-shade * alpha * 0.85)
                ctx.fill(tri, with: .color(col))
            }

            // 3) Outer rim shade — darken the lower-right, brighten the
            //    upper-left so the ball reads three-dimensional.
            ctx.fill(
                silhouette,
                with: .radialGradient(
                    Gradient(colors: [
                        warm.opacity(0.0),
                        warm.opacity(0.45 * alpha)
                    ]),
                    center: CGPoint(x: cx + R * 0.25, y: cy + R * 0.35),
                    startRadius: R * 0.35,
                    endRadius:   R * 1.05
                )
            )
            ctx.fill(
                silhouette,
                with: .radialGradient(
                    Gradient(colors: [
                        Color.white.opacity(0.30 * alpha),
                        Color.white.opacity(0.0)
                    ]),
                    center: CGPoint(x: cx - R * 0.30, y: cy - R * 0.35),
                    startRadius: 0,
                    endRadius: R * 0.85
                )
            )

            // 4) A few crisp crease lines radiating from the centre.
            for _ in 0..<10 {
                let t = Double.random(in: 0...(.pi * 2), using: &rng)
                let rIn  = CGFloat.random(in: R * 0.05 ... R * 0.30, using: &rng)
                let rOut = CGFloat.random(in: R * 0.55 ... R * 0.95, using: &rng)
                var line = Path()
                line.move(to: CGPoint(x: cx + cos(t) * rIn,  y: cy + sin(t) * rIn))
                line.addLine(to: CGPoint(x: cx + cos(t) * rOut, y: cy + sin(t) * rOut))
                ctx.stroke(line,
                           with: .color(.black.opacity(0.28 * alpha)),
                           style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
            }

            // 5) Hairline rim.
            ctx.stroke(silhouette,
                       with: .color(.black.opacity(0.22 * alpha)),
                       style: StrokeStyle(lineWidth: 0.8, lineJoin: .round))
        }
        .frame(width: diameter, height: diameter)
    }
}
