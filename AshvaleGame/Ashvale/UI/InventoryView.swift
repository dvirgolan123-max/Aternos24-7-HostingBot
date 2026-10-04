//
//  InventoryView.swift
//  Ashvale
//
//  Grid inventory: VICINITY (items on the ground nearby), PLAYER (HEAD, FACE,
//  TORSO, VEST, LEGS, FEET, BACKPACK, SHOULDER, HANDS) and the cargo grids of
//  worn clothing. Drag and drop to move, wear, attach, load and drop items.
//

import UIKit

/// One item drawn as a tile with icon, quantity and condition.
final class ItemTileView: UIView {
    let uid: Int
    let inVicinity: Bool
    let worldID: Int?
    private let icon = UIImageView()
    private let qty = UILabel()
    private let name = UILabel()
    private let condBar = UIView()
    var selectedTile = false { didSet { refresh() } }
    let rotated: Bool

    init(item: ItemInstance, rotated: Bool, inVicinity: Bool, worldID: Int?, showName: Bool) {
        uid = item.uid
        self.inVicinity = inVicinity
        self.worldID = worldID
        self.rotated = rotated
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 1, alpha: 0.07)
        layer.cornerRadius = 4
        layer.borderWidth = 1
        icon.image = ItemIcons.shared.image(for: item)
        icon.contentMode = .scaleAspectFit
        addSubview(icon)
        qty.font = Theme.mono(9, .bold)
        qty.textColor = Theme.text
        qty.textAlignment = .right
        qty.text = item.quantityText
        addSubview(qty)
        name.font = Theme.font(8, .semibold)
        name.textColor = Theme.textDim
        name.text = showName ? item.def.name : nil
        name.numberOfLines = 1
        addSubview(name)
        let c = item.condition
        condBar.backgroundColor = c > 0.8 ? Theme.good : (c > 0.55 ? UIColor(red: 0.75, green: 0.8, blue: 0.4, alpha: 1) : (c > 0.3 ? Theme.accent : Theme.danger))
        addSubview(condBar)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func refresh() {
        layer.borderColor = (selectedTile ? Theme.accent : UIColor(white: 1, alpha: 0.18)).cgColor
        layer.borderWidth = selectedTile ? 2 : 1
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds.insetBy(dx: 2, dy: 2)
        if rotated {
            icon.transform = .identity
            icon.frame = CGRect(x: 0, y: 0, width: b.height, height: b.width)
            icon.center = CGPoint(x: bounds.midX, y: bounds.midY)
            icon.transform = CGAffineTransform(rotationAngle: .pi / 2)
        } else {
            icon.transform = .identity
            icon.frame = b
        }
        qty.frame = CGRect(x: 2, y: bounds.height - 13, width: bounds.width - 5, height: 11)
        name.frame = CGRect(x: 3, y: 1, width: bounds.width - 6, height: 10)
        condBar.frame = CGRect(x: 2, y: bounds.height - 3, width: bounds.width - 4, height: 2)
    }
}

/// Drop target describing what is under the finger.
enum DropTarget {
    case cargo(EquipSlot, Int, Int)
    case slot(EquipSlot)
    case hands
    case vicinity
    case item(Int)
    case quickSlot(Int)
}

final class InventoryView: OverlayView, UIGestureRecognizerDelegate {
    unowned let game: Game
    var onClose: (() -> Void)?

    private let topBar = UIView()
    private let titleLabel = UILabel()
    private let weightLabel = UILabel()
    private let closeButton = PillButton("CLOSE", size: 12)
    private let vicinityPanel = UIView()
    private let vicinityScroll = UIScrollView()
    private let playerPanel = UIView()
    private let cargoPanel = UIView()
    private let cargoScroll = UIScrollView()
    private let detailPanel = UIView()
    private let detailIcon = UIImageView()
    private let detailText = UILabel()
    private var actionButtons: [PillButton] = []
    private let quickBar = UIView()
    private var quickViews: [UIView] = []
    private var slotViews: [EquipSlot: UIView] = [:]
    private let handsView = UIView()
    private let statusLabel = UILabel()

