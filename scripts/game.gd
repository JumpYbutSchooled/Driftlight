extends Node
## Global state: the galaxy, the player's inventory and progress, and every item table.

signal changed
signal notify(text: String, color: Color)
signal toast(title: String, text: String, icon: String, color: Color)
signal saved
signal jettisoned(ore: String, q: int, n: int)  # cargo thrown out of the hold (main spawns it as loose chunks)

const VERSION := 14  # bump on every release: the auto-updater only installs a higher number
const REPO := "JumpYbutSchooled/Driftlight"
# two save slots: your pilot, and a sandbox where everything is free (anyone can open it)
const SLOTS := {"pilot": "driftlight_save.json", "sandbox": "driftlight_admin.json"}
const SAVE_VERSION := 3  # saves older than this are set aside (v4 and v8 started everyone over)
const BACKUPS_KEPT := 40  # rolling copies of each save kept in user://backups (old copies of the game never touch it)
const BACKUP_EVERY := 600.0  # seconds of play between rolling backups
const GALAXY_SEED := 20261024
const GALAXY_RADIUS := 2650.0
const SYSTEM_COUNT := 1000
const MIN_SPACING := 62.0  # closest two systems can be on the galaxy map
const LINK_RANGE := 190.0  # furthest apart two systems can be and still get a stargate
const MINE_COST := 7.0  # mining power needed to split one ore off a Corrite rock; rarer ores are harder
const HARDNESS_PER_TIER := 0.2
const REFINE_TIME := [0.8, 1.2, 2.0, 4.0]  # seconds to smelt one raw ore, by quality (rarer ores +12% per tier)
const PROBE_COST := {"corrite": 4}
const BUILD_COST_MULT := 16  # building ships, weapons and modules takes this many times the listed materials (x4 before v8)
const PRICE_MULT := 50  # v8: everything bought with credits costs 50 times what it did
const PROBE_PRICE := 12 * PRICE_MULT  # credits, at a market
const MARKET_MARKUP := 5.0  # ready-made gear costs this many times its materials' worth (then x PRICE_MULT)
const MARKET_BASIS := 4  # ...worked out from the listed materials x4, as building took before v8, so dearer building doesn't stack on PRICE_MULT
const MAX_MISSIONS := 4
const MAX_PINS := 3
const WORLD_SCALE := 0.12  # 3D metres per old 2D pixel: turns the speeds/ranges in these tables into 3D units
const WORMHOLE_PRICE := 6000  # what a market pays for a portable wormhole
# credits the Cartographers' Guild pays for charting things, by system category (Core ... Wild)
const CHART_PAY := [0, 25, 70, 180]
const SCAN_PAY := [4, 10, 25, 60]
const ANOMALY_PAY := 300

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

# The galaxy is split into regions: the Core, then each ring cut into sectors. Every region outside the
# Core has its own ore, found nowhere else, and the better ships and gear need them.
const REGIONS := [
	{"name": "The Core", "cat": 0, "ore": "", "color": Color("4aa8ff")},
	{"name": "Verdant Reach", "cat": 1, "ore": "verdite", "color": Color("6fe08a")},
	{"name": "Amber Expanse", "cat": 1, "ore": "ambrite", "color": Color("ffb347")},
	{"name": "Cinder Marches", "cat": 2, "ore": "cindrite", "color": Color("ff7a4a")},
	{"name": "Frostveil", "cat": 2, "ore": "glacite", "color": Color("bfe8ff")},
	{"name": "Tidewell", "cat": 2, "ore": "tidestone", "color": Color("3fd0c8")},
	{"name": "The Shroud", "cat": 3, "ore": "shroudium", "color": Color("8a6cff")},
	{"name": "Ember Abyss", "cat": 3, "ore": "infernite", "color": Color("ff4a78")},
	{"name": "Starfall Wastes", "cat": 3, "ore": "starglass", "color": Color("fff0a8")},
	{"name": "The Rift", "cat": 3, "ore": "riftcore", "color": Color("e060ff")},
]
const REGION_FIRST := [0, 1, 3, 6]  # first region of each ring (Core, Secure, Unsecure, Wild)
const REGION_COUNT := [1, 2, 3, 4]
const REGION_TWIST := [0.0, 0.4, 1.3, 2.2]  # where each ring's sectors start, radians
const REGION_CHANCE := 0.24  # chance a rock in a field holds the region's own ore (anomalies: much more)
const REGION_Q := [0, 62, 30, 8]  # regional ore is never Inferior
const REGION_ANOMALY_Q := [0, 30, 45, 25]

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
const Q_YIELD := [1, 3, 5, 25]  # materials smelted from one piece of ore, by quality
const Q_COLORS := [Color("8d8d8d"), Color("f0f0f0"), Color("ffd24a"), Color("74f7ff")]
# ore quality odds by system category; Pristine ore is only ever found in the anomalies of Wild space
const Q_WEIGHTS := [[97, 3, 0, 0], [58, 35, 7, 0], [0, 74, 26, 0], [0, 55, 45, 0]]
const ANOMALY_Q_WEIGHTS := [0, 0, 40, 60]

# the eight common ores (found all over) and then the nine regional ones
const BASE_ORES := ["corrite", "ferrox", "lumenite", "cryonite", "vexium", "aurelite", "nyxium", "prismium"]
const ORE_ORDER := ["corrite", "ferrox", "lumenite", "cryonite", "vexium", "aurelite", "nyxium", "prismium",
	"verdite", "ambrite", "cindrite", "glacite", "tidestone", "shroudium", "infernite", "starglass", "riftcore"]
const ORES := {
	"corrite": {"name": "Corrite", "color": Color("c28f5c"), "value": 2, "tier": 0, "desc": "Rusty common ore. Everything is built on it."},
	"ferrox": {"name": "Ferrox", "color": Color("9aa8b8"), "value": 3, "tier": 1, "desc": "Dense structural metal."},
	"lumenite": {"name": "Lumenite", "color": Color("5fd8ff"), "value": 5, "tier": 2, "desc": "Glows under stress. Used in shields."},
	"cryonite": {"name": "Cryonite", "color": Color("d6fbff"), "value": 7, "tier": 3, "desc": "Frozen crystal that never melts."},
	"vexium": {"name": "Vexium", "color": Color("8cff5a"), "value": 10, "tier": 4, "desc": "Volatile green ore. Powers weapons."},
	"aurelite": {"name": "Aurelite", "color": Color("ffc93c"), "value": 16, "tier": 5, "desc": "Precious gold-like ore from the outer rim."},
	"nyxium": {"name": "Nyxium", "color": Color("d050ff"), "value": 28, "tier": 6, "desc": "Dark matter in rock form. Mostly out in Wild space."},
	"prismium": {"name": "Prismium", "color": Color("ff5fa2"), "value": 60, "tier": 7, "desc": "Shifts colour as you look at it. Almost only found in anomalies."},
	"verdite": {"name": "Verdite", "color": Color("6fe08a"), "value": 9, "tier": 2, "region": 1,
		"desc": "Living green crystal. Only the Verdant Reach has it."},
	"ambrite": {"name": "Ambrite", "color": Color("ffb347"), "value": 9, "tier": 2, "region": 2,
		"desc": "Warm amber stone. Only the Amber Expanse has it."},
	"cindrite": {"name": "Cindrite", "color": Color("ff7a4a"), "value": 15, "tier": 4, "region": 3,
		"desc": "Still smouldering inside. Only the Cinder Marches have it."},
	"glacite": {"name": "Glacite", "color": Color("bfe8ff"), "value": 15, "tier": 4, "region": 4,
		"desc": "Ice harder than steel. Only Frostveil has it."},
	"tidestone": {"name": "Tidestone", "color": Color("3fd0c8"), "value": 15, "tier": 4, "region": 5,
		"desc": "Ripples like water when struck. Only Tidewell has it."},
	"shroudium": {"name": "Shroudium", "color": Color("8a6cff"), "value": 28, "tier": 6, "region": 6,
		"desc": "Swallows light. Only The Shroud has it."},
	"infernite": {"name": "Infernite", "color": Color("ff4a78"), "value": 28, "tier": 6, "region": 7,
		"desc": "Burns without air. Only the Ember Abyss has it."},
	"starglass": {"name": "Starglass", "color": Color("fff0a8"), "value": 28, "tier": 6, "region": 8,
		"desc": "Fallen starlight, set solid. Only the Starfall Wastes have it."},
	"riftcore": {"name": "Riftcore", "color": Color("e060ff"), "value": 50, "tier": 7, "region": 9,
		"desc": "A splinter of somewhere else. Only The Rift has it."},
}
# chance of each common ore per system category; rarer ores also scale up with distance from the core
const ORE_WEIGHTS := [
	[80, 14, 6, 0, 0, 0, 0, 0],
	[45, 22, 18, 10, 5, 0, 0, 0],
	[18, 14, 20, 16, 18, 10, 4, 0],
	[8, 8, 14, 14, 20, 18, 14, 4],
]
# anomalies hold everything, the common ores included
const ANOMALY_ORE_WEIGHTS := [14, 12, 12, 11, 14, 14, 13, 10]

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

