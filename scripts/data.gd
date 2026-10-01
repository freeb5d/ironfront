class_name Data
extends RefCounted
## Static game data. Countries are pure data: add one by adding an entry here.

const MAX_SLOTS := 8
const START_MONEY := 500.0
const INCOME := 2.0          # passive income per second
const OIL_INCOME := 4.0      # per captured oil derrick per second
const FARM_LOAD := 50.0      # money a farmer carries per trip
const FARM_TIME := 2.5       # seconds spent gathering
const MONEY_AMOUNT := 6000.0 # money in each field
const UNIT_CAP := 40

const PLAYER_COLORS := [
	Color("2b6cff"), Color("ff3b30"), Color("ffd60a"), Color("30d158"),
	Color("bf5af2"), Color("ff9f0a"), Color("64d2ff"), Color("f5f5f5"),
]

# Map layout (world units, map spans -150..150). Two bases per side, money fields ($) around the
# edges, five oil derricks in the sunken centre.
const MAP_HALF := 225.0 # the playable map spans -MAP_HALF..MAP_HALF on both axes
const MAP_SIZE := 450.0
const SLOT_POS := [
	Vector3(-67.5, 0, -168), Vector3(67.5, 0, -168), Vector3(177, 0, -72), Vector3(177, 0, 72),
	Vector3(67.5, 0, 168), Vector3(-67.5, 0, 168), Vector3(-177, 0, 72), Vector3(-177, 0, -72),
]
const MONEY_NODES := [
	Vector3(-202.5, 0, -195), Vector3(202.5, 0, -195), Vector3(-202.5, 0, 195), Vector3(202.5, 0, 195),
	Vector3(-108, 0, -195), Vector3(108, 0, -195), Vector3(-108, 0, 195), Vector3(108, 0, 195),
	Vector3(-207, 0, -102), Vector3(207, 0, -102), Vector3(-207, 0, 102), Vector3(207, 0, 102),
]
const OIL_NODES := [
	Vector3(0, 0, 0), Vector3(-84, 0, -33), Vector3(84, 0, 33), Vector3(-84, 0, 33), Vector3(84, 0, -33),
]

const BUILDER := {"name": "Builder", "cost": 120, "hp": 90, "dmg": 0, "rng": 0, "spd": 6.0, "cd": 1.0}
const TRAIN_TIME := [4.0, 9.0, 5.0, 8.0] # seconds: light, heavy, farmer, builder

# Buildings (key = entity kind). power > 0 produces power, power < 0 consumes it.
const BUILD := {
	7: {"name": "Power Plant", "cost": 200, "time": 14.0, "hp": 700.0, "radius": 5.0, "power": 8},
	8: {"name": "Supply Depot", "cost": 250, "time": 16.0, "hp": 900.0, "radius": 5.5, "power": -1},
	9: {"name": "Barracks", "cost": 300, "time": 18.0, "hp": 1100.0, "radius": 6.0, "power": -2},
	10: {"name": "War Factory", "cost": 500, "time": 26.0, "hp": 1500.0, "radius": 7.0, "power": -3},
	11: {"name": "Turret", "cost": 250, "time": 12.0, "hp": 600.0, "radius": 3.0, "power": -1},
	12: {"name": "Superweapon", "cost": 1500, "time": 45.0, "hp": 1800.0, "radius": 7.5, "power": -6},
}

# Research (Armor and Weapons need a Barracks, Logistics only the HQ).
const UPGRADES := [
	{"name": "Armor Plating", "cost": 600, "time": 25.0},
	{"name": "Weapon Tuning", "cost": 600, "time": 25.0},
	{"name": "Logistics", "cost": 400, "time": 20.0},
]
const SUPER_COOLDOWN := 180.0
const SUPER_DELAY := 6.0
const SUPER_RADIUS := 30.0
const SUPER_DAMAGE := 320.0

const FARMER := {"name": "Farmer", "cost": 75, "hp": 60, "dmg": 0, "rng": 0, "spd": 6.5, "cd": 1.0}

