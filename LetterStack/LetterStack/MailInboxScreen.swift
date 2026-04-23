import SwiftUI
import UIKit

struct MailInboxScreen: View {
    @State private var letters: [Letter] = Letter.sampleDeck(count: 8)
    @State private var drag: CGSize = .zero
    @State private var outcome: SwipeOutcome = .idle
    @State private var isCompletingGesture = false
    @State private var viewportWidth: CGFloat = 393
    @State private var fingerOnCard: CGPoint?
    /// Locked on touch-down and cleared on touch-up. Prevents the curl's
    /// anchor corner from flipping between sides mid-drag (jitter).
    @State private var lockedCurlCorner: CurlCorner?
    @State private var lastHapticBucket: Int = 0
    @State private var didHapticEngage = false
    @State private var trashPulse: CGFloat = 1

    // Trash flight.
    @State private var trashImage: UIImage?
    @State private var trashLetter: Letter?
    @State private var isTrashing = false
    @State private var trashTrigger: Int = 0
    @State private var trashStart: CGPoint = .zero
    @State private var trashApex: CGPoint = .zero
    @State private var trashTarget: CGPoint = .zero
    @State private var trashPillCenter: CGPoint = .zero
    @State private var trashCardSize: CGSize = .zero
    /// Crumple value at the moment the user commits the trash gesture.
    /// Lets the flight view start mid-crumple so the paper doesn't
    /// "snap flat" between the live drag-crumple overlay and the
    /// flight-view takeover.
    @State private var trashInitialCrumple: CGFloat = 0

    // Unread fly-to-back.
    @State private var unreadImage: UIImage?
    @State private var unreadTrigger: Int = 0
    @State private var unreadEndOffset: CGSize = .zero
    @State private var unreadEndRotation: Double = 0

    // Top card live centre — needed to launch the trash flight from the
    // card's current on-screen position.
    @State private var topCardCenter: CGPoint = .zero

    // Undo history: every completed action pushes an entry.  The Undo
    // pill pops the most recent one and replays it backwards.
    @State private var undoStack: [UndoAction] = []
    // Active undo reentry — drives the reverse flight overlay.
    @State private var undoReentry: UndoReentry?

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let cardWidth = min(328, width - 44)
            let cardHeight = cardWidth * (448.0 / 328.0)
            let cardSize = CGSize(width: cardWidth, height: cardHeight)

            ZStack {
                MailDesign.sky.ignoresSafeArea()

                VStack(spacing: 0) {
                    topHeader(safeTop: geo.safeAreaInsets.top)

                    // NOTE ORDER: `.background(trashCenterReader)` MUST be
                    // attached to the bare `TrashPill` BEFORE any padding
                    // so the reader captures the pill's own frame (48 pt
                    // tall).  If padding is applied first, the reader
                    // sees the padded box and `trashPillCenter` drifts
                    // 21 pt downward.
                    TrashPill(highlight: trashHighlight, pulse: trashPulse)
                        .background(trashCenterReader)
                        .padding(.top, 42)   // 42 pt between header baseline and pill

                    // Equal breathing room above AND below the paper
                    // stack — 36 pt gap between the Trash pill and the
                    // top card, matched by 36 pt between the bottom card
                    // and the Unread/Archive row.  `minLength` lets the
                    // layout grow on larger devices without collapsing.
                    Spacer(minLength: 36)

                    letterStack(
                        cardWidth: cardWidth,
                        cardHeight: cardHeight,
                        cardSize: cardSize
                    )
                    .frame(width: cardWidth, height: cardHeight)

                    Spacer(minLength: 36)

                    HStack {
                        NeutralActionPill(
                            title: "Unread",
                            iconName: "icon_unread",
                            tint: MailDesign.unreadTint,
                            highlight: unreadHighlight
                        )
                        Spacer()
                        IconOnlyPill(iconName: "icon_undo",
                                     isActive: !undoStack.isEmpty,
                                     action: undoLastAction)
                        Spacer()
                        NeutralActionPill(
                            title: "Archive",
                            iconName: "icon_archive",
                            tint: MailDesign.archiveTint,
                            highlight: archiveHighlight
                        )
                    }
                    // Identical horizontal inset to the header (20 pt) so
                    // Unread's left edge sits directly under the chevron
                    // and Archive's right edge sits directly under the
                    // count text.
                    .padding(.horizontal, 20)
                    // Exactly 34 pt above the PHYSICAL screen bottom.
                    // The VStack is constrained to the safe area, so
                    // its bottom already sits `safeAreaInsets.bottom`
                    // above the physical bottom.  We subtract that
                    // inset from 34 so the final gap is always 34 pt
                    // regardless of device (notched iPhones have a
                    // ~34 pt home-indicator inset → padding collapses
                    // to 0; older devices with no inset → full 34 pt).
                    .padding(.bottom,
                             max(0, 34 - geo.safeAreaInsets.bottom))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                // Full-screen centred empty state: sun, two caption lines, 15pt.
                if letters.isEmpty {
                    ZStack {
                        Color.clear
                        let emptyCaptionGray = Color(
                            red: 66 / 255, green: 66 / 255, blue: 66 / 255
                        ).opacity(0.72)

                        VStack(alignment: .center, spacing: 0) {
                            Text("☀️")
                                .font(.system(size: 23))
                            Text("Great start")
                                .font(.system(size: 15, weight: .medium,
                                              design: .default))
                                .foregroundStyle(emptyCaptionGray)
                                .padding(.top, 8)
                            Text("to your day!")
                                .font(.system(size: 15, weight: .medium,
                                              design: .default))
                                .foregroundStyle(emptyCaptionGray)
                                .padding(.top, 2)
                        }
                        .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                }

                if isTrashing {
                    // Crumpled ball flies ABOVE the trash pill (the
                    // pill stays fixed and is never occluded by an
                    // overlay copy).  Visually: the ball arcs into
                    // the pill and the final sub-pixel scale on
                    // top of the pill lets it disappear at the pill
                    // centre without ever passing behind it.
                    TrashFlightView(
                        image: trashImage,
                        letter: trashLetter,
                        cardSize: trashCardSize,
                        trigger: trashTrigger,
                        startPoint: trashStart,
                        apexPoint: trashApex,
                        endPoint: trashTarget,
                        initialCrumple: trashInitialCrumple,
                        onLand: { pulseTrashPill() }
                    )
                    .allowsHitTesting(false)
                }

                if let reentry = undoReentry {
                    UndoReentryView(
                        reentry: reentry,
                        onLand: finishUndoReentry
                    )
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }

            }
            .onAppear {
                viewportWidth = width
                PaperSound.shared.activate()
            }
            .onChange(of: width) { _, newValue in viewportWidth = newValue }
        }
    }

