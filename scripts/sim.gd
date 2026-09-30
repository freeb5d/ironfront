class_name Sim
extends RefCounted
## Server-side game simulation. No scene-tree dependencies so it can be unit tested headless.
##
## Entity kinds: 0 HQ, 1 light unit, 2 heavy unit, 3 farmer, 4 oil derrick, 5 money field.

const SIGHT := 35.0
const HQ_HP := 2500.0
const MAX_SHOTS := 240
const OIL_RADIUS := 9.0
const OIL_CAPTURE_TIME := 4.0
const FARMERS_PER_FIELD := 4

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
	var fstate: int = 0 # 0 look for a field, 1 walk to field, 2 gathering, 3 carry to HQ
	var node_id: int = -1
	var carry: float = 0.0
	var timer: float = 0.0
	# oil derricks
	var cap_t: float = 0.0

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
var difficulty: int = 1 # bots: 0 easy, 1 normal, 2 hard
var kills: Array = []
var lost: Array = []
var earned: Array = []
var rand: RandomNumberGenerator = RandomNumberGenerator.new()
var _next_id: int = 1


func setup(p_slots: Array, seed_value: int) -> void:
	rand.seed = seed_value
	slots = p_slots.duplicate(true)
	_spawn_map()
	for i in Data.MAX_SLOTS:
		var t: String = slots[i]["type"]
		var active: bool = (t == "human" or t == "bot")
		alive.append(active)
		money.append(Data.START_MONEY if active else 0.0)
		bot_timer.append(rand.randf_range(1.0, 4.0))
		hq_pos.append(Data.slot_pos(i))
		hq_ids.append(-1)
		kills.append(0)
		lost.append(0)
		earned.append(0.0)
		if active:
			active_count += 1
			_spawn_hq(i)
			for k in 4:
				spawn_unit(i, 0)
			for k in 2:
				spawn_unit(i, 2)


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
	for p in Data.MONEY_NODES:
		var e: Ent = Ent.new()
		e.id = _new_id()
		e.kind = 5
		e.owner = -1
		e.pos = p
		e.hp = Data.MONEY_AMOUNT
		e.max_hp = Data.MONEY_AMOUNT
		e.radius = 2.5
		ents[e.id] = e
	for p in Data.OIL_NODES:
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
	e.radius = 7.5
	ents[e.id] = e
	hq_ids[slot] = e.id


func spawn_unit(slot: int, idx: int) -> Ent:
	var st: Dictionary = Data.unit(slots[slot]["country"], idx)
	var e: Ent = Ent.new()
	e.id = _new_id()
	e.kind = 1 + idx
	e.owner = slot
	var base: Vector3 = hq_pos[slot]
	var dir: Vector3 = (-base).normalized()
	var side: Vector3 = dir.rotated(Vector3.UP, PI / 2.0)
	e.pos = base + dir * rand.randf_range(9.0, 14.0) + side * rand.randf_range(-7.0, 7.0)
	e.hp = float(st["hp"])
	e.max_hp = e.hp
	e.dmg = float(st["dmg"])
	e.rng = float(st["rng"])
	e.spd = float(st["spd"])
	e.cd = float(st["cd"])
	e.radius = 3.0 if idx == 1 else 1.6
	ents[e.id] = e
	return e


func unit_count(slot: int) -> int:
	var n: int = 0
	for e in ents.values():
		if e.owner == slot and e.kind >= 1 and e.kind <= 3:
			n += 1
	return n


# ---- commands (already validated for the sending slot by the caller's slot lookup) ----

func cmd_move(slot: int, ids: Array, pos: Vector3, attack_move: bool) -> void:
	var n: int = 0
	for id in ids:
		var e = ents.get(id)
		if e == null or e.owner != slot or e.kind < 1 or e.kind > 3:
			continue
		e.target = -1
		e.goal = pos + Vector3((n % 6 - 2.5) * 2.5, 0.0, floorf(n / 6.0) * 2.5)
		e.has_goal = true
		e.atk_move = attack_move and e.kind != 3
		n += 1


func cmd_attack(slot: int, ids: Array, target_id: int) -> void:
	var t = ents.get(target_id)
	if t == null or t.owner == slot or t.kind >= 4:
		return
	for id in ids:
		var e = ents.get(id)
		if e == null or e.owner != slot or (e.kind != 1 and e.kind != 2):
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
		if e == null or e.owner != slot or e.kind < 1 or e.kind > 3:
			continue
		e.target = -1
		e.has_goal = false
		e.atk_move = false


func stats() -> Array:
	var earned_i: Array = []
	for v in earned:
		earned_i.append(int(v))
	return [kills, lost, earned_i]


func cmd_train(slot: int, idx: int) -> bool:
	if slot < 0 or slot >= alive.size() or not alive[slot] or status != "":
		return false
	if idx < 0 or idx > 2:
		return false
	var st: Dictionary = Data.unit(slots[slot]["country"], idx)
	var cost: float = float(st["cost"])
	if money[slot] < cost or unit_count(slot) >= Data.UNIT_CAP:
		return false
	money[slot] -= cost
	spawn_unit(slot, idx)
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
	for e in ents.values():
		if e.kind == 1 or e.kind == 2:
			_tick_unit(e, dt)
		elif e.kind == 3:
			_tick_farmer(e, dt)
	_update_oil(dt)
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
	e.pos += d / l * minf(e.spd * dt, l)


func _find_enemy(e: Ent) -> int:
	var best: int = -1
	var best_d: float = SIGHT
	for o in ents.values():
		if o.owner == e.owner or o.hp <= 0.0 or o.kind >= 4:
			continue
		var d: float = _flat(e.pos, o.pos) - o.radius
		if d < best_d:
			best_d = d
			best = o.id
	return best


