//
//  HUDView.swift
//  Ashvale
//
//  In-game heads-up display: touch controls, crosshair, interaction prompt,
//  survival status, notifications, location banner, ammo, quick slots, FPS.
//

import UIKit

/// Small icon + bar status indicator.
final class StatusIndicator: UIView {
    private let icon = UILabel()
    private let bar = UIView()
    private let fill = UIView()
    var value: Float = 1 { didSet { setNeedsLayout() } }
    var warning = false { didSet { refresh() } }
    var critical = false { didSet { refresh() } }
    private let baseColor: UIColor

    init(symbol: String, color: UIColor) {
        baseColor = color
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        icon.attributedText = Theme.tracked(symbol, size: 9, weight: .heavy, color: Theme.text, kern: 0.8)
        icon.textAlignment = .center
        addSubview(icon)
        bar.backgroundColor = UIColor(white: 1, alpha: 0.14)
        bar.layer.cornerRadius = 2
        bar.clipsToBounds = true
        addSubview(bar)
        fill.backgroundColor = color
        bar.addSubview(fill)
        backgroundColor = UIColor(white: 0, alpha: 0.35)
        layer.cornerRadius = 6
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func refresh() {
        fill.backgroundColor = critical ? Theme.danger : (warning ? Theme.accent : baseColor)
        layer.borderWidth = critical ? 1.5 : 0
        layer.borderColor = Theme.danger.cgColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        icon.frame = CGRect(x: 0, y: 2, width: bounds.width, height: 14)
        bar.frame = CGRect(x: 5, y: bounds.height - 9, width: bounds.width - 10, height: 4)
        fill.frame = CGRect(x: 0, y: 0, width: bar.bounds.width * CGFloat(saturatef(value)), height: 4)
    }
}

final class HUDView: UIView {
    let controls = TouchControlsView()
    let crosshair = UIView()
    private let hitMarker = UILabel()
    let fpsLabel = UILabel()
    private let banner = UILabel()
    private let bannerSub = UILabel()
    private let messages = UILabel()
    let ammoLabel = UILabel()
    let pauseButton = PillButton("II", size: 14)
    let inventoryButton = PillButton("GEAR", size: 11)
    let cameraButton = PillButton("1P", size: 11)
    let statusStack = UIView()
    var indicators: [String: StatusIndicator] = [:]
    private let damageOverlay = UIView()
    let scopeOverlay = ScopeOverlayView()
    let redDot = UIView()
    let quickSlots = QuickSlotBar()
    let effectsLabel = UILabel()
    let actionLabel = UILabel()
    let actionBar = ProgressBar()
    let compassLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        damageOverlay.isUserInteractionEnabled = false
        damageOverlay.backgroundColor = UIColor(red: 0.6, green: 0, blue: 0, alpha: 1)
        damageOverlay.alpha = 0
        addSubview(damageOverlay)
        scopeOverlay.isHidden = true
        addSubview(scopeOverlay)
        addSubview(controls)

        crosshair.isUserInteractionEnabled = false
        crosshair.backgroundColor = UIColor(white: 1, alpha: 0.85)
        crosshair.layer.cornerRadius = 2
        crosshair.layer.borderWidth = 0.5
        crosshair.layer.borderColor = UIColor(white: 0, alpha: 0.6).cgColor
        addSubview(crosshair)
        redDot.isUserInteractionEnabled = false
        redDot.backgroundColor = UIColor(red: 1, green: 0.1, blue: 0.08, alpha: 0.95)
        redDot.layer.cornerRadius = 2.5
        redDot.isHidden = true
        addSubview(redDot)
        hitMarker.attributedText = Theme.tracked("✕", size: 22, weight: .bold, color: UIColor(white: 1, alpha: 0.95), kern: 0)
        hitMarker.textAlignment = .center
        hitMarker.alpha = 0
        addSubview(hitMarker)

        fpsLabel.font = Theme.mono(11)
        fpsLabel.textColor = Theme.good
        fpsLabel.textAlignment = .center
        fpsLabel.isHidden = true
        addSubview(fpsLabel)

        banner.textAlignment = .center
        banner.alpha = 0
        addSubview(banner)
        bannerSub.textAlignment = .center
        bannerSub.alpha = 0
        addSubview(bannerSub)

        messages.numberOfLines = 0
        messages.isUserInteractionEnabled = false
        addSubview(messages)

        effectsLabel.numberOfLines = 0
        effectsLabel.isUserInteractionEnabled = false
        addSubview(effectsLabel)

        ammoLabel.textAlignment = .right
        ammoLabel.numberOfLines = 2
        ammoLabel.isUserInteractionEnabled = true
        addSubview(ammoLabel)

        for b in [pauseButton, inventoryButton, cameraButton] { addSubview(b) }