    // MARK: - Header

    private func topHeader(safeTop: CGFloat) -> some View {
        // Single-row header: chevron + titles share the same **vertical
        // centre** so the caret reads aligned with the 21 pt headline (using
        // `.firstTextBaseline` sat the icon on the text baseline, which left
        // the glyph visually low vs the cap-height block).
        HStack(alignment: .center, spacing: 8) {
            Image("icon_back")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 18)
                .foregroundStyle(MailDesign.ink)

            Text("All Inboxes")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(MailDesign.ink)

            Text("\(letters.count) left")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(MailDesign.mutedInk)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .dynamicTypeSize(.xSmall ... .large)
    }

    // MARK: - Trash target + card origin tracking

    private var trashCenterReader: some View {
        GeometryReader { g in
            Color.clear.preference(key: TrashCenterKey.self, value: g.frame(in: .global).center)
        }
        .onPreferenceChange(TrashCenterKey.self) { trashPillCenter = $0 }
    }

    private var cardOriginReader: some View {
        GeometryReader { g in
            Color.clear.preference(key: CardCenterKey.self, value: g.frame(in: .global).center)
        }
        .onPreferenceChange(CardCenterKey.self) { topCardCenter = $0 }
    }

    // MARK: - Highlight helpers

    private var unreadHighlight:  CGFloat { if case let .unread(p)  = outcome { return p } else { return 0 } }
    private var archiveHighlight: CGFloat { if case let .archive(p) = outcome { return p } else { return 0 } }
    private var trashHighlight:   CGFloat { if case let .trash(p)   = outcome { return p } else { return 0 } }

    // MARK: - Stack

    /// The top card's live curl geometry, derived from the same shared
    /// drag / finger state that `LetterCardView` uses internally.
    /// Computed here so the stack can punch the pocket out of every
    /// card's shadow, not just the top sheet's.
    private func topCardCurl(cardSize: CGSize) -> PageCurlGeometry {
        let d = min(1, max(0, hypot(drag.width, drag.height) / 160))
        let intensity: CGFloat = fingerOnCard == nil ? 0 : (0.42 + 0.58 * d)
        return PageCurlGeometry(
            origin: fingerOnCard,
            lockedCorner: lockedCurlCorner,
            cardSize: cardSize,
            cornerRadius: MailDesign.cardCorner,
            intensity: intensity
        )
    }

