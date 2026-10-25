extends Node
## Global state: the galaxy, the player's inventory and progress, and every item table.

signal changed
signal notify(text: String, color: Color)
signal toast(title: String, text: String, icon: String, color: Color)
signal saved

const VERSION := 3  # bump on every release: the auto-updater only installs a higher number
const REPO := "JumpYbutSchooled/Driftlight"
# two save slots. The admin one (everything free, jump anywhere, god mode) only opens on a device that has
# the admin key file, tied to that machine (see admin_allowed).
const SLOTS := {"pilot": "user://driftlight_save.json", "admin": "user://driftlight_admin.json"}
const ADMIN_KEY := "user://admin_device.key"
const SAVE_PATH := "user://driftlight_save.json"
const SAVE_VERSION := 1
const GALAXY_SEED := 20261024
const GALAXY_RADIUS := 2650.0
const SYSTEM_COUNT := 1000
const MIN_SPACING := 62.0  # closest two systems can be on the galaxy map
const LINK_RANGE := 190.0  # furthest apart two systems can be and still get a stargate
const MINE_COST := 7.0  # mining power needed to split one ore off a Corrite rock; rarer ores are harder
const HARDNESS_PER_TIER := 0.2
const REFINE_TIME := [0.8, 1.2, 2.0, 4.0]  # seconds to smelt one raw ore, by quality (rarer ores +12% per tier)
const PROBE_COST := {"corrite": 4}
const BUILD_COST_MULT := 4  # building ships, weapons and modules takes this many times the listed materials
const PROBE_PRICE := 12  # credits, at a market
const MARKET_MARKUP := 4.0  # ready-made gear costs this many times its materials' worth
const MAX_MISSIONS := 4
const WORLD_SCALE := 0.12  # 3D metres per old 2D pixel: turns the speeds/ranges in these tables into 3D units

const CAT_BLUE := 0
const CAT_GREEN := 1
const CAT_RED := 2
const CAT_PURPLE := 3
const CAT_NAMES := ["Core", "Secure", "Unsecure", "Wild"]
const CAT_COLORS := [Color("4aa8ff"), Color("4cd964"), Color("ff5050"), Color("b366ff")]
const CAT_BG := [Color("03060d"), Color("030906"), Color("0b0305"), Color("09030f")]
# Systems are binned by distance from the core. The outer rings cover the most area, so Wild ends up
# the biggest group (roughly 8% Core, 19% Secure, 25% Unsecure, 48% Wild).
const CAT_EDGES := [0.28, 0.52, 0.72]
const PIRATE_CHANCE := [0.0, 0.12, 0.3, 0.6]
const CAT_PRICE := [0.8, 1.0, 1.25, 1.5]  # market sell price multiplier
const CAT_DANGER := [1.0, 1.0, 1.2, 1.5]  # pirate toughness multiplier

const Q_NAMES := ["Inferior", "Normal", "Superior", "Pristine"]
const Q_NORMAL := 1  # plain ore: shown by its name alone


## An ore's name, with a noun ("vein", "ore") if given, and its quality in brackets unless it's Normal:
## "Corrite vein", "Corrite vein (Pristine)".
static func ore_label(id: String, q: int, noun := "") -> String:
	var s: String = ORES[id].name + ((" " + noun) if noun != "" else "")
	return s if q == Q_NORMAL else "%s (%s)" % [s, Q_NAMES[q]]


## A quality tag for compact lists: "" for Normal, else e.g. "Pri".
static func q_tag(q: int, short := false) -> String:
	if q == Q_NORMAL:
		return ""
	return Q_NAMES[q].substr(0, 3) if short else Q_NAMES[q]
const Q_YIELD := [1, 3, 5, 25]
const Q_COLORS := [Color("8d8d8d"), Color("f0f0f0"), Color("ffd24a"), Color("74f7ff")]
# ore quality odds by system category; Pristine ore is only ever found in the anomalies of Wild space
const Q_WEIGHTS := [[97, 3, 0, 0], [58, 35, 7, 0], [0, 74, 26, 0], [0, 55, 45, 0]]
const ANOMALY_Q_WEIGHTS := [0, 0, 40, 60]

const ORE_ORDER := ["corrite", "ferrox", "lumenite", "cryonite", "vexium", "aurelite", "nyxium", "prismium"]
const ORES := {
	"corrite": {"name": "Corrite", "color": Color("c28f5c"), "value": 2, "desc": "Rusty common ore. Everything is built on it."},
	"ferrox": {"name": "Ferrox", "color": Color("9aa8b8"), "value": 3, "desc": "Dense structural metal."},
	"lumenite": {"name": "Lumenite", "color": Color("5fd8ff"), "value": 5, "desc": "Glows under stress. Used in shields."},
	"cryonite": {"name": "Cryonite", "color": Color("d6fbff"), "value": 7, "desc": "Frozen crystal that never melts."},
	"vexium": {"name": "Vexium", "color": Color("8cff5a"), "value": 10, "desc": "Volatile green ore. Powers weapons."},
	"aurelite": {"name": "Aurelite", "color": Color("ffc93c"), "value": 16, "desc": "Precious gold-like ore from the outer rim."},
	"nyxium": {"name": "Nyxium", "color": Color("d050ff"), "value": 28, "desc": "Dark matter in rock form. Wild space only."},
	"prismium": {"name": "Prismium", "color": Color("ff5fa2"), "value": 60, "desc": "Shifts colour as you look at it. Almost only found in anomalies."},
}
# chance of each ore per system category; rarer ores also scale up with distance from the core
const ORE_WEIGHTS := [
	[80, 14, 6, 0, 0, 0, 0, 0],
	[45, 22, 18, 10, 5, 0, 0, 0],
	[18, 14, 20, 16, 18, 10, 4, 0],
	[8, 8, 14, 14, 20, 18, 14, 4],
]
const ANOMALY_ORE_WEIGHTS := [0, 0, 6, 8, 18, 26, 26, 16]

const SPICE_ORDER := ["ember_pepper", "void_saffron", "starbloom", "nebula_vanilla"]
const SPICES := {
	"ember_pepper": {"name": "Ember Pepper", "color": Color("ff6a3d"), "rarity": 0, "price": {"corrite": 8},
		"desc": "Hot enough to warm a cold reactor. Common."},
	"void_saffron": {"name": "Void Saffron", "color": Color("ffb03d"), "rarity": 1, "price": {"lumenite": 6},
		"desc": "Golden threads picked from drifting space-lilies."},
	"starbloom": {"name": "Starbloom", "color": Color("ff7de9"), "rarity": 2, "price": {"vexium": 6},
		"desc": "Glows faintly. The obelisks seem to like it."},
	"nebula_vanilla": {"name": "Nebula Vanilla", "color": Color("b9a6ff"), "rarity": 3, "price": {"aurelite": 6},
		"desc": "Extremely rare. Smells like the edge of the galaxy."},
}
const SPICE_WEIGHTS := [[85, 15, 0, 0], [60, 32, 8, 0], [20, 38, 30, 12], [25, 35, 28, 12]]

# Ships are drawn from their shape: body size, gap between hull and gun pods, pod height, stripe style.
# guns = weapon slots (gun pods, half on each side); modules = module slots. Costs are deliberately steep:
# the big ships are long-term goals.
const SHIP_ORDER := ["wren", "sparrow", "mule", "prospector", "kestrel", "corsair", "lancer", "aegis", "bastion",
	"specter", "nyx", "leviathan", "seraph", "halberd", "monarch", "behemoth", "ark", "titan"]
