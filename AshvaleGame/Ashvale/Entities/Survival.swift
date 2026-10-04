//
//  Survival.swift
//  Ashvale
//
//  Survivor physiology: health, blood, hunger (energy), thirst (water),
//  stamina, body temperature, wetness, bleeding wounds, wound infection,
//  food poisoning, common cold, broken legs, pain and medication effects.
//

import Foundation

struct Bleed: Codable {
    var rate: Float       // ml per second
    var dirty: Bool       // caused by infected / dirty object: may get infected
    var age: Float = 0
}

struct SurvivalContext {
    var dt: Float
    var airTemp: Float
    var indoors: Bool
    var rain: Float
    var wind: Float
    var swimming: Bool
    var sprinting: Bool
    var moving: Bool
    var insulation: Float
    var waterproof: Float
    var drain: Float
}

struct SurvivalEvents {
    var messages: [(String, Bool)] = []
    var deathCause: String?
    var vomited = false
    var coughed = false
    var sneezed = false
}

final class SurvivorStats: Codable {
    static let maxEnergy: Float = 2500
    static let maxWater: Float = 2500
    static let maxBlood: Float = 5000

    var health: Float = 100
    var blood: Float = 5000
    var energy: Float = 950
    var water: Float = 850
    var stamina: Float = 100
    var bodyTemp: Float = 36.8
    var wetness: Float = 0
    var bleeds: [Bleed] = []
    var infectionRisk: Float = 0
    var woundInfection: Float = 0
    var foodPoisoning: Float = 0
    var cold: Float = 0
    var brokenLeg = false
    var splinted = false
    var legHeal: Float = 0
    var pain: Float = 0
    var painkillers: Float = 0
    var antibiotics: Float = 0
    var charcoal: Float = 0
    var vitamins: Float = 0
    var saline: Float = 0
    var morphine: Float = 0
    var shock: Float = 0
    var lastDamageCause = "Unknown"
    private var messageCooldowns: [String: Float] = [:]
    private var symptomTimer: Float = 0

    init() {}

    /// Independent copy (via Codable) for background saving.
    func copy() -> SurvivorStats {
        guard let d = try? JSONEncoder().encode(self), let c = try? JSONDecoder().decode(SurvivorStats.self, from: d) else { return self }
        return c
    }

    var isBleeding: Bool { !bleeds.isEmpty }
    var bleedRate: Float { bleeds.reduce(0) { $0 + $1.rate } }
    var hasFever: Bool { woundInfection > 0.25 }
    var isSick: Bool { woundInfection > 0.05 || foodPoisoning > 0.05 || cold > 0.1 }

    /// Maximum stamina given condition and carried weight.
    func maxStamina(weight: Float) -> Float {
        var m: Float = 100
        if energy < 300 { m -= 25 }
        if water < 300 { m -= 25 }
        if blood < 3500 { m -= 25 }
        if cold > 0.3 { m -= 10 }
        m -= max(0, weight - 15) * 1.6
        return max(20, m)
    }

    /// Movement speed multiplier from injuries and condition.
    var movementMultiplier: Float {
        var m: Float = 1
        if brokenLeg && morphine <= 0 { m *= splinted ? 0.55 : 0.4 }
        if blood < 3000 { m *= 0.8 }
        if health < 20 { m *= 0.85 }
        return m
    }

    var canSprint: Bool { !(brokenLeg && morphine <= 0) && stamina > 5 }
    var canJump: Bool { !(brokenLeg && morphine <= 0) && stamina > 12 }

    /// Weapon sway multiplier (pain, low blood, cold, stamina).
    var aimSway: Float {
        var s: Float = 1
        if painkillers <= 0 && morphine <= 0 { s += pain * 2.0 }
        if blood < 3800 { s += 0.6 }
        if bodyTemp < 35.5 { s += 0.8 }
        s += (1 - stamina / 100) * 0.6
        return s
    }

    /// 1 = full color, lower = desaturated (blood loss).
    var saturation: Float {
        return clampf(0.25 + (blood - 2500) / 2000 * 0.75, 0.25, 1)
    }

    private func notify(_ ev: inout SurvivalEvents, _ text: String, important: Bool = false, every: Float = 45) {
        if let t = messageCooldowns[text], t > 0 { return }
        messageCooldowns[text] = every
        ev.messages.append((text, important))
    }

    // MARK: Damage

