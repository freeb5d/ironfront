class_name Sim
extends RefCounted
## Server-side game simulation. No scene-tree dependencies so it can be unit tested headless.
##
## Entity kinds: 0 HQ, 1 light unit, 2 heavy unit, 3 farmer, 4 oil derrick, 5 money field,
## 6 builder, 7 power plant, 8 supply depot, 9 barracks, 10 war factory, 11 turret.

const SIGHT := 35.0
const HQ_HP := 2500.0
const MAX_SHOTS := 240
const OIL_RADIUS := 9.0
const OIL_CAPTURE_TIME := 4.0
const FARMERS_PER_FIELD := 4
const BASE_ZONE := 75.0 # buildings must be placed this close to your HQ
const LOW_POWER_SPEED := 0.45

const POWER_COOLDOWN := [45.0, 60.0, 60.0]
const STRIKE_DELAY := 2.5
const STRIKE_RADIUS := 16.0
const STRIKE_DAMAGE := 140.0


static func is_unit_kind(k: int) -> bool:
	return k == 1 or k == 2 or k == 3 or k == 6


static func is_combat_kind(k: int) -> bool:
	return k == 1 or k == 2


static func is_building_kind(k: int) -> bool:
	return k == 0 or (k >= 7 and k <= 12)


static func is_neutral_kind(k: int) -> bool:
	return k == 4 or k == 5


class Ent:
	var id: int = 0
	var kind: int = 0
	var owner: int = 0
	var pos: Vector3 = Vector3.ZERO
	var hp: float = 1.0
	var max_hp: float = 1.0
	var dmg: float = 0.0
	var rng: float = 0.0
	var spd: float = 0.0
	var cd: float = 1.0
	var cd_left: float = 0.0
	var radius: float = 1.0
	var target: int = -1
	var goal: Vector3 = Vector3.ZERO
	var has_goal: bool = false
	var atk_move: bool = false
	var scan: float = 0.0
	# farmers
	var fstate: int = 0 # 0 look for a field, 1 walk to field, 2 gathering, 3 carry to a drop-off
	var node_id: int = -1
	var carry: float = 0.0
	var timer: float = 0.0
	# oil derricks
	var cap_t: float = 0.0
	# veterancy
	var xp: float = 0.0
	var rank: int = 0 # 0 rookie, 1 veteran, 2 elite, 3 heroic
	var value: float = 0.0
	var base_hp: float = 1.0
	var base_dmg: float = 0.0
	# construction
	var constructing: bool = false
	var progress: float = 0.0
	var build_target: int = -1 # builders: the building they are working on

var ents: Dictionary = {}
var slots: Array = []
var alive: Array = []
var money: Array = []
var bot_timer: Array = []
var hq_pos: Array = []
var hq_ids: Array = []
var shots: PackedFloat32Array = PackedFloat32Array()
var status: String = ""
var time: float = 0.0
var active_count: int = 0
var farmed: float = 0.0
var built: int = 0 # finished constructions (for tests)
var produced: int = 0 # units finished by production queues (for tests)
var difficulty: int = 1 # bots: 0 easy, 1 normal, 2 hard
var kills: Array = []
var lost: Array = []
var earned: Array = []
var cpoints: Array = []   # commander points per slot
var team: Array = []      # team id per slot (free for all = own slot)
var unit_cap: int = Data.UNIT_CAP
var powers_on: bool = true
var team_count: int = 0
var power_cd: Array = []  # per slot: cooldown seconds for each of the 3 powers
var strikes: Array = []   # pending strike powers: {t, pos, slot}
var qn: Array = []        # production queues: per slot, 4 counts (light, heavy, farmer, builder)
var qp: Array = []        # progress of the item being built in each queue
var power_prod: Array = []
var power_use: Array = []
var low_power: Array = []
var comp: Array = []      # per slot: completed building count by kind
var blds: Array = []      # per slot: completed buildings by kind
var super_cd: Array = []  # superweapon cooldown per slot
var upg: Array = []       # researched upgrades per slot: [armor, weapons, logistics]
var upg_prog: Array = []  # seconds spent on each running research, -1 when idle
var fx: PackedFloat32Array = PackedFloat32Array() # visual events for clients: type, x, z
var _obstacles: Array = [] # buildings, rebuilt every step, used for steering
var rand: RandomNumberGenerator = RandomNumberGenerator.new()
var _next_id: int = 1


