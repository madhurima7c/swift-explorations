import SwiftUI

// MARK: - Pill chrome
//
// Crisp white pill with a bright inner rim for depth.
//
//   • Body             : pure white @ 80 %.  Translucent enough that
//                        whatever is behind still reads through softly,
//                        but never reads as grey (which is what happens
//                        when you stack translucent material + a white
//                        tint on a light background).
//   • Inner rim        : white @ 95 %, 0.75 pt — adds a specular edge
//                        that gives the pill its glass depth without
//                        any gradient.
//   • Outer hairline   : black @ 6 %, 0.5 pt — a whisper of an outline
//                        to help the pill read against the sky.
//   • Soft shadow halo : 0 0 4.2 1 black @ 5 %
//   • Crisp outset rim : 0 0 0 1 black @ 7 %
private struct PillChrome: View {
    let cornerRadius: CGFloat
    let size: CGSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            // Shadow 2/2 — soft halo.  CSS: 0 0 4.2 1 black @ 5 %.
            RoundedRectangle(cornerRadius: cornerRadius + 1, style: .continuous)
                .fill(.black.opacity(0.05))
                .frame(width: size.width + 2, height: size.height + 2)
                .blur(radius: 4.2)

            // Shadow 1/2 — crisp 1 pt outset.  CSS: 0 0 0 1 black @ 7 %.
            RoundedRectangle(cornerRadius: cornerRadius + 1, style: .continuous)
                .fill(.black.opacity(0.07))
                .frame(width: size.width + 2, height: size.height + 2)

            // Body: a subtle frosted backdrop *plus* a near-opaque white
            // tint so text on the paper behind never bleeds through.
            // Reads as glass on the sky, but when a card drags past,
            // you see the pill as a solid, readable button — not a
            // translucent window.
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.fill(Color.white.opacity(0.82)))
                .overlay(
                    // Bright inner rim — glassy depth.
                    shape
                        .inset(by: 0.5)
                        .stroke(Color.white.opacity(0.95), lineWidth: 0.75)
                )
                .overlay(
                    // Whisper-soft outer hairline to define the edge.
                    shape.stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                )
                .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Progress fill

private struct ProgressFill: View {
    let pillSize: CGSize
    let chamberWidth: CGFloat
    let cornerRadius: CGFloat
    let progress: CGFloat
    let tint: Color

