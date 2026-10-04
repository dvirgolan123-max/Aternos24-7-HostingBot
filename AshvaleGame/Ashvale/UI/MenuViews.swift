//
//  MenuViews.swift
//  Ashvale
//
//  Boot splash, cinematic main menu, story intro, loading screen, server
//  browser, credits, pause menu and death screen.
//

import UIKit

/// Base class for full-screen overlays with fade in/out.
class OverlayView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        alpha = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present(in parent: UIView, duration: TimeInterval = 0.35) {
        frame = parent.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        parent.addSubview(self)
        UIView.animate(withDuration: duration) { self.alpha = 1 }
    }

    func dismiss(duration: TimeInterval = 0.3, completion: (() -> Void)? = nil) {
        UIView.animate(withDuration: duration, animations: { self.alpha = 0 }, completion: { _ in
            self.removeFromSuperview()
            completion?()
        })
    }
}

final class GradientView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }
    var gradient: CAGradientLayer { layer as! CAGradientLayer }

    init(colors: [UIColor], start: CGPoint, end: CGPoint) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        gradient.colors = colors.map { $0.cgColor }
        gradient.startPoint = start
        gradient.endPoint = end
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class ProgressBar: UIView {
    private let fill = UIView()
    var progress: Float = 0 { didSet { setNeedsLayout() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 1, alpha: 0.12)
        layer.cornerRadius = 1.5
        clipsToBounds = true
        fill.backgroundColor = Theme.accent
        addSubview(fill)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        fill.frame = CGRect(x: 0, y: 0, width: bounds.width * CGFloat(saturatef(progress)), height: bounds.height)
    }
}

// MARK: - Boot

final class BootView: OverlayView {
    private let title = UILabel()
    private let sub = UILabel()
    let bar = ProgressBar()
    let status = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        title.attributedText = Theme.tracked("ASHVALE", size: 44, weight: .heavy, color: Theme.text, kern: 14)
        title.textAlignment = .center
        addSubview(title)
        sub.attributedText = Theme.tracked("THE GREY FEVER", size: 12, weight: .semibold, color: Theme.accent, kern: 6)
        sub.textAlignment = .center
        addSubview(sub)
        addSubview(bar)
        status.font = Theme.font(11, .medium)
        status.textColor = Theme.textDim
        status.textAlignment = .center
        addSubview(status)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        title.frame = CGRect(x: 0, y: bounds.midY - 50, width: bounds.width, height: 56)
        sub.frame = CGRect(x: 0, y: bounds.midY + 6, width: bounds.width, height: 18)
        bar.frame = CGRect(x: bounds.midX - 110, y: bounds.midY + 48, width: 220, height: 3)
        status.frame = CGRect(x: 0, y: bounds.midY + 58, width: bounds.width, height: 16)
    }
}

// MARK: - Main menu

final class MainMenuView: OverlayView {
    let newGame = MenuButton(title: "NEW GAME")
    let continueGame = MenuButton(title: "CONTINUE")
    let servers = MenuButton(title: "SERVERS")
    let settings = MenuButton(title: "SETTINGS")
    let credits = MenuButton(title: "CREDITS")
    private let shade = GradientView(colors: [UIColor(white: 0, alpha: 0.88), UIColor(white: 0, alpha: 0.55), UIColor(white: 0, alpha: 0)],
                                     start: CGPoint(x: 0, y: 0.5), end: CGPoint(x: 0.75, y: 0.5))
    private let bottomShade = GradientView(colors: [UIColor(white: 0, alpha: 0), UIColor(white: 0, alpha: 0.6)],
                                           start: CGPoint(x: 0.5, y: 0.6), end: CGPoint(x: 0.5, y: 1))
    private let title = UILabel()
    private let subtitle = UILabel()
    private let rule = UIView()
    private let serverLabel = UILabel()
    private let version = UILabel()
    private let quote = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(shade)
        addSubview(bottomShade)
        title.attributedText = Theme.tracked("ASHVALE", size: 46, weight: .heavy, color: Theme.text, kern: 12)
        addSubview(title)
        subtitle.attributedText = Theme.tracked("THE GREY FEVER", size: 12, weight: .bold, color: Theme.accent, kern: 7)
        addSubview(subtitle)
        rule.backgroundColor = Theme.accentDim
        addSubview(rule)
        for b in [newGame, continueGame, servers, settings, credits] { addSubview(b) }
        serverLabel.numberOfLines = 2
        addSubview(serverLabel)
        version.attributedText = Theme.tracked("VERTICAL SLICE  ·  BUILD 0.1", size: 9, weight: .semibold, color: Theme.textDim, kern: 2)
        addSubview(version)
        quote.attributedText = Theme.tracked("\"THE QUIET IS THE WORST PART.\"", size: 10, weight: .semibold, color: UIColor(white: 0.8, alpha: 0.7), kern: 2.5)
        quote.textAlignment = .right
        addSubview(quote)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setContinue(_ summary: SaveSummary?) {
        if let s = summary {
            continueGame.isEnabled = true
            continueGame.subtitleLabel.text = "DAY \(s.day)  ·  \(s.timeText)  ·  \(s.location.uppercased())  ·  \(s.survivedText.uppercased())"
        } else {
            continueGame.isEnabled = false
            continueGame.subtitleLabel.text = "NO SURVIVOR ON THIS SERVER"
        }
        continueGame.setNeedsLayout()
    }

