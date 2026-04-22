import SwiftUI
import UIKit
import CoreText

/// Registers the bundled Bogart Trial font files and exposes helpers to load
/// the correct PostScript name no matter what Apple ends up registering it as.
enum LetterTypography {

    // MARK: Registration

    private static var didRegister = false
    private static let fontFiles: [String] = [
        "Bogart-Regular-trial",
        "Bogart-Medium-trial",
        "Bogart-Semibold-trial",
        "Bogart-Bold-trial",
        "Bogart-Italic-trial"
    ]

    static func registerBundledFonts() {
        guard !didRegister else { return }
        didRegister = true
        for name in fontFiles {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
    }

    // MARK: Font resolution

    /// Candidate PostScript names Bogart Trial may register as.
    private static let regularCandidates = [
        "BogartTrial-Regular", "Bogart-Regular-trial", "Bogart-Regular",
        "BogartTrial-Medium",  "Bogart-Medium-trial",  "Bogart-Medium"
    ]
    private static let semiboldCandidates = [
        "BogartTrial-Semibold", "Bogart-Semibold-trial", "Bogart-Semibold",
        "BogartTrial-Bold",     "Bogart-Bold-trial",     "Bogart-Bold"
    ]
    private static let italicCandidates = [
        "BogartTrial-Italic", "Bogart-Italic-trial", "Bogart-Italic"
    ]

    static func letterRegular(_ size: CGFloat) -> Font {
        registerBundledFonts()
        if let name = firstInstalled(regularCandidates) { return .custom(name, size: size) }
        return .system(size: size, weight: .regular, design: .serif)
    }

    static func letterSemibold(_ size: CGFloat) -> Font {
        registerBundledFonts()
        if let name = firstInstalled(semiboldCandidates) { return .custom(name, size: size) }
        return .system(size: size, weight: .semibold, design: .serif)
    }

    static func letterItalic(_ size: CGFloat) -> Font {
        registerBundledFonts()
        if let name = firstInstalled(italicCandidates) { return .custom(name, size: size) }
        return .system(size: size, weight: .regular, design: .serif).italic()
    }

    private static func firstInstalled(_ names: [String]) -> String? {
        for name in names where UIFont(name: name, size: 12) != nil { return name }
        return nil
    }
}
