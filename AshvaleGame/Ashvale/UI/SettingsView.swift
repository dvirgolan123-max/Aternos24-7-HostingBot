//
//  SettingsView.swift
//  Ashvale
//
//  Settings screen (graphics, controls, gameplay, audio). Changes are saved
//  immediately and applied live through `onChange`.
//

import UIKit

final class SettingsView: OverlayView {
    var onBack: (() -> Void)?
    var onChange: (() -> Void)?
    private let panel = UIView()
    private let header = UILabel()
    private let scroll = UIScrollView()
    private let back = PillButton("DONE", size: 13)
    private var rows: [UIView] = []
    private let s = GameSettings.shared

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0, alpha: 0.6)
        Theme.stylePanel(panel, radius: 12)
        addSubview(panel)
        header.attributedText = Theme.tracked("SETTINGS", size: 18, weight: .heavy, kern: 5)
        panel.addSubview(header)
        scroll.showsVerticalScrollIndicator = true
        scroll.delaysContentTouches = false
        panel.addSubview(scroll)
        back.selectedStyle = true
        back.action = { [weak self] in self?.onBack?() }
        panel.addSubview(back)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func section(_ title: String) {
        let l = UILabel()
        l.attributedText = Theme.tracked(title, size: 10, weight: .bold, color: Theme.accent, kern: 3)
        scroll.addSubview(l)
        rows.append(l)
    }

    private func rowLabel(_ title: String) -> UILabel {
        let l = UILabel()
        l.text = title
        l.font = Theme.font(13, .medium)
        l.textColor = Theme.text
        return l
    }

    private func segmented(_ title: String, _ items: [String], selected: Int, _ onSelect: @escaping (Int) -> Void) {
        let row = UIView()
        let l = rowLabel(title)
        l.tag = 1
        row.addSubview(l)
        let seg = UISegmentedControl(items: items)
        seg.tag = 2
        seg.selectedSegmentIndex = selected
        seg.selectedSegmentTintColor = Theme.accent
        seg.setTitleTextAttributes([.foregroundColor: UIColor.white, .font: Theme.font(11, .bold)], for: .normal)
        seg.addAction(UIAction { [weak seg] _ in onSelect(seg?.selectedSegmentIndex ?? 0) }, for: .valueChanged)
        row.addSubview(seg)
        scroll.addSubview(row)
        rows.append(row)
    }

    private func slider(_ title: String, min: Float, max: Float, value: Float, format: @escaping (Float) -> String, _ onChange: @escaping (Float) -> Void) {
        let row = UIView()
        let l = rowLabel(title)
        l.tag = 1
        row.addSubview(l)
        let sl = UISlider()
        sl.tag = 2
        sl.minimumValue = min
        sl.maximumValue = max
        sl.value = value
        sl.minimumTrackTintColor = Theme.accent
        row.addSubview(sl)
        let v = UILabel()
        v.tag = 3
        v.font = Theme.mono(12)
        v.textColor = Theme.textDim
        v.textAlignment = .right
        v.text = format(value)
        row.addSubview(v)
        sl.addAction(UIAction { [weak sl, weak v] _ in
            guard let sl = sl else { return }
            v?.text = format(sl.value)
            onChange(sl.value)
        }, for: .valueChanged)
        scroll.addSubview(row)
        rows.append(row)
    }

    private func toggle(_ title: String, value: Bool, _ onChange: @escaping (Bool) -> Void) {
        let row = UIView()
        let l = rowLabel(title)
        l.tag = 1
        row.addSubview(l)
        let sw = UISwitch()
        sw.tag = 2
        sw.isOn = value
        sw.onTintColor = Theme.accent
        sw.addAction(UIAction { [weak sw] _ in onChange(sw?.isOn ?? false) }, for: .valueChanged)
        row.addSubview(sw)
        scroll.addSubview(row)
        rows.append(row)
    }

    private func build() {
        section("GRAPHICS")
        segmented("Quality", QualityLevel.allCases.map { $0.name }, selected: s.quality.rawValue) { [weak self] i in
            self?.s.quality = QualityLevel(rawValue: i) ?? .medium
            self?.onChange?()
        }
        toggle("Show FPS counter", value: s.showFPS) { [weak self] v in
            self?.s.showFPS = v
            self?.onChange?()
        }
        slider("Field of view", min: 55, max: 90, value: s.fieldOfView, format: { "\(Int($0))°" }) { [weak self] v in
            self?.s.fieldOfView = v
            self?.onChange?()
        }
        section("CONTROLS")
        slider("Look sensitivity", min: 0.3, max: 2.5, value: s.lookSensitivity, format: { String(format: "%.2f", $0) }) { [weak self] v in
            self?.s.lookSensitivity = v
            self?.onChange?()
        }
        slider("Aim sensitivity", min: 0.2, max: 1.5, value: s.aimSensitivity, format: { String(format: "%.2f", $0) }) { [weak self] v in
            self?.s.aimSensitivity = v
            self?.onChange?()
        }
        slider("Joystick size", min: 0.7, max: 1.4, value: s.joystickScale, format: { String(format: "%.0f%%", $0 * 100) }) { [weak self] v in
            self?.s.joystickScale = v
            self?.onChange?()
        }
        toggle("Invert look Y", value: s.invertY) { [weak self] v in
            self?.s.invertY = v
            self?.onChange?()
        }
        toggle("Start in first person", value: s.firstPersonDefault) { [weak self] v in
            self?.s.firstPersonDefault = v
            self?.onChange?()
        }
        section("GAMEPLAY")
        toggle("Crosshair (where the server allows it)", value: s.showCrosshair) { [weak self] v in
            self?.s.showCrosshair = v
            self?.onChange?()
        }
        let lengths: [Float] = [30, 60, 120]
        segmented("Day length", ["30 MIN", "60 MIN", "120 MIN"], selected: lengths.firstIndex(of: s.dayLengthMinutes) ?? 1) { [weak self] i in
            self?.s.dayLengthMinutes = lengths[i]
            self?.onChange?()
        }
        section("AUDIO")
        slider("Master volume", min: 0, max: 1, value: s.masterVolume, format: { "\(Int($0 * 100))%" }) { [weak self] v in
            self?.s.masterVolume = v
            self?.onChange?()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = min(bounds.width - 60, 600), h = min(bounds.height - 24, 360)
        panel.frame = CGRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)
        header.frame = CGRect(x: 20, y: 12, width: 300, height: 24)
        back.frame = CGRect(x: w - 16 - 100, y: 10, width: 100, height: 30)
        scroll.frame = CGRect(x: 0, y: 46, width: w, height: h - 52)
        var y: CGFloat = 4
        let cw = w - 40
        for r in rows {
            if r is UILabel {
                r.frame = CGRect(x: 20, y: y + 8, width: cw, height: 16)
                y += 28
                continue
            }
            r.frame = CGRect(x: 20, y: y, width: cw, height: 40)
            r.viewWithTag(1)?.frame = CGRect(x: 0, y: 0, width: cw * 0.45, height: 40)
            if let seg = r.viewWithTag(2) as? UISegmentedControl {
                seg.frame = CGRect(x: cw * 0.45, y: 6, width: cw * 0.55, height: 28)
            } else if let sl = r.viewWithTag(2) as? UISlider {
                sl.frame = CGRect(x: cw * 0.45, y: 5, width: cw * 0.55 - 60, height: 30)
                r.viewWithTag(3)?.frame = CGRect(x: cw - 56, y: 0, width: 56, height: 40)
            } else if let sw = r.viewWithTag(2) as? UISwitch {
                sw.frame = CGRect(x: cw - 52, y: 4, width: 51, height: 31)
            }
            y += 42
        }
        scroll.contentSize = CGSize(width: w, height: y + 10)
    }
}