    private var tiles: [ItemTileView] = []
    private var gridViews: [(EquipSlot, UIView, Container)] = []
    private var selectedUID: Int?
    private var signature = ""
    private var cell: CGFloat = 26
    private var lastSize = CGSize.zero
    private var needsContent = true

    // Dragging.
    private var dragGhost: ItemTileView?
    private var dragUID: Int?
    private var dragRotated = false
    private let dropHighlight = UIView()

    init(game: Game) {
        self.game = game
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 0, alpha: 0.82)
        for p in [vicinityPanel, playerPanel, cargoPanel, detailPanel, quickBar] {
            Theme.stylePanel(p, radius: 8)
            addSubview(p)
        }
        addSubview(topBar)
        titleLabel.attributedText = Theme.tracked("INVENTORY", size: 15, weight: .heavy, kern: 4)
        topBar.addSubview(titleLabel)
        weightLabel.font = Theme.mono(11)
        weightLabel.textColor = Theme.textDim
        topBar.addSubview(weightLabel)
        closeButton.action = { [weak self] in self?.onClose?() }
        topBar.addSubview(closeButton)
        vicinityPanel.addSubview(vicinityScroll)
        cargoPanel.addSubview(cargoScroll)
        vicinityScroll.delaysContentTouches = false
        cargoScroll.delaysContentTouches = false
        detailIcon.contentMode = .scaleAspectFit
        detailPanel.addSubview(detailIcon)
        detailText.numberOfLines = 0
        detailPanel.addSubview(detailText)
        statusLabel.numberOfLines = 0
        playerPanel.addSubview(statusLabel)
        for s in [EquipSlot.head, .face, .torso, .vest, .legs, .feet, .backpack, .shoulder] {
            let v = makeSlotView(s.title)
            slotViews[s] = v
            playerPanel.addSubview(v)
        }
        let hl = UILabel()
        hl.attributedText = Theme.tracked("HANDS", size: 8, weight: .bold, color: Theme.textDim, kern: 1.5)
        hl.tag = 77
        handsView.addSubview(hl)
        styleSlot(handsView)
        playerPanel.addSubview(handsView)
        for i in 0..<5 {
            let q = UIView()
            styleSlot(q)
            let n = UILabel()
            n.attributedText = Theme.tracked("\(i + 1)", size: 8, weight: .bold, color: Theme.textDim, kern: 0)
            n.frame = CGRect(x: 3, y: 1, width: 10, height: 10)
            q.addSubview(n)
            quickBar.addSubview(q)
            quickViews.append(q)
        }
        dropHighlight.isUserInteractionEnabled = false
        dropHighlight.layer.cornerRadius = 3
        dropHighlight.isHidden = true
        addSubview(dropHighlight)
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func styleSlot(_ v: UIView) {
        v.backgroundColor = UIColor(white: 1, alpha: 0.04)
        v.layer.cornerRadius = 6
        v.layer.borderWidth = 1
        v.layer.borderColor = UIColor(white: 1, alpha: 0.14).cgColor
    }