# The hand-built ships. "tier" places each on the progression ladder (its build cost comes from its tier
# and role, see _ship_cost); body/gap/pod/style are left from the old 2D icons.
const SHIP_BASE := {
	"wren": {"name": "Wren", "class": "Skiff", "hull": 100, "shield": 50, "speed": 330, "turn": 3.0, "cargo": 60,
		"modules": 1, "guns": 2, "energy": 100, "body": Vector2i(9, 11), "gap": 2, "pod": 4, "style": "h",
		"colors": [Color("b8c4d6"), Color("4a7fd0"), Color("7ff0ff")], "bonus": {}, "tier": 0, "role": "starter",
		"desc": "Your trusty starter skiff. A plain box with a blaster pod on each side."},
	"sparrow": {"name": "Sparrow", "class": "Scout", "hull": 80, "shield": 70, "speed": 480, "turn": 4.6, "cargo": 30,
		"modules": 1, "guns": 2, "energy": 140, "body": Vector2i(5, 9), "gap": 2, "pod": 4, "style": "v",
		"colors": [Color("e6e0c8"), Color("e07a3c"), Color("9dfcff")], "bonus": {"warp": 1.5}, "tier": 1, "role": "scout",
		"desc": "Tiny and quick. Warps 50% faster."},
	"mule": {"name": "Mule", "class": "Hauler", "hull": 170, "shield": 60, "speed": 260, "turn": 2.0, "cargo": 240,
		"modules": 2, "guns": 2, "energy": 80, "body": Vector2i(11, 13), "gap": 3, "pod": 4, "style": "x",
		"colors": [Color("c9a46a"), Color("8a5a2e"), Color("7ff0ff")], "bonus": {}, "tier": 1, "role": "hauler", "refinery": true,
		"desc": "Slow and boxy, but it swallows a mountain of ore."},
	"prospector": {"name": "Prospector", "class": "Mining Barge", "hull": 200, "shield": 80, "speed": 240, "turn": 1.8,
		"cargo": 320, "modules": 2, "guns": 2, "energy": 80, "body": Vector2i(13, 13), "gap": 2, "pod": 6, "style": "h",
		"colors": [Color("d9b23c"), Color("3a3a3a"), Color("ffe066")], "bonus": {"mining": 1.5}, "tier": 2, "role": "miner",
		"refinery": true, "desc": "Built to dig. +50% mining power."},
	"kestrel": {"name": "Kestrel", "class": "Interceptor", "hull": 110, "shield": 110, "speed": 460, "turn": 4.2,
		"cargo": 50, "modules": 2, "guns": 2, "energy": 130, "body": Vector2i(5, 10), "gap": 4, "pod": 4, "style": "v",
		"colors": [Color("e8f0ea"), Color("3fc46a"), Color("9dfcff")], "bonus": {}, "tier": 2, "role": "fighter",
		"desc": "Fast, nimble, and its narrow hull gives the guns wide arcs."},
	"corsair": {"name": "Corsair", "class": "Fighter", "hull": 180, "shield": 140, "speed": 400, "turn": 3.6, "cargo": 70,
		"modules": 3, "guns": 2, "energy": 110, "body": Vector2i(7, 11), "gap": 4, "pod": 6, "style": "x",
		"colors": [Color("2e3440"), Color("e04848"), Color("ffd24a")], "bonus": {"fire": 1.15}, "tier": 3, "role": "fighter",
		"desc": "A pirate-hunter. +15% fire rate."},
	"lancer": {"name": "Lancer", "class": "Marksman", "hull": 140, "shield": 120, "speed": 360, "turn": 2.8, "cargo": 80,
		"modules": 3, "guns": 2, "energy": 100, "body": Vector2i(5, 15), "gap": 3, "pod": 4, "style": "v",
		"colors": [Color("cfd6e6"), Color("7a5cff"), Color("b9a6ff")], "bonus": {"bolt": 1.4}, "tier": 3, "role": "gunship",
		"desc": "Long and lean. Shots fly 40% faster and further."},
	"aegis": {"name": "Aegis", "class": "Guardian", "hull": 200, "shield": 420, "speed": 290, "turn": 2.4, "cargo": 90,
		"modules": 3, "guns": 2, "energy": 100, "body": Vector2i(11, 11), "gap": 3, "pod": 4, "style": "h",
		"colors": [Color("dfe9ff"), Color("4fd6ff"), Color("4fd6ff")], "bonus": {}, "tier": 3, "role": "tank",
		"desc": "Wrapped in shields. Shrugs off pirate fire."},
	"bastion": {"name": "Bastion", "class": "Gunship", "hull": 380, "shield": 200, "speed": 270, "turn": 1.8, "cargo": 100,
		"modules": 4, "guns": 4, "energy": 90, "body": Vector2i(11, 15), "gap": 3, "pod": 4, "style": "x",
		"colors": [Color("8a8f9c"), Color("b8433a"), Color("ffd27a")], "bonus": {"damage": 1.2}, "tier": 4, "role": "gunship",
		"desc": "A flying fortress with four gun pods. +20% damage."},
	"specter": {"name": "Specter", "class": "Stealth", "hull": 160, "shield": 160, "speed": 440, "turn": 3.8, "cargo": 80,
		"modules": 3, "guns": 2, "energy": 150, "body": Vector2i(7, 12), "gap": 2, "pod": 4, "style": "n",
		"colors": [Color("2a2f3a"), Color("4a5468"), Color("6fffd8")], "bonus": {"stealth": 0.55}, "tier": 4, "role": "stealth",
		"desc": "Dark plating. Pirates only notice you at about half the range."},
	"nyx": {"name": "Nyx Runner", "class": "Explorer", "hull": 240, "shield": 280, "speed": 420, "turn": 3.4, "cargo": 160,
		"modules": 4, "guns": 2, "energy": 140, "body": Vector2i(7, 11), "gap": 4, "pod": 4, "style": "v",
		"colors": [Color("3c2c55"), Color("b366ff"), Color("f0b0ff")], "bonus": {"probe": 1.5, "warp": 1.25}, "tier": 4,
		"role": "explorer", "spice": {"nebula_vanilla": 3}, "desc": "Made for anomaly hunting. Probes fly 50% longer, warps 25% faster."},
	"leviathan": {"name": "Leviathan", "class": "Freighter", "hull": 500, "shield": 300, "speed": 220, "turn": 1.4,
		"cargo": 800, "modules": 5, "guns": 4, "energy": 80, "body": Vector2i(17, 19), "gap": 3, "pod": 4, "style": "x",
		"colors": [Color("6b7080"), Color("d9b23c"), Color("7ff0ff")], "bonus": {}, "tier": 5, "role": "hauler", "refinery": true,
		"desc": "A moving warehouse. 800 cargo, four gun pods."},
	"seraph": {"name": "Seraph", "class": "Flagship", "hull": 320, "shield": 380, "speed": 470, "turn": 3.6, "cargo": 200,
		"modules": 5, "guns": 4, "energy": 180, "body": Vector2i(9, 15), "gap": 4, "pod": 4, "style": "h",
		"colors": [Color("fff0f6"), Color("ff5fa2"), Color("ffe066")], "bonus": {"damage": 1.15, "mining": 1.25}, "tier": 5,
		"role": "fighter", "spice": {"starbloom": 6}, "desc": "The finest small ship in the galaxy. +15% damage, +25% mining."},
	"halberd": {"name": "Halberd", "class": "Destroyer", "hull": 700, "shield": 450, "speed": 245, "turn": 1.4, "cargo": 220,
		"modules": 5, "guns": 4, "energy": 120, "body": Vector2i(13, 21), "gap": 3, "pod": 4, "style": "x",
		"colors": [Color("9aa4b4"), Color("2fb8a8"), Color("bff4ff")], "bonus": {"damage": 1.1}, "tier": 5, "role": "gunship",
		"desc": "The first real warship. Twice the length of a fighter, four gun pods."},
	"monarch": {"name": "Monarch", "class": "Cruiser", "hull": 1200, "shield": 750, "speed": 215, "turn": 1.1, "cargo": 320,
		"modules": 6, "guns": 6, "energy": 130, "body": Vector2i(17, 27), "gap": 3, "pod": 4, "style": "h",
		"colors": [Color("2c3e66"), Color("e8b84a"), Color("ffe7a3")], "bonus": {"damage": 1.1}, "tier": 6, "role": "gunship",
		"desc": "A cruiser with six gun pods. Pirates think twice."},
	"behemoth": {"name": "Behemoth", "class": "Battlecruiser", "hull": 2000, "shield": 1200, "speed": 190, "turn": 0.9,
		"cargo": 450, "modules": 7, "guns": 8, "energy": 140, "body": Vector2i(21, 33), "gap": 4, "pod": 4, "style": "x",
		"colors": [Color("6a3a40"), Color("d8433a"), Color("ffb36b")], "bonus": {"damage": 1.15}, "tier": 7, "role": "gunship",
		"desc": "Eight gun pods and armour like a moon."},
	"ark": {"name": "Ark", "class": "Mothership", "hull": 2600, "shield": 1300, "speed": 150, "turn": 0.6, "cargo": 3000,
		"modules": 7, "guns": 6, "energy": 100, "body": Vector2i(27, 37), "gap": 3, "pod": 4, "style": "v",
		"colors": [Color("8a8170"), Color("4a7fd0"), Color("7ff0ff")], "bonus": {"mining": 1.3}, "tier": 7, "role": "hauler",
		"refinery": true, "desc": "A flying city. 3,000 cargo and a mining bay. Painfully slow."},
	"titan": {"name": "Titan", "class": "Dreadnought", "hull": 3400, "shield": 2000, "speed": 165, "turn": 0.7, "cargo": 600,
		"modules": 8, "guns": 10, "energy": 160, "body": Vector2i(25, 43), "gap": 4, "pod": 4, "style": "n",
		"colors": [Color("4a4462"), Color("9b4dff"), Color("e0a0ff")], "bonus": {"damage": 1.25}, "tier": 8, "role": "gunship",
		"spice": {"nebula_vanilla": 10}, "desc": "Ten gun pods, +25% damage, and the size of a station."},
}
# The rest of the fleet: [id, name, class, role, tier, turrets, accent colour, description]. Their numbers come
# from their role and tier (ROLE_STATS); the models are built in tools/blender/ships.py (FLEET).
const FLEET := [
	["gnat", "Gnat", "Scout", "scout", 1, 2, "39a0d8", "A cheap little scout with X-fins. Quick to build, quick to fly."],
	["wisp", "Wisp", "Scout", "scout", 1, 2, "8a7cff", "Twin booms under a solar sail. Warps fast."],
	["pike", "Pike", "Fighter", "fighter", 1, 2, "d84a3a", "A narrow wedge with a prow cannon. A first real fighter."],
	["bumble", "Bumble", "Hauler", "hauler", 1, 2, "e0b84a", "A tubby little hauler with fuel tanks. A big hold for the price."],
	["drifter", "Drifter", "Explorer", "explorer", 2, 2, "4ab0a0", "A ring-waisted explorer for the first trips out of the Core."],
	["hornet", "Hornet", "Fighter", "fighter", 2, 2, "e8c02a", "Spiked, striped and angry."],
	["digger", "Digger", "Miner", "miner", 2, 2, "3a3330", "A small mining barge with claws, a drill and radiators."],
	["porter", "Porter", "Hauler", "hauler", 2, 2, "e07a3c", "A container hauler riding between two outriggers."],
	["falcon", "Falcon", "Interceptor", "fighter", 3, 2, "2f6fd8", "Forward-swept wings and three engines. Very quick."],
	["vanguard", "Vanguard", "Gunship", "gunship", 3, 4, "e8b84a", "A compact warship with four turrets and a spinal gun."],
	["quarry", "Quarry", "Miner", "miner", 3, 2, "e0b030", "A bigger barge with sensor domes and fuel tanks."],
	["wayfarer", "Wayfarer", "Explorer", "explorer", 3, 2, "c0603a", "A long-range explorer with a sail and X-fins."],
	["brick", "Brick", "Guardian", "tank", 3, 2, "5a7090", "A flying bunker. Slow, but very hard to kill."],
	["raptor", "Raptor", "Fighter", "fighter", 4, 4, "3fc46a", "Four turrets and two engine nacelles."],
	["bulwark", "Bulwark", "Guardian", "tank", 4, 4, "3a62b0", "A shield fortress with a collar of emitters."],
	["trawler", "Trawler", "Hauler", "hauler", 4, 2, "d8a040", "A big container ship with hangar pods and radiators."],
	["phantom", "Phantom", "Stealth", "stealth", 4, 2, "3a4458", "A black wedge with a split prow. Pirates barely see it."],
	["warden", "Warden", "Guardian", "tank", 5, 4, "2fa8c8", "A heavy guardian with engine nacelles and antennas."],
	["tempest", "Tempest", "Fighter", "fighter", 5, 4, "7a3ad8", "A heavy dart with nacelles and X-fins."],
	["excavator", "Excavator", "Miner", "miner", 5, 4, "303030", "A mining barge between two outrigger hulls."],
	["pathfinder", "Pathfinder", "Explorer", "explorer", 5, 4, "3a7ad8", "A deep-space explorer: a ring, radiators and domes."],
	["mantis", "Mantis", "Fighter", "fighter", 5, 4, "2a3a22", "Twin booms and a split prow. Mines nearly as well as it fights."],
	["dominator", "Dominator", "Destroyer", "gunship", 6, 6, "c83a3a", "Six turrets, a spinal cannon and radiators."],
	["atlas", "Atlas", "Freighter", "hauler", 6, 4, "3a8ad0", "A huge freighter with a collar and hangar pods."],
	["valkyrie", "Valkyrie", "Fighter", "fighter", 6, 4, "d84a8a", "A big, elegant fighter on forward-swept wings."],
	["obsidian", "Obsidian", "Stealth", "stealth", 6, 4, "50306a", "A stealth wedge as black as space."],
	["juggernaut", "Juggernaut", "Battleship", "gunship", 7, 10, "d8433a", "Ten turrets, armour bands and outrigger hulls."],
	["harbinger", "Harbinger", "Cruiser", "gunship", 7, 8, "3ad0c0", "A fast cruiser with a split prow and twin fins."],
	["starminer", "Starminer", "Mining Ship", "miner", 7, 6, "3a3a3a", "A mining ship the size of a cruiser."],
	["paragon", "Paragon", "Flagship", "fighter", 8, 8, "e8b84a", "A golden flagship ringed with a collar."],
	["oracle", "Oracle", "Explorer Cruiser", "explorer", 8, 6, "8a5ad8", "An explorer cruiser with a great sail."],
	["colossus", "Colossus", "Carrier", "capital", 9, 12, "d8a83a", "A 360 metre carrier. Built-in jump drive: skips stargates."],
	["starforge", "Starforge", "Forge Ship", "capital", 9, 10, "2a2a2a", "A 360 metre mining and smelting ship. Jump drive and furnaces on board."],
	["sovereign", "Sovereign", "Command Dreadnought", "capital", 9, 14, "e8c060", "A 640 metre dreadnought with a long-range jump drive."],
	["eclipse", "Eclipse", "Worldship", "capital", 9, 16, "ff7a3a", "A kilometre-long worldship. Its jump drive crosses half the galaxy."],
	["aeon", "Aeon", "Ascendant", "capital", 9, 18, "5a9aff", "The largest thing anyone ever built. Jumps almost anywhere."],
]
# base numbers per role (at tier 1; hull, shield and cargo grow with tier). bonus: ship bonuses
const ROLE_STATS := {
	"scout": {"hull": 75, "shield": 70, "speed": 500, "turn": 4.6, "cargo": 35, "energy": 150, "modules": 1, "bonus": {"warp": 1.3}},
	"fighter": {"hull": 110, "shield": 100, "speed": 440, "turn": 4.1, "cargo": 45, "energy": 125, "modules": 2, "bonus": {"fire": 1.1}},
	"miner": {"hull": 150, "shield": 70, "speed": 260, "turn": 2.0, "cargo": 200, "energy": 80, "modules": 2, "bonus": {"mining": 1.35}},
	"hauler": {"hull": 165, "shield": 60, "speed": 250, "turn": 1.9, "cargo": 280, "energy": 80, "modules": 2, "bonus": {}},
	"explorer": {"hull": 120, "shield": 120, "speed": 420, "turn": 3.4, "cargo": 110, "energy": 140, "modules": 2,
		"bonus": {"probe": 1.5, "warp": 1.25}},
	"tank": {"hull": 260, "shield": 280, "speed": 280, "turn": 2.2, "cargo": 90, "energy": 100, "modules": 3, "bonus": {}},
	"gunship": {"hull": 240, "shield": 170, "speed": 290, "turn": 2.0, "cargo": 90, "energy": 100, "modules": 3, "bonus": {"damage": 1.15}},
	"stealth": {"hull": 140, "shield": 150, "speed": 450, "turn": 3.8, "cargo": 70, "energy": 150, "modules": 2, "bonus": {"stealth": 0.55}},
}
# the capital ships: numbers set by hand. jump: jump drive reach on the galaxy map; scale: how many times
# bigger than its Blender model it's shown
const CAPITALS := {
	"colossus": {"hull": 9000, "shield": 6000, "speed": 700, "turn": 0.35, "cargo": 4000, "modules": 9, "energy": 220,
		"bonus": {"damage": 1.2}, "jump": 420, "cost": {"ferrox": 6000, "aurelite": 2000, "nyxium": 600, "prismium": 150,
		"starglass": 300, "infernite": 200, "riftcore": 60}},
	"starforge": {"hull": 8000, "shield": 5000, "speed": 620, "turn": 0.3, "cargo": 9000, "modules": 9, "energy": 200,
		"bonus": {"mining": 2.2}, "jump": 380, "refinery": true, "cost": {"corrite": 12000, "ferrox": 6000, "aurelite": 1500,
		"prismium": 120, "starglass": 500, "tidestone": 400, "riftcore": 60}},
	"sovereign": {"hull": 16000, "shield": 10000, "speed": 650, "turn": 0.28, "cargo": 3000, "modules": 10, "energy": 240,
		"bonus": {"damage": 1.4}, "jump": 620, "cost": {"ferrox": 10000, "aurelite": 3500, "nyxium": 1200, "prismium": 300,
		"infernite": 500, "shroudium": 300, "riftcore": 150}},
	"eclipse": {"hull": 26000, "shield": 16000, "speed": 600, "turn": 0.22, "cargo": 12000, "modules": 11, "energy": 260,
		"bonus": {"mining": 1.6, "probe": 2.0}, "jump": 950, "refinery": true, "cost": {"ferrox": 16000, "aurelite": 5000,
		"nyxium": 2000, "prismium": 500, "starglass": 600, "shroudium": 600, "riftcore": 300, "nebula_vanilla": 20}},
	"aeon": {"hull": 40000, "shield": 25000, "speed": 640, "turn": 0.2, "cargo": 6000, "modules": 12, "energy": 300,
		"bonus": {"damage": 1.6, "mining": 1.5}, "jump": 1400, "cost": {"ferrox": 25000, "aurelite": 8000, "nyxium": 3000,
		"prismium": 900, "infernite": 900, "shroudium": 900, "starglass": 900, "riftcore": 600, "nebula_vanilla": 40}},
}
const REFINERY_ROLES := ["miner", "hauler"]  # ships of these roles can carry a Portable Refinery
var SHIPS := {}  # every ship: SHIP_BASE plus the generated FLEET (see _expand_ships)
var SHIP_ORDER := []  # cheapest first

