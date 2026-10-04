//
//  ServerProfile.swift
//  Ashvale
//
//  World "servers": locally hosted single-player sessions with their own
//  rule sets and save slots. Shown in the SERVERS browser.
//

import Foundation

struct ServerProfile {
    let id: String
    let name: String
    let mode: String
    let summary: String
    let lootMultiplier: Float
    let infectedMultiplier: Float
    let infectedAggression: Float
    let survivalDrain: Float
    let crosshairAllowed: Bool
    let firstPersonOnly: Bool
    let startHour: Float

    static let all: [ServerProfile] = [
        ServerProfile(id: "regular", name: "ASHVALE  |  REGULAR", mode: "Third & first person",
                      summary: "Balanced loot and infected. Recommended for a first life in Ashvale.",
                      lootMultiplier: 1.0, infectedMultiplier: 1.0, infectedAggression: 1.0, survivalDrain: 1.0,
                      crosshairAllowed: true, firstPersonOnly: false, startHour: 7.5),
        ServerProfile(id: "hardcore", name: "ASHVALE  |  HARDCORE", mode: "First person only · No crosshair",
                      summary: "Scarce loot, more infected, faster hunger and thirst. Night falls early.",
                      lootMultiplier: 0.6, infectedMultiplier: 1.5, infectedAggression: 1.3, survivalDrain: 1.35,
                      crosshairAllowed: false, firstPersonOnly: true, startHour: 16.5),
        ServerProfile(id: "relaxed", name: "ASHVALE  |  SURVIVOR+", mode: "Third & first person",
                      summary: "More loot, fewer infected and slower needs. Good for exploring the map.",
                      lootMultiplier: 1.5, infectedMultiplier: 0.6, infectedAggression: 0.8, survivalDrain: 0.7,
                      crosshairAllowed: true, firstPersonOnly: false, startHour: 9.0),
    ]

    static func byID(_ id: String) -> ServerProfile {
        all.first { $0.id == id } ?? all[0]
    }

    static var selectedID: String {
        get { UserDefaults.standard.string(forKey: "selectedServer") ?? "regular" }
        set { UserDefaults.standard.set(newValue, forKey: "selectedServer") }
    }
}

/// Summary of a save shown in menus.
struct SaveSummary {
    var serverID: String
    var day: Int
    var hour: Float
    var location: String
    var survivedSeconds: Float
    var savedAt: Date

    var survivedText: String {
        let m = Int(survivedSeconds / 60)
        return m >= 60 ? "\(m / 60)h \(m % 60)m survived" : "\(m)m survived"
    }

    var timeText: String {
        let h = Int(hour), mm = Int((hour - Float(h)) * 60)
        return String(format: "%02d:%02d", h, mm)
    }
}
