//
//  ItemDefs.swift
//  Ashvale
//
//  Static definitions of every item in Ashvale: food, drinks, medicine,
//  clothing, backpacks, vests, firearms, magazines, ammunition, attachments,
//  melee weapons and tools. All names and items are original.
//

import Foundation

enum ItemCategory: Int, Codable {
    case food, drink, medical, clothing, firearm, melee, ammo, magazine, attachment, tool, misc
}

enum EquipSlot: Int, Codable, CaseIterable {
    case head, face, torso, vest, legs, feet, backpack, shoulder

    var title: String {
        switch self {
        case .head: return "HEAD"
        case .face: return "FACE"
        case .torso: return "TORSO"
        case .vest: return "VEST"
        case .legs: return "LEGS"
        case .feet: return "FEET"
        case .backpack: return "BACKPACK"
        case .shoulder: return "SHOULDER"
        }
    }
}

enum Caliber: Int, Codable {
    case nine, fortyFive, fiveFiveSix, sevenSixTwoShort, sevenSixTwoLong, twelveGauge

    var name: String {
        switch self {
        case .nine: return "9×19mm"
        case .fortyFive: return ".45 ACP"
        case .fiveFiveSix: return "5.56×45mm"
        case .sevenSixTwoShort: return "7.62×39mm"
        case .sevenSixTwoLong: return "7.62×51mm"
        case .twelveGauge: return "12 Gauge"
        }
    }
}

enum WeaponClass: Int, Codable {
    case pistol, smg, assaultRifle, shotgun, sniper, melee
}

enum FireMode: Int, Codable {
    case semi, auto, bolt, pump

    var name: String {
        switch self {
        case .semi: return "SEMI"
        case .auto: return "AUTO"
        case .bolt: return "BOLT"
        case .pump: return "PUMP"
        }
    }
}

enum AttachSlot: Int, Codable, CaseIterable {
    case optic, muzzle, rail, grip

    var title: String {
        switch self {
        case .optic: return "OPTIC"
        case .muzzle: return "MUZZLE"
        case .rail: return "LIGHT"
        case .grip: return "GRIP"
        }
    }
}

enum ItemModel: Int, CaseIterable {
    // Food & drink
    case can, canTall, sodaCan, waterBottle, canteen, cerealBox, crackers, bar, apple, potato, juiceBox, jerky
    // Medical
    case bandage, rag, spray, pillBottle, salineBag, splint, injector
    // Clothing (world look)
    case foldedShirt, foldedJacket, foldedPants, boots, sneakers, capItem, beanieItem, helmetItem, policeCapItem, motoHelmetItem
    case bandanaItem, surgicalMaskItem, gasMaskItem, balaclavaItem
    case vestHuntingItem, vestPoliceItem, plateCarrierItem, chestRigItem
    case backpackSchoolItem, backpackHikingItem, backpackMilitaryItem
    // Firearms
    case pistolWarden, pistolHollis, smgWasp, rifleKestrel, rifleVanta, shotgunBrennan, sniperLongreach
    // Magazines
    case magPistol, magPistolShort, magSMG, magKestrel, magVanta, magSniper
    // Ammo
    case ammoPistol, ammoRifle, ammoShells
    // Attachments
    case redDot, scope, suppressorPistol, suppressorRifle, flashlightAttach, verticalGrip
    // Melee
    case kitchenKnife, huntingKnife, machete, axe, crowbar, bat, wrench
    // Tools
    case canOpener, matches, ductTape, sewingKit, cleaningKit, battery, flashlight, compass
}

struct FoodProps {
    var energy: Float          // kcal for the whole item
    var water: Float           // ml for the whole item (negative = dry food)
    var needsOpening = false
    var liquidContainer = false // refillable container (quantity = ml)
    var capacity: Float = 0
    var poisonChance: Float = 0
}

enum MedicalKind: Int, Codable {
    case bandage, rag, disinfectant, antibiotics, painkillers, vitamins, charcoal, saline, splint, morphine
}

struct WeaponProps {
    var weaponClass: WeaponClass
    var caliber: Caliber?
    var magazineID: String?      // compatible detachable magazine item id
    var internalCapacity = 0     // tube / internal magazine
    var modes: [FireMode]
    var damage: Float
    var pellets = 1
    var rpm: Float
    var recoil: Float            // vertical kick (radians)
    var spread: Float            // base inaccuracy (radians)
    var range: Float             // effective range
    var muzzleVelocity: Float = 400
    var noise: Float             // hearing radius in meters
    var attachSlots: [AttachSlot] = []
    var meleeDamage: Float = 15
    var meleeRange: Float = 1.6
    var meleeSpeed: Float = 1.0  // swings per second
    var twoHanded = false
    var sound: SoundID = .gunRifle
    var reloadTime: Float = 2.4
    var bleedChance: Float = 0.3
}

struct MagazineProps {
    var caliber: Caliber
    var capacity: Int
}

struct AttachmentProps {
    var slot: AttachSlot
    var compatible: [String]
    var zoomFOV: Float = 0        // degrees when aiming (0 = none)
    var scope = false
    var redDot = false
    var noiseMultiplier: Float = 1
    var recoilMultiplier: Float = 1
    var light = false
}

struct ClothingProps {
    var slot: EquipSlot
    var cargo: (w: Int, h: Int)?
    var insulation: Float = 0.1
    var waterproof: Float = 0
    var armor: Float = 0
    var color: Vec3 = Vec3(0.7, 0.7, 0.7)
    var layer: Mat = .fabric
    var bulky = false
    var longSleeves = true
    var gear: GearMesh?
    var boots = false
}

enum ToolKind: Int, Codable {
    case canOpener, matches, ductTape, sewingKit, cleaningKit, battery, flashlight, compass, blade
}

