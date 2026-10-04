//
//  SaveSystem.swift
//  Ashvale
//
//  Saves and restores: player position, camera, survival stats, inventory
//  (hands, clothing, cargo, quick slots), every item lying in the world
//  (dropped items and remaining loot), doors, time of day, weather and
//  previous bodies. One save per server profile.
//

import Foundation

struct SavedWorldItem: Codable {
    var item: ItemInstance
    var position: Vec3
    var yaw: Float
}

struct SavedCorpse: Codable {
    var position: Vec3
    var yaw: Float
    var skin: Vec3
    var hair: Vec3
    var forward: Bool
}

struct SaveData: Codable {
    var version = 1
    var serverID: String
    var savedAt: Date
    var location: String
    // Player.
    var position: Vec3
    var yaw: Float
    var camYaw: Float
    var camPitch: Float
    var firstPerson: Bool
    var crouched: Bool
    var skin: Vec3
    var hair: Vec3
    var longHair: Bool
    var stats: SurvivorStats
    var equipment: Equipment
    var record: LifeRecord
    var timeAlive: Float
    var flashlightOn: Bool
    // World.
    var items: [SavedWorldItem]
    var spawnedSpots: [Int]
    var openDoors: [Int]
    var hour: Float
    var day: Int
    var weather: Int
    var cloud: Float
    var rain: Float
    var fog: Float
    var wetness: Float
    var corpses: [SavedCorpse]
}

struct SaveMeta: Codable {
    var serverID: String
    var day: Int
    var hour: Float
    var location: String
    var survived: Float
    var savedAt: Date
}