const SHIPS := {
	"wren": {"name": "Wren", "class": "Skiff", "hull": 100, "shield": 50, "speed": 330, "turn": 3.0, "cargo": 60,
		"modules": 1, "guns": 2, "energy": 100, "body": Vector2i(9, 11), "gap": 2, "pod": 4, "style": "h",
		"colors": [Color("b8c4d6"), Color("4a7fd0"), Color("7ff0ff")], "bonus": {}, "cost": {},
		"desc": "Your trusty starter skiff. A plain box with a blaster pod on each side."},
	"sparrow": {"name": "Sparrow", "class": "Scout", "hull": 80, "shield": 70, "speed": 480, "turn": 4.6, "cargo": 30,
		"modules": 1, "guns": 2, "energy": 140, "body": Vector2i(5, 9), "gap": 2, "pod": 4, "style": "v",
		"colors": [Color("e6e0c8"), Color("e07a3c"), Color("9dfcff")], "bonus": {"warp": 1.5},
		"cost": {"corrite": 160, "ferrox": 60}, "desc": "Tiny and quick. Warps 50% faster."},
	"mule": {"name": "Mule", "class": "Hauler", "hull": 170, "shield": 60, "speed": 260, "turn": 2.0, "cargo": 240,
		"modules": 2, "guns": 2, "energy": 80, "body": Vector2i(11, 13), "gap": 3, "pod": 4, "style": "x",
		"colors": [Color("c9a46a"), Color("8a5a2e"), Color("7ff0ff")], "bonus": {},
		"cost": {"corrite": 380, "ferrox": 120}, "desc": "Slow and boxy, but it swallows a mountain of ore."},
	"prospector": {"name": "Prospector", "class": "Mining Barge", "hull": 200, "shield": 80, "speed": 240, "turn": 1.8,
		"cargo": 320, "modules": 2, "guns": 2, "energy": 80, "body": Vector2i(13, 13), "gap": 2, "pod": 6, "style": "h",
		"colors": [Color("d9b23c"), Color("3a3a3a"), Color("ffe066")], "bonus": {"mining": 1.5},
		"cost": {"corrite": 550, "ferrox": 220, "lumenite": 110}, "desc": "Built to dig. +50% mining power."},
	"kestrel": {"name": "Kestrel", "class": "Interceptor", "hull": 110, "shield": 110, "speed": 460, "turn": 4.2,
		"cargo": 50, "modules": 2, "guns": 2, "energy": 130, "body": Vector2i(5, 10), "gap": 4, "pod": 4, "style": "v",
		"colors": [Color("e8f0ea"), Color("3fc46a"), Color("9dfcff")], "bonus": {},
		"cost": {"corrite": 240, "lumenite": 120, "vexium": 45}, "desc": "Fast, nimble, and its narrow hull gives the guns wide arcs."},
	"corsair": {"name": "Corsair", "class": "Fighter", "hull": 180, "shield": 140, "speed": 400, "turn": 3.6, "cargo": 70,
		"modules": 3, "guns": 2, "energy": 110, "body": Vector2i(7, 11), "gap": 4, "pod": 6, "style": "x",
		"colors": [Color("2e3440"), Color("e04848"), Color("ffd24a")], "bonus": {"fire": 1.15},
		"cost": {"ferrox": 220, "cryonite": 110, "vexium": 80}, "desc": "A pirate-hunter. +15% fire rate."},
	"lancer": {"name": "Lancer", "class": "Marksman", "hull": 140, "shield": 120, "speed": 360, "turn": 2.8, "cargo": 80,
		"modules": 3, "guns": 2, "energy": 100, "body": Vector2i(5, 15), "gap": 3, "pod": 4, "style": "v",
		"colors": [Color("cfd6e6"), Color("7a5cff"), Color("b9a6ff")], "bonus": {"bolt": 1.4},
		"cost": {"lumenite": 220, "vexium": 140, "aurelite": 50}, "desc": "Long and lean. Shots fly 40% faster and further."},
	"aegis": {"name": "Aegis", "class": "Guardian", "hull": 200, "shield": 420, "speed": 290, "turn": 2.4, "cargo": 90,
		"modules": 3, "guns": 2, "energy": 100, "body": Vector2i(11, 11), "gap": 3, "pod": 4, "style": "h",
		"colors": [Color("dfe9ff"), Color("4fd6ff"), Color("4fd6ff")], "bonus": {},
		"cost": {"cryonite": 240, "vexium": 160, "aurelite": 80}, "desc": "Wrapped in shields. Shrugs off pirate fire."},
	"bastion": {"name": "Bastion", "class": "Gunship", "hull": 380, "shield": 200, "speed": 270, "turn": 1.8, "cargo": 100,
		"modules": 4, "guns": 4, "energy": 90, "body": Vector2i(11, 15), "gap": 3, "pod": 4, "style": "x",
		"colors": [Color("8a8f9c"), Color("b8433a"), Color("ffd27a")], "bonus": {"damage": 1.2},
		"cost": {"corrite": 700, "vexium": 220, "aurelite": 110}, "desc": "A flying fortress with four gun pods. +20% damage."},
	"specter": {"name": "Specter", "class": "Stealth", "hull": 160, "shield": 160, "speed": 440, "turn": 3.8, "cargo": 80,
		"modules": 3, "guns": 2, "energy": 150, "body": Vector2i(7, 12), "gap": 2, "pod": 4, "style": "n",
		"colors": [Color("2a2f3a"), Color("4a5468"), Color("6fffd8")], "bonus": {"stealth": 0.55},
		"cost": {"vexium": 240, "aurelite": 140, "nyxium": 40}, "desc": "Dark plating. Pirates only notice you at about half the range."},
	"nyx": {"name": "Nyx Runner", "class": "Explorer", "hull": 240, "shield": 280, "speed": 420, "turn": 3.4, "cargo": 160,
		"modules": 4, "guns": 2, "energy": 140, "body": Vector2i(7, 11), "gap": 4, "pod": 4, "style": "v",
		"colors": [Color("3c2c55"), Color("b366ff"), Color("f0b0ff")], "bonus": {"probe": 1.5, "warp": 1.25},
		"cost": {"vexium": 240, "aurelite": 160, "nyxium": 70, "nebula_vanilla": 3},
		"desc": "Made for anomaly hunting. Probes fly 50% longer, warps 25% faster."},
	"leviathan": {"name": "Leviathan", "class": "Freighter", "hull": 500, "shield": 300, "speed": 220, "turn": 1.4,
		"cargo": 800, "modules": 5, "guns": 4, "energy": 80, "body": Vector2i(17, 19), "gap": 3, "pod": 4, "style": "x",
		"colors": [Color("6b7080"), Color("d9b23c"), Color("7ff0ff")], "bonus": {},
		"cost": {"ferrox": 800, "aurelite": 320, "nyxium": 110, "prismium": 25}, "desc": "A moving warehouse. 800 cargo, four gun pods."},
	"seraph": {"name": "Seraph", "class": "Flagship", "hull": 320, "shield": 380, "speed": 470, "turn": 3.6, "cargo": 200,
		"modules": 5, "guns": 4, "energy": 180, "body": Vector2i(9, 15), "gap": 4, "pod": 4, "style": "h",
		"colors": [Color("fff0f6"), Color("ff5fa2"), Color("ffe066")], "bonus": {"damage": 1.15, "mining": 1.25},
		"cost": {"aurelite": 320, "nyxium": 220, "prismium": 80, "starbloom": 6},
		"desc": "The finest small ship in the galaxy. +15% damage, +25% mining."},
	"halberd": {"name": "Halberd", "class": "Destroyer", "hull": 700, "shield": 450, "speed": 245, "turn": 1.4, "cargo": 220,
		"modules": 5, "guns": 4, "energy": 120, "body": Vector2i(13, 21), "gap": 3, "pod": 4, "style": "x",
		"colors": [Color("9aa4b4"), Color("2fb8a8"), Color("bff4ff")], "bonus": {"damage": 1.1},
		"cost": {"corrite": 1600, "ferrox": 900, "vexium": 360, "aurelite": 120},
		"desc": "The first real warship. Twice the length of a fighter, four gun pods."},
	"monarch": {"name": "Monarch", "class": "Cruiser", "hull": 1200, "shield": 750, "speed": 215, "turn": 1.1, "cargo": 320,
		"modules": 6, "guns": 6, "energy": 130, "body": Vector2i(17, 27), "gap": 3, "pod": 4, "style": "h",
		"colors": [Color("2c3e66"), Color("e8b84a"), Color("ffe7a3")], "bonus": {"damage": 1.1},
		"cost": {"ferrox": 2400, "cryonite": 800, "vexium": 800, "aurelite": 400, "nyxium": 80},
		"desc": "A cruiser with six gun pods. Pirates think twice."},
	"behemoth": {"name": "Behemoth", "class": "Battlecruiser", "hull": 2000, "shield": 1200, "speed": 190, "turn": 0.9,
		"cargo": 450, "modules": 7, "guns": 8, "energy": 140, "body": Vector2i(21, 33), "gap": 4, "pod": 4, "style": "x",
		"colors": [Color("6a3a40"), Color("d8433a"), Color("ffb36b")], "bonus": {"damage": 1.15},
		"cost": {"ferrox": 4000, "vexium": 1600, "aurelite": 1000, "nyxium": 300, "prismium": 40},
		"desc": "Eight gun pods and armour like a moon."},
	"ark": {"name": "Ark", "class": "Mothership", "hull": 2600, "shield": 1300, "speed": 150, "turn": 0.6, "cargo": 3000,
		"modules": 7, "guns": 6, "energy": 100, "body": Vector2i(27, 37), "gap": 3, "pod": 4, "style": "v",
		"colors": [Color("8a8170"), Color("4a7fd0"), Color("7ff0ff")], "bonus": {"mining": 1.3},
		"cost": {"corrite": 8000, "ferrox": 5000, "aurelite": 1200, "prismium": 80},
		"desc": "A flying city. 3,000 cargo and a mining bay. Painfully slow."},
	"titan": {"name": "Titan", "class": "Dreadnought", "hull": 3400, "shield": 2000, "speed": 165, "turn": 0.7, "cargo": 600,
		"modules": 8, "guns": 10, "energy": 160, "body": Vector2i(25, 43), "gap": 4, "pod": 4, "style": "n",
		"colors": [Color("4a4462"), Color("9b4dff"), Color("e0a0ff")], "bonus": {"damage": 1.25},
		"cost": {"ferrox": 7000, "aurelite": 2000, "nyxium": 800, "prismium": 160, "nebula_vanilla": 10},
		"desc": "The end-game. Ten gun pods, +25% damage, and the size of a station."},
}
# Each weapon is one gun pod's worth: build or buy one per slot you want to fill (Blasters are free).
# pellets/spread = shotgun, pierce = passes through targets, homing = turn rate toward pirates, slow = seconds slowed
# These are the Mk I weapons; _expand_weapons() adds a Mk II and Mk III of each to WEAPONS (see WEAPON_TIERS).
const WEAPON_BASE_ORDER := ["twin_blasters", "mining_lasers", "scatter_guns", "pulse_cannons", "ion_repeaters",
	"cryo_projectors", "seeker_darts", "rail_drivers", "deep_core_drills", "nova_lances", "prism_cannons"]
