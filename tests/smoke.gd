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
	for path in ["res://scripts/net.gd", "res://scripts/ui.gd", "res://scripts/minimap.gd", "res://scripts/menu.gd", "res://scripts/game.gd", "res://scripts/sfx.gd", "res://scripts/models.gd", "res://scripts/portrait.gd", "res://scripts/turntable.gd"]:
		var sc = load(path)
		if sc == null or not sc.can_instantiate():
			printerr("script failed to compile: " + path)
			ok = false
	var expected: int = 8 * 7 + Data.MONEY_NODES.size() + Data.OIL_NODES.size()
	if sim.ents.size() != expected:
		printerr("expected %d starting entities, got %d" % [expected, sim.ents.size()])
		ok = false

	# player-style commands must work
	sim.money[0] = 1000.0
	if not sim.cmd_train(0, 1):
		printerr("cmd_train failed")
		ok = false

	var dt: float = 1.0 / 30.0
	var steps: int = 30 * 60 * 8
	for s in steps:
		sim.step(dt)
		if sim.status != "":
			break

	var snap: PackedFloat32Array = sim.snapshot()
	if snap.size() != sim.ents.size() * 6:
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