final class ItemDef {
    let id: String
    let name: String
    let desc: String
    let category: ItemCategory
    let size: (w: Int, h: Int)
    let weight: Float
    let stackMax: Int
    let model: ItemModel
    let tint: Vec3
    var food: FoodProps?
    var medical: MedicalKind?
    var medicalUses = 1
    var clothing: ClothingProps?
    var weapon: WeaponProps?
    var ammo: Caliber?
    var magazine: MagazineProps?
    var attachment: AttachmentProps?
    var tool: ToolKind?
    var loot: [LootCategory: Float] = [:]
    var largeLoot = false

    init(_ id: String, _ name: String, _ desc: String, _ cat: ItemCategory, size: (Int, Int), weight: Float, stack: Int = 1,
         model: ItemModel, tint: Vec3 = Vec3(1, 1, 1)) {
        self.id = id
        self.name = name
        self.desc = desc
        category = cat
        self.size = (size.0, size.1)
        self.weight = weight
        stackMax = stack
        self.model = model
        self.tint = tint
    }

    var isStackable: Bool { stackMax > 1 }
    var isFirearm: Bool { category == .firearm }
    var isMelee: Bool { category == .melee }
    var isLong: Bool { weapon.map { $0.weaponClass == .assaultRifle || $0.weaponClass == .shotgun || $0.weaponClass == .sniper } ?? false }
}

enum ItemDB {
    static private(set) var all: [String: ItemDef] = [:]
    static private(set) var ordered: [ItemDef] = []

    static func get(_ id: String) -> ItemDef? { all[id] }

    @discardableResult
    private static func add(_ d: ItemDef, _ configure: (ItemDef) -> Void = { _ in }) -> ItemDef {
        configure(d)
        all[d.id] = d
        ordered.append(d)
        return d
    }

