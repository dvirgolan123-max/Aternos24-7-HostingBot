//
//  Input.swift
//  Ashvale
//
//  Platform-independent input state written by the touch controls and read
//  by gameplay each frame.
//

import Foundation

struct InputState {
    /// Left stick: x = strafe right, y = forward. Magnitude 0...1.
    var move = Vec2(0, 0)
    /// Accumulated look delta in radians since the last frame (x = yaw right, y = pitch up).
    var look = Vec2(0, 0)

    // Held / toggled states.
    var fireHeld = false
    var aimToggled = false
    var sprintToggled = false
    var crouchToggled = false

    // Edge-triggered presses (cleared after each simulation step).
    var jumpPressed = false
    var reloadPressed = false
    var interactPressed = false
    var interactHeldTime: Float = 0
    var firePressed = false
    var fireModePressed = false
    var cameraTogglePressed = false
    var quickSlotPressed: Int? = nil
    var holsterPressed = false

    mutating func clearEdges() {
        look = Vec2(0, 0)
        jumpPressed = false
        reloadPressed = false
        interactPressed = false
        firePressed = false
        fireModePressed = false
        cameraTogglePressed = false
        quickSlotPressed = nil
        holsterPressed = false
    }
}

/// Persistent user settings.
final class GameSettings {
    static let shared = GameSettings()
    private let d = UserDefaults.standard

    /// First-launch graphics preset: older iPhones (3 GB of RAM or less) start on Low.
    static var defaultQuality: QualityLevel {
        ProcessInfo.processInfo.physicalMemory <= 3_300_000_000 ? .low : .medium
    }

    var quality: QualityLevel {
        get { QualityLevel(rawValue: d.object(forKey: "quality") as? Int ?? GameSettings.defaultQuality.rawValue) ?? .medium }
        set { d.set(newValue.rawValue, forKey: "quality") }
    }
    var showFPS: Bool {
        get { d.object(forKey: "showFPS") as? Bool ?? false }
        set { d.set(newValue, forKey: "showFPS") }
    }
    var lookSensitivity: Float {
        get { d.object(forKey: "lookSensitivity") as? Float ?? 1.0 }
        set { d.set(newValue, forKey: "lookSensitivity") }
    }
    var aimSensitivity: Float {
        get { d.object(forKey: "aimSensitivity") as? Float ?? 0.6 }
        set { d.set(newValue, forKey: "aimSensitivity") }
    }
    var invertY: Bool {
        get { d.object(forKey: "invertY") as? Bool ?? false }
        set { d.set(newValue, forKey: "invertY") }
    }
    var fieldOfView: Float {
        get { d.object(forKey: "fov") as? Float ?? 70 }
        set { d.set(newValue, forKey: "fov") }
    }
    var masterVolume: Float {
        get { d.object(forKey: "volume") as? Float ?? 0.9 }
        set { d.set(newValue, forKey: "volume") }
    }
    var showCrosshair: Bool {
        get { d.object(forKey: "crosshair") as? Bool ?? true }
        set { d.set(newValue, forKey: "crosshair") }
    }
    var firstPersonDefault: Bool {
        get { d.object(forKey: "firstPerson") as? Bool ?? false }
        set { d.set(newValue, forKey: "firstPerson") }
    }
    var joystickScale: Float {
        get { d.object(forKey: "joystickScale") as? Float ?? 1.0 }
        set { d.set(newValue, forKey: "joystickScale") }
    }
    var dayLengthMinutes: Float {
        get { d.object(forKey: "dayLength") as? Float ?? 60 }
        set { d.set(newValue, forKey: "dayLength") }
    }
    var autoRunSprint: Bool {
        get { d.object(forKey: "autoSprint") as? Bool ?? true }
        set { d.set(newValue, forKey: "autoSprint") }
    }
    var introSeen: Bool {
        get { d.object(forKey: "introSeen") as? Bool ?? false }
        set { d.set(newValue, forKey: "introSeen") }
    }

    var renderSettings: RenderSettings {
        var r = RenderSettings()
        r.quality = quality
        return r
    }
}