# Each weapon is one gun pod's worth: build or buy one per slot you want to fill (Blasters are free).
# pellets/spread = shotgun, pierce = passes through targets, homing = turn rate toward pirates, slow = seconds slowed,
# beam = a continuous beam that locks on to what's under the crosshair (mining lasers)
# These are the Mk I weapons; _expand_weapons() adds Mk II to Mk V of each to WEAPONS (see WEAPON_TIERS).
const WEAPON_BASE_ORDER := ["twin_blasters", "mining_lasers", "scatter_guns", "flak_battery", "pulse_cannons", "ion_repeaters",
	"cryo_projectors", "plasma_projectors", "seeker_darts", "rail_drivers", "deep_core_drills", "torpedo_bays", "nova_lances",
	"graviton_lances", "prism_cannons"]
const WEAPON_BASE := {
	"twin_blasters": {"name": "Blaster", "damage": 6.0, "rate": 4.0, "speed": 950.0, "mining": 1.0, "life": 1.1,
		"color": Color("ffe066"), "size": Vector2(2, 6), "cost": {}, "desc": "The standard gun pod. Free and unlimited - every empty slot has one."},
	"mining_lasers": {"name": "Mining Laser", "damage": 3.0, "rate": 7.0, "speed": 1100.0, "mining": 2.2, "life": 0.7, "beam": true,
		"color": Color("66ffcc"), "size": Vector2(2, 8), "cost": {"corrite": 70, "lumenite": 15},
		"desc": "Click a rock and its beam locks on and cuts ore straight into your hold on its own. Click again to stop."},
	"scatter_guns": {"name": "Scatter Gun", "damage": 4.0, "rate": 1.6, "speed": 820.0, "mining": 0.6, "life": 0.6,
		"pellets": 5, "spread": 22.0, "color": Color("ffb36b"), "size": Vector2(3, 3), "cost": {"corrite": 90, "ferrox": 45},
		"desc": "Five pellets per shot. Brutal up close."},
	"flak_battery": {"name": "Flak Battery", "damage": 3.0, "rate": 2.0, "speed": 760.0, "mining": 0.4, "life": 0.5,
		"pellets": 8, "spread": 30.0, "color": Color("ffe08a"), "size": Vector2(2, 2), "cost": {"ferrox": 80, "cryonite": 30},
		"desc": "A wall of flak. Shreds swarmers."},
	"pulse_cannons": {"name": "Pulse Cannon", "damage": 16.0, "rate": 2.2, "speed": 800.0, "mining": 1.2, "life": 1.2,
		"color": Color("ff8a3d"), "size": Vector2(4, 6), "cost": {"corrite": 105, "lumenite": 40, "vexium": 15},
		"desc": "Slow, heavy bolts that hurt pirates."},
	"ion_repeaters": {"name": "Ion Repeater", "damage": 7.0, "rate": 10.0, "speed": 1050.0, "mining": 0.8, "life": 1.0,
		"color": Color("7aa8ff"), "size": Vector2(2, 5), "cost": {"vexium": 55, "cryonite": 25}, "desc": "A storm of fast ion bolts."},
	"cryo_projectors": {"name": "Cryo Projector", "damage": 5.0, "rate": 5.0, "speed": 900.0, "mining": 0.8, "life": 0.9,
		"slow": 1.5, "color": Color("bff4ff"), "size": Vector2(3, 5), "cost": {"cryonite": 60, "lumenite": 30},
		"desc": "Freezing bolts. Pirates that are hit slow to half speed."},
	"plasma_projectors": {"name": "Plasma Projector", "damage": 12.0, "rate": 3.0, "speed": 900.0, "mining": 1.0, "life": 1.0,
		"color": Color("5affd8"), "size": Vector2(4, 5), "cost": {"vexium": 50, "verdite": 20},
		"desc": "Globs of plasma that splash on impact."},
	"seeker_darts": {"name": "Seeker Dart", "damage": 9.0, "rate": 2.5, "speed": 620.0, "mining": 0.5, "life": 2.2,
		"homing": 4.0, "color": Color("ff66aa"), "size": Vector2(2, 5), "cost": {"vexium": 45, "aurelite": 25},
		"desc": "Darts that curve toward the nearest pirate."},
	"rail_drivers": {"name": "Rail Driver", "damage": 28.0, "rate": 1.1, "speed": 1800.0, "mining": 2.0, "life": 1.2,
		"pierce": 3, "color": Color("e8f6ff"), "size": Vector2(2, 16), "cost": {"vexium": 75, "aurelite": 45},
		"desc": "Hypersonic slugs that punch through up to 3 targets."},
	"deep_core_drills": {"name": "Deep-Core Drill", "damage": 4.0, "rate": 6.0, "speed": 700.0, "mining": 5.0, "life": 0.35,
		"color": Color("ffd24a"), "size": Vector2(4, 4), "cost": {"aurelite": 45, "nyxium": 15, "cryonite": 45},
		"desc": "Very short range, insane mining power."},
	"torpedo_bays": {"name": "Torpedo Bay", "damage": 70.0, "rate": 0.45, "speed": 520.0, "mining": 2.5, "life": 3.2,
		"homing": 1.6, "color": Color("ff7a4a"), "size": Vector2(5, 10), "cost": {"aurelite": 50, "vexium": 40, "ambrite": 30},
		"desc": "Slow homing torpedoes that hit like a freighter."},
	"nova_lances": {"name": "Nova Lance", "damage": 34.0, "rate": 1.4, "speed": 1400.0, "mining": 3.0, "life": 1.3,
		"pierce": 1, "color": Color("ff66ff"), "size": Vector2(3, 14), "cost": {"aurelite": 55, "nyxium": 20, "starbloom": 5},
		"desc": "Long-range lances of pure Nyxium light."},
	"graviton_lances": {"name": "Graviton Lance", "damage": 45.0, "rate": 1.0, "speed": 1600.0, "mining": 4.0, "life": 1.3,
		"pierce": 4, "color": Color("a080ff"), "size": Vector2(3, 18), "cost": {"nyxium": 40, "glacite": 30, "aurelite": 40},
		"desc": "Bends space along its path: pierces four targets."},
	"prism_cannons": {"name": "Prism Cannon", "damage": 22.0, "rate": 3.0, "speed": 1200.0, "mining": 3.0, "life": 1.2,
		"pellets": 3, "spread": 10.0, "pierce": 1, "color": Color("ff5fa2"), "size": Vector2(3, 8),
		"cost": {"nyxium": 60, "prismium": 30}, "desc": "Split a beam of Prismium into three piercing rays."},
}
# Five marks of every weapon. Each mark up hits harder, fires faster and mines better, takes far more
# materials (and from Mk III on a regional ore), and uses up one of the mark below it from your stores.
const WEAPON_TIERS := [
	{"suffix": "", "damage": 1.0, "rate": 1.0, "mining": 1.0, "cost": 1.0, "region": -1},
	{"suffix": " Mk II", "damage": 1.35, "rate": 1.08, "mining": 1.3, "cost": 2.5, "region": -1},
	{"suffix": " Mk III", "damage": 1.8, "rate": 1.16, "mining": 1.7, "cost": 6.0, "region": 0},
	{"suffix": " Mk IV", "damage": 2.4, "rate": 1.25, "mining": 2.2, "cost": 12.0, "region": 1},
	{"suffix": " Mk V", "damage": 3.2, "rate": 1.35, "mining": 2.9, "cost": 24.0, "region": 2},
]
const MK := ["I", "II", "III", "IV", "V"]
# the regional ore each weapon needs at Mk III (a Secure region), Mk IV (Unsecure) and Mk V (Wild)
const WEAPON_REGION := {
	"twin_blasters": ["ambrite", "tidestone", "starglass"], "mining_lasers": ["ambrite", "tidestone", "starglass"],
	"scatter_guns": ["verdite", "cindrite", "infernite"], "flak_battery": ["ambrite", "cindrite", "infernite"],
	"pulse_cannons": ["verdite", "cindrite", "infernite"], "ion_repeaters": ["verdite", "glacite", "shroudium"],
	"cryo_projectors": ["ambrite", "glacite", "shroudium"], "plasma_projectors": ["verdite", "cindrite", "infernite"],
	"seeker_darts": ["verdite", "cindrite", "infernite"], "rail_drivers": ["ambrite", "glacite", "starglass"],
	"deep_core_drills": ["ambrite", "tidestone", "starglass"], "torpedo_bays": ["ambrite", "tidestone", "shroudium"],
	"nova_lances": ["verdite", "glacite", "riftcore"], "graviton_lances": ["ambrite", "glacite", "riftcore"],
	"prism_cannons": ["verdite", "cindrite", "riftcore"],
}
var WEAPONS := {}  # every weapon, all five marks: Mk I under its base id, then "<id>_mk2" ... "<id>_mk5"
var WEAPON_ORDER := []

# Modules, by what they do. Each kind has its own icon and colour in the menus (MODULE_CATS). fx: what one does
# to the ship (see stats_ship); Mk II and Mk III are stronger (MODULE_TIERS). only: which ships can fit it.
const MODULE_CATS := {
	"cargo": {"name": "Cargo", "icon": "cargo", "color": Color("d8b070")},
	"shield": {"name": "Shields", "icon": "shield", "color": Color("5fc8ee")},
	"hull": {"name": "Armour", "icon": "hull", "color": Color("e8845a")},
	"engine": {"name": "Engines", "icon": "throttle", "color": Color("e8d06a")},
	"energy": {"name": "Energy", "icon": "energy", "color": Color("a890e0")},
	"mining": {"name": "Mining", "icon": "ore", "color": Color("8ee070")},
	"weapon": {"name": "Weapons", "icon": "weapon", "color": Color("ee6a5a")},
	"scan": {"name": "Scanning", "icon": "radar", "color": Color("7aa8ff")},
	"warp": {"name": "Warp", "icon": "gate", "color": Color("c080ff")},
	"utility": {"name": "Utility", "icon": "wrench", "color": Color("b0bccc")},
	"refinery": {"name": "Refining", "icon": "flame", "color": Color("ff9a3d")},
}
const MODULE_BASE_ORDER := ["cargo_pod", "cargo_bay", "ore_compressor", "shield_booster", "shield_capacitor", "hull_plating",
	"bulkheads", "heavy_armor", "repair_nanites", "afterburner", "gyro", "boost_cells", "mining_amp", "tractor_beam",
	"portable_refinery", "overcharger", "damage_amp", "targeting_cpu", "probe_kit", "survey_array", "anomaly_sense", "warp_core",
	"stealth_plating", "salvage_rig"]
const MODULE_BASE := {
	"cargo_pod": {"name": "Cargo Pod", "cat": "cargo", "fx": {"cargo_add": 60}, "cost": {"corrite": 75}},
	"cargo_bay": {"name": "Cargo Bay", "cat": "cargo", "fx": {"cargo_add": 160}, "cost": {"ferrox": 120, "cryonite": 30}},
	"ore_compressor": {"name": "Ore Compressor", "cat": "cargo", "fx": {"cargo_mul": 1.25}, "cost": {"lumenite": 80, "ambrite": 20}},
	"shield_booster": {"name": "Shield Booster", "cat": "shield", "fx": {"shield_add": 60}, "cost": {"corrite": 60, "lumenite": 30}},
	"shield_capacitor": {"name": "Shield Capacitor", "cat": "shield", "fx": {"shield_rate_mul": 2.0, "shield_delay_mul": 0.45},
		"cost": {"lumenite": 60, "cryonite": 30}},
	"hull_plating": {"name": "Hull Plating", "cat": "hull", "fx": {"hull_add": 80}, "cost": {"corrite": 120, "ferrox": 45}},
	"bulkheads": {"name": "Reinforced Bulkheads", "cat": "hull", "fx": {"armor_mul": 0.8}, "cost": {"ferrox": 135, "vexium": 30}},
	"heavy_armor": {"name": "Heavy Armour", "cat": "hull", "fx": {"hull_add": 400, "speed_mul": 0.92}, "cost": {"ferrox": 400, "tidestone": 40}},
	"repair_nanites": {"name": "Repair Nanites", "cat": "hull", "fx": {"regen_add": 3.0},
		"cost": {"vexium": 30, "aurelite": 25, "starbloom": 5}},
	"afterburner": {"name": "Afterburner", "cat": "engine", "fx": {"speed_mul": 1.25}, "cost": {"lumenite": 45, "vexium": 15}},
	"gyro": {"name": "Gyro Stabilizer", "cat": "engine", "fx": {"turn_mul": 1.4}, "cost": {"ferrox": 60, "lumenite": 30}},
	"boost_cells": {"name": "Boost Cells", "cat": "energy", "fx": {"energy_mul": 1.6, "energy_regen_mul": 1.5},
		"cost": {"lumenite": 45, "cryonite": 40}},
	"mining_amp": {"name": "Mining Amplifier", "cat": "mining", "fx": {"mining_mul": 1.5}, "cost": {"ferrox": 60, "vexium": 30}},
	"tractor_beam": {"name": "Tractor Beam", "cat": "mining", "fx": {"tractor_add": 300}, "cost": {"lumenite": 40, "vexium": 25}},
	"portable_refinery": {"name": "Portable Refinery", "cat": "refinery", "fx": {"refine_add": 16.0}, "only": "refinery",
		"cost": {"ferrox": 200, "cryonite": 80, "ambrite": 30}},
	"overcharger": {"name": "Overcharger", "cat": "weapon", "fx": {"fire_mul": 1.2}, "cost": {"vexium": 60, "aurelite": 25}},
	"damage_amp": {"name": "Damage Amplifier", "cat": "weapon", "fx": {"damage_mul": 1.15}, "cost": {"vexium": 80, "cindrite": 30}},
	"targeting_cpu": {"name": "Targeting Computer", "cat": "weapon", "fx": {"bolt_mul": 1.3}, "cost": {"lumenite": 60, "aurelite": 15}},
	"probe_kit": {"name": "Probe Kit", "cat": "scan", "fx": {"probe_mul": 2.0}, "cost": {"lumenite": 60, "ferrox": 30}},
	"survey_array": {"name": "Survey Array", "cat": "scan", "fx": {"scan_mul": 2.0}, "cost": {"lumenite": 80, "verdite": 25}},
	"anomaly_sense": {"name": "Anomaly Sense", "cat": "scan", "fx": {"sense_add": 1.0}, "cost": {"cryonite": 80, "glacite": 30, "nyxium": 10}},
	"warp_core": {"name": "Warp Core", "cat": "warp", "fx": {"warp_mul": 2.0}, "cost": {"cryonite": 45, "aurelite": 30}},
	"stealth_plating": {"name": "Stealth Plating", "cat": "utility", "fx": {"stealth_mul": 0.65}, "cost": {"cryonite": 60, "nyxium": 15}},
	"salvage_rig": {"name": "Salvage Rig", "cat": "utility", "fx": {"salvage_add": 1}, "cost": {"ferrox": 105, "corrite": 60}},
}
const MODULE_TIERS := [{"suffix": "", "k": 1.0, "cost": 1.0}, {"suffix": " II", "k": 1.7, "cost": 3.0},
	{"suffix": " III", "k": 2.5, "cost": 8.0}]