func setup(p_slots: Array, seed_value: int, opts: Dictionary = {}) -> void:
	rand.seed = seed_value
	Data.map_id = int(opts.get("map", 0))
	slots = p_slots.duplicate(true)
	unit_cap = int(opts.get("unit_cap", Data.UNIT_CAP))
	powers_on = bool(opts.get("powers", true))
	var start_money: float = float(opts.get("money", Data.START_MONEY))
	var start_units: int = int(opts.get("start_units", 4))
	var bot_bonus: float = float(opts.get("bot_money", 0.0))
	_spawn_map()
	for i in Data.MAX_SLOTS:
		var t: String = slots[i]["type"]
		var active: bool = (t == "human" or t == "bot")
		alive.append(active)
		money.append((start_money + (bot_bonus if t == "bot" else 0.0)) if active else 0.0)
		team.append(int(slots[i].get("team", i)))
		bot_timer.append(rand.randf_range(1.0, 4.0))
		hq_pos.append(Data.slot_pos(i))
		hq_ids.append(-1)
		kills.append(0)
		lost.append(0)
		earned.append(0.0)
		cpoints.append(1.0 if active else 0.0)
		power_cd.append([0.0, 0.0, 0.0])
		qn.append([0, 0, 0, 0])
		qp.append([0.0, 0.0, 0.0, 0.0])
		power_prod.append(0)
		power_use.append(0)
		low_power.append(false)
		comp.append({})
		blds.append({})
		super_cd.append(0.0)
		upg.append([false, false, false])
		upg_prog.append([-1.0, -1.0, -1.0])
		if active:
			active_count += 1
			_spawn_hq(i)
			for k in start_units:
				spawn_unit(i, 0)
			for k in 2:
				spawn_unit(i, 2)
			spawn_unit(i, 3)
	team_count = _count_teams()
	_recount()


func same_team(a: int, b: int) -> bool:
	if a == b:
		return true
	if a < 0 or b < 0:
		return false
	return team[a] == team[b]


func _count_teams() -> int:
	var seen: Dictionary = {}
	for i in Data.MAX_SLOTS:
		if alive[i]:
			seen[team[i]] = true
	return seen.size()


func label(slot: int) -> String:
	var n: String = slots[slot]["name"]
	if n == "":
		n = "Bot"
	return "%s (%s)" % [n, slots[slot]["country"]]


func _new_id() -> int:
	var v: int = _next_id
	_next_id += 1
	return v


func _spawn_map() -> void:
	for p in Data.money_nodes():
		var e: Ent = Ent.new()
		e.id = _new_id()
		e.kind = 5
		e.owner = -1
		e.pos = p
		e.hp = Data.MONEY_AMOUNT
		e.max_hp = Data.MONEY_AMOUNT
		e.radius = 2.5
		ents[e.id] = e
	for p in Data.oil_nodes():
		var o: Ent = Ent.new()
		o.id = _new_id()
		o.kind = 4
		o.owner = -1
		o.pos = p
		o.max_hp = 100.0
		o.hp = 5.0
		o.radius = 4.0
		ents[o.id] = o


func _spawn_hq(slot: int) -> void:
	var e: Ent = Ent.new()
	e.id = _new_id()
	e.kind = 0
	e.owner = slot
	e.pos = hq_pos[slot]
	e.hp = HQ_HP
	e.max_hp = HQ_HP
	e.value = 600.0
	e.radius = 7.5
	ents[e.id] = e
	hq_ids[slot] = e.id


## idx: 0 light, 1 heavy, 2 farmer, 3 builder. `origin` is where the unit appears (default: next to the HQ).
func spawn_unit(slot: int, idx: int, origin: Vector3 = Vector3.INF) -> Ent:
	var st: Dictionary = Data.unit(slots[slot]["country"], idx)
	var e: Ent = Ent.new()
	e.id = _new_id()
	e.kind = [1, 2, 3, 6][idx]
	e.owner = slot
	var base: Vector3 = hq_pos[slot] if origin == Vector3.INF else origin
	var dir: Vector3 = (-hq_pos[slot]).normalized()
	var side: Vector3 = dir.rotated(Vector3.UP, PI / 2.0)
	e.pos = base + dir * rand.randf_range(9.0, 14.0) + side * rand.randf_range(-7.0, 7.0)
	e.hp = float(st["hp"])
	e.max_hp = e.hp
	e.dmg = float(st["dmg"])
	e.rng = float(st["rng"])
	e.spd = float(st["spd"])
	e.cd = float(st["cd"])
	e.base_hp = e.hp
	e.base_dmg = e.dmg
	e.value = float(st["cost"])
	e.radius = 3.0 if idx == 1 else 1.6
	_recalc(e)
	ents[e.id] = e
	return e


func unit_count(slot: int) -> int:
	var n: int = 0
	for e in ents.values():
		if e.owner == slot and is_unit_kind(e.kind):
			n += 1
	return n


func queued_count(slot: int) -> int:
	var n: int = 0
	for c in qn[slot]:
		n += int(c)
	return n


# ---- commands (already validated for the sending slot by the caller's slot lookup) ----

func cmd_move(slot: int, ids: Array, pos: Vector3, attack_move: bool) -> void:
	var n: int = 0
	for id in ids:
		var e = ents.get(id)
		if e == null or e.owner != slot or not is_unit_kind(e.kind):
			continue
		e.target = -1
		e.build_target = -1
		e.goal = pos + Vector3((n % 6 - 2.5) * 2.5, 0.0, floorf(n / 6.0) * 2.5)
		e.has_goal = true
		e.atk_move = attack_move and is_combat_kind(e.kind)
		n += 1


func cmd_attack(slot: int, ids: Array, target_id: int) -> void:
	var t = ents.get(target_id)
	if t == null or same_team(t.owner, slot) or is_neutral_kind(t.kind):
		return
	for id in ids:
		var e = ents.get(id)
		if e == null or e.owner != slot or not is_combat_kind(e.kind):
			continue
		e.target = target_id
		e.has_goal = false


