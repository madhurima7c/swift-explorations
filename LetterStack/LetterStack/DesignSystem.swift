import SwiftUI

enum MailDesign {
    // Palette
    static let sky         = Color(red: 208 / 255, green: 242 / 255, blue: 255 / 255) // #D0F2FF
    static let paper       = Color(red: 253 / 255, green: 253 / 255, blue: 251 / 255)
    static let paperWarm   = Color(red: 244 / 255, green: 242 / 255, blue: 236 / 255) // used for underside / vignette
    static let ink         = Color(red: 36 / 255, green: 36 / 255, blue: 36 / 255)
    static let mutedInk    = Color(red: 36 / 255, green: 36 / 255, blue: 36 / 255).opacity(0.26)
    static let secondary   = Color(red: 120 / 255, green: 120 / 255, blue: 120 / 255)
    /// Disabled / resting icon & label colour inside action pills — #8B8B8B.
    /// Flips to `ink` (solid black) the moment a gesture starts, then to
    /// white once the progress fill has swept past the chamber.
    static let iconIdle    = Color(red: 139 / 255, green: 139 / 255, blue: 139 / 255)
    static let link        = Color(red: 0 / 255, green: 120 / 255, blue: 206 / 255)

    // Actions
    static let trash       = Color(red: 254 / 255, green: 39 / 255, blue: 39 / 255)
    static let trashCap    = Color(red: 255 / 255, green: 76 / 255, blue: 76 / 255)

    /// Unread + Archive progress fill — exact hex #00A9EA.
    static let actionBlue  = Color(red: 0 / 255, green: 169 / 255, blue: 234 / 255)
    static let unreadTint  = actionBlue
    static let archiveTint = actionBlue

    // Pill
    static let pillFill         = Color.white
    static let pillBorder       = Color.black.opacity(0.06)
    static let pillSeparator    = Color.black.opacity(0.07)
    /// From the Figma MCP: tight 1pt shadow + very soft diffuse.
    static let pillShadowKey    = Color.black.opacity(0.08)
    static let pillShadowAmbient = Color.black.opacity(0.04)

    // Card — sharp stationery corners (~2 pt), not a UI “bubble card”.
    static let cardCorner: CGFloat = 2

    /// Outside-only stack shadow — blur is masked so **nothing** paints
    /// inside the card rounded rect. That prevents any “shadow patch”
    /// showing through the curl hole (native `.shadow` always bleeds
    /// slightly inward past the path).
    static let cardOutsideShadowTightOpacity: Double = 0.062
    static let cardOutsideShadowTightBlur: CGFloat = 2.6
    static let cardOutsideShadowTightY: CGFloat = 0.92
    static let cardOutsideShadowMidOpacity: Double = 0.038
    static let cardOutsideShadowMidBlur: CGFloat = 11
    static let cardOutsideShadowMidY: CGFloat = 2.75
    static let cardOutsideShadowSoftOpacity: Double = 0.026
    static let cardOutsideShadowSoftBlur: CGFloat = 22
    static let cardOutsideShadowSoftY: CGFloat = 4.9
    /// Feathered erase of card shadow in pocket+flap region (blur only, no
    /// stroked outline — avoids straight-line artefacts).
    static let cardShadowCurlPunchBlur: CGFloat = 18
    /// Warm-dark ink used for the 1 pt crisp outline around each card.
    static let cardOutlineColorBase = Color(
        red:   54 / 255,
        green: 48 / 255,
        blue:  40 / 255
    )
    static let cardOutlineColor: Color = cardOutlineColorBase.opacity(0.10)

    /// Stack arrangement — bigger rotation + offset variance than before
    /// so the stack reads as a **pile of paper with depth**, not one
    /// flat card. Each card casts its own shadow onto the one beneath.
    static let stackRotations: [Double] = [
         2.8,   // front
        -2.4,
         4.6,
        -1.2,
        -3.8,
         3.4,
        -2.6,
         1.8
    ]
    static let stackOffsets: [CGSize] = [
        CGSize(width:  0, height:  0),   // front
        CGSize(width:  3, height:  3),
        CGSize(width: -3, height:  4),
        CGSize(width:  2, height:  6),
        CGSize(width: -2, height:  7),
        CGSize(width:  3, height:  9),
        CGSize(width: -3, height: 10),
        CGSize(width:  1, height: 12)
    ]
}
