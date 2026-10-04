//
//  AudioEngine.swift
//  Ashvale
//
//  Procedural audio: every sound effect is synthesized at startup (no audio
//  assets) and played through a pool of AVAudioPlayerNodes with distance
//  attenuation and stereo panning. Wind and rain ambience loops follow the
//  weather.
//

import Foundation
import AVFoundation

/// Offline synthesis helpers (platform independent math, Float samples).
enum Synth {
    static let rate: Float = 44100

    struct Biquad {
        var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
        var z1: Float = 0, z2: Float = 0

        static func bandpass(_ f: Float, q: Float) -> Biquad {
            let w = 2 * Float.pi * f / rate
            let alpha = sinf(w) / (2 * q)
            let a0 = 1 + alpha
            var b = Biquad()
            b.b0 = alpha / a0
            b.b1 = 0
            b.b2 = -alpha / a0
            b.a1 = -2 * cosf(w) / a0
            b.a2 = (1 - alpha) / a0
            return b
        }

        static func lowpass(_ f: Float, q: Float = 0.707) -> Biquad {
            let w = 2 * Float.pi * f / rate
            let alpha = sinf(w) / (2 * q)
            let c = cosf(w)
            let a0 = 1 + alpha
            var b = Biquad()
            b.b0 = (1 - c) / 2 / a0
            b.b1 = (1 - c) / a0
            b.b2 = (1 - c) / 2 / a0
            b.a1 = -2 * c / a0
            b.a2 = (1 - alpha) / a0
            return b
        }

        static func highpass(_ f: Float, q: Float = 0.707) -> Biquad {
            let w = 2 * Float.pi * f / rate
            let alpha = sinf(w) / (2 * q)
            let c = cosf(w)
            let a0 = 1 + alpha
            var b = Biquad()
            b.b0 = (1 + c) / 2 / a0
            b.b1 = -(1 + c) / a0
            b.b2 = (1 + c) / 2 / a0
            b.a1 = -2 * c / a0
            b.a2 = (1 - alpha) / a0
            return b
        }

        mutating func process(_ x: Float) -> Float {
            let y = b0 * x + z1
            z1 = b1 * x - a1 * y + z2
            z2 = b2 * x - a2 * y
            return y
        }
    }

    static func noise(_ rng: inout RNG) -> Float { rng.float() * 2 - 1 }

    static func normalize(_ s: inout [Float], peak: Float = 0.9) {
        var m: Float = 0.0001
        for v in s { m = max(m, abs(v)) }
        let k = peak / m
        for i in 0..<s.count { s[i] *= k }
    }

    /// Adds decaying echoes for outdoor reverberation.
    static func echo(_ s: inout [Float], delays: [Float], gains: [Float], lowpass: Float) {
        let src = s
        var lp = Biquad.lowpass(lowpass)
        let maxDelay = Int((delays.max() ?? 0) * rate)
        s.append(contentsOf: [Float](repeating: 0, count: maxDelay))
        var filtered = [Float](repeating: 0, count: src.count)
        for i in 0..<src.count { filtered[i] = lp.process(src[i]) }
        for (d, g) in zip(delays, gains) {
            let off = Int(d * rate)
            for i in 0..<filtered.count { s[i + off] += filtered[i] * g }
        }
    }

    static func gunshot(duration: Float, crack: Float, body: Float, thumpHz: Float, decay: Float, tail: Float, lp: Float, seed: UInt64) -> [Float] {
        var rng = RNG(seed: seed)
        let n = Int(duration * rate)
        var s = [Float](repeating: 0, count: n)
        var lpf = Biquad.lowpass(lp)
        var hp = Biquad.highpass(1800)
        for i in 0..<n {
            let t = Float(i) / rate
            let env = expf(-t * decay)
            let crackEnv = expf(-t * 90)
            var v = lpf.process(noise(&rng)) * env * body
            v += hp.process(noise(&rng)) * crackEnv * crack
            v += sinf(2 * .pi * thumpHz * t * (1 - t * 2)) * expf(-t * 22) * 0.9
            s[i] = v
        }
        if tail > 0 {
            echo(&s, delays: [0.07, 0.16, 0.33, 0.6], gains: [0.35 * tail, 0.25 * tail, 0.18 * tail, 0.1 * tail], lowpass: 1500)
        }
        normalize(&s)
        return s
    }