# Each country trains two units: [0] light (cheap, fast), [1] heavy (armored / long range).
const COUNTRIES := {
	"USA": {"powers": ["Air Strike", "Rapid Deploy", "Field Repair", "Orbital Cannon"], "color": Color("3b82f6"), "blurb": "Elite, expensive forces. Tough tanks and reliable all-round firepower.", "units": [
		{"name": "Ranger", "cost": 110, "hp": 110, "dmg": 13, "rng": 12, "spd": 7.0, "cd": 1.0},
		{"name": "Abrams", "cost": 380, "hp": 380, "dmg": 34, "rng": 16, "spd": 6.0, "cd": 1.4},
	]},
	"China": {"powers": ["Artillery", "Horde Call", "Field Repair", "Nuke Missile"], "color": Color("ef4444"), "blurb": "Cheap, plentiful troops. Overwhelm the enemy with numbers.", "units": [
		{"name": "Conscript", "cost": 70, "hp": 80, "dmg": 10, "rng": 11, "spd": 7.0, "cd": 1.0},
		{"name": "Type 99", "cost": 300, "hp": 320, "dmg": 28, "rng": 15, "spd": 6.0, "cd": 1.4},
	]},
	"Russia": {"powers": ["Rocket Barrage", "Call-up", "Field Repair", "Tactical Nuke"], "color": Color("cbd5e1"), "blurb": "Heavy armor. Slow, but the toughest tanks on the field.", "units": [
		{"name": "Motor Rifle", "cost": 100, "hp": 105, "dmg": 12, "rng": 12, "spd": 6.5, "cd": 1.0},
		{"name": "T-90", "cost": 340, "hp": 400, "dmg": 30, "rng": 16, "spd": 5.5, "cd": 1.4},
	]},
	"Israel": {"powers": ["Precision Hit", "Commando Drop", "Field Repair", "Jericho Strike"], "color": Color("38bdf8"), "blurb": "Fast, precise strikes. Agile units that hit hard and first.", "units": [
		{"name": "Commando", "cost": 120, "hp": 90, "dmg": 15, "rng": 13, "spd": 8.0, "cd": 0.9},
		{"name": "Merkava", "cost": 400, "hp": 420, "dmg": 33, "rng": 16, "spd": 6.0, "cd": 1.4},
	]},
	"Iran": {"powers": ["Missile Salvo", "Uprising", "Field Repair", "Scud Storm"], "color": Color("22c55e"), "blurb": "Asymmetric warfare. Cheap militia and long-range missile trucks.", "units": [
		{"name": "Militia", "cost": 60, "hp": 70, "dmg": 9, "rng": 11, "spd": 7.0, "cd": 1.0},
		{"name": "Missile Truck", "cost": 300, "hp": 150, "dmg": 45, "rng": 26, "spd": 5.0, "cd": 2.5},
	]},
}


# Models per nation: HQ building, then [model, fit_by_height, target_size] for the light and heavy unit.
const _U := "res://assets/units/"
const _B := "res://assets/buildings/kenney_city_industrial/"
const FARMER_VISUAL := [_U + "farmer_a.glb", true, 3.3]
const BUILDER_VISUAL := [_U + "worker_a.glb", true, 3.3]
const BUILD_VISUAL := {
	7: [_B + "windmill.glb", true, 15.0],
	8: [_B + "detail-tank-large.glb", false, 10.0],
	9: [_B + "building-n.glb", false, 13.0],
	10: [_B + "building-q.glb", false, 17.0],
	12: [_B + "chimney-large.glb", true, 24.0],
}
const VISUALS := {
	"USA": {"hq": _B + "building-a.glb", "units": [[_U + "soldier_b.glb", true, 3.6], [_U + "tank_a.glb", false, 7.0]]},
	"China": {"hq": _B + "building-c.glb", "units": [[_U + "soldier_a.glb", true, 3.6], [_U + "tank_b.glb", false, 7.0]]},
	"Russia": {"hq": _B + "building-e.glb", "units": [[_U + "soldier_a.glb", true, 3.6], [_U + "tank_c.glb", false, 7.6]]},
	"Israel": {"hq": _B + "building-g.glb", "units": [[_U + "soldier_b.glb", true, 3.6], [_U + "tank_d.glb", false, 7.0]]},
	"Iran": {"hq": _B + "building-i.glb", "units": [[_U + "soldier_a.glb", true, 3.6], [_U + "vehicle_x.glb", false, 7.4]]},
}