func cmd_harvest(slot: int, ids: Array, node_id: int) -> void:
	var n = ents.get(node_id)
	if n == null or n.kind != 5:
		return
	for id in ids:
		var e = ents.get(id)
		if e == null or e.owner != slot or e.kind != 3:
			continue
		e.has_goal = false
		e.node_id = node_id
		e.fstate = 3 if e.carry > 0.0 else 1


func cmd_stop(slot: int, ids: Array) -> void:
	for id in ids:
		var e = ents.get(id)
		if e == null or e.owner != slot or not is_unit_kind(e.kind):
			continue
		e.target = -1
		e.build_target = -1
		e.has_goal = false
		e.atk_move = false


func spot_ok(pos: Vector3, r: float, slot: int) -> bool:
	if absf(pos.x) > Data.MAP_HALF - 10.0 or absf(pos.z) > Data.MAP_HALF - 10.0:
		return false
	if _flat(pos, hq_pos[slot]) > BASE_ZONE:
		return false
	for e in ents.values():
		if is_neutral_kind(e.kind):
			if _flat(pos, e.pos) < r + e.radius + 4.0:
				return false
		elif is_building_kind(e.kind):
			if _flat(pos, e.pos) < r + e.radius + 1.5:
				return false
	return true


## Place a building and send the selected builders to construct it.
func cmd_build(slot: int, ids: Array, btype: int, pos: Vector3) -> bool:
	if not Data.BUILD.has(btype) or status != "" or slot < 0 or slot >= alive.size() or not alive[slot]:
		return false
	var def: Dictionary = Data.BUILD[btype]
	if money[slot] < float(def["cost"]) or not spot_ok(pos, float(def["radius"]), slot):
		return false
	if btype == 10 and int(comp[slot].get(9, 0)) == 0:
		return false # the war factory needs a barracks first
	if btype == 12 and int(comp[slot].get(10, 0)) == 0:
		return false # the superweapon needs a war factory
	var builders: Array = []
	for id in ids:
		var e = ents.get(id)
		if e != null and e.owner == slot and e.kind == 6:
			builders.append(e)
	if builders.is_empty():
		return false
	money[slot] -= float(def["cost"])
	var b: Ent = Ent.new()
	b.id = _new_id()
	b.kind = btype
	b.owner = slot
	b.pos = Vector3(pos.x, 0.0, pos.z)
	b.max_hp = float(def["hp"])
	b.hp = b.max_hp * 0.1
	b.radius = float(def["radius"])
	b.constructing = true
	b.value = float(def["cost"]) * 0.6
	if btype == 11:
		b.dmg = 18.0
		b.rng = 26.0
		b.cd = 0.9
	ents[b.id] = b
	for e in builders:
		e.build_target = b.id
		e.has_goal = false
		e.target = -1
	return true


## Send builders to help finish an unfinished building.
func cmd_assist(slot: int, ids: Array, bid: int) -> void:
	var b = ents.get(bid)
	if b == null or b.owner != slot or not b.constructing:
		return
	for id in ids:
		var e = ents.get(id)
		if e != null and e.owner == slot and e.kind == 6:
			e.build_target = bid
			e.has_goal = false


func stats() -> Array:
	var earned_i: Array = []
	for v in earned:
		earned_i.append(int(v))
	var cp: Array = []
	for v in cpoints:
		cp.append(snappedf(v, 0.1))
	return [kills, lost, earned_i, cp, power_cd, power_prod, power_use, qn, qp, upg, upg_prog, super_cd]


## Commander powers (cost 1 commander point each): 0 targeted strike, 1 reinforcements, 2 field repair.
func cmd_power(slot: int, idx: int, pos: Vector3) -> bool:
	if idx == 3:
		return _fire_super(slot, pos)
	if not powers_on or status != "" or slot < 0 or slot >= alive.size() or not alive[slot] or idx < 0 or idx > 2:
		return false
	if cpoints[slot] < 1.0 or power_cd[slot][idx] > 0.0:
		return false
	match idx:
		0:
			var p: Vector3 = Vector3(clampf(pos.x, -Data.MAP_HALF, Data.MAP_HALF), 0.0, clampf(pos.z, -Data.MAP_HALF, Data.MAP_HALF))
			strikes.append({"t": STRIKE_DELAY, "pos": p, "slot": slot})
			fx.append(1.0)
			fx.append(p.x)
			fx.append(p.z)
		1:
			for k in 4:
				spawn_unit(slot, 0)
		2:
			for e in ents.values():
				if e.owner == slot and (is_unit_kind(e.kind) or is_building_kind(e.kind)) and not e.constructing:
					e.hp = minf(e.max_hp, e.hp + e.max_hp * 0.6)
	cpoints[slot] -= 1.0
	power_cd[slot][idx] = POWER_COOLDOWN[idx]
	return true


