// CPU frame-cost benchmark: simulation + scene building + a CPU replica of the
// renderer's culling/grouping work, with the player walking through a town.
import Foundation

private func ms(_ s: Double) -> String { String(format: "%.2f ms", s * 1000) }

/// Mirrors Renderer.draw's per-chunk culling and instance grouping (without Metal).
private func cullCost(world: World, registry: MeshRegistry, scene: RenderScene, settings: RenderSettings,
                      buildingBounds: [AABB], propBounds: [AABB]) -> (main: Int, shadow: Int, groups: Int) {
    let aspect: Float = 19.5 / 9
    let proj = Mat4.perspectiveReverseZ(fovY: scene.fovY, aspect: aspect, near: scene.near)
    let frustum = Frustum(viewProjection: proj * scene.view)
    let cam = scene.cameraPos
    let shadowR = settings.shadowRange * 1.6
    var groups: [Int32: Int] = [:]
    var main = 0, shadow = 0
    func add(_ m: MeshID, _ n: inout Int) { groups[m.raw, default: 0] += 1; n += 1 }
    let r = Int(ceilf(settings.viewDistance / World.chunkSize))
    let ccx = Int(cam.x / World.chunkSize), ccz = Int(cam.z / World.chunkSize)
    for dz in -r...r {
        for dx in -r...r {
            let cx = ccx + dx, cz = ccz + dz
            if cx < 0 || cz < 0 || cx >= World.chunksPerSide || cz >= World.chunksPerSide { continue }
            let minB = Vec3(Float(cx) * World.chunkSize, -50, Float(cz) * World.chunkSize)
            let maxB = Vec3(Float(cx + 1) * World.chunkSize, 400, Float(cz + 1) * World.chunkSize)
            let d = max(0, vdistanceXZ((minB + maxB) * 0.5, cam) - World.chunkSize * 0.7)
            if d > settings.viewDistance { continue }
            let inView = frustum.intersectsBox(min: minB, max: maxB)
            let inShadow = d < shadowR
            if !inView && !inShadow { continue }
            let ci = cz * World.chunksPerSide + cx
            for bi in world.buildingsByChunk[ci] {
                let bb = buildingBounds[bi]
                let bd = max(0, vdistance(bb.center, cam) - bb.radius)
                if bd > settings.viewDistance { continue }
                let b = world.buildings[bi]
                guard let ids = world.buildingMeshIDs[World.modelKey(b.type, b.variant)] else { continue }
                if frustum.intersectsBox(min: bb.min, max: bb.max) {
                    add(ids.shell, &main)
                    add(bd < settings.interiorDistance ? ids.interior : ids.plugs, &main)
                }
                if bd < shadowR { add(ids.shell, &shadow) }
            }
            for pi in world.propsByChunk[ci] {
                let p = world.props[pi]
                let pb = propBounds[pi]
                let pd = vdistance(pb.center, cam)
                if pd > p.type.drawDistance * settings.propDistanceScale { continue }
                guard let id = world.propMeshIDs[p.type.rawValue] else { continue }
                if frustum.intersectsBox(min: pb.min, max: pb.max) { add(id, &main) }
                if pd < shadowR { add(id, &shadow) }
            }
            if d < settings.treeDistance {
                for ti in world.treesByChunk[ci] {
                    let t = world.trees[ti]
                    let td = vdistance(t.position, cam)
                    if td > settings.treeDistance { continue }
                    guard let ids = world.treeMeshIDs[t.kind.rawValue] else { continue }
                    let rad: Float = (t.kind == .bush ? 2 : 6) * t.scale
                    let hi = td < settings.treeHiDistance
                    _ = Mat4.translation(t.position) * Mat4.rotationY(t.yaw) * Mat4.scale(Vec3(repeating: t.scale))
                    if frustum.containsSphere(t.position + Vec3(0, rad, 0), rad * 1.3) { add(hi ? ids.hi : ids.lo, &main) }
                    if td < shadowR { add(hi ? ids.hi : ids.lo, &shadow) }
                }
            }
        }
    }
    return (main + scene.dynamic.count, shadow + scene.shadowCasters.count, groups.count)
}