    func damage(health dh: Float, blood db: Float = 0, cause: String) {
        health -= dh
        blood -= db
        pain = min(1, pain + dh / 60)
        shock = min(1, shock + dh / 80)
        lastDamageCause = cause
    }

    func addBleed(rate: Float, dirty: Bool) {
        bleeds.append(Bleed(rate: rate, dirty: dirty))
        if dirty { infectionRisk += 0.35 }
    }

    // MARK: Treatments

    func bandage(clean: Bool) -> Bool {
        guard !bleeds.isEmpty else { return false }
        // Treat the worst wound first.
        if let i = bleeds.indices.max(by: { bleeds[$0].rate < bleeds[$1].rate }) {
            let wasDirty = bleeds[i].dirty
            bleeds.remove(at: i)
            if !clean { infectionRisk += 0.2 } else if wasDirty { infectionRisk += 0.1 }
        }
        return true
    }

    func disinfect() {
        infectionRisk = 0
        for i in 0..<bleeds.count { bleeds[i].dirty = false }
    }

    // MARK: Simulation

    func update(_ c: SurvivalContext) -> SurvivalEvents {
        var ev = SurvivalEvents()
        let dt = c.dt
        for (k, v) in messageCooldowns { messageCooldowns[k] = v - dt }

        // Metabolism.
        var burn: Float = 0.42
        var thirst: Float = 0.55
        if c.moving { burn *= 1.4; thirst *= 1.3 }
        if c.sprinting { burn *= 1.9; thirst *= 1.8 }
        if bodyTemp < 36 { burn *= 1.3 }
        if bodyTemp > 38 { thirst *= 1.8 }
        energy = max(0, energy - burn * dt * c.drain)
        water = max(0, water - thirst * dt * c.drain)

        // Stamina regenerates when not sprinting.
        if !c.sprinting {
            let regen: Float = (energy < 300 || water < 300) ? 6 : 12
            stamina = min(100, stamina + regen * dt)
        }

        // Bleeding.
        if !bleeds.isEmpty {
            for i in 0..<bleeds.count {
                bleeds[i].age += dt
                blood -= bleeds[i].rate * dt
            }
            // Small cuts clot on their own.
            bleeds.removeAll { $0.rate < 3 && $0.age > 90 }
            lastDamageCause = "Blood loss"
            notify(&ev, "You are bleeding", important: true, every: 20)
        }

        // Infection from dirty wounds.
        if infectionRisk > 0 {
            infectionRisk = max(0, infectionRisk - dt * 0.002)
            if woundInfection <= 0 && Float.random(in: 0...1) < infectionRisk * dt * 0.004 {
                woundInfection = 0.02
                notify(&ev, "Your wound looks infected", important: true, every: 120)
            }
        }
        if woundInfection > 0 {
            if antibiotics > 0 {
                woundInfection = max(0, woundInfection - dt * 0.006)
            } else {
                woundInfection = min(1, woundInfection + dt * 0.0016)
            }
            if woundInfection > 0.35 {
                health -= dt * 0.12 * woundInfection
                lastDamageCause = "Wound infection"
                notify(&ev, "You feel feverish", important: true, every: 60)
            }
        }

        // Food poisoning.
        if foodPoisoning > 0 {
            foodPoisoning = max(0, foodPoisoning - dt * (charcoal > 0 ? 0.01 : 0.0018))
            health -= dt * 0.04 * foodPoisoning
            symptomTimer += dt
            if symptomTimer > 25 && Float.random(in: 0...1) < foodPoisoning * 0.6 {
                symptomTimer = 0
                ev.vomited = true
                water = max(0, water - 250)
                energy = max(0, energy - 200)
                notify(&ev, "You threw up", important: true, every: 10)
            }
            lastDamageCause = "Food poisoning"
        }

        // Common cold.
        if bodyTemp < 35.6 && cold < 0.05 && Float.random(in: 0...1) < dt * 0.004 * (vitamins > 0 ? 0.3 : 1) {
            cold = 0.3
            notify(&ev, "You caught a cold", important: true, every: 120)
        }
        if cold > 0 {
            cold = max(0, cold - dt * (vitamins > 0 ? 0.004 : 0.0012) * (bodyTemp > 36.3 ? 1.5 : 0.5))
            symptomTimer += dt * 0.5
            if symptomTimer > 30 && Float.random(in: 0...1) < 0.5 {
                symptomTimer = 0
                if Float.random(in: 0...1) < 0.5 { ev.sneezed = true } else { ev.coughed = true }
            }
        }

        // Temperature and wetness.
        if c.swimming {
            wetness = 1
        } else if !c.indoors && c.rain > 0.05 {
            wetness = min(1, wetness + c.rain * (1 - c.waterproof * 0.9) * dt * 0.012)
        } else {
            let dry: Float = c.indoors ? 0.006 : 0.003
            wetness = max(0, wetness - dt * dry * (c.airTemp > 10 ? 1.4 : 0.7))
        }
        let env = c.indoors ? max(c.airTemp + 5, 13) : c.airTemp
        let ins = c.insulation * (1 - wetness * 0.6)
        var comfort = env + ins * 20 - wetness * 9 - (c.indoors ? 0 : c.wind * 4)
        if c.sprinting { comfort += 6 } else if c.moving { comfort += 2.5 }
        if c.swimming { comfort -= 10 }
        var target: Float = 36.8
        if comfort < 13 { target = 36.8 - (13 - comfort) * 0.35 }
        if comfort > 27 { target = 36.8 + (comfort - 27) * 0.15 }
        if woundInfection > 0.25 { target += 1.6 * woundInfection }
        target = clampf(target, 30, 41)
        let rate: Float = target < bodyTemp ? 0.0035 : 0.006
        bodyTemp += (target - bodyTemp) * min(1, rate * dt * 3)
        if bodyTemp < 35.5 { notify(&ev, bodyTemp < 34.5 ? "You are freezing" : "You feel cold", important: bodyTemp < 34.5, every: 50) }
        if bodyTemp < 35 {
            health -= dt * (bodyTemp < 34 ? 0.45 : 0.15)
            lastDamageCause = "Hypothermia"
        }
        if bodyTemp > 39.2 && woundInfection < 0.25 {
            water -= dt * 0.8
            notify(&ev, "You are overheating", every: 60)
        }

        // Starvation / dehydration.
        if energy < 400 { notify(&ev, energy < 150 ? "You are starving" : "You are hungry", important: energy < 150, every: 70) }
        if water < 400 { notify(&ev, water < 150 ? "You are severely dehydrated" : "You are thirsty", important: water < 150, every: 60) }
        if energy <= 0 {
            health -= dt * 0.28
            lastDamageCause = "Starvation"
        }
        if water <= 0 {
            health -= dt * 0.42
            lastDamageCause = "Dehydration"
        }

        // Blood regeneration and saline.
        if saline > 0 {
            blood = min(SurvivorStats.maxBlood, blood + dt * 4)
        }
        if bleeds.isEmpty && energy > 400 && water > 400 && blood < SurvivorStats.maxBlood {
            blood = min(SurvivorStats.maxBlood, blood + dt * 1.1)
            energy -= dt * 0.08
            water -= dt * 0.12
        }
        if blood < 3500 { notify(&ev, "You feel dizzy", important: true, every: 40) }
        if blood < 2600 {
            health -= dt * 0.5
            lastDamageCause = "Blood loss"
        }

        // Health regeneration.
        if blood > 4500 && energy > 900 && water > 900 && bleeds.isEmpty && bodyTemp > 35.8 && woundInfection < 0.1 && foodPoisoning < 0.05 {
            health = min(100, health + dt * 0.06)
        }

        // Broken leg healing.
        if brokenLeg {
            if splinted {
                legHeal += dt
                if legHeal > 360 {
                    brokenLeg = false
                    splinted = false
                    legHeal = 0
                    ev.messages.append(("Your leg has healed", false))
                }
            }
            if morphine <= 0 { pain = max(pain, 0.5) }
            notify(&ev, "Your leg is broken", important: true, every: 90)
        }

        // Timers.
        pain = max(0, pain - dt * 0.02)
        shock = max(0, shock - dt * 0.05)
        painkillers = max(0, painkillers - dt)
        antibiotics = max(0, antibiotics - dt)
        charcoal = max(0, charcoal - dt)
        vitamins = max(0, vitamins - dt)
        saline = max(0, saline - dt)
        morphine = max(0, morphine - dt)

        health = min(100, health)
        if blood < 1800 {
            ev.deathCause = "Blood loss"
        } else if health <= 0 {
            ev.deathCause = lastDamageCause
        }
        return ev
    }
}