func _fire_super(slot: int, pos: Vector3) -> bool:
	if status != "" or slot < 0 or slot >= alive.size() or not alive[slot]:
		return false
	if int(comp[slot].get(12, 0)) == 0 or super_cd[slot] > 0.0:
		return false
	var p: Vector3 = Vector3(clampf(pos.x, -Data.MAP_HALF, Data.MAP_HALF), 0.0, clampf(pos.z, -Data.MAP_HALF, Data.MAP_HALF))
	strikes.append({"t": Data.SUPER_DELAY, "pos": p, "slot": slot, "r": Data.SUPER_RADIUS, "dmg": Data.SUPER_DAMAGE})
	fx.append(5.0)
	fx.append(p.x)
	fx.append(p.z)
	super_cd[slot] = Data.SUPER_COOLDOWN
	return true


func cmd_upgrade(slot: int, idx: int) -> bool:
	if status != "" or slot < 0 or slot >= alive.size() or not alive[slot] or idx < 0 or idx > 2:
		return false
	if upg[slot][idx] or upg_prog[slot][idx] >= 0.0:
		return false
	if idx < 2 and int(comp[slot].get(9, 0)) == 0:
		return false
	var cost: float = float(Data.UPGRADES[idx]["cost"])
	if money[slot] < cost:
		return false
	money[slot] -= cost
	upg_prog[slot][idx] = 0.0
	return true


func _update_upgrades(dt: float) -> void:
	for i in Data.MAX_SLOTS:
		if not alive[i]:
			continue
		for k in 3:
			if upg_prog[i][k] < 0.0:
				continue
			upg_prog[i][k] += dt * (LOW_POWER_SPEED if low_power[i] else 1.0)
			if upg_prog[i][k] >= float(Data.UPGRADES[k]["time"]):
				upg_prog[i][k] = -1.0
				upg[i][k] = true
				for e in ents.values():
					if e.owner == i and is_unit_kind(e.kind):
						_recalc(e)
				fx.append(7.0)
				fx.append(hq_pos[i].x)
				fx.append(hq_pos[i].z)


func _update_powers(dt: float) -> void:
	for i in Data.MAX_SLOTS:
		super_cd[i] = maxf(0.0, super_cd[i] - dt)
		for k in 3:
			power_cd[i][k] = maxf(0.0, power_cd[i][k] - dt)
	var si: int = strikes.size() - 1
	while si >= 0:
		var s: Dictionary = strikes[si]
		s["t"] -= dt
		if s["t"] <= 0.0:
			var pos: Vector3 = s["pos"]
			var sr: float = float(s.get("r", STRIKE_RADIUS))
			var sd: float = float(s.get("dmg", STRIKE_DAMAGE))
			fx.append(6.0 if sr > 20.0 else 2.0)
			fx.append(pos.x)
			fx.append(pos.z)
			for e in ents.values():
				if not is_neutral_kind(e.kind) and not same_team(e.owner, s["slot"]) and e.hp > 0.0 and _flat(e.pos, pos) < sr + e.radius * 0.5:
					_hit(s["slot"], null, e, sd * (0.6 if is_building_kind(e.kind) else 1.0))
			strikes.remove_at(si)
		si -= 1


## Queue a unit: 0 light, 1 heavy (needs a war factory), 2 farmer, 3 builder.
func cmd_train(slot: int, idx: int) -> bool:
	if slot < 0 or slot >= alive.size() or not alive[slot] or status != "":
		return false
	if idx < 0 or idx > 3:
		return false
	if idx == 1 and int(comp[slot].get(10, 0)) == 0:
		return false
	var st: Dictionary = Data.unit(slots[slot]["country"], idx)
	var cost: float = float(st["cost"])
	if money[slot] < cost or qn[slot][idx] >= 5:
		return false
	if unit_count(slot) + queued_count(slot) >= unit_cap:
		return false
	money[slot] -= cost
	qn[slot][idx] += 1
	return true


## Cancel one queued unit and get the money back.
func cmd_untrain(slot: int, idx: int) -> bool:
	if slot < 0 or slot >= alive.size() or not alive[slot] or idx < 0 or idx > 3:
		return false
	if qn[slot][idx] <= 0:
		return false
	qn[slot][idx] -= 1
	money[slot] += float(Data.unit(slots[slot]["country"], idx)["cost"])
	if qn[slot][idx] == 0:
		qp[slot][idx] = 0.0
	return true


# ---- simulation ----

func step(dt: float) -> void:
	time += dt
	for i in Data.MAX_SLOTS:
		if alive[i]:
			money[i] += Data.INCOME * dt
			if slots[i]["type"] == "bot":
				if difficulty == 2:
					money[i] += Data.INCOME * dt # hard bots get double passive income
				_bot(i, dt)
	_recount()
	_obstacles.clear()
	for ob in ents.values():
		if is_building_kind(ob.kind):
			_obstacles.append(ob)
	_update_production(dt)
	_update_upgrades(dt)
	for e in ents.values():
		if is_combat_kind(e.kind):
			_tick_unit(e, dt)
		elif e.kind == 3:
			_tick_farmer(e, dt)
		elif e.kind == 6:
			_tick_builder(e, dt)
		elif e.kind == 11 and not e.constructing:
			_tick_turret(e, dt)
	_update_oil(dt)
	_update_powers(dt)
	_separate()
	_reap()
	_check_victory()


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _move(e: Ent, p: Vector3, dt: float) -> void:
	var d: Vector3 = p - e.pos
	d.y = 0.0
	var l: float = d.length()
	if l < 0.01:
		return
	var dir: Vector3 = d / l
	if l > 3.0:
		dir = _steer(e, dir, l, p)
	e.pos += dir * minf(e.spd * dt, l)