        statusStack.isUserInteractionEnabled = false
        addSubview(statusStack)
        let specs: [(String, String, UIColor)] = [
            ("health", "HP", UIColor(red: 0.5, green: 0.85, blue: 0.45, alpha: 1)),
            ("blood", "BLD", UIColor(red: 0.85, green: 0.25, blue: 0.22, alpha: 1)),
            ("food", "FOOD", UIColor(red: 0.85, green: 0.65, blue: 0.3, alpha: 1)),
            ("water", "H2O", UIColor(red: 0.35, green: 0.65, blue: 0.95, alpha: 1)),
            ("temp", "TEMP", UIColor(red: 0.95, green: 0.85, blue: 0.5, alpha: 1)),
            ("stamina", "STA", UIColor(white: 0.9, alpha: 1)),
        ]
        for s in specs {
            let ind = StatusIndicator(symbol: s.1, color: s.2)
            indicators[s.0] = ind
            statusStack.addSubview(ind)
        }
        addSubview(quickSlots)
        actionLabel.textAlignment = .center
        actionLabel.isUserInteractionEnabled = false
        addSubview(actionLabel)
        actionBar.isHidden = true
        actionBar.isUserInteractionEnabled = false
        addSubview(actionBar)
        compassLabel.textAlignment = .center
        compassLabel.isUserInteractionEnabled = false
        addSubview(compassLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let ins = safeAreaInsets
        let left = max(ins.left, 12), top = max(ins.top, 8)
        let right = bounds.width - max(ins.right, 12)
        damageOverlay.frame = bounds
        scopeOverlay.frame = bounds
        controls.frame = bounds
        crosshair.frame = CGRect(x: bounds.midX - 2, y: bounds.midY - 2, width: 4, height: 4)
        redDot.frame = CGRect(x: bounds.midX - 2.5, y: bounds.midY - 2.5, width: 5, height: 5)
        hitMarker.frame = CGRect(x: bounds.midX - 15, y: bounds.midY - 15, width: 30, height: 30)
        fpsLabel.frame = CGRect(x: bounds.midX - 120, y: top, width: 240, height: 14)
        banner.frame = CGRect(x: 0, y: bounds.height * 0.18, width: bounds.width, height: 34)
        bannerSub.frame = CGRect(x: 0, y: bounds.height * 0.18 + 34, width: bounds.width, height: 18)
        // Status column (top-left).
        statusStack.frame = CGRect(x: left, y: top, width: 6 * 46, height: 30)
        let keys = ["health", "blood", "food", "water", "temp", "stamina"]
        for (i, k) in keys.enumerated() {
            indicators[k]?.frame = CGRect(x: CGFloat(i) * 46, y: 0, width: 42, height: 28)
        }
        effectsLabel.frame = CGRect(x: left, y: top + 32, width: 280, height: 40)
        messages.frame = CGRect(x: left, y: top + 70, width: min(340, bounds.width * 0.4), height: 120)
        // Top-right buttons.
        let bw: CGFloat = 50, bh: CGFloat = 32
        pauseButton.frame = CGRect(x: right - bw, y: top, width: bw, height: bh)
        inventoryButton.frame = CGRect(x: right - bw * 2 - 8, y: top, width: bw, height: bh)
        cameraButton.frame = CGRect(x: right - bw * 3 - 16, y: top, width: bw, height: bh)
        ammoLabel.frame = CGRect(x: right - 220, y: top + bh + 6, width: 220, height: 40)
        let qsW: CGFloat = min(330, bounds.width * 0.38)
        quickSlots.frame = CGRect(x: bounds.midX - qsW * 0.5 - 40, y: bounds.height - max(ins.bottom, 6) - 50, width: qsW, height: 46)
        actionLabel.frame = CGRect(x: bounds.midX - 160, y: bounds.midY + 46, width: 320, height: 16)
        actionBar.frame = CGRect(x: bounds.midX - 80, y: bounds.midY + 66, width: 160, height: 3)
        compassLabel.frame = CGRect(x: bounds.midX - 100, y: top + 16, width: 200, height: 16)
        controls.reservedRects = [pauseButton.frame, inventoryButton.frame, cameraButton.frame, quickSlots.frame, ammoLabel.frame]
    }

    func showBanner(_ title: String, subtitle: String) {
        banner.attributedText = Theme.tracked(title.uppercased(), size: 26, weight: .heavy, color: Theme.text, kern: 6)
        bannerSub.attributedText = Theme.tracked(subtitle.uppercased(), size: 11, weight: .semibold, color: Theme.accent, kern: 3)
        banner.alpha = 0
        bannerSub.alpha = 0
        UIView.animate(withDuration: 0.8, animations: {
            self.banner.alpha = 1
            self.bannerSub.alpha = 1
        }, completion: { _ in
            UIView.animate(withDuration: 1.2, delay: 2.5, options: [], animations: {
                self.banner.alpha = 0
                self.bannerSub.alpha = 0
            }, completion: nil)
        })
    }