const WEAPON_BASE := {
	"twin_blasters": {"name": "Blaster", "damage": 6.0, "rate": 4.0, "speed": 950.0, "mining": 1.0, "life": 1.1,
		"color": Color("ffe066"), "size": Vector2(2, 6), "cost": {}, "desc": "The standard gun pod. Free and unlimited - every empty slot has one."},
	"mining_lasers": {"name": "Mining Lasers", "damage": 3.0, "rate": 7.0, "speed": 1100.0, "mining": 2.2, "life": 0.7,
		"color": Color("66ffcc"), "size": Vector2(2, 8), "cost": {"corrite": 70, "lumenite": 15},
		"desc": "Chews through rock up close. Weak against ships."},
	"scatter_guns": {"name": "Scatter Guns", "damage": 4.0, "rate": 1.6, "speed": 820.0, "mining": 0.6, "life": 0.6,
		"pellets": 5, "spread": 22.0, "color": Color("ffb36b"), "size": Vector2(3, 3), "cost": {"corrite": 90, "ferrox": 45},
		"desc": "Five pellets per shot. Brutal up close."},
	"pulse_cannons": {"name": "Pulse Cannons", "damage": 16.0, "rate": 2.2, "speed": 800.0, "mining": 1.2, "life": 1.2,
		"color": Color("ff8a3d"), "size": Vector2(4, 6), "cost": {"corrite": 105, "lumenite": 40, "vexium": 15},
		"desc": "Slow, heavy bolts that hurt pirates."},
	"ion_repeaters": {"name": "Ion Repeaters", "damage": 7.0, "rate": 10.0, "speed": 1050.0, "mining": 0.8, "life": 1.0,
		"color": Color("7aa8ff"), "size": Vector2(2, 5), "cost": {"vexium": 55, "cryonite": 25}, "desc": "A storm of fast ion bolts."},
	"cryo_projectors": {"name": "Cryo Projectors", "damage": 5.0, "rate": 5.0, "speed": 900.0, "mining": 0.8, "life": 0.9,
		"slow": 1.5, "color": Color("bff4ff"), "size": Vector2(3, 5), "cost": {"cryonite": 60, "lumenite": 30},
		"desc": "Freezing bolts. Pirates that are hit slow to half speed."},
	"seeker_darts": {"name": "Seeker Darts", "damage": 9.0, "rate": 2.5, "speed": 620.0, "mining": 0.5, "life": 2.2,
		"homing": 4.0, "color": Color("ff66aa"), "size": Vector2(2, 5), "cost": {"vexium": 45, "aurelite": 25},
		"desc": "Darts that curve toward the nearest pirate."},
	"rail_drivers": {"name": "Rail Drivers", "damage": 28.0, "rate": 1.1, "speed": 1800.0, "mining": 2.0, "life": 1.2,
		"pierce": 3, "color": Color("e8f6ff"), "size": Vector2(2, 16), "cost": {"vexium": 75, "aurelite": 45},
		"desc": "Hypersonic slugs that punch through up to 3 targets."},
	"deep_core_drills": {"name": "Deep-Core Drills", "damage": 4.0, "rate": 6.0, "speed": 700.0, "mining": 5.0, "life": 0.35,
		"color": Color("ffd24a"), "size": Vector2(4, 4), "cost": {"aurelite": 45, "nyxium": 15, "cryonite": 45},
		"desc": "Very short range, insane mining power."},
	"nova_lances": {"name": "Nova Lances", "damage": 34.0, "rate": 1.4, "speed": 1400.0, "mining": 3.0, "life": 1.3,
		"pierce": 1, "color": Color("ff66ff"), "size": Vector2(3, 14), "cost": {"aurelite": 55, "nyxium": 20, "starbloom": 5},
		"desc": "Long-range lances of pure Nyxium light."},
	"prism_cannons": {"name": "Prism Cannons", "damage": 22.0, "rate": 3.0, "speed": 1200.0, "mining": 3.0, "life": 1.2,
		"pellets": 3, "spread": 10.0, "pierce": 1, "color": Color("ff5fa2"), "size": Vector2(3, 8),
		"cost": {"nyxium": 60, "prismium": 30}, "desc": "Split a beam of Prismium into three piercing rays."},
}

# Three marks of every weapon. Each mark up hits harder, fires faster and mines better, takes far more
# materials to build, and uses up one of the mark below it from your stores (the free Blaster aside).
const WEAPON_TIERS := [
	{"suffix": "", "damage": 1.0, "rate": 1.0, "mining": 1.0, "cost": 1.0},
	{"suffix": " Mk II", "damage": 1.45, "rate": 1.12, "mining": 1.35, "cost": 3.0},
	{"suffix": " Mk III", "damage": 2.1, "rate": 1.25, "mining": 1.8, "cost": 8.0},
]
var WEAPONS := {}  # every weapon, all three marks: Mk I under its base id, then "<id>_mk2" and "<id>_mk3"
var WEAPON_ORDER := []

const MODULE_ORDER := ["cargo_pod", "cargo_bay", "shield_booster", "shield_capacitor", "hull_plating", "bulkheads",
	"afterburner", "gyro", "boost_cells", "tractor_beam", "repair_nanites", "mining_amp", "overcharger", "targeting_cpu",
	"stealth_plating", "probe_kit", "warp_core", "salvage_rig"]
const MODULES := {
	"cargo_pod": {"name": "Cargo Pod", "desc": "+60 cargo space.", "cost": {"corrite": 75}},
	"cargo_bay": {"name": "Cargo Bay II", "desc": "+160 cargo space.", "cost": {"ferrox": 120, "cryonite": 30}},
	"shield_booster": {"name": "Shield Booster", "desc": "+60 max shield.", "cost": {"corrite": 60, "lumenite": 30}},
	"shield_capacitor": {"name": "Shield Capacitor", "desc": "Shields start recharging sooner and twice as fast.",
		"cost": {"lumenite": 60, "cryonite": 30}},
	"hull_plating": {"name": "Hull Plating", "desc": "+80 max hull.", "cost": {"corrite": 120, "ferrox": 45}},
	"bulkheads": {"name": "Reinforced Bulkheads", "desc": "Take 20% less damage.", "cost": {"ferrox": 135, "vexium": 30}},
	"afterburner": {"name": "Afterburner", "desc": "+25% top speed.", "cost": {"lumenite": 45, "vexium": 15}},
	"gyro": {"name": "Gyro Stabilizer", "desc": "+40% turn rate.", "cost": {"ferrox": 60, "lumenite": 30}},
	"boost_cells": {"name": "Boost Cells", "desc": "+60% boost energy and faster recharge.", "cost": {"lumenite": 45, "cryonite": 40}},
	"tractor_beam": {"name": "Tractor Beam", "desc": "Pulls nearby ore chunks toward your ship.", "cost": {"lumenite": 40, "vexium": 25}},
	"repair_nanites": {"name": "Repair Nanites", "desc": "Slowly repairs your hull (3 per second).",
		"cost": {"vexium": 30, "aurelite": 25, "starbloom": 5}},
	"mining_amp": {"name": "Mining Amplifier", "desc": "+50% mining power.", "cost": {"ferrox": 60, "vexium": 30}},
	"overcharger": {"name": "Overcharger", "desc": "+20% fire rate.", "cost": {"vexium": 60, "aurelite": 25}},
	"targeting_cpu": {"name": "Targeting Computer", "desc": "Shots fly 30% faster and further.", "cost": {"lumenite": 60, "aurelite": 15}},
	"stealth_plating": {"name": "Stealth Plating", "desc": "Pirates notice you 35% later.", "cost": {"cryonite": 60, "nyxium": 15}},
	"probe_kit": {"name": "Probe Kit", "desc": "Probes fly twice as long and 50% faster.", "cost": {"lumenite": 60, "ferrox": 30}},
	"warp_core": {"name": "Warp Core", "desc": "Warps and jumps charge twice as fast.", "cost": {"cryonite": 45, "aurelite": 30}},
	"salvage_rig": {"name": "Salvage Rig", "desc": "Wrecks give double loot.", "cost": {"ferrox": 105, "corrite": 60}},
}

# hp/speed/dmg are base values (scaled by CAT_DANGER). keep = preferred distance, sight = aggro range.
const ENEMIES := {
	"raider": {"name": "Raider", "hp": 45.0, "speed": 270.0, "damage": 5.0, "rate": 1.6, "bolt": 720.0, "range": 780.0,
		"keep": 330.0, "sight": 1300.0, "credits": 15, "loot": 3},
	"gunner": {"name": "Gunner", "hp": 110.0, "speed": 210.0, "damage": 8.0, "rate": 1.3, "bolt": 680.0, "range": 700.0,
		"keep": 300.0, "sight": 1200.0, "credits": 25, "loot": 5, "pellets": 2},
	"sniper": {"name": "Sniper", "hp": 60.0, "speed": 240.0, "damage": 14.0, "rate": 0.6, "bolt": 1300.0, "range": 1250.0,
		"keep": 760.0, "sight": 1500.0, "credits": 22, "loot": 3},
	"swarmer": {"name": "Swarmer", "hp": 22.0, "speed": 420.0, "damage": 3.0, "rate": 2.5, "bolt": 760.0, "range": 600.0,
		"keep": 170.0, "sight": 1300.0, "credits": 6, "loot": 1},
	"captain": {"name": "Pirate Captain", "hp": 650.0, "speed": 230.0, "damage": 10.0, "rate": 2.6, "bolt": 800.0,
		"range": 900.0, "keep": 380.0, "sight": 1600.0, "credits": 250, "loot": 18, "pellets": 3, "boss": true},
	"sentinel": {"name": "Sentinel", "hp": 160.0, "speed": 170.0, "damage": 8.0, "rate": 2.0, "bolt": 780.0, "range": 850.0,
		"keep": 360.0, "sight": 1100.0, "credits": 45, "loot": 6},
}