## Bend the walking direction around buildings in the way (instead of grinding along their walls).
func _steer(e: Ent, dir: Vector3, dist: float, dest: Vector3) -> Vector3:
	var out: Vector3 = dir
	var reach: float = minf(dist, 20.0)
	for o in _obstacles:
		if o.id == e.target or o.id == e.build_target:
			continue
		var to: Vector3 = o.pos - e.pos
		to.y = 0.0
		var ahead: float = to.dot(dir)
		if ahead <= 0.0 or ahead > reach + o.radius:
			continue
		if _flat(dest, o.pos) < o.radius + 2.0:
			continue # that is where we are going (drop-off, attack target)
		var side: Vector3 = to - dir * ahead
		var clearance: float = o.radius + e.radius + 2.0
		var sl: float = side.length()
		if sl < clearance:
			var perp: Vector3 = Vector3(-dir.z, 0.0, dir.x)
			var sgn: float = -1.0 if perp.dot(side) > 0.0 else 1.0
			if sl < 0.2:
				sgn = 1.0 if e.id % 2 == 0 else -1.0
			out += perp * sgn * (1.0 - sl / clearance) * 1.8
	return out.normalized()


## Completed buildings, power and tech per player.
func _recount() -> void:
	for i in Data.MAX_SLOTS:
		power_prod[i] = 0
		power_use[i] = 0
		comp[i] = {}
		blds[i] = {}
	for e in ents.values():
		if e.owner < 0 or not is_building_kind(e.kind) or e.constructing:
			continue
		var i: int = e.owner
		comp[i][e.kind] = int(comp[i].get(e.kind, 0)) + 1
		if not blds[i].has(e.kind):
			blds[i][e.kind] = []
		blds[i][e.kind].append(e)
		if e.kind == 0:
			power_prod[i] += 4
		else:
			var p: int = int(Data.BUILD[e.kind]["power"])
			if p > 0:
				power_prod[i] += p
			else:
				power_use[i] += -p
	for i in Data.MAX_SLOTS:
		low_power[i] = power_use[i] > power_prod[i]


func _update_production(dt: float) -> void:
	for i in Data.MAX_SLOTS:
		if not alive[i]:
			continue
		var mult: float = LOW_POWER_SPEED if low_power[i] else 1.0
		for cat in 4:
			if qn[i][cat] <= 0:
				qp[i][cat] = 0.0
				continue
			var speed: float = 1.0
			if cat == 0:
				speed += 0.6 * int(comp[i].get(9, 0))
			elif cat == 1:
				speed += 0.6 * maxi(0, int(comp[i].get(10, 0)) - 1)
			qp[i][cat] += dt * speed * mult
			if qp[i][cat] >= float(Data.TRAIN_TIME[cat]):
				qp[i][cat] = 0.0
				qn[i][cat] -= 1
				var origin: Vector3 = hq_pos[i]
				var kind_src: int = 9 if cat == 0 else (10 if cat == 1 else 0)
				if blds[i].has(kind_src):
					var list: Array = blds[i][kind_src]
					origin = list[rand.randi() % list.size()].pos
				spawn_unit(i, cat, origin)
				produced += 1


func _find_enemy(e: Ent, reach: float = SIGHT) -> int:
	var best: int = -1
	var best_d: float = reach
	for o in ents.values():
		if is_neutral_kind(o.kind) or o.hp <= 0.0 or same_team(o.owner, e.owner):
			continue
		var d: float = _flat(e.pos, o.pos) - o.radius
		if is_building_kind(o.kind) and o.kind != 11:
			d += 6.0 # prefer fighting units and turrets before walls of concrete
		if d < best_d:
			best_d = d
			best = o.id
	return best


## One place where damage is dealt, so kills, experience and commander points stay consistent.
func _hit(slot: int, attacker, t: Ent, dmg: float) -> void:
	var was_alive: bool = t.hp > 0.0
	t.hp -= dmg
	if was_alive and t.hp <= 0.0:
		kills[slot] += 1
		cpoints[slot] += t.value / 400.0
		if attacker != null:
			_gain_xp(attacker, t.value)


## Effective health and damage = base stats x veterancy rank x the owner's upgrades.
func _recalc(e: Ent) -> void:
	var hm: float = [1.0, 1.1, 1.2, 1.3][e.rank]
	var dm: float = [1.0, 1.15, 1.3, 1.5][e.rank]
	if e.owner >= 0:
		if upg[e.owner][0]:
			hm *= 1.25
		if upg[e.owner][1]:
			dm *= 1.2
	var old_max: float = e.max_hp
	e.max_hp = e.base_hp * hm
	e.hp += e.max_hp - old_max
	e.dmg = e.base_dmg * dm


