//
//  TouchControls.swift
//  Ashvale
//
//  Full-screen multi-touch layer: floating joystick on the left, camera look
//  on the right, and the action buttons (AIM, FIRE, RELOAD, JUMP, CROUCH,
//  RUN, INTERACT). Writes into InputState.
//

import UIKit

enum ControlKind: Equatable {
    case joystick
    case look
    case button(ActionKind)
}

enum ActionKind: Int, CaseIterable {
    case fire, aim, reload, jump, crouch, run, interact

    var title: String {
        switch self {
        case .fire: return "FIRE"
        case .aim: return "AIM"
        case .reload: return "RELOAD"
        case .jump: return "JUMP"
        case .crouch: return "CROUCH"
        case .run: return "RUN"
        case .interact: return "USE"
        }
    }

    var isToggle: Bool { self == .aim || self == .crouch || self == .run }
}

/// Circular on-screen button drawn with a glyph and a caption.
final class ActionButtonView: UIView {
    let kind: ActionKind
    var radius: CGFloat = 30 { didSet { setNeedsLayout() } }
    private let caption = UILabel()
    private let ring = UIView()
    var isActive = false { didSet { refresh() } }
    var isPressed = false { didSet { refresh() } }
    var isDimmed = false { didSet { refresh() } }

    init(kind: ActionKind) {
        self.kind = kind
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        ring.layer.borderWidth = 2
        addSubview(ring)
        caption.textAlignment = .center
        caption.adjustsFontSizeToFitWidth = true
        caption.minimumScaleFactor = 0.6
        addSubview(caption)
        setCaption(kind.title)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setCaption(_ t: String) {
        caption.attributedText = Theme.tracked(t, size: kind == .fire ? 14 : 11, weight: .heavy, color: UIColor(white: 1, alpha: 0.92), kern: 1.2)
    }

    private func refresh() {
        let base: UIColor
        if isActive {
            base = Theme.accent.withAlphaComponent(0.55)
        } else if kind == .fire {
            base = UIColor(red: 0.55, green: 0.12, blue: 0.1, alpha: 0.45)
        } else {
            base = UIColor(white: 0.05, alpha: 0.38)
        }
        ring.backgroundColor = isPressed ? base.withAlphaComponent(0.85) : base
        ring.layer.borderColor = (isActive ? Theme.accent : UIColor(white: 1, alpha: 0.35)).cgColor
        alpha = isDimmed ? 0.4 : 1
        transform = isPressed ? CGAffineTransform(scaleX: 0.92, y: 0.92) : .identity
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        ring.frame = bounds
        ring.layer.cornerRadius = bounds.width * 0.5
        caption.frame = bounds.insetBy(dx: 5, dy: 0)
    }
}

final class JoystickView: UIView {
    private let base = UIView()
    private let knob = UIView()
    var radius: CGFloat = 68 { didSet { setNeedsLayout() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        base.backgroundColor = UIColor(white: 0, alpha: 0.22)
        base.layer.borderWidth = 2
        base.layer.borderColor = UIColor(white: 1, alpha: 0.28).cgColor
        addSubview(base)
        knob.backgroundColor = UIColor(white: 1, alpha: 0.35)
        knob.layer.borderWidth = 1
        knob.layer.borderColor = UIColor(white: 1, alpha: 0.6).cgColor
        addSubview(knob)
        alpha = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(at p: CGPoint) {
        base.frame = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
        base.layer.cornerRadius = radius
        let k = radius * 0.45
        knob.frame = CGRect(x: p.x - k, y: p.y - k, width: k * 2, height: k * 2)
        knob.layer.cornerRadius = k
        UIView.animate(withDuration: 0.08) { self.alpha = 1 }
    }

    func moveKnob(to p: CGPoint) {
        knob.center = p
    }

    func hide() {
        UIView.animate(withDuration: 0.15) { self.alpha = 0 }
    }
}

final class TouchControlsView: UIView {
    var input = InputState()
    let joystick = JoystickView()
    private(set) var buttons: [ActionKind: ActionButtonView] = [:]
    private var assignments: [ObjectIdentifier: ControlKind] = [:]
    private var lastLook: [ObjectIdentifier: CGPoint] = [:]
    private var joyCenter = CGPoint.zero
    private var joyTouch: ObjectIdentifier?
    var lookSensitivity: CGFloat = 0.0052
    var joystickScale: CGFloat = 1
    var onFireDown: (() -> Void)?
    var promptLabel = UILabel()
    /// Extra hit-test exclusion rects (other HUD controls) in this view's coordinates.
    var reservedRects: [CGRect] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        addSubview(joystick)
        for k in ActionKind.allCases {
            let b = ActionButtonView(kind: k)
            buttons[k] = b
            addSubview(b)
        }
        promptLabel.textAlignment = .right
        promptLabel.numberOfLines = 2
        promptLabel.isUserInteractionEnabled = false
        addSubview(promptLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        joystick.frame = bounds
        joystick.radius = 66 * joystickScale
        let ins = safeAreaInsets
        let W = bounds.width - max(ins.right, 12)
        let H = bounds.height - max(ins.bottom, 10)
        let s = min(1.0, bounds.height / 390)
        func place(_ k: ActionKind, _ dx: CGFloat, _ dy: CGFloat, _ r: CGFloat) {
            guard let b = buttons[k] else { return }
            let rr = r * s
            b.radius = rr
            b.frame = CGRect(x: W - dx * s - rr, y: H - dy * s - rr, width: rr * 2, height: rr * 2)
        }
        place(.fire, 70, 72, 46)
        place(.aim, 178, 52, 34)
        place(.jump, 56, 182, 30)
        place(.reload, 150, 150, 28)
        place(.crouch, 266, 44, 28)
        place(.run, 250, 122, 28)
        place(.interact, 140, 238, 30)
        if let ib = buttons[.interact] {
            promptLabel.frame = CGRect(x: ib.frame.minX - 230, y: ib.frame.midY - 22, width: 222, height: 44)
        }
    }

    func setPrompt(_ text: String?) {
        if let t = text {
            promptLabel.attributedText = Theme.tracked(t.uppercased(), size: 12, weight: .bold, color: Theme.text, kern: 1.2)
            buttons[.interact]?.isDimmed = false
        } else {
            promptLabel.attributedText = nil
            buttons[.interact]?.isDimmed = true
        }
    }

    func syncToggles() {
        buttons[.aim]?.isActive = input.aimToggled
        buttons[.crouch]?.isActive = input.crouchToggled
        buttons[.run]?.isActive = input.sprintToggled
    }

    private func buttonAt(_ p: CGPoint) -> ActionKind? {
        var best: ActionKind?
        var bestD = CGFloat.greatestFiniteMagnitude
        for (k, b) in buttons where !b.isHidden {
            let c = CGPoint(x: b.frame.midX, y: b.frame.midY)
            let d = hypot(p.x - c.x, p.y - c.y)
            if d < b.frame.width * 0.5 + 10 && d < bestD {
                best = k
                bestD = d
            }
        }
        return best
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        for r in reservedRects where r.contains(point) { return false }
        return super.point(inside: point, with: event)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let id = ObjectIdentifier(t)
            let p = t.location(in: self)
            if let k = buttonAt(p) {
                assignments[id] = .button(k)
                lastLook[id] = p
                press(k, down: true)
            } else if p.x < bounds.width * 0.42 && joyTouch == nil {
                assignments[id] = .joystick
                joyTouch = id
                let r = 66 * joystickScale
                joyCenter = CGPoint(x: max(p.x, r + 8), y: min(max(p.y, r + 8), bounds.height - r - 8))
                joystick.show(at: joyCenter)
                updateJoystick(p)
            } else {
                assignments[id] = .look
                lastLook[id] = p
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let id = ObjectIdentifier(t)
            let p = t.location(in: self)
            guard let a = assignments[id] else { continue }
            switch a {
            case .joystick:
                updateJoystick(p)
            case .look, .button(.fire), .button(.aim):
                if let last = lastLook[id] {
                    let dx = p.x - last.x, dy = p.y - last.y
                    input.look.x += Float(dx * lookSensitivity)
                    input.look.y -= Float(dy * lookSensitivity)
                }
                lastLook[id] = p
            default:
                break
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        release(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        release(touches)
    }

    private func release(_ touches: Set<UITouch>) {
        for t in touches {
            let id = ObjectIdentifier(t)
            if let a = assignments[id] {
                switch a {
                case .joystick:
                    joyTouch = nil
                    input.move = Vec2(0, 0)
                    joystick.hide()
                case .button(let k):
                    press(k, down: false)
                case .look:
                    break
                }
            }
            assignments.removeValue(forKey: id)
            lastLook.removeValue(forKey: id)
        }
    }

    /// Releases every active touch (e.g. when an overlay opens).
    func resetAll() {
        assignments.removeAll()
        lastLook.removeAll()
        joyTouch = nil
        input.move = Vec2(0, 0)
        input.fireHeld = false
        joystick.hide()
        for b in buttons.values { b.isPressed = false }
    }

    private func updateJoystick(_ p: CGPoint) {
        let r = 66 * joystickScale
        var dx = p.x - joyCenter.x, dy = p.y - joyCenter.y
        let d = hypot(dx, dy)
        if d > r {
            dx = dx / d * r
            dy = dy / d * r
        }
        joystick.moveKnob(to: CGPoint(x: joyCenter.x + dx, y: joyCenter.y + dy))
        input.move = Vec2(Float(dx / r), Float(-dy / r))
    }

    private func press(_ k: ActionKind, down: Bool) {
        buttons[k]?.isPressed = down
        if down { Haptics.tap() }
        switch k {
        case .fire:
            input.fireHeld = down
            if down {
                input.firePressed = true
                onFireDown?()
            }
        case .aim:
            if down { input.aimToggled.toggle() }
        case .crouch:
            if down { input.crouchToggled.toggle() }
        case .run:
            if down {
                input.sprintToggled.toggle()
                if input.sprintToggled { input.crouchToggled = false }
            }
        case .jump:
            if down { input.jumpPressed = true }
        case .reload:
            if down { input.reloadPressed = true }
        case .interact:
            if down { input.interactPressed = true }
        }
        syncToggles()
    }

    /// Hands the accumulated input to the game and clears edge triggers locally.
    func collect() -> InputState {
        let out = input
        input.look = Vec2(0, 0)
        input.jumpPressed = false
        input.reloadPressed = false
        input.interactPressed = false
        input.firePressed = false
        input.fireModePressed = false
        input.cameraTogglePressed = false
        input.quickSlotPressed = nil
        input.holsterPressed = false
        return out
    }
}
