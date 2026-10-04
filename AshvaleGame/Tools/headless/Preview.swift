// Software-rendered previews of the generated world (for verification only).
import Foundation

func drawEntry(_ r: Raster, _ reg: MeshRegistry, _ id: MeshID, _ model: Mat4, _ vp: Mat4, tint: Vec3 = Vec3(1, 1, 1)) {
    guard id.isValid else { return }
    let e = reg.entries[Int(id.raw)]
    r.drawMesh(vertices: e.vertices, indices: e.indices, model: model, viewProj: vp, tint: tint)
}

func renderScene(world: World, reg: MeshRegistry, eye: Vec3, target: Vec3, fov: Float, w: Int, h: Int, path: String,
                 lodRadius: Float = 200, interiors: Bool = true, cutaway: AABB? = nil) {
    let r = Raster(w, h)
    r.camPos = eye
    r.clear(Vec3(0.62, 0.7, 0.8))
    let view = Mat4.lookAt(eye: eye, target: target, up: Vec3(0, 1, 0))
    let proj = Mat4.perspectiveReverseZ(fovY: fov * kDegToRad, aspect: Float(w) / Float(h), near: 0.1)
    let vp = proj * view
    let frustum = Frustum(viewProjection: vp)
    for cz in 0..<World.chunksPerSide {
        for cx in 0..<World.chunksPerSide {
            let c = Vec3((Float(cx) + 0.5) * World.chunkSize, eye.y, (Float(cz) + 0.5) * World.chunkSize)
            let d = vdistanceXZ(c, eye)
            if d > 900 { continue }
            let minB = Vec3(Float(cx) * 64, -50, Float(cz) * 64), maxB = Vec3(Float(cx + 1) * 64, 300, Float(cz + 1) * 64)
            if !frustum.intersectsBox(min: minB, max: maxB) { continue }
            let mb = ChunkMesher.build(world: world, cx: cx, cz: cz, lod: d < lodRadius ? 0 : 1)
            r.drawMesh(vertices: mb.vertices, indices: mb.indices, model: .identity, viewProj: vp)
            let ci = cz * World.chunksPerSide + cx
            for bi in world.buildingsByChunk[ci] {
                let b = world.buildings[bi]
                if let cut = cutaway, cut.contains(b.position) { continue }
                guard let ids = world.buildingMeshIDs[World.modelKey(b.type, b.variant)] else { continue }
                let bd = vdistance(b.position, eye)
                drawEntry(r, reg, ids.shell, b.transform, vp, tint: b.tint)
                if interiors && bd < 120 { drawEntry(r, reg, ids.interior, b.transform, vp) } else { drawEntry(r, reg, ids.plugs, b.transform, vp) }
            }
            for pi in world.propsByChunk[ci] {
                let p = world.props[pi]
                if vdistance(p.position, eye) > p.type.drawDistance { continue }
                if let id = world.propMeshIDs[p.type.rawValue] { drawEntry(r, reg, id, p.transform, vp) }
            }
            for ti in world.treesByChunk[ci] {
                let t = world.trees[ti]
                let td = vdistance(t.position, eye)
                if td > 600 { continue }
                guard let ids = world.treeMeshIDs[t.kind.rawValue] else { continue }
                let m = Mat4.translation(t.position) * Mat4.rotationY(t.yaw) * Mat4.scale(Vec3(repeating: t.scale))
                drawEntry(r, reg, td < 120 ? ids.hi : ids.lo, m, vp, tint: t.tint)
            }
            for di in world.doorsByChunk[ci] where vdistance(world.doors[di].hinge, eye) < 100 {
                let d = world.doors[di]
                if let id = world.doorMeshIDs[Int(d.style.rawValue)] {
                    drawEntry(r, reg, id, d.transform * Mat4.scale(Vec3(d.width, d.height / 2.12, 1)), vp)
                }
            }
        }
    }
    for lake in world.water {
        let lm = ChunkMesher.lakeMesh(lake)
        r.drawMesh(vertices: lm.vertices, indices: lm.indices, model: .identity, viewProj: vp)
    }
    r.savePPM(path)
    print("wrote \(path)")
}