func _gain_xp(e: Ent, v: float) -> void:
	e.xp += v
	var r: int = 0
	if e.xp >= 900.0:
		r = 3
	elif e.xp >= 400.0:
		r = 2
	elif e.xp >= 150.0:
		r = 1
	if r > e.rank:
		e.rank = r
		_recalc(e)
		fx.append(3.0)
		fx.append(e.pos.x)
		fx.append(e.pos.z)


func _shoot(e: Ent, t: Ent) -> void:
	_hit(e.owner, e, t, e.dmg)
	if shots.size() < MAX_SHOTS * 6:
		shots.append(e.id)
		shots.append(e.pos.x)
		shots.append(e.pos.z)
		shots.append(t.pos.x)
		shots.append(t.pos.z)
		shots.append(e.kind)


func _tick_unit(e: Ent, dt: float) -> void:
	e.cd_left -= dt
	e.scan -= dt
	if e.rank == 3:
		e.hp = minf(e.max_hp, e.hp + 2.0 * dt) # heroic units slowly repair themselves
	var t = null
	if e.target != -1:
		t = ents.get(e.target)
		if t == null or t.hp <= 0.0:
			e.target = -1
			t = null
	if t == null and (not e.has_goal or e.atk_move) and e.scan <= 0.0:
		e.scan = 0.5 + rand.randf() * 0.2
		e.target = _find_enemy(e)
		if e.target != -1:
			t = ents.get(e.target)
	if t != null:
		var dist: float = _flat(e.pos, t.pos) - t.radius
		if dist <= e.rng:
			if e.cd_left <= 0.0:
				e.cd_left = e.cd
				_shoot(e, t)
		else:
			_move(e, t.pos, dt)
	elif e.has_goal:
		_move(e, e.goal, dt)
		if _flat(e.pos, e.goal) < 1.5:
			e.has_goal = false
			e.atk_move = false


func _tick_turret(e: Ent, dt: float) -> void:
	if low_power[e.owner]:
		return # no power, no guns
	e.cd_left -= dt
	e.scan -= dt
	var t = null
	if e.target != -1:
		t = ents.get(e.target)
		if t == null or t.hp <= 0.0 or _flat(e.pos, t.pos) - t.radius > e.rng:
			e.target = -1
			t = null
	if t == null and e.scan <= 0.0:
		e.scan = 0.4
		e.target = _find_enemy(e, e.rng)
		if e.target != -1:
			t = ents.get(e.target)
	if t != null and e.cd_left <= 0.0:
		e.cd_left = e.cd
		_shoot(e, t)


# ---- construction ----

func _tick_builder(e: Ent, dt: float) -> void:
	if e.build_target != -1:
		var b = ents.get(e.build_target)
		if b == null or not b.constructing:
			e.build_target = -1
			return
		if _flat(e.pos, b.pos) > b.radius + e.radius + 1.5:
			_move(e, b.pos, dt)
			return
		var step_p: float = dt / float(Data.BUILD[b.kind]["time"])
		b.progress += step_p
		b.hp = minf(b.max_hp, b.hp + b.max_hp * 0.9 * step_p)
		if b.progress >= 1.0:
			b.constructing = false
			b.hp = maxf(b.hp, b.max_hp * 0.5)
			built += 1
			fx.append(4.0)
			fx.append(b.pos.x)
			fx.append(b.pos.z)
			e.build_target = -1
		return
	if e.has_goal:
		_move(e, e.goal, dt)
		if _flat(e.pos, e.goal) < 1.5:
			e.has_goal = false


# ---- economy ----

func _nearest_field(e: Ent) -> Ent:
	var counts: Dictionary = {}
	for f in ents.values():
		if f.kind == 3 and f != e and (f.fstate == 1 or f.fstate == 2) and f.node_id != -1:
			counts[f.node_id] = int(counts.get(f.node_id, 0)) + 1
	var best: Ent = null
	var best_d: float = INF
	for n in ents.values():
		if n.kind != 5 or n.hp <= 0.0 or int(counts.get(n.id, 0)) >= FARMERS_PER_FIELD:
			continue
		var d: float = _flat(e.pos, n.pos)
		if d < best_d:
			best_d = d
			best = n
	return best


func _nearest_dropoff(e: Ent) -> Ent:
	var best: Ent = null
	var best_d: float = INF
	for k in [0, 8]:
		if not blds[e.owner].has(k):
			continue
		for b in blds[e.owner][k]:
			var d: float = _flat(e.pos, b.pos)
			if d < best_d:
				best_d = d
				best = b
	return best