func runBench(world: World, registry: MeshRegistry) {
    print("== Frame cost benchmark")
    ItemVisuals.registerAll(registry: registry)
    let cm = CharacterMeshes.build(registry: registry)
    let g = Game(world: world, registry: registry, characterMeshes: cm, seed: 11)
    g.configure(server: ServerProfile.byID("regular"))
    g.startNewGame()
    let buildingBounds = world.buildings.map { b -> AABB in
        if let ids = world.buildingMeshIDs[World.modelKey(b.type, b.variant)] {
            var bb = registry.bounds(ids.shell).transformed(b.transform)
            bb.expand(registry.bounds(ids.interior).transformed(b.transform))
            return bb
        }
        return AABB(center: b.position, halfExtents: Vec3(10, 10, 10))
    }
    let propBounds = world.props.map { p -> AABB in
        if let id = world.propMeshIDs[p.type.rawValue] { return registry.bounds(id).transformed(p.transform) }
        return AABB(center: p.position, halfExtents: Vec3(2, 2, 2))
    }
    let scene = RenderScene()
    for place in ["Halden", "Greywood"] {
    let loc = world.locations.first { $0.name == place } ?? world.locations[0]
    let start = Vec3(loc.center.x - 60, 0, loc.center.y)
    g.player.position = Vec3(start.x, world.groundHeight(at: Vec3(start.x, 200, start.z)).height, start.z)
    g.player.yaw = -kPi / 2
    g.camYaw = -kPi / 2
    let tp = Date()
    let before = g.ai.nav.builtChunks
    g.populateInfected()
    print("  -- \(place): populate + nav prepare \(ms(Date().timeIntervalSince(tp))) for \(g.ai.nav.builtChunks - before) chunks")
    for q in QualityLevel.allCases {
        var settings = RenderSettings()
        settings.quality = q
        var tUpdate = 0.0, tScene = 0.0, tCull = 0.0, worst = 0.0
        var mainSum = 0, shadowSum = 0, groupSum = 0
        var spikes: [(Int, Double, Double, Double)] = []
        let frames = 600
        for f in 0..<frames {
            var input = InputState()
            input.move = Vec2(0, 1)
            input.look = Vec2(sinf(Float(f) * 0.02) * 0.01, 0)
            input.sprintToggled = f % 400 < 200
            g.input = input
            let a = Date()
            g.update(dt: 1.0 / 60.0)
            let b = Date()
            g.buildScene(scene, dt: 1.0 / 60.0)
            let c = Date()
            let r = cullCost(world: world, registry: registry, scene: scene, settings: settings, buildingBounds: buildingBounds, propBounds: propBounds)
            let d = Date()
            tUpdate += b.timeIntervalSince(a)
            tScene += c.timeIntervalSince(b)
            tCull += d.timeIntervalSince(c)
            if f > 30 { worst = max(worst, d.timeIntervalSince(a)) }
            if d.timeIntervalSince(a) > 0.003 { spikes.append((f, b.timeIntervalSince(a), c.timeIntervalSince(b), d.timeIntervalSince(c))) }
            mainSum += r.main; shadowSum += r.shadow; groupSum += r.groups
            if !g.player.alive { g.respawn() }
        }
        let n = Double(frames)
        print("  \(q.name): update \(ms(tUpdate / n))  scene \(ms(tScene / n))  cull \(ms(tCull / n))  worst frame \(ms(worst))")
        print("        instances main \(mainSum / frames)  shadow \(shadowSum / frames)  mesh groups \(groupSum / frames)  agents \(g.ai.agents.count)  dynamic \(scene.dynamic.count)")
        if !spikes.isEmpty {
            print("        spikes >3ms: " + spikes.prefix(8).map { "f\($0.0) u\(ms($0.1)) s\(ms($0.2)) c\(ms($0.3))" }.joined(separator: ", "))
        }
    }
    }
}