func renderMap(world: World, reg: MeshRegistry, path: String) {
    let size = 1024
    let r = Raster(size, size)
    r.clear(Vec3(0, 0, 0))
    r.fogDensity = 0
    let eye = Vec3(1024, 900, 1024)
    let view = Mat4.lookAt(eye: eye, target: Vec3(1024, 0, 1024), up: Vec3(0, 0, -1))
    let proj = Mat4.orthographic(left: -1024, right: 1024, bottom: -1024, top: 1024, near: 2000, far: 1)
    let vp = proj * view
    r.camPos = eye
    for cz in 0..<World.chunksPerSide {
        for cx in 0..<World.chunksPerSide {
            let mb = ChunkMesher.build(world: world, cx: cx, cz: cz, lod: 1)
            r.drawMesh(vertices: mb.vertices, indices: mb.indices, model: .identity, viewProj: vp)
        }
    }
    for b in world.buildings {
        if let ids = world.buildingMeshIDs[World.modelKey(b.type, b.variant)] { drawEntry(r, reg, ids.shell, b.transform, vp, tint: b.tint) }
    }
    for p in world.props { if let id = world.propMeshIDs[p.type.rawValue] { drawEntry(r, reg, id, p.transform, vp) } }
    for t in world.trees {
        if let ids = world.treeMeshIDs[t.kind.rawValue] {
            drawEntry(r, reg, ids.lo, Mat4.translation(t.position) * Mat4.rotationY(t.yaw) * Mat4.scale(Vec3(repeating: t.scale)), vp, tint: t.tint)
        }
    }
    for lake in world.water {
        let lm = ChunkMesher.lakeMesh(lake)
        r.drawMesh(vertices: lm.vertices, indices: lm.indices, model: .identity, viewProj: vp)
    }
    r.savePPM(path)
    print("wrote \(path)")
}

func renderPreviews(world: World, registry: MeshRegistry, outDir: String) {
    let which = ProcessInfo.processInfo.environment["PREVIEW"] ?? "all"
    let t = world.terrain
    func ground(_ x: Float, _ z: Float) -> Float { t.height(x, z) }
    if which == "all" || which.contains("map") {
        renderMap(world: world, reg: registry, path: "\(outDir)/map.ppm")
    }
    if which == "all" || which.contains("town") {
        let e = Vec3(990, ground(990, 1050) + 1.7, 1052)
        renderScene(world: world, reg: registry, eye: e, target: e + Vec3(40, -2, -3), fov: 60, w: 960, h: 540, path: "\(outDir)/town_street.ppm")
        let a = Vec3(1000, ground(1000, 1100) + 70, 1180)
        renderScene(world: world, reg: registry, eye: a, target: Vec3(1060, ground(1060, 1040), 1040), fov: 55, w: 960, h: 540, path: "\(outDir)/town_aerial.ppm")
    }
    if which == "all" || which.contains("military") {
        let a = Vec3(1520, ground(1520, 1440) + 40, 1430)
        renderScene(world: world, reg: registry, eye: a, target: Vec3(1570, ground(1570, 1560), 1560), fov: 55, w: 960, h: 540, path: "\(outDir)/military.ppm")
    }
    if which == "all" || which.contains("village") {
        let a = Vec3(520, ground(520, 800) + 30, 820)
        renderScene(world: world, reg: registry, eye: a, target: Vec3(520, ground(520, 722), 722), fov: 55, w: 960, h: 540, path: "\(outDir)/village.ppm")
    }
    if which == "all" || which.contains("interior") {
        // Inside the police station looking at the reception.
        if let b = world.buildings.first(where: { $0.type == .police }) {
            let m = b.transform
            let eye = m.transformPoint(Vec3(-3, 1.65, 5.5))
            let target = m.transformPoint(Vec3(3, 1.2, -4))
            renderScene(world: world, reg: registry, eye: eye, target: target, fov: 70, w: 960, h: 540, path: "\(outDir)/interior_police.ppm")
        }
        if let b = world.buildings.first(where: { $0.type == .houseTwoStory }) {
            let m = b.transform
            let eye = m.transformPoint(Vec3(-3.5, 1.6, 4.0))
            let target = m.transformPoint(Vec3(2.0, 1.0, -3.0))
            renderScene(world: world, reg: registry, eye: eye, target: target, fov: 75, w: 960, h: 540, path: "\(outDir)/interior_house.ppm")
        }
        if let b = world.buildings.first(where: { $0.type == .apartment }) {
            let m = b.transform
            let eye = m.transformPoint(Vec3(0.6, 1.6, 4.5))
            let target = m.transformPoint(Vec3(-0.4, 1.4, -3.0))
            renderScene(world: world, reg: registry, eye: eye, target: target, fov: 75, w: 960, h: 540, path: "\(outDir)/interior_stairs.ppm")
        }
    }
}