    private func makeSlotView(_ title: String) -> UIView {
        let v = UIView()
        styleSlot(v)
        let l = UILabel()
        l.attributedText = Theme.tracked(title, size: 7, weight: .bold, color: Theme.textDim, kern: 1)
        l.tag = 77
        v.addSubview(l)
        return v
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let ins = safeAreaInsets
        let left = max(ins.left, 10), right = bounds.width - max(ins.right, 10)
        let top = max(ins.top, 6), bottom = bounds.height - max(ins.bottom, 6)
        let W = right - left
        topBar.frame = CGRect(x: left, y: top, width: W, height: 30)
        titleLabel.frame = CGRect(x: 4, y: 4, width: 200, height: 22)
        weightLabel.frame = CGRect(x: 160, y: 4, width: W - 270, height: 22)
        closeButton.frame = CGRect(x: W - 90, y: 0, width: 90, height: 28)
        let detailH: CGFloat = 86
        let colTop = top + 34
        let colH = bottom - colTop - detailH - 6
        let vw = W * 0.24, pw = W * 0.33, cw = W - vw - pw - 12
        vicinityPanel.frame = CGRect(x: left, y: colTop, width: vw, height: colH)
        playerPanel.frame = CGRect(x: left + vw + 6, y: colTop, width: pw, height: colH)
        cargoPanel.frame = CGRect(x: left + vw + pw + 12, y: colTop, width: cw, height: colH)
        detailPanel.frame = CGRect(x: left, y: bottom - detailH, width: W * 0.68, height: detailH)
        quickBar.frame = CGRect(x: left + W * 0.68 + 6, y: bottom - detailH, width: W * 0.32 - 6, height: detailH)
        vicinityScroll.frame = vicinityPanel.bounds.insetBy(dx: 4, dy: 4).offsetBy(dx: 0, dy: 10).insetBy(dx: 0, dy: 5)
        cargoScroll.frame = cargoPanel.bounds.insetBy(dx: 4, dy: 4)
        // Player slots: two columns of slots + hands.
        let sw = (pw - 24) / 3, sh = min(46, (colH - 70) / 4)
        let order: [[EquipSlot?]] = [[.head, .face, nil], [.torso, .vest, .backpack], [.legs, .feet, .shoulder]]
        for (r, row) in order.enumerated() {
            for (c, s) in row.enumerated() {
                guard let s = s, let v = slotViews[s] else { continue }
                v.frame = CGRect(x: 6 + CGFloat(c) * (sw + 6), y: 6 + CGFloat(r) * (sh + 6), width: sw, height: sh)
                v.viewWithTag(77)?.frame = CGRect(x: 4, y: 2, width: sw, height: 9)
            }
        }
        handsView.frame = CGRect(x: 6 + 2 * (sw + 6), y: 6, width: sw, height: sh)
        handsView.viewWithTag(77)?.frame = CGRect(x: 4, y: 2, width: sw, height: 9)
        statusLabel.frame = CGRect(x: 8, y: 6 + 3 * (sh + 6), width: pw - 16, height: colH - (6 + 3 * (sh + 6)) - 4)
        let qw = (quickBar.bounds.width - 12 - 4 * 4) / 5
        for (i, q) in quickViews.enumerated() {
            q.frame = CGRect(x: 6 + CGFloat(i) * (qw + 4), y: 22, width: qw, height: min(qw, detailH - 30))
        }
        detailIcon.frame = CGRect(x: 8, y: 8, width: 70, height: 70)
        detailText.frame = CGRect(x: 86, y: 4, width: detailPanel.bounds.width * 0.48, height: detailH - 8)
        layoutActions()
        if bounds.size != lastSize {
            lastSize = bounds.size
            needsContent = true
        }
        if needsContent {
            needsContent = false
            layoutContents()
        }
    }

    private func layoutActions() {
        let x0 = 86 + detailPanel.bounds.width * 0.48 + 6
        let w = detailPanel.bounds.width - x0 - 8
        let bw = (w - 6) / 2
        for (i, b) in actionButtons.enumerated() {
            let col = i % 2, row = i / 2
            b.frame = CGRect(x: x0 + CGFloat(col) * (bw + 6), y: 6 + CGFloat(row) * 26, width: bw, height: 22)
        }
    }

    // MARK: Building

    private func computeSignature() -> String {
        var s = ""
        let e = game.equipment
        if let h = e.hands { s += "h\(h.uid):\(h.quantityText ?? "")\(h.attachments.count)\(h.magazine?.uid ?? 0);" }
        for (k, v) in e.slots.sorted(by: { $0.key < $1.key }) { s += "s\(k):\(v.uid)\(v.quantityText ?? "")\(v.attachments.count)\(v.magazine?.uid ?? 0);" }
        for (_, _, c) in e.containers {
            for en in c.entries { s += "c\(en.item.uid),\(en.x),\(en.y),\(en.rotated),\(en.item.quantityText ?? "")\(en.item.opened);" }
        }
        for w in game.vicinityItems() { s += "v\(w.id);" }
        s += "q\(e.quickSlots.map { "\($0 ?? 0)" }.joined(separator: ","))"
        s += "a\(game.action?.label ?? "")"
        return s
    }