# [id, name, description, stat, goal]
const ACHIEVEMENTS := [
	["first_rock", "First Rock", "Collect your first piece of ore.", "ore", 1],
	["rock_hound", "Rock Hound", "Collect 500 ore.", "ore", 500],
	["strip_miner", "Strip Miner", "Collect 5,000 ore.", "ore", 5000],
	["smelter", "Smelter", "Refine 250 materials.", "refined", 250],
	["flawless", "Flawless", "Collect a piece of Pristine ore.", "pristine", 1],
	["prismatic", "Prismatic", "Collect Prismium ore.", "prismium", 1],
	["first_blood", "First Blood", "Destroy a pirate.", "kills", 1],
	["ace", "Ace Pilot", "Destroy 25 pirates.", "kills", 25],
	["scourge", "Scourge of Pirates", "Destroy 150 pirates.", "kills", 150],
	["mutiny", "Mutiny", "Destroy a Pirate Captain.", "captains", 1],
	["gatecrasher", "Gatecrasher", "Destroy an anomaly Sentinel.", "sentinels", 1],
	["wanderer", "Wanderer", "Visit 10 systems.", "systems", 10],
	["voyager", "Voyager", "Visit 50 systems.", "systems", 50],
	["cartographer", "Cartographer", "Visit 200 systems.", "systems", 200],
	["gate_runner", "Gate Runner", "Make 100 stargate jumps.", "jumps", 100],
	["into_the_wild", "Into the Wild", "Enter a Wild system.", "wild", 1],
	["surveyor", "Surveyor", "Scan 25 planets with probes.", "scans", 25],
	["something_strange", "Something Strange", "Find an anomaly.", "anomalies", 1],
	["anomaly_hunter", "Anomaly Hunter", "Find 15 anomalies.", "anomalies", 15],
	["looking_glass", "Through the Looking Glass", "Travel through a wormhole.", "wormholes", 1],
	["scavenger", "Scavenger", "Salvage 10 wrecks.", "salvaged", 10],
	["devout", "Devout", "Make 5 offerings at obelisks.", "offerings", 5],
	["shipwright", "Shipwright", "Build a new ship.", "ships_built", 1],
	["fleet_admiral", "Fleet Admiral", "Own 6 ships.", "ships_owned", 6],
	["big_boat", "Big Boat", "Own a Leviathan.", "leviathan", 1],
	["contractor", "Contractor", "Complete 10 missions.", "missions", 10],
	["tycoon", "Tycoon", "Earn 25,000 credits.", "earned", 25000],
	["phoenix", "Phoenix", "Get your ship destroyed.", "deaths", 1],
]

const PLANET_TYPES := ["rocky", "ice", "gas", "lava", "ocean", "toxic", "desert"]
const PLANET_COLORS := {
	"rocky": Color("a08a74"), "ice": Color("a6c8e0"), "gas": Color("d9a86a"), "lava": Color("ff5a1f"),
	"ocean": Color("1f66a8"), "toxic": Color("7fa62a"), "desert": Color("dbb57a"),
}
const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII"]
const NAME_A := ["Vel", "Or", "Kar", "Thal", "Ny", "Ser", "Dra", "Ix", "Vo", "Ka", "Lu", "Zan", "Mer", "Ash", "Cy",
	"Pha", "Rho", "Tor", "El", "Quin", "Bel", "Sol", "Aer", "Gal", "Hes", "Jun", "Mor", "Nex", "Os", "Pyr", "Ul",
	"Vey", "Wyn", "Zor", "Cal", "Fen", "Ith", "Brae"]
const NAME_B := ["ra", "on", "is", "ex", "ium", "ar", "os", "ane", "ith", "el", "or", "us", "ix", "eon", "a", "yn",
	"oth", "ae", "ren", "dor", "ka", "vin"]

# --- player state (reset by new_game) ---
var credits := 0
var materials := {}  # refined ore id -> amount
var cargo := {}  # "ore_id:quality" -> raw ore count
var spices := {}
var probes := 0
var owned_ships := ["wren"]
var ship_id := "wren"
const BLASTER := "twin_blasters"  # the free default gun pod
var weapon_stock := {}  # weapons built/bought but not mounted: id -> count
var loadouts := {}  # ship id -> weapon id in each gun slot
var module_stock := {}  # unequipped modules: id -> count
var modules_equipped := []
var blessings := {}  # id -> seconds left
var stats := {}
var unlocked := {}  # achievement id -> true
var missions := []  # accepted missions
var boards := {}  # "sys:loc" -> missions offered at that station
var salvaged := []  # [sys, loc] pairs whose wreck has been looted
# station furnaces: "sys:loc" -> {name, queue: [[ore, quality, count]], progress (s into the current piece), output: {ore: n}}
var refineries := {}
var dirty := false  # something changed since the last save
var playtime := 0.0
var no_save := false  # set by the screenshot test so it never touches the player's save
var save_path := SAVE_PATH
var save_slot := "pilot"  # which save slot is in use
var admin := false  # playing the admin slot
var god := false  # admin: can't be hurt

# --- galaxy ---
var systems := []
var anomalies := []  # {"sys": system id, "loc": location index}
var current_system := 0
var current_loc := 0
var route_target := -1
var gen_ms := 0


func _init() -> void:
	_expand_weapons()


## WEAPONS: every base weapon as Mk I, plus a Mk II and Mk III built from the mark below.
func _expand_weapons() -> void:
	for id in WEAPON_BASE_ORDER:
		var base: Dictionary = WEAPON_BASE[id]
		var prev := ""
		for t in WEAPON_TIERS.size():
			var tier: Dictionary = WEAPON_TIERS[t]
			var wid: String = id if t == 0 else "%s_mk%d" % [id, t + 1]
			var w: Dictionary = base.duplicate(true)
			w["tier"] = t + 1
			w["base"] = id
			w.name = base.name + tier.suffix
			w.damage = base.damage * tier.damage
			w.rate = base.rate * tier.rate
			w.mining = base.mining * tier.mining
			w.size = Vector2(base.size) * (1.0 + 0.15 * t)
			w.color = Color(base.color).lightened(0.12 * t)
			if t > 0:
				var cost := {}
				for k in base.cost:
					cost[k] = ceili(base.cost[k] * tier.cost)
				if base.cost.is_empty():  # the Blaster (free at Mk I)
					cost = {"corrite": 60} if t == 1 else {"corrite": 240, "ferrox": 60}
				if id != BLASTER or t > 1:
					cost["w:" + prev] = 1
				w.cost = cost
				w.desc = "%s Mark %s: harder hitting and faster. Built from a %s." % [base.desc, ["I", "II", "III"][t],
					WEAPONS[prev].name]
			WEAPONS[wid] = w
			WEAPON_ORDER.append(wid)
			prev = wid

func _ready() -> void:
	# the user's layout: W/S pitch the nose, Q/E turn, A/D roll, R/F work the throttle
	_key("move_up", [KEY_R])
	_key("move_down", [KEY_F])
	_key("yaw_left", [KEY_Q, KEY_LEFT])
	_key("yaw_right", [KEY_E, KEY_RIGHT])
	_key("pitch_up", [KEY_W, KEY_UP])
	_key("pitch_down", [KEY_S, KEY_DOWN])
	_key("roll_left", [KEY_A])
	_key("roll_right", [KEY_D])
	_key("warp_menu", [KEY_SPACE])
	_key("galaxy_map", [KEY_M])
	_key("system_map", [KEY_N])
	_key("interact", [KEY_G, KEY_4])
	_key("close", [KEY_ESCAPE])
	_key("inventory", [KEY_I, KEY_TAB])
	_key("debug", [KEY_F3])
	_key("cut_throttle", [KEY_X])
	_key("boost", [KEY_SHIFT])
	_key("fullscreen", [KEY_F11])
	_key("approach", [KEY_1])
	_key("orbit", [KEY_2])
	_key("warp_to", [KEY_3])
	_key("scan", [KEY_V])
	_key("photo", [KEY_F1])
	_key("admin", [KEY_F8])
	_key("command", [KEY_C])
	_key("collect", [KEY_O])
	_key("cruise", [KEY_5])
	_key("fitting", [KEY_L])
	if not InputMap.has_action("fire"):
		InputMap.add_action("fire")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("fire", mb)
	generate_galaxy()
	changed.connect(func(): dirty = true)


