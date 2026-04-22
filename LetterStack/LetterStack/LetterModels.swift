import Foundation

struct Letter: Identifiable, Equatable {
    let id: UUID
    var fromLabel: String
    var fromName: String
    var fromEmail: String
    var dateLabel: String
    var subject: String
    var body: String

    static func sampleDeck(count: Int) -> [Letter] {
        // Each entry: (name, email, day, subject, body + sign-off).
        // Some receipts / system mails intentionally skip a personal
        // sign-off to keep the tone varied across the stack.
        let entries: [(String, String, String, String, String)] = [
            (
                "Maya Okafor", "maya@parallelstudio.co", "Today",
                "Offer letter: Product Designer role",
                """
                Thanks for the lovely chat yesterday. I put together a short draft of what a \
                first-month plan could look like and tucked it below. No pressure — just wanted \
                you to have something to look at over coffee.

                Let me know if Thursday still works for the paperwork call.

                Best,
                Maya
                """
            ),
            (
                "Ishaan Rao", "ishaan.rao@northkite.io", "Today",
                "Re: Portfolio review — a few notes",
                """
                I read the deck twice. Lots to love — especially the way you framed the \
                onboarding problem. A couple of small asks: could we see the numbers behind \
                the pricing slide, and is the hero shot placeholder final?

                Loosely proposing a short call this week to walk through edits.

                Cheers,
                Ishaan
                """
            ),
            (
                "Celeste Huang", "celeste@kelpandclover.com", "Yesterday",
                "Tuesday supper club, in or out?",
                """
                Short one from my kitchen: making the slow pasta again on Tuesday. \
                I have room for four. Bring something fizzy or nothing at all — up to you. \
                Let me know by Monday so I can hunt down a second pack of semolina.

                xo,
                Celeste
                """
            ),
            (
                "Dorian West", "d.west@halfmoonmail.com", "Mon",
                "Demo day follow-ups + decks",
                """
                Wrapping up demo day follow-ups. Attaching the investor-facing deck and the \
                founder-facing one (they diverge on the traction slides). If anything looks \
                off, nudge me tonight — I'm sending the final pass first thing tomorrow.

                Thanks,
                Dorian
                """
            ),
            (
                "Ayaan Farooqi", "ayaan@roost.studio", "Mon",
                "Signed NDA — ready when you are",
                """
                Countersigned and attached. Happy to jump on a call this week to align on \
                scope and timelines — Wednesday afternoon or Thursday morning both work on \
                my end. Just say the word.

                Best,
                Ayaan
                """
            ),
            (
                "Nola Ibarra", "nola@thesoftletter.press", "Sun",
                "Printing proof is in (photos inside)",
                """
                The latest proof came back this morning and I think we're almost there. The \
                trim is finally clean, though the duplex is still a hair warmer than the \
                file. A pair of colour chips tucked inside — let me know which you'd like \
                to push to print.

                Talk soon,
                Nola
                """
            ),
            (
                "Kai Lindqvist", "kai@fieldandfernmag.com", "Sat",
                "Your subscription renewed · receipt",
                """
                Thanks for sticking with us another year. Your annual subscription to Field & \
                Fern has renewed and your next issue ships at the end of the month.

                Receipt attached for your records. Reply to this note if anything's off.

                — The Field & Fern team
                """
            ),
            (
                "Priya Shanker", "priya@orbitlabs.ai", "Fri",
                "Design system sync — agenda draft",
                """
                Draft agenda for Thursday's sync below — flag anything you'd like added or \
                swapped out and I'll lock it in by EOD Wednesday. Mostly stewardship updates \
                and the proposal for a shared icon spec.

                See you then,
                Priya
                """
            ),
            (
                "Rowan Delgado", "rowan@latepost.co", "Fri",
                "Your letter went out today",
                """
                Quick note to let you know your letter was picked up this afternoon and is \
                on its way. Tracking link below — it should land later this week, depending \
                on the weather front rolling through the Midwest.

                Warmly,
                Rowan
                """
            ),
            (
                "Thalia Moreau", "thalia@figtree.bakery", "Thu",
                "Saturday croissants — reserved a box",
                """
                Held a box of the plain and two of the pain-au-chocolat for you this Saturday. \
                If you want the canelés too, let me know by Friday and I'll pull them from the \
                morning bake.

                À bientôt,
                Thalia
                """
            )
        ]

        return (0..<count).map { i in
            let e = entries[i % entries.count]
            return Letter(
                id: UUID(),
                fromLabel: "From:",
                fromName: e.0,
                fromEmail: e.1,
                dateLabel: e.2,
                subject: e.3,
                body: e.4
            )
        }
    }
}

enum SwipeOutcome: Equatable {
    case idle
    case unread(progress: CGFloat)
    case archive(progress: CGFloat)
    case trash(progress: CGFloat)

    var progress: CGFloat {
        switch self {
        case .idle: return 0
        case let .unread(p), let .archive(p), let .trash(p): return p
        }
    }
}