    private func letterStack(cardWidth: CGFloat,
                             cardHeight: CGFloat,
                             cardSize: CGSize) -> some View {
        let topCurl = topCardCurl(cardSize: cardSize)
        // Top card's visual transform — the mask has to follow the
        // sheet as the user drags so the pocket cut-out stays aligned
        // with the lifted corner.
        let topRotation = stackRotation(for: 0) + Double(drag.width) * 0.03
        let topOffset = CGSize(
            width: stackOffset(for: 0).width + drag.width,
            height: stackOffset(for: 0).height + drag.height
        )

        return ZStack {
            // Every card's outside shadow, rendered together in one
            // layer so a single mask can punch the top sheet's curl
            // pocket out of *all* of them.  Without this, lower sheets'
            // shadows bled through the hole and read as a grey patch
            // behind the lifted corner.  Card bodies render in the
            // layer below this one, unmasked — so the pocket still
            // reveals the next sheet's paper wherever it reaches.
            outsideShadowLayer(cardSize: cardSize, topCurl: topCurl)
                .mask(
                    ZStack {
                        Rectangle()
                            .fill(Color.black)
                            .frame(width: cardSize.width + 240,
                                   height: cardSize.height + 240)

                        if topCurl.isActive {
                            CurlPocketShape(curl: topCurl)
                                .fill(Color.black)
                                .frame(width: cardSize.width,
                                       height: cardSize.height)
                                .rotationEffect(.degrees(topRotation))
                                .offset(topOffset)
                                .blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
                )

            ForEach(Array(letters.enumerated()), id: \.element.id) { index, letter in
                let iFromTop = index
                let drawZ = Double(max(0, letters.count - 1 - index))
                let rotation = stackRotation(for: iFromTop)
                let offset = stackOffset(for: iFromTop)
                let isTop = iFromTop == 0

                // Live trash progress on the top card.  The moment the
                // user drags upward and the red bar starts filling, this
                // goes > 0.  We snap-swap the pristine `LetterCardView`
                // for a `PaperCrumple` (a SINGLE sheet visibly squishing
                // in on itself) so only ONE piece of paper is on screen
                // at a time — not a stack of 8 ghost copies — and the
                // shadow moves with that one sheet.
                let liveCrumple: CGFloat = isTop ? trashHighlight : 0
                let crumpleActive = isTop && !isTrashing && liveCrumple > 0.02
                let cardFade: CGFloat = (isTop && isTrashing) ? 1 :
                    (crumpleActive ? 1 : 0)

                ZStack {
                    LetterCardView(
                        letter: letter,
                        isInteractive: isTop && !isCompletingGesture,
                        translation: isTop ? drag : .zero,
                        fingerLocal: isTop ? fingerOnCard : nil,
                        lockedCurlCorner: isTop ? lockedCurlCorner : nil,
                        stackIndexFromTop: iFromTop,
                        stackCount: letters.count,
                        cardLayoutSize: cardSize,
                        fadeProgress: cardFade,
                        drawsOutsideShadow: false
                    )

                    if crumpleActive {
                        PaperCrumple(
                            letter: letter,
                            size: cardSize,
                            progress: liveCrumple
                        )
                        .frame(width: cardWidth, height: cardHeight)
                        // Slide toward the top of the screen as the sheet
                        // crumples so it reads as being thrown upward, not
                        // trapped inside the stack slot.
                        .offset(y: -pow(liveCrumple, 1.12) * 280)
                        .allowsHitTesting(false)
                    }
                }
                .frame(width: cardWidth, height: cardHeight)
                .rotationEffect(.degrees(rotation + (isTop ? Double(drag.width) * 0.03 : 0)))
                .offset(x: offset.width + (isTop ? drag.width : 0),
                        y: offset.height + (isTop ? drag.height : 0))
                .modifier(TopCardGestureModifier(
                    isEnabled: isTop,
                    gesture: topCardDrag(cardSize: cardSize)
                ))
                .background(isTop ? cardOriginReader : nil)
                .zIndex(drawZ)
            }

            // Unread ghost — flies out left, curves up, lands at the back of
            // the stack. Rendered behind everything so it reads as "going to
            // the back".
            if let img = unreadImage {
                UnreadFlightView(
                    image: img,
                    trigger: unreadTrigger,
                    endOffset: unreadEndOffset,
                    endRotation: unreadEndRotation,
                    cardSize: cardSize
                )
                .zIndex(-1)
            }
        }
    }

    /// Renders every card's outside stack shadow in a single layer so
    /// one mask can punch the top sheet's curl pocket out of all of
    /// them together.  Each shadow still follows its own sheet's
    /// rotation and offset so the stack silhouette reads correctly.
    @ViewBuilder
    private func outsideShadowLayer(cardSize: CGSize,
                                    topCurl: PageCurlGeometry) -> some View {
        let stackDepthScale: Double = letters.count > 1 ? 1.14 : 1.0
        ZStack {
            ForEach(Array(letters.enumerated()), id: \.element.id) { index, letter in
                let iFromTop = index
                let drawZ = Double(max(0, letters.count - 1 - index))
                let rotation = stackRotation(for: iFromTop)
                let offset = stackOffset(for: iFromTop)
                let isTop = iFromTop == 0
                // This layer must stay a rounded-rect *card* ring. During
                // crumple the visible paper is a ball offset upward; during
                // trash flight the stack card is empty.  Leaving the top ring
                // here (Mark's single combined shadow pass) would read as a
                // wrong grey L-fragment at the old slot, since it doesn't move
                // with `PaperCrumple` and isn't a sphere-sized halo.
                let hideTopStackRing: Bool = isTop
                    && (isTrashing
                        || (!isTrashing && trashHighlight > 0.02))

                LetterCardOutsideShadow(
                    size: cardSize,
                    cornerRadius: MailDesign.cardCorner,
                    // Top sheet still carries its own mirror-flap punch-out
                    // so the outer rim shadow doesn't paint behind the
                    // lifted flap.  Lower sheets don't need this — the
                    // stack-level mask handles the pocket for them.
                    curlPunchOut: (isTop && topCurl.isActive) ? topCurl : nil,
                    opacityScale: stackDepthScale
                )
                .frame(width: cardSize.width, height: cardSize.height)
                .rotationEffect(.degrees(rotation + (isTop ? Double(drag.width) * 0.03 : 0)))
                .offset(x: offset.width + (isTop ? drag.width : 0),
                        y: offset.height + (isTop ? drag.height : 0))
                .opacity(hideTopStackRing ? 0 : 1)
                .zIndex(drawZ)
            }
        }
    }

    private func stackRotation(for indexFromTop: Int) -> Double {
        let palette = MailDesign.stackRotations
        return palette[min(max(indexFromTop, 0), palette.count - 1)]
    }

    private func stackOffset(for indexFromTop: Int) -> CGSize {
        let palette = MailDesign.stackOffsets
        return palette[min(max(indexFromTop, 0), palette.count - 1)]
    }

    // MARK: - Gestures

    private func topCardDrag(cardSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .local)
            .onChanged { value in
                guard !letters.isEmpty, !isCompletingGesture else { return }
                if !didHapticEngage {
                    didHapticEngage = true
                    Haptics.softTap()
                    // Lock the curl's anchor corner at the moment the
                    // finger touches down.  This is what the finger is
                    // "holding" — and it stays fixed for the whole drag
                    // so the curl never flips sides.
                    lockedCurlCorner = nearestCorner(
                        to: value.location,
                        in: cardSize
                    )
                }
                drag = value.translation
                fingerOnCard = value.location
                let next = classify(translation: value.translation)
                outcome = next

                let bucket = Int(next.progress * 4)
                if bucket != lastHapticBucket {
                    lastHapticBucket = bucket
                    if bucket > 0 { Haptics.tick() }
                }
            }
            .onEnded { value in
                fingerOnCard = nil
                didHapticEngage = false
                lockedCurlCorner = nil
                guard !letters.isEmpty, !isCompletingGesture else { return }
                handleEnd(translation: value.translation, cardSize: cardSize)
            }
    }

    /// Returns the corner of the card closest to `point` in card-local
    /// coordinates.  Used to lock the curl anchor on touch-down.
    private func nearestCorner(to point: CGPoint, in size: CGSize) -> CurlCorner {
        let leftish = point.x < size.width / 2
        let topish  = point.y < size.height / 2
        switch (leftish, topish) {
        case (true,  true):  return .topLeft
        case (false, true):  return .topRight
        case (true,  false): return .bottomLeft
        case (false, false): return .bottomRight
        }
    }

    private func classify(translation: CGSize) -> SwipeOutcome {
        let x = translation.width
        let y = translation.height
        let ax = abs(x)
        let ay = abs(y)
        let denom: CGFloat = 120

        if ay > ax, y < -12 {
            return .trash(progress: min(1, (-y) / denom))
        }
        if ax > ay, x < -12 {
            return .unread(progress: min(1, (-x) / denom))
        }
        if ax > ay, x > 12 {
            return .archive(progress: min(1, x / denom))
        }
        return .idle
    }

    private func handleEnd(translation: CGSize, cardSize: CGSize) {
        switch classify(translation: translation) {
        case let .trash(p) where p > 0.5:
            completeTrash(cardSize: cardSize)
        case let .unread(p) where p > 0.5:
            completeUnread(cardSize: cardSize)
        case let .archive(p) where p > 0.5:
            completeArchive()
        default:
            Haptics.softTap()
            withAnimation(.easeOut(duration: 0.2)) {
                drag = .zero
                outcome = .idle
            }
            lastHapticBucket = 0
        }
    }

    // MARK: - Unread (fly to back)

    private func completeUnread(cardSize: CGSize) {
        guard let topLetter = letters.first else { return }

        // Only one letter left → there's no "back of the stack" to send it
        // to. Snap back to the front with a light tick and bail out.
        guard letters.count > 1 else {
            Haptics.softTap()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                drag = .zero
                outcome = .idle
            }
            lastHapticBucket = 0
            return
        }

        isCompletingGesture = true
        Haptics.tap()
        PaperSound.shared.rustle(volume: 0.85)

        // 1) Snapshot the current top card.
        let snapshotView = LetterCardView(
            letter: topLetter,
            isInteractive: false,
            translation: .zero,
            fingerLocal: nil,
            lockedCurlCorner: nil,
            stackIndexFromTop: 0,
            stackCount: 1,
            cardLayoutSize: cardSize,
            fadeProgress: 0
        )
        .frame(width: cardSize.width, height: cardSize.height)

        let renderer = ImageRenderer(content: snapshotView)
        renderer.scale = UIScreen.main.scale
        let image = renderer.uiImage

        // 2) Compute target back-stack position (where the last card sits).
        let backIndex = max(0, letters.count - 1)
        unreadEndOffset = stackOffset(for: backIndex)
        unreadEndRotation = stackRotation(for: backIndex)

        // 3) Slide the real top card off to the left…
        withAnimation(.easeIn(duration: 0.26)) {
            drag = CGSize(width: -viewportWidth * 1.15, height: 24)
            outcome = .unread(progress: 1)
        }

        // 4) …then at 0.26s, rotate the array and kick off the ghost coming
        //    back in from the upper left to land at the back of the stack.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            var next = letters
            let first = next.removeFirst()
            next.append(first)

            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) {
                letters = next
                drag = .zero
                unreadImage = image
            }
            unreadTrigger &+= 1
            pushUndo(.unread(topLetter))
        }

        // 5) After the ghost lands, tear it down.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26 + 0.60) {
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { unreadImage = nil }
            withAnimation(.easeOut(duration: 0.18)) {
                outcome = .idle
            }
            isCompletingGesture = false
            lastHapticBucket = 0
        }
    }

    // MARK: - Archive

    private func completeArchive() {
        guard letters.count >= 1 else { return }
        isCompletingGesture = true
        Haptics.success()
        PaperSound.shared.rustle(volume: 0.55)

        let archived = letters.first

        withAnimation(.easeIn(duration: 0.3)) {
            drag = CGSize(width: viewportWidth * 1.12, height: 12)
            outcome = .archive(progress: 1)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { if !letters.isEmpty { letters.removeFirst() } }
            withAnimation(.easeOut(duration: 0.22)) {
                drag = .zero; outcome = .idle
            }
            isCompletingGesture = false
            lastHapticBucket = 0
            if let archived { pushUndo(.archive(archived)) }
        }
    }

    // MARK: - Trash (crumple → arc → swallow)

    private func completeTrash(cardSize: CGSize) {
        guard let topLetter = letters.first else { return }
        isCompletingGesture = true
        Haptics.softTap()
        PaperSound.shared.crumple(volume: 0.85)

        // Where the live-crumple overlay was when the user released.
        // We hand this to the flight view so it starts *at the same
        // crumple value* rather than resetting to a flat paper.
        trashInitialCrumple = max(0.35, trashHighlight)

        // Snapshot a *simplified* version of the card (rectangle + text, no
        // Canvas layers) so `ImageRenderer` captures it reliably. If capture
        // fails for any reason the flight view falls back to drawing the same
        // simplified representation live — the crumple is guaranteed to be
        // visible either way.
        let renderer = ImageRenderer(
            content: SimpleLetterSnapshot(
                letter: topLetter,
                size: cardSize
            )
        )
        renderer.scale = UIScreen.main.scale
        trashImage   = renderer.uiImage
        trashLetter  = topLetter
        trashCardSize = cardSize

        // Flight points.  Target the TRASH ICON (the red chamber on
        // the left of the pill) rather than the pill's geometric
        // centre — the ball should appear to be sucked into the
        // icon, not the dividing line between icon and label.
        let start = CGPoint(x: topCardCenter.x + drag.width,
                            y: topCardCenter.y + drag.height)
        let pillHalfW = PillMetrics.trashW / 2
        let chamberHalfW = PillMetrics.chamber / 2
        let iconCenterX = trashPillCenter.x - pillHalfW + chamberHalfW
        let end = CGPoint(x: iconCenterX, y: trashPillCenter.y)
        // Arc peak well above the card + pill so the crumple reads as
        // flung toward / past the top of the frame before diving to trash.
        let apex = CGPoint(x: (start.x + end.x) / 2,
                           y: min(start.y, end.y) - 240)
        trashStart = start
        trashApex  = apex
        trashTarget = end
        isTrashing  = true
        trashTrigger &+= 1

        withAnimation(.easeIn(duration: 0.18)) {
            outcome = .trash(progress: 1)
        }

        // Total flight ≈ 1.15s — the drag already did the heavy
        // lifting on the crumple, so we just finish it, hold the ball
        // briefly, and arc into the trash pill.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) {
                if !letters.isEmpty { letters.removeFirst() }
                isTrashing  = false
                trashImage  = nil
                trashLetter = nil
            }
            withAnimation(.easeOut(duration: 0.22)) {
                drag = .zero; outcome = .idle
            }
            isCompletingGesture = false
            lastHapticBucket = 0
            pushUndo(.trash(topLetter))
        }
    }

    // MARK: - Undo

    private func pushUndo(_ action: UndoAction) {
        // Cap the stack so we don't accumulate forever.
        undoStack.append(action)
        if undoStack.count > 16 { undoStack.removeFirst() }
    }

    /// Pops the last action and replays it in reverse — swipe direction
    /// comes from the original action:
    ///   Archive → slides back in from the right.
    ///   Unread  → rises up from the back of the stack.
    ///   Trash   → flies out of the trash pill as a crumpled ball and
    ///             un-crumples into a flat letter on top.
    private func undoLastAction() {
        guard !isCompletingGesture, undoReentry == nil else {
            Haptics.softTap(); return
        }
        guard let last = undoStack.popLast() else {
            Haptics.softTap(); return
        }

        Haptics.tap()
        PaperSound.shared.rustle(volume: 0.7)

        let kind: UndoReentry.Kind
        switch last {
        case .unread:  kind = .unread
        case .archive: kind = .archive
        case .trash:   kind = .trash
        }

        // For Unread undo we need to remove the letter from the back
        // before reinserting at the front, so the deck stays at the
        // correct length.
        if case let .unread(letter) = last,
           let backIdx = letters.firstIndex(of: letter) {
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { letters.remove(at: backIdx) }
        }

        // Back-of-stack pose the Unread reentry should emerge from
        // (the slot that was the "back" when the letter originally flew
        // there — we use the NEXT back index = current count).
        let backIdx = min(letters.count, MailDesign.stackOffsets.count - 1)
        let reentry = UndoReentry(
            kind: kind,
            letter: last.letter,
            fromBackOffset: MailDesign.stackOffsets[backIdx],
            fromBackRotation: MailDesign.stackRotations[backIdx],
            trashPillCenter: trashPillCenter,
            targetCenter: topCardCenterOrFallback(),
            cardSize: currentCardSize()
        )
        undoReentry = reentry

        // When the reentry animation lands, swap the letter into the
        // deck at position 0 and tear down the overlay.
        // Handler lives in the overlay itself via its `onLand` closure
        // (see `undoReentryOverlay` in body).
    }

    /// Where the reentry animation should land (the on-screen top-card
    /// centre if we know it; otherwise a reasonable fallback).
    private func topCardCenterOrFallback() -> CGPoint {
        if topCardCenter != .zero { return topCardCenter }
        return CGPoint(x: viewportWidth / 2, y: 400)
    }

    /// Current card size, derived the same way the main body computes it.
    private func currentCardSize() -> CGSize {
        let w = min(328, viewportWidth - 44)
        return CGSize(width: w, height: w * (448.0 / 328.0))
    }

    /// Called by `UndoReentryView.onLand` — insert the letter at the
    /// front of the stack and drop the overlay.
    private func finishUndoReentry() {
        guard let reentry = undoReentry else { return }
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) {
            letters.insert(reentry.letter, at: 0)
            undoReentry = nil
        }
    }

    private func pulseTrashPill() {
        Haptics.thud()
        withAnimation(.interpolatingSpring(stiffness: 500, damping: 18)) {
            trashPulse = 1.12
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
                trashPulse = 1.0
            }
        }
    }
}