func _tick_unit(e: Ent, dt: float) -> void:
	e.cd_left -= dt
	e.scan -= dt
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
				var was_alive: bool = t.hp > 0.0
				t.hp -= e.dmg
				if was_alive and t.hp <= 0.0:
					kills[e.owner] += 1
				if shots.size() < MAX_SHOTS * 6:
					shots.append(e.id)
					shots.append(e.pos.x)
					shots.append(e.pos.z)
					shots.append(t.pos.x)
					shots.append(t.pos.z)
					shots.append(e.kind)
		else:
			_move(e, t.pos, dt)
	elif e.has_goal:
		_move(e, e.goal, dt)
		if _flat(e.pos, e.goal) < 1.5:
			e.has_goal = false
			e.atk_move = false


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
				var take: float = minf(Data.FARM_LOAD, n2.hp)
				n2.hp -= take
				e.carry = take
				e.fstate = 3
		3:
			var hq = ents.get(hq_ids[e.owner])
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
		var present: Dictionary = {}
		for u in ents.values():
			if (u.kind == 1 or u.kind == 2) and _flat(u.pos, o.pos) < OIL_RADIUS:
				present[u.owner] = true
		var who: Array = present.keys()
		if who.size() == 1 and who[0] != o.owner:
			o.cap_t += dt
			if o.cap_t >= OIL_CAPTURE_TIME:
				o.owner = who[0]
				o.cap_t = 0.0
		else:
			o.cap_t = maxf(0.0, o.cap_t - dt)
		o.hp = o.max_hp * (0.05 + 0.95 * o.cap_t / OIL_CAPTURE_TIME)
		if o.owner >= 0 and alive[o.owner]:
			money[o.owner] += Data.OIL_INCOME * dt
			earned[o.owner] += Data.OIL_INCOME * dt


func _separate() -> void:
	# soft collision: units push each other apart and slide around HQs instead of overlapping them
	var grid: Dictionary = {}
	var hqs: Array = []
	for e in ents.values():
		if e.kind == 0:
			hqs.append(e)
			continue
		if e.kind >= 4:
			continue
		var key: Vector2i = Vector2i(floori(e.pos.x / 4.0), floori(e.pos.z / 4.0))
		if grid.has(key):
			grid[key].append(e)
		else:
			grid[key] = [e]
	for e in ents.values():
		if e.kind == 0 or e.kind >= 4:
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
		for h in hqs:
			var dh: Vector3 = e.pos - h.pos
			dh.y = 0.0
			var lh: float = dh.length()
			var md: float = h.radius + e.radius
			if lh < md:
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
			if e.kind >= 1 and e.kind <= 3 and alive[e.owner]:
				lost[e.owner] += 1
			if e.kind == 0 and alive[e.owner]:
				alive[e.owner] = false
				for o in ents.values():
					if o.owner != e.owner:
						continue
					if o.kind >= 4:
						o.owner = -1
					else:
						o.hp = 0.0
				again = true


func _check_victory() -> void:
	if status != "" or active_count < 2:
		return
	var left: Array = []
	for i in Data.MAX_SLOTS:
		if alive[i]:
			left.append(i)
	if left.size() == 1:
		status = "WINNER: " + label(left[0])
	elif left.size() == 0:
		status = "DRAW"


func _nearest_enemy_hq(slot: int) -> Vector3:
	var best: Vector3 = Vector3.INF
	var best_d: float = INF
	for e in ents.values():
		if e.kind == 0 and e.owner != slot:
			var d: float = _flat(hq_pos[slot], e.pos)
			if d < best_d:
				best_d = d
				best = e.pos
	return best


func _nearest_oil(slot: int) -> Vector3:
	var best: Vector3 = Vector3.INF
	var best_d: float = INF
	for e in ents.values():
		if e.kind == 4 and e.owner != slot:
			var d: float = _flat(hq_pos[slot], e.pos)
			if d < best_d:
				best_d = d
				best = e.pos
	return best


func _bot(slot: int, dt: float) -> void:
	bot_timer[slot] -= dt
	if bot_timer[slot] > 0.0:
		return
	bot_timer[slot] = rand.randf_range(2.5, 4.5) * [1.6, 1.0, 0.7][difficulty]
	var farmers: int = 0
	for e in ents.values():
		if e.owner == slot and e.kind == 3:
			farmers += 1
	var want_farmers: int = 4 + mini(int(time / 90.0), 4)
	if farmers < want_farmers and cmd_train(slot, 2):
		return
	var country: String = slots[slot]["country"]
	var idx: int = 1 if rand.randf() < 0.4 else 0
	if money[slot] < float(Data.unit(country, idx)["cost"]):
		idx = 0
	cmd_train(slot, idx)
	if time < 90.0:
		return
	var idle: Array = []
	for e in ents.values():
		if e.owner == slot and (e.kind == 1 or e.kind == 2) and not e.has_goal and e.target == -1:
			idle.append(e.id)
	if idle.size() >= [16, 12, 9][difficulty]:
		var tgt: Vector3 = Vector3.INF
		if rand.randf() < 0.4:
			tgt = _nearest_oil(slot)
		if tgt == Vector3.INF:
			tgt = _nearest_enemy_hq(slot)
		if tgt != Vector3.INF:
			cmd_move(slot, idle, tgt, true)


# ---- network snapshot: 6 floats per entity ----

func snapshot() -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	for e in ents.values():
		out.append(e.id)
		out.append(e.kind)
		out.append(e.owner)
		out.append(e.pos.x)
		out.append(e.pos.z)
		out.append(e.hp / e.max_hp)
	return out


func money_packed() -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	for m in money:
		out.append(m)
	return out