    static func noiseBurst(duration: Float, decay: Float, lp: Float, hp: Float = 20, seed: UInt64, attack: Float = 0.002) -> [Float] {
        var rng = RNG(seed: seed)
        let n = Int(duration * rate)
        var s = [Float](repeating: 0, count: n)
        var l = Biquad.lowpass(lp)
        var h = Biquad.highpass(hp)
        for i in 0..<n {
            let t = Float(i) / rate
            let env = min(1, t / attack) * expf(-t * decay)
            s[i] = h.process(l.process(noise(&rng))) * env
        }
        normalize(&s, peak: 0.8)
        return s
    }

    static func tone(freq: Float, duration: Float, decay: Float, partials: [Float] = [1], seed: UInt64 = 1, noiseAmt: Float = 0) -> [Float] {
        var rng = RNG(seed: seed)
        let n = Int(duration * rate)
        var s = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Float(i) / rate
            var v: Float = 0
            for (k, p) in partials.enumerated() {
                v += sinf(2 * .pi * freq * p * t) / Float(k + 1)
            }
            v += noise(&rng) * noiseAmt
            s[i] = v * expf(-t * decay) * min(1, t / 0.002)
        }
        normalize(&s, peak: 0.7)
        return s
    }

    /// Voice-like sound: sawtooth with pitch contour through formant filters.
    static func voice(duration: Float, f0: (Float) -> Float, formants: [(Float, Float)], rough: Float, seed: UInt64, env: (Float) -> Float) -> [Float] {
        var rng = RNG(seed: seed)
        let n = Int(duration * rate)
        var s = [Float](repeating: 0, count: n)
        var filters = formants.map { Biquad.bandpass($0.0, q: $0.1) }
        var phase: Float = 0
        for i in 0..<n {
            let t = Float(i) / rate
            let f = f0(t) * (1 + noise(&rng) * rough * 0.08)
            phase += f / rate
            if phase > 1 { phase -= 1 }
            let saw = phase * 2 - 1 + noise(&rng) * rough
            var v: Float = 0
            for k in 0..<filters.count { v += filters[k].process(saw) }
            s[i] = v * env(t / duration)
        }
        normalize(&s, peak: 0.8)
        return s
    }

    static func concat(_ parts: [[Float]], gap: Float = 0) -> [Float] {
        var out: [Float] = []
        for p in parts {
            out.append(contentsOf: p)
            out.append(contentsOf: [Float](repeating: 0, count: Int(gap * rate)))
        }
        return out
    }

    static func loopNoise(duration: Float, lp: Float, hp: Float, modRate: Float, crackle: Float, seed: UInt64) -> [Float] {
        var rng = RNG(seed: seed)
        let n = Int(duration * rate)
        var s = [Float](repeating: 0, count: n)
        var l = Biquad.lowpass(lp)
        var h = Biquad.highpass(hp)
        for i in 0..<n {
            let t = Float(i) / rate
            let mod = 0.65 + 0.35 * sinf(2 * .pi * modRate * t / duration * floorf(duration))
            var v = h.process(l.process(noise(&rng))) * mod
            if crackle > 0 && rng.float() < crackle { v += noise(&rng) * 0.8 }
            s[i] = v
        }
        // Crossfade the ends so the loop is seamless.
        let fade = Int(0.25 * rate)
        for i in 0..<fade {
            let k = Float(i) / Float(fade)
            s[i] = s[i] * k + s[n - fade + i] * (1 - k)
        }
        s.removeLast(fade)
        normalize(&s, peak: 0.6)
        return s
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func make(_ id: SoundID, variant v: Int) -> [Float] {
        let seed = UInt64(id.rawValue * 31 + v * 7 + 1)
        switch id {
        case .footstepGrass:
            return noiseBurst(duration: 0.16, decay: 30, lp: 2500, hp: 300, seed: seed, attack: 0.01)
        case .footstepConcrete:
            return mix(noiseBurst(duration: 0.1, decay: 60, lp: 5000, hp: 800, seed: seed), tone(freq: 90, duration: 0.1, decay: 50), 0.5)
        case .footstepWood:
            return mix(tone(freq: 160 + Float(v) * 20, duration: 0.18, decay: 28, partials: [1, 2.3], noiseAmt: 0.3), noiseBurst(duration: 0.08, decay: 60, lp: 3000, seed: seed), 0.6)
        case .footstepMetal:
            return mix(tone(freq: 520 + Float(v) * 40, duration: 0.3, decay: 14, partials: [1, 2.7, 4.1], noiseAmt: 0.1), noiseBurst(duration: 0.06, decay: 80, lp: 6000, seed: seed), 0.5)
        case .footstepWater:
            return noiseBurst(duration: 0.3, decay: 10, lp: 3500, hp: 500, seed: seed, attack: 0.03)
        case .jumpLand:
            return mix(tone(freq: 70, duration: 0.25, decay: 18), noiseBurst(duration: 0.15, decay: 30, lp: 1800, seed: seed), 0.6)
        case .vault:
            return noiseBurst(duration: 0.35, decay: 9, lp: 2200, hp: 200, seed: seed, attack: 0.05)
        case .doorOpen:
            return voice(duration: 0.7, f0: { 180 + 120 * $0 }, formants: [(900, 6), (2200, 8)], rough: 0.6, seed: seed) { t in sinf(.pi * t) * 0.6 }
        case .doorClose:
            return mix(tone(freq: 85, duration: 0.4, decay: 14, partials: [1, 1.6], noiseAmt: 0.2), noiseBurst(duration: 0.2, decay: 20, lp: 3000, seed: seed), 0.6)
        case .pickup, .equip:
            return noiseBurst(duration: 0.22, decay: 14, lp: 4000, hp: 600, seed: seed, attack: 0.02)
        case .drop:
            return mix(tone(freq: 110, duration: 0.15, decay: 30), noiseBurst(duration: 0.12, decay: 35, lp: 2500, seed: seed), 0.5)
        case .throwItem, .punchSwing, .meleeSwing:
            var s = [Float]()
            var rng = RNG(seed: seed)
            let dur: Float = id == .meleeSwing ? 0.35 : 0.25
            let n = Int(dur * rate)
            var bp = Biquad.bandpass(600, q: 1.5)
            for i in 0..<n {
                let t = Float(i) / Float(n)
                if i % 64 == 0 { bp = Biquad.bandpass(400 + 1600 * t, q: 1.4) }
                s.append(bp.process(noise(&rng)) * sinf(.pi * t))
            }
            normalize(&s, peak: 0.6)
            return s
        case .gunPistol:
            return gunshot(duration: 0.35, crack: 1.0, body: 0.7, thumpHz: 140, decay: 20, tail: 0.8, lp: 3500, seed: seed)
        case .gunSMG:
            return gunshot(duration: 0.28, crack: 0.9, body: 0.7, thumpHz: 150, decay: 24, tail: 0.6, lp: 3800, seed: seed)
        case .gunRifle:
            return gunshot(duration: 0.55, crack: 1.2, body: 0.9, thumpHz: 100, decay: 13, tail: 1.0, lp: 2800, seed: seed)
        case .gunShotgun:
            return gunshot(duration: 0.7, crack: 0.8, body: 1.2, thumpHz: 70, decay: 9, tail: 1.1, lp: 2000, seed: seed)
        case .gunSniper:
            return gunshot(duration: 0.9, crack: 1.4, body: 1.0, thumpHz: 80, decay: 8, tail: 1.4, lp: 2400, seed: seed)
        case .gunSuppressed:
            return mix(noiseBurst(duration: 0.18, decay: 30, lp: 1400, hp: 120, seed: seed), tone(freq: 240, duration: 0.05, decay: 90, noiseAmt: 0.4), 0.5)
        case .dryFire, .uiClick:
            return tone(freq: 2400, duration: 0.04, decay: 120, partials: [1, 1.7], noiseAmt: 0.5)
        case .reloadStart, .magOut:
            return concat([tone(freq: 1800, duration: 0.05, decay: 80, partials: [1, 2.2], noiseAmt: 0.5), noiseBurst(duration: 0.12, decay: 25, lp: 4000, hp: 900, seed: seed)])
        case .magIn:
            return concat([noiseBurst(duration: 0.06, decay: 40, lp: 4000, hp: 900, seed: seed), tone(freq: 1300, duration: 0.07, decay: 60, partials: [1, 2.5], noiseAmt: 0.6)])
        case .boltCycle, .chamber:
            return concat([tone(freq: 1500, duration: 0.06, decay: 70, partials: [1, 1.9], noiseAmt: 0.5),
                           tone(freq: 1100, duration: 0.07, decay: 60, partials: [1, 2.4], noiseAmt: 0.6)], gap: 0.09)
        case .shellInsert:
            return concat([noiseBurst(duration: 0.05, decay: 40, lp: 3500, hp: 500, seed: seed), tone(freq: 900, duration: 0.05, decay: 80, noiseAmt: 0.5)])
        case .hitFlesh:
            return mix(tone(freq: 95, duration: 0.2, decay: 25, noiseAmt: 0.3), noiseBurst(duration: 0.15, decay: 25, lp: 1200, seed: seed), 0.6)
        case .hitHard:
            return mix(tone(freq: 120, duration: 0.18, decay: 30, partials: [1, 2.1], noiseAmt: 0.3), noiseBurst(duration: 0.1, decay: 40, lp: 2500, seed: seed), 0.6)
        case .bulletImpact:
            return mix(noiseBurst(duration: 0.12, decay: 40, lp: 6000, hp: 1500, seed: seed), tone(freq: 2600 + Float(v) * 400, duration: 0.15, decay: 30, noiseAmt: 0.2), 0.7)
        case .infectedIdle:
            let base: Float = 85 + Float(v) * 12
            return voice(duration: 1.3, f0: { base + 10 * sinf($0 * 9) }, formants: [(600, 5), (1050, 6), (2400, 8)], rough: 0.5, seed: seed) { t in
                sinf(.pi * t) * (0.7 + 0.3 * sinf(t * 30))
            }
        case .infectedAlert:
            let base: Float = 260 + Float(v) * 30
            return voice(duration: 0.9, f0: { base + 160 * $0 }, formants: [(800, 4), (1300, 5), (2800, 7)], rough: 0.8, seed: seed) { t in
                min(1, t * 8) * (1 - t * 0.6)
            }
        case .infectedAttack:
            let base: Float = 140 + Float(v) * 20
            return voice(duration: 0.6, f0: { base + 60 * sinf($0 * 20) }, formants: [(700, 4), (1200, 5), (2500, 7)], rough: 0.9, seed: seed) { t in
                min(1, t * 10) * (1 - t)
            }
        case .infectedDeath:
            return voice(duration: 1.1, f0: { 180 - 110 * $0 }, formants: [(650, 5), (1100, 6)], rough: 0.6, seed: seed) { t in (1 - t) * min(1, t * 6) }
        case .infectedHurt:
            return voice(duration: 0.35, f0: { 200 - 60 * $0 }, formants: [(700, 4), (1250, 5)], rough: 0.7, seed: seed) { t in (1 - t) * min(1, t * 15) }
        case .playerHurt:
            return voice(duration: 0.32, f0: { 150 - 30 * $0 }, formants: [(500, 6), (1500, 8)], rough: 0.25, seed: seed) { t in (1 - t) * min(1, t * 20) }
        case .playerDeath:
            return voice(duration: 1.2, f0: { 140 - 60 * $0 }, formants: [(500, 6), (1400, 8)], rough: 0.3, seed: seed) { t in (1 - t) * min(1, t * 8) }
        case .heartbeat:
            return concat([tone(freq: 55, duration: 0.15, decay: 22), tone(freq: 50, duration: 0.15, decay: 22)], gap: 0.12)
        case .eat:
            return concat((0..<4).map { k in noiseBurst(duration: 0.12, decay: 30, lp: 2500, hp: 400, seed: seed + UInt64(k)) }, gap: 0.12)
        case .drink:
            return concat((0..<3).map { k in tone(freq: 300 + Float(k) * 40, duration: 0.18, decay: 18, partials: [1, 1.5], seed: seed + UInt64(k), noiseAmt: 0.4) }, gap: 0.15)
        case .bandage:
            return noiseBurst(duration: 0.6, decay: 4, lp: 6000, hp: 1500, seed: seed, attack: 0.05)
        case .medicate:
            return noiseBurst(duration: 0.4, decay: 6, lp: 9000, hp: 3000, seed: seed, attack: 0.02)
        case .vomit:
            return voice(duration: 1.0, f0: { 120 + 30 * sinf($0 * 7) }, formants: [(400, 3), (900, 4)], rough: 1.2, seed: seed) { t in sinf(.pi * t) }
        case .cough:
            return concat([noiseBurst(duration: 0.18, decay: 18, lp: 2000, hp: 200, seed: seed), noiseBurst(duration: 0.15, decay: 20, lp: 2000, hp: 200, seed: seed + 3)], gap: 0.1)
        case .sneeze:
            return concat([voice(duration: 0.3, f0: { 220 + 80 * $0 }, formants: [(300, 4), (2300, 6)], rough: 0.3, seed: seed) { t in t },
                           noiseBurst(duration: 0.3, decay: 12, lp: 7000, hp: 900, seed: seed + 9)])
        case .uiOpen, .uiClose:
            return noiseBurst(duration: 0.15, decay: 20, lp: 3500, hp: 700, seed: seed, attack: 0.03)
        case .ambienceWind:
            return loopNoise(duration: 6, lp: 600, hp: 60, modRate: 2, crackle: 0, seed: seed)
        case .rainLoop:
            return loopNoise(duration: 4, lp: 9000, hp: 1200, modRate: 1, crackle: 0.002, seed: seed)
        case .thunder:
            var s = noiseBurst(duration: 3.0, decay: 1.2, lp: 300, hp: 25, seed: seed, attack: 0.15)
            echo(&s, delays: [0.4, 0.9], gains: [0.5, 0.3], lowpass: 200)
            normalize(&s)
            return s
        }
    }

    static func mix(_ a: [Float], _ b: [Float], _ kb: Float) -> [Float] {
        var out = [Float](repeating: 0, count: max(a.count, b.count))
        for i in 0..<a.count { out[i] += a[i] }
        for i in 0..<b.count { out[i] += b[i] * kb }
        normalize(&out, peak: 0.85)
        return out
    }
}

