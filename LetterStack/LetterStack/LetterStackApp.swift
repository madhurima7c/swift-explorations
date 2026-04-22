import SwiftUI

@main
struct LetterStackApp: App {
    init() {
        LetterTypography.registerBundledFonts()
        Haptics.prepare()
    }

    var body: some Scene {
        WindowGroup {
            MailInboxScreen()
        }
    }
}
