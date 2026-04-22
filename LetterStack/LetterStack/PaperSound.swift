import AVFoundation

/// Generates short paper sounds on the fly with filtered noise.
/// We use `.playback` so the sounds play even when the phone's ring switch
/// is on silent.
final class PaperSound {
    static let shared = PaperSound()

    private let engine = AVAudioEngine()
    private let rustleNode = AVAudioPlayerNode()
    private let crumpleNode = AVAudioPlayerNode()
    private var rustleBuffer: AVAudioPCMBuffer?
    private var crumpleBuffer: AVAudioPCMBuffer?
    private var isConfigured = false

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    func activate() {
        guard !isConfigured else {
            if !engine.isRunning { try? engine.start() }
            return
        }
        isConfigured = true

        do {
            let session = AVAudioSession.sharedInstance()
            // `.playback` + `.mixWithOthers` → plays even when the ring switch
            // is on silent, and doesn't duck other audio (Music etc.).
            try session.setCategory(.playback,
                                    mode: .default,
                                    options: [.mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            print("PaperSound session error:", error)
        }

        let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        engine.attach(rustleNode)
        engine.attach(crumpleNode)
        engine.connect(rustleNode,  to: engine.mainMixerNode, format: fmt)
        engine.connect(crumpleNode, to: engine.mainMixerNode, format: fmt)

        rustleBuffer  = makeRustleBuffer(duration: 0.32, format: fmt)
        crumpleBuffer = makeCrumpleBuffer(duration: 0.30, format: fmt)

        do {
            try engine.start()
            rustleNode.play()
            crumpleNode.play()
        } catch {
            print("PaperSound engine start error:", error)
        }
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard
            let info = note.userInfo,
            let type = AVAudioSession.InterruptionType(rawValue: info[AVAudioSessionInterruptionTypeKey] as? UInt ?? 0)
        else { return }
        if type == .ended {
            try? AVAudioSession.sharedInstance().setActive(true)
            try? engine.start()
            rustleNode.play()
            crumpleNode.play()
        }
    }

    /// Dry paper slide — for unread / archive exits.
    func rustle(volume: Float = 0.75) {
        if !engine.isRunning { try? engine.start() }
        guard let buf = rustleBuffer else { return }
        rustleNode.volume = volume
        if !rustleNode.isPlaying { rustleNode.play() }
        rustleNode.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
    }

    /// Soft paper-dismiss — for trash. iOS does not offer a public “move to
    /// trash” audio API; this is a low, muffled scrunch (not the old burst
    /// noise, which read like a gunshot).
    func crumple(volume: Float = 0.38) {
        if !engine.isRunning { try? engine.start() }
        guard let buf = crumpleBuffer else { return }
        crumpleNode.volume = volume
        if !crumpleNode.isPlaying { crumpleNode.play() }
        crumpleNode.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
    }

    // MARK: - Synthesis

    private func makeRustleBuffer(duration: Double, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(duration * format.sampleRate)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let data = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = frameCount

        var low: Float = 0
        for i in 0..<Int(frameCount) {
            let t = Float(i) / Float(frameCount)
            let env: Float
            if t < 0.08 { env = t / 0.08 }
            else if t > 0.6 { env = max(0, (1 - t) / 0.4) }
            else { env = 1 }
            let white = Float.random(in: -1...1)
            low = low * 0.72 + white * 0.28
            let highBias = white - low
            let mix = 0.55 * highBias + 0.45 * white
            data[i] = mix * env * 0.55
        }
        return buf
    }

    private func makeCrumpleBuffer(duration: Double, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(duration * format.sampleRate)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let data = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = frameCount

        var lp: Float = 0
        var lp2: Float = 0
        for i in 0..<Int(frameCount) {
            let t = Float(i) / max(1, Float(frameCount - 1))
            // Smooth attack / decay — no sudden transients.
            let attack = min(1, t / 0.05)
            let decay = (t < 0.55) ? 1 : max(0, 1 - (t - 0.55) / 0.45)
            let env = attack * decay

            let n = Float.random(in: -1...1)
            lp = lp * 0.88 + n * 0.12
            lp2 = lp2 * 0.72 + lp * 0.28
            // Low-mid band only (removes harsh high crackle).
            let body = lp2 * 0.95
            data[i] = body * env * 0.42
        }
        return buf
    }
}
