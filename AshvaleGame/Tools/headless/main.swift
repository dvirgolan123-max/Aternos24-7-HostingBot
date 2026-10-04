// Headless test harness: runs the platform-independent game core on Linux/macOS.
// Usage: run.sh [preview] [test]
import Foundation

let args = CommandLine.arguments
let outDir = ProcessInfo.processInfo.environment["OUT_DIR"] ?? "/w/Tools/headless/out"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let t0 = Date()
let world = WorldGenerator.generate(seed: 1337) { p, msg in
    print(String(format: "[%3.0f%%] %@", p * 100, msg))
}
print("World generated in \(String(format: "%.2f", Date().timeIntervalSince(t0)))s")
print("Buildings: \(world.buildings.count)  props: \(world.props.count)  trees: \(world.trees.count)")
print("Colliders: \(world.collision.colliders.count)  doors: \(world.doors.count)  loot spots: \(world.lootSpots.count)")
var byType: [String: Int] = [:]
for b in world.buildings { byType[b.type.displayName, default: 0] += 1 }
print(byType.sorted { $0.key < $1.key })

let registry = MeshRegistry()
world.registerMeshes(registry)
print("Registered meshes: \(registry.count), triangles: \(registry.totalTriangles)")

if args.contains("chars") {
    renderCharacters(outDir: outDir)
}

if args.contains("tests") {
    runTests(world: world, registry: registry)
    runGameTests(world: world, registry: registry)
    runSystemTests(world: world, registry: registry)
}

if args.contains("preview") {
    renderPreviews(world: world, registry: registry, outDir: outDir)
}
