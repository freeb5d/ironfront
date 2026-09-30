extends Node3D
## In-match scene. The host runs Sim and broadcasts snapshots; every peer (host included)
## renders from snapshots and sends orders to the host.

const SNAP_HZ := 10.0

var sim: Sim = null
var my_slot: int = -1
var running: bool = false
var ready_peers: Dictionary = {}
var started_at: float = 0.0
var snap_timer: float = 0.0

# view state (all peers)
var views: Dictionary = {}    # id -> Node3D
var targets: Dictionary = {}  # id -> Vector3
var info: Dictionary = {}     # id -> [kind, owner, hp_frac]
var selected: Dictionary = {} # id -> true
var money: PackedFloat32Array = PackedFloat32Array()
var alive_arr: Array = []
var status_text: String = ""
var projectiles: Array = []   # in-flight bullets / shells
var moved: bool = false
var box_mode: bool = false
var pan_anchor = null

var cam_pivot: Node3D
var cam: Camera3D
var zoom: float = 60.0

var money_label: Label
var sel_label: Label
var players_label: RichTextLabel
var status_label: Label
var minimap: MiniMap
var pause_layer: CanvasLayer
var train_buttons: Array = []
var drag_rect: ColorRect
var dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO


func _ready() -> void:
	var me: int = multiplayer.get_unique_id()
	for i in Net.slots.size():
		if Net.slots[i]["type"] == "human" and Net.slots[i]["peer"] == me:
			my_slot = i
	_build_world()
	_build_hud()
	cam_pivot.position = Data.slot_pos(maxi(my_slot, 0)) * 0.75
	_update_cam()
	Net.server_lost.connect(_leave)
	if multiplayer.is_server():
		sim = Sim.new()
		sim.setup(Net.slots, Net.seed_value)
		Net.peer_left.connect(_on_peer_left)
		ready_peers[1] = true
		started_at = Time.get_ticks_msec() / 1000.0
	else:
		srv_ready.rpc_id(1)
	if "--autotest" in OS.get_cmdline_user_args():
		get_tree().create_timer(6.0).timeout.connect(_autotest_finish)


func _autotest_finish() -> void:
	# exercise the same code paths real input uses
	for id in info:
		if info[id][1] == my_slot and info[id][0] != 0:
			selected[id] = true
	_train(0)
	_train(1)
	_right_click(Vector2(640, 360))
	_finish_drag(Vector2(100, 100))
	# force the combat visuals that a real fight would trigger
	var any_id: int = views.keys()[0] if not views.is_empty() else -1
	_spawn_shot(any_id, Vector3(0, 0, 0), Vector3(12, 0, 3), 1)
	_spawn_shot(any_id, Vector3(0, 0, 0), Vector3(20, 0, -4), 2)
	_update_projectiles(0.05)
	_update_projectiles(1.0)
	_burst(Vector3(5, 1, 5), 20, 0.5, 0.3, Color(1, 0.5, 0.1), 8.0, Vector3(0, -9, 0))
	# simulate a click-drag pan
	drag_start = Vector2(400, 300)
	pan_anchor = _ground_point(drag_start)
	moved = true
	box_mode = false
	dragging = true
	await get_tree().create_timer(0.3).timeout
	dragging = false
	pause_layer.visible = true
	await get_tree().create_timer(2.0).timeout
	print("AUTOTEST OK views=%d" % views.size())
	get_tree().quit(0)


@rpc("any_peer", "reliable")
func srv_ready() -> void:
	if multiplayer.is_server():
		ready_peers[multiplayer.get_remote_sender_id()] = true


func _on_peer_left(slot: int) -> void:
	if sim != null:
		sim.slots[slot]["type"] = "bot"
		sim.slots[slot]["name"] = "Bot"


func _slot_of(peer: int) -> int:
	for i in Net.slots.size():
		if Net.slots[i]["type"] == "human" and Net.slots[i]["peer"] == peer:
			return i
	return -1


# ------------------------------------------------------------------ world / hud

