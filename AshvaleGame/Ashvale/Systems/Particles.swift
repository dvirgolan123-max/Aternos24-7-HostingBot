//
//  Particles.swift
//  Ashvale
//
//  Pooled CPU particles: muzzle flashes, blood, bullet impacts (dust,
//  splinters, sparks), smoke and bullet tracers.
//

import Foundation

final class ParticleSystem {
    struct Particle {
        var pos: Vec3
        var vel: Vec3
        var life: Float
        var maxLife: Float
        var size: Float
        var grow: Float
        var color: Vec4
        var kind: Float
        var gravity: Float
        var drag: Float
    }

    private(set) var particles: [Particle] = []
    private let capacity = 1600
    private var rng = RNG(seed: 99)
    /// Short-lived muzzle light (position, intensity).
    var light: (Vec3, Float) = (Vec3(0, 0, 0), 0)

    init() { particles.reserveCapacity(capacity) }

    private func add(_ p: Particle) {
        if particles.count >= capacity { particles.removeFirst(64) }
        particles.append(p)
    }

    func clear() { particles.removeAll(keepingCapacity: true) }

    func muzzleFlash(at p: Vec3, dir: Vec3, suppressed: Bool) {
        if !suppressed {
            add(Particle(pos: p + dir * 0.05, vel: dir * 1.5, life: 0.05, maxLife: 0.05, size: 0.16, grow: 1.5,
                         color: Vec4(1.0, 0.75, 0.35, 1.0), kind: 2, gravity: 0, drag: 0))
            add(Particle(pos: p + dir * 0.12, vel: dir * 3, life: 0.04, maxLife: 0.04, size: 0.09, grow: 0.5,
                         color: Vec4(1.0, 0.9, 0.6, 1.0), kind: 2, gravity: 0, drag: 0))
            light = (p + dir * 0.3, 2.5)
        }
        for _ in 0..<3 {
            let v = dir * rng.range(0.6, 1.5) + Vec3(rng.range(-0.2, 0.2), rng.range(0.1, 0.4), rng.range(-0.2, 0.2))
            add(Particle(pos: p, vel: v, life: 0.9, maxLife: 0.9, size: 0.05, grow: 0.35, color: Vec4(0.7, 0.7, 0.68, suppressed ? 0.15 : 0.28),
                         kind: 3, gravity: -0.2, drag: 1.5))
        }
    }

    func blood(at p: Vec3, dir: Vec3, amount: Int = 8) {
        for _ in 0..<amount {
            let v = dir * rng.range(0.5, 2.5) + Vec3(rng.range(-1, 1), rng.range(0, 1.5), rng.range(-1, 1))
            add(Particle(pos: p, vel: v, life: rng.range(0.35, 0.7), maxLife: 0.7, size: rng.range(0.025, 0.06), grow: 0.05,
                         color: Vec4(0.45, 0.02, 0.02, 0.95), kind: 0, gravity: 9, drag: 0.5))
        }
        add(Particle(pos: p, vel: dir * 0.3, life: 0.3, maxLife: 0.3, size: 0.12, grow: 0.4, color: Vec4(0.5, 0.05, 0.05, 0.5),
                     kind: 3, gravity: 0, drag: 2))
    }

    func impact(at p: Vec3, normal n: Vec3, surface: SurfaceKind) {
        let color: Vec4
        var sparks = false
        switch surface {
        case .metal:
            color = Vec4(0.7, 0.7, 0.68, 0.6)
            sparks = true
        case .wood:
            color = Vec4(0.55, 0.42, 0.28, 0.8)
        case .dirt, .grass:
            color = Vec4(0.4, 0.33, 0.25, 0.8)
        case .glass:
            color = Vec4(0.8, 0.85, 0.9, 0.7)
        case .water:
            color = Vec4(0.75, 0.8, 0.85, 0.7)
        case .flesh:
            blood(at: p, dir: n)
            return
        default:
            color = Vec4(0.65, 0.64, 0.6, 0.75)
        }
        for _ in 0..<7 {
            let v = n * rng.range(0.8, 3) + Vec3(rng.range(-1, 1), rng.range(0, 1.5), rng.range(-1, 1))
            add(Particle(pos: p + n * 0.02, vel: v, life: rng.range(0.3, 0.6), maxLife: 0.6, size: rng.range(0.012, 0.03), grow: 0,
                         color: color, kind: 0, gravity: 9, drag: 0.5))
        }
        add(Particle(pos: p + n * 0.05, vel: n * 0.5, life: 1.0, maxLife: 1.0, size: 0.08, grow: 0.5, color: Vec4(color.x, color.y, color.z, 0.35),
                     kind: 3, gravity: -0.1, drag: 2))
        if sparks {
            for _ in 0..<6 {
                let v = n * rng.range(2, 5) + Vec3(rng.range(-2, 2), rng.range(0, 2), rng.range(-2, 2))
                add(Particle(pos: p, vel: v, life: rng.range(0.1, 0.25), maxLife: 0.25, size: 0.008, grow: 0,
                             color: Vec4(1, 0.8, 0.4, 1), kind: 1, gravity: 9, drag: 0.2))
            }
        }
    }

    func tracer(from a: Vec3, to b: Vec3) {
        let d = b - a
        let len = vlength(d)
        guard len > 2 else { return }
        let dir = d / len
        let speed: Float = 350
        add(Particle(pos: a + dir * 1.5, vel: dir * speed, life: min(0.1, len / speed), maxLife: 0.1, size: 0.012, grow: 0,
                     color: Vec4(1, 0.85, 0.55, 0.85), kind: 1, gravity: 0, drag: 0))
    }

    func puff(at p: Vec3, color: Vec4, size: Float = 0.15) {
        add(Particle(pos: p, vel: Vec3(0, 0.3, 0), life: 0.8, maxLife: 0.8, size: size, grow: 0.4, color: color, kind: 3, gravity: 0, drag: 1))
    }

    func update(dt: Float) {
        var i = 0
        while i < particles.count {
            particles[i].life -= dt
            if particles[i].life <= 0 {
                particles.swapAt(i, particles.count - 1)
                particles.removeLast()
                continue
            }
            particles[i].vel.y -= particles[i].gravity * dt
            particles[i].vel *= max(0, 1 - particles[i].drag * dt)
            particles[i].pos += particles[i].vel * dt
            particles[i].size += particles[i].grow * dt
            i += 1
        }
        light.1 = max(0, light.1 - dt * 50)
    }

    func fill(_ scene: RenderScene) {
        for p in particles {
            let fade = min(1, p.life / (p.maxLife * 0.5))
            var c = p.color
            c.w *= fade
            let velKind = Vec4(p.vel.x, p.vel.y, p.vel.z, p.kind)
            scene.particles.append(ParticleInstance(posSize: Vec4(p.pos.x, p.pos.y, p.pos.z, p.size), color: c, velKind: velKind))
        }
        if light.1 > 0 {
            scene.uniforms.pointLight = Vec4(light.0.x, light.0.y, light.0.z, light.1)
        }
    }
}