func _tick_farmer(e: Ent, dt: float) -> void:
	if e.has_goal: # manual move order, then go back to work
		_move(e, e.goal, dt)
		if _flat(e.pos, e.goal) < 1.5:
			e.has_goal = false
		return
	match e.fstate:
		0:
			var n: Ent = _nearest_field(e)
			if n != null:
				e.node_id = n.id
				e.fstate = 1
		1:
			var n1 = ents.get(e.node_id)
			if n1 == null or n1.hp <= 0.0:
				e.fstate = 0
				return
			_move(e, n1.pos, dt)
			if _flat(e.pos, n1.pos) < n1.radius + 1.5:
				e.fstate = 2
				e.timer = Data.FARM_TIME
		2:
			var n2 = ents.get(e.node_id)
			if n2 == null or n2.hp <= 0.0:
				e.fstate = 0
				return
			e.timer -= dt
			if e.timer <= 0.0:
				var take: float = minf(Data.FARM_LOAD * (1.5 if upg[e.owner][2] else 1.0), n2.hp)
				n2.hp -= take
				e.carry = take
				e.fstate = 3
		3:
			var hq: Ent = _nearest_dropoff(e)
			if hq == null:
				return
			_move(e, hq.pos, dt)
			if _flat(e.pos, hq.pos) < hq.radius + e.radius + 2.5:
				money[e.owner] += e.carry
				earned[e.owner] += e.carry
				farmed += e.carry
				e.carry = 0.0
				e.fstate = 1
				var nn = ents.get(e.node_id)
				if nn == null or nn.hp <= 0.0:
					e.fstate = 0


func _update_oil(dt: float) -> void:
	for o in ents.values():
		if o.kind != 4:
			continue
		var present: Dictionary = {} # team -> first slot seen
		for u in ents.values():
			if is_combat_kind(u.kind) and _flat(u.pos, o.pos) < OIL_RADIUS:
				if not present.has(team[u.owner]):
					present[team[u.owner]] = u.owner
		var who: Array = present.keys()
		if who.size() == 1 and (o.owner < 0 or team[o.owner] != who[0]):
			o.cap_t += dt
			if o.cap_t >= OIL_CAPTURE_TIME:
				o.owner = present[who[0]]
				o.cap_t = 0.0
		else:
			o.cap_t = maxf(0.0, o.cap_t - dt)
		o.hp = o.max_hp * (0.05 + 0.95 * o.cap_t / OIL_CAPTURE_TIME)
		if o.owner >= 0 and alive[o.owner]:
			money[o.owner] += Data.OIL_INCOME * dt
			earned[o.owner] += Data.OIL_INCOME * dt


func _separate() -> void:
	# soft collision: units push each other apart and slide around buildings instead of overlapping them
	var grid: Dictionary = {}
	var obstacles: Array = []
	for e in ents.values():
		if is_building_kind(e.kind):
			obstacles.append(e)
			continue
		if not is_unit_kind(e.kind):
			continue
		var key: Vector2i = Vector2i(floori(e.pos.x / 4.0), floori(e.pos.z / 4.0))
		if grid.has(key):
			grid[key].append(e)
		else:
			grid[key] = [e]
	for e in ents.values():
		if not is_unit_kind(e.kind):
			continue
		var cx: int = floori(e.pos.x / 4.0)
		var cz: int = floori(e.pos.z / 4.0)
		var push: Vector3 = Vector3.ZERO
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var cell = grid.get(Vector2i(cx + dx, cz + dz))
				if cell == null:
					continue
				for o in cell:
					if o == e:
						continue
					var d: Vector3 = e.pos - o.pos
					d.y = 0.0
					var l: float = d.length()
					var min_d: float = e.radius + o.radius
					if l < min_d:
						if l < 0.001:
							d = Vector3(rand.randf() - 0.5, 0.0, rand.randf() - 0.5)
							l = maxf(d.length(), 0.001)
						push += d / l * (min_d - l) * 0.4
		e.pos += push
		for h in obstacles:
			var dh: Vector3 = e.pos - h.pos
			dh.y = 0.0
			var lh: float = dh.length()
			var md: float = h.radius + e.radius
			if lh < md:
				# builders may stand at the wall of the building they are constructing
				if e.kind == 6 and e.build_target == h.id:
					continue
				e.pos += dh / maxf(lh, 0.001) * (md - lh)


func _reap() -> void:
	var again: bool = true
	while again:
		again = false
		var dead: Array = []
		for e in ents.values():
			if e.hp <= 0.0:
				dead.append(e)
		for e in dead:
			ents.erase(e.id)
			if is_unit_kind(e.kind) and alive[e.owner]:
				lost[e.owner] += 1
			if e.kind == 0 and alive[e.owner]:
				alive[e.owner] = false
				for o in ents.values():
					if o.owner != e.owner:
						continue
					if is_neutral_kind(o.kind):
						o.owner = -1
					else:
						o.hp = 0.0
				again = true


func _check_victory() -> void:
	if status != "" or team_count < 2:
		return
	var left: Array = []
	var teams_left: Dictionary = {}
	for i in Data.MAX_SLOTS:
		if alive[i]:
			left.append(i)
			teams_left[team[i]] = true
	if teams_left.size() == 1:
		var names: Array = []
		for i in left:
			names.append(label(i))
		status = "WINNER: " + ", ".join(names)
	elif left.size() == 0:
		status = "DRAW"


func _nearest_enemy_hq(slot: int) -> Vector3:
	var best: Vector3 = Vector3.INF
	var best_d: float = INF
	for e in ents.values():
		if e.kind == 0 and not same_team(e.owner, slot):
			var d: float = _flat(hq_pos[slot], e.pos)
			if d < best_d:
				best_d = d
				best = e.pos
	return best


