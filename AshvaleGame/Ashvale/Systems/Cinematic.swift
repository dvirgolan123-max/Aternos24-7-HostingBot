//
//  Cinematic.swift
//  Ashvale
//
//  Camera shots rendered with the game engine for the cinematic main menu
//  background and the story intro.
//

import Foundation

struct CinematicShot {
    var eyeFrom: Vec3
    var eyeTo: Vec3
    var lookFrom: Vec3
    var lookTo: Vec3
    var duration: Float
    var hour: Float
    var weather: WeatherKind
    var caption: String?
}

final class CinematicDirector {
    let world: World
    let env: Environment
    private(set) var shots: [CinematicShot] = []
    private(set) var index = 0
    private(set) var t: Float = 0
    var loop = true
    private(set) var finished = false
    var time: Float = 0
    /// Infected extras shown in shots (positions + yaw + phase).
    var extras: [(pos: Vec3, yaw: Float, phase: Float, speed: Float)] = []

    init(world: World, seed: UInt64) {
        self.world = world
        env = Environment(seed: seed)
        env.dayLengthMinutes = 1e6
    }

    private func g(_ x: Float, _ z: Float, _ h: Float) -> Vec3 {
        Vec3(x, world.terrain.height(x, z) + h, z)
    }

    func setupMenu() {
        loop = true
        finished = false
        shots = [
            CinematicShot(eyeFrom: g(870, 1210, 55), eyeTo: g(990, 1215, 48), lookFrom: g(1050, 1040, 0), lookTo: g(1110, 1030, 0),
                          duration: 26, hour: 18.4, weather: .cloudy, caption: nil),
            CinematicShot(eyeFrom: g(1270, 1052, 2.0), eyeTo: g(1170, 1050, 2.2), lookFrom: g(1000, 1048, 3), lookTo: g(930, 1050, 3),
                          duration: 22, hour: 19.1, weather: .fog, caption: nil),
            CinematicShot(eyeFrom: g(560, 1250, 30), eyeTo: g(640, 1280, 26), lookFrom: g(700, 1350, 2), lookTo: g(710, 1360, 2),
                          duration: 24, hour: 6.4, weather: .fog, caption: nil),
            CinematicShot(eyeFrom: g(1460, 1450, 35), eyeTo: g(1500, 1430, 30), lookFrom: g(1580, 1560, 2), lookTo: g(1560, 1550, 2),
                          duration: 22, hour: 17.5, weather: .overcast, caption: nil),
        ]
        index = 0
        t = 0
        applyShotEnvironment()
        spawnExtras()
    }

    func setupIntro() {
        loop = false
        finished = false
        shots = [
            CinematicShot(eyeFrom: g(1300, 1345, 6), eyeTo: g(1330, 1350, 5), lookFrom: g(1360, 1330, 1.5), lookTo: g(1370, 1330, 1.5), duration: 7.5, hour: 19.0, weather: .fog,
                          caption: "It began in the autumn. A sickness the doctors called the Grey Fever spread through the northern valleys."),
            CinematicShot(eyeFrom: g(1180, 1046, 1.8), eyeTo: g(1110, 1052, 1.8), lookFrom: g(990, 1050, 2.5), lookTo: g(960, 1050, 2.5), duration: 8, hour: 20.3, weather: .overcast,
                          caption: "Within weeks the sick stopped sleeping. Then they stopped knowing their own families."),
            CinematicShot(eyeFrom: g(1030, 1095, 3), eyeTo: g(1070, 1092, 3), lookFrom: g(1050, 1066, 4), lookTo: g(1052, 1066, 5), duration: 7.5, hour: 5.6, weather: .rain,
                          caption: "Halden Hospital took the first wave. Nobody who went in came back out."),
            CinematicShot(eyeFrom: g(1520, 1430, 9), eyeTo: g(1522, 1460, 7), lookFrom: g(1520, 1500, 2), lookTo: g(1525, 1540, 2), duration: 7.5, hour: 6.2, weather: .fog,
                          caption: "The army sealed off Ashvale. Checkpoints. Curfews. Promises of evacuation."),
            CinematicShot(eyeFrom: g(700, 1240, 25), eyeTo: g(740, 1280, 18), lookFrom: g(700, 1350, 0), lookTo: g(690, 1360, 0), duration: 7.5, hour: 6.8, weather: .cloudy,
                          caption: "The evacuation never came. On the ninth day, the radio went silent."),
            CinematicShot(eyeFrom: g(150, 790, 3), eyeTo: g(230, 765, 2.5), lookFrom: g(420, 725, 2), lookTo: g(520, 722, 3), duration: 8.5, hour: 7.4, weather: .clear,
                          caption: "You wake on the outskirts with nothing but the clothes on your back. Find water. Find food. Find a weapon. Survive."),
        ]
        index = 0
        t = 0
        applyShotEnvironment()
        spawnExtras()
    }

