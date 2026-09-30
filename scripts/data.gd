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
const SLOT_POS := [
	Vector3(-45, 0, -112), Vector3(45, 0, -112), Vector3(118, 0, -48), Vector3(118, 0, 48),
	Vector3(45, 0, 112), Vector3(-45, 0, 112), Vector3(-118, 0, 48), Vector3(-118, 0, -48),
]
const MONEY_NODES := [
	Vector3(-135, 0, -130), Vector3(135, 0, -130), Vector3(-135, 0, 130), Vector3(135, 0, 130),
	Vector3(-72, 0, -130), Vector3(72, 0, -130), Vector3(-72, 0, 130), Vector3(72, 0, 130),
	Vector3(-138, 0, -68), Vector3(138, 0, -68), Vector3(-138, 0, 68), Vector3(138, 0, 68),
]
const OIL_NODES := [
	Vector3(0, 0, 0), Vector3(-56, 0, -22), Vector3(56, 0, 22), Vector3(-56, 0, 22), Vector3(56, 0, -22),
]

const FARMER := {"name": "Farmer", "cost": 75, "hp": 60, "dmg": 0, "rng": 0, "spd": 6.5, "cd": 1.0}

# Each country trains two units: [0] light (cheap, fast), [1] heavy (armored / long range).
const COUNTRIES := {
	"USA": {"powers": ["Air Strike", "Rapid Deployment", "Field Repair"], "color": Color("3b82f6"), "blurb": "Elite, expensive forces. Tough tanks and reliable all-round firepower.", "units": [
		{"name": "Ranger", "cost": 110, "hp": 110, "dmg": 13, "rng": 12, "spd": 7.0, "cd": 1.0},
		{"name": "Abrams", "cost": 380, "hp": 380, "dmg": 34, "rng": 16, "spd": 6.0, "cd": 1.4},
	]},
	"China": {"powers": ["Artillery Barrage", "Conscript Horde", "Field Repair"], "color": Color("ef4444"), "blurb": "Cheap, plentiful troops. Overwhelm the enemy with numbers.", "units": [
		{"name": "Conscript", "cost": 70, "hp": 80, "dmg": 10, "rng": 11, "spd": 7.0, "cd": 1.0},
		{"name": "Type 99", "cost": 300, "hp": 320, "dmg": 28, "rng": 15, "spd": 6.0, "cd": 1.4},
	]},
	"Russia": {"powers": ["Rocket Barrage", "Reserve Call-up", "Field Repair"], "color": Color("cbd5e1"), "blurb": "Heavy armor. Slow, but the toughest tanks on the field.", "units": [
		{"name": "Motor Rifle", "cost": 100, "hp": 105, "dmg": 12, "rng": 12, "spd": 6.5, "cd": 1.0},
		{"name": "T-90", "cost": 340, "hp": 400, "dmg": 30, "rng": 16, "spd": 5.5, "cd": 1.4},
	]},
	"Israel": {"powers": ["Precision Strike", "Commando Drop", "Field Repair"], "color": Color("38bdf8"), "blurb": "Fast, precise strikes. Agile units that hit hard and first.", "units": [
		{"name": "Commando", "cost": 120, "hp": 90, "dmg": 15, "rng": 13, "spd": 8.0, "cd": 0.9},
		{"name": "Merkava", "cost": 400, "hp": 420, "dmg": 33, "rng": 16, "spd": 6.0, "cd": 1.4},
	]},
	"Iran": {"powers": ["Missile Salvo", "Militia Uprising", "Field Repair"], "color": Color("22c55e"), "blurb": "Asymmetric warfare. Cheap militia and long-range missile trucks.", "units": [
		{"name": "Militia", "cost": 60, "hp": 70, "dmg": 9, "rng": 11, "spd": 7.0, "cd": 1.0},
		{"name": "Missile Truck", "cost": 300, "hp": 150, "dmg": 45, "rng": 26, "spd": 5.0, "cd": 2.5},
	]},
}


# Models per nation: HQ building, then [model, fit_by_height, target_size] for the light and heavy unit.
const _U := "res://assets/units/"
const _B := "res://assets/buildings/kenney_city_industrial/"
const FARMER_VISUAL := [_U + "worker_a.glb", true, 3.3]
const VISUALS := {
	"USA": {"hq": _B + "building-a.glb", "units": [[_U + "soldier_b.glb", true, 3.6], [_U + "tank_a.glb", false, 7.0]]},
	"China": {"hq": _B + "building-c.glb", "units": [[_U + "soldier_a.glb", true, 3.6], [_U + "tank_b.glb", false, 7.0]]},
	"Russia": {"hq": _B + "building-e.glb", "units": [[_U + "soldier_a.glb", true, 3.6], [_U + "tank_c.glb", false, 7.6]]},
	"Israel": {"hq": _B + "building-g.glb", "units": [[_U + "soldier_b.glb", true, 3.6], [_U + "tank_d.glb", false, 7.0]]},
	"Iran": {"hq": _B + "building-i.glb", "units": [[_U + "soldier_a.glb", true, 3.6], [_U + "vehicle_x.glb", false, 7.4]]},
}


static func country_names() -> Array:
	return COUNTRIES.keys()


static func unit(country: String, idx: int) -> Dictionary:
	if idx == 2:
		return FARMER
	return COUNTRIES[country]["units"][idx]


static func slot_pos(i: int) -> Vector3:
	return SLOT_POS[i]