    func setMessages(_ list: [HUDMessage]) {
        let text = NSMutableAttributedString(string: "")
        for (i, m) in list.enumerated() {
            let alpha = CGFloat(min(1, m.time / 0.6))
            let color = m.important ? Theme.accent.withAlphaComponent(alpha) : UIColor(white: 0.95, alpha: alpha)
            text.append(NSAttributedString(string: m.text + (i < list.count - 1 ? "\n" : ""),
                                           attributes: [.font: Theme.font(12, .semibold), .foregroundColor: color]))
        }
        messages.attributedText = text
    }

    func setDamage(_ amount: Float) {
        damageOverlay.alpha = CGFloat(min(0.35, amount * 0.35))
    }

    func flashHit() {
        hitMarker.alpha = 1
        UIView.animate(withDuration: 0.25) { self.hitMarker.alpha = 0 }
    }
}

/// Black scope mask with a reticle for magnified optics.
final class ScopeOverlayView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        let r = min(bounds.width, bounds.height) * 0.46
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        let path = UIBezierPath(rect: bounds)
        path.append(UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).reversing())
        UIColor.black.setFill()
        path.fill()
        let ret = UIBezierPath()
        ret.move(to: CGPoint(x: c.x - r, y: c.y))
        ret.addLine(to: CGPoint(x: c.x - 6, y: c.y))
        ret.move(to: CGPoint(x: c.x + 6, y: c.y))
        ret.addLine(to: CGPoint(x: c.x + r, y: c.y))
        ret.move(to: CGPoint(x: c.x, y: c.y + 6))
        ret.addLine(to: CGPoint(x: c.x, y: c.y + r))
        ret.move(to: CGPoint(x: c.x, y: c.y - r))
        ret.addLine(to: CGPoint(x: c.x, y: c.y - 6))
        ret.lineWidth = 1.2
        UIColor(white: 0, alpha: 0.9).setStroke()
        ret.stroke()
        // Range marks.
        for i in 1...4 {
            let y = c.y + CGFloat(i) * r * 0.12
            let m = UIBezierPath()
            m.move(to: CGPoint(x: c.x - 5, y: y))
            m.addLine(to: CGPoint(x: c.x + 5, y: y))
            m.lineWidth = 1
            m.stroke()
        }
        let ring = UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ring.lineWidth = 3
        UIColor(white: 0.05, alpha: 1).setStroke()
        ring.stroke()
    }
}

/// Bottom quick-access bar. Slots are filled by the inventory system.
final class QuickSlotBar: UIView {
    var slotViews: [UIView] = []
    var iconViews: [UIImageView] = []
    var countLabels: [UILabel] = []
    var onTap: ((Int) -> Void)?
    var onLongPress: ((Int) -> Void)?
    let slotCount = 5
    var highlighted: Int? { didSet { refresh() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        for i in 0..<slotCount {
            let v = UIView()
            v.backgroundColor = UIColor(white: 0, alpha: 0.35)
            v.layer.cornerRadius = 7
            v.layer.borderWidth = 1
            v.layer.borderColor = UIColor(white: 1, alpha: 0.2).cgColor
            let num = UILabel()
            num.attributedText = Theme.tracked("\(i + 1)", size: 8, weight: .bold, color: Theme.textDim, kern: 0)
            num.frame = CGRect(x: 4, y: 2, width: 12, height: 10)
            v.addSubview(num)
            let img = UIImageView()
            img.contentMode = .scaleAspectFit
            v.addSubview(img)
            let cnt = UILabel()
            cnt.font = Theme.mono(9, .bold)
            cnt.textColor = Theme.text
            cnt.textAlignment = .right
            v.addSubview(cnt)
            addSubview(v)
            slotViews.append(v)
            iconViews.append(img)
            countLabels.append(cnt)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let gap: CGFloat = 6
        let w = (bounds.width - gap * CGFloat(slotCount - 1)) / CGFloat(slotCount)
        for (i, v) in slotViews.enumerated() {
            v.frame = CGRect(x: CGFloat(i) * (w + gap), y: 0, width: w, height: bounds.height)
            iconViews[i].frame = v.bounds.insetBy(dx: 6, dy: 5)
            countLabels[i].frame = CGRect(x: 0, y: v.bounds.height - 13, width: v.bounds.width - 4, height: 11)
        }
    }

    private func refresh() {
        for (i, v) in slotViews.enumerated() {
            v.layer.borderColor = (highlighted == i ? Theme.accent : UIColor(white: 1, alpha: 0.2)).cgColor
            v.layer.borderWidth = highlighted == i ? 2 : 1
        }
    }

    private var pressStart: [ObjectIdentifier: (Int, Date)] = [:]

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let p = t.location(in: self)
            if let i = slotViews.firstIndex(where: { $0.frame.contains(p) }) {
                pressStart[ObjectIdentifier(t)] = (i, Date())
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            guard let entry = pressStart.removeValue(forKey: ObjectIdentifier(t)) else { continue }
            let (i, start) = entry
            Haptics.tap()
            if Date().timeIntervalSince(start) > 0.5 { onLongPress?(i) } else { onTap?(i) }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { pressStart.removeValue(forKey: ObjectIdentifier(t)) }
    }
}
