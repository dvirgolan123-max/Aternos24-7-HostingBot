//
//  GameViewController.swift
//  Ashvale
//
//  Root controller: owns the Metal view and renderer, generates the world at
//  boot, and runs the app flow MAIN MENU -> STORY INTRO -> LOADING -> GAMEPLAY
//  plus pause, settings, servers, credits, death and respawn.
//

import UIKit
import MetalKit
import QuartzCore

enum AppPhase {
    case boot, menu, intro, loading, playing, paused, dead
}

final class GameViewController: UIViewController, MTKViewDelegate {
    private var mtkView: MTKView!
    private var renderer: Renderer?
    private(set) var world: World?
    private var registry: MeshRegistry?
    private var characters: CharacterMeshes?
    private(set) var game: Game?
    private var cinematic: CinematicDirector?
    private let scene = RenderScene()
    private(set) var phase: AppPhase = .boot
    private var lastTime: CFTimeInterval = 0
    private var server = ServerProfile.byID(ServerProfile.selectedID)

    private var boot: BootView?
    private var menu: MainMenuView?
    private var intro: StoryIntroView?
    private var loading: LoadingView?
    private var hud: HUDView?
    private var pauseMenu: PauseMenuView?
    private var deathView: DeathView?
    private weak var subOverlay: OverlayView?

