//
//  Environment.swift
//  Ashvale
//
//  Day/night cycle (sunrise, day, sunset, night with moon and stars) and a
//  weather simulation (clear, cloudy, overcast, rain, storm, fog) that drives
//  lighting, fog, wetness, wind and air temperature.
//

import Foundation

enum WeatherKind: Int, Codable, CaseIterable {
    case clear, cloudy, overcast, rain, storm, fog

    var name: String {
        switch self {
        case .clear: return "Clear"
        case .cloudy: return "Cloudy"
        case .overcast: return "Overcast"
        case .rain: return "Rain"
        case .storm: return "Storm"
        case .fog: return "Fog"
        }
    }

    var targets: (cloud: Float, rain: Float, fog: Float, wind: Float) {
        switch self {
        case .clear: return (0.15, 0, 0.0, 0.2)
        case .cloudy: return (0.5, 0, 0.1, 0.35)
        case .overcast: return (0.85, 0, 0.2, 0.45)
        case .rain: return (0.95, 0.65, 0.35, 0.6)
        case .storm: return (1.0, 1.0, 0.45, 1.0)
        case .fog: return (0.6, 0, 1.0, 0.1)
        }
    }
}

final class Environment {
    /// Hour of day, 0...24.
    var hour: Float = 7.5
    var day: Int = 1
    var dayLengthMinutes: Float = 60

    var weather: WeatherKind = .clear
    var cloud: Float = 0.2
    var rain: Float = 0
    var fog: Float = 0.05
    var windStrength: Float = 0.25
    var windAngle: Float = 0.7
    var wetness: Float = 0
    var weatherTimer: Float = 300
    var lightning: Float = 0
    private var rng: RNG

    init(seed: UInt64) {
        rng = RNG(seed: seed &+ 4242)
    }

    var isNight: Bool { hour < 5.6 || hour > 20.2 }

    /// 0 = full night, 1 = full day.
    var daylight: Float {
        let s = sunDirection.y
        return smoothstepf(-0.12, 0.25, s)
    }

    var sunDirection: Vec3 {
        let theta = (hour - 6) / 12 * kPi
        return vnormalize(Vec3(-cosf(theta), sinf(theta) * 0.92, 0.38))
    }

    var moonDirection: Vec3 {
        let theta = (hour - 18) / 12 * kPi
        return vnormalize(Vec3(-cosf(theta), sinf(theta) * 0.85 + 0.1, -0.3))
    }

    /// Light level used by AI vision and stealth (0 dark .. 1 bright).
    var lightLevel: Float {
        let d = daylight * (1 - cloud * 0.35) * (1 - fog * 0.3)
        return max(d, 0.12)
    }

    /// Visibility distance factor for AI (fog/rain reduce sight).
    var visibilityFactor: Float {
        return (1 - fog * 0.6) * (1 - rain * 0.3)
    }

    /// Outdoor air temperature in Celsius at a given altitude.
    func airTemperature(altitude: Float) -> Float {
        let dayCurve = sinf((hour - 9) / 24 * kTwoPi) * 0.5 + 0.5   // peaks mid afternoon
        var t = mixf(3.5, 15.5, dayCurve)
        t -= cloud * 2.0 * daylight
        t -= rain * 3.5
        t -= fog * 1.0
        t -= windStrength * 2.0
        t -= max(0, altitude - 40) * 0.0065
        return t
    }

    func update(dt: Float) {
        // Time: a full day takes dayLengthMinutes real minutes.
        let hoursPerSecond = 24 / max(dayLengthMinutes * 60, 1)
        hour += dt * hoursPerSecond
        if hour >= 24 {
            hour -= 24
            day += 1
        }
        // Weather state machine.
        weatherTimer -= dt
        if weatherTimer <= 0 {
            weather = nextWeather()
            weatherTimer = rng.range(240, 600)
        }
        let t = weather.targets
        let rate: Float = 0.025
        cloud = damp(cloud, t.cloud, rate, dt)
        rain = damp(rain, cloud > 0.7 ? t.rain : 0, rate * 1.5, dt)
        let nightMist: Float = (hour > 4.5 && hour < 8) ? 0.25 : 0
        fog = damp(fog, max(t.fog, nightMist), rate, dt)
        windStrength = damp(windStrength, t.wind, rate, dt)
        windAngle += sinf(hour * 0.7) * dt * 0.01
        // Surfaces get wet in rain and dry slowly.
        if rain > 0.05 {
            wetness = min(1, wetness + rain * dt * 0.02)
        } else {
            wetness = max(0, wetness - dt * 0.004 * (0.3 + daylight))
        }
        // Lightning flashes in storms.
        if weather == .storm && rain > 0.6 && rng.chance(dt * 0.04) {
            lightning = 1
        }
        lightning = max(0, lightning - dt * 3)
    }