final class AudioEngine {
    private let engine = AVAudioEngine()
    private var pool: [AVAudioPlayerNode] = []
    private var poolIndex = 0
    private var buffers: [Int: [AVAudioPCMBuffer]] = [:]
    private let windNode = AVAudioPlayerNode()
    private let rainNode = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    private var started = false
    var masterVolume: Float = GameSettings.shared.masterVolume
    private var heartbeatTimer: Float = 0
    private var menuMode = true
    private var lastThunder: Float = 0

    init() {}

    func start() {
        guard !started else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: Double(Synth.rate), channels: 1) else { return }
        format = fmt
        for _ in 0..<18 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: fmt)
            pool.append(p)
        }
        engine.attach(windNode)
        engine.connect(windNode, to: engine.mainMixerNode, format: fmt)
        engine.attach(rainNode)
        engine.connect(rainNode, to: engine.mainMixerNode, format: fmt)
        // Synthesize every sound (a few variants for frequent ones).
        for id in SoundID.allCases {
            let variants: Int
            switch id {
            case .footstepGrass, .footstepConcrete, .footstepWood, .infectedIdle, .infectedAlert, .infectedAttack, .bulletImpact: variants = 3
            default: variants = 1
            }
            buffers[id.rawValue] = (0..<variants).compactMap { makeBuffer(Synth.make(id, variant: $0), format: fmt) }
        }
        do {
            try engine.start()
            started = true
        } catch {
            print("Audio engine failed to start: \(error)")
            return
        }
        if let w = buffers[SoundID.ambienceWind.rawValue]?.first {
            windNode.scheduleBuffer(w, at: nil, options: .loops, completionHandler: nil)
            windNode.volume = 0
            windNode.play()
        }
        if let r = buffers[SoundID.rainLoop.rawValue]?.first {
            rainNode.scheduleBuffer(r, at: nil, options: .loops, completionHandler: nil)
            rainNode.volume = 0
            rainNode.play()
        }
    }

    private func makeBuffer(_ samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
        b.frameLength = AVAudioFrameCount(samples.count)
        if let ch = b.floatChannelData {
            samples.withUnsafeBufferPointer { src in
                ch[0].update(from: src.baseAddress!, count: samples.count)
            }
        }
        return b
    }

    func setAmbience(menu: Bool) {
        menuMode = menu
    }

    private func nextPlayer() -> AVAudioPlayerNode? {
        guard !pool.isEmpty else { return nil }
        poolIndex = (poolIndex + 1) % pool.count
        return pool[poolIndex]
    }

    func play2D(_ id: SoundID, volume: Float = 0.7) {
        play(id, volume: volume, pan: 0)
    }

    private func play(_ id: SoundID, volume: Float, pan: Float) {
        guard started, let list = buffers[id.rawValue], !list.isEmpty, let p = nextPlayer() else { return }
        let b = list[Int.random(in: 0..<list.count)]
        p.stop()
        p.volume = min(1, volume * masterVolume)
        p.pan = clampf(pan, -1, 1)
        p.scheduleBuffer(b, at: nil, options: [], completionHandler: nil)
        p.play()
    }

    /// Audible range (meters) at full event volume.
    private func range(_ id: SoundID) -> Float {
        switch id {
        case .gunPistol, .gunSMG: return 450
        case .gunRifle, .gunShotgun: return 700
        case .gunSniper: return 1000
        case .gunSuppressed: return 70
        case .thunder: return 5000
        case .infectedAlert, .infectedAttack, .infectedDeath: return 70
        case .infectedIdle, .infectedHurt: return 45
        case .bulletImpact, .hitFlesh, .hitHard: return 60
        case .doorOpen, .doorClose: return 35
        default: return 28
        }
    }

    func update(listener: Vec3, forward: Vec3, events: [SoundEvent], game: Game) {
        guard started else { return }
        let right = vnormalize(vcross(forward, Vec3(0, 1, 0)))
        for e in events {
            guard let p = e.position else {
                play(e.id, volume: e.volume, pan: 0)
                continue
            }
            let to = p - listener
            let d = vlength(to)
            let r = range(e.id)
            if d > r { continue }
            let att = 1 / (1 + (d / (r * 0.12)) * (d / (r * 0.12)))
            let pan = d > 0.5 ? vdot(to / d, right) * min(1, d / 4) : 0
            play(e.id, volume: e.volume * att, pan: pan * 0.8)
        }
        // Ambience follows the weather.
        let indoors = game.world.isIndoors(listener)
        let wind = (0.15 + game.env.windStrength * 0.5) * (indoors ? 0.35 : 1) * masterVolume
        windNode.volume = damp(windNode.volume, menuMode ? 0.2 * masterVolume : wind, 2, 1.0 / 60)
        let rain = game.env.rain * (indoors ? 0.45 : 0.9) * masterVolume
        rainNode.volume = damp(rainNode.volume, rain, 2, 1.0 / 60)
        if game.env.lightning > 0.95 && game.gameTime - lastThunder > 3 {
            lastThunder = game.gameTime
            play(.thunder, volume: 0.9, pan: Float.random(in: -0.5...0.5))
        }
        // Heartbeat when badly hurt.
        heartbeatTimer -= 1.0 / 60
        if game.player.alive && (game.stats.blood < 3200 || game.stats.health < 25) && heartbeatTimer <= 0 {
            heartbeatTimer = 1.1
            play(.heartbeat, volume: 0.6, pan: 0)
        }
    }
}