    func setServer(_ p: ServerProfile) {
        let t = NSMutableAttributedString(attributedString: Theme.tracked("SERVER  ", size: 9, weight: .bold, color: Theme.textDim, kern: 2))
        t.append(Theme.tracked(p.name, size: 10, weight: .bold, color: Theme.accent, kern: 2))
        serverLabel.attributedText = t
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let ins = safeAreaInsets
        let left = max(ins.left, 20) + 18
        let h = bounds.height
        shade.frame = bounds
        bottomShade.frame = bounds
        let scale = min(1, h / 390)
        title.frame = CGRect(x: left, y: h * 0.1, width: 420, height: 56 * scale)
        subtitle.frame = CGRect(x: left + 4, y: title.frame.maxY, width: 400, height: 18)
        rule.frame = CGRect(x: left + 4, y: subtitle.frame.maxY + 10, width: 150, height: 1)
        var y = rule.frame.maxY + 16 * scale
        let bh = 40 * scale
        for b in [newGame, continueGame, servers, settings, credits] {
            let tall = b === continueGame
            b.frame = CGRect(x: left - 14, y: y, width: 380, height: tall ? bh + 10 : bh)
            y += (tall ? bh + 10 : bh) + 4 * scale
        }
        serverLabel.frame = CGRect(x: left, y: h - max(ins.bottom, 10) - 34, width: 420, height: 14)
        version.frame = CGRect(x: left, y: h - max(ins.bottom, 10) - 18, width: 300, height: 12)
        quote.frame = CGRect(x: bounds.width - max(ins.right, 20) - 420, y: h - max(ins.bottom, 10) - 18, width: 400, height: 12)
    }
}

// MARK: - Story intro

final class StoryIntroView: OverlayView {
    private let topBar = UIView()
    private let bottomBar = UIView()
    private let caption = UILabel()
    private let skip = PillButton("SKIP INTRO", size: 10)
    private let hint = UILabel()
    var onSkip: (() -> Void)?
    var onTap: (() -> Void)?
    private var fullText = ""
    private var shown: Float = 0
    let fadeView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        fadeView.backgroundColor = .black
        fadeView.isUserInteractionEnabled = false
        addSubview(fadeView)
        topBar.backgroundColor = .black
        bottomBar.backgroundColor = .black
        addSubview(topBar)
        addSubview(bottomBar)
        caption.numberOfLines = 0
        caption.textAlignment = .center
        addSubview(caption)
        skip.action = { [weak self] in self?.onSkip?() }
        addSubview(skip)
        hint.attributedText = Theme.tracked("TAP TO CONTINUE", size: 9, weight: .semibold, color: Theme.textDim, kern: 2)
        hint.textAlignment = .center
        addSubview(hint)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func tapped() { onTap?() }

    func setCaption(_ text: String?) {
        let t = text ?? ""
        if t != fullText {
            fullText = t
            shown = 0
        }
    }