# Mk III modules need a regional ore too, by kind
const MODULE_REGION := {"cargo": "tidestone", "hull": "tidestone", "mining": "tidestone", "refinery": "tidestone",
	"utility": "glacite", "shield": "glacite", "energy": "glacite", "scan": "glacite", "warp": "glacite", "weapon": "cindrite",
	"engine": "cindrite"}
var MODULES := {}  # every module, all three marks: Mk I under its base id, then "<id>_mk2", "<id>_mk3"
var MODULE_ORDER := []

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
	["planet_eater", "Planet Eater", "Collect 50,000 ore.", "ore", 50000],
	["smelter", "Smelter", "Refine 250 materials.", "refined", 250],
	["foundry", "Foundry", "Refine 10,000 materials.", "refined", 10000],
	["flawless", "Flawless", "Collect a piece of Pristine ore.", "pristine", 1],
	["prismatic", "Prismatic", "Collect Prismium ore.", "prismium", 1],
	["local_flavour", "Local Flavour", "Collect a regional ore.", "regional", 1],
	["connoisseur", "Connoisseur", "Collect all nine regional ores.", "regional_kinds", 9],
	["motherlode", "Motherlode", "Collect 2,000 ore in anomalies.", "anomaly_ore", 2000],
	["first_blood", "First Blood", "Destroy a pirate.", "kills", 1],
	["ace", "Ace Pilot", "Destroy 25 pirates.", "kills", 25],
	["scourge", "Scourge of Pirates", "Destroy 150 pirates.", "kills", 150],
	["mutiny", "Mutiny", "Destroy a Pirate Captain.", "captains", 1],
	["gatecrasher", "Gatecrasher", "Destroy an anomaly Sentinel.", "sentinels", 1],
	["wanderer", "Wanderer", "Visit 10 systems.", "systems", 10],
	["voyager", "Voyager", "Visit 50 systems.", "systems", 50],
	["cartographer", "Cartographer", "Visit 200 systems.", "systems", 200],
	["tourist", "Tourist", "Visit 4 regions.", "regions", 4],
	["known_space", "Known Space", "Visit all 10 regions.", "regions", 10],
	["gate_runner", "Gate Runner", "Make 100 stargate jumps.", "jumps", 100],
	["into_the_wild", "Into the Wild", "Enter a Wild system.", "wild", 1],
	["wild_child", "Wild Child", "Arrive in Wild systems 100 times.", "wild", 100],
	["surveyor", "Surveyor", "Scan 25 planets with probes.", "scans", 25],
	["something_strange", "Something Strange", "Find an anomaly.", "anomalies", 1],
	["anomaly_hunter", "Anomaly Hunter", "Find 15 anomalies.", "anomalies", 15],
	["looking_glass", "Through the Looking Glass", "Travel through a wormhole.", "wormholes", 1],
	["pocket_universe", "Pocket Universe", "Open a portable wormhole.", "portals", 1],
	["archaeologist", "Archaeologist", "Decode an ancient relic.", "relics", 1],
	["lore_keeper", "Lore Keeper", "Decode 10 ancient relics.", "relics", 10],
	["scavenger", "Scavenger", "Salvage 10 wrecks.", "salvaged", 10],
	["devout", "Devout", "Make 5 offerings at obelisks.", "offerings", 5],
	["note_taker", "Note Taker", "Record 50 places in your notebook.", "noted", 50],
	["shipwright", "Shipwright", "Build a new ship.", "ships_built", 1],
	["fleet_admiral", "Fleet Admiral", "Own 10 ships.", "ships_owned", 10],
	["armada", "Armada", "Own 25 ships.", "ships_owned", 25],
	["collector", "Collector", "Own every ship.", "ships_owned", 54],
	["big_boat", "Big Boat", "Own a Leviathan.", "leviathan", 1],
	["capital_idea", "Capital Idea", "Own a capital ship.", "capitals", 1],
	["skip_the_queue", "Skip the Queue", "Use a jump drive.", "jumpdrives", 1],
	["master_crafted", "Master Crafted", "Build a Mk V weapon.", "mk5", 1],
	["contractor", "Contractor", "Complete 10 missions.", "missions", 10],
	["tycoon", "Tycoon", "Earn 25,000 credits.", "earned", 25000],
	["magnate", "Magnate", "Earn 1,000,000 credits.", "earned", 1000000],
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
# notebook tags: [tag, label, icon, colour]
const NOTE_TAGS := [["refinery", "Refinery", "flame", Color("ff9a3d")], ["station", "Station", "station", Color("ffe066")],
	["ore", "Ore field", "ore", Color("c8a070")], ["anomaly", "Anomaly", "anomaly", Color("e080ff")],
	["wormhole", "Wormhole", "anomaly", Color("d050ff")], ["relic", "Relic", "star", Color("7fd8ff")],
	["obelisk", "Obelisk", "obelisk", Color("d050ff")], ["spice", "Spice stand", "spice", Color("ffb03d")],
	["wreck", "Wreck", "wreck", Color("b0b8c8")], ["pirates", "Pirates", "skull", Color("ff6a5a")]]

# --- player state (reset by new_game) ---
var credits := 0
var materials := {}  # refined ore id -> amount
var cargo := {}  # "ore_id:quality" -> raw ore count
var spices := {}
var probes := 0
var portals := 0  # portable wormholes in the hold
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
var relics_done := []  # [sys, loc, unix time] of each relic decoded in the last week (see refresh_relics)
# station furnaces: "sys:loc" -> {name, queue: [[ore, quality, count]], progress (s into the current piece), output: {ore: n}}
var refineries := {}
var notebook := {}  # "sys:loc" -> {"sys", "loc", "tags": [...], "ores": [...]}: every place worth remembering
var pinned := []  # [kind, id] recipes shown on the HUD
var route_stops := []  # further stops after route_target, in order
var regions_seen := {}  # region index -> true
var regional_seen := {}  # regional ore id -> true
var home := [0, 0]  # [system, location] where a lost ship is rebuilt: always the Core's station (main._respawn)
# Station storage: one store shared by every station. What's in it is safe; everything carried in the ship
# (cargo, materials, spices, spare weapons and modules, probes, portable wormholes) is lost with the ship.
var storage := {"materials": {}, "spices": {}, "weapons": {}, "modules": {}, "cargo": {}, "probes": 0, "portals": 0}  # "materials" / "spices" / "weapons" / "modules": {id: n}, "cargo": {"ore:q": n}, "probes": n, "portals": n
var auto_store := true  # put everything carried into storage whenever you dock
var docked := false  # (main sets it) at a station: storage can be drawn on for building and fitting
var dirty := false  # something changed since the last save
var playtime := 0.0
var no_save := false  # set by the screenshot test so it never touches the player's save
var save_root := "user://"  # where the saves live (the save test points this at a scratch folder)
var save_path := "user://driftlight_save.json"
var save_slot := "pilot"  # which save slot is in use
var in_game := false  # a game is loaded or started: before that (on the title) there's nothing of the player's to save
var load_error := ""  # why the last load failed
var save_too_new := 0  # the save was made by this newer version of the game, so this copy won't touch it
var loaded_backup := ""  # the save was missing or unusable and this backup was loaded instead
var _backup_at := 0.0  # playtime at the last rolling backup
var sandbox := false  # playing the sandbox slot
var god := false  # sandbox: can't be hurt
var peaceful := false  # sandbox: no pirates
var reset_note := false  # old saves were set aside this run (v8 started everyone over)
var away_time := 0.0  # how long the game was closed before this save was loaded
var away_smelted := 0  # materials the furnaces made in that time
var skip_wild_warning := false  # "don't show this again" was ticked on the Wild space warnings (settings.cfg)
var swap_ws := true  # W dips the nose and S lifts it (a setting in the ESC menu, saved in settings.cfg)
var _portable_rate := 0.0  # Portable Refinery: ore per minute
var _portable_t := 0.0

# --- galaxy ---
var systems := []
var anomalies := []  # {"sys": system id, "loc": location index}
var current_system := 0
var current_loc := 0
var route_target := -1
var gen_ms := 0


func _init() -> void:
	_expand_ships()
	_expand_weapons()
	_expand_modules()


## SHIPS: the hand-built ships plus the generated fleet, each with its build cost; SHIP_ORDER cheapest first.
func _expand_ships() -> void:
	for id in SHIP_BASE:
		var s: Dictionary = SHIP_BASE[id].duplicate(true)
		s["cost"] = {} if s.tier == 0 else _ship_cost(s.tier, s.role)
		s.cost.merge(s.get("spice", {}))
		SHIPS[id] = s
	for f in FLEET:
		var id: String = f[0]
		var tier: int = f[4]
		var s := {"name": f[1], "class": f[2], "role": f[3], "tier": tier, "guns": f[5], "desc": f[7]}
		var acc := Color(f[6])
		s["colors"] = [acc.lightened(0.4), acc, acc.lightened(0.6)]
		if CAPITALS.has(id):
			var c: Dictionary = CAPITALS[id]
			for k in ["hull", "shield", "speed", "turn", "cargo", "modules", "energy", "bonus", "jump"]:
				s[k] = c[k]
			s["cost"] = c.cost.duplicate()
			s["capital"] = true
			s["refinery"] = c.get("refinery", false)
		else:
			var r: Dictionary = ROLE_STATS[f[3]]
			var g := pow(1.45, tier - 1)
			s["hull"] = roundi(r.hull * g / 10.0) * 10
			s["shield"] = roundi(r.shield * g / 10.0) * 10
			s["speed"] = r.speed - tier * 6
			s["turn"] = snappedf(maxf(0.8, r.turn - tier * 0.12), 0.1)
			s["cargo"] = roundi(r.cargo * g / 5.0) * 5
			s["energy"] = r.energy + tier * 6
			s["modules"] = mini(r.modules + floori(tier / 2.0), 8)
			var bonus: Dictionary = r.bonus.duplicate()
			for k in bonus:  # bonuses grow a little with tier
				bonus[k] = snappedf(bonus[k] + (0.04 * tier if bonus[k] > 1.0 else -0.02 * tier), 0.01)
			s["bonus"] = bonus
			s["cost"] = _ship_cost(tier, f[3])
			s["refinery"] = f[3] in REFINERY_ROLES
		SHIPS[id] = s
	SHIP_ORDER = SHIPS.keys()
	SHIP_ORDER.sort_custom(func(a, b): return SHIPS[a].tier < SHIPS[b].tier or (SHIPS[a].tier == SHIPS[b].tier and
		_cost_value(SHIPS[a].cost) < _cost_value(SHIPS[b].cost)))


## What a ship of this tier and role takes to build (before BUILD_COST_MULT): common ores, and from tier 3 on
## the ores of the regions further and further out.
func _ship_cost(tier: int, role: String) -> Dictionary:
	var sec: String = "verdite" if role in ["fighter", "scout", "explorer", "stealth"] else "ambrite"
	var uns: String = {"fighter": "cindrite", "gunship": "cindrite", "explorer": "glacite", "stealth": "glacite",
		"scout": "glacite"}.get(role, "tidestone")
	var wld: String = {"fighter": "infernite", "gunship": "infernite", "explorer": "shroudium", "stealth": "shroudium"}.get(role,
		"starglass")
	var t: Dictionary = [{}, {"corrite": 70, "ferrox": 25},
		{"corrite": 180, "ferrox": 70, "lumenite": 25},
		{"ferrox": 200, "lumenite": 90, "cryonite": 30, sec: 25},
		{"lumenite": 220, "cryonite": 110, "vexium": 50, sec: 60},
		{"cryonite": 280, "vexium": 160, "aurelite": 50, sec: 80, uns: 30},
		{"vexium": 450, "aurelite": 200, "nyxium": 40, uns: 90},
		{"ferrox": 2000, "aurelite": 450, "nyxium": 140, "prismium": 15, uns: 160, wld: 40},
		{"aurelite": 1100, "nyxium": 400, "prismium": 80, wld: 140, "riftcore": 30}][tier]
	var k: float = {"scout": 0.8, "fighter": 1.0, "miner": 0.9, "hauler": 0.9, "explorer": 1.0, "tank": 1.15, "gunship": 1.25,
		"stealth": 1.1}.get(role, 1.0)
	var out := {}
	for id in t:
		out[id] = maxi(5, roundi(t[id] * k / 5.0) * 5)
	return out


## Rough credit worth of a cost (for sorting).
func _cost_value(cost: Dictionary) -> int:
	var v := 0
	for k in cost:
		v += cost[k] * (ORES[k].value if ORES.has(k) else 100)
	return v