// MARK: - Unread flight

private struct UnreadFlightState {
    var offset: CGSize
    var scale: CGFloat
    var rotation: Double
    var opacity: CGFloat
}

private struct UnreadFlightView: View {
    let image: UIImage
    let trigger: Int
    let endOffset: CGSize
    let endRotation: Double
    let cardSize: CGSize

    var body: some View {
        KeyframeAnimator(
            initialValue: UnreadFlightState(
                offset: .zero, scale: 1.0, rotation: 0, opacity: 0
            ),
            trigger: trigger
        ) { state in
            Image(uiImage: image)
                .resizable()
                .frame(width: cardSize.width, height: cardSize.height)
                .rotationEffect(.degrees(state.rotation))
                .scaleEffect(state.scale)
                .offset(state.offset)
                .opacity(state.opacity)
                .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 3)
        } keyframes: { _ in
            // Phase A (0 → 0.22s): fade in off-screen upper-left, smaller.
            // Phase B (0.22 → 0.60s): fly to back-stack slot, rotating in.

            KeyframeTrack(\.offset) {
                LinearKeyframe(CGSize(width: -cardSize.width * 0.9,
                                      height: -cardSize.height * 0.35),
                               duration: 0.01)
                CubicKeyframe(CGSize(width: -cardSize.width * 0.55,
                                     height: -cardSize.height * 0.20),
                              duration: 0.22)
                CubicKeyframe(endOffset, duration: 0.38)
            }
            KeyframeTrack(\.scale) {
                LinearKeyframe(0.88, duration: 0.01)
                CubicKeyframe(0.92, duration: 0.22)
                CubicKeyframe(1.0,  duration: 0.38)
            }
            KeyframeTrack(\.rotation) {
                LinearKeyframe(-22, duration: 0.01)
                CubicKeyframe(-12, duration: 0.22)
                CubicKeyframe(endRotation, duration: 0.38)
            }
            KeyframeTrack(\.opacity) {
                LinearKeyframe(0.0, duration: 0.01)
                LinearKeyframe(1.0, duration: 0.10)
                LinearKeyframe(1.0, duration: 0.50)
            }
        }
    }
}