# Match options the host can change in the lobby (key -> label, values, display names).
const OPTION_DEFS := {
	"money": {"label": "Starting money", "values": [300, 500, 2000, 10000], "names": ["$300", "$500", "$2,000", "$10,000"]},
	"speed": {"label": "Game speed", "values": [0.75, 1.0, 1.5, 2.0], "names": ["Slow", "Normal", "Fast", "Very fast"]},
	"unit_cap": {"label": "Unit limit", "values": [20, 40, 80], "names": ["20", "40", "80"]},
	"start_units": {"label": "Starting army", "values": [2, 4, 8], "names": ["Small", "Normal", "Large"]},
	"teams": {"label": "Teams", "values": ["ffa", "2t", "4t"], "names": ["Free for all", "2 teams of 4", "4 teams of 2"]},
	"powers": {"label": "Commander powers", "values": [true, false], "names": ["On", "Off"]},
	"fog": {"label": "Fog of war", "values": [false, true], "names": ["Off", "On"]},
}
const DEFAULT_OPTIONS := {"money": 500, "speed": 1.0, "unit_cap": 40, "start_units": 4, "teams": "ffa", "powers": true, "fog": false}


# Single-player "Challenge" ladder. Player is always slot 0 (team 0); bots come from `bots`.
const CHALLENGE := [
	{"title": "Border Skirmish", "desc": "One weak opponent. Learn the basics.", "difficulty": 0, "bot_money": 0,
		"bots": [{"slot": 4, "country": "China", "team": 1}]},
	{"title": "Oil Rush", "desc": "A sharper rival who fights you for the oil.", "difficulty": 1, "bot_money": 0,
		"bots": [{"slot": 4, "country": "Russia", "team": 1}]},
	{"title": "Two Fronts", "desc": "Two rivals attack you and each other.", "difficulty": 1, "bot_money": 200,
		"bots": [{"slot": 2, "country": "Israel", "team": 1}, {"slot": 6, "country": "Iran", "team": 2}]},
	{"title": "Allied Offensive", "desc": "You and an ally against two hard opponents.", "difficulty": 2, "bot_money": 300,
		"bots": [{"slot": 1, "country": "USA", "team": 0}, {"slot": 4, "country": "China", "team": 1}, {"slot": 6, "country": "Russia", "team": 1}]},
	{"title": "The Final Stand", "desc": "Three hard opponents united against you.", "difficulty": 2, "bot_money": 800,
		"bots": [{"slot": 2, "country": "USA", "team": 1}, {"slot": 4, "country": "China", "team": 1}, {"slot": 6, "country": "Israel", "team": 1}]},
]

# Tooltip texts
const TRAIN_TIPS := [
	"Light infantry: cheap and quick. Trained at your base, faster with Barracks.",
	"Heavy vehicle: tough and hard-hitting. Needs a War Factory.",
	"Farmer: harvests the green $ fields and carries money to your HQ or Supply Depot.",
	"Builder: constructs buildings. Select it, then pick a building to place.",
]
const POWER_TIPS := [
	"Targeted strike: click the map, a barrage lands after a short warning. Costs 1 commander point.",
	"Reinforcements: four light units arrive at your base. Costs 1 commander point.",
	"Field repair: heals all your units and buildings by 60%. Costs 1 commander point.",
	"Superweapon: huge delayed blast with a big warning ring. Needs the Superweapon building.",
]
const UPGRADE_TIPS := [
	"+25% health for all your units. Needs a Barracks.",
	"+20% damage for all your units. Needs a Barracks.",
	"Farmers carry 50% more money per trip.",
]
const BUILD_TIPS := {
	7: "Produces power. Every other building needs power; low power slows production and turns off turrets.",
	8: "Drop-off point for farmers, so they walk less. Build it near the $ fields side of your base.",
	9: "Trains infantry faster and unlocks Armor and Weapon upgrades. Required for the War Factory.",
	10: "Unlocks heavy vehicles. Required for the Superweapon.",
	11: "Automatic defence. Needs power.",
	12: "Late-game superweapon. Fire it with J and click the target.",
}

static func unit_visual(country: String, idx: int) -> Array:
	if idx == 2:
		return FARMER_VISUAL
	if idx == 3:
		return BUILDER_VISUAL
	return VISUALS[country]["units"][idx]


static func country_names() -> Array:
	return COUNTRIES.keys()


static func unit(country: String, idx: int) -> Dictionary:
	if idx == 2:
		return FARMER
	if idx == 3:
		return BUILDER
	return COUNTRIES[country]["units"][idx]


static func slot_pos(i: int) -> Vector3:
	return SLOT_POS[i]
