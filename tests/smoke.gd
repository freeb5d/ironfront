extends SceneTree
## Headless smoke test: 8 bots (all 5 countries) fight for 8 simulated minutes.
## Run: godot --headless --path . --script tests/smoke.gd


func _initialize() -> void:
	var slots: Array = []
	var names: Array = Data.country_names()
	for i in Data.MAX_SLOTS:
		slots.append({"type": "bot", "peer": 0, "name": "Bot", "country": names[i % names.size()]})
	var sim: Sim = Sim.new()
	sim.setup(slots, 12345)

	var ok: bool = true
	for path in ["res://scripts/net.gd", "res://scripts/ui.gd", "res://scripts/minimap.gd", "res://scripts/menu.gd", "res://scripts/game.gd"]:
		var sc = load(path)
		if sc == null or not sc.can_instantiate():
			printerr("script failed to compile: " + path)
			ok = false
	if sim.ents.size() != 8 * 5:
		printerr("expected 40 starting entities, got %d" % sim.ents.size())
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
	print("t=%.0fs entities=%d survivors=%d status='%s'" % [sim.time, sim.ents.size(), survivors, sim.status])
	if sim.ents.size() <= 0:
		ok = false

	if ok:
		print("SMOKE OK")
		quit(0)
	else:
		print("SMOKE FAILED")
		quit(1)