    private var refreshTick = 0

    /// Called every frame while open; checks for changes a few times per second.
    func refreshIfNeeded() {
        if dragUID != nil { return }
        refreshTick += 1
        if refreshTick % 8 != 0 { return }
        let sig = computeSignature()
        if sig != signature {
            rebuild()
        }
        updateStatus()
    }

    private func rebuild() {
        signature = computeSignature()
        for t in tiles { t.removeFromSuperview() }
        tiles.removeAll()
        for g in gridViews { g.1.removeFromSuperview() }
        gridViews.removeAll()
        cargoScroll.subviews.forEach { $0.removeFromSuperview() }
        vicinityScroll.subviews.forEach { $0.removeFromSuperview() }
        needsContent = true
        setNeedsLayout()
        layoutIfNeeded()
        updateDetail()
        updateStatus()
    }

    private func layoutContents() {
        guard cargoScroll.bounds.width > 0 else { return }
        for t in tiles { t.removeFromSuperview() }
        tiles.removeAll()
        cargoScroll.subviews.forEach { $0.removeFromSuperview() }
        vicinityScroll.subviews.forEach { $0.removeFromSuperview() }
        gridViews.removeAll()
        let e = game.equipment

        // Equipment slots.
        for (s, v) in slotViews {
            v.subviews.filter { $0 is ItemTileView }.forEach { $0.removeFromSuperview() }
            if let it = e.item(s) {
                let t = makeTile(it, rotated: false, vicinity: false, worldID: nil, showName: false)
                t.frame = v.bounds.insetBy(dx: 3, dy: 3).offsetBy(dx: 0, dy: 4).insetBy(dx: 0, dy: 2)
                v.addSubview(t)
            }
        }
        handsView.subviews.filter { $0 is ItemTileView }.forEach { $0.removeFromSuperview() }
        if let h = e.hands {
            let t = makeTile(h, rotated: false, vicinity: false, worldID: nil, showName: false)
            t.frame = handsView.bounds.insetBy(dx: 3, dy: 3).offsetBy(dx: 0, dy: 4).insetBy(dx: 0, dy: 2)
            handsView.addSubview(t)
        }
        // Quick slots.
        for (i, q) in quickViews.enumerated() {
            q.subviews.filter { $0 is UIImageView }.forEach { $0.removeFromSuperview() }
            if let uid = e.quickSlots[i], let it = e.find(uid: uid) {
                let img = UIImageView(image: ItemIcons.shared.image(for: it))
                img.contentMode = .scaleAspectFit
                img.frame = q.bounds.insetBy(dx: 4, dy: 6)
                q.addSubview(img)
            }
        }

        // Cargo grids.
        let maxW = e.containers.map { $0.2.width }.max() ?? 4
        cell = min(30, max(20, floor((cargoScroll.bounds.width - 12) / CGFloat(max(maxW, 4)))))
        var y: CGFloat = 4
        for (slot, holder, c) in e.containers {
            let header = UILabel()
            header.attributedText = Theme.tracked("\(holder.def.name.uppercased())  ·  \(c.width)×\(c.height)", size: 9, weight: .bold, color: Theme.accent, kern: 1.5)
            header.frame = CGRect(x: 4, y: y, width: cargoScroll.bounds.width - 8, height: 14)
            cargoScroll.addSubview(header)
            y += 16
            let grid = GridBackgroundView(cols: c.width, rows: c.height, cell: cell)
            grid.frame = CGRect(x: 4, y: y, width: CGFloat(c.width) * cell, height: CGFloat(c.height) * cell)
            cargoScroll.addSubview(grid)
            gridViews.append((slot, grid, c))
            for en in c.entries {
                let t = makeTile(en.item, rotated: en.rotated, vicinity: false, worldID: nil, showName: false)
                t.frame = CGRect(x: grid.frame.minX + CGFloat(en.x) * cell + 1, y: grid.frame.minY + CGFloat(en.y) * cell + 1,
                                 width: CGFloat(en.w) * cell - 2, height: CGFloat(en.h) * cell - 2)
                cargoScroll.addSubview(t)
            }
            y += CGFloat(c.height) * cell + 10
        }
        if e.containers.isEmpty {
            let l = Theme.label("Wear clothing with pockets, a vest or a backpack to carry items.", size: 11, color: Theme.textDim)
            l.frame = CGRect(x: 6, y: 6, width: cargoScroll.bounds.width - 12, height: 60)
            cargoScroll.addSubview(l)
        }
        cargoScroll.contentSize = CGSize(width: cargoScroll.bounds.width, height: y)

        // Vicinity list.
        let vh = UILabel()
        vh.attributedText = Theme.tracked("VICINITY", size: 9, weight: .bold, color: Theme.accent, kern: 2)
        vh.frame = CGRect(x: 4, y: 0, width: 200, height: 12)
        vicinityScroll.addSubview(vh)
        var vy: CGFloat = 16
        let tw = vicinityScroll.bounds.width - 4
        for w in game.vicinityItems() {
            let t = makeTile(w.item, rotated: false, vicinity: true, worldID: w.id, showName: true)
            t.frame = CGRect(x: 2, y: vy, width: tw, height: 40)
            vicinityScroll.addSubview(t)
            vy += 44
        }
        if game.vicinityItems().isEmpty {
            let l = Theme.label("Nothing within reach.\nDrag items here to drop them.", size: 10, color: Theme.textDim)
            l.frame = CGRect(x: 4, y: 18, width: tw, height: 40)
            vicinityScroll.addSubview(l)
        }
        vicinityScroll.contentSize = CGSize(width: vicinityScroll.bounds.width, height: vy + 4)
        for t in tiles { t.selectedTile = t.uid == selectedUID }
    }