    private var loadingSteps: [(String, () -> Bool)] = []
    private var loadingIndex = 0
    private var continueRequested = false
    private var fpsTime: Float = 0
    private var fpsFrames = 0
    private var autosaveTimer: Float = 0
    private var deathShownTimer: Float = 0
    private var lastBanner: String?
    let audio = AudioEngine()

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let device = MTLCreateSystemDefaultDevice() else {
            showFatal("This device does not support Metal.")
            return
        }
        let mv = MTKView(frame: view.bounds, device: device)
        mv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mv.colorPixelFormat = .bgra8Unorm_srgb
        mv.depthStencilPixelFormat = .depth32Float
        mv.clearDepth = 0
        mv.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mv.preferredFramesPerSecond = 60
        mv.framebufferOnly = true
        mv.autoResizeDrawable = false
        mv.isMultipleTouchEnabled = true
        view.addSubview(mv)
        mtkView = mv
        guard let r = Renderer(device: device) else {
            showFatal("Failed to initialise the renderer.")
            return
        }
        r.applySettings(GameSettings.shared.renderSettings, view: mv)
        mv.sampleCount = r.sampleCount
        renderer = r
        mv.delegate = self
        let b = BootView()
        b.present(in: view, duration: 0.6)
        boot = b
        audio.start()
        startBoot()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        guard let mv = mtkView else { return }
        let scale = view.traitCollection.displayScale
        let rs = CGFloat(renderer?.settings.renderScale ?? 1)
        let w = max(1, (view.bounds.width * scale * rs).rounded())
        let h = max(1, (view.bounds.height * scale * rs).rounded())
        mv.drawableSize = CGSize(width: w, height: h)
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }

    private func showFatal(_ msg: String) {
        let l = Theme.label(msg, size: 16, weight: .semibold, align: .center)
        l.frame = view.bounds
        view.addSubview(l)
    }

    func appWillResignActive() {
        if phase == .playing {
            pauseGame()
        }
        saveIfPossible()
    }

    // MARK: Boot

    private func startBoot() {
        let bootView = boot
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let w = WorldGenerator.generate(seed: 1337) { p, msg in
                DispatchQueue.main.async {
                    bootView?.bar.progress = p * 0.85
                    bootView?.status.text = msg.uppercased()
                }
            }
            let reg = MeshRegistry()
            w.registerMeshes(reg)
            let cm = CharacterMeshes.build(registry: reg)
            ItemVisuals.registerAll(registry: reg)
            DispatchQueue.main.async {
                bootView?.status.text = "PAINTING TEXTURES"
                bootView?.bar.progress = 0.9
            }
            let tex = TextureFactory.generateAll()
            DispatchQueue.main.async {
                self?.finishBoot(world: w, registry: reg, characters: cm, textures: tex)
            }
        }
    }

    private func finishBoot(world w: World, registry reg: MeshRegistry, characters cm: CharacterMeshes, textures: [[UInt8]]) {
        guard let r = renderer else { return }
        world = w
        registry = reg
        characters = cm
        r.uploadTextures(textures)
        r.prepare(world: w, registry: reg)
        let cin = CinematicDirector(world: w, seed: 7)
        cin.setupMenu()
        cinematic = cin
        if let s = cin.shots.first { r.prewarm(around: s.eyeFrom, radius: 200) }
        boot?.bar.progress = 1
        boot?.dismiss(duration: 0.8)
        boot = nil
        showMainMenu()
    }

    // MARK: Menu

    private func showMainMenu() {
        phase = .menu
        hud?.removeFromSuperview()
        hud = nil
        cinematic?.setupMenu()
        let m = MainMenuView()
        m.newGame.action = { [weak self] in self?.newGameTapped() }
        m.continueGame.action = { [weak self] in self?.continueTapped() }
        m.servers.action = { [weak self] in self?.showServers() }
        m.settings.action = { [weak self] in self?.showSettings() }
        m.credits.action = { [weak self] in self?.showCredits() }
        m.present(in: view, duration: 0.8)
        menu = m
        refreshMenu()
        audio.setAmbience(menu: true)
    }

    private func refreshMenu() {
        server = ServerProfile.byID(ServerProfile.selectedID)
        menu?.setServer(server)
        menu?.setContinue(SaveSystem.summary(serverID: server.id))
    }

    private func newGameTapped() {
        if SaveSystem.summary(serverID: server.id) != nil {
            let c = ConfirmView(message: "Start a new life on \(server.name)?\nYour current survivor on this server will be lost.")
            c.onConfirm = { [weak self] in self?.startIntro(continueGame: false) }
            c.present(in: view)
        } else {
            startIntro(continueGame: false)
        }
    }

    private func continueTapped() {
        continueRequested = true
        menu?.dismiss()
        menu = nil
        beginLoading(continueGame: true)
    }

    private func showServers() {
        let s = ServersView()
        s.summaryProvider = { SaveSystem.summary(serverID: $0.id) }
        s.refresh()
        s.onBack = { [weak self, weak s] in
            s?.dismiss()
            self?.refreshMenu()
        }
        s.onJoin = { [weak self, weak s] p in
            s?.dismiss()
            guard let self = self else { return }
            self.server = p
            self.refreshMenu()
            if SaveSystem.summary(serverID: p.id) != nil {
                self.continueTapped()
            } else {
                self.startIntro(continueGame: false)
            }
        }
        s.present(in: view)
        subOverlay = s
    }

    private func showSettings() {
        let s = SettingsView()
        s.onBack = { [weak s] in s?.dismiss() }
        s.onChange = { [weak self] in self?.applySettings() }
        s.present(in: view)
        subOverlay = s
    }

    private func showCredits() {
        let c = CreditsView()
        c.onBack = { [weak c] in c?.dismiss() }
        c.present(in: view)
        subOverlay = c
    }

    private func applySettings() {
        let gs = GameSettings.shared
        if let r = renderer {
            r.applySettings(gs.renderSettings, view: mtkView)
            mtkView.sampleCount = r.sampleCount
        }
        updateDrawableSize()
        game?.applySettings()
        hud?.fpsLabel.isHidden = !gs.showFPS
        hud?.controls.joystickScale = CGFloat(gs.joystickScale)
        hud?.setNeedsLayout()
        audio.masterVolume = gs.masterVolume
    }

    // MARK: Intro

    private func startIntro(continueGame: Bool) {
        menu?.dismiss()
        menu = nil
        guard let cin = cinematic else { beginLoading(continueGame: continueGame); return }
        cin.setupIntro()
        if let s = cin.shots.first { renderer?.prewarm(around: s.eyeFrom, radius: 140) }
        let iv = StoryIntroView()
        iv.onSkip = { [weak self] in self?.finishIntro() }
        iv.onTap = { [weak self] in self?.cinematic?.skipShot() }
        iv.present(in: view, duration: 0.6)
        intro = iv
        phase = .intro
        audio.setAmbience(menu: true)
    }

    private func finishIntro() {
        guard phase == .intro else { return }
        GameSettings.shared.introSeen = true
        intro?.dismiss(duration: 0.4)
        intro = nil
        beginLoading(continueGame: false)
    }

    // MARK: Loading

    private func beginLoading(continueGame: Bool) {
        guard let w = world, let reg = registry, let cm = characters, let r = renderer else { return }
        phase = .loading
        let lv = LoadingView()
        lv.setLocation(server.name)
        lv.present(in: view, duration: 0.3)
        loading = lv
        let profile = server
        var chunkList: [(Int, Int, Int)] = []
        loadingSteps = [
            ("PREPARING SURVIVOR", { [weak self] in
                guard let self = self else { return true }
                if self.game == nil {
                    self.game = Game(world: w, registry: reg, characterMeshes: cm, seed: 2024)
                }
                self.game?.configure(server: profile)
                return true
            }),
            (continueGame ? "LOADING SAVE" : "SCATTERING LOOT", { [weak self] in
                guard let self = self, let g = self.game else { return true }
                if continueGame, let save = SaveSystem.load(serverID: profile.id) {
                    g.restore(from: save)
                } else {
                    g.startNewGame()
                    SaveSystem.save(g, serverID: profile.id)
                }
                return true
            }),
            ("STREAMING TERRAIN", { [weak self] in
                guard let self = self, let g = self.game else { return true }
                if chunkList.isEmpty {
                    let p = g.player.position
                    let cx0 = Int(p.x / World.chunkSize), cz0 = Int(p.z / World.chunkSize)
                    for dz in -5...5 {
                        for dx in -5...5 {
                            let cx = cx0 + dx, cz = cz0 + dz
                            if cx < 0 || cz < 0 || cx >= World.chunksPerSide || cz >= World.chunksPerSide { continue }
                            let c = Vec3((Float(cx) + 0.5) * World.chunkSize, p.y, (Float(cz) + 0.5) * World.chunkSize)
                            let d = vdistanceXZ(c, p)
                            if d < r.settings.lod0Distance { chunkList.append((cx, cz, 0)) }
                            if d < 330 { chunkList.append((cx, cz, 1)) }
                        }
                    }
                    chunkList.append((-1, -1, -1))
                }
                // A few chunks per frame keeps the progress bar animating.
                for _ in 0..<4 {
                    guard let item = chunkList.first else { return true }
                    if item.2 < 0 { chunkList.removeAll(); return true }
                    chunkList.removeFirst()
                    r.prewarm(around: Vec3((Float(item.0) + 0.5) * World.chunkSize, 0, (Float(item.1) + 0.5) * World.chunkSize), radius: 1)
                }
                return false
            }),
            ("PREPARING ITEM ICONS", { [weak self] in
                guard let self = self else { return true }
                ItemIcons.shared.generate(renderer: r, uniforms: self.scene.uniforms)
                return true
            }),
            ("WAKING THE INFECTED", { [weak self] in
                self?.game?.populateInfected()
                return true
            }),
        ]
        loadingIndex = 0
    }

    private func runLoadingStep() {
        guard loadingIndex < loadingSteps.count else { return }
        let (name, step) = loadingSteps[loadingIndex]
        loading?.status.text = name
        if step() { loadingIndex += 1 }
        let p = Float(loadingIndex) / Float(loadingSteps.count)
        loading?.bar.progress = p
        if loadingIndex >= loadingSteps.count {
            finishLoading()
        }
    }

    private func finishLoading() {
        loading?.dismiss(duration: 0.6)
        loading = nil
        startPlaying()
    }

    // MARK: Gameplay

    private func startPlaying() {
        guard let g = game else { return }
        let h = HUDView()
        h.frame = view.bounds
        h.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(h)
        hud = h
        h.pauseButton.action = { [weak self] in self?.pauseGame() }
        h.cameraButton.action = { [weak self] in
            guard let self = self, let g = self.game else { return }
            if g.server.firstPersonOnly {
                g.message("This server is first person only")
                return
            }
            g.input.cameraTogglePressed = true
            self.hud?.controls.input.cameraTogglePressed = true
        }
        h.inventoryButton.action = { [weak self] in self?.openInventory() }
        h.quickSlots.onTap = { [weak self] i in self?.hud?.controls.input.quickSlotPressed = i }
        h.quickSlots.onLongPress = { [weak self] i in self?.game?.clearQuickSlot(i) }
        let tapAmmo = UITapGestureRecognizer(target: self, action: #selector(ammoTapped))
        h.ammoLabel.addGestureRecognizer(tapAmmo)
        h.controls.input.crouchToggled = false
        h.controls.input.aimToggled = false
        h.controls.input.sprintToggled = false
        h.controls.syncToggles()
        applySettings()
        phase = .playing
        lastBanner = nil
        audio.setAmbience(menu: false)
        let loc = world?.location(at: g.player.position)?.name ?? "Ashvale"
        h.showBanner(loc, subtitle: "Day \(g.env.day)  ·  \(String(format: "%02d:%02d", Int(g.env.hour), Int((g.env.hour - Float(Int(g.env.hour))) * 60)))")
    }

    @objc private func ammoTapped() {
        hud?.controls.input.fireModePressed = true
    }

    private func pauseGame() {
        guard phase == .playing, let g = game else { return }
        phase = .paused
        hud?.controls.resetAll()
        let p = PauseMenuView()
        p.setInfo("\(server.name)\nDAY \(g.env.day)  ·  \(g.env.weather.name.uppercased())  ·  \(world?.location(at: g.player.position)?.name.uppercased() ?? "WILDERNESS")")
        p.resume.action = { [weak self] in self?.resumeGame() }
        p.settings.action = { [weak self] in self?.showSettings() }
        p.mainMenu.action = { [weak self] in self?.backToMainMenu() }
        p.present(in: view, duration: 0.2)
        pauseMenu = p
        saveIfPossible()
    }

    private func resumeGame() {
        pauseMenu?.dismiss(duration: 0.2)
        pauseMenu = nil
        phase = .playing
        lastTime = CACurrentMediaTime()
    }

    private func backToMainMenu() {
        saveIfPossible()
        pauseMenu?.dismiss()
        pauseMenu = nil
        deathView?.dismiss()
        deathView = nil
        inventory?.dismiss()
        inventory = nil
        hud?.removeFromSuperview()
        hud = nil
        showMainMenu()
    }

    func saveIfPossible() {
        guard let g = game, phase == .playing || phase == .paused || phase == .dead else { return }
        if g.player.alive {
            SaveSystem.save(g, serverID: server.id)
        } else {
            SaveSystem.deleteCharacter(g, serverID: server.id)
        }
    }

    private func showDeath() {
        guard let g = game else { return }
        hud?.controls.resetAll()
        let d = DeathView()
        d.configure(cause: g.deathCause, survived: g.player.timeAlive, kills: g.record.kills, distance: g.record.distanceTravelled)
        d.respawn.action = { [weak self] in self?.respawn() }
        d.mainMenu.action = { [weak self] in self?.backToMainMenu() }
        d.present(in: view, duration: 1.2)
        deathView = d
        SaveSystem.deleteCharacter(g, serverID: server.id)
    }

    private func respawn() {
        guard let g = game else { return }
        deathView?.dismiss()
        deathView = nil
        g.respawn()
        SaveSystem.save(g, serverID: server.id)
        hud?.controls.input = InputState()
        hud?.controls.syncToggles()
        phase = .playing
        let loc = world?.location(at: g.player.position)?.name ?? "Ashvale"
        hud?.showBanner(loc, subtitle: "A new life begins")
    }

    // MARK: Inventory

    private var inventory: InventoryView?

    private func openInventory() {
        guard phase == .playing, let g = game, g.player.alive else { return }
        hud?.controls.resetAll()
        let inv = InventoryView(game: g)
        inv.onClose = { [weak self] in
            self?.inventory?.dismiss(duration: 0.15)
            self?.inventory = nil
        }
        inv.present(in: view, duration: 0.15)
        inventory = inv
        audio.play2D(.uiOpen)
    }

    // MARK: Frame loop

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        var dt = Float(now - lastTime)
        if lastTime == 0 || dt > 0.25 { dt = 1.0 / 60.0 }
        lastTime = now
        guard let r = renderer else { return }
        switch phase {
        case .boot:
            return
        case .menu:
            guard let cin = cinematic else { return }
            cin.update(dt: dt)
            cin.buildScene(scene, characters: characters)
            r.draw(in: view, scene: scene)
        case .intro:
            guard let cin = cinematic else { return }
            cin.update(dt: dt)
            cin.buildScene(scene, characters: characters)
            intro?.setCaption(cin.currentCaption)
            intro?.update(dt: dt, fade: cin.fade)
            r.draw(in: view, scene: scene)
            if cin.finished { finishIntro() }
        case .loading:
            runLoadingStep()
        case .playing, .dead:
            guard let g = game, let h = hud else { return }
            if inventory == nil {
                let collected = h.controls.collect()
                g.input = collected
            } else {
                g.input = InputState()
                g.input.crouchToggled = h.controls.input.crouchToggled
            }
            g.update(dt: dt)
            // Persistent toggles may be changed by the game (e.g. forced crouch).
            h.controls.input.crouchToggled = g.input.crouchToggled
            h.controls.input.aimToggled = g.input.aimToggled
            h.controls.input.sprintToggled = g.input.sprintToggled
            h.controls.syncToggles()
            g.buildScene(scene, dt: dt)
            r.draw(in: view, scene: scene)
            updateHUD(dt: dt)
            inventory?.refreshIfNeeded()
            audio.update(listener: g.camPos, forward: scene.forward, events: g.sounds.drain(), game: g)
            autosaveTimer += dt
            if autosaveTimer > 120 && g.player.alive && g.action == nil {
                autosaveTimer = 0
                SaveSystem.saveAsync(g, serverID: server.id)
            }
            if !g.player.alive {
                if phase == .playing {
                    phase = .dead
                    deathShownTimer = 0
                    inventory?.dismiss()
                    inventory = nil
                }
                deathShownTimer += dt
                if deathShownTimer > 2.2 && deathView == nil { showDeath() }
            }
        case .paused:
            guard let g = game else { return }
            g.buildScene(scene, dt: 0)
            r.draw(in: view, scene: scene)
        }
        fpsFrames += 1
        fpsTime += dt
        if fpsTime > 0.5, let h = hud, !h.fpsLabel.isHidden {
            let fps = Float(fpsFrames) / fpsTime
            h.fpsLabel.text = String(format: "%.0f FPS  ·  %d draws  ·  %dk tris", fps, r.lastDrawCalls, r.lastTriangles / 1000)
            fpsFrames = 0
            fpsTime = 0
        } else if fpsTime > 0.5 {
            fpsFrames = 0
            fpsTime = 0
        }
    }

    private func updateHUD(dt: Float) {
        guard let g = game, let h = hud else { return }
        h.controls.setPrompt(g.hud.prompt)
        h.setMessages(g.hud.messages)
        h.setDamage(g.hud.damageFlash)
        if g.hud.hitMarker > 0.9 { h.flashHit() }
        let scope = g.hud.showScope
        h.scopeOverlay.isHidden = !scope
        if !scope && h.scopeOverlay.isHidden == false { h.scopeOverlay.setNeedsDisplay() }
        if scope { h.scopeOverlay.setNeedsDisplay() }
        let crosshairAllowed = g.server.crosshairAllowed && GameSettings.shared.showCrosshair
        h.crosshair.isHidden = !(crosshairAllowed && !scope && !g.hud.showRedDot) || !g.player.alive
        h.redDot.isHidden = !g.hud.showRedDot || scope
        if let b = g.hud.locationBanner, b != lastBanner, g.hud.locationTimer > 3.5 {
            lastBanner = b
            h.showBanner(b, subtitle: g.world.location(at: g.player.position).map { kindName($0.kind) } ?? "")
        }
        g.fillHUD(h)
    }

    private func kindName(_ k: AreaKind) -> String {
        switch k {
        case .town: return "Town"
        case .village: return "Village"
        case .military: return "Military Base"
        case .industrial: return "Industrial Zone"
        case .checkpoint: return "Military Checkpoint"
        case .farm: return "Farmland"
        case .forest: return "Forest"
        case .wilderness: return "Wilderness"
        }
    }
}