## WEAPONS: every base weapon as Mk I, plus Mk II to Mk V each built from the mark below.
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
			w.size = Vector2(base.size) * (1.0 + 0.12 * t)
			w.color = Color(base.color).lightened(0.08 * t)
			if t > 0:
				var cost := {}
				for k in base.cost:
					cost[k] = ceili(base.cost[k] * tier.cost)
				if base.cost.is_empty():  # the Blaster (free at Mk I)
					cost = [{}, {"corrite": 60}, {"corrite": 200, "ferrox": 60}, {"ferrox": 300, "lumenite": 100},
						{"ferrox": 800, "vexium": 150}][t]
				if tier.region >= 0:
					cost[WEAPON_REGION[id][tier.region]] = [20, 40, 60][tier.region]
				if id != BLASTER or t > 1:
					cost["w:" + prev] = 1
				w.cost = cost
				w.desc = "%s Mark %s: harder hitting and faster. Built from a %s." % [base.desc, MK[t], WEAPONS[prev].name]
			WEAPONS[wid] = w
			WEAPON_ORDER.append(wid)
			prev = wid


## MODULES: every base module as Mk I, plus Mk II and Mk III (stronger, each built from the mark below).
func _expand_modules() -> void:
	for id in MODULE_BASE_ORDER:
		var base: Dictionary = MODULE_BASE[id]
		var prev := ""
		for t in MODULE_TIERS.size():
			if t > 0 and base.fx.has("sense_add"):
				break  # (a sense either works or it doesn't)
			var tier: Dictionary = MODULE_TIERS[t]
			var mid: String = id if t == 0 else "%s_mk%d" % [id, t + 1]
			var m: Dictionary = base.duplicate(true)
			m["tier"] = t + 1
			m["base"] = id
			m.name = base.name + tier.suffix
			var fx := {}
			for k in base.fx:
				var v: float = base.fx[k]
				if k.ends_with("_mul"):
					fx[k] = 1.0 + (v - 1.0) * tier.k if v >= 1.0 else maxf(0.3, 1.0 - (1.0 - v) * (1.0 + (tier.k - 1.0) * 0.6))
				else:
					fx[k] = v * tier.k if k != "salvage_add" else v + t
			m.fx = fx
			m["desc"] = fx_text(fx) + ("  (Mining and hauling ships only.)" if base.has("only") else "")
			if t > 0:
				var cost := {}
				for k in base.cost:
					cost[k] = ceili(base.cost[k] * tier.cost)
				if t == 2:
					cost[MODULE_REGION[base.cat]] = cost.get(MODULE_REGION[base.cat], 0) + 30
				cost["m:" + prev] = 1
				m.cost = cost
			MODULES[mid] = m
			MODULE_ORDER.append(mid)
			prev = mid


## A module's effects in words.
static func fx_text(fx: Dictionary) -> String:
	var parts := []
	for k in fx:
		var v: float = fx[k]
		var pc := roundi(absf(v - 1.0) * 100.0)
		match k:
			"cargo_add": parts.append("+%d cargo space" % v)
			"cargo_mul": parts.append("+%d%% cargo space" % pc)
			"shield_add": parts.append("+%d max shield" % v)
			"shield_rate_mul": parts.append("shields recharge %d%% faster" % pc)
			"shield_delay_mul": parts.append("and start sooner")
			"hull_add": parts.append("+%d max hull" % v)
			"armor_mul": parts.append("take %d%% less damage" % pc)
			"speed_mul": parts.append(("+%d%% top speed" if v > 1.0 else "-%d%% top speed") % pc)
			"turn_mul": parts.append("+%d%% turn rate" % pc)
			"energy_mul": parts.append("+%d%% boost energy" % pc)
			"energy_regen_mul": parts.append("+%d%% boost recharge" % pc)
			"regen_add": parts.append("repairs %.1f hull per second" % v)
			"mining_mul": parts.append("+%d%% mining power" % pc)
			"tractor_add": parts.append("+%d m tractor beam reach" % v)
			"refine_add": parts.append("smelts %d ore a minute straight from your hold" % roundi(v))
			"fire_mul": parts.append("+%d%% fire rate" % pc)
			"damage_mul": parts.append("+%d%% damage" % pc)
			"bolt_mul": parts.append("shots fly %d%% faster and further" % pc)
			"probe_mul": parts.append("probes fly %d%% longer" % pc)
			"scan_mul": parts.append("+%d%% survey scanner reach, faster recharge" % pc)
			"sense_add": parts.append("pings hidden anomalies whenever you arrive in a Wild system")
			"warp_mul": parts.append("warps and jumps charge %d%% faster" % pc)
			"stealth_mul": parts.append("pirates notice you %d%% later" % pc)
			"salvage_add": parts.append("wrecks and relics give x%d loot" % (v + 1))
	var s := ", ".join(parts)
	return s.substr(0, 1).to_upper() + s.substr(1) + "."


func _ready() -> void:
	# the user's layout: W/S pitch the nose, Q/E turn, A/D roll, R/F work the throttle
	_key("move_up", [KEY_R])
	_key("move_down", [KEY_F])
	_key("yaw_left", [KEY_Q, KEY_LEFT])
	_key("yaw_right", [KEY_E, KEY_RIGHT])
	set_swap_ws(swap_ws)
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
	_key("auto_travel", [KEY_T])
	_key("guide", [KEY_H])
	if not InputMap.has_action("fire"):
		InputMap.add_action("fire")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("fire", mb)
	generate_galaxy()
	changed.connect(_on_changed)


func _on_changed() -> void:
	dirty = true
	_portable_rate = stats_ship().refine


## W and S pitch the nose. Swapped (the default), W dips it and S lifts it, like pushing and pulling a flight
## stick; otherwise W lifts and S dips. The arrow keys stay as they are (Up lifts, Down dips).
func set_swap_ws(on: bool) -> void:
	swap_ws = on
	for a in ["pitch_up", "pitch_down"]:
		if InputMap.has_action(a):
			InputMap.erase_action(a)
	_key("pitch_up", [KEY_S if on else KEY_W, KEY_UP])
	_key("pitch_down", [KEY_W if on else KEY_S, KEY_DOWN])


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
	_tick_portable(delta)
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
	portals = 0
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
	relics_done = []
	refineries = {}
	notebook = {}
	pinned = []
	route_stops = []
	regions_seen = {}
	regional_seen = {}
	home = [0, 0]
	storage = _empty_storage()
	auto_store = true
	playtime = 0.0
	_backup_at = 0.0
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
		systems.append({"id": i, "name": nm, "initials": _initials(nm), "pos": pts[i], "cat": cat, "region": region_at(pts[i], cat),
			"depth": d, "links": [], "locs": [], "visited": i == 0})
	_link_systems(rng)
	for sys in systems:
		_gen_locations(sys, rng)
	_setup_core()
	_pair_wormholes(rng)
	gen_ms = Time.get_ticks_msec() - started


## Which region a system at galaxy-map position `p` (in ring `cat`) belongs to: its ring's sector by angle.
static func region_at(p: Vector2, cat: int) -> int:
	if cat == CAT_BLUE:
		return 0
	var n: int = REGION_COUNT[cat]
	var a := fposmod(atan2(p.y, p.x) + REGION_TWIST[cat], TAU)
	return REGION_FIRST[cat] + mini(floori(a / (TAU / n)), n - 1)


# Stars, by kind: [name, colour, size (sun = 1), light, chance]. A system's star sits at its centre.
const STAR_KINDS := [
	["Red dwarf", Color(1.0, 0.5, 0.32), 0.55, 1.5, 30],
	["Orange star", Color(1.0, 0.72, 0.45), 0.8, 1.85, 20],
	["Yellow star", Color(1.0, 0.92, 0.78), 1.0, 2.1, 18],
	["White star", Color(0.93, 0.96, 1.0), 1.25, 2.35, 12],
	["Blue giant", Color(0.62, 0.76, 1.0), 2.0, 2.7, 7],
	["Red giant", Color(1.0, 0.42, 0.22), 4.2, 1.8, 6],
	["White dwarf", Color(0.85, 0.92, 1.0), 0.28, 1.6, 4],
	["Yellow giant", Color(1.0, 0.82, 0.5), 2.8, 2.2, 3],
]
# Nebula palettes, after real ones: each [glowing gas, second gas, filaments / dust glow]
const NEBULA_PALETTES := [
	[Color(1.0, 0.24, 0.36), Color(0.18, 0.74, 0.82), Color(0.95, 0.62, 0.3)],  # emission: hydrogen red, oxygen teal, gold
	[Color(0.95, 0.3, 0.62), Color(0.33, 0.5, 1.0), Color(1.0, 0.72, 0.48)],  # orion
	[Color(1.0, 0.55, 0.2), Color(0.22, 0.7, 0.68), Color(0.75, 0.16, 0.16)],  # carina
	[Color(0.3, 0.55, 1.0), Color(0.56, 0.36, 0.96), Color(0.78, 0.88, 1.0)],  # reflection
	[Color(0.2, 0.88, 0.95), Color(1.0, 0.3, 0.26), Color(0.62, 0.32, 0.92)],  # veil
	[Color(0.96, 0.74, 0.34), Color(0.3, 0.8, 0.56), Color(0.78, 0.32, 0.16)],  # eagle
	[Color(1.0, 0.36, 0.46), Color(0.82, 0.12, 0.22), Color(1.0, 0.86, 0.62)],  # rosette
	[Color(1.0, 0.46, 0.66), Color(0.46, 0.7, 1.0), Color(0.76, 0.56, 1.0)],  # lagoon
	[Color(0.58, 0.4, 0.28), Color(0.92, 0.56, 0.26), Color(0.36, 0.46, 0.72)],  # dark dust
	[Color(0.72, 0.3, 1.0), Color(1.0, 0.2, 0.72), Color(0.2, 0.8, 1.0)],  # wild violet
]
# how likely each palette is, by kind of space (Core, Secure, Unsecure, Wild)
const PALETTE_WEIGHTS := [[3, 3, 1, 5, 1, 3, 1, 4, 5, 0], [4, 4, 3, 3, 3, 4, 3, 3, 3, 1], [5, 3, 5, 1, 4, 3, 5, 2, 3, 2],
	[3, 3, 3, 2, 4, 2, 3, 3, 2, 6]]
var _looks := {}


## How a system looks: its star, the colours of its nebulae and where they lie in its sky, the galactic band.
## The same every time (worked out from its id).
func system_look(sys: Dictionary) -> Dictionary:
	var id: int = sys.id
	if _looks.has(id):
		return _looks[id]
	var rng := RandomNumberGenerator.new()
	rng.seed = id * 7919 + 13
	var kinds := STAR_KINDS.map(func(k): return k[4])
	var k: Array = STAR_KINDS[pick_weighted(kinds, rng)] if id != 0 else STAR_KINDS[2]
	var pal: Array = NEBULA_PALETTES[pick_weighted(PALETTE_WEIGHTS[sys.cat], rng)]
	var shift := rng.randf_range(-0.04, 0.04)  # a little hue shift of its own
	var cols := pal.map(func(c): return Color.from_hsv(fposmod(c.h + shift, 1.0), c.s, c.v))
	var look := {"star": k[0], "star_color": k[1], "star_size": k[2] * rng.randf_range(0.85, 1.15), "star_light": k[3],
		"binary": rng.randf() < 0.12, "c1": cols[0], "c2": cols[1], "c3": cols[2],
		"nebula": rng.randf_range(0.35, 1.25) * (1.25 if sys.cat == CAT_PURPLE else 1.0),
		"neb_dir": Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 0.8), rng.randf_range(-1, 1)).normalized(),
		"neb_size": rng.randf_range(0.15, 0.6), "neb_dir2": Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.8, 0.8),
		rng.randf_range(-1, 1)).normalized(), "neb_size2": rng.randf_range(0.55, 0.85),
		"band_axis": Vector3(rng.randf_range(-1, 1), rng.randf_range(0.3, 1.0), rng.randf_range(-1, 1)).normalized(),
		"band": rng.randf_range(0.6, 1.4), "stars": rng.randf_range(0.7, 1.4), "seed": rng.randf() * 100.0,
		"yaw": rng.randf() * TAU, "tilt": rng.randf_range(0.05, 0.4), "turb": rng.randf_range(1.6, 3.4),
		"lanes": rng.randf_range(0.35, 0.95)}
	if look.binary:
		var c2: Array = STAR_KINDS[pick_weighted(kinds, rng)]
		look["companion_color"] = c2[1]
		look["companion_size"] = minf(c2[2], 1.2) * rng.randf_range(0.5, 0.9)
		look["star"] += " + " + c2[0].to_lower()
	_looks[id] = look
	return look


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
		"wreck": false, "relic": false, "planet_type": "rocky", "seed": 0, "gate_to": -1, "anom": -1, "wormhole": -1}


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
		# Wild stations are rarer since v12 (12% -> 3%). The draws stay exactly as they were (the old, higher chance
		# decides whether the refinery draw is made), so nothing else in the galaxy moves.
		var st_draw := rng.randf()
		var had_station: bool = st_draw < [0.45, 0.3, 0.0, 0.12][cat]
		loc.station = st_draw < [0.45, 0.3, 0.0, 0.03][cat]
		var rf_draw := rng.randf() if had_station else 1.0
		loc.refinery = loc.station and rf_draw < [0.85, 0.6, 0.0, 0.5][cat]
		loc.obelisk = rng.randf() < [0.0, 0.0, 0.2, 0.22][cat]  # offerings only out in red and Wild space
		loc.spice = rng.randf() < [0.08, 0.15, 0.35, 0.25][cat]
		loc.wreck = rng.randf() < [0.1, 0.2, 0.35, 0.45][cat]
		loc.relic = rng.randf() < [0.0, 0.0, 0.004, 0.015][cat]  # ancient relics: deep space only, and very rare (v12)
		loc.pirates = rng.randf() < PIRATE_CHANCE[cat] and not loc.station  # (never where there's a station)
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
			loc.relic = rng.randf() < 0.03
			anomalies.append({"sys": sys.id, "loc": sys.locs.size()})
			sys.locs.append(loc)


func _setup_core() -> void:
	var core: Dictionary = systems[0]
	var names := ["Core Station", "Core Belt", "Halden's Rest", "Rustfall Drift"]
	for i in 4:
		var l: Dictionary = core.locs[i]
		l.name = names[i]
		l.scanned = true
		for f in ["ore", "station", "refinery", "obelisk", "spice", "pirates", "wreck", "relic"]:
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