func _build_world() -> void:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.6, 0.8)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.5
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	add_child(sun)

	var ground: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(320, 320)
	ground.mesh = pm
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color(0.22, 0.34, 0.2)
	ground.material_override = gm
	add_child(ground)

	_scatter_props()
	_decorate_bases()

	cam_pivot = Node3D.new()
	add_child(cam_pivot)
	cam = Camera3D.new()
	cam.rotation_degrees = Vector3(-60, 0, 0)
	cam_pivot.add_child(cam)
	cam.make_current()



func _panel(root: Control) -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	root.add_child(p)
	return p


func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var root: Control = Control.new()
	root.theme = UI.make_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# top bar
	var top: PanelContainer = _panel(root)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 10
	top.offset_right = -10
	top.offset_top = 10
	var tb: HBoxContainer = HBoxContainer.new()
	tb.add_theme_constant_override("separation", 30)
	top.add_child(tb)
	money_label = UI.label("", 24, UI.ACCENT)
	tb.add_child(money_label)
	sel_label = UI.label("", 18)
	tb.add_child(sel_label)
	var sp: Control = Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tb.add_child(sp)
	var country_name: String = "Spectator"
	if my_slot >= 0:
		country_name = Net.slots[my_slot]["country"]
	tb.add_child(UI.label(country_name.to_upper(), 20, Data.PLAYER_COLORS[maxi(my_slot, 0)]))

	# players list (top right)
	var pl: PanelContainer = _panel(root)
	pl.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pl.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	pl.offset_top = 78
	pl.offset_right = -10
	players_label = RichTextLabel.new()
	players_label.bbcode_enabled = true
	players_label.fit_content = true
	players_label.scroll_active = false
	players_label.custom_minimum_size = Vector2(290, 0)
	players_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pl.add_child(players_label)

	# bottom command bar
	var bottom: PanelContainer = _panel(root)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_left = 10
	bottom.offset_bottom = -10
	var bh: HBoxContainer = HBoxContainer.new()
	bh.add_theme_constant_override("separation", 14)
	bottom.add_child(bh)
	minimap = MiniMap.new()
	minimap.game = self
	bh.add_child(minimap)
	var bv: VBoxContainer = VBoxContainer.new()
	bv.add_theme_constant_override("separation", 8)
	bh.add_child(bv)
	bv.add_child(UI.label("TRAIN", 14, Color("8b98a9")))
	if my_slot >= 0:
		var country: String = Net.slots[my_slot]["country"]
		for idx in 2:
			var st: Dictionary = Data.unit(country, idx)
			var b: Button = Button.new()
			b.text = "[%s]  %s   $%d" % [["Q", "E"][idx], st["name"], st["cost"]]
			b.custom_minimum_size = Vector2(250, 46)
			b.pressed.connect(_train.bind(idx))
			bv.add_child(b)
			train_buttons.append(b)
	var help: Label = UI.label("Click select   Drag = move map   Shift+drag box select   F army\nRMB move / attack   WASD pan   Wheel zoom   F11 fullscreen   Esc menu", 13, Color("8b98a9"))
	bv.add_child(help)

	# centre status (victory / defeat)
	status_label = UI.label("", 72, UI.ACCENT)
	status_label.add_theme_color_override("font_outline_color", Color.BLACK)
	status_label.add_theme_constant_override("outline_size", 12)
	root.add_child(status_label)
	status_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	status_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	status_label.grow_vertical = Control.GROW_DIRECTION_BOTH

	drag_rect = ColorRect.new()
	drag_rect.color = Color(0.2, 1, 0.2, 0.15)
	drag_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_rect.visible = false
	root.add_child(drag_rect)

	_build_pause()


