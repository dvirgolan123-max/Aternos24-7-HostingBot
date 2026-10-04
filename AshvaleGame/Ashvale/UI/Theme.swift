//
//  Theme.swift
//  Ashvale
//
//  Visual style helpers for the UIKit menus and HUD.
//

import UIKit

enum Theme {
    static let accent = UIColor(red: 0.86, green: 0.62, blue: 0.24, alpha: 1)
    static let accentDim = UIColor(red: 0.86, green: 0.62, blue: 0.24, alpha: 0.45)
    static let danger = UIColor(red: 0.85, green: 0.2, blue: 0.16, alpha: 1)
    static let good = UIColor(red: 0.45, green: 0.78, blue: 0.4, alpha: 1)
    static let text = UIColor(white: 0.92, alpha: 1)
    static let textDim = UIColor(white: 0.62, alpha: 1)
    static let panel = UIColor(red: 0.05, green: 0.06, blue: 0.06, alpha: 0.78)
    static let panelLight = UIColor(red: 0.12, green: 0.13, blue: 0.13, alpha: 0.85)
    static let border = UIColor(white: 1, alpha: 0.14)

    static func font(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: UIFont.Weight = .medium) -> UIFont {
        UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    static func tracked(_ s: String, size: CGFloat, weight: UIFont.Weight = .semibold, color: UIColor = Theme.text, kern: CGFloat = 2) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: font(size, weight), .foregroundColor: color, .kern: kern])
    }

    static func label(_ text: String, size: CGFloat, weight: UIFont.Weight = .regular, color: UIColor = Theme.text, align: NSTextAlignment = .left) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = font(size, weight)
        l.textColor = color
        l.textAlignment = align
        l.numberOfLines = 0
        return l
    }

    /// Soft dark glow behind HUD text so it stays readable over bright sky and snow.
    static func textShadow(_ v: UIView) {
        v.layer.shadowColor = UIColor.black.cgColor
        v.layer.shadowOpacity = 0.75
        v.layer.shadowRadius = 2
        v.layer.shadowOffset = CGSize(width: 0, height: 1)
    }

    static func stylePanel(_ v: UIView, radius: CGFloat = 10) {
        v.backgroundColor = panel
        v.layer.cornerRadius = radius
        v.layer.borderWidth = 1
        v.layer.borderColor = border.cgColor
    }
}

/// Large menu button with tracked uppercase title and an accent bar when highlighted.
final class MenuButton: UIControl {
    let titleLabel = UILabel()
    let subtitleLabel = UILabel()
    private let bar = UIView()
    var action: (() -> Void)?
    private var title: String

    init(title: String, subtitle: String? = nil, size: CGFloat = 20) {
        self.title = title
        super.init(frame: .zero)
        titleLabel.attributedText = Theme.tracked(title, size: size, weight: .bold, color: Theme.text, kern: 3)
        addSubview(titleLabel)
        subtitleLabel.font = Theme.font(11, .medium)
        subtitleLabel.textColor = Theme.textDim
        subtitleLabel.text = subtitle
        addSubview(subtitleLabel)
        bar.backgroundColor = Theme.accent
        bar.alpha = 0
        addSubview(bar)
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        addTarget(self, action: #selector(down), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(up), for: [.touchUpOutside, .touchCancel, .touchDragExit, .touchUpInside])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isEnabled: Bool {
        didSet { alpha = isEnabled ? 1 : 0.35 }
    }

    func setTitle(_ t: String, size: CGFloat = 20) {
        title = t
        titleLabel.attributedText = Theme.tracked(t, size: size, weight: .bold, color: Theme.text, kern: 3)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let hasSub = !(subtitleLabel.text ?? "").isEmpty
        bar.frame = CGRect(x: 0, y: 6, width: 3, height: bounds.height - 12)
        titleLabel.frame = CGRect(x: 14, y: hasSub ? 2 : 0, width: bounds.width - 14, height: hasSub ? bounds.height * 0.6 : bounds.height)
        subtitleLabel.frame = CGRect(x: 14, y: bounds.height * 0.58, width: bounds.width - 14, height: bounds.height * 0.4)
    }

    @objc private func down() {
        UIView.animate(withDuration: 0.1) {
            self.bar.alpha = 1
            self.transform = CGAffineTransform(translationX: 6, y: 0)
        }
    }

    @objc private func up() {
        UIView.animate(withDuration: 0.2) {
            self.bar.alpha = 0
            self.transform = .identity
        }
    }

    @objc private func tapped() {
        Haptics.tap()
        action?()
    }
}

/// Compact rounded button used in panels.
final class PillButton: UIControl {
    let label = UILabel()
    var action: (() -> Void)?
    var selectedStyle = false { didSet { refresh() } }

    init(_ title: String, size: CGFloat = 13) {
        super.init(frame: .zero)
        label.attributedText = Theme.tracked(title, size: size, weight: .bold, kern: 1.5)
        label.textAlignment = .center
        addSubview(label)
        layer.cornerRadius = 8
        layer.borderWidth = 1
        refresh()
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setTitle(_ t: String, size: CGFloat = 13) {
        label.attributedText = Theme.tracked(t, size: size, weight: .bold, kern: 1.5)
    }

    private func refresh() {
        backgroundColor = selectedStyle ? Theme.accent.withAlphaComponent(0.85) : Theme.panelLight
        layer.borderColor = (selectedStyle ? Theme.accent : Theme.border).cgColor
    }

    override var isEnabled: Bool { didSet { alpha = isEnabled ? 1 : 0.4 } }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 4, dy: 0)
    }

    @objc private func tapped() {
        Haptics.tap()
        action?()
    }
}

enum Haptics {
    static func tap() {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.impactOccurred()
    }

    static func heavy() {
        let g = UIImpactFeedbackGenerator(style: .heavy)
        g.impactOccurred()
    }
}
