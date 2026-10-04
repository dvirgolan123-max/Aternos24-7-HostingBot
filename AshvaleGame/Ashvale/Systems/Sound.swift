//
//  Sound.swift
//  Ashvale
//
//  Platform-independent sound events. Gameplay pushes events; the audio
//  engine (AVAudioEngine on iOS) synthesizes and plays them spatially.
//

import Foundation

enum SoundID: Int, CaseIterable {
    case footstepGrass, footstepConcrete, footstepWood, footstepMetal, footstepWater
    case jumpLand, vault
    case doorOpen, doorClose
    case pickup, drop, throwItem, equip
    case gunPistol, gunRifle, gunSMG, gunShotgun, gunSniper, gunSuppressed
    case dryFire, reloadStart, magOut, magIn, boltCycle, shellInsert, chamber
    case punchSwing, meleeSwing, hitFlesh, hitHard, bulletImpact
    case infectedIdle, infectedAlert, infectedAttack, infectedDeath, infectedHurt
    case playerHurt, playerDeath, heartbeat
    case eat, drink, bandage, medicate, vomit, cough, sneeze
    case uiClick, uiOpen, uiClose, ambienceWind, rainLoop, thunder
}

struct SoundEvent {
    var id: SoundID
    var position: Vec3?     // nil = 2D / non-spatial
    var volume: Float
    var pitch: Float
}

final class SoundQueue {
    private(set) var events: [SoundEvent] = []
    func play(_ id: SoundID, at p: Vec3? = nil, volume: Float = 1, pitch: Float = 1) {
        events.append(SoundEvent(id: id, position: p, volume: volume, pitch: pitch))
    }
    func drain() -> [SoundEvent] {
        let e = events
        events.removeAll(keepingCapacity: true)
        return e
    }
}