    var body: some View {
        let p = min(max(progress, 0), 1)
        let chamber = chamberWidth
        let width: CGFloat = p <= 0.5
            ? chamber * (p / 0.5)
            : chamber + (pillSize.width - chamber) * ((p - 0.5) / 0.5)

        Rectangle()
            .fill(tint)
            .frame(width: width, height: pillSize.height)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// A single 1 pt vertical stripe. On the resting white body it shows as a
/// dark hairline; as the progress fill reaches the separator it crossfades
/// to a white @ 55 % stripe so it stays visible on the coloured fill.
private struct PillSeparator: View {
    let height: CGFloat
    /// 0 = resting, 1 = fill has passed the separator.
    let progress: CGFloat

    var body: some View {
        // Crossfade centred at ~45 % progress (the fill reaches the
        // separator right around there).
        let t = Double(min(max((progress - 0.35) / 0.20, 0), 1))
        ZStack {
            Rectangle().fill(Color.black.opacity(0.14 * (1 - t)))
            Rectangle().fill(Color.white.opacity(0.21 * t))
        }
        .frame(width: 1, height: height)
    }
}

// MARK: - Common layout metrics
//
// 24 pt icon with 12 pt padding on each side → 48 pt square chamber.
// 48 pt pill height → 12 pt vertical padding around the icon.
// Separator is full-height (inset 1 pt top & bottom).
enum PillMetrics {
    static let corner: CGFloat   = 24
    static let height: CGFloat   = 48
    static let chamber: CGFloat  = 48          // square chamber
    static let unreadW: CGFloat  = 134
    static let trashW: CGFloat   = 134
    static let icon: CGFloat     = 24
}

// MARK: - Trash pill

struct TrashPill: View {
    var highlight: CGFloat
    var pulse: CGFloat = 1
    private var tint: Color { MailDesign.trash }

    var body: some View {
        let p = min(max(highlight, 0), 1)
        let size = CGSize(width: PillMetrics.trashW, height: PillMetrics.height)

        ZStack {
            PillChrome(cornerRadius: PillMetrics.corner, size: size)

            ProgressFill(
                pillSize: size,
                chamberWidth: PillMetrics.chamber,
                cornerRadius: PillMetrics.corner,
                progress: p,
                tint: tint
            )

            HStack(spacing: 0) {
                Image("icon_trash")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: PillMetrics.icon, height: PillMetrics.icon)
                    .foregroundStyle(p > 0.12 ? .white : tint)   // trash tint stays red
                    .frame(width: PillMetrics.chamber, height: PillMetrics.height)

                Text("Trash")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(p > 0.55 ? .white : tint)
                    .lineLimit(1)
                    .frame(width: PillMetrics.trashW - PillMetrics.chamber,
                           height: PillMetrics.height)
            }

            // Separator drawn ON TOP so it stays visible over the progress
            // fill. Full-height, flush with top/bottom.
            PillSeparator(height: PillMetrics.height, progress: p)
                .offset(x: -PillMetrics.trashW / 2 + PillMetrics.chamber)
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(pulse)
    }
}

// MARK: - Neutral pill (Unread / Archive)

struct NeutralActionPill: View {
    let title: String
    let iconName: String
    let tint: Color
    var highlight: CGFloat

    var body: some View {
        let p = min(max(highlight, 0), 1)
        let size = CGSize(width: PillMetrics.unreadW, height: PillMetrics.height)

        ZStack {
            PillChrome(cornerRadius: PillMetrics.corner, size: size)

            ProgressFill(
                pillSize: size,
                chamberWidth: PillMetrics.chamber,
                cornerRadius: PillMetrics.corner,
                progress: p,
                tint: tint
            )

            HStack(spacing: 0) {
                Image(iconName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: PillMetrics.icon, height: PillMetrics.icon)
                    .foregroundStyle(p > 0.12 ? .white : MailDesign.ink.opacity(0.88))
                    .frame(width: PillMetrics.chamber, height: PillMetrics.height)

                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(p > 0.55 ? .white : MailDesign.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .frame(width: PillMetrics.unreadW - PillMetrics.chamber,
                           height: PillMetrics.height)
            }

            PillSeparator(height: PillMetrics.height, progress: p)
                .offset(x: -PillMetrics.unreadW / 2 + PillMetrics.chamber)
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Icon-only pill (Undo)

/// Square, icon-only companion to `NeutralActionPill`.  Sits between
/// Unread and Archive and uses the exact same chrome + metrics as the
/// chamber of the flanking pills, so the three elements read as a set.
///
/// Resting icon tint is #8B8B8B (no undo history yet).  The moment the
/// user has actually performed an action — meaning tapping Undo will do
/// something — the icon flips to solid black to advertise that the
/// button is now "armed".  While the finger is down it also renders
/// black (same visual as the active state).
struct IconOnlyPill: View {
    let iconName: String
    /// True when there is at least one action on the undo stack.  The
    /// icon stays grey until this is true, at which point it turns
    /// black to indicate the button is live.
    var isActive: Bool = false
    var action: () -> Void = {}

    @State private var isPressed = false

    var body: some View {
        let size = CGSize(width: PillMetrics.chamber, height: PillMetrics.height)
        let iconIsBlack = isActive || isPressed
        ZStack {
            PillChrome(cornerRadius: PillMetrics.corner, size: size)

            Image(iconName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: PillMetrics.icon, height: PillMetrics.icon)
                .foregroundStyle(iconIsBlack ? MailDesign.ink : MailDesign.iconIdle)
                .animation(.easeOut(duration: 0.18), value: isActive)
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(isPressed ? 0.96 : 1)
        .animation(.easeOut(duration: 0.12), value: isPressed)
        .contentShape(RoundedRectangle(cornerRadius: PillMetrics.corner,
                                       style: .continuous))
        .opacity(isActive ? 1 : 0.96)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressed { isPressed = true } }
                .onEnded { value in
                    let inside = CGRect(origin: .zero, size: size)
                        .contains(value.location)
                    isPressed = false
                    if inside && isActive { action() }
                }
        )
    }
}