## Arrived at the route's target: on to the next stop, if there is one. Returns true if the route goes on.
func next_stop() -> bool:
	route_target = -1
	while not route_stops.is_empty():
		var s: int = route_stops.pop_front()
		if s != current_system:
			route_target = s
			changed.emit()
			return true
	changed.emit()
	return false


## Add a stop to the end of the route (or start one).
func add_stop(id: int) -> void:
	if route_target < 0:
		route_target = id
	elif id != route_target and (route_stops.is_empty() or route_stops[-1] != id):
		route_stops.append(id)
	changed.emit()


func clear_route() -> void:
	route_target = -1
	route_stops = []
	changed.emit()


## Jumps in the whole route: to the target, then stop to stop.
func route_jumps() -> int:
	var n := route_path().size()
	var at := route_target
	for s in route_stops:
		if at >= 0:
			n += find_path(at, s).size()
		at = s
	return n


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
	if l.get("relic", false):
		parts.append("Relic")
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


## Returns [ore_id, quality] for a new rock in this system: now and then its region's own ore (never
## Inferior), otherwise one of the common ores.
func roll_ore(sys: Dictionary, anomaly: bool) -> Array:
	var reg: Dictionary = REGIONS[sys.get("region", 0)]
	if reg.ore != "" and randf() < (0.3 if anomaly else REGION_CHANCE):
		return [reg.ore, pick_weighted(REGION_ANOMALY_Q if anomaly else REGION_Q)]
	var w: Array
	if anomaly:
		w = ANOMALY_ORE_WEIGHTS.duplicate()
	else:
		w = ORE_WEIGHTS[sys.cat].duplicate()
		for t in range(1, w.size()):
			w[t] = w[t] * (1.0 + sys.depth * t * 0.5)
	var ore: String = BASE_ORES[pick_weighted(w)]
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


## Where an ore can be found, in words (no secrets: just the kind of space, or its region).
func ore_where(ore: String) -> String:
	var o: Dictionary = ORES[ore]
	if o.has("region"):
		return "%s only (%s space)" % [REGIONS[o.region].name, CAT_NAMES[REGIONS[o.region].cat]]
	return ["Everywhere, most in the Core", "Everywhere", "Secure space and further out", "Secure space and further out",
		"Unsecure and Wild space", "Unsecure and Wild space", "Wild space", "Wild anomalies"][o.tier]


# ---------------------------------------------------------------- notebook

## Write what's known about a place into the notebook (stations, refineries, ore seen there...).
func note_loc(sys_id: int, loc_i: int, ores := []) -> void:
	var l: Dictionary = systems[sys_id].locs[loc_i]
	if l.kind == "gate":
		return
	var key := "%d:%d" % [sys_id, loc_i]
	var fresh := not notebook.has(key)
	var e: Dictionary = notebook.get(key, {"sys": sys_id, "loc": loc_i, "tags": [], "ores": []})
	var tags := []
	if l.kind == "anomaly":
		tags.append("anomaly")
		if l.wormhole >= 0:
			tags.append("wormhole")
	for f in ["station", "refinery", "ore", "obelisk", "spice", "wreck", "pirates", "relic"]:
		if l.get(f, false):
			tags.append(f)
	e.tags = tags
	for o in ores:
		if not e.ores.has(o):
			e.ores.append(o)
	if tags.is_empty() and e.ores.is_empty():
		return
	notebook[key] = e
	if fresh:
		bump("noted")


## Notebook entries with a tag (or holding an ore), nearest first: [{"key", "sys", "loc", "jumps"}].
func notes_with(tag: String, ore := "") -> Array:
	var out := []
	var near := systems_within(current_system, 0, 60)
	for key in notebook:
		var e: Dictionary = notebook[key]
		if (tag != "" and not e.tags.has(tag)) or (ore != "" and not e.ores.has(ore)):
			continue
		out.append({"key": key, "sys": int(e.sys), "loc": int(e.loc), "jumps": near.get(int(e.sys), 99)})
	out.sort_custom(func(a, b): return a.jumps < b.jumps)
	return out


# ---------------------------------------------------------------- inventory

func item_name(id: String) -> String:
	if id == "credits":
		return "Credits"
	if id.begins_with("w:"):
		return WEAPONS[id.substr(2)].name
	if id.begins_with("m:"):
		return MODULES[id.substr(2)].name
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
	if id.begins_with("m:"):
		return module_color(id.substr(2))
	if ORES.has(id):
		return ORES[id].color
	if SPICES.has(id):
		return SPICES[id].color
	return Color.WHITE


func module_color(id: String) -> Color:
	return MODULE_CATS[MODULES[id].cat].color


func module_icon(id: String) -> String:
	return MODULE_CATS[MODULES[id].cat].icon


## How many you have of a cost item - carried and in station storage together: credits, a material, a spice,
## or ("w:<id>" / "m:<id>") a spare weapon or module.
func have(id: String) -> int:
	if id == "credits":
		return credits
	return carried(id) + stored(id)


## How many of a cost item the ship is carrying (lost if it's destroyed).
func carried(id: String) -> int:
	if id.begins_with("w:"):
		return weapon_stock.get(id.substr(2), 0)
	if id.begins_with("m:"):
		return module_stock.get(id.substr(2), 0)
	if ORES.has(id):
		return materials.get(id, 0)
	return spices.get(id, 0)


## How many of a cost item are in station storage.
func stored(id: String) -> int:
	if id.begins_with("w:"):
		return storage.weapons.get(id.substr(2), 0)
	if id.begins_with("m:"):
		return storage.modules.get(id.substr(2), 0)
	if ORES.has(id):
		return storage.materials.get(id, 0)
	return storage.spices.get(id, 0)


## Use up `n` of a cost item: from what the ship carries first, then from storage.
func take(id: String, n: int) -> void:
	var from_ship := mini(n, carried(id))
	give(id, -from_ship)
	n -= from_ship
	if n > 0:
		var d: Dictionary = _store_dict(id)
		var key := id.substr(2) if id.begins_with("w:") or id.begins_with("m:") else id
		d[key] = d.get(key, 0) - n
		if d[key] <= 0:
			d.erase(key)


func _store_dict(id: String) -> Dictionary:
	if id.begins_with("w:"):
		return storage.weapons
	if id.begins_with("m:"):
		return storage.modules
	return storage.materials if ORES.has(id) else storage.spices


static func _empty_storage() -> Dictionary:
	return {"materials": {}, "spices": {}, "weapons": {}, "modules": {}, "cargo": {}, "probes": 0, "portals": 0}


## Put everything the ship carries into station storage (cargo, materials, spices, spare gear, probes,
## portable wormholes). Returns how many things moved. `probes_too` false (the automatic store when docking)
## leaves your probes on the ship: you want them with you.
func store_all(probes_too := true) -> int:
	var n := 0
	for pair in [[materials, storage.materials], [spices, storage.spices], [weapon_stock, storage.weapons],
			[module_stock, storage.modules], [cargo, storage.cargo]]:
		var src: Dictionary = pair[0]
		var dst: Dictionary = pair[1]
		for k in src.keys():
			if src[k] > 0:
				dst[k] = dst.get(k, 0) + src[k]
				n += src[k]
		src.clear()
	if probes_too:
		n += probes
		storage.probes += probes
		probes = 0
	n += portals
	storage.portals += portals
	portals = 0
	changed.emit()
	return n


## Move one stack between the ship and storage. kind: materials, spices, weapons, modules, cargo, probes,
## portals. to_ship false stores it.
func move_stack(kind: String, key: String, to_ship: bool) -> void:
	var ship_side: Dictionary = {"materials": materials, "spices": spices, "weapons": weapon_stock, "modules": module_stock,
		"cargo": cargo}.get(kind, {})
	if kind in ["probes", "portals"]:
		var n: int = storage[kind] if to_ship else get(kind)
		if to_ship:
			set(kind, get(kind) + n)
			storage[kind] = 0
		else:
			storage[kind] += n
			set(kind, 0)
		changed.emit()
		return
	var src: Dictionary = storage[kind] if to_ship else ship_side
	var dst: Dictionary = ship_side if to_ship else storage[kind]
	var n: int = src.get(key, 0)
	if kind == "cargo" and to_ship:
		n = mini(n, stats_ship().cargo - cargo_used())  # only as much as the hold has room for
	if n <= 0:
		return
	dst[key] = dst.get(key, 0) + n
	src[key] -= n
	if src[key] <= 0:
		src.erase(key)
	changed.emit()


## The ship is lost: everything it carried goes with it. Returns a description of what was lost.
func lose_carried() -> String:
	var lost := []
	var ore := cargo_used()
	if ore > 0:
		lost.append("%d ore" % ore)
	var mats := 0
	for k in materials:
		mats += materials[k]
	if mats > 0:
		lost.append("%d materials" % mats)
	var gear := 0
	for d in [weapon_stock, module_stock]:
		for k in d:
			gear += d[k]
	if gear > 0:
		lost.append("%d spare weapons and modules" % gear)
	var sp := 0
	for k in spices:
		sp += spices[k]
	if sp > 0:
		lost.append("%d spices" % sp)
	if probes > 0:
		lost.append("%d probes" % probes)
	if portals > 0:
		lost.append("%d portable wormholes" % portals)
	cargo.clear()
	materials.clear()
	weapon_stock.clear()
	module_stock.clear()
	spices.clear()
	probes = 0
	portals = 0
	changed.emit()
	return ", ".join(lost)


func give(id: String, n: int) -> void:
	if id == "credits":
		credits += n
	elif id.begins_with("w:"):
		weapon_stock[id.substr(2)] = weapon_stock.get(id.substr(2), 0) + n
	elif id.begins_with("m:"):
		module_stock[id.substr(2)] = module_stock.get(id.substr(2), 0) + n
	elif ORES.has(id):
		materials[id] = materials.get(id, 0) + n
	else:
		spices[id] = spices.get(id, 0) + n


func add_credits(n: int) -> void:
	credits += n
	bump("earned", n)
	changed.emit()


## Credits for charting something, with a note saying so.
func _payout(n: int, why: String) -> void:
	if n <= 0:
		return
	add_credits(n)
	say("%s  +%d credits" % [why, n], Color("ffd24a"))


func can_afford(cost: Dictionary) -> bool:
	if sandbox:
		return true  # everything is free in the sandbox
	for id in cost:
		if have(id) < cost[id]:
			return false
	return true


func pay(cost: Dictionary) -> void:
	if sandbox:
		return
	for id in cost:
		if id == "credits":
			credits -= cost[id]
		else:
			take(id, cost[id])


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
	return REFINE_TIME[q] * (1.0 + ORES[ore].tier * 0.12)


## Mining power needed to break one piece of this ore off a rock.
func hardness(ore: String) -> float:
	return MINE_COST * (1.0 + ORES[ore].tier * HARDNESS_PER_TIER)


func refinery(key: String, station_name := "") -> Dictionary:
	if not refineries.has(key):
		refineries[key] = {"name": station_name, "queue": [], "progress": 0.0, "output": {}}
	if station_name != "":
		refineries[key].name = station_name
	return refineries[key]


## Move one cargo stack (from the hold, or raw ore kept in storage) into a station's furnace queue.
func load_ore(key: String, station_name: String, cargo_key: String, from_storage := false) -> void:
	var src: Dictionary = storage.cargo if from_storage else cargo
	var n: int = src.get(cargo_key, 0)
	if n <= 0:
		return
	var parts: PackedStringArray = cargo_key.split(":")
	var q: Array = refinery(key, station_name).queue
	if not q.is_empty() and q[-1][0] == parts[0] and q[-1][1] == int(parts[1]):
		q[-1][2] += n
	else:
		q.append([parts[0], int(parts[1]), n])
	src.erase(cargo_key)
	changed.emit()


func load_all(key: String, station_name: String) -> void:
	for k in cargo.keys():
		load_ore(key, station_name, k)
	for k in storage.cargo.keys():
		load_ore(key, station_name, k, true)


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


## A Portable Refinery (or a forge ship) slowly smelts ore straight out of the hold into materials.
func _tick_portable(delta: float) -> void:
	if _portable_rate <= 0.0 or cargo.is_empty():
		_portable_t = 0.0
		return
	_portable_t += delta * _portable_rate / 60.0
	if _portable_t < 1.0:
		return
	_portable_t -= 1.0
	# the best ore first
	var keys := cargo.keys()
	keys.sort_custom(func(a, b): return int(a.get_slice(":", 1)) > int(b.get_slice(":", 1)))
	var key: String = keys[0]
	var ore := key.get_slice(":", 0)
	var q := int(key.get_slice(":", 1))
	cargo[key] -= 1
	if cargo[key] <= 0:
		cargo.erase(key)
	give(ore, Q_YIELD[q])
	bump("refined", Q_YIELD[q])
	changed.emit()


## Finished materials waiting in furnaces, all stations together.
func furnace_output() -> int:
	var n := 0
	for key in refineries:
		for id in refineries[key].output:
			n += refineries[key].output[id]
	return n


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
		storage.materials[id] = storage.materials.get(id, 0) + out[id]  # straight into station storage, safe
	if not out.is_empty():
		changed.emit()
	return out


## Throw a cargo stack out of the hold: it tumbles out behind the ship as loose ore you can pick up again.
func jettison(key: String) -> void:
	var parts: PackedStringArray = key.split(":")
	var n: int = cargo.get(key, 0)
	if n <= 0:
		return
	say("Jettisoned %d %s." % [n, ore_label(parts[0], int(parts[1]))], Color("8a94a8"))
	cargo.erase(key)
	jettisoned.emit(parts[0], int(parts[1]), n)
	changed.emit()


func sell_price(ore: String, cat: int) -> int:
	return maxi(1, roundi(ORES[ore].value * CAT_PRICE[cat]))


func buy_price(ore: String) -> int:
	return ORES[ore].value * 3 * PRICE_MULT


func sell(ore: String, n: int, cat: int) -> void:
	n = mini(n, have(ore))
	if n <= 0:
		return
	take(ore, n)
	add_credits(n * sell_price(ore, cat))
	say("Sold %d %s for %d credits." % [n, ORES[ore].name, n * sell_price(ore, cat)], Color("ffd24a"))