    // swiftlint:disable:next function_body_length
    static func load() {
        guard all.isEmpty else { return }

        // MARK: Food
        add(ItemDef("beans", "Canned Beans", "Baked beans in tomato sauce. Needs to be opened with a tool.", .food, size: (1, 2), weight: 0.45, model: .can, tint: Vec3(0.8, 0.35, 0.2))) {
            $0.food = FoodProps(energy: 450, water: 60, needsOpening: true)
            $0.loot = [.kitchen: 3, .shop: 4, .vehicle: 1, .military: 1, .farm: 1]
        }
        add(ItemDef("peaches", "Canned Peaches", "Sweet peach halves in syrup. Good for thirst too.", .food, size: (1, 2), weight: 0.42, model: .can, tint: Vec3(0.95, 0.65, 0.2))) {
            $0.food = FoodProps(energy: 300, water: 200, needsOpening: true)
            $0.loot = [.kitchen: 2, .shop: 3, .vehicle: 0.6]
        }
        add(ItemDef("tuna", "Canned Tuna", "Flat tin of tuna. Protein, not much else.", .food, size: (1, 1), weight: 0.2, model: .can, tint: Vec3(0.3, 0.5, 0.75))) {
            $0.food = FoodProps(energy: 250, water: 40, needsOpening: true)
            $0.loot = [.kitchen: 2, .shop: 3, .industrial: 0.5]
        }
        add(ItemDef("spaghetti", "Canned Spaghetti", "Pasta in sauce. Filling.", .food, size: (1, 2), weight: 0.5, model: .canTall, tint: Vec3(0.85, 0.75, 0.3))) {
            $0.food = FoodProps(energy: 520, water: 90, needsOpening: true)
            $0.loot = [.kitchen: 2, .shop: 2, .military: 0.5]
        }
        add(ItemDef("crackers", "Salted Crackers", "A box of dry crackers. Makes you thirsty.", .food, size: (2, 1), weight: 0.25, model: .crackers, tint: Vec3(0.9, 0.8, 0.4))) {
            $0.food = FoodProps(energy: 380, water: -80)
            $0.loot = [.kitchen: 2, .shop: 3, .office: 1, .vehicle: 0.5]
        }
        add(ItemDef("cereal", "Oat Cereal", "Half a box of oat cereal.", .food, size: (2, 2), weight: 0.4, model: .cerealBox, tint: Vec3(0.85, 0.5, 0.25))) {
            $0.food = FoodProps(energy: 650, water: -60)
            $0.loot = [.kitchen: 2, .shop: 2]
        }
        add(ItemDef("energybar", "Energy Bar", "Dense oat and honey bar.", .food, size: (1, 1), weight: 0.08, model: .bar, tint: Vec3(0.3, 0.55, 0.85))) {
            $0.food = FoodProps(energy: 300, water: -10)
            $0.loot = [.shop: 2, .office: 1, .military: 1.5, .vehicle: 1, .living: 0.5]
        }
        add(ItemDef("chocolate", "Chocolate Bar", "Slightly melted milk chocolate.", .food, size: (1, 1), weight: 0.1, model: .bar, tint: Vec3(0.45, 0.25, 0.15))) {
            $0.food = FoodProps(energy: 260, water: -10)
            $0.loot = [.shop: 2, .office: 1, .living: 1, .vehicle: 0.6]
        }
        add(ItemDef("apple", "Apple", "A fresh red apple.", .food, size: (1, 1), weight: 0.15, model: .apple, tint: Vec3(0.75, 0.12, 0.1))) {
            $0.food = FoodProps(energy: 90, water: 80, poisonChance: 0.05)
            $0.loot = [.kitchen: 1.5, .farm: 3, .shop: 1]
        }
        add(ItemDef("potato", "Potato", "A raw potato. Edible, barely.", .food, size: (1, 1), weight: 0.2, model: .potato, tint: Vec3(0.75, 0.6, 0.4))) {
            $0.food = FoodProps(energy: 110, water: 30, poisonChance: 0.12)
            $0.loot = [.farm: 4, .kitchen: 1]
        }
        add(ItemDef("jerky", "Beef Jerky", "Dried, salted strips of beef.", .food, size: (1, 1), weight: 0.1, model: .jerky, tint: Vec3(0.5, 0.25, 0.15))) {
            $0.food = FoodProps(energy: 330, water: -40)
            $0.loot = [.shop: 1.5, .vehicle: 1, .military: 1, .farm: 1]
        }

        // MARK: Drinks
        add(ItemDef("waterbottle", "Water Bottle", "Plastic bottle. Refill it at wells, pumps or lakes.", .drink, size: (1, 2), weight: 0.1, model: .waterBottle, tint: Vec3(0.6, 0.8, 0.95))) {
            $0.food = FoodProps(energy: 0, water: 0, liquidContainer: true, capacity: 1000)
            $0.loot = [.kitchen: 2, .shop: 3, .vehicle: 2, .office: 1, .medical: 1, .industrial: 1]
        }
        add(ItemDef("canteen", "Army Canteen", "Steel canteen with a canvas cover. Holds 1.5 liters.", .drink, size: (2, 2), weight: 0.35, model: .canteen, tint: Vec3(0.35, 0.4, 0.28))) {
            $0.food = FoodProps(energy: 0, water: 0, liquidContainer: true, capacity: 1500)
            $0.loot = [.military: 3, .police: 0.5]
        }
        add(ItemDef("soda", "Fizzy Cola", "Warm, flat and sugary.", .drink, size: (1, 1), weight: 0.35, model: .sodaCan, tint: Vec3(0.75, 0.1, 0.1))) {
            $0.food = FoodProps(energy: 140, water: 330)
            $0.loot = [.shop: 3, .kitchen: 1.5, .office: 1.5, .vehicle: 1, .living: 1]
        }
        add(ItemDef("juice", "Juice Box", "Apple juice. Tiny straw included.", .drink, size: (1, 1), weight: 0.22, model: .juiceBox, tint: Vec3(0.3, 0.7, 0.3))) {
            $0.food = FoodProps(energy: 90, water: 200)
            $0.loot = [.shop: 2, .kitchen: 1.5, .living: 0.5]
        }

        // MARK: Medical
        add(ItemDef("bandage", "Bandage", "Sterile gauze roll. Stops one bleeding wound.", .medical, size: (1, 1), weight: 0.05, stack: 4, model: .bandage, tint: Vec3(0.95, 0.95, 0.92))) {
            $0.medical = .bandage
            $0.loot = [.bathroom: 3, .medical: 5, .police: 1.5, .military: 2, .office: 0.5, .vehicle: 0.6]
        }
        add(ItemDef("rag", "Rags", "Strips of cloth. Can bind a wound, but it isn't clean.", .medical, size: (1, 1), weight: 0.05, stack: 6, model: .rag, tint: Vec3(0.75, 0.72, 0.65))) {
            $0.medical = .rag
            $0.loot = [.bathroom: 1.5, .bedroom: 1, .garage: 1.5, .industrial: 1, .living: 0.6]
        }
        add(ItemDef("disinfectant", "Disinfectant Spray", "Cleans wounds and prevents infection.", .medical, size: (1, 2), weight: 0.25, model: .spray, tint: Vec3(0.3, 0.6, 0.85))) {
            $0.medical = .disinfectant
            $0.medicalUses = 6
            $0.loot = [.bathroom: 1.5, .medical: 3, .shop: 0.5]
        }
        add(ItemDef("antibiotics", "Antibiotics", "Tetracycline-type tablets. Treats wound infection.", .medical, size: (1, 1), weight: 0.05, model: .pillBottle, tint: Vec3(0.85, 0.85, 0.3))) {
            $0.medical = .antibiotics
            $0.medicalUses = 6
            $0.loot = [.medical: 3, .bathroom: 0.6, .military: 0.5]
        }
        add(ItemDef("painkillers", "Painkillers", "Strong analgesic tablets. Steadies shaking hands.", .medical, size: (1, 1), weight: 0.05, model: .pillBottle, tint: Vec3(0.85, 0.3, 0.3))) {
            $0.medical = .painkillers
            $0.medicalUses = 8
            $0.loot = [.medical: 2.5, .bathroom: 1.5, .shop: 0.5]
        }
        add(ItemDef("vitamins", "Multivitamins", "Daily vitamins. Helps the body fight off colds.", .medical, size: (1, 1), weight: 0.05, model: .pillBottle, tint: Vec3(0.3, 0.75, 0.4))) {
            $0.medical = .vitamins
            $0.medicalUses = 10
            $0.loot = [.medical: 1.5, .bathroom: 1.5, .shop: 1, .kitchen: 0.5]
        }
        add(ItemDef("charcoal", "Charcoal Tablets", "Activated charcoal. Treats food poisoning.", .medical, size: (1, 1), weight: 0.05, model: .pillBottle, tint: Vec3(0.2, 0.2, 0.2))) {
            $0.medical = .charcoal
            $0.medicalUses = 6
            $0.loot = [.medical: 2, .bathroom: 1, .shop: 0.5]
        }
        add(ItemDef("saline", "Saline Bag", "IV saline solution. Restores lost blood volume over time.", .medical, size: (2, 2), weight: 0.6, model: .salineBag, tint: Vec3(0.85, 0.92, 0.95))) {
            $0.medical = .saline
            $0.loot = [.medical: 2, .military: 0.4]
        }
        add(ItemDef("splint", "Splint", "Padded aluminium splint. Lets a broken leg heal.", .medical, size: (1, 3), weight: 0.3, model: .splint, tint: Vec3(0.85, 0.55, 0.2))) {
            $0.medical = .splint
            $0.loot = [.medical: 2, .military: 0.6, .police: 0.3]
        }
        add(ItemDef("morphine", "Morphine Auto-Injector", "Military injector. Instantly kills pain and lets you walk on a broken leg.", .medical, size: (1, 1), weight: 0.05, model: .injector, tint: Vec3(0.3, 0.55, 0.3))) {
            $0.medical = .morphine
            $0.loot = [.medical: 0.8, .military: 1.2]
        }

        // MARK: Clothing
        func clothing(_ id: String, _ name: String, _ desc: String, size: (Int, Int), weight: Float, model: ItemModel, _ c: ClothingProps, loot: [LootCategory: Float]) {
            add(ItemDef(id, name, desc, .clothing, size: size, weight: weight, model: model, tint: c.color)) {
                $0.clothing = c
                $0.loot = loot
                $0.largeLoot = size.0 * size.1 >= 6
            }
        }
        clothing("beanie", "Knit Beanie", "Warm wool hat.", size: (1, 1), weight: 0.1, model: .beanieItem,
                 ClothingProps(slot: .head, insulation: 0.25, color: Vec3(0.3, 0.3, 0.32), gear: .beanie), loot: [.bedroom: 1.5, .shop: 0.8])
        clothing("cap", "Baseball Cap", "Faded cap with a frayed brim.", size: (1, 1), weight: 0.08, model: .capItem,
                 ClothingProps(slot: .head, insulation: 0.08, color: Vec3(0.2, 0.3, 0.55), gear: .cap), loot: [.bedroom: 1.5, .shop: 0.6, .living: 0.5])
        clothing("helmet", "Combat Helmet", "Ballistic helmet. Protects against blows and some gunfire.", size: (2, 2), weight: 1.4, model: .helmetItem,
                 ClothingProps(slot: .head, insulation: 0.1, armor: 0.5, color: Vec3(0.36, 0.4, 0.3), layer: .camo, gear: .helmet), loot: [.military: 1.6])
        clothing("policecap", "Police Cap", "Peaked cap of the Halden police.", size: (1, 1), weight: 0.1, model: .policeCapItem,
                 ClothingProps(slot: .head, insulation: 0.08, color: Vec3(0.12, 0.14, 0.25), gear: .policeCap), loot: [.police: 1.5])
        clothing("motohelmet", "Motorcycle Helmet", "Full-face helmet. Heavy, but it takes a hit.", size: (2, 2), weight: 1.2, model: .motoHelmetItem,
                 ClothingProps(slot: .head, insulation: 0.2, armor: 0.3, color: Vec3(0.12, 0.12, 0.13), gear: .motoHelmet), loot: [.garage: 1, .vehicle: 0.4])
        clothing("bandana", "Bandana", "Cotton bandana tied over the face.", size: (1, 1), weight: 0.05, model: .bandanaItem,
                 ClothingProps(slot: .face, insulation: 0.05, color: Vec3(0.6, 0.15, 0.12), gear: .bandana), loot: [.bedroom: 1, .garage: 0.6])
        clothing("surgicalmask", "Surgical Mask", "Thin mask. Reduces the chance of catching illness.", size: (1, 1), weight: 0.02, model: .surgicalMaskItem,
                 ClothingProps(slot: .face, insulation: 0.02, color: Vec3(0.6, 0.8, 0.85), gear: .surgicalMask), loot: [.medical: 2, .bathroom: 0.6])
        clothing("gasmask", "Gas Mask", "Rubber respirator with a filter canister.", size: (2, 2), weight: 0.8, model: .gasMaskItem,
                 ClothingProps(slot: .face, insulation: 0.15, color: Vec3(0.2, 0.22, 0.2), layer: .rubber, gear: .gasMask), loot: [.military: 0.8, .police: 0.4])
        clothing("balaclava", "Balaclava", "Knitted face mask. Warm.", size: (1, 1), weight: 0.1, model: .balaclavaItem,
                 ClothingProps(slot: .face, insulation: 0.2, color: Vec3(0.12, 0.12, 0.12), gear: .balaclava), loot: [.military: 1, .bedroom: 0.4])

        clothing("tshirt", "T-Shirt", "Plain cotton t-shirt. Cold and thin.", size: (2, 2), weight: 0.2, model: .foldedShirt,
                 ClothingProps(slot: .torso, cargo: (2, 2), insulation: 0.1, color: Vec3(0.78, 0.78, 0.75), layer: .fabric, bulky: false, longSleeves: false), loot: [.bedroom: 1.5, .shop: 1])
        clothing("hoodie", "Hoodie", "Thick cotton hoodie with a front pocket.", size: (2, 3), weight: 0.6, model: .foldedJacket,
                 ClothingProps(slot: .torso, cargo: (3, 2), insulation: 0.4, waterproof: 0.1, color: Vec3(0.35, 0.38, 0.42), layer: .fabric, bulky: false, longSleeves: true), loot: [.bedroom: 2, .shop: 1])
        clothing("fieldjacket", "Field Jacket", "Waxed canvas jacket with deep pockets.", size: (3, 3), weight: 1.1, model: .foldedJacket,
                 ClothingProps(slot: .torso, cargo: (4, 3), insulation: 0.55, waterproof: 0.45, color: Vec3(0.42, 0.38, 0.25), layer: .canvas, bulky: true, longSleeves: true), loot: [.bedroom: 1, .farm: 1.5, .garage: 0.6])
        clothing("policejacket", "Police Jacket", "Navy jacket with reflective strips.", size: (3, 3), weight: 1.0, model: .foldedJacket,
                 ClothingProps(slot: .torso, cargo: (3, 3), insulation: 0.45, waterproof: 0.4, color: Vec3(0.12, 0.15, 0.28), layer: .fabric, bulky: true, longSleeves: true), loot: [.police: 2])
        clothing("militaryjacket", "Military Jacket", "Woodland camouflage combat jacket.", size: (3, 3), weight: 1.2, model: .foldedJacket,
                 ClothingProps(slot: .torso, cargo: (4, 3), insulation: 0.5, waterproof: 0.5, color: Vec3(0.8, 0.85, 0.75), layer: .camo, bulky: true, longSleeves: true), loot: [.military: 2])
        clothing("downcoat", "Down Coat", "Puffy winter coat. Very warm.", size: (3, 3), weight: 1.3, model: .foldedJacket,
                 ClothingProps(slot: .torso, cargo: (3, 3), insulation: 0.85, waterproof: 0.3, color: Vec3(0.5, 0.15, 0.12), layer: .fabric, bulky: true, longSleeves: true), loot: [.bedroom: 0.8, .shop: 0.4])
        clothing("raincoat", "Raincoat", "Bright yellow raincoat. Keeps you dry.", size: (2, 3), weight: 0.6, model: .foldedJacket,
                 ClothingProps(slot: .torso, cargo: (3, 2), insulation: 0.25, waterproof: 0.95, color: Vec3(0.9, 0.75, 0.15), layer: .plastic, bulky: true, longSleeves: true), loot: [.farm: 1, .garage: 0.8, .bedroom: 0.5])

        clothing("huntingvest", "Hunting Vest", "Orange mesh vest full of pouches.", size: (3, 3), weight: 0.7, model: .vestHuntingItem,
                 ClothingProps(slot: .vest, cargo: (4, 3), insulation: 0.1, color: Vec3(0.9, 0.45, 0.1), layer: .canvas, gear: .vestHunting), loot: [.farm: 1, .garage: 0.5])
        clothing("policevest", "Police Vest", "Soft body armor. Stops pistol rounds, mostly.", size: (3, 3), weight: 2.5, model: .vestPoliceItem,
                 ClothingProps(slot: .vest, cargo: (2, 2), insulation: 0.15, armor: 0.4, color: Vec3(0.15, 0.17, 0.22), layer: .fabric, gear: .vestPolice), loot: [.police: 1.4])
        clothing("platecarrier", "Plate Carrier", "Military plate carrier with ceramic plates.", size: (3, 3), weight: 6.0, model: .plateCarrierItem,
                 ClothingProps(slot: .vest, cargo: (3, 3), insulation: 0.15, armor: 0.65, color: Vec3(0.75, 0.78, 0.65), layer: .camo, gear: .plateCarrier), loot: [.military: 0.8])
        clothing("chestrig", "Chest Rig", "Webbing rig with magazine pouches.", size: (3, 2), weight: 0.8, model: .chestRigItem,
                 ClothingProps(slot: .vest, cargo: (4, 2), insulation: 0.05, color: Vec3(0.35, 0.38, 0.28), layer: .canvas, gear: .chestRig), loot: [.military: 1.4])

        clothing("jeans", "Jeans", "Worn blue jeans.", size: (2, 3), weight: 0.7, model: .foldedPants,
                 ClothingProps(slot: .legs, cargo: (3, 2), insulation: 0.2, color: Vec3(0.32, 0.4, 0.58), layer: .denim), loot: [.bedroom: 1.5, .shop: 0.8])
        clothing("cargopants", "Cargo Pants", "Canvas work trousers with side pockets.", size: (2, 3), weight: 0.8, model: .foldedPants,
                 ClothingProps(slot: .legs, cargo: (4, 3), insulation: 0.3, waterproof: 0.2, color: Vec3(0.45, 0.42, 0.32), layer: .canvas), loot: [.garage: 1, .industrial: 1, .bedroom: 0.8, .farm: 0.8])
        clothing("militarypants", "Military Pants", "Camouflage combat trousers.", size: (2, 3), weight: 0.9, model: .foldedPants,
                 ClothingProps(slot: .legs, cargo: (4, 3), insulation: 0.4, waterproof: 0.4, color: Vec3(0.8, 0.85, 0.75), layer: .camo), loot: [.military: 2])
        clothing("trackpants", "Track Pants", "Soft fleece track pants.", size: (2, 2), weight: 0.5, model: .foldedPants,
                 ClothingProps(slot: .legs, cargo: (2, 2), insulation: 0.3, color: Vec3(0.2, 0.22, 0.25), layer: .fabric), loot: [.bedroom: 1.2, .shop: 0.6])

        clothing("sneakers", "Sneakers", "Comfortable but thin running shoes.", size: (2, 2), weight: 0.6, model: .sneakers,
                 ClothingProps(slot: .feet, insulation: 0.1, color: Vec3(0.88, 0.88, 0.86), layer: .fabric), loot: [.bedroom: 1, .shop: 0.6])
        clothing("hikingboots", "Hiking Boots", "Waterproof leather hiking boots.", size: (2, 2), weight: 1.1, model: .boots,
                 ClothingProps(slot: .feet, insulation: 0.4, waterproof: 0.6, color: Vec3(0.45, 0.32, 0.2), layer: .leather, boots: true), loot: [.bedroom: 0.6, .shop: 0.5, .farm: 0.8])
        clothing("militaryboots", "Military Boots", "Black combat boots.", size: (2, 2), weight: 1.3, model: .boots,
                 ClothingProps(slot: .feet, insulation: 0.45, waterproof: 0.7, color: Vec3(0.12, 0.12, 0.12), layer: .leather, boots: true), loot: [.military: 1.5, .police: 0.6])
        clothing("rubberboots", "Rubber Boots", "Tall wellingtons. Fully waterproof, not warm.", size: (2, 3), weight: 1.0, model: .boots,
                 ClothingProps(slot: .feet, insulation: 0.15, waterproof: 1.0, color: Vec3(0.2, 0.35, 0.2), layer: .rubber, boots: true), loot: [.farm: 1.5, .garage: 0.5])

        clothing("schoolbag", "School Backpack", "Small nylon backpack.", size: (3, 3), weight: 0.5, model: .backpackSchoolItem,
                 ClothingProps(slot: .backpack, cargo: (5, 4), color: Vec3(0.2, 0.35, 0.6), layer: .canvas, gear: .backpackSchool), loot: [.bedroom: 1, .living: 0.6, .shop: 0.3])
        clothing("hikingpack", "Hiking Backpack", "Framed hiking pack with a bedroll.", size: (4, 4), weight: 1.2, model: .backpackHikingItem,
                 ClothingProps(slot: .backpack, cargo: (6, 6), color: Vec3(0.35, 0.45, 0.32), layer: .canvas, gear: .backpackHiking), loot: [.bedroom: 0.4, .garage: 0.5, .farm: 0.5, .vehicle: 0.3])
        clothing("rucksack", "Military Rucksack", "Large camouflaged field pack.", size: (4, 5), weight: 1.8, model: .backpackMilitaryItem,
                 ClothingProps(slot: .backpack, cargo: (7, 8), color: Vec3(0.8, 0.85, 0.75), layer: .camo, gear: .backpackMilitary), loot: [.military: 0.9])

        // MARK: Firearms
        add(ItemDef("warden", "M9 Warden", "Reliable 9×19mm service pistol. Uses Warden 15-round magazines.", .firearm, size: (2, 2), weight: 0.95, model: .pistolWarden)) {
            $0.weapon = WeaponProps(weaponClass: .pistol, caliber: .nine, magazineID: "mag_warden", modes: [.semi], damage: 34, rpm: 420, recoil: 0.035,
                                    spread: 0.009, range: 60, muzzleVelocity: 360, noise: 110, attachSlots: [.muzzle, .rail], meleeDamage: 10,
                                    sound: .gunPistol, reloadTime: 1.8, bleedChance: 0.35)
            $0.loot = [.police: 2.5, .military: 0.8, .bedroom: 0.15, .office: 0.2]
        }
        add(ItemDef("hollis", "Hollis .45", "Heavy-hitting .45 ACP pistol. Uses Hollis 8-round magazines.", .firearm, size: (2, 2), weight: 1.1, model: .pistolHollis)) {
            $0.weapon = WeaponProps(weaponClass: .pistol, caliber: .fortyFive, magazineID: "mag_hollis", modes: [.semi], damage: 48, rpm: 340, recoil: 0.06,
                                    spread: 0.011, range: 55, muzzleVelocity: 260, noise: 120, attachSlots: [.rail], meleeDamage: 11,
                                    sound: .gunPistol, reloadTime: 1.9, bleedChance: 0.45)
            $0.loot = [.police: 1.2, .bedroom: 0.12, .living: 0.08, .vehicle: 0.1]
        }
        add(ItemDef("wasp", "Wasp-9 SMG", "Compact 9×19mm submachine gun. Uses Wasp 30-round magazines.", .firearm, size: (3, 2), weight: 2.6, model: .smgWasp)) {
            $0.weapon = WeaponProps(weaponClass: .smg, caliber: .nine, magazineID: "mag_wasp", modes: [.auto, .semi], damage: 30, rpm: 820, recoil: 0.028,
                                    spread: 0.012, range: 90, muzzleVelocity: 390, noise: 130, attachSlots: [.optic, .muzzle, .rail, .grip], meleeDamage: 13,
                                    sound: .gunSMG, reloadTime: 2.2, bleedChance: 0.35)
            $0.loot = [.police: 0.7, .military: 0.9]
        }
        add(ItemDef("kestrel", "Kestrel AR", "5.56×45mm assault rifle. Uses Kestrel 30-round magazines.", .firearm, size: (5, 2), weight: 3.4, model: .rifleKestrel)) {
            $0.weapon = WeaponProps(weaponClass: .assaultRifle, caliber: .fiveFiveSix, magazineID: "mag_kestrel", modes: [.semi, .auto], damage: 44, rpm: 760, recoil: 0.03,
                                    spread: 0.0035, range: 350, muzzleVelocity: 900, noise: 300, attachSlots: [.optic, .muzzle, .rail, .grip], meleeDamage: 18,
                                    twoHanded: true, sound: .gunRifle, reloadTime: 2.4, bleedChance: 0.55)
            $0.loot = [.military: 1.4]
            $0.largeLoot = true
        }
        add(ItemDef("vanta", "Vanta-47", "Rugged 7.62×39mm assault rifle. Uses Vanta 30-round magazines.", .firearm, size: (5, 2), weight: 3.8, model: .rifleVanta)) {
            $0.weapon = WeaponProps(weaponClass: .assaultRifle, caliber: .sevenSixTwoShort, magazineID: "mag_vanta", modes: [.semi, .auto], damage: 52, rpm: 610, recoil: 0.045,
                                    spread: 0.005, range: 300, muzzleVelocity: 715, noise: 320, attachSlots: [.optic, .rail, .grip], meleeDamage: 18,
                                    twoHanded: true, sound: .gunRifle, reloadTime: 2.6, bleedChance: 0.6)
            $0.loot = [.military: 1.0, .police: 0.2]
            $0.largeLoot = true
        }
        add(ItemDef("brennan", "Brennan 12", "Pump-action 12 gauge shotgun with a 6-shell tube. Load shells directly.", .firearm, size: (5, 2), weight: 3.3, model: .shotgunBrennan)) {
            $0.weapon = WeaponProps(weaponClass: .shotgun, caliber: .twelveGauge, magazineID: nil, internalCapacity: 6, modes: [.pump], damage: 15, pellets: 9,
                                    rpm: 70, recoil: 0.09, spread: 0.045, range: 35, muzzleVelocity: 400, noise: 260, attachSlots: [.rail], meleeDamage: 18,
                                    twoHanded: true, sound: .gunShotgun, reloadTime: 0.6, bleedChance: 0.7)
            $0.loot = [.police: 0.8, .farm: 0.7, .garage: 0.15]
            $0.largeLoot = true
        }
        add(ItemDef("longreach", "Longreach M2", "Bolt-action 7.62×51mm precision rifle. Uses Longreach 5-round magazines.", .firearm, size: (6, 2), weight: 4.5, model: .sniperLongreach)) {
            $0.weapon = WeaponProps(weaponClass: .sniper, caliber: .sevenSixTwoLong, magazineID: "mag_longreach", modes: [.bolt], damage: 110, rpm: 45, recoil: 0.11,
                                    spread: 0.001, range: 800, muzzleVelocity: 850, noise: 450, attachSlots: [.optic, .muzzle], meleeDamage: 18,
                                    twoHanded: true, sound: .gunSniper, reloadTime: 2.8, bleedChance: 0.8)
            $0.loot = [.military: 0.35, .farm: 0.2]
            $0.largeLoot = true
        }

        // MARK: Magazines
        func mag(_ id: String, _ name: String, _ cal: Caliber, _ cap: Int, size: (Int, Int), model: ItemModel, loot: [LootCategory: Float]) {
            add(ItemDef(id, name, "Detachable \(cal.name) magazine. Holds \(cap) rounds.", .magazine, size: size, weight: 0.12 + Float(cap) * 0.008, model: model)) {
                $0.magazine = MagazineProps(caliber: cal, capacity: cap)
                $0.loot = loot
            }
        }
        mag("mag_warden", "Warden 15rnd Mag", .nine, 15, size: (1, 1), model: .magPistol, loot: [.police: 2, .military: 0.6])
        mag("mag_hollis", "Hollis 8rnd Mag", .fortyFive, 8, size: (1, 1), model: .magPistolShort, loot: [.police: 1.2, .bedroom: 0.08])
        mag("mag_wasp", "Wasp 30rnd Mag", .nine, 30, size: (1, 2), model: .magSMG, loot: [.police: 0.8, .military: 1])
        mag("mag_kestrel", "Kestrel 30rnd Mag", .fiveFiveSix, 30, size: (1, 2), model: .magKestrel, loot: [.military: 2])
        mag("mag_vanta", "Vanta 30rnd Mag", .sevenSixTwoShort, 30, size: (1, 2), model: .magVanta, loot: [.military: 1.5])
        mag("mag_longreach", "Longreach 5rnd Mag", .sevenSixTwoLong, 5, size: (1, 1), model: .magSniper, loot: [.military: 0.8, .farm: 0.2])

        // MARK: Ammunition
        func ammo(_ id: String, _ name: String, _ cal: Caliber, stack: Int, model: ItemModel, loot: [LootCategory: Float]) {
            add(ItemDef(id, name, "Loose \(cal.name) rounds. Load them into a matching magazine.", .ammo, size: (1, 1), weight: 0.012, stack: stack, model: model)) {
                $0.ammo = cal
                $0.loot = loot
            }
        }
        ammo("ammo_9mm", "9mm Rounds", .nine, stack: 50, model: .ammoPistol, loot: [.police: 3, .military: 1.5, .bedroom: 0.4, .vehicle: 0.4, .garage: 0.3])
        ammo("ammo_45", ".45 ACP Rounds", .fortyFive, stack: 40, model: .ammoPistol, loot: [.police: 1.6, .bedroom: 0.3, .vehicle: 0.3])
        ammo("ammo_556", "5.56mm Rounds", .fiveFiveSix, stack: 60, model: .ammoRifle, loot: [.military: 3])
        ammo("ammo_762", "7.62×39mm Rounds", .sevenSixTwoShort, stack: 60, model: .ammoRifle, loot: [.military: 2.2, .police: 0.3])
        ammo("ammo_308", "7.62×51mm Rounds", .sevenSixTwoLong, stack: 40, model: .ammoRifle, loot: [.military: 1, .farm: 0.6])
        ammo("ammo_12ga", "12ga Buckshot", .twelveGauge, stack: 30, model: .ammoShells, loot: [.police: 1.5, .farm: 1.8, .garage: 0.5, .vehicle: 0.3])

        // MARK: Attachments
        add(ItemDef("reddot", "Pinpoint Red Dot", "Compact reflex sight. Fits Kestrel, Vanta and Wasp rails.", .attachment, size: (1, 1), weight: 0.2, model: .redDot)) {
            $0.attachment = AttachmentProps(slot: .optic, compatible: ["kestrel", "vanta", "wasp"], zoomFOV: 48, redDot: true)
            $0.loot = [.military: 1.2, .police: 0.3]
        }
        add(ItemDef("scope4x", "Ranger 4× Scope", "Magnified optic. Fits Kestrel, Vanta and Longreach.", .attachment, size: (2, 1), weight: 0.5, model: .scope)) {
            $0.attachment = AttachmentProps(slot: .optic, compatible: ["kestrel", "vanta", "longreach"], zoomFOV: 15, scope: true)
            $0.loot = [.military: 0.7, .farm: 0.15]
        }
        add(ItemDef("supp_pistol", "9mm Suppressor", "Threaded suppressor for the Warden and Wasp-9.", .attachment, size: (2, 1), weight: 0.25, model: .suppressorPistol)) {
            $0.attachment = AttachmentProps(slot: .muzzle, compatible: ["warden", "wasp"], noiseMultiplier: 0.22)
            $0.loot = [.police: 0.5, .military: 0.5]
        }
        add(ItemDef("supp_rifle", "Rifle Suppressor", "Sound suppressor for the Kestrel AR and Longreach.", .attachment, size: (2, 1), weight: 0.55, model: .suppressorRifle)) {
            $0.attachment = AttachmentProps(slot: .muzzle, compatible: ["kestrel", "longreach"], noiseMultiplier: 0.3)
            $0.loot = [.military: 0.5]
        }
        add(ItemDef("weaponlight", "Tactical Light", "Rail-mounted weapon light. Lights the way when aiming.", .attachment, size: (1, 1), weight: 0.15, model: .flashlightAttach)) {
            $0.attachment = AttachmentProps(slot: .rail, compatible: ["kestrel", "vanta", "wasp", "warden", "hollis", "brennan"], light: true)
            $0.loot = [.police: 1, .military: 1]
        }
        add(ItemDef("vgrip", "Vertical Grip", "Foregrip that tames recoil. Fits Kestrel, Vanta and Wasp.", .attachment, size: (1, 1), weight: 0.12, model: .verticalGrip)) {
            $0.attachment = AttachmentProps(slot: .grip, compatible: ["kestrel", "vanta", "wasp"], recoilMultiplier: 0.72)
            $0.loot = [.military: 0.9, .police: 0.2]
        }

        // MARK: Melee
        func melee(_ id: String, _ name: String, _ desc: String, size: (Int, Int), weight: Float, model: ItemModel, dmg: Float, range: Float, speed: Float,
                   twoHanded: Bool = false, blade: Bool = false, bleed: Float, loot: [LootCategory: Float]) {
            add(ItemDef(id, name, desc, .melee, size: size, weight: weight, model: model)) {
                $0.weapon = WeaponProps(weaponClass: .melee, caliber: nil, magazineID: nil, modes: [], damage: dmg, rpm: 0, recoil: 0, spread: 0,
                                        range: range, noise: 6, meleeDamage: dmg, meleeRange: range, meleeSpeed: speed, twoHanded: twoHanded,
                                        sound: .meleeSwing, bleedChance: bleed)
                if blade { $0.tool = .blade }
                $0.loot = loot
                $0.largeLoot = size.0 * size.1 >= 4
            }
        }
        melee("kitchenknife", "Kitchen Knife", "Sharp kitchen knife. Opens cans, cuts rags.", size: (1, 2), weight: 0.2, model: .kitchenKnife, dmg: 24, range: 1.4, speed: 1.8,
              blade: true, bleed: 0.5, loot: [.kitchen: 2.5])
        melee("huntingknife", "Hunting Knife", "Fixed blade hunting knife.", size: (1, 2), weight: 0.3, model: .huntingKnife, dmg: 30, range: 1.4, speed: 1.7,
              blade: true, bleed: 0.6, loot: [.farm: 1, .military: 0.8, .garage: 0.4])
        melee("machete", "Machete", "Long blade for clearing brush — or anything else.", size: (1, 4), weight: 0.9, model: .machete, dmg: 48, range: 1.8, speed: 1.15,
              blade: true, bleed: 0.75, loot: [.farm: 0.8, .garage: 0.5, .military: 0.4])
        melee("fireaxe", "Fire Axe", "Heavy red fire axe. Devastating, slow.", size: (2, 5), weight: 2.6, model: .axe, dmg: 75, range: 2.0, speed: 0.75,
              twoHanded: true, blade: true, bleed: 0.8, loot: [.industrial: 1, .garage: 0.6, .farm: 0.6])
        melee("crowbar", "Crowbar", "Steel pry bar.", size: (1, 4), weight: 1.6, model: .crowbar, dmg: 38, range: 1.8, speed: 1.05, bleed: 0.2,
              loot: [.garage: 1.5, .industrial: 1.5, .vehicle: 0.5])
        melee("bat", "Baseball Bat", "Ash wood bat.", size: (1, 4), weight: 1.0, model: .bat, dmg: 34, range: 1.9, speed: 1.1, twoHanded: true, bleed: 0.1,
              loot: [.bedroom: 0.6, .garage: 0.5, .living: 0.3])
        melee("wrench", "Pipe Wrench", "Heavy adjustable wrench.", size: (1, 3), weight: 1.4, model: .wrench, dmg: 32, range: 1.6, speed: 1.15, bleed: 0.15,
              loot: [.garage: 1.5, .industrial: 1.5, .vehicle: 0.6])

        // MARK: Tools
        func tool(_ id: String, _ name: String, _ desc: String, size: (Int, Int), weight: Float, stack: Int = 1, model: ItemModel, kind: ToolKind, loot: [LootCategory: Float]) {
            add(ItemDef(id, name, desc, .tool, size: size, weight: weight, stack: stack, model: model)) {
                $0.tool = kind
                $0.loot = loot
            }
        }
        tool("canopener", "Can Opener", "Opens cans without spilling a drop.", size: (1, 1), weight: 0.1, model: .canOpener, kind: .canOpener, loot: [.kitchen: 2.5, .shop: 0.5])
        tool("matches", "Matches", "Box of matches.", size: (1, 1), weight: 0.03, stack: 1, model: .matches, kind: .matches, loot: [.kitchen: 1.2, .living: 0.8, .shop: 0.8, .farm: 0.6])
        tool("ducttape", "Duct Tape", "Fixes almost anything. Repairs weapons and gear.", size: (1, 1), weight: 0.2, model: .ductTape, kind: .ductTape, loot: [.garage: 1.5, .industrial: 1, .shop: 0.4])
        tool("sewingkit", "Sewing Kit", "Needle and thread. Repairs clothing.", size: (1, 1), weight: 0.1, model: .sewingKit, kind: .sewingKit, loot: [.bedroom: 1, .living: 0.6, .shop: 0.4])
        tool("cleaningkit", "Weapon Cleaning Kit", "Oil and brushes. Restores firearm condition.", size: (2, 1), weight: 0.3, model: .cleaningKit, kind: .cleaningKit, loot: [.police: 1, .military: 1.2])
        tool("battery", "9V Battery", "Powers flashlights.", size: (1, 1), weight: 0.05, stack: 4, model: .battery, kind: .battery, loot: [.shop: 1, .office: 1, .garage: 0.8, .living: 0.6])
        tool("flashlight", "Flashlight", "Handheld flashlight. Use it in your hands at night.", size: (1, 2), weight: 0.3, model: .flashlight, kind: .flashlight, loot: [.garage: 1, .police: 0.8, .living: 0.6, .vehicle: 0.5, .military: 0.5])
        tool("compass", "Compass", "Shows your heading while it is in your inventory.", size: (1, 1), weight: 0.1, model: .compass, kind: .compass, loot: [.military: 0.8, .farm: 0.4, .office: 0.3, .vehicle: 0.3])
    }
}