// MARK: - Trash flight

private struct TrashFlightState {
    var crumple: CGFloat = 0
    var ballMorph: CGFloat = 0
    var scale: CGFloat = 1
    var pos: CGPoint
    var rot: Double = 0
    var opacity: CGFloat = 1
}

private struct TrashFlightView: View {
    /// Optional: a captured snapshot of the card. `TrashFlightView` falls
    /// back to drawing a live simplified letter if this is `nil` so the
    /// crumple is always visible.
    let image: UIImage?
    let letter: Letter?
    let cardSize: CGSize
    let trigger: Int
    let startPoint: CGPoint
    let apexPoint: CGPoint
    let endPoint: CGPoint
    /// Starting crumple value — provided by the live drag overlay
    /// so this view picks up *exactly* where the user left off.
    let initialCrumple: CGFloat
    let onLand: () -> Void

    @State private var didLand = false

    var body: some View {
        GeometryReader { geo in
            Color.clear.onChange(of: trigger) { _, _ in didLand = false }
            
            let origin = geo.frame(in: .global)

            trashKeyframeAnimator(origin: origin)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func trashKeyframeAnimator(origin: CGRect) -> some View {
        KeyframeAnimator(
            initialValue: TrashFlightState(crumple: initialCrumple, pos: startPoint),
            trigger: trigger
        ) { state in
            flightBody(state: state, origin: origin)
        } keyframes: { _ in
            let shootUp = CGPoint(
                x: startPoint.x,
                y: startPoint.y - min(280, max(100, startPoint.y * 0.34))
            )
            // The live overlay already crumpled the paper during the
            // upward drag — this flight view picks up mid-crumple and
            // carries it home.
            //
            //   A 0   → 0.25  Finish the crumple (initialCrumple → 1.0)
            //                 while staying at the card's release
            //                 position.  Sheet rapidly folds the rest
            //                 of the way and crossfades to a paper ball.
            //   B 0.25 → 0.45  Formed ball holds briefly at the card's
            //                  position so the user reads "that's a
            //                  paper ball now".
            //   C 0.45 → 1.05  Ball arcs up and into the trash pill,
            //                  slipping BEHIND the pill's lid overlay.
            //   D 1.05 → 1.15  Swallow / fade.
            KeyframeTrack(\TrashFlightState.crumple) {
                CubicKeyframe(1.00, duration: 0.25)   // initialCrumple → 1
                LinearKeyframe(1.00, duration: 0.90)
            }
            KeyframeTrack(\TrashFlightState.ballMorph) {
                LinearKeyframe(0.0, duration: 0.12)   // brief sheet tail
                CubicKeyframe(1.0, duration: 0.18)    // crossfade to ball
                LinearKeyframe(1.0, duration: 0.85)
            }
            KeyframeTrack(\TrashFlightState.scale) {
                // Genie shrink.  The ball compacts during the
                // finish-crumple phase, holds briefly so the user
                // reads "that's a paper ball", then during the
                // arc to the trash icon it shrinks aggressively.
                // The final two keyframes do the Genie vanish —
                // from ~12 pt wide down to a single point,
                // disappearing INTO the trash icon.
                CubicKeyframe(0.42, duration: 0.25)   // crumple compacts
                LinearKeyframe(0.28, duration: 0.20)  // ball hold
                CubicKeyframe(0.10, duration: 0.35)   // mid-flight shrink
                CubicKeyframe(0.035, duration: 0.20)  // entering icon
                CubicKeyframe(0.00,  duration: 0.15)  // gone (genie)
            }
            KeyframeTrack(\TrashFlightState.rot) {
                CubicKeyframe(14.0,  duration: 0.25)  // small twist as it balls
                LinearKeyframe(18.0, duration: 0.20)  // hold
                CubicKeyframe(95.0,  duration: 0.45)
                LinearKeyframe(115.0, duration: 0.25)
            }
            KeyframeTrack(\TrashFlightState.pos) {
                LinearKeyframe(startPoint, duration: 0.38)   // finish crumple + ball hold
                CubicKeyframe(shootUp,     duration: 0.14)   // punch upward off the stack
                CubicKeyframe(apexPoint,  duration: 0.28)
                CubicKeyframe(endPoint,   duration: 0.25)
                LinearKeyframe(endPoint,   duration: 0.10)
            }
            KeyframeTrack(\TrashFlightState.opacity) {
                LinearKeyframe(1.0, duration: 1.05)
                LinearKeyframe(0.0, duration: 0.10)
            }
        }
    }

    @ViewBuilder
    private func flightBody(state: TrashFlightState, origin: CGRect) -> some View {
        // Uses `PaperCrumple` — a SINGLE deforming sheet that
        // crossfades to a `PaperBall`.  No 8-copy ghosting, no
        // separate halo shadow.  The shadow is baked into the
        // `PaperCrumple` itself and therefore travels with the
        // paper through scale/rotation/position.
        Group {
            if let letter {
                PaperCrumple(
                    letter: letter,
                    size: cardSize,
                    progress: state.crumple
                )
            } else {
                // Extremely unlikely fallback (would only hit if the
                // trash completion ran without a letter captured).
                PaperBall(
                    diameter: min(cardSize.width, cardSize.height) * 0.80,
                    progress: state.crumple
                )
                .frame(width: cardSize.width, height: cardSize.height)
            }
        }
        .rotationEffect(.degrees(state.rot))
        .scaleEffect(state.scale)
        .opacity(state.opacity)
        .position(x: state.pos.x - origin.minX,
                  y: state.pos.y - origin.minY)
        .onChange(of: state.pos) { _, new in
            if !didLand {
                let d = hypot(new.x - endPoint.x, new.y - endPoint.y)
                if d < 20 {
                    didLand = true
                    onLand()
                }
            }
        }
    }
}

// MARK: - Preferences

private struct TrashCenterKey: PreferenceKey {
    static var defaultValue: CGPoint = .zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        let v = nextValue()
        if v != .zero { value = v }
    }
}

private struct CardCenterKey: PreferenceKey {
    static var defaultValue: CGPoint = .zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        let v = nextValue()
        if v != .zero { value = v }
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

#Preview {
    MailInboxScreen()
}

private struct TopCardGestureModifier<G: Gesture>: ViewModifier {
    let isEnabled: Bool
    let gesture: G

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.highPriorityGesture(gesture)
        } else {
            content
        }
    }
}