func _nearest_oil(slot: int) -> Vector3:
	var best: Vector3 = Vector3.INF
	var best_d: float = INF
	for e in ents.values():
		if e.kind == 4 and (e.owner < 0 or not same_team(e.owner, slot)):
			var d: float = _flat(hq_pos[slot], e.pos)
			if d < best_d:
				best_d = d
				best = e.pos
	return best


# ---- bots ----

func _count_kind(slot: int, kind: int) -> int:
	var n: int = 0
	for e in ents.values():
		if e.owner == slot and e.kind == kind:
			n += 1
	return n


## A free spot for a new building near the bot's HQ, preferring the side facing away from the map centre.
func find_spot(slot: int, kind: int) -> Vector3:
	var r: float = float(Data.BUILD[kind]["radius"])
	var out: Vector3 = hq_pos[slot].normalized()
	var base_angle: float = atan2(out.z, out.x)
	for ring in [17.0, 25.0, 33.0, 41.0, 49.0]:
		for k in 12:
			var a: float = base_angle + (k / 2 + 1) * (PI / 6.0) * (1.0 if k % 2 == 0 else -1.0)
			var p: Vector3 = hq_pos[slot] + Vector3(cos(a), 0.0, sin(a)) * ring
			if spot_ok(p, r, slot):
				return p
	return Vector3.INF


func _bot_build(slot: int) -> void:
	var idle: Array = []
	var builders: int = 0
	for e in ents.values():
		if e.owner == slot and e.kind == 6:
			builders += 1
			if e.build_target == -1:
				idle.append(e.id)
	if builders + qn[slot][3] == 0:
		cmd_train(slot, 3)
		return
	if idle.is_empty():
		return
	var want: int = -1
	var have_power: int = _count_kind(slot, 7)
	if have_power < 1:
		want = 7
	elif _count_kind(slot, 9) < 1:
		want = 9
	elif _count_kind(slot, 8) < 1 and time > 60.0:
		want = 8
	elif _count_kind(slot, 10) < 1 and int(comp[slot].get(9, 0)) > 0:
		want = 10
	elif low_power[slot] or power_use[slot] + 3 > power_prod[slot]:
		want = 7
	elif _count_kind(slot, 12) < 1 and time > 300.0 and int(comp[slot].get(10, 0)) > 0 and money[slot] > 1750.0:
		want = 12
	elif _count_kind(slot, 11) < 2 and time > 150.0:
		want = 11
	elif _count_kind(slot, 9) < 2 and time > 240.0:
		want = 9
	if want == -1:
		return
	if money[slot] < float(Data.BUILD[want]["cost"]) + 40.0:
		return
	var spot: Vector3 = find_spot(slot, want)
	if spot != Vector3.INF:
		cmd_build(slot, [idle[0]], want, spot)


func _bot(slot: int, dt: float) -> void:
	bot_timer[slot] -= dt
	if bot_timer[slot] > 0.0:
		return
	bot_timer[slot] = rand.randf_range(2.5, 4.5) * [1.6, 1.0, 0.7][difficulty]
	_bot_build(slot)
	if time > 150.0 and money[slot] > 900.0:
		for k in [2, 0, 1]:
			if cmd_upgrade(slot, k):
				break
	if int(comp[slot].get(12, 0)) > 0 and super_cd[slot] <= 0.0 and rand.randf() < 0.3:
		var stgt: Vector3 = _nearest_enemy_hq(slot)
		if stgt != Vector3.INF:
			cmd_power(slot, 3, stgt)
	var farmers: int = 0
	for e in ents.values():
		if e.owner == slot and e.kind == 3:
			farmers += 1
	var want_farmers: int = 4 + mini(int(time / 90.0), 4)
	if farmers + qn[slot][2] < want_farmers and cmd_train(slot, 2):
		return
	var country: String = slots[slot]["country"]
	var idx: int = 1 if (rand.randf() < 0.4 and int(comp[slot].get(10, 0)) > 0) else 0
	if money[slot] < float(Data.unit(country, idx)["cost"]):
		idx = 0
	cmd_train(slot, idx)
	if time < 90.0:
		return
	var idle: Array = []
	for e in ents.values():
		if e.owner == slot and is_combat_kind(e.kind) and not e.has_goal and e.target == -1:
			idle.append(e.id)
	if idle.size() >= [16, 12, 9][difficulty]:
		var tgt: Vector3 = Vector3.INF
		if rand.randf() < 0.4:
			tgt = _nearest_oil(slot)
		if tgt == Vector3.INF:
			tgt = _nearest_enemy_hq(slot)
		if tgt != Vector3.INF:
			cmd_move(slot, idle, tgt, true)


# ---- network snapshot: 7 floats per entity (rank 9 = still under construction) ----

func snapshot() -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	for e in ents.values():
		out.append(e.id)
		out.append(e.kind)
		out.append(e.owner)
		out.append(e.pos.x)
		out.append(e.pos.z)
		out.append(e.hp / e.max_hp)
		out.append(9 if e.constructing else e.rank)
	return out


func money_packed() -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	for m in money:
		out.append(m)
	return out