func _build_pause() -> void:
	pause_layer = CanvasLayer.new()
	pause_layer.layer = 10
	add_child(pause_layer)
	var root: Control = Control.new()
	root.theme = UI.make_theme()
	pause_layer.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var c: CenterContainer = CenterContainer.new()
	root.add_child(c)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p: PanelContainer = PanelContainer.new()
	c.add_child(p)
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	var t: Label = UI.label("MENU", 36, UI.ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var resume: Button = Button.new()
	resume.text = "RESUME"
	resume.custom_minimum_size = Vector2(300, 50)
	resume.pressed.connect(func(): pause_layer.visible = false)
	v.add_child(resume)
	var fs: Button = Button.new()
	fs.text = "TOGGLE FULLSCREEN (F11)"
	fs.custom_minimum_size = Vector2(300, 50)
	fs.pressed.connect(Net.toggle_fullscreen)
	v.add_child(fs)
	var leave: Button = Button.new()
	leave.text = "LEAVE MATCH"
	leave.custom_minimum_size = Vector2(300, 50)
	leave.pressed.connect(_leave)
	v.add_child(leave)
	pause_layer.visible = false


# ------------------------------------------------------------------ per-frame

func _process(dt: float) -> void:
	if multiplayer.is_server() and not running:
		var all_ready: bool = true
		for s in Net.slots:
			if s["type"] == "human" and not ready_peers.has(s["peer"]):
				all_ready = false
		if all_ready or Time.get_ticks_msec() / 1000.0 - started_at > 10.0:
			running = true

	_pan_camera(dt)

	var k: float = minf(1.0, dt * 14.0)
	for id in views:
		var node: Node3D = views[id]
		var d3: Vector3 = targets[id] - node.position
		d3.y = 0.0
		var speed: float = d3.length() * 14.0
		var kind_id: int = info[id][0]
		var has_anim: bool = node.has_meta("ap")
		var pv: Node3D = node.get_node("pivot")
		var turn_rate: float = 2.2 if kind_id == 2 else 9.0
		var moving_now: bool = d3.length() > 0.12 and kind_id != 0
		if moving_now:
			pv.rotation.y = _turn(pv.rotation.y, atan2(d3.x, d3.z), dt * turn_rate)
			if has_anim:
				node.set_meta("mv", 0.3)
		elif has_anim:
			node.set_meta("mv", maxf(0.0, float(node.get_meta("mv")) - dt))
		if node.has_meta("aim_t"):
			var at: float = float(node.get_meta("aim_t")) - dt
			node.set_meta("aim_t", at)
			if at > 0.0 and not moving_now:
				pv.rotation.y = _turn(pv.rotation.y, float(node.get_meta("aim")), dt * turn_rate)
		if has_anim:
			var ap: AnimationPlayer = node.get_meta("ap")
			var shoot_t: float = maxf(0.0, float(node.get_meta("shoot_t", 0.0)) - dt)
			node.set_meta("shoot_t", shoot_t)
			var want: String = String(node.get_meta("idle"))
			var spd_scale: float = 1.0
			if float(node.get_meta("mv")) > 0.0:
				want = String(node.get_meta("run"))
				spd_scale = clampf(speed / (5.0 if kind_id == 2 else 6.0), 0.5, 1.8)
			elif shoot_t > 0.0 and String(node.get_meta("shoot")) != "":
				want = String(node.get_meta("shoot"))
			ap.speed_scale = spd_scale
			if want == "":
				if ap.is_playing():
					ap.pause()
			elif ap.current_animation != want or not ap.is_playing():
				ap.play(want)
		node.position = node.position.lerp(targets[id], k)
		node.get_node("sel").visible = selected.has(id)

	_update_projectiles(dt)

	if my_slot >= 0 and my_slot < money.size():
		money_label.text = "$ %d" % int(money[my_slot])
	sel_label.text = ("Selected: %d" % selected.size()) if not selected.is_empty() else ""
	var lines: PackedStringArray = PackedStringArray()
	for i in Net.slots.size():
		var sl: Dictionary = Net.slots[i]
		if sl["type"] == "human" or sl["type"] == "bot":
			var n: String = str(sl["name"]) if str(sl["name"]) != "" else "Bot"
			var dead: bool = i < alive_arr.size() and not alive_arr[i]
			var col: String = Data.PLAYER_COLORS[i].to_html(false)
			var line: String = "[color=#%s]■[/color] %s  [color=#8b98a9]%s[/color]" % [col, n, sl["country"]]
			if dead:
				line = "[s][color=#6b7280]%s  %s[/color][/s]  [color=#ff7b72]OUT[/color]" % [n, sl["country"]]
			lines.append(line)
	players_label.text = "\n".join(lines)
	status_label.text = status_text
	minimap.queue_redraw()

	if dragging:
		var m: Vector2 = get_viewport().get_mouse_position()
		if not moved and m.distance_to(drag_start) > 6.0:
			moved = true
		if moved and not box_mode and pan_anchor != null:
			var g = _ground_point(m)
			if g != null:
				cam_pivot.position += Vector3(pan_anchor.x - g.x, 0.0, pan_anchor.z - g.z)
				cam_pivot.position.x = clampf(cam_pivot.position.x, -140.0, 140.0)
				cam_pivot.position.z = clampf(cam_pivot.position.z, -140.0, 140.0)
		drag_rect.visible = moved and box_mode
		if drag_rect.visible:
			drag_rect.position = Vector2(minf(drag_start.x, m.x), minf(drag_start.y, m.y))
			drag_rect.size = (m - drag_start).abs()
		Input.set_default_cursor_shape(Input.CURSOR_DRAG if (moved and not box_mode) else Input.CURSOR_ARROW)
	else:
		drag_rect.visible = false


func _physics_process(dt: float) -> void:
	if sim == null or not running:
		return
	sim.step(dt)
	snap_timer += dt
	if snap_timer >= 1.0 / SNAP_HZ:
		snap_timer = 0.0
		var snap: PackedFloat32Array = sim.snapshot()
		var shots: PackedFloat32Array = sim.shots
		sim.shots = PackedFloat32Array()
		var mp: PackedFloat32Array = sim.money_packed()
		on_snapshot.rpc(snap, shots, mp, sim.alive, sim.status)
		on_snapshot(snap, shots, mp, sim.alive, sim.status)


@rpc("authority", "unreliable_ordered")
func on_snapshot(snap: PackedFloat32Array, shots: PackedFloat32Array, money_p: PackedFloat32Array, alive_p: Array, status: String) -> void:
	money = money_p
	alive_arr = alive_p
	status_text = status
	var seen: Dictionary = {}
	var n: int = floori(snap.size() / 6.0)
	for k in n:
		var o: int = k * 6
		var id: int = int(snap[o])
		var kind: int = int(snap[o + 1])
		var owner: int = int(snap[o + 2])
		var p: Vector3 = Vector3(snap[o + 3], 0.0, snap[o + 4])
		var frac: float = snap[o + 5]
		seen[id] = true
		if not views.has(id):
			_make_view(id, kind, owner)
			views[id].position = p
		targets[id] = p
		info[id] = [kind, owner, frac]
		_update_hp(id, kind, frac)
	for id in views.keys():
		if not seen.has(id):
			var kd: int = info[id][0]
			var bpos: Vector3 = views[id].position + Vector3(0, 1.5, 0)
			if kd == 0:
				_burst(bpos, 60, 1.0, 0.6, Color(1.0, 0.45, 0.1), 14.0, Vector3(0, -8, 0))
			elif kd == 2:
				_burst(bpos, 24, 0.7, 0.4, Color(1.0, 0.45, 0.1), 9.0, Vector3(0, -10, 0))
			else:
				_burst(bpos, 8, 0.4, 0.15, Color(0.85, 0.2, 0.1), 4.0, Vector3(0, -10, 0))
			views[id].queue_free()
			views.erase(id)
			targets.erase(id)
			info.erase(id)
			selected.erase(id)
	var m: int = floori(shots.size() / 6.0)
	for k in m:
		var o: int = k * 6
		_spawn_shot(int(shots[o]), Vector3(shots[o + 1], 0.0, shots[o + 2]), Vector3(shots[o + 3], 0.0, shots[o + 4]), int(shots[o + 5]))


func _make_view(id: int, kind: int, owner: int) -> void:
	var root: Node3D = Node3D.new()
	add_child(root)
	var pivot: Node3D = Node3D.new()
	pivot.name = "pivot"
	root.add_child(pivot)

	var country: String = Net.slots[owner]["country"]
	var col: Color = Data.PLAYER_COLORS[owner]
	var bar_w: float = 2.2
	var bar_y: float = 3.6
	var ring_r: float = 1.9
	var disc_r: float = 1.3
	var model_path: String = ""
	var by_h: bool = true
	var size: float = 2.4
	if kind == 0:
		model_path = Data.VISUALS[country]["hq"]
		by_h = false
		size = 13.0
		bar_w = 9.0
		bar_y = 9.0
		ring_r = 8.5
		disc_r = 8.5
	else:
		var v: Array = Data.VISUALS[country]["units"][kind - 1]
		model_path = v[0]
		by_h = v[1]
		size = v[2]
		if not by_h:
			bar_w = 3.4
			bar_y = 3.8
			ring_r = 3.4
			disc_r = 2.8

	# team-coloured ground disc so ownership is readable whatever the model colours are
	var disc: MeshInstance3D = MeshInstance3D.new()
	var dm: CylinderMesh = CylinderMesh.new()
	dm.top_radius = disc_r
	dm.bottom_radius = disc_r
	dm.height = 0.14
	disc.mesh = dm
	var dmat: StandardMaterial3D = StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.albedo_color = col
	disc.material_override = dmat
	disc.position.y = 0.07
	pivot.add_child(disc)

	var res = load(model_path)
	if res != null:
		var inst: Node3D = res.instantiate()
		pivot.add_child(inst)
		_fit(inst, size, by_h)
		_setup_anim(root, inst)
	else:
		var fb: MeshInstance3D = MeshInstance3D.new()
		var cm: CapsuleMesh = CapsuleMesh.new()
		cm.radius = 0.6
		cm.height = 2.0
		fb.mesh = cm
		fb.position.y = 1.0
		pivot.add_child(fb)

	var bar: MeshInstance3D = MeshInstance3D.new()
	var barm: BoxMesh = BoxMesh.new()
	barm.size = Vector3(bar_w, 0.3, 0.3)
	bar.mesh = barm
	var bmat: StandardMaterial3D = StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.albedo_color = Color(0.2, 1, 0.2)
	bar.material_override = bmat
	bar.position.y = bar_y
	bar.visible = false
	bar.name = "hp"
	root.add_child(bar)

	var ring: MeshInstance3D = MeshInstance3D.new()
	var rm: CylinderMesh = CylinderMesh.new()
	rm.top_radius = ring_r
	rm.bottom_radius = ring_r
	rm.height = 0.1
	ring.mesh = rm
	var rmat: StandardMaterial3D = StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.albedo_color = Color(0.2, 1, 0.2, 0.5)
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = rmat
	ring.position.y = 0.2
	ring.visible = false
	ring.name = "sel"
	root.add_child(ring)

	views[id] = root


# ---- model helpers ----

func _bounds(inst: Node3D) -> AABB:
	var parent: Node3D = inst.get_parent() as Node3D
	var inv: Transform3D = parent.global_transform.affine_inverse()
	var have: bool = false
	var box: AABB = AABB()
	var skels: Array = inst.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		# skinned models: bone positions give a reliable body extent
		for sk in skels:
			for b in sk.get_bone_count():
				var p: Vector3 = inv * (sk.global_transform * sk.get_bone_global_rest(b).origin)
				if not have:
					box = AABB(p, Vector3.ZERO)
					have = true
				else:
					box = box.expand(p)
		box = box.grow(maxf(box.size.x, maxf(box.size.y, box.size.z)) * 0.06)
		return box
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var b2: AABB = (inv * mi.global_transform) * mi.get_aabb()
		if not have:
			box = b2
			have = true
		else:
			box = box.merge(b2)
	return box


func _fit(inst: Node3D, target: float, by_height: bool) -> void:
	var box: AABB = _bounds(inst)
	var dim: float = box.size.y if by_height else maxf(box.size.x, box.size.z)
	if OS.get_cmdline_user_args().has("--autotest"):
		print("FIT %s raw=%s dim=%.3f" % [inst.name, box.size, dim])
	if dim < 0.0001:
		return
	var k: float = target / dim
	inst.scale = Vector3.ONE * k
	inst.position = Vector3(-(box.position.x + box.size.x * 0.5) * k, -box.position.y * k, -(box.position.z + box.size.z * 0.5) * k)


func _setup_anim(root: Node3D, inst: Node3D) -> void:
	var aps: Array = inst.find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		return
	var ap: AnimationPlayer = aps[0]
	var idle: String = ""
	var run: String = ""
	var shoot: String = ""
	for n in ap.get_animation_list():
		var low: String = String(n).to_lower()
		if idle == "" and low.ends_with("idle"):
			idle = String(n)
		if run == "" and (low.ends_with("|run") or low.ends_with("tank_forward")):
			run = String(n)
		if shoot == "" and (low.ends_with("idle_gun_shoot") or low.ends_with("idle_shoot")):
			shoot = String(n)
	for nm in [idle, run, shoot]:
		if nm != "":
			ap.get_animation(nm).loop_mode = Animation.LOOP_LINEAR
	root.set_meta("ap", ap)
	root.set_meta("idle", idle)
	root.set_meta("run", run)
	root.set_meta("shoot", shoot)
	root.set_meta("shoot_t", 0.0)
	root.set_meta("mv", 0.0)
	if idle != "":
		ap.play(idle)


func _place_model(path: String, pos: Vector3, size: float, by_h: bool, yaw: float) -> void:
	var res = load(path)
	if res == null:
		return
	var holder: Node3D = Node3D.new()
	holder.position = pos
	holder.rotation.y = yaw
	add_child(holder)
	var inst: Node3D = res.instantiate()
	holder.add_child(inst)
	_fit(inst, size, by_h)


func _scatter_props() -> void:
	var r: RandomNumberGenerator = RandomNumberGenerator.new()
	r.seed = Net.seed_value + 7
	var trees: Array = ["res://assets/props/tree.glb", "res://assets/props/tree-high.glb"]
	var rocks: Array = ["res://assets/props/rocks-high.glb", "res://assets/props/rocks-low.glb", "res://assets/props/stones.glb"]
	var placed: int = 0
	var attempts: int = 0
	while placed < 100 and attempts < 800:
		attempts += 1
		var a: float = r.randf() * TAU
		var rad: float = r.randf_range(30.0, 150.0)
		if rad < 105.0 and r.randf() < 0.85:
			continue # keep the battle lanes mostly clear
		var p: Vector3 = Vector3(cos(a) * rad, 0.0, sin(a) * rad)
		var blocked: bool = false
		for i in Data.MAX_SLOTS:
			if p.distance_to(Data.slot_pos(i)) < 34.0:
				blocked = true
		if blocked:
			continue
		if r.randf() < 0.65:
			_place_model(trees[r.randi() % trees.size()], p, r.randf_range(5.0, 9.0), true, r.randf() * TAU)
		else:
			_place_model(rocks[r.randi() % rocks.size()], p, r.randf_range(3.0, 7.0), false, r.randf() * TAU)
		placed += 1


func _decorate_bases() -> void:
	var kit: String = "res://assets/buildings/kenney_city_industrial/"
	for i in Net.slots.size():
		var t: String = Net.slots[i]["type"]
		if t != "human" and t != "bot":
			continue
		var base: Vector3 = Data.slot_pos(i)
		var out: Vector3 = base.normalized()
		var side: Vector3 = out.rotated(Vector3.UP, PI / 2.0)
		var yaw: float = atan2(out.x, out.z)
		_place_model(kit + "shipping-container-a.glb", base + out * 15.0 + side * -9.0, 4.5, false, yaw)
		_place_model(kit + "shipping-container-b.glb", base + out * 15.0 + side * -3.0, 4.5, false, yaw)
		_place_model(kit + "shipping-container-c.glb", base + out * 15.0 + side * 3.0, 4.5, false, yaw)
		_place_model(kit + "water-tower.glb", base + out * 17.0 + side * 10.0, 10.0, true, 0.0)
		_place_model(kit + "detail-tank.glb", base + out * 10.0 + side * 13.0, 4.0, false, 0.0)
		_place_model("res://assets/props/tent.glb", base + side * -15.0, 5.0, false, yaw)
		_place_model("res://assets/props/flag.glb", base + out * -9.0 + side * 8.0, 6.0, true, 0.0)


func _update_hp(id: int, _kind: int, frac: float) -> void:
	var bar: Node3D = views[id].get_node("hp")
	bar.visible = frac < 0.999
	bar.scale.x = maxf(frac, 0.01)


func _turn(cur: float, tgt: float, step: float) -> float:
	return cur + clampf(wrapf(tgt - cur, -PI, PI), -step, step)


func _fx_material(col: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	return m


func _spawn_shot(shooter: int, from: Vector3, to: Vector3, kind: int) -> void:
	var dv: Vector3 = to - from
	dv.y = 0.0
	if views.has(shooter):
		var v: Node3D = views[shooter]
		v.set_meta("aim", atan2(dv.x, dv.z))
		v.set_meta("aim_t", 0.7)
		v.set_meta("shoot_t", 0.5)
	if projectiles.size() >= 60 or dv.length() < 0.5:
		return
	var heavy: bool = kind == 2
	var a: Vector3 = Vector3(from.x, 2.3 if heavy else 1.5, from.z)
	var b: Vector3 = Vector3(to.x, 1.4, to.z)
	var node: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = Vector3(0.25, 0.25, 1.8) if heavy else Vector3(0.08, 0.08, 1.2)
	node.mesh = bm
	node.material_override = _fx_material(Color(1.0, 0.65, 0.15) if heavy else Color(1.0, 0.95, 0.5))
	add_child(node)
	node.position = a
	node.look_at(b)
	projectiles.append({"n": node, "a": a, "b": b, "t": 0.0, "d": maxf(0.04, a.distance_to(b) / (40.0 if heavy else 85.0)), "heavy": heavy})
	_burst(a, 6 if heavy else 3, 0.12, 0.25 if heavy else 0.12, Color(1.0, 0.85, 0.3), 3.0, Vector3.ZERO)


func _burst(pos: Vector3, amount: int, life: float, size: float, col: Color, vel: float, grav: Vector3) -> void:
	if get_tree().get_nodes_in_group("fx").size() > 50:
		return
	var ps: CPUParticles3D = CPUParticles3D.new()
	ps.add_to_group("fx")
	ps.one_shot = true
	ps.amount = amount
	ps.lifetime = life
	ps.explosiveness = 1.0
	ps.spread = 180.0
	ps.direction = Vector3.UP
	ps.initial_velocity_min = vel * 0.4
	ps.initial_velocity_max = vel
	ps.gravity = grav
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = size
	sm.height = size * 2.0
	sm.radial_segments = 6
	sm.rings = 3
	sm.material = _fx_material(col)
	ps.mesh = sm
	ps.position = pos
	add_child(ps)
	ps.emitting = true
	ps.finished.connect(ps.queue_free)


func _update_projectiles(dt: float) -> void:
	var i: int = projectiles.size() - 1
	while i >= 0:
		var p: Dictionary = projectiles[i]
		p["t"] += dt
		var f: float = minf(p["t"] / p["d"], 1.0)
		p["n"].position = p["a"].lerp(p["b"], f)
		if f >= 1.0:
			var heavy: bool = p["heavy"]
			_burst(p["b"], 14 if heavy else 6, 0.4, 0.22 if heavy else 0.1, Color(1.0, 0.5, 0.12), 6.0 if heavy else 3.5, Vector3(0, -12, 0))
			p["n"].queue_free()
			projectiles.remove_at(i)
		i -= 1


# ------------------------------------------------------------------ camera

func _update_cam() -> void:
	cam.position = Vector3(0, zoom * 0.87, zoom * 0.5)


func _pan_camera(dt: float) -> void:
	var dir: Vector2 = Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	var vp: Viewport = get_viewport()
	var m: Vector2 = vp.get_mouse_position()
	var sz: Vector2 = vp.get_visible_rect().size
	if Rect2(Vector2.ZERO, sz).has_point(m):
		if m.x <= 4.0:
			dir.x -= 1.0
		if m.x >= sz.x - 4.0:
			dir.x += 1.0
		if m.y <= 4.0:
			dir.y -= 1.0
		if m.y >= sz.y - 4.0:
			dir.y += 1.0
	cam_pivot.position += Vector3(dir.x, 0, dir.y) * zoom * 1.2 * dt
	cam_pivot.position.x = clampf(cam_pivot.position.x, -140.0, 140.0)
	cam_pivot.position.z = clampf(cam_pivot.position.z, -140.0, 140.0)


# ------------------------------------------------------------------ input

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				dragging = true
				moved = false
				box_mode = ev.shift_pressed
				drag_start = ev.position
				pan_anchor = _ground_point(ev.position)
			elif dragging:
				dragging = false
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
				if not moved and drag_start.distance_to(ev.position) > 6.0:
					moved = true
				if not moved or box_mode:
					_finish_drag(ev.position)
		elif ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
			_right_click(ev.position)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
			zoom = clampf(zoom - 6.0, 20.0, 140.0)
			_update_cam()
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
			zoom = clampf(zoom + 6.0, 20.0, 140.0)
			_update_cam()
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.keycode == KEY_Q:
			_train(0)
		elif ev.keycode == KEY_E:
			_train(1)
		elif ev.keycode == KEY_F:
			selected.clear()
			for id in info:
				if info[id][1] == my_slot and info[id][0] != 0:
					selected[id] = true
		elif ev.keycode == KEY_ESCAPE:
			pause_layer.visible = not pause_layer.visible


func _ground_point(sp: Vector2) -> Variant:
	var o: Vector3 = cam.project_ray_origin(sp)
	var d: Vector3 = cam.project_ray_normal(sp)
	if absf(d.y) < 0.0001:
		return null
	var t: float = -o.y / d.y
	if t < 0.0:
		return null
	return o + d * t


func _finish_drag(end: Vector2) -> void:
	selected.clear()
	if my_slot < 0:
		return
	if drag_start.distance_to(end) < 6.0:
		var g = _ground_point(end)
		if g == null:
			return
		var best: int = -1
		var best_d: float = 2.5
		for id in info:
			if info[id][1] == my_slot and info[id][0] != 0:
				var d: float = Vector2(targets[id].x - g.x, targets[id].z - g.z).length()
				if d < best_d:
					best_d = d
					best = id
		if best != -1:
			selected[best] = true
	else:
		var rect: Rect2 = Rect2(drag_start, Vector2.ZERO).expand(end)
		for id in info:
			if info[id][1] == my_slot and info[id][0] != 0:
				if rect.has_point(cam.unproject_position(views[id].position)):
					selected[id] = true


func _right_click(sp: Vector2) -> void:
	if selected.is_empty() or my_slot < 0:
		return
	var g = _ground_point(sp)
	if g == null:
		return
	var enemy: int = -1
	var best_d: float = 100.0
	for id in info:
		if info[id][1] == my_slot:
			continue
		var reach: float = 8.0 if info[id][0] == 0 else 2.5
		var d: float = Vector2(targets[id].x - g.x, targets[id].z - g.z).length()
		if d < reach and d < best_d:
			best_d = d
			enemy = id
	var ids: Array = selected.keys()
	if ids.size() > 200:
		ids = ids.slice(0, 200)
	if enemy != -1:
		if multiplayer.is_server():
			sim.cmd_attack(my_slot, ids, enemy)
		else:
			srv_attack.rpc_id(1, ids, enemy)
	else:
		if multiplayer.is_server():
			sim.cmd_move(my_slot, ids, g, false)
		else:
			srv_move.rpc_id(1, ids, g)


func _train(idx: int) -> void:
	if my_slot < 0:
		return
	if multiplayer.is_server():
		if sim != null:
			sim.cmd_train(my_slot, idx)
	else:
		srv_train.rpc_id(1, idx)


@rpc("any_peer", "reliable")
func srv_move(ids: Array, pos: Vector3) -> void:
	if not multiplayer.is_server() or sim == null or ids.size() > 200:
		return
	var slot: int = _slot_of(multiplayer.get_remote_sender_id())
	if slot >= 0:
		sim.cmd_move(slot, ids, pos, false)


@rpc("any_peer", "reliable")
func srv_attack(ids: Array, target_id: int) -> void:
	if not multiplayer.is_server() or sim == null or ids.size() > 200:
		return
	var slot: int = _slot_of(multiplayer.get_remote_sender_id())
	if slot >= 0:
		sim.cmd_attack(slot, ids, target_id)


@rpc("any_peer", "reliable")
func srv_train(idx: int) -> void:
	if not multiplayer.is_server() or sim == null:
		return
	var slot: int = _slot_of(multiplayer.get_remote_sender_id())
	if slot >= 0:
		sim.cmd_train(slot, idx)


func _leave() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	Net.reset()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