// MARK: - Undo types

/// A completed action that can be reversed by the Undo pill.
enum UndoAction {
    case unread(Letter)    // was sent to the back of the stack
    case archive(Letter)   // swiped right off-screen
    case trash(Letter)     // crumpled into the trash button

    var letter: Letter {
        switch self {
        case let .unread(l), let .archive(l), let .trash(l): return l
        }
    }
}

/// Active reverse-flight state driving `UndoReentryView`.
struct UndoReentry: Identifiable, Equatable {
    enum Kind { case unread, archive, trash }
    let id = UUID()
    let kind: Kind
    let letter: Letter
    /// Rotation/offset of the back slot the letter should seem to emerge
    /// from (unread reentry only; ignored for archive/trash).
    let fromBackOffset: CGSize
    let fromBackRotation: Double
    /// Trash pill centre — the origin of the crumpled-ball reentry.
    let trashPillCenter: CGPoint
    /// Target centre on the card stack (where the top card sits).
    let targetCenter: CGPoint
    let cardSize: CGSize
}

// MARK: - Reverse trash flight state
//
// Same shape as `TrashFlightState` but updated by keyframes that
// mirror the forward trash flight exactly.  Kept as a separate
// type so the forward and reverse flights can coexist without
// field-ordering surprises.
private struct ReverseTrashState {
    var crumple: CGFloat = 1    // starts balled up
    var scale:   CGFloat = 0    // emerges from a point inside the pill
    var pos:     CGPoint
    var rot:     Double  = 115  // matches end rotation of forward
    var opacity: CGFloat = 1
}

