import UIKit
import CoreHaptics

/// Haptics wrapper with Core Haptics as the primary path (works in every
/// mode on iPhone 8+ and is noticeably stronger/more reliable than the UIKit
/// feedback generators) and a UIKit fallback when the engine isn't available.
enum Haptics {
    private static let kit = UIKitHaptics()
    private static let core = CoreHapticsPlayer()

    static func prepare() {
        core.prepare()
        kit.prepare()
    }

    static func tick()    { core.play(.tick)    ?? kit.selection() }
    static func softTap() { core.play(.softTap) ?? kit.light() }
    static func tap()     { core.play(.tap)     ?? kit.medium() }
    static func thud()    { core.play(.thud)    ?? kit.rigid() }
    static func success() { core.play(.success) ?? kit.success() }
    static func warning() { core.play(.warning) ?? kit.warning() }
}

// MARK: - Core Haptics

private enum HapticKind { case tick, softTap, tap, thud, success, warning }

private final class CoreHapticsPlayer {
    private var engine: CHHapticEngine?

    func prepare() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = true
            engine.resetHandler = { [weak self] in
                try? self?.engine?.start()
            }
            engine.stoppedHandler = { _ in }
            try engine.start()
            self.engine = engine
        } catch {
            print("CoreHaptics prepare error:", error)
        }
    }

    /// Returns `Void?` — `nil` means Core Haptics isn't available / failed and
    /// the caller should use the UIKit fallback.
    @discardableResult
    func play(_ kind: HapticKind) -> Void? {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        if engine == nil { prepare() }
        guard let engine else { return nil }

        let events: [CHHapticEvent]
        switch kind {
        case .tick:
            events = [transient(intensity: 0.45, sharpness: 0.85)]
        case .softTap:
            events = [transient(intensity: 0.55, sharpness: 0.35)]
        case .tap:
            events = [transient(intensity: 0.85, sharpness: 0.55)]
        case .thud:
            events = [
                transient(intensity: 1.0, sharpness: 0.8),
                continuous(start: 0.02, duration: 0.10, intensity: 0.65, sharpness: 0.2)
            ]
        case .success:
            events = [
                transient(time: 0.00, intensity: 0.7, sharpness: 0.6),
                transient(time: 0.09, intensity: 1.0, sharpness: 0.9)
            ]
        case .warning:
            events = [
                transient(time: 0.00, intensity: 0.9, sharpness: 0.9),
                transient(time: 0.12, intensity: 0.9, sharpness: 0.9)
            ]
        }

        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try engine.start()
            try player.start(atTime: CHHapticTimeImmediate)
            return ()
        } catch {
            print("CoreHaptics play error:", error)
            return nil
        }
    }

    private func transient(time: TimeInterval = 0,
                           intensity: Float,
                           sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: time
        )
    }

    private func continuous(start: TimeInterval,
                            duration: TimeInterval,
                            intensity: Float,
                            sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: start,
            duration: duration
        )
    }
}

// MARK: - UIKit fallback (kept warm)

private final class UIKitHaptics {
    private let lightGen  = UIImpactFeedbackGenerator(style: .light)
    private let mediumGen = UIImpactFeedbackGenerator(style: .medium)
    private let rigidGen  = UIImpactFeedbackGenerator(style: .rigid)
    private let selectionGen = UISelectionFeedbackGenerator()
    private let noticeGen = UINotificationFeedbackGenerator()

    func prepare() {
        lightGen.prepare()
        mediumGen.prepare()
        rigidGen.prepare()
        selectionGen.prepare()
        noticeGen.prepare()
    }

    func selection() { selectionGen.prepare(); selectionGen.selectionChanged() }
    func light()     { lightGen.prepare();     lightGen.impactOccurred(intensity: 0.6) }
    func medium()    { mediumGen.prepare();    mediumGen.impactOccurred() }
    func rigid()     { rigidGen.prepare();     rigidGen.impactOccurred(intensity: 0.9) }
    func success()   { noticeGen.prepare();    noticeGen.notificationOccurred(.success) }
    func warning()   { noticeGen.prepare();    noticeGen.notificationOccurred(.warning) }
}
