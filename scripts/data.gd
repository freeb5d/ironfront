class_name Data
extends RefCounted
## Static game data. Countries are pure data: add one by adding an entry here.

const MAX_SLOTS := 8
const MAP_RADIUS := 90.0
const START_MONEY := 500.0
const INCOME := 6.0
const UNIT_CAP := 40

const PLAYER_COLORS := [
	Color("2b6cff"), Color("ff3b30"), Color("ffd60a"), Color("30d158"),
	Color("bf5af2"), Color("ff9f0a"), Color("64d2ff"), Color("f5f5f5"),
]

# Each country trains two units: [0] light (cheap, fast), [1] heavy (armored / long range).
const COUNTRIES := {
	"USA": {"units": [
		{"name": "Ranger", "cost": 110, "hp": 110, "dmg": 13, "rng": 12, "spd": 7.0, "cd": 1.0},
		{"name": "Abrams", "cost": 380, "hp": 380, "dmg": 34, "rng": 16, "spd": 6.0, "cd": 1.4},
	]},
	"China": {"units": [
		{"name": "Conscript", "cost": 70, "hp": 80, "dmg": 10, "rng": 11, "spd": 7.0, "cd": 1.0},
		{"name": "Type 99", "cost": 300, "hp": 320, "dmg": 28, "rng": 15, "spd": 6.0, "cd": 1.4},
	]},
	"Russia": {"units": [
		{"name": "Motor Rifle", "cost": 100, "hp": 105, "dmg": 12, "rng": 12, "spd": 6.5, "cd": 1.0},
		{"name": "T-90", "cost": 340, "hp": 400, "dmg": 30, "rng": 16, "spd": 5.5, "cd": 1.4},
	]},
	"Israel": {"units": [
		{"name": "Commando", "cost": 120, "hp": 90, "dmg": 15, "rng": 13, "spd": 8.0, "cd": 0.9},
		{"name": "Merkava", "cost": 400, "hp": 420, "dmg": 33, "rng": 16, "spd": 6.0, "cd": 1.4},
	]},
	"Iran": {"units": [
		{"name": "Militia", "cost": 60, "hp": 70, "dmg": 9, "rng": 11, "spd": 7.0, "cd": 1.0},
		{"name": "Missile Truck", "cost": 300, "hp": 150, "dmg": 45, "rng": 26, "spd": 5.0, "cd": 2.5},
	]},
}


static func country_names() -> Array:
	return COUNTRIES.keys()


static func unit(country: String, idx: int) -> Dictionary:
	return COUNTRIES[country]["units"][idx]


static func slot_pos(i: int) -> Vector3:
	var a: float = TAU * float(i) / float(MAX_SLOTS)
	return Vector3(cos(a), 0.0, sin(a)) * MAP_RADIUS