func renderCharacters(outDir: String) {
    let reg = MeshRegistry()
    let cm = CharacterMeshes.build(registry: reg)
    let scene = RenderScene()
    var poses: [(CharacterPose, Appearance)] = []
    var a = Appearance()
    var p = CharacterPose()
    p.position = Vec3(-3, 0, 0); poses.append((p, a))                       // idle T-shirt + jeans
    p = CharacterPose(); p.position = Vec3(-1.8, 0, 0); p.speed = 3.5; p.phase = 0.8
    a.top = Garment(color: Vec3(0.3, 0.35, 0.28), layer: .camo, bulky: true, longSleeves: true)
    a.pants = Garment(color: Vec3(0.35, 0.38, 0.3), layer: .camo); a.bootsStyle = true; a.shoes = Garment(color: Vec3(0.25, 0.2, 0.15), layer: .leather)
    a.head = .helmet; a.vest = .plateCarrier; a.backpack = .backpackMilitary
    poses.append((p, a))
    p = CharacterPose(); p.position = Vec3(-0.6, 0, 0); p.crouch = 1; p.hold = .rifle; p.aim = 1; p.aimPitch = 0.1
    a = Appearance(); a.top = Garment(color: Vec3(0.2, 0.25, 0.4), layer: .fabric, bulky: true, longSleeves: true); a.head = .beanie; a.backpack = .backpackHiking
    poses.append((p, a))
    p = CharacterPose(); p.position = Vec3(0.6, 0, 0); p.hold = .pistol; p.aim = 1
    a = Appearance(); a.top = Garment(color: Vec3(0.15, 0.18, 0.3), layer: .fabric, bulky: true, longSleeves: true); a.head = .policeCap; a.vest = .vestPolice; a.vestTint = Vec3(0.2, 0.22, 0.3)
    poses.append((p, a))
    p = CharacterPose(); p.position = Vec3(1.8, 0, 0); p.infected = true; p.speed = 2.0; p.phase = 2.0
    a = Appearance(); a.infected = true; a.skin = Vec3(0.62, 0.66, 0.58); a.top = Garment(color: Vec3(0.5, 0.45, 0.4), layer: .fabric, bulky: false, longSleeves: true, dirt: 0.5); a.pants.dirt = 0.4
    poses.append((p, a))
    p = CharacterPose(); p.position = Vec3(3.2, 0, 0); p.death = 1; p.deathForward = false
    poses.append((p, Appearance()))
    for (pp, aa) in poses {
        var q = pp
        q.yaw = 0.5
        let j = CharacterAnimator.compute(q)
        CharacterAnimator.emit(j, aa, meshes: cm, scene: scene)
    }
    let r = Raster(960, 420)
    r.clear(Vec3(0.55, 0.6, 0.66))
    r.fogDensity = 0
    let eye = Vec3(0, 1.4, -5.2)
    r.camPos = eye
    let view = Mat4.lookAt(eye: eye, target: Vec3(0, 0.9, 0), up: Vec3(0, 1, 0))
    let proj = Mat4.perspectiveReverseZ(fovY: 45 * kDegToRad, aspect: 960 / 420, near: 0.1)
    // Ground plane.
    let g = MeshBuilder(); g.material = .concrete; g.addBox(min: Vec3(-6, -0.1, -3), max: Vec3(6, 0, 3))
    r.drawMesh(vertices: g.vertices, indices: g.indices, model: .identity, viewProj: proj * view)
    for item in scene.dynamic {
        let e = reg.entries[Int(item.mesh.raw)]
        var tint = Vec3(item.instance.tint.x, item.instance.tint.y, item.instance.tint.z)
        let layer = item.instance.tint.w
        if layer >= 0 { tint *= Raster.matColor(UInt8(layer)) * 1.6 }
        r.drawMesh(vertices: e.vertices, indices: e.indices, model: item.instance.model, viewProj: proj * view, tint: tint)
    }
    r.savePPM("\(outDir)/characters.ppm")
    print("wrote characters")
}