    func update(dt: Float, fade: Float) {
        shown = min(Float(fullText.count), shown + dt * 38)
        let visible = String(fullText.prefix(Int(shown)))
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 5
        style.alignment = .center
        caption.attributedText = NSAttributedString(string: visible, attributes: [
            .font: Theme.font(17, .medium), .foregroundColor: UIColor(white: 0.93, alpha: 1), .kern: 0.6, .paragraphStyle: style,
        ])
        fadeView.alpha = CGFloat(fade)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let barH = bounds.height * 0.12
        fadeView.frame = bounds
        topBar.frame = CGRect(x: 0, y: 0, width: bounds.width, height: barH)
        bottomBar.frame = CGRect(x: 0, y: bounds.height - barH, width: bounds.width, height: barH)
        caption.frame = CGRect(x: bounds.width * 0.14, y: bounds.height - barH - 96, width: bounds.width * 0.72, height: 90)
        let ins = safeAreaInsets
        skip.frame = CGRect(x: bounds.width - max(ins.right, 16) - 110, y: barH * 0.5 - 14, width: 104, height: 28)
        hint.frame = CGRect(x: 0, y: bounds.height - barH * 0.6, width: bounds.width, height: 14)
    }
}

// MARK: - Loading

final class LoadingView: OverlayView {
    private let title = UILabel()
    private let location = UILabel()
    private let tip = UILabel()
    let bar = ProgressBar()
    let status = UILabel()
    private let shade = GradientView(colors: [UIColor(red: 0.04, green: 0.045, blue: 0.05, alpha: 1), UIColor(red: 0.1, green: 0.1, blue: 0.09, alpha: 1)],
                                     start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1, y: 1))
    static let tips = [
        "Bleeding kills quietly. Bandage wounds before you do anything else.",
        "Closed doors stop the infected. Use them.",
        "Gunshots carry for hundreds of meters. Every shot is an invitation.",
        "Crouching makes you quieter and harder to see.",
        "Lake water can make you sick. Wells and hand pumps are safer.",
        "Rain soaks your clothes. Wet and cold is how most survivors die.",
        "Magazines are not universal. Check what fits before you load rounds.",
        "Cans need a blade or an opener — or you lose half of it smashing them.",
        "Hospitals have medicine. Police stations have pistols. The military has everything — and the dead guarding it.",
        "At night, a flashlight helps you see. It also helps them see you.",
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(shade)
        title.attributedText = Theme.tracked("ASHVALE", size: 30, weight: .heavy, color: Theme.text, kern: 10)
        addSubview(title)
        location.numberOfLines = 1
        addSubview(location)
        tip.numberOfLines = 0
        tip.textAlignment = .left
        addSubview(tip)
        addSubview(bar)
        status.font = Theme.font(11, .semibold)
        status.textColor = Theme.textDim
        addSubview(status)
        setTip(LoadingView.tips.randomElement() ?? "")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setTip(_ t: String) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        let s = NSMutableAttributedString(attributedString: Theme.tracked("SURVIVAL TIP\n", size: 10, weight: .bold, color: Theme.accent, kern: 3))
        s.append(NSAttributedString(string: t, attributes: [.font: Theme.font(14, .medium), .foregroundColor: Theme.text, .paragraphStyle: style]))
        tip.attributedText = s
    }

    func setLocation(_ t: String) {
        location.attributedText = Theme.tracked(t.uppercased(), size: 11, weight: .bold, color: Theme.textDim, kern: 4)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        shade.frame = bounds
        let ins = safeAreaInsets
        let left = max(ins.left, 24) + 12
        title.frame = CGRect(x: left, y: bounds.height * 0.16, width: 400, height: 40)
        location.frame = CGRect(x: left + 2, y: title.frame.maxY + 2, width: 400, height: 16)
        tip.frame = CGRect(x: left, y: bounds.height * 0.42, width: min(520, bounds.width * 0.6), height: 90)
        bar.frame = CGRect(x: left, y: bounds.height - max(ins.bottom, 14) - 40, width: bounds.width - left * 2, height: 3)
        status.frame = CGRect(x: left, y: bar.frame.maxY + 8, width: 400, height: 16)
    }
}

