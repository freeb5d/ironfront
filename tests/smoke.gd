extends SceneTree
## Headless smoke test: 8 bots (all 5 countries) fight for 8 simulated minutes.
## Run: godot --headless --path . --script tests/smoke.gd


func _initialize() -> void:
	var slots: Array = []
	var names: Array = Data.country_names()
	for i in Data.MAX_SLOTS:
		slots.append({"type": "bot", "peer": 0, "name": "Bot", "country": names[i % names.size()]})
	for kind in ["shot", "cannon", "boom", "click", "coin", "capture", "alarm", "ready"]:
		var w: AudioStreamWAV = Sfx.make(kind)
		if w == null or w.data.size() < 100:
			printerr("sound failed to generate: " + kind)
			quit(1)
			return
	var sim: Sim = Sim.new()
	sim.setup(slots, 12345)

	var ok: bool = true
	for path in ["res://scripts/net.gd", "res://scripts/ui.gd", "res://scripts/minimap.gd", "res://scripts/menu.gd", "res://scripts/game.gd", "res://scripts/sfx.gd", "res://scripts/models.gd", "res://scripts/portrait.gd", "res://scripts/turntable.gd", "res://scripts/power_icon.gd"]:
		var sc = load(path)
		if sc == null or not sc.can_instantiate():
			printerr("script failed to compile: " + path)
			ok = false
	var expected: int = 8 * 8 + Data.money_nodes().size() + Data.oil_nodes().size()
	if sim.ents.size() != expected:
		printerr("expected %d starting entities, got %d" % [expected, sim.ents.size()])
		ok = false

	# player-style commands must work
	sim.money[0] = 1000.0
	if not sim.cmd_train(0, 0):
		printerr("cmd_train failed")
		ok = false
	if sim.cmd_train(0, 1):
		printerr("heavy units must need a war factory")
		ok = false
	var before: float = sim.money[0]
	if not sim.cmd_untrain(0, 0) or sim.money[0] <= before:
		printerr("cancelling a queued unit must refund it")
		ok = false
	sim.cmd_train(0, 0)
	# a builder can place a power plant
	var b_id: int = -1
	for e in sim.ents.values():
		if e.owner == 0 and e.kind == 6:
			b_id = e.id
	var spot: Vector3 = sim.find_spot(0, 7)
	if b_id == -1 or spot == Vector3.INF or not sim.cmd_build(0, [b_id], 7, spot):
		printerr("cmd_build failed")
		ok = false
	if sim.cmd_build(0, [b_id], 10, sim.find_spot(0, 10)):
		printerr("war factory must need a barracks")
		ok = false

	# commander powers must work and respect cost
	sim.cpoints[0] = 3.0
	if not sim.cmd_power(0, 1, Vector3.ZERO) or not sim.cmd_power(0, 2, Vector3.ZERO) or not sim.cmd_power(0, 0, Vector3(0, 0, 0)):
		printerr("commander powers failed")
		ok = false
	if sim.cmd_power(0, 1, Vector3.ZERO):
		printerr("power ignored its cooldown")
		ok = false

	var dt: float = 1.0 / 30.0
	var steps: int = 30 * 60 * 8
	for s in steps:
		sim.step(dt)
		if sim.status != "":
			break

	var snap: PackedFloat32Array = sim.snapshot()
	if snap.size() != sim.ents.size() * 7:
		printerr("snapshot size mismatch")
		ok = false
	var survivors: int = 0
	for a in sim.alive:
		if a:
			survivors += 1
	var oil_owned: int = 0
	for e in sim.ents.values():
		if e.kind == 4 and e.owner >= 0:
			oil_owned += 1
	print("t=%.0fs entities=%d survivors=%d farmed=%d oil_owned=%d status='%s'" % [sim.time, sim.ents.size(), survivors, int(sim.farmed), oil_owned, sim.status])
	var vets: int = 0
	for e in sim.ents.values():
		if e.rank > 0:
			vets += 1
	print("veterans alive=%d" % vets)
	var structures: int = 0
	for e in sim.ents.values():
		if e.kind >= 7:
			structures += 1
	print("buildings finished=%d standing=%d units produced=%d" % [sim.built, structures, sim.produced])
	if sim.built <= 0 or sim.produced <= 0:
		printerr("bots never built a base or produced units")
		ok = false
	# second match: 4 teams of 2, rich start, big armies, powers disabled
	var slots2: Array = []
	for i in Data.MAX_SLOTS:
		slots2.append({"type": "bot", "peer": 0, "name": "Bot", "country": names[(i + 2) % names.size()], "team": floori(i / 2.0)})
	var sim2: Sim = Sim.new()
	sim2.setup(slots2, 7, {"teams": "4t", "money": 2000, "unit_cap": 80, "start_units": 8, "powers": false})
	if sim2.money[0] != 2000.0 or sim2.team[3] != 1 or sim2.team_count != 4:
		printerr("match options were not applied")
		ok = false
	sim2.cpoints[0] = 2.0
	if sim2.cmd_power(0, 1, Vector3.ZERO):
		printerr("powers should be disabled")
		ok = false
	for s2 in steps:
		sim2.step(dt)
		if sim2.status != "":
			break
	var left_teams: Dictionary = {}
	for i in Data.MAX_SLOTS:
		if sim2.alive[i]:
			left_teams[sim2.team[i]] = true
	print("team match: t=%.0fs teams_left=%d status='%s'" % [sim2.time, left_teams.size(), sim2.status])
	if sim2.status != "" and left_teams.size() != 1:
		printerr("team victory condition is wrong")
		ok = false
	# every challenge stage must be a valid match
	for cst in Data.CHALLENGE:
		var cs: Array = []
		for i in Data.MAX_SLOTS:
			cs.append({"type": "closed", "peer": 0, "name": "", "country": "USA", "team": i})
		cs[0] = {"type": "human", "peer": 1, "name": "Me", "country": "USA", "team": 0}
		for b in cst["bots"]:
			cs[b["slot"]] = {"type": "bot", "peer": 0, "name": "Bot", "country": b["country"], "team": b["team"]}
		var csim: Sim = Sim.new()
		csim.setup(cs, 5, {"bot_money": cst["bot_money"]})
		for k in 30 * 10:
			csim.step(dt)
		if csim.team_count < 2:
			printerr("challenge stage has no opponent: " + str(cst["title"]))
			ok = false
	# upgrades and superweapon
	var sim3: Sim = Sim.new()
	sim3.setup(slots, 99, {"money": 10000})
	if not sim3.cmd_upgrade(0, 2) or sim3.cmd_upgrade(0, 2):
		printerr("logistics upgrade should start once")
		ok = false
	for s3 in 30 * 25:
		sim3.step(dt)
	if not sim3.upg[0][2]:
		printerr("upgrade never finished")
		ok = false
	var sw: Sim.Ent = Sim.Ent.new()
	sw.id = sim3._new_id()
	sw.kind = 12
	sw.owner = 0
	sw.pos = sim3.hq_pos[0] + Vector3(20, 0, 0)
	sw.max_hp = 1800.0
	sw.hp = 1800.0
	sw.radius = 7.5
	sim3.ents[sw.id] = sw
	sim3.step(dt)
	var foe: Vector3 = sim3.hq_pos[4]
	if not sim3.cmd_power(0, 3, foe) or sim3.cmd_power(0, 3, foe):
		printerr("superweapon should fire once then cool down")
		ok = false
	var hq4: float = sim3.ents[sim3.hq_ids[4]].hp
	for s4 in int(30.0 * (Data.SUPER_DELAY + 1.0)):
		sim3.step(dt)
	if sim3.hq_ids[4] in sim3.ents and sim3.ents[sim3.hq_ids[4]].hp >= hq4:
		printerr("superweapon did no damage")
		ok = false
	if sim.farmed <= 0.0:
		printerr("farmers never delivered any money")
		ok = false
	if sim.ents.size() <= 0:
		ok = false

	if ok:
		print("SMOKE OK")
		quit(0)
	else:
		print("SMOKE FAILED")
		quit(1)
