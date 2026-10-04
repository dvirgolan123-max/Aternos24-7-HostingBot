//
//  HUDBinding.swift
//  Ashvale
//
//  Pushes live game state into the HUD views each frame.
//

import UIKit

extension Game {
    func fillHUD(_ h: HUDView) {
        let s = stats
        func set(_ key: String, _ v: Float, warn: Bool, crit: Bool) {
            guard let ind = h.indicators[key] else { return }
            ind.value = v
            ind.warning = warn
            ind.critical = crit
        }
        set("health", s.health / 100, warn: s.health < 60, crit: s.health < 25)
        set("blood", (s.blood - 1800) / (SurvivorStats.maxBlood - 1800), warn: s.blood < 4200, crit: s.blood < 3000)
        set("food", s.energy / SurvivorStats.maxEnergy, warn: s.energy < 400, crit: s.energy < 120)
        set("water", s.water / SurvivorStats.maxWater, warn: s.water < 400, crit: s.water < 120)
        set("temp", saturatef((s.bodyTemp - 34) / 4), warn: s.bodyTemp < 35.8 || s.bodyTemp > 38.3, crit: s.bodyTemp < 35 || s.bodyTemp > 39.3)
        set("stamina", s.stamina / 100, warn: s.stamina < 30, crit: s.stamina < 10)

        // Conditions.
        var effects: [(String, UIColor)] = []
        if s.isBleeding { effects.append(("BLEEDING ×\(s.bleeds.count)", Theme.danger)) }
        if s.brokenLeg { effects.append((s.splinted ? "SPLINTED" : "BROKEN LEG", Theme.danger)) }
        if s.woundInfection > 0.05 { effects.append(("INFECTION", Theme.danger)) }
        if s.foodPoisoning > 0.05 { effects.append(("SICK", Theme.accent)) }
        if s.cold > 0.1 { effects.append(("COLD", Theme.accent)) }
        if s.wetness > 0.35 { effects.append(("WET", UIColor(red: 0.45, green: 0.7, blue: 1, alpha: 1))) }
        if s.bodyTemp < 35.5 { effects.append(("FREEZING", UIColor(red: 0.55, green: 0.8, blue: 1, alpha: 1))) }
        if s.pain > 0.4 && s.painkillers <= 0 && s.morphine <= 0 { effects.append(("PAIN", Theme.accent)) }
        if equipment.totalWeight > 25 { effects.append(("OVERLOADED", Theme.accent)) }
        let e = NSMutableAttributedString(string: "")
        for (i, (t, c)) in effects.enumerated() {
            e.append(Theme.tracked(t + (i < effects.count - 1 ? "   " : ""), size: 9, weight: .heavy, color: c, kern: 1.2))
        }
        h.effectsLabel.attributedText = e

        // Weapon / hands.
        let c = h.controls
        if let held = equipment.hands {
            let d = held.def
            if d.isFirearm, let w = d.weapon {
                let mode = w.modes[min(held.fireModeIndex, w.modes.count - 1)].name
                let magRounds = held.magazine?.quantity ?? held.internalRounds
                let cap = held.magazine?.def.magazine?.capacity ?? w.internalCapacity
                let magText = held.magazine == nil && w.internalCapacity == 0 ? "NO MAG" : "\(magRounds)/\(cap)"
                let t = NSMutableAttributedString(attributedString: Theme.tracked(magText, size: 20, weight: .heavy, kern: 1))
                t.append(Theme.tracked(held.chambered ? " +1" : " +0", size: 11, weight: .bold, color: held.chambered ? Theme.text : Theme.danger, kern: 0))
                t.append(Theme.tracked("\n\(d.name.uppercased())  ·  \(mode)\(weapon.jammed ? "  ·  JAMMED" : "")", size: 9, weight: .bold, color: weapon.jammed ? Theme.danger : UIColor(white: 0.88, alpha: 0.95), kern: 1.2))
                h.ammoLabel.attributedText = t
                c.buttons[.fire]?.setCaption("FIRE")
                c.buttons[.reload]?.isDimmed = false
            } else {
                h.ammoLabel.attributedText = Theme.tracked(d.name.uppercased(), size: 11, weight: .bold, color: Theme.text, kern: 1.5)
                if d.isMelee {
                    c.buttons[.fire]?.setCaption("SWING")
                } else if d.tool == .flashlight {
                    c.buttons[.fire]?.setCaption(flashlightOn ? "LIGHT OFF" : "LIGHT")
                } else {
                    c.buttons[.fire]?.setCaption("THROW")
                }
                c.buttons[.reload]?.isDimmed = true
            }
        } else {
            h.ammoLabel.attributedText = Theme.tracked("UNARMED", size: 10, weight: .bold, color: Theme.textDim, kern: 2)
            c.buttons[.fire]?.setCaption("PUNCH")
            c.buttons[.reload]?.isDimmed = true
        }
        h.cameraButton.setTitle(firstPerson ? "3P" : "1P", size: 11)

        // Quick slots.
        for i in 0..<h.quickSlots.slotCount {
            if let uid = equipment.quickSlots[i], let it = equipment.find(uid: uid) {
                h.quickSlots.iconViews[i].image = ItemIcons.shared.image(for: it)
                h.quickSlots.countLabels[i].text = it.quantityText
            } else {
                h.quickSlots.iconViews[i].image = nil
                h.quickSlots.countLabels[i].text = nil
            }
        }
        if let hu = equipment.hands?.uid {
            h.quickSlots.highlighted = equipment.quickSlots.firstIndex { $0 == hu }
        } else {
            h.quickSlots.highlighted = nil
        }

        // Timed action progress.
        if let label = hud.actionLabel {
            h.actionLabel.attributedText = Theme.tracked(label.uppercased(), size: 10, weight: .bold, color: Theme.text, kern: 1.5)
            h.actionBar.isHidden = false
            h.actionBar.progress = hud.actionProgress
        } else {
            h.actionLabel.attributedText = nil
            h.actionBar.isHidden = true
        }

        // Compass when carried.
        if equipment.firstItem(where: { $0.def.tool == .compass }) != nil {
            var deg = Int((-camYaw * 180 / kPi).rounded())
            deg = ((deg % 360) + 360) % 360
            let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
            let name = names[Int((Float(deg) + 22.5) / 45) % 8]
            h.compassLabel.attributedText = Theme.tracked("\(name)  \(deg)°", size: 11, weight: .heavy, color: Theme.text, kern: 2)
        } else {
            h.compassLabel.attributedText = nil
        }
    }
}