// MARK: - Undo reentry renderer

/// Animates a single letter BACK onto the stack, playing the reverse of
/// the action that removed it.  While it runs the real top card stays
/// hidden behind this overlay; on completion we swap the letter into the
/// stack and drop the overlay.
private struct UndoReentryView: View {
    let reentry: UndoReentry
    let onLand: () -> Void

    /// 0 → just launched, 1 → landed on the card stack.
    @State private var progress: CGFloat = 0

    var body: some View {
        Group {
            switch reentry.kind {
            case .unread:
                positionedBody(unreadReentryBody)
            case .archive:
                positionedBody(archiveReentryBody)
            case .trash:
                // Trash uses its own keyframe-driven view — it needs
                // to traverse the exact reverse of the forward flight
                // path, which a single `progress` scrub can't express.
                trashReentryBody
            }
        }
        .onAppear {
            // Non-trash reentries still use the simple `progress`
            // scrub — animate it here.  Trash drives itself via
            // KeyframeAnimator inside `trashReentryBody`.
            guard reentry.kind != .trash else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
                    onLand()
                }
                return
            }
            let duration: Double = reentry.kind == .unread ? 0.55 : 0.60
            withAnimation(.spring(response: duration, dampingFraction: 0.82)) {
                progress = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { onLand() }
        }
    }

    /// Positions a simple-progress reentry body at the target
    /// centre in global coordinates.  Only used for unread / archive.
    private func positionedBody<V: View>(_ content: V) -> some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global)
            content
                .position(x: reentry.targetCenter.x - origin.minX,
                          y: reentry.targetCenter.y - origin.minY)
        }
        .ignoresSafeArea()
    }

    /// Paper emerging from the back slot and rising forward to the top.
    private var unreadReentryBody: some View {
        let p = progress
        let t = 1 - p
        // Start pose: back-of-stack transform; end pose: identity.
        return SimpleLetterSnapshot(letter: reentry.letter, size: reentry.cardSize)
            .frame(width: reentry.cardSize.width, height: reentry.cardSize.height)
            .rotationEffect(.degrees(reentry.fromBackRotation * Double(t)))
            .scaleEffect(0.92 + 0.08 * p)
            .offset(
                x: reentry.fromBackOffset.width * t,
                y: reentry.fromBackOffset.height * t
            )
            .opacity(0.1 + 0.9 * p)
            // Isolated in flight = full-rect drop shadow (strong read).  In the
            // stack we avoid `.shadow` on the card to prevent bleed through
            // the curl; depth there comes from `LetterCardOutsideShadow` + shade.
            .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 3)
    }

    /// Paper sliding in from the right edge (archive direction, reversed).
    private var archiveReentryBody: some View {
        let p = progress
        let t = 1 - p
        return SimpleLetterSnapshot(letter: reentry.letter, size: reentry.cardSize)
            .frame(width: reentry.cardSize.width, height: reentry.cardSize.height)
            .rotationEffect(.degrees(14 * Double(t)))
            .offset(
                x: reentry.cardSize.width * 1.4 * t,
                y: 14 * t
            )
            .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 5)
    }

    /// Keyframe-driven reverse flight.  Every track here is the
    /// *exact reverse* of the forward trash flight's corresponding
    /// track in `TrashFlightView`.  Forward emits `crumple: 0 → 1`,
    /// `scale: 1.0 → 0.48 → 0.32 → 0.14 → 0.02 → 0.00`, and
    /// `pos: start → start → apex → end → end` over 1.15 s; reverse
    /// plays those same waypoints in opposite order so the crumpled
    /// ball follows the identical spatial path back out, then
    /// uncrumples at the card.
    private var trashReentryBody: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global)
            // Emerge from the TRASH ICON — same point the forward
            // flight vanishes into, so the reverse genie reads as
            // an exact mirror.
            let pillHalfW = PillMetrics.trashW / 2
            let chamberHalfW = PillMetrics.chamber / 2
            let iconCenterX = reentry.trashPillCenter.x
                - pillHalfW + chamberHalfW
            let end   = CGPoint(x: iconCenterX,
                                y: reentry.trashPillCenter.y)
            let start = reentry.targetCenter
            let apex  = CGPoint(
                x: (start.x + end.x) / 2,
                y: min(start.y, end.y) - 240)
            let shootUp = CGPoint(
                x: start.x,
                y: start.y - min(280, max(100, start.y * 0.34)))

            KeyframeAnimator(
                initialValue: ReverseTrashState(pos: end),
                trigger: reentry.id
            ) { state in
                PaperCrumple(
                    letter: reentry.letter,
                    size: reentry.cardSize,
                    progress: state.crumple
                )
                .frame(width: reentry.cardSize.width,
                       height: reentry.cardSize.height)
                .rotationEffect(.degrees(state.rot))
                .scaleEffect(state.scale)
                .opacity(state.opacity)
                .position(x: state.pos.x - origin.minX,
                          y: state.pos.y - origin.minY)
            } keyframes: { _ in
                // Mirror of forward `TrashFlightState.scale` track:
                // reverse genie — emerges from a point inside the
                // trash icon, grows as it arcs back to the card,
                // and uncrumples to full size.
                KeyframeTrack(\ReverseTrashState.scale) {
                    LinearKeyframe(0.00,  duration: 0.05)  // hidden point
                    CubicKeyframe(0.035, duration: 0.15)   // emerging
                    CubicKeyframe(0.10,  duration: 0.20)   // climbing out
                    CubicKeyframe(0.28,  duration: 0.35)   // flying back
                    LinearKeyframe(0.42, duration: 0.20)   // ball hold
                    CubicKeyframe(1.00,  duration: 0.25)   // uncrumpled
                }
                // Mirror of forward `TrashFlightState.rot` track.
                KeyframeTrack(\ReverseTrashState.rot) {
                    LinearKeyframe(115.0, duration: 0.10)
                    CubicKeyframe(95.0,   duration: 0.25)
                    CubicKeyframe(18.0,   duration: 0.45)
                    LinearKeyframe(14.0,  duration: 0.10)
                    CubicKeyframe(0.0,    duration: 0.25)
                }
                // Mirror of forward `TrashFlightState.pos` track:
                // end → end → apex → start → start.
                KeyframeTrack(\ReverseTrashState.pos) {
                    LinearKeyframe(end,     duration: 0.10)
                    CubicKeyframe(apex,    duration: 0.25)
                    CubicKeyframe(shootUp, duration: 0.28)
                    CubicKeyframe(start,   duration: 0.14)
                    LinearKeyframe(start,  duration: 0.38)
                }
                // Mirror of forward `TrashFlightState.crumple` track.
                // Ball stays balled while flying, then uncrumples
                // over the final 0.25 s as the paper opens at the
                // target card.
                KeyframeTrack(\ReverseTrashState.crumple) {
                    LinearKeyframe(1.0, duration: 0.90)
                    CubicKeyframe(0.0, duration: 0.25)
                }
                // Opacity — full-on through the entire flight, then
                // fades out at the very end so SwiftUI tears down
                // the overlay without a pop.
                KeyframeTrack(\ReverseTrashState.opacity) {
                    LinearKeyframe(1.0, duration: 1.10)
                    LinearKeyframe(1.0, duration: 0.05)
                }
            }
        }
        .ignoresSafeArea()
    }
}