    private func nextWeather() -> WeatherKind {
        // Weighted transitions favour gradual changes.
        let weights: [Float]
        switch weather {
        case .clear: weights = [3, 4, 1, 0.3, 0, 0.6]
        case .cloudy: weights = [3, 2, 3, 1.5, 0.2, 0.8]
        case .overcast: weights = [1, 3, 2, 3, 0.8, 1]
        case .rain: weights = [0.5, 2, 3, 2, 1, 0.5]
        case .storm: weights = [0, 1, 2, 3, 0.5, 0]
        case .fog: weights = [2, 3, 1, 0.5, 0, 1.5]
        }
        return WeatherKind(rawValue: rng.weightedIndex(weights)) ?? .clear
    }

    func forceWeather(_ w: WeatherKind) {
        weather = w
        weatherTimer = rng.range(300, 600)
    }

    /// Fills lighting/fog/sky fields of the frame uniforms.
    func fill(_ u: inout FrameUniforms, indoors: Bool) {
        let sun = sunDirection
        let moon = moonDirection
        let dl = daylight
        let sunLow = 1 - smoothstepf(0.05, 0.45, sun.y)
        let overcast = smoothstepf(0.45, 1.0, cloud)

        // Direct light: sun by day, moon by night.
        var sunCol = vlerp(Vec3(1.0, 0.93, 0.82), Vec3(1.0, 0.55, 0.3), sunLow)
        var sunI = 3.0 * smoothstepf(-0.02, 0.12, sun.y) * (1 - overcast * 0.8) * (1 - fog * 0.4)
        var lightDir = sun
        if dl < 0.3 {
            let moonI = 0.32 * smoothstepf(0.0, 0.3, moon.y) * (1 - overcast * 0.85)
            let mix = 1 - smoothstepf(0.0, 0.3, dl)
            if mix > 0.5 {
                lightDir = moon
                sunCol = Vec3(0.55, 0.65, 0.95)
                sunI = moonI
            }
        }
        u.sunDir = Vec4(lightDir.x, lightDir.y, lightDir.z, sunI)
        u.sunColor = Vec4(sunCol.x, sunCol.y, sunCol.z, 1)
        u.moonDir = Vec4(moon.x, moon.y, moon.z, 1 - smoothstepf(0.0, 0.25, dl))

        // Sky gradient.
        let dayZ = Vec3(0.17, 0.36, 0.72), dayH = Vec3(0.6, 0.72, 0.86)
        let setZ = Vec3(0.18, 0.22, 0.42), setH = Vec3(0.98, 0.56, 0.32)
        let nightZ = Vec3(0.006, 0.01, 0.025), nightH = Vec3(0.025, 0.035, 0.06)
        var zen = vlerp(dayZ, setZ, sunLow * dl)
        var hor = vlerp(dayH, setH, sunLow * smoothstepf(-0.1, 0.1, sun.y))
        zen = vlerp(nightZ, zen, dl)
        hor = vlerp(nightH, hor, smoothstepf(-0.15, 0.05, sun.y))
        let grey = Vec3(0.5, 0.52, 0.55) * (0.15 + 0.85 * dl)
        zen = vlerp(zen, grey * 0.9, overcast * 0.85)
        hor = vlerp(hor, grey * 1.05, overcast * 0.8)
        let fogGrey = Vec3(0.62, 0.64, 0.66) * (0.08 + 0.92 * dl)
        hor = vlerp(hor, fogGrey, fog * 0.7)
        if lightning > 0 {
            zen += Vec3(0.6, 0.65, 0.8) * lightning
            hor += Vec3(0.6, 0.65, 0.8) * lightning
        }
        u.skyZenith = Vec4(zen.x, zen.y, zen.z, 1)
        u.skyHorizon = Vec4(hor.x, hor.y, hor.z, 1)

        // Ambient.
        var skyAmb = vlerp(Vec3(0.03, 0.04, 0.07), Vec3(0.42, 0.48, 0.58), dl)
        skyAmb = vlerp(skyAmb, Vec3(0.5, 0.52, 0.55) * (0.1 + 0.9 * dl), overcast * 0.6)
        skyAmb += Vec3(0.25, 0.12, 0.05) * sunLow * dl * 0.5
        let groundAmb = skyAmb * Vec3(0.55, 0.5, 0.42)
        if lightning > 0 { skyAmb += Vec3(0.8, 0.85, 1.0) * lightning * 1.5 }
        u.skyAmbient = Vec4(skyAmb.x, skyAmb.y, skyAmb.z, 1)
        u.groundAmbient = Vec4(groundAmb.x, groundAmb.y, groundAmb.z, 1)

        // Fog.
        let density = 0.0011 + cloud * 0.0004 + rain * 0.0035 + fog * 0.017
        u.fogColor = Vec4(1, 1, 1, density)
        u.fogParams = Vec4(0.018, indoors ? 0 : wetness, 1 - dl, cloud)
        let wd = Vec2(cosf(windAngle), sinf(windAngle))
        u.wind = Vec4(wd.x, wd.y, 0.2 + windStrength, rain)
        // Exposure brightens nights a little so the game stays readable.
        u.grade.w = mixf(2.4, 1.0, smoothstepf(0.0, 0.6, dl))
    }
}