enum SaveSystem {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("Ashvale", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func saveURL(_ id: String) -> URL { directory.appendingPathComponent("save_\(id).json") }
    static func metaURL(_ id: String) -> URL { directory.appendingPathComponent("meta_\(id).json") }

    /// Builds a snapshot. With `copy` the item graph is deep-copied so it can be encoded off the main thread.
    static func makeSnapshot(_ g: Game, serverID: String, copy: Bool = false) -> SaveData {
        let p = g.player
        let items = g.items.items.values.map { SavedWorldItem(item: copy ? $0.item.clone() : $0.item, position: $0.position, yaw: $0.yaw) }
        let doors = g.world.doors.indices.filter { g.world.doors[$0].isOpen }
        let corpses = g.corpses.map { SavedCorpse(position: $0.position, yaw: 0, skin: $0.appearance.skin, hair: $0.appearance.hair, forward: false) }
        return SaveData(serverID: serverID, savedAt: Date(), location: g.world.location(at: p.position)?.name ?? "Wilderness",
                        position: p.position, yaw: p.yaw, camYaw: g.camYaw, camPitch: g.camPitch, firstPerson: g.firstPerson,
                        crouched: p.body.stance == .crouched, skin: p.appearance.skin, hair: p.appearance.hair, longHair: p.appearance.longHair,
                        stats: copy ? g.stats.copy() : g.stats, equipment: copy ? g.equipment.clone() : g.equipment, record: g.record, timeAlive: p.timeAlive, flashlightOn: g.flashlightOn,
                        items: items, spawnedSpots: Array(g.items.spawnedSpots), openDoors: doors,
                        hour: g.env.hour, day: g.env.day, weather: g.env.weather.rawValue, cloud: g.env.cloud, rain: g.env.rain,
                        fog: g.env.fog, wetness: g.env.wetness, corpses: corpses)
    }

    @discardableResult
    static func save(_ g: Game, serverID: String) -> Bool {
        guard g.player.alive else { return false }
        let snap = makeSnapshot(g, serverID: serverID)
        let meta = SaveMeta(serverID: serverID, day: snap.day, hour: snap.hour, location: snap.location, survived: snap.timeAlive, savedAt: snap.savedAt)
        do {
            let enc = JSONEncoder()
            let data = try enc.encode(snap)
            try data.write(to: saveURL(serverID), options: .atomic)
            try enc.encode(meta).write(to: metaURL(serverID), options: .atomic)
            return true
        } catch {
            print("Save failed: \(error)")
            return false
        }
    }

    private static let saveQueue = DispatchQueue(label: "ashvale.save", qos: .utility)

    /// Snapshot on the calling thread, encode and write in the background (used for autosave).
    static func saveAsync(_ g: Game, serverID: String) {
        guard g.player.alive else { return }
        let snap = makeSnapshot(g, serverID: serverID, copy: true)
        let meta = SaveMeta(serverID: serverID, day: snap.day, hour: snap.hour, location: snap.location, survived: snap.timeAlive, savedAt: snap.savedAt)
        saveQueue.async {
            let enc = JSONEncoder()
            if let data = try? enc.encode(snap) {
                try? data.write(to: saveURL(serverID), options: .atomic)
                try? enc.encode(meta).write(to: metaURL(serverID), options: .atomic)
            }
        }
    }

    /// Waits for pending background saves (before reading files).
    static func flush() {
        saveQueue.sync {}
    }

    static func load(serverID: String) -> SaveData? {
        flush()
        guard let data = try? Data(contentsOf: saveURL(serverID)) else { return nil }
        do {
            return try JSONDecoder().decode(SaveData.self, from: data)
        } catch {
            print("Load failed: \(error)")
            return nil
        }
    }

    static func summary(serverID: String) -> SaveSummary? {
        flush()
        guard let data = try? Data(contentsOf: metaURL(serverID)),
              let m = try? JSONDecoder().decode(SaveMeta.self, from: data) else { return nil }
        return SaveSummary(serverID: m.serverID, day: m.day, hour: m.hour, location: m.location, survivedSeconds: m.survived, savedAt: m.savedAt)
    }

    /// Called when the survivor dies: there is no character to continue.
    static func deleteCharacter(_ g: Game, serverID: String) {
        flush()
        try? FileManager.default.removeItem(at: metaURL(serverID))
        try? FileManager.default.removeItem(at: saveURL(serverID))
    }
}

extension Game {
    /// Restores a saved session.
    func restore(from s: SaveData) {
        items.removeAll()
        ai.reset()
        corpses.removeAll()
        var maxUID = 0
        for wi in s.items {
            items.add(wi.item, at: wi.position, yaw: wi.yaw)
            maxUID = max(maxUID, wi.item.maxUID())
        }
        items.spawnedSpots = Set(s.spawnedSpots)
        let open = Set(s.openDoors)
        for i in 0..<world.doors.count { world.setDoor(i, open: open.contains(i), immediate: true) }
        env.hour = s.hour
        env.day = s.day
        env.forceWeather(WeatherKind(rawValue: s.weather) ?? .clear)
        env.cloud = s.cloud
        env.rain = s.rain
        env.fog = s.fog
        env.wetness = s.wetness

        player = Player(position: s.position, yaw: s.yaw)
        player.appearance.skin = s.skin
        player.appearance.hair = s.hair
        player.appearance.longHair = s.longHair
        player.timeAlive = s.timeAlive
        if s.crouched {
            player.body.stance = .crouched
            input.crouchToggled = true
        }
        camYaw = s.camYaw
        camPitch = s.camPitch
        camSmoothY = s.position.y
        firstPerson = server.firstPersonOnly || s.firstPerson
        stats = s.stats
        equipment = s.equipment
        record = s.record
        flashlightOn = s.flashlightOn
        deathCause = ""
        action = nil
        weapon = WeaponRuntime()
        maxUID = max(maxUID, equipment.maxUID())
        ItemInstance.reserveUIDs(above: maxUID)
        for c in s.corpses {
            var a = Appearance()
            a.skin = c.skin
            a.hair = c.hair
            a.top = Garment(color: Vec3(0.7, 0.7, 0.68), layer: .fabric, bulky: false, longSleeves: false, dirt: 0.4)
            a.pants = Garment(color: Vec3(0.25, 0.25, 0.27), layer: .fabric, dirt: 0.4)
            var pose = CharacterPose()
            pose.position = c.position
            pose.death = 1
            corpses.append(PlayerCorpse(joints: CharacterAnimator.compute(pose), appearance: a, position: c.position, age: 0))
        }
        refreshAppearance()
        hud.messages.removeAll()
        message("Welcome back. Day \(env.day).")
    }
}