func sell_portal() -> void:
	if portals <= 0 and storage.portals <= 0:
		return
	if portals > 0:
		portals -= 1
	else:
		storage.portals -= 1
	add_credits(WORMHOLE_PRICE)
	say("Sold a portable wormhole for %d credits." % WORMHOLE_PRICE, Color("ffd24a"))


func buy(id: String, n: int) -> bool:
	var price := 0 if sandbox else (PROBE_PRICE * n if id == "probe" else buy_price(id) * n)
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
## anything worth having takes a lot of ore (probes stay cheap; spices and parts aren't multiplied).
func build_cost(kind: String, id: String, mult := BUILD_COST_MULT) -> Dictionary:
	var base: Dictionary
	match kind:
		"ship": base = SHIPS[id].cost
		"weapon": base = WEAPONS[id].cost
		"module": base = MODULES[id].cost
		_: return PROBE_COST
	var out := {}
	for k in base:
		out[k] = base[k] * (mult if ORES.has(k) else 1)
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
	var cost := build_cost(kind, id, MARKET_BASIS)
	var markup := MARKET_MARKUP * PRICE_MULT
	for k in cost:
		var each := 0
		if k.begins_with("w:"):
			each = roundi(market_price("weapon", k.substr(2)) / markup)  # the mark below, at its own worth
		elif k.begins_with("m:"):
			each = roundi(market_price("module", k.substr(2)) / markup)
		else:
			each = ORES[k].value if ORES.has(k) else [30, 80, 200, 500][SPICES[k].rarity]
		total += each * cost[k]
	return maxi(50 * PRICE_MULT, roundi(total * markup / 10.0) * 10)


func buy_ready_made(kind: String, id: String) -> bool:
	var price := 0 if sandbox else market_price(kind, id)
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
		"weapon":
			weapon_stock[id] = weapon_stock.get(id, 0) + 1
			if WEAPONS[id].tier == 5:
				bump("mk5")
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


## Pin a recipe to the HUD (or unpin it). Up to MAX_PINS at once.
func toggle_pin(kind: String, id: String) -> void:
	for i in pinned.size():
		if pinned[i][0] == kind and pinned[i][1] == id:
			pinned.remove_at(i)
			changed.emit()
			return
	if pinned.size() >= MAX_PINS:
		pinned.pop_front()
	pinned.append([kind, id])
	changed.emit()


func is_pinned(kind: String, id: String) -> bool:
	return pinned.any(func(p): return p[0] == kind and p[1] == id)


func pin_name(p: Array) -> String:
	match p[0]:
		"ship": return SHIPS[p[1]].name
		"weapon": return WEAPONS[p[1]].name
		"module": return MODULES[p[1]].name
	return "?"


func board_ship(id: String) -> void:
	ship_id = id
	var slots: int = SHIPS[id].modules
	while modules_equipped.size() > slots:
		var m: String = modules_equipped.pop_back()
		module_stock[m] = module_stock.get(m, 0) + 1
	# a refinery that this ship can't carry goes back into storage
	if not SHIPS[id].get("refinery", false):
		for i in range(modules_equipped.size() - 1, -1, -1):
			if MODULES[modules_equipped[i]].has("only"):
				unequip_module(i)
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


## Spare weapons of a type you can fit right now: carried, plus station storage while docked.
func spare_weapon(id: String) -> int:
	return weapon_stock.get(id, 0) + (storage.weapons.get(id, 0) if docked else 0)


func spare_module(id: String) -> int:
	return module_stock.get(id, 0) + (storage.modules.get(id, 0) if docked else 0)


## Take one spare weapon / module out of the ship's stores (or, docked, station storage).
func _use_spare(stock: Dictionary, stored_d: Dictionary, id: String) -> void:
	if stock.get(id, 0) > 0:
		stock[id] -= 1
	else:
		stored_d[id] -= 1
		if stored_d[id] <= 0:
			stored_d.erase(id)


## Put a weapon in a gun slot; whatever was there goes back into the ship's stores.
func mount(slot: int, weapon: String) -> void:
	var l := loadout()
	var old: String = l[slot]
	if old == weapon:
		return
	if weapon != BLASTER:
		if spare_weapon(weapon) <= 0:
			return
		_use_spare(weapon_stock, storage.weapons, weapon)
	if old != BLASTER:
		weapon_stock[old] = weapon_stock.get(old, 0) + 1
	l[slot] = weapon
	changed.emit()


## Fill every slot of the current ship with as many of `weapon` as you have.
func mount_all(weapon: String) -> void:
	for i in loadout().size():
		mount(i, weapon)


## Weapons of this type you own, mounted (on any ship), carried or in storage.
func weapon_count(id: String) -> int:
	var n: int = weapon_stock.get(id, 0) + storage.weapons.get(id, 0)
	for ship in loadouts:
		n += loadouts[ship].count(id)
	return n


## Can the current ship carry this module (the Portable Refinery only fits mining and hauling ships)?
func module_fits(id: String) -> bool:
	return not MODULES[id].has("only") or SHIPS[ship_id].get("refinery", false)


func equip_module(id: String) -> void:
	if spare_module(id) <= 0 or modules_equipped.size() >= SHIPS[ship_id].modules:
		return
	if not module_fits(id):
		say("The %s only fits mining and hauling ships." % MODULES[id].name, Color("ff9a8a"))
		return
	_use_spare(module_stock, storage.modules, id)
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
		"tractor": 90.0, "regen": 0.0, "mining": b.get("mining", 1.0), "fire": b.get("fire", 1.0),
		"damage": b.get("damage", 1.0), "bolt": b.get("bolt", 1.0), "stealth": b.get("stealth", 1.0),
		"armor": 1.0, "shield_delay": 3.5, "shield_rate": 0.25, "probe": b.get("probe", 1.0), "warp": b.get("warp", 1.0),
		"salvage": 1, "refine": 60.0 if s.get("capital", false) and s.get("refinery", false) else 0.0, "scan": 1.0, "sense": 0.0,
		"jump": float(s.get("jump", 0)), "capital": s.get("capital", false)}
	for m in modules_equipped:
		var fx: Dictionary = MODULES[m].fx
		for k in fx:
			var v: float = fx[k]
			match k:
				"cargo_add": st.cargo += int(v)
				"cargo_mul": st.cargo = int(st.cargo * v)
				"shield_add": st.shield += v
				"shield_rate_mul": st.shield_rate *= v
				"shield_delay_mul": st.shield_delay *= v
				"hull_add": st.hull += v
				"armor_mul": st.armor *= v
				"speed_mul": st.speed *= v
				"turn_mul": st.turn *= v
				"energy_mul": st.energy *= v
				"energy_regen_mul": st.energy_regen *= v
				"regen_add": st.regen += v
				"mining_mul": st.mining *= v
				"tractor_add": st.tractor += v
				"refine_add": st.refine += v
				"fire_mul": st.fire *= v
				"damage_mul": st.damage *= v
				"bolt_mul": st.bolt *= v
				"probe_mul": st.probe *= v
				"scan_mul": st.scan *= v
				"sense_add": st.sense += v
				"warp_mul": st.warp *= v
				"stealth_mul": st.stealth *= v
				"salvage_add": st.salvage += int(v)
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
			var tier := clampi(r * 2 + randi() % 2, 0, BASE_ORES.size() - 1)
			var amount: int = maxi(4, 40 - tier * 5) * (r + 1)
			var ore: String = BASE_ORES[tier]
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


const RELIC_RESPAWN := 7 * 24 * 3600  # a decoded relic comes back after this many real seconds (a week)


## A relic was decoded (`when`: the unix time it was, now by default): it's gone for a week.
func mark_relic(sys_id: int, loc_i: int, when := -1.0) -> void:
	systems[sys_id].locs[loc_i].relic = false
	for r in relics_done:
		if r[0] == sys_id and r[1] == loc_i:
			return
	relics_done.append([sys_id, loc_i, Time.get_unix_time_from_system() if when < 0.0 else when])


## Bring back the relics that were decoded a week or more ago. Returns how many came back.
func refresh_relics() -> int:
	var now := Time.get_unix_time_from_system()
	var back := 0
	for i in range(relics_done.size() - 1, -1, -1):
		var r: Array = relics_done[i]
		if now - float(r[2]) >= RELIC_RESPAWN:
			systems[int(r[0])].locs[int(r[1])].relic = true
			relics_done.remove_at(i)
			back += 1
	return back


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
		var m: String = MODULE_BASE_ORDER.pick_random()
		module_stock[m] = module_stock.get(m, 0) + 1
		parts.append("a %s module!" % MODULES[m].name)
	if randf() < 0.2:
		var sp: String = SPICE_ORDER[pick_weighted(SPICE_WEIGHTS[cat])]
		give(sp, 1)
		parts.append(SPICES[sp].name)
	if cat == CAT_PURPLE and randf() < 0.04:
		portals += 1
		parts.append("a PORTABLE WORMHOLE!")
	event("salvage")
	changed.emit()
	return "Salvaged " + ", ".join(parts)


## Decoding an ancient relic: a big haul of the region's ore, credits, maybe a rare module, a star chart that
## reveals anomalies nearby, or (rarely) a portable wormhole.
func decode_relic(sys: Dictionary) -> String:
	var mult: int = stats_ship().salvage
	var cr: int = randi_range(300, 900) * int(sys.cat) * mult
	add_credits(cr)
	var parts := ["%d credits" % cr]
	var reg: Dictionary = REGIONS[sys.get("region", 0)]
	var ore: String = reg.ore if reg.ore != "" else "aurelite"
	var n := randi_range(20, 50) * mult
	give(ore, n)
	parts.append("%d %s" % [n, ORES[ore].name])
	if randf() < 0.35:
		var pick: String = MODULE_ORDER.filter(func(id): return MODULES[id].tier >= 2).pick_random()
		module_stock[pick] = module_stock.get(pick, 0) + 1
		parts.append("a %s!" % MODULES[pick].name)
	if randf() < 0.4:
		var near := systems_within(sys.id, 0, 4).keys()
		var told := 0
		for sid in near:
			for l in systems[sid].locs:
				if l.kind == "anomaly" and not l.found and told < 2:
					l.found = true
					told += 1
					event("anomaly")
		if told > 0:
			parts.append("a star chart showing %d hidden anomal%s nearby" % [told, "y" if told == 1 else "ies"])
	if randf() < 0.22:
		portals += 1
		parts.append("a PORTABLE WORMHOLE!")
	bump("relics")
	changed.emit()
	return "Decoded the relic: " + ", ".join(parts)


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


## Something happened in the world: count it, unlock achievements, advance missions, pay for charting.
func event(kind: String, data := {}) -> void:
	match kind:
		"ore":
			bump("ore", data.n)
			if data.q == 3:
				bump("pristine", data.n)
			if data.ore == "prismium":
				bump("prismium", data.n)
			if ORES[data.ore].has("region"):
				bump("regional", data.n)
				if not regional_seen.has(data.ore):
					regional_seen[data.ore] = true
					bump("regional_kinds")
					toast.emit("NEW REGIONAL ORE", "%s  -  %s" % [ORES[data.ore].name, ORES[data.ore].desc], "ore",
						ORES[data.ore].color)
			var l: Dictionary = systems[current_system].locs[current_loc]
			if l.kind == "anomaly":
				bump("anomaly_ore", data.n)
			note_loc(current_system, current_loc, [data.ore])
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
			var sys: Dictionary = systems[data.sys]
			if data.new:
				bump("systems")
				_payout(CHART_PAY[sys.cat], "Charted %s." % sys.name)
				if sys.cat == CAT_PURPLE:
					_advance("expedition", -1)
			if not regions_seen.has(sys.region):
				regions_seen[sys.region] = true
				bump("regions")
				var reg: Dictionary = REGIONS[sys.region]
				toast.emit("NEW REGION", "%s%s" % [reg.name, ("  -  home of %s" % ORES[reg.ore].name) if reg.ore != "" else ""],
					"planet", reg.color)
			if sys.cat == CAT_PURPLE:
				bump("wild")
			_advance("explore", data.sys)
		"jump":
			bump("jumps")
		"scan":
			bump("scans")
			_advance("survey", -1)
			_payout(SCAN_PAY[systems[current_system].cat], "Survey data sold.")
		"anomaly":
			bump("anomalies")
			_advance("anomaly", -1)
			_payout(ANOMALY_PAY, "Anomaly charted.")
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
			if SHIPS[data.id].get("capital", false):
				bump("capitals")
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
	for i in 6:
		var kind: String = ["bounty", "explore", "survey", "deliver", "deliver", "anomaly", "expedition", "regional"].pick_random()
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
				var tier := randi_range(0, mini(BASE_ORES.size() - 2, cat * 2 + 1))
				m.ore = BASE_ORES[tier]
				m.need = int(randi_range(15, 60) / float(tier + 1)) + 5
				m.reward = int(m.need * ORES[m.ore].value * 1.4) + 10
				m.title = "Supply order: %s" % ORES[m.ore].name
				m.desc = "Deliver %d refined %s. Turn it in at any station." % [m.need, ORES[m.ore].name]
			"regional":
				var reg: Dictionary = REGIONS[randi_range(1, 5 if cat < CAT_RED else 9)]
				m.type = "deliver"
				m.ore = reg.ore
				m.need = randi_range(10, 30)
				m.reward = int(m.need * ORES[m.ore].value * 2.2) + 100
				m.title = "Rare order: %s" % ORES[m.ore].name
				m.desc = "Deliver %d refined %s, from %s. Turn it in at any station." % [m.need, ORES[m.ore].name, reg.name]
			"anomaly":
				m.reward = 400
				m.title = "Strange signals"
				m.desc = "Find any anomaly with a probe (they hide in Wild systems)."
			"expedition":
				m.need = randi_range(2, 4)
				m.reward = 350 * m.need
				m.title = "Wild expedition"
				m.desc = "Chart %d Wild systems you've never visited." % m.need
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
	take(m.ore, m.need)
	_complete_mission(m)
	changed.emit()


# ---------------------------------------------------------------- saving