    private func applyShotEnvironment() {
        guard index < shots.count else { return }
        let s = shots[index]
        env.hour = s.hour
        env.weather = s.weather
        let tg = s.weather.targets
        env.cloud = tg.cloud
        env.rain = tg.rain
        env.fog = tg.fog
        env.windStrength = tg.wind
        env.wetness = tg.rain > 0 ? 0.8 : 0
        env.weatherTimer = 1e9
    }

    private func spawnExtras() {
        extras.removeAll()
        guard index < shots.count else { return }
        let s = shots[index]
        var r = RNG(seed: UInt64(index * 77 + 5))
        let n = r.int(2, 5)
        for _ in 0..<n {
            let c = vlerp(s.lookFrom, s.lookTo, r.float())
            let x = c.x + r.range(-14, 14), z = c.z + r.range(-14, 14)
            let p = Vec3(x, world.groundHeight(at: Vec3(x, world.terrain.height(x, z) + 1, z)).height, z)
            extras.append((p, r.range(0, kTwoPi), r.range(0, 6), r.range(0.0, 1.2)))
        }
    }

    var currentCaption: String? { index < shots.count ? shots[index].caption : nil }
    var shotProgress: Float { index < shots.count ? t / shots[index].duration : 1 }
    /// Black fade amount at cuts.
    var fade: Float {
        guard index < shots.count else { return 1 }
        let d = shots[index].duration
        return max(1 - smoothstepf(0, 1.2, t), smoothstepf(d - 1.2, d, t))
    }

    func skipShot() {
        t = shots.isEmpty ? 0 : shots[index].duration
    }

    func update(dt: Float) {
        guard !shots.isEmpty, !finished else { return }
        time += dt
        t += dt
        env.update(dt: dt)
        for i in 0..<extras.count {
            extras[i].phase += dt * (1 + extras[i].speed * 2)
            if extras[i].speed > 0.1 {
                let f = flatForward(yaw: extras[i].yaw)
                var p = extras[i].pos + f * (extras[i].speed * dt)
                p.y = world.terrain.height(p.x, p.z)
                extras[i].pos = p
            }
        }
        if t >= shots[index].duration {
            index += 1
            t = 0
            if index >= shots.count {
                if loop {
                    index = 0
                } else {
                    index = shots.count - 1
                    t = shots[index].duration
                    finished = true
                    return
                }
            }
            applyShotEnvironment()
            spawnExtras()
        }
    }

    func buildScene(_ scene: RenderScene, characters: CharacterMeshes?) {
        scene.beginFrame()
        guard index < shots.count else { return }
        let s = shots[index]
        let k = smoothstepf(0, 1, min(t / s.duration, 1))
        let eye = vlerp(s.eyeFrom, s.eyeTo, k)
        let look = vlerp(s.lookFrom, s.lookTo, k)
        scene.cameraPos = eye
        scene.view = Mat4.lookAt(eye: eye, target: look, up: Vec3(0, 1, 0))
        scene.fovY = 55 * kDegToRad
        scene.time = time
        env.fill(&scene.uniforms, indoors: false)
        scene.rainIntensity = env.rain
        scene.drawRain = true
        scene.uniforms.grade = Vec4(0.85, 0.75, 0, scene.uniforms.grade.w)
        if let cm = characters {
            for e in extras {
                var pose = CharacterPose()
                pose.position = e.pos
                pose.yaw = e.yaw
                pose.speed = e.speed
                pose.phase = e.phase
                pose.infected = true
                var a = Appearance()
                a.infected = true
                a.skin = Vec3(0.6, 0.64, 0.56)
                a.top = Garment(color: Vec3(0.45, 0.42, 0.38), layer: .fabric, bulky: false, longSleeves: true, dirt: 0.5)
                a.pants.dirt = 0.4
                let j = CharacterAnimator.compute(pose)
                CharacterAnimator.emit(j, a, meshes: cm, scene: scene)
            }
        }
    }
}
