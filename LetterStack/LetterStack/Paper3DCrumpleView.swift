 import SwiftUI
import SceneKit
import simd

// MARK: - Paper3DCrumpleView
//
// A SceneKit-backed crumpling-paper view driven by a single
// `progress` value in 0…1.
//
//   · A 28 × 36 subdivided mesh is deformed every frame by a
//     deterministic function of (u, v, progress).  Folds are
//     multi-scale ridge waves; as progress → 1 the mesh morphs
//     onto a small, lumpy, asymmetric blob.
//   · The letter itself is rendered into the mesh's diffuse
//     texture, so text creases / warps / wraps with the paper
//     instead of being a separate overlay.
//   · A Lambert material + shader modifier shades the paper
//     with pure diffuse lighting plus a hand-rolled "fold darken"
//     term that deepens shadows along creases — no specular, no
//     metallic sheen.
//   · The text fades out via a shader uniform as the paper balls
//     up, so by the ball-hold the mesh is plain paper.
struct Paper3DCrumpleView: UIViewRepresentable {

    let letter: Letter
    let size: CGSize
    var progress: CGFloat
    var cardCorner: CGFloat = MailDesign.cardCorner

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.scene = context.coordinator.scene
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = false
        view.rendersContinuously = true
        view.autoenablesDefaultLighting = false
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let aspect = max(0.1, size.width / max(1, size.height))
        context.coordinator.update(
            letter: letter,
            size: size,
            progress: progress,
            aspect: aspect,
            cardCorner: cardCorner)
    }

    // MARK: · Coordinator

    @MainActor
    final class Coordinator {

        private let segX: Int = 28
        private let segY: Int = 36

        // Paper colour — matches `MailDesign.paper` exactly
        // (rgb 253/255, 252/255, 248/255).  Using the true paper
        // tone means the crumpled ball reads as the same material
        // as the flat card, instead of a cooler "white" that looks
        // metallic against the warm card.
        private let paperRGB = SIMD3<Float>(
            253.0 / 255.0,
            252.0 / 255.0,
            248.0 / 255.0)

        let scene = SCNScene()
        private let paperNode = SCNNode()

        private let material: SCNMaterial = {
            let m = SCNMaterial()
            // Constant lighting — we evaluate all shading ourselves
            // inside a shader modifier, so we need the geometry
            // fragment to pass through untouched.
            m.lightingModel = .constant
            m.diffuse.contents = UIColor.white
            m.isDoubleSided = true
            m.diffuse.mipFilter            = .linear
            m.diffuse.magnificationFilter  = .linear
            m.diffuse.minificationFilter   = .linear
            m.diffuse.maxAnisotropy        = 8
            m.diffuse.wrapS = .clamp
            m.diffuse.wrapT = .clamp
            return m
        }()

        // Topology cache.
        private var indexData: Data = Data()
        private var indexCount: Int = 0
        private var uvs: [CGPoint] = []

        // Per-frame scratch buffers.
        private var positions: [SCNVector3] = []
        private var normals:   [SCNVector3] = []

        // Texture cache.
        private var lastLetterID: Letter.ID?
        private var lastTextureTargetSize: CGSize = .zero
        private var lastCardCorner: CGFloat = -1

        private var lastProgress: CGFloat = -1
        private var lastAspect:   CGFloat = -1
        private var lastVariant:  Int     = -1
        private var variant: Int = 0

        init() {
            scene.background.contents = UIColor.clear

            // Single orthographic camera.  Looking straight down the
            // −Z axis so our (x, y) vertex coordinates are 1:1 pixels
            // at progress = 0.
            let camNode = SCNNode()
            let cam = SCNCamera()
            cam.usesOrthographicProjection = true
            cam.orthographicScale = 0.62
            cam.zNear = 0.01
            cam.zFar  = 10
            camNode.camera = cam
            camNode.position = SCNVector3(0, 0, 3)
            scene.rootNode.addChildNode(camNode)

            scene.rootNode.addChildNode(paperNode)

            installShaderModifier()
            buildTopology()
        }

        // MARK: · Shader modifier — all shading happens here
        //
        // We bypass SceneKit's Lambert path entirely so we have
        // exact, predictable control of what the paper looks like.
        // No specular, no metallic sheen, no light clipping.
        //
        //   · N·L lambert against a single soft upper-left light.
        //   · Sideness (1 - |n.z|) darkens crease walls — fake AO.
        //   · `textMix` cross-fades the sampled letter texture into
        //     plain paper colour as the paper balls up.
        private func installShaderModifier() {
            // Paper shading tuned for a real-paper feel (like the
            // reference photograph):
            //   · Most pixels sit close to paperColor (matte,
            //     uniform).  Deep creases darken but only a little.
            //   · A handful of patches pick up a soft highlight
            //     (crests) and others slightly more shadow —
            //     driven by UV-space region noise at two scales.
            //   · No specular / fresnel.  Top-end clipped to 1.0
            //     so nothing ever goes brighter than paperColor.
            //   · Colour is multiplicative, so the ball is the
            //     SAME tone as the flat card — not a cooler white.
            let surfaceShader = """
            #pragma arguments
            float textMix;
            float3 paperColor;

            #pragma body
            float3 L = normalize(float3(-0.35, 0.55, 0.78));
            float3 N = normalize(_surface.normal);
            float ndotl = max(dot(N, L), 0.0);

            // Crease AO — deepest where normals point sideways.
            float sideness = 1.0 - abs(N.z);
            float ao = 1.0 - 0.18 * sideness;

            // Matte band: 0.88 floor (only 12 % dynamic range) so
            // the bulk of the ball reads as plain paper.  Deep
            // creases still pick up 12 % shadow — a gentle hint,
            // not a sharp shaded facet.
            float shade = 0.88 + 0.12 * ndotl;
            shade *= ao;

            // Regional variation — the key to the "some flat, some
            // crooked" real-paper look.
            //   · `regBroad` controls which big patch of the ball
            //     is currently lifted toward the light.  Ranges
            //     ±6 % around the base shade.
            //   · `regFine`  adds finer-grain mottling (±3 %) so
            //     even flat patches aren't perfectly uniform.
            //   · Two distinct hashes at very different freqs give
            //     the uncorrelated look the reference photo has.
            float2 uv = _surface.diffuseTexcoord;
            float regBroad =
                fract(sin(dot(uv, float2(2.93,  5.71))) * 17.13);
            float regFine  =
                fract(sin(dot(uv, float2(19.7, 27.3))) * 83.47);
            // Bias regBroad toward mid-range so extremes are rare.
            float broad = (regBroad - 0.5);
            float fine  = (regFine  - 0.5);
            shade += broad * 0.060;   // ±6 % region highlight/shadow
            shade += fine  * 0.030;   // ±3 % mottling

            // Subtle highlight crest on steep normals pointing at
            // the camera — catches the light on the tips of
            // wrinkles the way a glossy fold does, but very mild.
            float crest = pow(max(N.z, 0.0), 6.0);
            shade += 0.04 * crest;

            shade = clamp(shade, 0.70, 1.00);

            float3 tex = _surface.diffuse.rgb;
            float3 base = mix(paperColor, tex, textMix);

            _surface.diffuse.rgb = base * shade;
            _surface.diffuse.a   = 1.0;
            """
            material.shaderModifiers = [.surface: surfaceShader]
            material.setValue(
                NSValue(scnVector3: SCNVector3(paperRGB.x,
                                               paperRGB.y,
                                               paperRGB.z)),
                forKey: "paperColor")
            material.setValue(1.0 as Float, forKey: "textMix")
        }

        // MARK: · Topology (built once)

        private func buildTopology() {
            uvs.reserveCapacity((segX + 1) * (segY + 1))
            for j in 0...segY {
                for i in 0...segX {
                    // UV origin top-left, matching UIImage pixel
                    // layout.  Previous build had this inverted,
                    // which is why the text rendered upside-down.
                    uvs.append(CGPoint(
                        x: Double(i) / Double(segX),
                        y: Double(j) / Double(segY)))
                }
            }

            var idx: [Int32] = []
            idx.reserveCapacity(segX * segY * 6)
            for j in 0..<segY {
                for i in 0..<segX {
                    let a = Int32(j * (segX + 1) + i)
                    let b = Int32(j * (segX + 1) + i + 1)
                    let c = Int32((j + 1) * (segX + 1) + i)
                    let d = Int32((j + 1) * (segX + 1) + i + 1)
                    idx.append(contentsOf: [a, c, b, b, c, d])
                }
            }
            indexCount = idx.count
            indexData = idx.withUnsafeBufferPointer { Data(buffer: $0) }

            positions = [SCNVector3](
                repeating: SCNVector3Zero,
                count: (segX + 1) * (segY + 1))
            normals = [SCNVector3](
                repeating: SCNVector3(0, 0, 1),
                count: (segX + 1) * (segY + 1))
        }

        // MARK: · Per-frame update

        func update(letter: Letter,
                    size: CGSize,
                    progress: CGFloat,
                    aspect: CGFloat,
                    cardCorner: CGFloat) {
            let sizeChanged =
                abs(size.width  - lastTextureTargetSize.width)  > 1 ||
                abs(size.height - lastTextureTargetSize.height) > 1
            let cornerChanged = abs(cardCorner - lastCardCorner) > 0.01
            if letter.id != lastLetterID || sizeChanged || cornerChanged {
                regenerateLetterTexture(letter: letter, size: size,
                                        cardCorner: cardCorner)
                lastLetterID = letter.id
                lastTextureTargetSize = size
                lastCardCorner = cardCorner
            }

            // Pick one of 4 shape variants deterministically from
            // the letter's UUID.  Each variant applies different
            // axis-squash, wobble weights, and hash offsets so the
            // crumpled ball has a distinct silhouette per letter —
            // never the same shape twice in a row in the deck.
            let newVariant = abs(letter.id.hashValue) % 4
            if newVariant != variant {
                variant = newVariant
                lastProgress = -1   // force a geometry rebuild
            }

            // Text fade — fully visible until progress 0.35, gone
            // by 0.62 so the ball-hold shows clean paper.  Once
            // textMix hits 0 the mesh samples paperColor only.
            let textMix = Float(1.0 - smoothstepF(
                Float(progress), 0.35, 0.62))
            material.setValue(textMix, forKey: "textMix")

            if abs(progress - lastProgress) < 0.001
                && abs(aspect - lastAspect) < 0.001
                && variant == lastVariant {
                return
            }
            lastProgress = progress
            lastAspect   = aspect
            lastVariant  = variant

            rebuildGeometry(progress: Float(progress),
                            aspect:   Float(aspect))
        }

        @MainActor
        private func regenerateLetterTexture(letter: Letter,
                                             size: CGSize,
                                             cardCorner: CGFloat) {
            guard size.width > 0, size.height > 0 else { return }

            // Render the letter on a FULL paper-colour rectangle —
            // no rounded clip, no shadow, no outline.  The rounded
            // card corners in `SimpleLetterSnapshot` produced
            // transparent-going-to-black corner pixels that showed
            // up as dark patches on the mesh; wrapping the content
            // in a square paper-filled rect eliminates that.
            let content = ZStack {
                Rectangle().fill(MailDesign.paper)
                SimpleLetterSnapshot(letter: letter, size: size,
                                      cornerRadius: cardCorner)
                    .clipped()
            }
            .frame(width: size.width, height: size.height)

            let renderer = ImageRenderer(content: content)
            renderer.scale = 3.0
            renderer.isOpaque = true
            if let img = renderer.uiImage {
                material.diffuse.contents = img
            }
        }

        // MARK: · Mesh deformation

        private func rebuildGeometry(progress p: Float, aspect: Float) {
            let W: Float = aspect
            let H: Float = 1.0

            // Fold envelope — creases grow quickly at the start,
            // then relax slightly as the paper balls up so we're
            // not fighting against the sphere morph.
            let foldEnv = smoothstepF(p, 0.00, 0.42)
                        * (1.0 - 0.25 * smoothstepF(p, 0.72, 1.0))
            let ballEnv = smoothstepF(p, 0.28, 0.96)

            // Ball radius in world units.  Shrunk again (0.12 →
            // 0.085) so the ball is unambiguously smaller than
            // the pill's inner chamber — supports the "genie"
            // read of the trash flight where the ball disappears
            // INTO the icon rather than landing on top of it.
            let ballRadius: Float = 0.085

            // 4 distinct shape profiles.  Each combines:
            //   · a hash-space offset (seedX, seedY) so the
            //     per-vertex noise completely re-rolls,
            //   · a different axis-squash (long-axis direction
            //     and severity of the squash),
            //   · different weights for the three wobble
            //     octaves — some variants are bulgy, others
            //     jagged, others flatter.
            struct ShapeProfile {
                var seedX: Float
                var seedY: Float
                var axis:  SIMD3<Float>
                var broad: Float
                var mid:   Float
                var hi:    Float
                var lump:  Float   // lump-offset multiplier
            }
            let profiles: [ShapeProfile] = [
                // 0 · Long & jagged — elongated along X, lots of
                //     mid-freq bumps, pokey corners.
                ShapeProfile(seedX: 0.00, seedY: 0.00,
                             axis: SIMD3<Float>(1.18, 0.80, 0.92),
                             broad: 0.28, mid: 0.22, hi: 0.10,
                             lump: 1.2),
                // 1 · Tall & bulgy — elongated along Y, big broad
                //     lumps, smoother fine detail.
                ShapeProfile(seedX: 2.71, seedY: 1.33,
                             axis: SIMD3<Float>(0.86, 1.14, 0.92),
                             broad: 0.36, mid: 0.14, hi: 0.07,
                             lump: 1.0),
                // 2 · Squat & chunky — flatter, wider, with a
                //     couple of dominant cheeks.
                ShapeProfile(seedX: 5.19, seedY: 3.47,
                             axis: SIMD3<Float>(1.10, 0.88, 0.80),
                             broad: 0.30, mid: 0.18, hi: 0.08,
                             lump: 1.1),
                // 3 · Rough & unruly — near-isotropic but very
                //     high-freq, many jagged pokes.
                ShapeProfile(seedX: 7.93, seedY: 6.11,
                             axis: SIMD3<Float>(1.05, 0.95, 0.90),
                             broad: 0.22, mid: 0.20, hi: 0.16,
                             lump: 1.3),
            ]
            let prof = profiles[variant]

            let rows = segY + 1
            let cols = segX + 1
            for j in 0..<rows {
                let v = Float(j) / Float(segY)
                let y0 = (0.5 - v) * H
                for i in 0..<cols {
                    let u = Float(i) / Float(segX)
                    let x0 = (u - 0.5) * W

                    // Per-variant seed offsets fully re-roll the
                    // deterministic noise — different variant =>
                    // different bumps, dents, and poking corners.
                    let sx = prof.seedX
                    let sy = prof.seedY
                    let h1 = hash(u *  7.13 + 0.17 + sx, v *  5.31 + 0.41 + sy)
                    let h2 = hash(u *  3.77 + 0.89 + sx, v *  9.01 + 0.13 + sy)
                    let h3 = hash(u * 11.21 + 0.53 + sx, v *  4.19 + 0.71 + sy)
                    let h4 = hash(u *  2.03 + 0.37 + sx, v *  6.47 + 0.29 + sy)
                    let h5 = hash(u * 15.11 + 0.61 + sx, v *  2.23 + 0.83 + sy)

                    // Softer, lower-frequency folds.  Only two
                    // scales, smooth `sin` (no ridge steepening)
                    // so wrinkles roll instead of facet.
                    let a1 = x0 * 6.0 + y0 * 2.4 + (h1 - 0.5) * 2.2
                    let a2 = y0 * 5.0 - x0 * 1.6 + (h2 - 0.5) * 1.8
                    let zFold = (sinf(a1) * 0.050
                               + sinf(a2) * 0.032)
                              * foldEnv

                    // Mild planar contraction — paper doesn't
                    // stretch, so it pulls in slightly as it
                    // wrinkles.  Smaller than before (0.05 vs
                    // 0.08) to reduce the text-compression look.
                    let pinch: Float = 1.0 - 0.05 * foldEnv
                    let planePt = SIMD3<Float>(
                        x0 * pinch,
                        y0 * pinch,
                        zFold)

                    // Asymmetric crumple target.  A real wad of
                    // paper is never a sphere — it has a long
                    // axis, a couple of flat-ish cheeks where
                    // paper stacked on itself, and two or three
                    // corners that poke out.  We build that
                    // character explicitly:
                    //
                    //   · Strong axis squash (1.15, 0.82, 0.94)
                    //     gives the wad a clear long axis, not
                    //     a round silhouette.
                    //   · Three-octave radial wobble:
                    //       ±0.32 broad lumping (big dents/bulges)
                    //       ±0.18 per-vertex bump
                    //       ±0.10 high-freq roughness
                    //     → net range ~0.55…1.30 = very bumpy.
                    //   · Lump offset increased to ±0.050 so
                    //     individual verts poke out further,
                    //     creating the jagged corners real
                    //     crumpled paper has.
                    //   · `flatten` hash zero's out the lump on
                    //     some patches → smooth "cheek" regions
                    //     alongside the rough ones.
                    let bx = (h1 - 0.5) * 2.0
                    let by = (h2 - 0.5) * 2.0
                    let bz = (h3 - 0.5) * 2.0 + 0.20
                    let rawDir = SIMD3<Float>(
                        bx * 1.05 + x0 * 0.9,
                        by * 0.85 + y0 * 0.9,
                        bz)
                    let dir = simd_normalize(rawDir)

                    // Three-octave wobble weights come from the
                    // shape profile so each variant has its own
                    // character (bulgy vs jagged vs chunky …).
                    let broadLump = sinf(h4 * 5.2 + h1 * 3.1)
                    let midBump   = sinf(h5 * 8.0 + h3 * 2.0)
                    let hiRough   = sinf(h2 * 13.0 + h4 * 7.0)
                    let rWobble: Float = 0.86
                                       + prof.broad * broadLump
                                       + prof.mid   * midBump
                                       + prof.hi    * hiRough

                    // Axis squash from the profile — different
                    // variants are elongated along different axes.
                    let axisScale = prof.axis

                    // Poke-out corners + flat cheeks.  `flatten`
                    // near 1 keeps the region smooth; near 0
                    // lets the lump offset push outward.  Lump
                    // strength scales with profile (jagged ones
                    // push harder).
                    let flatten: Float = smoothstepF(h5, 0.55, 0.95)
                    let lumpOffset = SIMD3<Float>(
                        (h5 - 0.5) * 0.050 * prof.lump,
                        (h4 - 0.5) * 0.050 * prof.lump,
                        (h1 - 0.5) * 0.040 * prof.lump
                    ) * (1.0 - flatten)

                    let ballPt = (dir * (ballRadius * rWobble))
                               * axisScale
                               + lumpOffset

                    let finalPt = mixv(planePt, ballPt, ballEnv)
                    positions[j * cols + i] = SCNVector3(
                        finalPt.x, finalPt.y, finalPt.z)
                }
            }

            recomputeSmoothNormals()

            let posSource = SCNGeometrySource(vertices: positions)
            let nrmSource = SCNGeometrySource(normals:  normals)
            let uvSource  = SCNGeometrySource(
                textureCoordinates: uvs)
            let element = SCNGeometryElement(
                data: indexData,
                primitiveType: .triangles,
                primitiveCount: indexCount / 3,
                bytesPerIndex: MemoryLayout<Int32>.size)

            let geo = SCNGeometry(
                sources: [posSource, nrmSource, uvSource],
                elements: [element])
            geo.materials = [material]
            paperNode.geometry = geo
        }

        // MARK: · Smooth per-vertex normals

        private func recomputeSmoothNormals() {
            let count = positions.count
            var acc = [SIMD3<Float>](repeating: .zero, count: count)

            let cols = segX + 1
            for j in 0..<segY {
                for i in 0..<segX {
                    let a = j * cols + i
                    let b = j * cols + i + 1
                    let c = (j + 1) * cols + i
                    let d = (j + 1) * cols + i + 1

                    let pa = simdv(positions[a])
                    let pb = simdv(positions[b])
                    let pc = simdv(positions[c])
                    let pd = simdv(positions[d])

                    let n1 = simd_cross(pc - pa, pb - pa)
                    let n2 = simd_cross(pc - pb, pd - pb)

                    acc[a] += n1
                    acc[b] += n1 + n2
                    acc[c] += n1 + n2
                    acc[d] += n2
                }
            }

            for k in 0..<count {
                let v = acc[k]
                let len = simd_length(v)
                let n = len > 1e-6 ? v / len : SIMD3<Float>(0, 0, 1)
                normals[k] = SCNVector3(n.x, n.y, n.z)
            }
        }

        // MARK: · Math helpers

        @inline(__always)
        private func hash(_ x: Float, _ y: Float) -> Float {
            let s = sinf(x * 127.1 + y * 311.7) * 43758.5453
            return s - floorf(s)
        }

        @inline(__always)
        private func ridge(_ t: Float) -> Float {
            let s = sinf(t)
            return (s < 0 ? -1 : 1) * powf(abs(s), 0.70)
        }

        @inline(__always)
        private func smoothstepF(_ x: Float,
                                 _ a: Float,
                                 _ b: Float) -> Float {
            let t = max(0, min(1, (x - a) / (b - a)))
            return t * t * (3.0 - 2.0 * t)
        }

        @inline(__always)
        private func mixv(_ a: SIMD3<Float>,
                          _ b: SIMD3<Float>,
                          _ t: Float) -> SIMD3<Float> {
            return a + (b - a) * t
        }

        @inline(__always)
        private func simdv(_ v: SCNVector3) -> SIMD3<Float> {
            return SIMD3<Float>(Float(v.x), Float(v.y), Float(v.z))
        }
    }
}
