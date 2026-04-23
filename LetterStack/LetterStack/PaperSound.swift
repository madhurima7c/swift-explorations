import AVFoundation

/// Mail action SFX. Prefers bundled Freesound clips (see `SoundFiles`); if a
/// file is missing, falls back to short procedural noise for that sound only.
/// Session: `.playback` + `.mixWithOthers` so audio plays in silent mode.
final class PaperSound {
    static let shared = PaperSound()

    private enum SoundFiles {
        /// Unread + Archive — paper rustle (`freesound_community-paper-rustle-81855`).
        static let paperRustleBase = "freesound_community-paper-rustle-81855"
        /// Trash — trash-can lid (`…dropping-trash-can-lid_zoomh2nxywav-87291`).
        static let trashLidBase =
            "freesound_community-075652_20131202_dropping-trash-can-lid_zoomh2nxywav-87291"
        /// Prefer your real `.mp3` in the app target; same basename as the download.
        static let tryExtensions = ["mp3", "m4a", "aac", "wav", "caf"]
    }

    private let engine = AVAudioEngine()
    private let rustleNode = AVAudioPlayerNode()
    private let crumpleNode = AVAudioPlayerNode()
    private var rustleBuffer: AVAudioPCMBuffer?
    private var crumpleBuffer: AVAudioPCMBuffer?
    private var rustleFile: AVAudioPlayer?
    private var trashLidFile: AVAudioPlayer?
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
            if !engine.isRunning, rustleBuffer != nil || crumpleBuffer != nil {
                try? engine.start()
            }
            return
        }
        isConfigured = true

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback,
                                    mode: .default,
                                    options: [.mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            print("PaperSound session error:", error)
        }

        rustleFile = loadBundledPlayer(base: SoundFiles.paperRustleBase)
        trashLidFile = loadBundledPlayer(base: SoundFiles.trashLidBase)

        rustleFile?.prepareToPlay()
        trashLidFile?.prepareToPlay()

        let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        if rustleFile == nil {
            engine.attach(rustleNode)
            engine.connect(rustleNode, to: engine.mainMixerNode, format: fmt)
            rustleBuffer = makeRustleBuffer(duration: 0.32, format: fmt)
        }
        if trashLidFile == nil {
            engine.attach(crumpleNode)
            engine.connect(crumpleNode, to: engine.mainMixerNode, format: fmt)
            crumpleBuffer = makeCrumpleBuffer(duration: 0.30, format: fmt)
        }

        guard rustleBuffer != nil || crumpleBuffer != nil else { return }
        do {
            try engine.start()
            if rustleBuffer != nil { rustleNode.play() }
            if crumpleBuffer != nil { crumpleNode.play() }
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
            if rustleBuffer != nil { rustleNode.play() }
            if crumpleBuffer != nil { crumpleNode.play() }
        }
    }

    private func loadBundledPlayer(base: String) -> AVAudioPlayer? {
        for ext in SoundFiles.tryExtensions {
            guard let url = Bundle.main.url(forResource: base, withExtension: ext) else { continue }
            if let p = try? AVAudioPlayer(contentsOf: url) {
                p.numberOfLoops = 0
                return p
            }
        }
        return nil
    }

    /// Paper rustle — Unread and Archive.
    func rustle(volume: Float = 0.75) {
        if rustleBuffer != nil, !engine.isRunning { try? engine.start() }
        if let p = rustleFile {
            p.volume = volume
            p.currentTime = 0
            p.play()
            return
        }
        guard let buf = rustleBuffer else { return }
        rustleNode.volume = volume
        if !rustleNode.isPlaying { rustleNode.play() }
        rustleNode.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
    }

    /// Trash-can lid — `completeTrash` (replaces procedural crumple when the MP3 is in the bundle).
    func crumple(volume: Float = 0.75) {
        if crumpleBuffer != nil, !engine.isRunning { try? engine.start() }
        if let p = trashLidFile {
            p.volume = volume
            p.currentTime = 0
            p.play()
            return
        }
        guard let buf = crumpleBuffer else { return }
        crumpleNode.volume = volume
        if !crumpleNode.isPlaying { crumpleNode.play() }
        crumpleNode.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
    }

    // MARK: - Synthesis (fallback when no file in bundle)

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
        var smooth: Float = 0
        for i in 0..<Int(frameCount) {
            let t = Float(i) / max(1, Float(frameCount - 1))
            let attack = min(1, t / 0.035)
            let decay = (t < 0.5) ? 1 : max(0, 1 - (t - 0.5) / 0.5)
            let env = attack * decay

            let n = Float.random(in: -1...1)
            lp = lp * 0.86 + n * 0.14
            lp2 = lp2 * 0.70 + lp * 0.30
            let body = lp2

            smooth = smooth * 0.97 + n * 0.03
            let hf = n - smooth
            let crinkle = min(abs(hf), 0.5) * 0.7

            let wobbleA = 0.78 + 0.22 * sin(2 * Float.pi * 3.0 * t)
            let wobbleB = 0.86 + 0.14 * sin(2 * Float.pi * 14.5 * t + 0.7)
            let mix = (body * 0.78 + crinkle * 0.22) * wobbleA * wobbleB
            data[i] = mix * env * 0.52
        }
        return buf
    }
}