// MARK: - Servers

final class ServersView: OverlayView {
    var onJoin: ((ServerProfile) -> Void)?
    var onBack: (() -> Void)?
    var summaryProvider: ((ServerProfile) -> SaveSummary?)?
    private let panel = UIView()
    private let header = UILabel()
    private let note = UILabel()
    private var rows: [UIControl] = []
    private let join = PillButton("JOIN SERVER", size: 13)
    private let back = PillButton("BACK", size: 13)
    private let detail = UILabel()
    private var selected = ServerProfile.selectedID

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0, alpha: 0.55)
        Theme.stylePanel(panel, radius: 12)
        addSubview(panel)
        header.attributedText = Theme.tracked("SERVER BROWSER", size: 18, weight: .heavy, kern: 5)
        panel.addSubview(header)
        note.attributedText = Theme.tracked("LOCAL SESSIONS HOSTED ON THIS DEVICE  ·  EACH SERVER HAS ITS OWN SURVIVOR", size: 9, weight: .semibold, color: Theme.textDim, kern: 1.5)
        panel.addSubview(note)
        for (i, p) in ServerProfile.all.enumerated() {
            let row = UIControl()
            row.tag = 100 + i   // keep clear of the child label tags (1...3); viewWithTag also matches the view itself
            row.layer.cornerRadius = 8
            row.layer.borderWidth = 1
            row.addTarget(self, action: #selector(rowTapped(_:)), for: .touchUpInside)
            let name = UILabel()
            name.tag = 1
            name.attributedText = Theme.tracked(p.name, size: 13, weight: .bold, kern: 1.5)
            row.addSubview(name)
            let info = UILabel()
            info.tag = 2
            info.font = Theme.font(10, .medium)
            info.textColor = Theme.textDim
            row.addSubview(info)
            let ping = UILabel()
            ping.tag = 3
            ping.attributedText = Theme.tracked("LOCAL  ·  1/1", size: 10, weight: .bold, color: Theme.good, kern: 1)
            ping.textAlignment = .right
            row.addSubview(ping)
            panel.addSubview(row)
            rows.append(row)
        }
        detail.numberOfLines = 0
        panel.addSubview(detail)
        join.selectedStyle = true
        join.action = { [weak self] in
            guard let self = self else { return }
            ServerProfile.selectedID = self.selected
            self.onJoin?(ServerProfile.byID(self.selected))
        }
        back.action = { [weak self] in self?.onBack?() }
        panel.addSubview(join)
        panel.addSubview(back)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func rowTapped(_ sender: UIControl) {
        Haptics.tap()
        selected = ServerProfile.all[sender.tag - 100].id
        ServerProfile.selectedID = selected
        refresh()
    }

    func refresh() {
        for (i, row) in rows.enumerated() {
            let p = ServerProfile.all[i]
            let isSel = p.id == selected
            row.backgroundColor = isSel ? Theme.accent.withAlphaComponent(0.18) : UIColor(white: 1, alpha: 0.04)
            row.layer.borderColor = (isSel ? Theme.accent : Theme.border).cgColor
            if let info = row.viewWithTag(2) as? UILabel {
                if let s = summaryProvider?(p) {
                    info.text = "\(p.mode)  ·  Day \(s.day), \(s.timeText)  ·  Survivor alive (\(s.survivedText))"
                } else {
                    info.text = "\(p.mode)  ·  No survivor yet"
                }
            }
        }
        let p = ServerProfile.byID(selected)
        let s = NSMutableAttributedString(attributedString: Theme.tracked(p.name + "\n", size: 12, weight: .bold, color: Theme.accent, kern: 1.5))
        s.append(NSAttributedString(string: p.summary + "\n", attributes: [.font: Theme.font(12, .medium), .foregroundColor: Theme.text]))
        let rules = "Loot ×\(String(format: "%.1f", p.lootMultiplier))   Infected ×\(String(format: "%.1f", p.infectedMultiplier))   Needs ×\(String(format: "%.2f", p.survivalDrain))   Crosshair \(p.crosshairAllowed ? "ON" : "OFF")"
        s.append(NSAttributedString(string: rules, attributes: [.font: Theme.mono(10), .foregroundColor: Theme.textDim]))
        detail.attributedText = s
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = min(bounds.width - 60, 640), h = min(bounds.height - 30, 360)
        panel.frame = CGRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)
        header.frame = CGRect(x: 20, y: 14, width: w - 40, height: 24)
        note.frame = CGRect(x: 20, y: 38, width: w - 40, height: 14)
        var y: CGFloat = 60
        for row in rows {
            row.frame = CGRect(x: 16, y: y, width: w - 32, height: 46)
            row.viewWithTag(1)?.frame = CGRect(x: 12, y: 6, width: w - 200, height: 18)
            row.viewWithTag(2)?.frame = CGRect(x: 12, y: 24, width: w - 60, height: 16)
            row.viewWithTag(3)?.frame = CGRect(x: w - 32 - 130, y: 6, width: 118, height: 18)
            y += 52
        }
        detail.frame = CGRect(x: 20, y: y + 2, width: w - 40, height: h - y - 52)
        back.frame = CGRect(x: 16, y: h - 46, width: 110, height: 34)
        join.frame = CGRect(x: w - 16 - 160, y: h - 46, width: 160, height: 34)
    }
}

