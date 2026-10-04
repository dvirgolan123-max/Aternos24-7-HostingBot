// UI layout preview: builds every screen with the real UIKit code (running on
// functional UIKit stand-ins), lays it out at several iPhone sizes and dumps the
// view tree as JSON for Tools/uipreview/render.py.
import Foundation
import UIKit

let outDir = ProcessInfo.processInfo.environment["OUT_DIR"] ?? "/w/Tools/uipreview/out"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func rgba(_ c: UIColor?) -> [Double]? { c.map { [Double($0.r), Double($0.g), Double($0.b), Double($0.a)] } }
func rgba(_ c: CGColor?) -> [Double]? { c.map { $0.components.map { Double($0) } } }

func textRuns(_ l: UILabel) -> [[String: Any]] {
    if let at = l.attributedText, at.length > 0 {
        var runs: [[String: Any]] = []
        at.enumerateAttributes(in: NSRange(location: 0, length: at.length), options: []) { attrs, range, _ in
            let s = (at.string as NSString).substring(with: range)
            let f = attrs[.font] as? UIFont ?? l.font
            let c = attrs[.foregroundColor] as? UIColor ?? l.textColor
            let k = attrs[.kern] as? CGFloat ?? 0
            runs.append(["text": s, "size": Double(f?.size ?? 17), "weight": Double(f?.weight.rawValue ?? 0),
                         "mono": f?.mono ?? false, "color": rgba(c) ?? [1, 1, 1, 1], "kern": Double(k)])
        }
        return runs
    }
    guard let t = l.text, !t.isEmpty else { return [] }
    return [["text": t, "size": Double(l.font?.size ?? 17), "weight": Double(l.font?.weight.rawValue ?? 0),
             "mono": l.font?.mono ?? false, "color": rgba(l.textColor) ?? [0, 0, 0, 1], "kern": 0.0]]
}

func dump(_ v: UIView, alpha: CGFloat, clip: CGRect, into nodes: inout [[String: Any]]) {
    if v.isHidden { return }
    let a = alpha * v.alpha
    if a < 0.01 { return }
    let f = v.absoluteFrame
    var n: [String: Any] = ["x": Double(f.minX), "y": Double(f.minY), "w": Double(f.width), "h": Double(f.height),
                            "alpha": Double(a), "clip": [Double(clip.minX), Double(clip.minY), Double(clip.width), Double(clip.height)],
                            "type": String(describing: type(of: v)), "radius": Double(v.layer.cornerRadius)]
    if let bg = rgba(v.backgroundColor) { n["bg"] = bg }
    if v.layer.borderWidth > 0, let bc = rgba(v.layer.borderColor) { n["border"] = [Double(v.layer.borderWidth)] + bc }
    if let g = v.layer as? CAGradientLayer, let cols = g.colors {
        n["gradient"] = ["colors": cols.compactMap { rgba($0 as? CGColor) }, "start": [Double(g.startPoint.x), Double(g.startPoint.y)],
                         "end": [Double(g.endPoint.x), Double(g.endPoint.y)]]
    }
    if let l = v as? UILabel {
        let runs = textRuns(l)
        if !runs.isEmpty {
            var align = l.textAlignment.rawValue
            if let at = l.attributedText, at.length > 0, let ps = at.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle {
                align = ps.alignment.rawValue
            }
            n["text"] = ["runs": runs, "align": align, "lines": l.numberOfLines, "shrink": l.adjustsFontSizeToFitWidth]
        }
    }
    if let s = v as? UISegmentedControl {
        n["segments"] = ["items": s.items, "selected": s.selectedSegmentIndex]
    }
    if let s = v as? UISwitch { n["switch"] = s.isOn }
    if let s = v as? UISlider { n["slider"] = Double((s.value - s.minimumValue) / max(0.0001, s.maximumValue - s.minimumValue)) }
    if let iv = v as? UIImageView, iv.image != nil { n["image"] = true }
    nodes.append(n)
    var childClip = clip
    if v.clipsToBounds || v is UIScrollView { childClip = clip.intersection(f) }
    for s in v.subviews { dump(s, alpha: a, clip: childClip, into: &nodes) }
}

func save(_ root: UIView, name: String, device: String, backdrop: String) {
    root.layoutIfNeeded()
    root.layoutIfNeeded()
    var nodes: [[String: Any]] = []
    dump(root, alpha: 1, clip: root.frame, into: &nodes)
    let doc: [String: Any] = ["width": Double(root.frame.width), "height": Double(root.frame.height), "backdrop": backdrop,
                              "safe": [Double(UIView.previewSafeArea.top), Double(UIView.previewSafeArea.left),
                                       Double(UIView.previewSafeArea.bottom), Double(UIView.previewSafeArea.right)], "nodes": nodes]
    let data = try! JSONSerialization.data(withJSONObject: doc, options: [])
    let path = "\(outDir)/ui_\(name)_\(device).json"
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) (\(nodes.count) views)")
}

