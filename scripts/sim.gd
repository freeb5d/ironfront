class_name Sim
extends RefCounted
## Server-side game simulation. No scene-tree dependencies so it can be unit tested headless.

const SIGHT := 35.0
const HQ_HP := 2500.0
const MAX_SHOTS := 240

class Ent:
	var id: int = 0
	var kind: int = 0 # 0 = HQ, 1 = light unit, 2 = heavy unit
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

var ents: Dictionary = {}
var slots: Array = []
var alive: Array = []
var money: Array = []
var bot_timer: Array = []
var hq_pos: Array = []
var shots: PackedFloat32Array = PackedFloat32Array()
var status: String = ""
var time: float = 0.0
var active_count: int = 0
var rand: RandomNumberGenerator = RandomNumberGenerator.new()
var _next_id: int = 1


func setup(p_slots: Array, seed_value: int) -> void:
	rand.seed = seed_value
	slots = p_slots.duplicate(true)
	for i in Data.MAX_SLOTS:
		var t: String = slots[i]["type"]
		var active: bool = (t == "human" or t == "bot")
		alive.append(active)
		money.append(Data.START_MONEY if active else 0.0)
		bot_timer.append(rand.randf_range(1.0, 4.0))
		hq_pos.append(Data.slot_pos(i))
		if active:
			active_count += 1
			_spawn_hq(i)
			for k in 4:
				spawn_unit(i, 0)


func label(slot: int) -> String:
	var n: String = slots[slot]["name"]
	if n == "":
		n = "Bot"
	return "%s (%s)" % [n, slots[slot]["country"]]


func _new_id() -> int:
	var v: int = _next_id
	_next_id += 1
	return v


func _spawn_hq(slot: int) -> void:
	var e: Ent = Ent.new()
	e.id = _new_id()
	e.kind = 0
	e.owner = slot
	e.pos = hq_pos[slot]
	e.hp = HQ_HP
	e.max_hp = HQ_HP
	e.radius = 6.0
	ents[e.id] = e


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
	e.radius = 1.0 if idx == 0 else 2.0
	ents[e.id] = e
	return e


func unit_count(slot: int) -> int:
	var n: int = 0
	for e in ents.values():
		if e.owner == slot and e.kind != 0:
			n += 1
	return n


# ---- commands (already validated for the sending slot by the caller's slot lookup) ----

func cmd_move(slot: int, ids: Array, pos: Vector3, attack_move: bool) -> void:
	var n: int = 0
	for id in ids:
		var e = ents.get(id)
		if e == null or e.owner != slot or e.kind == 0:
			continue
		e.target = -1
		e.goal = pos + Vector3((n % 6 - 2.5) * 2.5, 0.0, floorf(n / 6.0) * 2.5)
		e.has_goal = true
		e.atk_move = attack_move
		n += 1


func cmd_attack(slot: int, ids: Array, target_id: int) -> void:
	var t = ents.get(target_id)
	if t == null or t.owner == slot:
		return
	for id in ids:
		var e = ents.get(id)
		if e == null or e.owner != slot or e.kind == 0:
			continue
		e.target = target_id
		e.has_goal = false


func cmd_train(slot: int, idx: int) -> bool:
	if slot < 0 or slot >= alive.size() or not alive[slot] or status != "":
		return false
	if idx < 0 or idx > 1:
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
				_bot(i, dt)
	for e in ents.values():
		if e.kind != 0:
			_tick_unit(e, dt)
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
		if o.owner == e.owner or o.hp <= 0.0:
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
				t.hp -= e.dmg
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


func _separate() -> void:
	# soft collision: units push each other apart and slide around HQs instead of overlapping them
	var grid: Dictionary = {}
	var hqs: Array = []
	for e in ents.values():
		if e.kind == 0:
			hqs.append(e)
			continue
		var key: Vector2i = Vector2i(floori(e.pos.x / 4.0), floori(e.pos.z / 4.0))
		if grid.has(key):
			grid[key].append(e)
		else:
			grid[key] = [e]
	for e in ents.values():
		if e.kind == 0:
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
			if e.kind == 0 and alive[e.owner]:
				alive[e.owner] = false
				for o in ents.values():
					if o.owner == e.owner:
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


func _bot(slot: int, dt: float) -> void:
	bot_timer[slot] -= dt
	if bot_timer[slot] > 0.0:
		return
	bot_timer[slot] = rand.randf_range(2.5, 4.5)
	var country: String = slots[slot]["country"]
	var idx: int = 1 if rand.randf() < 0.4 else 0
	if money[slot] < float(Data.unit(country, idx)["cost"]):
		idx = 0
	cmd_train(slot, idx)
	if time < 90.0:
		return
	var idle: Array = []
	for e in ents.values():
		if e.owner == slot and e.kind != 0 and not e.has_goal and e.target == -1:
			idle.append(e.id)
	if idle.size() >= 12:
		var tgt: Vector3 = _nearest_enemy_hq(slot)
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