// MARK: - Credits

final class CreditsView: OverlayView {
    var onBack: (() -> Void)?
    private let scroll = UIScrollView()
    private let text = UILabel()
    private let back = PillButton("BACK", size: 13)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0, alpha: 0.82)
        addSubview(scroll)
        text.numberOfLines = 0
        text.textAlignment = .center
        let s = NSMutableAttributedString(string: "")
        func head(_ t: String) { s.append(Theme.tracked("\n" + t + "\n", size: 11, weight: .bold, color: Theme.accent, kern: 4)) }
        func line(_ t: String) { s.append(NSAttributedString(string: t + "\n", attributes: [.font: Theme.font(14, .medium), .foregroundColor: Theme.text])) }
        s.append(Theme.tracked("ASHVALE\n", size: 30, weight: .heavy, kern: 10))
        s.append(Theme.tracked("THE GREY FEVER\n", size: 11, weight: .bold, color: Theme.accent, kern: 6))
        head("GAME DESIGN & PROGRAMMING")
        line("Built with Claude Code for dvirgolan123-max")
        head("ENGINE")
        line("Custom Swift + Metal renderer")
        line("Procedural world, buildings, textures and audio")
        head("WORLD")
        line("Halden · Brekka · Northmill Works")
        line("Camp Vigil · Route 9 Checkpoint · Lake Silva")
        line("Greywood · Kettle Hills")
        head("ART")
        line("Every mesh, texture and sound in this game is generated at runtime.")
        line("No third-party assets were used.")
        head("SPECIAL THANKS")
        line("Everyone who still keeps a can opener in their pocket.")
        s.append(NSAttributedString(string: "\n\nStay quiet. Stay warm. Stay alive.\n\n", attributes: [.font: Theme.font(13, .semibold), .foregroundColor: Theme.textDim]))
        text.attributedText = s
        scroll.addSubview(text)
        back.action = { [weak self] in self?.onBack?() }
        addSubview(back)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds.insetBy(dx: 40, dy: 10)
        let size = text.sizeThatFits(CGSize(width: scroll.bounds.width, height: 4000))
        text.frame = CGRect(x: 0, y: 20, width: scroll.bounds.width, height: size.height)
        scroll.contentSize = CGSize(width: scroll.bounds.width, height: size.height + 60)
        let ins = safeAreaInsets
        back.frame = CGRect(x: max(ins.left, 16) + 4, y: max(ins.top, 12), width: 90, height: 32)
    }
}

// MARK: - Pause