    private func makeTile(_ it: ItemInstance, rotated: Bool, vicinity: Bool, worldID: Int?, showName: Bool) -> ItemTileView {
        let t = ItemTileView(item: it, rotated: rotated, inVicinity: vicinity, worldID: worldID, showName: showName)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tileTapped(_:)))
        t.addGestureRecognizer(tap)
        let drag = UILongPressGestureRecognizer(target: self, action: #selector(tileDragged(_:)))
        drag.minimumPressDuration = 0.18
        drag.allowableMovement = 10_000
        t.addGestureRecognizer(drag)
        let dbl = UITapGestureRecognizer(target: self, action: #selector(tileDoubleTapped(_:)))
        dbl.numberOfTapsRequired = 2
        t.addGestureRecognizer(dbl)
        tap.require(toFail: dbl)
        tiles.append(t)
        return t
    }

    // MARK: Status & details

    private func updateStatus() {
        let s = game.stats
        let w = game.equipment.totalWeight
        weightLabel.text = String(format: "WEIGHT %.1f kg   ·   %@", w, game.action?.label.uppercased() ?? "")
        var lines: [String] = []
        lines.append(String(format: "Health %.0f%%   Blood %.0f ml", s.health, s.blood))
        lines.append(String(format: "Energy %.0f kcal   Water %.0f ml", s.energy, s.water))
        lines.append(String(format: "Body %.1f°C   Wet %.0f%%", s.bodyTemp, s.wetness * 100))
        var cond: [String] = []
        if s.isBleeding { cond.append("Bleeding ×\(s.bleeds.count)") }
        if s.brokenLeg { cond.append(s.splinted ? "Leg splinted" : "Broken leg") }
        if s.woundInfection > 0.05 { cond.append("Wound infection") }
        if s.foodPoisoning > 0.05 { cond.append("Food poisoning") }
        if s.cold > 0.1 { cond.append("Cold") }
        if s.infectionRisk > 0.2 { cond.append("Dirty wound") }
        if !cond.isEmpty { lines.append(cond.joined(separator: " · ")) }
        let ins = game.clothingInsulation()
        lines.append(String(format: "Insulation %.0f%%   Waterproof %.0f%%", min(1, ins.0 / 1.4) * 100, ins.1 * 100))
        let txt = NSAttributedString(string: lines.joined(separator: "\n"), attributes: [.font: Theme.mono(10, .medium), .foregroundColor: Theme.textDim])
        statusLabel.attributedText = txt
    }

    private func updateDetail() {
        for b in actionButtons { b.removeFromSuperview() }
        actionButtons.removeAll()
        guard let uid = selectedUID, let it = game.findItem(uid: uid) else {
            detailIcon.image = nil
            detailText.attributedText = NSAttributedString(string: "Tap an item to inspect it. Long-press and drag to move it: onto a grid, a slot, HANDS, another item (load, attach, combine), a quick slot, or VICINITY to drop it.",
                                                           attributes: [.font: Theme.font(11, .medium), .foregroundColor: Theme.textDim])
            return
        }
        let d = it.def
        detailIcon.image = ItemIcons.shared.image(for: it)
        let s = NSMutableAttributedString(attributedString: Theme.tracked(d.name.uppercased() + "\n", size: 12, weight: .bold, kern: 1.2))
        var info = "\(it.conditionLevel.name)  ·  \(String(format: "%.2f", it.weight)) kg"
        if let q = it.quantityText { info += "  ·  \(q)" }
        if let w = d.weapon, d.isFirearm {
            let mode = w.modes[min(it.fireModeIndex, w.modes.count - 1)].name
            info += "  ·  \(w.caliber?.name ?? "")  ·  \(mode)\(it.chambered ? "  ·  chambered" : "")"
        }
        if let c = d.clothing {
            info += "  ·  \(c.slot.title)"
            if c.armor > 0 { info += "  ·  armor \(Int(c.armor * 100))%" }
            if let cg = c.cargo { info += "  ·  \(cg.w)×\(cg.h) slots" }
        }
        if it.dirty { info += "  ·  untreated water" }
        if d.food?.needsOpening == true { info += it.opened ? "  ·  opened" : "  ·  sealed" }
        s.append(NSAttributedString(string: info + "\n", attributes: [.font: Theme.font(10, .semibold), .foregroundColor: Theme.accent]))
        s.append(NSAttributedString(string: d.desc, attributes: [.font: Theme.font(10, .medium), .foregroundColor: Theme.text]))
        detailText.attributedText = s
        let inVicinity = game.worldItem(uid: uid) != nil
        for a in game.actions(for: it, inVicinity: inVicinity).prefix(6) {
            let b = PillButton(a.title, size: 9)
            b.action = { [weak self] in
                a.perform()
                self?.rebuild()
            }
            detailPanel.addSubview(b)
            actionButtons.append(b)
        }
        layoutActions()
    }

    @objc private func tileTapped(_ g: UITapGestureRecognizer) {
        guard let t = g.view as? ItemTileView else { return }
        selectedUID = t.uid
        for x in tiles { x.selectedTile = x.uid == t.uid }
        updateDetail()
        Haptics.tap()
    }

    @objc private func tileDoubleTapped(_ g: UITapGestureRecognizer) {
        guard let t = g.view as? ItemTileView else { return }
        // Quick default action: take from the ground, use consumables, wear clothing, otherwise to hands.
        if let wid = t.worldID {
            game.pickUp(worldItemID: wid)
        } else if let it = game.findItem(uid: t.uid) {
            let d = it.def
            if d.food != nil || d.medical != nil {
                game.useItem(uid: t.uid)
            } else if let c = d.clothing, game.equipment.item(c.slot)?.uid != it.uid {
                game.equip(uid: t.uid, to: c.slot)
            } else if game.equipment.hands?.uid == it.uid {
                game.holsterHands()
            } else {
                game.toHands(uid: t.uid)
            }
        }
        rebuild()
    }

    // MARK: Drag & drop

    @objc private func tileDragged(_ g: UILongPressGestureRecognizer) {
        let p = g.location(in: self)
        switch g.state {
        case .began:
            guard let t = g.view as? ItemTileView, let it = game.findItem(uid: t.uid) else { return }
            dragUID = t.uid
            dragRotated = t.rotated
            let size = CGSize(width: max(36, t.bounds.width), height: max(36, t.bounds.height))
            let ghost = ItemTileView(item: it, rotated: t.rotated, inVicinity: false, worldID: nil, showName: false)
            ghost.frame = CGRect(origin: .zero, size: size)
            ghost.alpha = 0.85
            ghost.center = p
            ghost.isUserInteractionEnabled = false
            addSubview(ghost)
            dragGhost = ghost
            selectedUID = t.uid
            updateDetail()
            Haptics.tap()
        case .changed:
            dragGhost?.center = p
            updateDropHighlight(at: p)
        case .ended:
            if let uid = dragUID { performDrop(uid: uid, at: p) }
            endDrag()
        default:
            endDrag()
        }
    }

    private func endDrag() {
        dragGhost?.removeFromSuperview()
        dragGhost = nil
        dragUID = nil
        dropHighlight.isHidden = true
    }

    /// Rotates the dragged item (tap with a second finger while dragging).
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        if dragUID != nil, let g = dragGhost {
            dragRotated.toggle()
            let c = g.center
            g.bounds = CGRect(x: 0, y: 0, width: g.bounds.height, height: g.bounds.width)
            g.center = c
        }
    }

    private func target(at p: CGPoint) -> DropTarget? {
        // Quick slots.
        for (i, q) in quickViews.enumerated() where q.convert(q.bounds, to: self).contains(p) { return .quickSlot(i) }
        // Hands and slots.
        if handsView.convert(handsView.bounds, to: self).contains(p) {
            if let h = game.equipment.hands, h.uid != dragUID { return .item(h.uid) }
            return .hands
        }
        for (s, v) in slotViews where v.convert(v.bounds, to: self).contains(p) {
            if let it = game.equipment.item(s), it.uid != dragUID, let d = dragUID, let dragged = game.findItem(uid: d),
               !game.canEquip(dragged, to: s) {
                return .item(it.uid)
            }
            return .slot(s)
        }
        if vicinityPanel.convert(vicinityPanel.bounds, to: self).contains(p) { return .vicinity }
        // Items in grids (combine) — checked before empty cells.
        for t in tiles where t.uid != dragUID && t.worldID == nil && t.superview === cargoScroll {
            if t.convert(t.bounds, to: self).contains(p) {
                if let d = dragUID, let dragged = game.findItem(uid: d), let target = game.findItem(uid: t.uid),
                   dragged.defID != target.defID || dragged.def.isStackable {
                    // Same non-stackable item type: treat as placement instead of combine.
                    return .item(t.uid)
                }
            }
        }
        for (slot, grid, c) in gridViews {
            let r = grid.convert(grid.bounds, to: self)
            if r.contains(p), let d = dragUID, let it = game.findItem(uid: d) {
                let w = dragRotated ? it.def.size.h : it.def.size.w
                let h = dragRotated ? it.def.size.w : it.def.size.h
                let lx = p.x - r.minX - CGFloat(w - 1) * cell * 0.5
                let ly = p.y - r.minY - CGFloat(h - 1) * cell * 0.5
                let cx = max(0, min(c.width - 1, Int(lx / cell)))
                let cy = max(0, min(c.height - 1, Int(ly / cell)))
                return .cargo(slot, cx, cy)
            }
        }
        return nil
    }

    private func updateDropHighlight(at p: CGPoint) {
        guard let t = target(at: p), let uid = dragUID, let it = game.findItem(uid: uid) else {
            dropHighlight.isHidden = true
            return
        }
        dropHighlight.isHidden = false
        var rect = CGRect.zero
        var ok = true
        switch t {
        case .cargo(let slot, let x, let y):
            if let g = gridViews.first(where: { $0.0 == slot }) {
                let r = g.1.convert(g.1.bounds, to: self)
                let w = dragRotated ? it.def.size.h : it.def.size.w
                let h = dragRotated ? it.def.size.w : it.def.size.h
                rect = CGRect(x: r.minX + CGFloat(x) * cell, y: r.minY + CGFloat(y) * cell, width: CGFloat(w) * cell, height: CGFloat(h) * cell)
                ok = g.2.canPlace(it, x: x, y: y, rotated: dragRotated)
            }
        case .slot(let s):
            if let v = slotViews[s] { rect = v.convert(v.bounds, to: self) }
            ok = game.canEquip(it, to: s)
        case .hands:
            rect = handsView.convert(handsView.bounds, to: self)
        case .vicinity:
            rect = vicinityPanel.convert(vicinityPanel.bounds, to: self)
        case .item(let tu):
            if let tv = tiles.first(where: { $0.uid == tu }) { rect = tv.convert(tv.bounds, to: self) } else if let h = game.equipment.hands, h.uid == tu {
                rect = handsView.convert(handsView.bounds, to: self)
            }
        case .quickSlot(let i):
            rect = quickViews[i].convert(quickViews[i].bounds, to: self)
        }
        dropHighlight.frame = rect
        dropHighlight.backgroundColor = (ok ? Theme.good : Theme.danger).withAlphaComponent(0.28)
        dropHighlight.layer.borderWidth = 1.5
        dropHighlight.layer.borderColor = (ok ? Theme.good : Theme.danger).cgColor
        bringSubviewToFront(dropHighlight)
        if let g = dragGhost { bringSubviewToFront(g) }
    }

    private func performDrop(uid: Int, at p: CGPoint) {
        guard let t = target(at: p) else { return }
        var ok = false
        switch t {
        case .cargo(let slot, let x, let y):
            ok = game.placeInCargo(uid: uid, slot: slot, x: x, y: y, rotated: dragRotated)
            if !ok { ok = game.placeInCargo(uid: uid, slot: slot, x: x, y: y, rotated: !dragRotated) }
            if !ok { game.message("Doesn't fit there") }
        case .slot(let s):
            ok = game.equip(uid: uid, to: s)
            if !ok { game.message("Can't wear that there") }
        case .hands:
            ok = game.toHands(uid: uid)
        case .vicinity:
            if game.worldItem(uid: uid) == nil {
                game.dropItem(uid: uid)
                ok = true
            }
        case .item(let target):
            ok = game.combine(uid: uid, onto: target)
        case .quickSlot(let i):
            if game.isCarried(uid: uid) {
                game.assignQuickSlot(i, uid: uid)
                ok = true
            } else {
                game.message("Pick the item up first")
            }
        }
        if ok { Haptics.tap() }
        rebuild()
    }
}

/// Draws the empty cells of a cargo grid.
final class GridBackgroundView: UIView {
    let cols: Int, rows: Int, cell: CGFloat

    init(cols: Int, rows: Int, cell: CGFloat) {
        self.cols = cols
        self.rows = rows
        self.cell = cell
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = UIColor(white: 1, alpha: 0.03)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        let path = UIBezierPath()
        for c in 0...cols {
            path.move(to: CGPoint(x: CGFloat(c) * cell, y: 0))
            path.addLine(to: CGPoint(x: CGFloat(c) * cell, y: CGFloat(rows) * cell))
        }
        for r in 0...rows {
            path.move(to: CGPoint(x: 0, y: CGFloat(r) * cell))
            path.addLine(to: CGPoint(x: CGFloat(cols) * cell, y: CGFloat(r) * cell))
        }
        path.lineWidth = 0.5
        UIColor(white: 1, alpha: 0.12).setStroke()
        path.stroke()
    }
}