// World + game state for the HUD and inventory.
let world = WorldGenerator.generate(seed: 1337) { _, _ in }
let registry = MeshRegistry()
world.registerMeshes(registry)
let cm = CharacterMeshes.build(registry: registry)
ItemVisuals.registerAll(registry: registry)
let game = Game(world: world, registry: registry, characterMeshes: cm, seed: 3)
game.configure(server: ServerProfile.byID("regular"))
game.startNewGame()
game.ai.populationMultiplier = 0
let town = world.locations.first { $0.name == "Halden" }!
game.player.position = Vec3(town.center.x, world.groundHeight(at: Vec3(town.center.x, 300, town.center.y)).height, town.center.y)
// A survivor a few hours in: gear, wounds and a loaded rifle.
let pack = ItemInstance(defID: "rucksack")
game.items.add(pack, at: game.player.position, yaw: 0)
_ = game.equip(uid: pack.uid, to: .backpack)
let vest = ItemInstance(defID: "policevest")
game.items.add(vest, at: game.player.position, yaw: 0)
_ = game.equip(uid: vest.uid, to: .vest)
let rifle = ItemInstance(defID: "kestrel")
rifle.magazine = ItemInstance(defID: "mag_kestrel", quantity: 23)
rifle.chambered = true
rifle.attachments[AttachSlot.optic.rawValue] = ItemInstance(defID: "reddot")
game.equipment.hands = rifle
for id in ["beans", "waterbottle", "bandage", "ammo_556", "mag_kestrel", "canopener", "painkillers", "flashlight", "warden", "mag_warden"] {
    _ = game.equipment.addToCargo(ItemInstance(defID: id))
}
for (i, id) in ["chocolate", "machete", "canteen"].enumerated() {
    game.items.add(ItemInstance(defID: id), at: game.player.position + Vec3(Float(i) * 0.4 - 0.4, 0, 0.8), yaw: 0)
}
game.equipment.quickSlots[0] = rifle.uid
game.stats.addBleed(rate: 8, dirty: true)
game.stats.energy = 380
game.stats.water = 900
game.stats.wetness = 0.5
game.message("You picked up Police Vest")
game.message("Bleeding! Bandage the wound", important: true)
for _ in 0..<30 { game.update(dt: 1.0 / 60.0) }
game.hud.prompt = "Open door"

let devices: [(String, CGFloat, CGFloat, UIEdgeInsets)] = [
    ("se", 667, 375, UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)),
    ("14", 844, 390, UIEdgeInsets(top: 0, left: 47, bottom: 21, right: 47)),
    ("promax", 932, 430, UIEdgeInsets(top: 0, left: 59, bottom: 21, right: 59)),
]
let summary = SaveSummary(serverID: "regular", day: 3, hour: 14.5, location: "Halden", survivedSeconds: 7380, savedAt: Date())
for (dev, w, h, ins) in devices {
    UIView.previewScreen = CGRect(x: 0, y: 0, width: w, height: h)
    UIView.previewSafeArea = ins
    func root() -> UIView { UIView(frame: CGRect(x: 0, y: 0, width: w, height: h)) }

    let r1 = root(); let m = MainMenuView(); m.present(in: r1); m.setServer(ServerProfile.byID("regular")); m.setContinue(summary)
    save(r1, name: "menu", device: dev, backdrop: "menu")

    let r2 = root(); let hud = HUDView(frame: r1.bounds); r2.addSubview(hud)
    hud.fpsLabel.isHidden = false; hud.fpsLabel.text = "60 FPS  ·  412 draws  ·  380k tris"
    hud.layoutIfNeeded()
    game.fillHUD(hud); hud.controls.setPrompt(game.hud.prompt); hud.setMessages(game.hud.messages)
    hud.controls.input.aimToggled = false; hud.controls.syncToggles()
    hud.showBanner("Halden", subtitle: "Town")
    save(r2, name: "hud", device: dev, backdrop: "fp")

    let r3 = root(); let inv = InventoryView(game: game); inv.present(in: r3)
    save(r3, name: "inventory", device: dev, backdrop: "fp")

    let r4 = root(); let st = SettingsView(); st.present(in: r4)
    save(r4, name: "settings", device: dev, backdrop: "menu")

    let r5 = root(); let sv = ServersView(); sv.summaryProvider = { $0.id == "regular" ? summary : nil }; sv.refresh(); sv.present(in: r5)
    save(r5, name: "servers", device: dev, backdrop: "menu")

    let r6 = root(); let p = PauseMenuView(); p.setInfo("ASHVALE  |  REGULAR\nDAY 3  ·  RAIN  ·  HALDEN"); p.present(in: r6)
    save(r6, name: "pause", device: dev, backdrop: "fp")

    let r7 = root(); let d = DeathView(); d.configure(cause: "Blood loss", survived: 7380, kills: 14, distance: 5230); d.present(in: r7)
    save(r7, name: "death", device: dev, backdrop: "tp")

    let r8 = root(); let lv = LoadingView(); lv.setLocation("ASHVALE  |  REGULAR"); lv.status.text = "STREAMING TERRAIN"; lv.bar.progress = 0.6; lv.present(in: r8)
    save(r8, name: "loading", device: dev, backdrop: "none")

    let r9 = root(); let iv = StoryIntroView(); iv.present(in: r9)
    iv.setCaption("Three weeks ago the Grey Fever reached Ashvale. The radio went quiet on the ninth day.")
    iv.update(dt: 10, fade: 0)
    save(r9, name: "intro", device: dev, backdrop: "menu")

    let r10 = root(); let cr = CreditsView(); cr.present(in: r10)
    save(r10, name: "credits", device: dev, backdrop: "menu")
}
