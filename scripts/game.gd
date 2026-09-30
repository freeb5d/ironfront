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
var shot_lines: Array = []    # [from, to, ttl]

var cam_pivot: Node3D
var cam: Camera3D
var zoom: float = 60.0
var shot_mesh: ImmediateMesh

var money_label: Label
var players_label: Label
var status_label: Label
var help_label: Label
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

	cam_pivot = Node3D.new()
	add_child(cam_pivot)
	cam = Camera3D.new()
	cam.rotation_degrees = Vector3(-60, 0, 0)
	cam_pivot.add_child(cam)
	cam.make_current()

	shot_mesh = ImmediateMesh.new()
	var sm: MeshInstance3D = MeshInstance3D.new()
	sm.mesh = shot_mesh
	var smat: StandardMaterial3D = StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(1, 0.9, 0.2)
	sm.material_override = smat
	add_child(sm)


func _build_hud() -> void:
	var hud: CanvasLayer = CanvasLayer.new()
	add_child(hud)

	money_label = Label.new()
	money_label.position = Vector2(16, 10)
	money_label.add_theme_font_size_override("font_size", 22)
	hud.add_child(money_label)

	help_label = Label.new()
	help_label.position = Vector2(16, 42)
	help_label.text = "LMB select | RMB move/attack | WASD/edges pan | wheel zoom | Q/E train | Esc menu"
	hud.add_child(help_label)

	players_label = Label.new()
	hud.add_child(players_label)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 48)
	hud.add_child(status_label)

	if my_slot >= 0:
		var country: String = Net.slots[my_slot]["country"]
		for idx in 2:
			var st: Dictionary = Data.unit(country, idx)
			var b: Button = Button.new()
			b.text = "[%s] %s  $%d" % [["Q", "E"][idx], st["name"], st["cost"]]
			b.custom_minimum_size = Vector2(220, 40)
			b.pressed.connect(_train.bind(idx))
			hud.add_child(b)
			train_buttons.append(b)

	drag_rect = ColorRect.new()
	drag_rect.color = Color(0, 1, 0, 0.15)
	drag_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_rect.visible = false
	hud.add_child(drag_rect)


func _layout_hud() -> void:
	var sz: Vector2 = get_viewport().get_visible_rect().size
	players_label.position = Vector2(sz.x - 300, 10)
	status_label.position = Vector2(sz.x * 0.5 - 250, sz.y * 0.35)
	for k in train_buttons.size():
		train_buttons[k].position = Vector2(16, sz.y - 56 - 48 * k)


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
	_layout_hud()

	var k: float = minf(1.0, dt * 14.0)
	for id in views:
		var node: Node3D = views[id]
		node.position = node.position.lerp(targets[id], k)
		node.get_node("sel").visible = selected.has(id)

	_draw_shots(dt)

	if my_slot >= 0 and my_slot < money.size():
		money_label.text = "Credits: %d" % int(money[my_slot])
	var lines: Array = []
	for i in Net.slots.size():
		var s: Dictionary = Net.slots[i]
		if s["type"] == "human" or s["type"] == "bot":
			var n: String = str(s["name"]) if str(s["name"]) != "" else "Bot"
			var dead: bool = i < alive_arr.size() and not alive_arr[i]
			lines.append("%d %s - %s%s" % [i + 1, n, s["country"], "  [OUT]" if dead else ""])
	players_label.text = "\n".join(lines)
	status_label.text = status_text

	if dragging:
		var m: Vector2 = get_viewport().get_mouse_position()
		drag_rect.visible = true
		drag_rect.position = Vector2(minf(drag_start.x, m.x), minf(drag_start.y, m.y))
		drag_rect.size = (m - drag_start).abs()
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
			views[id].queue_free()
			views.erase(id)
			targets.erase(id)
			info.erase(id)
			selected.erase(id)
	var m: int = floori(shots.size() / 4.0)
	for k in m:
		var o: int = k * 4
		shot_lines.append([Vector3(shots[o], 1.0, shots[o + 1]), Vector3(shots[o + 2], 1.0, shots[o + 3]), 0.2])


func _make_view(id: int, kind: int, owner: int) -> void:
	var root: Node3D = Node3D.new()
	var body: MeshInstance3D = MeshInstance3D.new()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Data.PLAYER_COLORS[owner]
	body.material_override = mat
	var bar_w: float = 2.0
	var bar_y: float = 3.2
	var ring_r: float = 1.8
	if kind == 0:
		var bm: BoxMesh = BoxMesh.new()
		bm.size = Vector3(10, 5, 10)
		body.mesh = bm
		body.position.y = 2.5
		bar_w = 8.0
		bar_y = 7.0
		ring_r = 8.0
	elif kind == 1:
		var cm: CapsuleMesh = CapsuleMesh.new()
		cm.radius = 0.6
		cm.height = 2.0
		body.mesh = cm
		body.position.y = 1.0
	else:
		var tm: BoxMesh = BoxMesh.new()
		tm.size = Vector3(2.6, 1.4, 3.6)
		body.mesh = tm
		body.position.y = 0.7
	body.name = "body"
	root.add_child(body)

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
	ring.position.y = 0.08
	ring.visible = false
	ring.name = "sel"
	root.add_child(ring)

	add_child(root)
	views[id] = root


func _update_hp(id: int, _kind: int, frac: float) -> void:
	var bar: Node3D = views[id].get_node("hp")
	bar.visible = frac < 0.999
	bar.scale.x = maxf(frac, 0.01)


func _draw_shots(dt: float) -> void:
	shot_mesh.clear_surfaces()
	for s in shot_lines:
		s[2] -= dt
	shot_lines = shot_lines.filter(func(s): return s[2] > 0.0)
	if shot_lines.is_empty():
		return
	shot_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for s in shot_lines:
		shot_mesh.surface_add_vertex(s[0])
		shot_mesh.surface_add_vertex(s[1])
	shot_mesh.surface_end()


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
				drag_start = ev.position
			elif dragging:
				dragging = false
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
		elif ev.keycode == KEY_ESCAPE:
			_leave()


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