final class PauseMenuView: OverlayView {
    let resume = MenuButton(title: "RESUME")
    let settings = MenuButton(title: "SETTINGS")
    let mainMenu = MenuButton(title: "BACK TO MAIN MENU")
    private let title = UILabel()
    private let info = UILabel()
    private let shade = GradientView(colors: [UIColor(white: 0, alpha: 0.85), UIColor(white: 0, alpha: 0.35)], start: CGPoint(x: 0, y: 0.5), end: CGPoint(x: 1, y: 0.5))

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(shade)
        title.attributedText = Theme.tracked("PAUSED", size: 30, weight: .heavy, kern: 10)
        addSubview(title)
        info.numberOfLines = 0
        addSubview(info)
        for b in [resume, settings, mainMenu] { addSubview(b) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setInfo(_ text: String) {
        info.attributedText = Theme.tracked(text, size: 10, weight: .semibold, color: Theme.textDim, kern: 1.5)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        shade.frame = bounds
        let left = max(safeAreaInsets.left, 20) + 18
        title.frame = CGRect(x: left, y: bounds.height * 0.16, width: 300, height: 40)
        info.frame = CGRect(x: left, y: title.frame.maxY + 2, width: 420, height: 30)
        var y = info.frame.maxY + 14
        for b in [resume, settings, mainMenu] {
            b.frame = CGRect(x: left - 14, y: y, width: 360, height: 42)
            y += 48
        }
    }
}

// MARK: - Death

final class DeathView: OverlayView {
    let respawn = PillButton("RESPAWN", size: 14)
    let mainMenu = PillButton("MAIN MENU", size: 14)
    private let title = UILabel()
    private let cause = UILabel()
    private let stats = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.05, green: 0, blue: 0, alpha: 0.6)
        title.attributedText = Theme.tracked("YOU ARE DEAD", size: 34, weight: .heavy, color: UIColor(red: 0.85, green: 0.15, blue: 0.12, alpha: 1), kern: 10)
        title.textAlignment = .center
        addSubview(title)
        cause.textAlignment = .center
        addSubview(cause)
        stats.textAlignment = .center
        stats.numberOfLines = 0
        addSubview(stats)
        respawn.selectedStyle = true
        addSubview(respawn)
        addSubview(mainMenu)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(cause c: String, survived: Float, kills: Int, distance: Float) {
        cause.attributedText = Theme.tracked(c.uppercased(), size: 13, weight: .bold, color: Theme.text, kern: 3)
        let m = Int(survived / 60), s = Int(survived) % 60
        stats.attributedText = Theme.tracked("SURVIVED \(m)M \(s)S   ·   INFECTED KILLED \(kills)   ·   TRAVELLED \(Int(distance))M\nYOUR BODY AND GEAR REMAIN WHERE YOU FELL.",
                                             size: 10, weight: .semibold, color: Theme.textDim, kern: 1.5)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        title.frame = CGRect(x: 0, y: bounds.height * 0.28, width: bounds.width, height: 44)
        cause.frame = CGRect(x: 0, y: title.frame.maxY + 6, width: bounds.width, height: 18)
        stats.frame = CGRect(x: 0, y: cause.frame.maxY + 10, width: bounds.width, height: 34)
        respawn.frame = CGRect(x: bounds.midX - 170, y: stats.frame.maxY + 26, width: 160, height: 40)
        mainMenu.frame = CGRect(x: bounds.midX + 10, y: stats.frame.maxY + 26, width: 160, height: 40)
    }
}

// MARK: - Confirmation

final class ConfirmView: OverlayView {
    var onConfirm: (() -> Void)?
    private let panel = UIView()
    private let label = UILabel()
    private let yes = PillButton("CONFIRM", size: 12)
    private let no = PillButton("CANCEL", size: 12)

    init(message: String) {
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 0, alpha: 0.6)
        Theme.stylePanel(panel)
        addSubview(panel)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.attributedText = NSAttributedString(string: message, attributes: [.font: Theme.font(14, .medium), .foregroundColor: Theme.text])
        panel.addSubview(label)
        yes.selectedStyle = true
        yes.action = { [weak self] in
            self?.dismiss()
            self?.onConfirm?()
        }
        no.action = { [weak self] in self?.dismiss() }
        panel.addSubview(yes)
        panel.addSubview(no)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        panel.frame = CGRect(x: bounds.midX - 190, y: bounds.midY - 80, width: 380, height: 160)
        label.frame = CGRect(x: 20, y: 16, width: 340, height: 80)
        no.frame = CGRect(x: 20, y: 110, width: 160, height: 36)
        yes.frame = CGRect(x: 200, y: 110, width: 160, height: 36)
    }
}
