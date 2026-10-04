// Renders actual gameplay frames (Game.buildScene output: world, characters,
// items and the first-person view model) with the software rasterizer.
import Foundation

func renderGameFrame(_ g: Game, scene: RenderScene, path: String, w: Int = 960, h: Int = 444) {
    let r = Raster(w, h)
    r.camPos = scene.cameraPos
    r.clear(Vec3(0.62, 0.7, 0.8))
    let aspect = Float(w) / Float(h)
    let proj = Mat4.perspectiveReverseZ(fovY: scene.fovY, aspect: aspect, near: scene.near)
    let vp = proj * scene.view
    if scene.drawWorld {
        drawWorldGeometry(r, world: g.world, reg: g.registry, eye: scene.cameraPos, vp: vp, lodRadius: 150)
    }
    for item in scene.dynamic {
        drawEntry(r, g.registry, item.mesh, item.instance.model, vp, tint: Vec3(item.instance.tint.x, item.instance.tint.y, item.instance.tint.z))
    }
    if !scene.viewModel.isEmpty {
        // Same as the GPU path: the view model is drawn in front of everything with its own projection.
        r.clearDepth()
        let vmvp = Mat4.perspectiveReverseZ(fovY: scene.viewModelFovY, aspect: aspect, near: 0.01) * scene.view
        for item in scene.viewModel {
            drawEntry(r, g.registry, item.mesh, item.instance.model, vmvp, tint: Vec3(item.instance.tint.x, item.instance.tint.y, item.instance.tint.z))
        }
    }
    r.savePPM(path)
    print("wrote \(path)")
}

func renderGameFrames(world: World, registry: MeshRegistry, outDir: String) {
    print("== Gameplay frames")
    ItemVisuals.registerAll(registry: registry)
    let cm = CharacterMeshes.build(registry: registry)
    let g = Game(world: world, registry: registry, characterMeshes: cm, seed: 5)
    g.configure(server: ServerProfile.byID("regular"))
    g.startNewGame()
    g.ai.populationMultiplier = 0
    g.ai.reset()
    g.env.hour = 15
    let scene = RenderScene()
    func settle(_ seconds: Float) {
        var t: Float = 0
        while t < seconds {
            g.update(dt: 1.0 / 60.0)
            g.buildScene(scene, dt: 1.0 / 60.0)
            t += 1.0 / 60.0
        }
    }
    // Stand on a Halden street looking along it.
    let town = world.locations.first { $0.name == "Halden" } ?? world.locations[0]
    let p0 = Vec3(town.center.x, 0, town.center.y)
    var best = p0
    var roadDir = Vec2(1, 0)
    search: for r in stride(from: Float(0), to: 120, by: 2) {
        for k in 0..<16 {
            let a = Float(k) / 16 * kTwoPi
            let q = p0 + Vec3(cosf(a), 0, sinf(a)) * r
            if let n = world.roads.nearest(q.x, q.z), n.distance < 1.0 {
                best = q
                roadDir = n.direction
                break search
            }
        }
    }
    g.player.position = Vec3(best.x, world.groundHeight(at: Vec3(best.x, 300, best.z)).height, best.z)
    g.camYaw = yawFromDirection(roadDir.x, roadDir.y)
    g.player.yaw = g.camYaw
    g.player.body.velocity = Vec3(0, 0, 0)
    // Rifle with red dot and a loaded magazine.
    let rifle = ItemInstance(defID: "kestrel")
    rifle.magazine = ItemInstance(defID: "mag_kestrel", quantity: 30)
    rifle.chambered = true
    rifle.attachments[AttachSlot.optic.rawValue] = ItemInstance(defID: "reddot")
    g.equipment.hands = rifle
    g.refreshAppearance()
    // A couple of infected down the street for scale.
    let fwd = flatForward(yaw: g.camYaw)
    for k in 0..<2 {
        let sp = g.player.position + fwd * Float(9 + k * 5) + flatRight(yaw: g.camYaw) * Float(k == 0 ? 1.5 : -2)
        let a = g.ai.spawn(k == 0 ? .civilian : .worker, at: Vec3(sp.x, world.groundHeight(at: sp + Vec3(0, 3, 0)).height, sp.z), location: 0)
        a.state = .idle
    }
    g.firstPerson = true
    g.camPitch = -0.05
    settle(0.6)
    renderGameFrame(g, scene: scene, path: "\(outDir)/game_fp_rifle.ppm")
    g.input.aimToggled = true
    settle(0.6)
    renderGameFrame(g, scene: scene, path: "\(outDir)/game_fp_rifle_aim.ppm")
    g.input.aimToggled = false
    g.firstPerson = false
    settle(0.6)
    renderGameFrame(g, scene: scene, path: "\(outDir)/game_tp_rifle.ppm")
    // Pistol, first person.
    let pistol = ItemInstance(defID: "warden")
    pistol.magazine = ItemInstance(defID: "mag_warden", quantity: 12)
    pistol.chambered = true
    g.equipment.hands = pistol
    g.firstPerson = true
    settle(0.6)
    renderGameFrame(g, scene: scene, path: "\(outDir)/game_fp_pistol.ppm")
    // Unarmed punch, first person.
    g.equipment.hands = nil
    settle(0.3)
    g.input.firePressed = true
    g.input.fireHeld = true
    g.update(dt: 1.0 / 60.0)
    g.input.firePressed = false
    g.input.fireHeld = false
    var t: Float = 0
    while t < 0.12 { g.update(dt: 1.0 / 60.0); t += 1.0 / 60.0 }
    g.buildScene(scene, dt: 1.0 / 60.0)
    renderGameFrame(g, scene: scene, path: "\(outDir)/game_fp_punch.ppm")
    // Inside a house, third person, unarmed.
    if let bi = world.buildings.firstIndex(where: { $0.type == .houseTwoStory && $0.area == .town }) {
        let b = world.buildings[bi]
        let inside = b.transform.transformPoint(Vec3(-1.5, 0, -1.0))
        g.player.position = Vec3(inside.x, b.position.y + 0.05, inside.z)
        g.equipment.hands = nil
        g.firstPerson = false
        let toDoor = vnormalize(b.transform.transformDirection(Vec3(0.4, 0, 1)))
        g.camYaw = yawFromDirection(toDoor.x, toDoor.z)
        settle(0.6)
        renderGameFrame(g, scene: scene, path: "\(outDir)/game_tp_interior.ppm")
    }
}