func _key(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _process(delta: float) -> void:
	playtime += delta
	tick_refineries(delta)
	for id in blessings.keys():
		blessings[id] -= delta
		if blessings[id] <= 0.0:
			blessings.erase(id)
			say("A blessing has faded.", Color("9a8fb5"))
			changed.emit()


func say(text: String, color := Color.WHITE) -> void:
	notify.emit(text, color)


func new_game() -> void:
	credits = 0
	materials = {}
	cargo = {}
	spices = {}
	probes = 0
	owned_ships = ["wren"]
	ship_id = "wren"
	weapon_stock = {}
	loadouts = {}
	module_stock = {}
	modules_equipped = []
	blessings = {}
	stats = {}
	unlocked = {}
	missions = []
	boards = {}
	salvaged = []
	refineries = {}
	playtime = 0.0
	route_target = -1
	current_system = 0
	current_loc = 0
	generate_galaxy()
	changed.emit()


# ---------------------------------------------------------------- galaxy

func generate_galaxy() -> void:
	var started := Time.get_ticks_msec()
	var rng := RandomNumberGenerator.new()
	rng.seed = GALAXY_SEED
	systems.clear()
	anomalies.clear()
	# scatter systems over a disc, never closer than MIN_SPACING (a grid keeps the checks local)
	var pts: Array[Vector2] = [Vector2.ZERO]
	var grid := {Vector2i.ZERO: [0]}
	var tries := 0
	while pts.size() < SYSTEM_COUNT and tries < 60000:
		tries += 1
		var p := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * GALAXY_RADIUS
		var cell := _cell(p, MIN_SPACING)
		var ok := true
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				for j in grid.get(cell + Vector2i(dx, dy), []):
					if pts[j].distance_squared_to(p) < MIN_SPACING * MIN_SPACING:
						ok = false
		if ok:
			grid[cell] = grid.get(cell, []) + [pts.size()]
			pts.append(p)
	var used := {}
	for i in pts.size():
		var d := pts[i].length() / GALAXY_RADIUS
		var score := d + rng.randf_range(-0.05, 0.05)
		var cat := CAT_PURPLE
		if i == 0 or score < CAT_EDGES[0]:
			cat = CAT_BLUE
		elif score < CAT_EDGES[1]:
			cat = CAT_GREEN
		elif score < CAT_EDGES[2]:
			cat = CAT_RED
		var nm := "The Core" if i == 0 else _unique_name(rng, used)
		systems.append({"id": i, "name": nm, "initials": _initials(nm), "pos": pts[i], "cat": cat,
			"depth": d, "links": [], "locs": [], "visited": i == 0})
	_link_systems(rng)
	for sys in systems:
		_gen_locations(sys, rng)
	_setup_core()
	_pair_wormholes(rng)
	gen_ms = Time.get_ticks_msec() - started


func _cell(p: Vector2, size: float) -> Vector2i:
	return Vector2i(floori(p.x / size), floori(p.y / size))


func _root(parent: Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


func _word(rng: RandomNumberGenerator) -> String:
	return NAME_A[rng.randi() % NAME_A.size()] + NAME_B[rng.randi() % NAME_B.size()]


func _unique_name(rng: RandomNumberGenerator, used: Dictionary) -> String:
	while true:
		var nm := _word(rng) + " " + _word(rng)
		if not used.has(nm):
			used[nm] = true
			return nm
	return ""


func _initials(nm: String) -> String:
	var out := ""
	for w in nm.split(" "):
		out += w.substr(0, 1).to_upper()
	return out


func _link(a: int, b: int) -> void:
	if a == b or systems[a].links.has(b):
		return
	systems[a].links.append(b)
	systems[b].links.append(a)


func _link_systems(rng: RandomNumberGenerator) -> void:
	var n := systems.size()
	var grid := {}
	for i in n:
		var c := _cell(systems[i].pos, LINK_RANGE)
		if not grid.has(c):
			grid[c] = []
		grid[c].append(i)
	# every pair of nearby systems is a candidate stargate
	var edges := []
	for i in n:
		var pi: Vector2 = systems[i].pos
		var c := _cell(pi, LINK_RANGE)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				for j in grid.get(c + Vector2i(dx, dy), []):
					if j > i:
						var d := pi.distance_to(systems[j].pos)
						if d < LINK_RANGE:
							edges.append([d, i, j])
	edges.sort_custom(func(a, b): return a[0] < b[0])
	# shortest gates first, skipping any that would close a loop: a spanning tree (Kruskal)
	var parent := range(n)
	var extra := []
	for e in edges:
		var ra := _root(parent, e[1])
		var rb := _root(parent, e[2])
		if ra != rb:
			parent[ra] = rb
			_link(e[1], e[2])
		else:
			extra.append(e)
	# any system stranded out of range gets a gate to the nearest connected system
	for i in n:
		var main_root := _root(parent, 0)
		if _root(parent, i) == main_root:
			continue
		var best := -1
		var bd := INF
		for j in n:
			if _root(parent, j) == main_root:
				var d: float = systems[i].pos.distance_to(systems[j].pos)
				if d < bd:
					bd = d
					best = j
		_link(i, best)
		parent[_root(parent, i)] = main_root
	# a few shortcuts so the map has loops
	for e in extra:
		var a: int = e[1]
		var b: int = e[2]
		if e[0] < 150.0 and rng.randf() < 0.3 and systems[a].links.size() < 5 and systems[b].links.size() < 5:
			_link(a, b)


func _new_loc(kind: String, nm: String, p: Vector2) -> Dictionary:
	return {"kind": kind, "name": nm, "map_pos": p, "scanned": kind != "planet", "found": kind != "anomaly",
		"ore": false, "station": false, "refinery": false, "obelisk": false, "spice": false, "pirates": false,
		"wreck": false, "planet_type": "rocky", "seed": 0, "gate_to": -1, "anom": -1, "wormhole": -1}


func _gen_locations(sys: Dictionary, rng: RandomNumberGenerator) -> void:
	var cat: int = sys.cat
	var n := 4 if sys.id == 0 else rng.randi_range(3, 7)
	var spots := []
	for i in n:
		var r := 0.22 + 0.7 * (i + 0.5) / n
		var p := Vector2.ZERO
		for _t in 12:
			p = Vector2.from_angle(rng.randf() * TAU) * r
			var clear := true
			for s in spots:
				if s.distance_to(p) < 0.2:
					clear = false
			if clear:
				break
		spots.append(p)
		var loc := _new_loc("planet", "%s %s" % [sys.name, ROMAN[i]], p)
		loc.planet_type = PLANET_TYPES[rng.randi() % PLANET_TYPES.size()]
		loc.seed = rng.randi()
		loc.ore = rng.randf() < 0.6
		loc.station = rng.randf() < [0.45, 0.3, 0.0, 0.12][cat]
		loc.refinery = loc.station and rng.randf() < [0.85, 0.6, 0.0, 0.5][cat]
		loc.obelisk = rng.randf() < [0.0, 0.0, 0.2, 0.22][cat]  # offerings only out in red and Wild space
		loc.spice = rng.randf() < [0.08, 0.15, 0.35, 0.25][cat]
		loc.wreck = rng.randf() < [0.1, 0.2, 0.35, 0.45][cat]
		loc.pirates = rng.randf() < PIRATE_CHANCE[cat] and not (loc.station and cat < CAT_PURPLE)
		sys.locs.append(loc)
	if cat <= CAT_GREEN and not sys.locs.any(func(l): return l.station):
		var l: Dictionary = sys.locs[rng.randi() % n]
		l.station = true
		l.refinery = rng.randf() < 0.7
		l.pirates = false
	# stargates sit on the edge of the system map, pointing at the system they lead to
	for other in sys.links:
		var o: Dictionary = systems[other]
		var dir: Vector2 = (o.pos - sys.pos).normalized()
		var gate := _new_loc("gate", "Stargate: %s" % o.name, dir * 1.08)
		gate.gate_to = other
		gate.seed = rng.randi()
		sys.locs.append(gate)
	if cat == CAT_PURPLE:
		for _k in rng.randi_range(1, 3):
			var p := Vector2.ZERO
			for _t in 20:
				p = Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.15, 0.95)
				var clear := true
				for s in spots:
					if s.distance_to(p) < 0.14:
						clear = false
				if clear:
					break
			spots.append(p)
			var aid := anomalies.size()
			var loc := _new_loc("anomaly", "Anomaly %s%d" % [sys.initials, aid + 1], p)
			loc.ore = true
			loc.anom = aid
			loc.seed = rng.randi()
			loc.pirates = true  # anomalies are always guarded by Sentinels
			loc.wreck = rng.randf() < 0.5
			anomalies.append({"sys": sys.id, "loc": sys.locs.size()})
			sys.locs.append(loc)


func _setup_core() -> void:
	var core: Dictionary = systems[0]
	var names := ["Core Station", "Core Belt", "Halden's Rest", "Rustfall Drift"]
	for i in 4:
		var l: Dictionary = core.locs[i]
		l.name = names[i]
		l.scanned = true
		for f in ["ore", "station", "refinery", "obelisk", "spice", "pirates", "wreck"]:
			l[f] = false
	core.locs[0].station = true
	core.locs[0].refinery = true
	core.locs[0].planet_type = "ocean"
	core.locs[1].ore = true
	core.locs[1].planet_type = "rocky"
	core.locs[2].ore = true
	core.locs[2].spice = true
	core.locs[2].wreck = true
	core.locs[3].ore = true
	core.locs[3].wreck = true


func _pair_wormholes(rng: RandomNumberGenerator) -> void:
	var cands := []
	for a in anomalies.size():
		if rng.randf() < 0.5:
			cands.append(a)
	for i in range(cands.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = cands[i]
		cands[i] = cands[j]
		cands[j] = t
	while cands.size() >= 2:
		var a: int = cands.pop_back()
		var pa: Vector2 = systems[anomalies[a].sys].pos
		for k in cands.size():
			var b: int = cands[k]
			if pa.distance_to(systems[anomalies[b].sys].pos) > GALAXY_RADIUS * 0.7:
				cands.remove_at(k)
				anom_loc(a).wormhole = b
				anom_loc(b).wormhole = a
				break


func anom_loc(aid: int) -> Dictionary:
	var a: Dictionary = anomalies[aid]
	return systems[a.sys].locs[a.loc]


func gate_index(sys_id: int, to_id: int) -> int:
	var locs: Array = systems[sys_id].locs
	for i in locs.size():
		if locs[i].kind == "gate" and locs[i].gate_to == to_id:
			return i
	return 0


func find_path(a: int, b: int) -> Array:
	var prev := {a: -1}
	var queue := [a]
	while not queue.is_empty():
		var u: int = queue.pop_front()
		if u == b:
			break
		for v in systems[u].links:
			if not prev.has(v):
				prev[v] = u
				queue.append(v)
	if not prev.has(b):
		return []
	var path := []
	var c := b
	while c != a:
		path.push_front(c)
		c = prev[c]
	return path


## Systems between min_j and max_j jumps from `from`, as {system id: jumps}.
func systems_within(from: int, min_j: int, max_j: int) -> Dictionary:
	var dist := {from: 0}
	var queue := [from]
	var out := {}
	while not queue.is_empty():
		var u: int = queue.pop_front()
		if dist[u] >= min_j:
			out[u] = dist[u]
		if dist[u] >= max_j:
			continue
		for v in systems[u].links:
			if not dist.has(v):
				dist[v] = dist[u] + 1
				queue.append(v)
	return out


func route_path() -> Array:
	if route_target < 0 or route_target == current_system:
		return []
	return find_path(current_system, route_target)


func loc_summary(l: Dictionary) -> String:
	if l.kind == "planet" and not l.scanned:
		return "Unscanned"
	var parts := []
	if l.station:
		parts.append("Station" + (" + Refinery" if l.refinery else ""))
	if l.ore:
		parts.append("Ore Field")
	if l.obelisk:
		parts.append("Obelisk")
	if l.spice:
		parts.append("Spice Stand")
	if l.wreck:
		parts.append("Wreck")
	if l.kind == "anomaly" and l.wormhole >= 0:
		parts.append("Wormhole")
	if l.pirates:
		parts.append("PIRATES")
	if parts.is_empty():
		return "Empty space"
	return ", ".join(parts)


func pick_weighted(weights: Array, rng: RandomNumberGenerator = null) -> int:
	var total := 0.0
	for w in weights:
		total += w
	var r: float = (rng.randf() if rng else randf()) * total
	for i in weights.size():
		r -= weights[i]
		if r < 0.0:
			return i
	return weights.size() - 1


## Returns [ore_id, quality] for a new rock in this system.
func roll_ore(sys: Dictionary, anomaly: bool) -> Array:
	var w: Array
	if anomaly:
		w = ANOMALY_ORE_WEIGHTS.duplicate()
	else:
		w = ORE_WEIGHTS[sys.cat].duplicate()
		for t in range(1, w.size()):
			w[t] = w[t] * (1.0 + sys.depth * t * 0.5)
	var ore: String = ORE_ORDER[pick_weighted(w)]
	var q := pick_weighted(ANOMALY_Q_WEIGHTS if anomaly and sys.cat == CAT_PURPLE else Q_WEIGHTS[sys.cat])
	return [ore, q]


func spice_stock(l: Dictionary, sys: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = l.seed + 77
	var out := []
	for i in 3:
		var id: String = SPICE_ORDER[pick_weighted(SPICE_WEIGHTS[sys.cat], rng)]
		if not out.has(id):
			out.append(id)
	return out


# ---------------------------------------------------------------- inventory

func item_name(id: String) -> String:
	if id == "credits":
		return "Credits"
	if id.begins_with("w:"):
		return WEAPONS[id.substr(2)].name
	if ORES.has(id):
		return ORES[id].name
	if SPICES.has(id):
		return SPICES[id].name
	return id


func item_color(id: String) -> Color:
	if id == "credits":
		return Color("ffd24a")
	if id.begins_with("w:"):
		return WEAPONS[id.substr(2)].color
	if ORES.has(id):
		return ORES[id].color
	if SPICES.has(id):
		return SPICES[id].color
	return Color.WHITE


## How many you have of a cost item: credits, a material, a spice, or ("w:<id>") a weapon in your stores.
func have(id: String) -> int:
	if id == "credits":
		return credits
	if id.begins_with("w:"):
		return weapon_stock.get(id.substr(2), 0)
	if ORES.has(id):
		return materials.get(id, 0)
	return spices.get(id, 0)


func give(id: String, n: int) -> void:
	if id == "credits":
		credits += n
	elif id.begins_with("w:"):
		weapon_stock[id.substr(2)] = weapon_stock.get(id.substr(2), 0) + n
	elif ORES.has(id):
		materials[id] = materials.get(id, 0) + n
	else:
		spices[id] = spices.get(id, 0) + n


func add_credits(n: int) -> void:
	credits += n
	bump("earned", n)
	changed.emit()


func can_afford(cost: Dictionary) -> bool:
	if admin:
		return true  # everything is free on the admin save
	for id in cost:
		if have(id) < cost[id]:
			return false
	return true


func pay(cost: Dictionary) -> void:
	if admin:
		return
	for id in cost:
		give(id, -cost[id])


func cargo_used() -> int:
	var n := 0
	for k in cargo:
		n += cargo[k]
	return n


func add_cargo(ore: String, q: int, n: int) -> bool:
	if cargo_used() + n > stats_ship().cargo:
		return false
	var key := "%s:%d" % [ore, q]
	cargo[key] = cargo.get(key, 0) + n
	event("ore", {"ore": ore, "q": q, "n": n})
	changed.emit()
	return true


func refine_time(ore: String, q: int) -> float:
	return REFINE_TIME[q] * (1.0 + ORE_ORDER.find(ore) * 0.12)


## Mining power needed to break one piece of this ore off a rock.
func hardness(ore: String) -> float:
	return MINE_COST * (1.0 + ORE_ORDER.find(ore) * HARDNESS_PER_TIER)


func refinery(key: String, station_name := "") -> Dictionary:
	if not refineries.has(key):
		refineries[key] = {"name": station_name, "queue": [], "progress": 0.0, "output": {}}
	if station_name != "":
		refineries[key].name = station_name
	return refineries[key]


## Move one cargo stack into a station's furnace queue.
func load_ore(key: String, station_name: String, cargo_key: String) -> void:
	var n: int = cargo.get(cargo_key, 0)
	if n <= 0:
		return
	var parts: PackedStringArray = cargo_key.split(":")
	var q: Array = refinery(key, station_name).queue
	if not q.is_empty() and q[-1][0] == parts[0] and q[-1][1] == int(parts[1]):
		q[-1][2] += n
	else:
		q.append([parts[0], int(parts[1]), n])
	cargo.erase(cargo_key)
	changed.emit()


func load_all(key: String, station_name: String) -> void:
	for k in cargo.keys():
		load_ore(key, station_name, k)


## Furnaces smelt one piece at a time, like Minecraft, and keep going wherever you are.
func tick_refineries(delta: float) -> void:
	for key in refineries:
		var r: Dictionary = refineries[key]
		if r.queue.is_empty():
			r.progress = 0.0
			continue
		r.progress += delta
		while not r.queue.is_empty():
			var item: Array = r.queue[0]
			var need := refine_time(item[0], item[1])
			if r.progress < need:
				break
			r.progress -= need
			item[2] -= 1
			r.output[item[0]] = r.output.get(item[0], 0) + Q_YIELD[item[1]]
			bump("refined", Q_YIELD[item[1]])
			if item[2] <= 0:
				r.queue.pop_front()
		if r.queue.is_empty():
			r.progress = 0.0
			dirty = true


func refinery_seconds_left(r: Dictionary) -> float:
	var t := 0.0
	for item in r.queue:
		t += refine_time(item[0], item[1]) * item[2]
	return maxf(0.0, t - r.progress)


## Take finished materials out of a station's furnace. Returns what was collected.
func collect(key: String) -> Dictionary:
	if not refineries.has(key):
		return {}
	var out: Dictionary = refineries[key].output
	refineries[key].output = {}
	for id in out:
		give(id, out[id])
	if not out.is_empty():
		changed.emit()
	return out

func jettison(key: String) -> void:
	var parts: PackedStringArray = key.split(":")
	say("Jettisoned %d %s." % [cargo.get(key, 0), ore_label(parts[0], int(parts[1]))], Color("8a94a8"))
	cargo.erase(key)
	changed.emit()


func sell_price(ore: String, cat: int) -> int:
	return maxi(1, roundi(ORES[ore].value * CAT_PRICE[cat]))


func buy_price(ore: String) -> int:
	return ORES[ore].value * 3


func sell(ore: String, n: int, cat: int) -> void:
	n = mini(n, have(ore))
	if n <= 0:
		return
	materials[ore] -= n
	add_credits(n * sell_price(ore, cat))
	say("Sold %d %s for %d credits." % [n, ORES[ore].name, n * sell_price(ore, cat)], Color("ffd24a"))


func buy(id: String, n: int) -> bool:
	var price := 0 if admin else (PROBE_PRICE * n if id == "probe" else buy_price(id) * n)
	if credits < price:
		return false
	credits -= price
	if id == "probe":
		probes += n
	else:
		give(id, n)
	changed.emit()
	return true


## What building something takes. The tables' material amounts are multiplied up by BUILD_COST_MULT:
## anything worth having takes a lot of ore (probes stay cheap; spices aren't multiplied).
func build_cost(kind: String, id: String) -> Dictionary:
	var base: Dictionary
	match kind:
		"ship": base = SHIPS[id].cost
		"weapon": base = WEAPONS[id].cost
		"module": base = MODULES[id].cost
		_: return PROBE_COST
	var out := {}
	for k in base:
		out[k] = base[k] * (BUILD_COST_MULT if ORES.has(k) else 1)
	return out


## Building only ever costs materials (and sometimes spices) - never credits.
func build(kind: String, id: String) -> bool:
	var cost := build_cost(kind, id)
	if not can_afford(cost):
		return false
	pay(cost)
	_grant(kind, id)
	return true


## What the station market charges to sell you something ready-made instead: the raw value of its
## materials and spices, with a hefty markup. Rich pilots can skip the grind.
func market_price(kind: String, id: String) -> int:
	var total := 0
	var cost := build_cost(kind, id)
	for k in cost:
		var each := 0
		if k.begins_with("w:"):
			each = roundi(market_price("weapon", k.substr(2)) / MARKET_MARKUP)  # the mark below, at its own worth
		else:
			each = ORES[k].value if ORES.has(k) else [30, 80, 200, 500][SPICES[k].rarity]
		total += each * cost[k]
	return maxi(50, roundi(total * MARKET_MARKUP / 10.0) * 10)


func buy_ready_made(kind: String, id: String) -> bool:
	var price := 0 if admin else market_price(kind, id)
	if credits < price:
		return false
	credits -= price
	_grant(kind, id)
	return true


func _grant(kind: String, id: String) -> void:
	match kind:
		"ship":
			owned_ships.append(id)
			event("ship_built", {"id": id})
		"weapon": weapon_stock[id] = weapon_stock.get(id, 0) + 1
		"module": module_stock[id] = module_stock.get(id, 0) + 1
		"probe": probes += 1
	changed.emit()


func buy_spice(id: String) -> bool:
	var price: Dictionary = SPICES[id].price
	if not can_afford(price):
		return false
	pay(price)
	give(id, 1)
	changed.emit()
	return true


func board_ship(id: String) -> void:
	ship_id = id
	var slots: int = SHIPS[id].modules
	while modules_equipped.size() > slots:
		var m: String = modules_equipped.pop_back()
		module_stock[m] = module_stock.get(m, 0) + 1
	changed.emit()


## The weapon in each gun slot of a ship (empty slots hold the free Blaster).
func loadout(id := "") -> Array:
	if id == "":
		id = ship_id
	var guns: int = SHIPS[id].guns
	var l: Array = loadouts.get(id, [])
	while l.size() < guns:
		l.append(BLASTER)
	loadouts[id] = l
	return l


## Put a weapon in a gun slot; whatever was there goes back into storage.
func mount(slot: int, weapon: String) -> void:
	var l := loadout()
	var old: String = l[slot]
	if old == weapon:
		return
	if weapon != BLASTER:
		if weapon_stock.get(weapon, 0) <= 0:
			return
		weapon_stock[weapon] -= 1
	if old != BLASTER:
		weapon_stock[old] = weapon_stock.get(old, 0) + 1
	l[slot] = weapon
	changed.emit()


## Fill every slot of the current ship with as many of `weapon` as you have.
func mount_all(weapon: String) -> void:
	for i in loadout().size():
		mount(i, weapon)


## Weapons of this type you own, mounted (on any ship) or in storage.
func weapon_count(id: String) -> int:
	var n: int = weapon_stock.get(id, 0)
	for ship in loadouts:
		n += loadouts[ship].count(id)
	return n


func equip_module(id: String) -> void:
	if module_stock.get(id, 0) <= 0 or modules_equipped.size() >= SHIPS[ship_id].modules:
		return
	module_stock[id] -= 1
	modules_equipped.append(id)
	changed.emit()


func unequip_module(index: int) -> void:
	var m: String = modules_equipped[index]
	modules_equipped.remove_at(index)
	module_stock[m] = module_stock.get(m, 0) + 1
	changed.emit()


## Every number that drives the player's ship, after modules, ship bonuses and blessings.
func stats_ship() -> Dictionary:
	var s: Dictionary = SHIPS[ship_id]
	var b: Dictionary = s.bonus
	var st := {"hull": float(s.hull), "shield": float(s.shield), "speed": float(s.speed), "turn": float(s.turn),
		"cargo": int(s.cargo), "slots": int(s.modules), "guns": int(s.guns), "energy": float(s.energy), "energy_regen": 18.0,
		"tractor": false, "regen": 0.0, "mining": b.get("mining", 1.0), "fire": b.get("fire", 1.0),
		"damage": b.get("damage", 1.0), "bolt": b.get("bolt", 1.0), "stealth": b.get("stealth", 1.0),
		"armor": 1.0, "shield_delay": 3.5, "shield_rate": 0.25, "probe": b.get("probe", 1.0), "warp": b.get("warp", 1.0), "salvage": 1}
	for m in modules_equipped:
		match m:
			"cargo_pod": st.cargo += 60
			"cargo_bay": st.cargo += 160
			"shield_booster": st.shield += 60.0
			"shield_capacitor":
				st.shield_delay = 1.5
				st.shield_rate *= 2.0
			"hull_plating": st.hull += 80.0
			"bulkheads": st.armor *= 0.8
			"afterburner": st.speed *= 1.25
			"gyro": st.turn *= 1.4
			"boost_cells":
				st.energy *= 1.6
				st.energy_regen *= 1.5
			"tractor_beam": st.tractor = true
			"repair_nanites": st.regen += 3.0
			"mining_amp": st.mining *= 1.5
			"overcharger": st.fire *= 1.2
			"targeting_cpu": st.bolt *= 1.3
			"stealth_plating": st.stealth *= 0.65
			"probe_kit": st.probe *= 2.0
			"warp_core": st.warp *= 2.0
			"salvage_rig": st.salvage = 2
	if blessings.has("aegis"):
		st.shield *= 1.5
	if blessings.has("swift"):
		st.speed *= 1.2
	if blessings.has("fury"):
		st.damage *= 1.3
	return st


## Offer a spice at an obelisk. Returns the text describing what happened.
func make_offering(spice_id: String, sys: Dictionary) -> String:
	spices[spice_id] -= 1
	var r: int = SPICES[spice_id].rarity
	var secs := 120 + 60 * r
	var txt := ""
	match randi() % 6:
		0:
			blessings["plenty"] = float(secs)
			txt = "Blessing of Plenty! Rocks shed double ore for %d seconds." % secs
		1:
			blessings["aegis"] = float(secs)
			txt = "Blessing of the Aegis! +50%% shield for %d seconds." % secs
		2:
			blessings["swift"] = float(secs)
			txt = "Blessing of Swiftness! +20%% speed for %d seconds." % secs
		3:
			blessings["fury"] = float(secs)
			txt = "Blessing of Fury! +30%% damage for %d seconds." % secs
		4:
			var tier := clampi(r * 2 + randi() % 2, 0, ORE_ORDER.size() - 1)
			var amount: int = maxi(4, 40 - tier * 5) * (r + 1)
			var ore: String = ORE_ORDER[tier]
			give(ore, amount)
			txt = "The obelisk gifts you %d %s." % [amount, ORES[ore].name]
		_:
			var hidden := []
			for l in sys.locs:
				if l.kind == "planet":
					l.scanned = true
				elif l.kind == "anomaly" and not l.found:
					hidden.append(l)
			txt = "A revelation! Every planet in %s is now scanned." % sys.name
			if not hidden.is_empty():
				var a: Dictionary = hidden.pick_random()
				a.found = true
				event("anomaly")
				txt += " The obelisk also whispers of %s..." % a.name
	event("offering")
	changed.emit()
	return txt


func mark_salvaged(sys_id: int, loc_i: int) -> void:
	systems[sys_id].locs[loc_i].wreck = false
	if not salvaged.has([sys_id, loc_i]):
		salvaged.append([sys_id, loc_i])


## Loot from a derelict wreck. Returns a description.
func salvage(sys: Dictionary) -> String:
	var mult: int = stats_ship().salvage
	var cat: int = sys.cat
	var cr := randi_range(10, 40) * (cat + 1) * mult
	add_credits(cr)
	var parts := ["%d credits" % cr]
	for i in randi_range(1, 2):
		var roll := roll_ore(sys, false)
		var n: int = randi_range(3, 9) * (roll[1] + 1) * mult
		give(roll[0], n)
		parts.append("%d %s" % [n, ORES[roll[0]].name])
	if randf() < 0.06 + 0.03 * cat:
		var m: String = MODULE_ORDER.pick_random()
		module_stock[m] = module_stock.get(m, 0) + 1
		parts.append("a %s module!" % MODULES[m].name)
	if randf() < 0.2:
		var sp: String = SPICE_ORDER[pick_weighted(SPICE_WEIGHTS[cat])]
		give(sp, 1)
		parts.append(SPICES[sp].name)
	event("salvage")
	changed.emit()
	return "Salvaged " + ", ".join(parts)


# ---------------------------------------------------------------- progress: stats, achievements, missions

func stat(id: String) -> int:
	return stats.get(id, 0)


func bump(id: String, n := 1) -> void:
	stats[id] = stat(id) + n
	for a in ACHIEVEMENTS:
		if a[3] == id and not unlocked.has(a[0]) and stats[id] >= a[4]:
			unlocked[a[0]] = true
			toast.emit("ACHIEVEMENT UNLOCKED", a[1] + "  -  " + a[2], "star", Color("ffd24a"))
			Sfx.play("found", -4.0)


## Something happened in the world: count it, unlock achievements and advance missions.
func event(kind: String, data := {}) -> void:
	match kind:
		"ore":
			bump("ore", data.n)
			if data.q == 3:
				bump("pristine", data.n)
			if data.ore == "prismium":
				bump("prismium", data.n)
		"refine":
			bump("refined", data.n)
		"kill":
			bump("kills")
			if data.type == "captain":
				bump("captains")
			elif data.type == "sentinel":
				bump("sentinels")
			_advance("bounty", data.sys)
		"visit":
			if data.new:
				bump("systems")
			if systems[data.sys].cat == CAT_PURPLE:
				bump("wild")
			_advance("explore", data.sys)
		"jump":
			bump("jumps")
		"scan":
			bump("scans")
			_advance("survey", -1)
		"anomaly":
			bump("anomalies")
			_advance("anomaly", -1)
		"wormhole":
			bump("wormholes")
		"salvage":
			bump("salvaged")
		"offering":
			bump("offerings")
		"ship_built":
			bump("ships_built")
			stats["ships_owned"] = 0
			bump("ships_owned", owned_ships.size())
			if data.id == "leviathan":
				bump("leviathan")
		"death":
			bump("deaths")


func _advance(type: String, sys: int) -> void:
	var done := []
	for m in missions:
		if m.type != type:
			continue
		if m.sys >= 0 and m.sys != sys:
			continue
		m.have += 1
		if m.have >= m.need:
			done.append(m)
	for m in done:
		_complete_mission(m)
	if not done.is_empty():
		changed.emit()


func _complete_mission(m: Dictionary) -> void:
	missions.erase(m)
	add_credits(m.reward)
	bump("missions")
	toast.emit("MISSION COMPLETE", "%s  -  +%d credits" % [m.title, m.reward], "mission", Color("7dff8a"))
	Sfx.play("refine", -2.0)


## The mission board at a station; generated on first look and refilled when empty.
func board(sys_id: int, loc_i: int) -> Array:
	var key := "%d:%d" % [sys_id, loc_i]
	if not boards.has(key) or boards[key].is_empty():
		boards[key] = _make_board(sys_id)
	return boards[key]


func _make_board(sys_id: int) -> Array:
	var sys: Dictionary = systems[sys_id]
	var cat: int = sys.cat
	var out := []
	var near := systems_within(sys_id, 1, 4)
	var far := systems_within(sys_id, 3, 8)
	var hostile := near.keys().filter(func(id): return systems[id].cat >= CAT_GREEN)
	for i in 5:
		var kind: String = ["bounty", "explore", "survey", "deliver", "deliver", "anomaly"].pick_random()
		if kind == "anomaly" and cat < CAT_GREEN:
			kind = "survey"
		if kind == "bounty" and hostile.is_empty():
			kind = "deliver"
		var m := {"type": kind, "sys": -1, "ore": "", "need": 1, "have": 0, "reward": 0, "title": "", "desc": ""}
		match kind:
			"bounty":
				var t: int = hostile.pick_random()
				m.sys = t
				m.need = randi_range(3, 6)
				m.reward = int(m.need * 35 * (1.0 + systems[t].cat * 0.5) + near[t] * 25)
				m.title = "Bounty: %s" % systems[t].name
				m.desc = "Destroy %d pirates in %s (%d jumps away)." % [m.need, systems[t].name, near[t]]
			"explore":
				var t: int = far.keys().pick_random() if not far.is_empty() else sys_id
				m.sys = t
				m.reward = 30 * far.get(t, 1) + 30
				m.title = "Courier run: %s" % systems[t].name
				m.desc = "Fly to the %s system (%d jumps away)." % [systems[t].name, far.get(t, 1)]
			"survey":
				m.need = randi_range(3, 6)
				m.reward = m.need * 20
				m.title = "Planetary survey"
				m.desc = "Scan %d unscanned planets with probes, anywhere in the galaxy." % m.need
			"deliver":
				var tier := randi_range(0, mini(ORE_ORDER.size() - 2, cat * 2 + 1))
				m.ore = ORE_ORDER[tier]
				m.need = int(randi_range(15, 60) / float(tier + 1)) + 5
				m.reward = int(m.need * ORES[m.ore].value * 1.4) + 10
				m.title = "Supply order: %s" % ORES[m.ore].name
				m.desc = "Deliver %d refined %s. Turn it in at any station." % [m.need, ORES[m.ore].name]
			"anomaly":
				m.reward = 400
				m.title = "Strange signals"
				m.desc = "Find any anomaly with a probe (they hide in Wild systems)."
		out.append(m)
	return out


func accept_mission(sys_id: int, loc_i: int, index: int) -> void:
	if missions.size() >= MAX_MISSIONS:
		say("You can only take %d missions at once." % MAX_MISSIONS, Color("ff9a8a"))
		return
	var b := board(sys_id, loc_i)
	var m: Dictionary = b[index]
	b.remove_at(index)
	missions.append(m)
	say("Mission accepted: " + m.title, Color("7dff8a"))
	changed.emit()


func abandon_mission(index: int) -> void:
	say("Mission abandoned: " + missions[index].title, Color("8a94a8"))
	missions.remove_at(index)
	changed.emit()


func turn_in(index: int) -> void:
	var m: Dictionary = missions[index]
	if m.type != "deliver" or have(m.ore) < m.need:
		return
	give(m.ore, -m.need)
	_complete_mission(m)
	changed.emit()


# ---------------------------------------------------------------- saving

## Is this the device the admin save belongs to? The key file must hold this machine's own key.
func admin_allowed() -> bool:
	var f := FileAccess.open(ADMIN_KEY, FileAccess.READ)
	return f != null and f.get_as_text().strip_edges() == device_key()


static func device_key() -> String:
	return ("driftlight-admin:" + OS.get_unique_id()).sha256_text()


## Switch save slot ("pilot" or "admin"). Falls back to the pilot slot where admin isn't allowed.
func use_slot(s: String) -> void:
	if s == "admin" and not admin_allowed():
		s = "pilot"
	save_slot = s
	admin = s == "admin"
	god = admin
	if not no_save:
		save_path = SLOTS[s]


## Admin: a bit of everything, and lots of it.
func admin_fill() -> void:
	credits = maxi(credits, 9999999)
	probes = maxi(probes, 99)
	for id in SHIPS:
		if not owned_ships.has(id):
			owned_ships.append(id)
	for id in WEAPONS:
		if id != BLASTER:
			weapon_stock[id] = maxi(weapon_stock.get(id, 0), 10)
	for id in MODULES:
		module_stock[id] = maxi(module_stock.get(id, 0), 4)
	for id in ORES:
		materials[id] = maxi(materials.get(id, 0), 999)
	for id in SPICES:
		spices[id] = maxi(spices.get(id, 0), 99)
	changed.emit()


## Admin: every system visited, every planet scanned, every anomaly found.
func admin_reveal() -> void:
	for s in systems:
		s.visited = true
		for l in s.locs:
			l.scanned = true
			if l.kind == "anomaly":
				l.found = true
	changed.emit()


func has_save() -> bool:
	return FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path + ".bak")


func save_game() -> void:
	if no_save:
		return
	var visited := []
	var scanned := []
	var found := []
	for s in systems:
		if s.visited:
			visited.append(s.id)
		for i in s.locs.size():
			var l: Dictionary = s.locs[i]
			if l.kind == "planet" and l.scanned:
				scanned.append([s.id, i])
			elif l.kind == "anomaly" and l.found:
				found.append(l.anom)
	var data := {"version": SAVE_VERSION, "credits": credits, "materials": materials, "cargo": cargo, "spices": spices,
		"probes": probes, "owned_ships": owned_ships, "ship_id": ship_id, "weapon_stock": weapon_stock,
		"loadouts": loadouts, "module_stock": module_stock, "modules_equipped": modules_equipped, "stats": stats,
		"unlocked": unlocked.keys(), "missions": missions, "route_target": route_target, "system": current_system,
		"loc": current_loc, "visited": visited, "scanned": scanned, "found": found, "salvaged": salvaged, "refineries": refineries, "playtime": playtime,
		"saved_at": Time.get_unix_time_from_system()}
	# write to a temp file first, keep the previous save as .bak, then swap the new one in
	var tmp := save_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if not f:
		push_warning("Could not write save: %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(data))
	f.close()
	var real := ProjectSettings.globalize_path(save_path)
	if FileAccess.file_exists(save_path):
		DirAccess.copy_absolute(real, real + ".bak")
		DirAccess.remove_absolute(real)
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), real)
	dirty = false
	saved.emit()


func load_game() -> bool:
	var data = _read_save(save_path)
	if data == null:
		data = _read_save(save_path + ".bak")
	if data == null:
		return false
	new_game()
	credits = int(data.get("credits", 0))
	materials = _ints(data.get("materials", {}))
	cargo = _ints(data.get("cargo", {}))
	spices = _ints(data.get("spices", {}))
	probes = int(data.get("probes", 0))
	owned_ships = data.get("owned_ships", ["wren"]).filter(func(id): return SHIPS.has(id))
	ship_id = data.get("ship_id", "wren") if SHIPS.has(data.get("ship_id", "")) else "wren"
	weapon_stock = _ints(data.get("weapon_stock", {}))
	for k in weapon_stock.keys():
		if not WEAPONS.has(k):
			weapon_stock.erase(k)
	var lo: Dictionary = data.get("loadouts", {})
	for sid in lo:
		if SHIPS.has(sid):
			loadouts[sid] = lo[sid].map(func(w): return w if WEAPONS.has(w) else BLASTER).slice(0, SHIPS[sid].guns)
	# older saves had one weapon type for both pods: turn each owned type into two pods' worth
	if data.has("owned_weapons"):
		for id in data.owned_weapons:
			if WEAPONS.has(id) and id != BLASTER:
				weapon_stock[id] = weapon_stock.get(id, 0) + 2
		var old: String = data.get("weapon_id", BLASTER)
		if WEAPONS.has(old) and old != BLASTER:
			ship_id = data.get("ship_id", "wren") if SHIPS.has(data.get("ship_id", "")) else "wren"
			mount_all(old)
	module_stock = _ints(data.get("module_stock", {}))
	modules_equipped = data.get("modules_equipped", []).filter(func(id): return MODULES.has(id))
	stats = _ints(data.get("stats", {}))
	for id in data.get("unlocked", []):
		unlocked[id] = true
	missions = []
	for m in data.get("missions", []):
		for k in ["sys", "need", "have", "reward"]:
			m[k] = int(m[k])
		missions.append(m)
	route_target = int(data.get("route_target", -1))
	playtime = float(data.get("playtime", 0.0))
	for id in data.get("visited", []):
		systems[int(id)].visited = true
	for pair in data.get("scanned", []):
		systems[int(pair[0])].locs[int(pair[1])].scanned = true
	for aid in data.get("found", []):
		anom_loc(int(aid)).found = true
	for pair in data.get("salvaged", []):
		mark_salvaged(int(pair[0]), int(pair[1]))
	refineries = {}
	var rd: Dictionary = data.get("refineries", {})
	for key in rd:
		var r: Dictionary = rd[key]
		var q := []
		for item in r.get("queue", []):
			q.append([str(item[0]), int(item[1]), int(item[2])])
		refineries[key] = {"name": str(r.get("name", "")), "queue": q, "progress": float(r.get("progress", 0.0)),
			"output": _ints(r.get("output", {}))}
	# furnaces kept smelting while the game was closed (up to a week)
	var away := clampf(Time.get_unix_time_from_system() - float(data.get("saved_at", Time.get_unix_time_from_system())), 0.0, 604800.0)
	tick_refineries(away)
	current_system = clampi(int(data.get("system", 0)), 0, systems.size() - 1)
	current_loc = clampi(int(data.get("loc", 0)), 0, systems[current_system].locs.size() - 1)
	changed.emit()
	return true


func _read_save(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return null
	var data = JSON.parse_string(f.get_as_text())
	return data if typeof(data) == TYPE_DICTIONARY else null


func _ints(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[k] = int(d[k])
	return out