## Switch save slot ("pilot" or "sandbox"). Anyone can play the sandbox.
func use_slot(s: String) -> void:
	if not SLOTS.has(s):
		s = "pilot"
	save_slot = s
	sandbox = s == "sandbox"
	god = sandbox
	peaceful = false
	if not no_save:
		save_path = save_root.path_join(SLOTS[s])


## Saves this copy of the game can't use are moved into the backups folder, never deleted: saves from before
## v4 (which started everyone over), unreadable ones, and ones an old copy of the game wrote over. Continue
## then picks up the newest good backup, so running an old copy can't wipe anyone's progress.
func migrate_saves() -> void:
	if no_save:
		return
	reset_note = false
	for s in SLOTS:
		var path: String = save_root.path_join(SLOTS[s])
		var moved := false
		for p in [path, path + ".bak"]:
			if not FileAccess.file_exists(p):
				continue
			var data = _read_save(p)
			if data != null and int(data.get("version", 1)) >= SAVE_VERSION:
				continue
			_keep_copy(path, p, "set_aside" + ("_bak" if p.ends_with(".bak") else ""), true)
			moved = true
		if moved and s == "pilot" and _pick_save(path) == null:
			reset_note = true


## Copy (or move) a save file into the backups folder as <slot>_<date and time>_<why>.json, then drop the
## oldest copies past BACKUPS_KEPT.
func _keep_copy(slot_path: String, from: String, why: String, move := false) -> void:
	var dir := save_root.path_join("backups")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var base := dir.path_join("%s_%s_%s" % [slot_path.get_file().get_basename(), stamp, why])
	var to := base + ".json"
	var n := 2
	while FileAccess.file_exists(to):
		to = "%s_%d.json" % [base, n]
		n += 1
	if move:
		DirAccess.rename_absolute(ProjectSettings.globalize_path(from), ProjectSettings.globalize_path(to))
	else:
		DirAccess.copy_absolute(ProjectSettings.globalize_path(from), ProjectSettings.globalize_path(to))
	var all := backups(slot_path)
	for i in maxi(all.size() - BACKUPS_KEPT, 0):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(all[i]))


## The backups of a save slot, oldest first (their names sort by date).
func backups(slot_path: String) -> Array:
	var dir := save_root.path_join("backups")
	var out := []
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		return out
	var stem := slot_path.get_file().get_basename() + "_"
	for f in DirAccess.get_files_at(dir):
		if f.begins_with(stem) and f.ends_with(".json"):
			out.append(dir.path_join(f))
	out.sort()
	return out


## The save data to load for a slot: the save itself, its .bak, or failing both the good backup saved most
## recently. Returns null (and says why in load_error) when there's nothing this copy of the game can load.
func _pick_save(path: String):
	load_error = ""
	save_too_new = 0
	loaded_backup = ""
	var best = null
	for p in [path, path + ".bak"] + backups(path):
		var d = _read_save(p)
		if d == null or int(d.get("version", 1)) < SAVE_VERSION:
			continue
		if int(d.get("game", 0)) > VERSION:
			save_too_new = int(d.game)
			load_error = "This save was made by a newer version of Driftlight (v%d). Update the game to play it." % save_too_new
			return null
		if p.begins_with(path):
			return d  # the save itself, or its .bak
		if best == null or float(d.get("saved_at", 0.0)) >= float(best.get("saved_at", 0.0)):
			best = d
			loaded_backup = p
	if best == null:
		load_error = "Your save couldn't be read."
	return best


## Sandbox: a bit of everything, and lots of it.
func sandbox_fill() -> void:
	credits = maxi(credits, 9999999)
	probes = maxi(probes, 99)
	portals = maxi(portals, 9)
	for id in SHIPS:
		if not owned_ships.has(id):
			owned_ships.append(id)
	for id in WEAPONS:
		if id != BLASTER:
			weapon_stock[id] = maxi(weapon_stock.get(id, 0), 10)
	for id in MODULES:
		module_stock[id] = maxi(module_stock.get(id, 0), 4)
	for id in ORES:
		materials[id] = maxi(materials.get(id, 0), 9999)
	for id in SPICES:
		spices[id] = maxi(spices.get(id, 0), 99)
	changed.emit()


## Sandbox: every system visited, every planet scanned, every anomaly found.
func sandbox_reveal() -> void:
	for s in systems:
		s.visited = true
		for i in s.locs.size():
			var l: Dictionary = s.locs[i]
			l.scanned = true
			if l.kind == "anomaly":
				l.found = true
			note_loc(s.id, i)
	changed.emit()


func has_save() -> bool:
	return FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path + ".bak") or _pick_save(save_path) != null


const CODE_TAG := "DLSAVE1"

## The current slot's save as a code you can paste on another device (Load Code there): the save file
## compressed and written as plain text, "DLSAVE1-<size>-<check>-<data>". It holds the whole save, so it's a
## few thousand characters, not a short password. Returns "" if there's no save.
func save_code() -> String:
	save_game()
	var src := save_path if FileAccess.file_exists(save_path) else save_path + ".bak"
	if not FileAccess.file_exists(src):
		return ""
	var raw := FileAccess.get_file_as_bytes(src)
	if raw.is_empty():
		return ""
	var b64 := Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE)).replace("+", "-").replace("/", "_")
	return "%s-%d-%s-%s" % [CODE_TAG, raw.size(), b64.sha256_text().substr(0, 8), b64]


## Turn a pasted code back into this slot's save (the save it replaces is kept in the backups folder). Returns
## "" when it worked, otherwise what was wrong with the code. Continue then loads it.
func import_code(code: String) -> String:
	var parts := code.strip_edges().replace("\n", "").replace("\r", "").replace(" ", "").split("-", true, 3)
	if parts.size() < 4 or parts[0] != CODE_TAG:
		return "That doesn't look like a Driftlight save code."
	var size := int(parts[1])
	var b64: String = parts[3]
	if b64.sha256_text().substr(0, 8) != parts[2]:
		return "The code is damaged or incomplete (it didn't match its check). Copy all of it and try again."
	var packed := Marshalls.base64_to_raw(b64.replace("-", "+").replace("_", "/"))
	var raw := packed.decompress(size, FileAccess.COMPRESSION_DEFLATE) if size > 0 and size < 4000000 else PackedByteArray()
	if raw.is_empty():
		return "The code couldn't be unpacked."
	var data = JSON.parse_string(raw.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY or not data.has("credits"):
		return "The code doesn't hold a Driftlight save."
	if int(data.get("version", 1)) < SAVE_VERSION:
		return "That save is from before the v8 reset, and can't be played any more."
	if int(data.get("game", 0)) > VERSION:
		return "That save was made by a newer version of Driftlight (v%d). Update the game first." % int(data.game)
	if FileAccess.file_exists(save_path):
		_keep_copy(save_path, save_path, "before_code")
	for p in [save_path, save_path + ".bak"]:
		var f := FileAccess.open(p, FileAccess.WRITE)
		if f == null:
			return "Couldn't write the save."
		f.store_buffer(raw)
		f.close()
	return ""


## Closing the game or going back to the title: save, and back up where you left off.
func end_session() -> void:
	save_game()
	if in_game and not no_save and FileAccess.file_exists(save_path):
		_backup_at = playtime
		_keep_copy(save_path, save_path, "auto")


## Starting over keeps a copy of the save it replaces.
func keep_before_new_game() -> void:
	if not no_save and FileAccess.file_exists(save_path):
		_keep_copy(save_path, save_path, "before_new_game")


func save_game() -> void:
	if no_save or not in_game:
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
	var data := {"version": SAVE_VERSION, "game": VERSION, "credits": credits, "materials": materials, "cargo": cargo, "spices": spices,
		"probes": probes, "portals": portals, "owned_ships": owned_ships, "ship_id": ship_id, "weapon_stock": weapon_stock,
		"loadouts": loadouts, "module_stock": module_stock, "modules_equipped": modules_equipped, "stats": stats,
		"unlocked": unlocked.keys(), "missions": missions, "route_target": route_target, "route_stops": route_stops,
		"system": current_system, "loc": current_loc, "visited": visited, "scanned": scanned, "found": found, "salvaged": salvaged,
		"relics_done": relics_done, "refineries": refineries, "notebook": notebook, "pinned": pinned,
		"regions_seen": regions_seen.keys(), "regional_seen": regional_seen.keys(), "home": home, "storage": storage,
		"auto_store": auto_store, "playtime": playtime,
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
	if playtime - _backup_at >= BACKUP_EVERY:
		_backup_at = playtime
		_keep_copy(save_path, save_path, "auto")
	saved.emit()


func load_game() -> bool:
	var data = _pick_save(save_path)
	if data == null:
		return false
	if loaded_backup == "" and not no_save:
		_keep_copy(save_path, save_path if FileAccess.file_exists(save_path) else save_path + ".bak", "session")
	new_game()
	credits = int(data.get("credits", 0))
	materials = _ints(data.get("materials", {}))
	for k in materials.keys():
		if not ORES.has(k):
			materials.erase(k)
	cargo = _ints(data.get("cargo", {}))
	for k in cargo.keys():
		if not ORES.has(k.get_slice(":", 0)):
			cargo.erase(k)
	spices = _ints(data.get("spices", {}))
	probes = int(data.get("probes", 0))
	portals = int(data.get("portals", 0))
	owned_ships = data.get("owned_ships", ["wren"]).filter(func(id): return SHIPS.has(id))
	if owned_ships.is_empty():
		owned_ships = ["wren"]
	ship_id = data.get("ship_id", "wren") if SHIPS.has(data.get("ship_id", "")) else "wren"
	weapon_stock = _ints(data.get("weapon_stock", {}))
	for k in weapon_stock.keys():
		if not WEAPONS.has(k):
			weapon_stock.erase(k)
	var lo: Dictionary = data.get("loadouts", {})
	for sid in lo:
		if SHIPS.has(sid):
			loadouts[sid] = lo[sid].map(func(w): return w if WEAPONS.has(w) else BLASTER).slice(0, SHIPS[sid].guns)
	module_stock = _ints(data.get("module_stock", {}))
	for k in module_stock.keys():
		if not MODULES.has(k):
			module_stock.erase(k)
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
	route_stops = data.get("route_stops", []).map(func(v): return int(v))
	playtime = float(data.get("playtime", 0.0))
	for id in data.get("visited", []):
		systems[int(id)].visited = true
	for pair in data.get("scanned", []):
		systems[int(pair[0])].locs[int(pair[1])].scanned = true
	for aid in data.get("found", []):
		anom_loc(int(aid)).found = true
	for pair in data.get("salvaged", []):
		mark_salvaged(int(pair[0]), int(pair[1]))
	# (saves from before the weekly return have no time on a relic: its week starts now)
	for pair in data.get("relics_done", []):
		mark_relic(int(pair[0]), int(pair[1]), float(pair[2]) if pair.size() > 2 else -1.0)
	refresh_relics()
	notebook = {}
	var nb: Dictionary = data.get("notebook", {})
	for key in nb:
		var e: Dictionary = nb[key]
		notebook[key] = {"sys": int(e.get("sys", 0)), "loc": int(e.get("loc", 0)), "tags": e.get("tags", []),
			"ores": e.get("ores", []).filter(func(o): return ORES.has(o))}
	pinned = []
	for p in data.get("pinned", []):
		var ok: bool = (p[0] == "ship" and SHIPS.has(p[1])) or (p[0] == "weapon" and WEAPONS.has(p[1])) or \
			(p[0] == "module" and MODULES.has(p[1]))
		if ok:
			pinned.append([str(p[0]), str(p[1])])
	for r in data.get("regions_seen", []):
		regions_seen[int(r)] = true
	for o in data.get("regional_seen", []):
		regional_seen[str(o)] = true
	var sd: Dictionary = data.get("storage", {})
	storage = _empty_storage()
	for kind in ["materials", "spices", "weapons", "modules", "cargo"]:
		storage[kind] = _ints(sd.get(kind, {}))
	for k in storage.materials.keys():
		if not ORES.has(k):
			storage.materials.erase(k)
	for k in storage.weapons.keys():
		if not WEAPONS.has(k):
			storage.weapons.erase(k)
	for k in storage.modules.keys():
		if not MODULES.has(k):
			storage.modules.erase(k)
	storage.probes = int(sd.get("probes", 0))
	storage.portals = int(sd.get("portals", 0))
	# v12 removed every portable wormhole (carried and stored): saves from an older game lose theirs here
	if int(data.get("game", 0)) < 12:
		portals = 0
		storage.portals = 0
	auto_store = bool(data.get("auto_store", true))
	var h: Array = data.get("home", [0, 0])
	if h.size() == 2 and int(h[0]) < systems.size() and int(h[1]) < systems[int(h[0])].locs.size() and \
			systems[int(h[0])].locs[int(h[1])].station:
		home = [int(h[0]), int(h[1])]
	refineries = {}
	var rd: Dictionary = data.get("refineries", {})
	for key in rd:
		var r: Dictionary = rd[key]
		var q := []
		for item in r.get("queue", []):
			if ORES.has(str(item[0])):
				q.append([str(item[0]), int(item[1]), int(item[2])])
		refineries[key] = {"name": str(r.get("name", "")), "queue": q, "progress": float(r.get("progress", 0.0)),
			"output": _ints(r.get("output", {}))}
		# (a furnace you've used stays, even if v12's rarer Wild stations would have removed its station)
		var kp: PackedStringArray = str(key).split(":")
		if kp.size() == 2 and int(kp[0]) < systems.size() and int(kp[1]) < systems[int(kp[0])].locs.size():
			var kl: Dictionary = systems[int(kp[0])].locs[int(kp[1])]
			if kl.kind == "planet" and not kl.station:
				kl.station = true
				kl.refinery = true
				kl.pirates = false
	# furnaces kept smelting while the game was closed (up to a week)
	away_time = clampf(Time.get_unix_time_from_system() - float(data.get("saved_at", Time.get_unix_time_from_system())), 0.0, 604800.0)
	var before := furnace_output()
	tick_refineries(away_time)
	away_smelted = furnace_output() - before
	current_system = clampi(int(data.get("system", 0)), 0, systems.size() - 1)
	current_loc = clampi(int(data.get("loc", 0)), 0, systems[current_system].locs.size() - 1)
	_backup_at = playtime
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
