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
var rdragging: bool = false
var rstart: Vector2 = Vector2.ZERO
var ground_tex: ImageTexture = null
var msg_label: RichTextLabel
var plate: PanelContainer
var fps_label: Label
var bottom_bar: PanelContainer
var info_label: RichTextLabel
var unit_bar: ProgressBar
var msgs: Array = []          # [text, ttl, colour]
var last_alert: float = -99.0
var sun: DirectionalLight3D
var stats: Array = []         # [kills[], lost[], earned[]] per slot
var t0: float = Time.get_ticks_msec() / 1000.0
var last_coin: float = -99.0
var last_ready: float = -99.0
var groups: Dictionary = {}   # 1..9 -> [unit ids]
var group_tap: Dictionary = {}
var last_click_t: float = -99.0
var last_click_kind: int = -1
var end_layer: CanvasLayer = null
var final_shown: bool = false
var elim_shown: bool = false
var targeting: int = -1      # power waiting for a map click, -1 = none
var power_tiles: Array = []
var placing: int = -1         # building type being placed, -1 = none
var ghost: MeshInstance3D = null
var ghost_mat: StandardMaterial3D = null
var power_row: HBoxContainer
var build_row: HBoxContainer
var build_tiles: Array = []
var super_tile: Button
var upg_tiles: Array = []
var shake: float = 0.0
var tips_shown: Dictionary = {}

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
	_build_hud_v2()
	cam_pivot.position = Data.slot_pos(maxi(my_slot, 0)) * 0.75
	_update_cam()
	Net.server_lost.connect(_leave)
	if multiplayer.is_server():
		sim = Sim.new()
		sim.difficulty = Net.match_difficulty
		sim.setup(Net.slots, Net.seed_value, Net.options)
		Net.peer_left.connect(_on_peer_left)
		ready_peers[1] = true
		started_at = Time.get_ticks_msec() / 1000.0
	else:
		srv_ready.rpc_id(1)
	if "--autotest" in OS.get_cmdline_user_args():
		get_tree().create_timer(5.0).timeout.connect(_autotest_finish)


func _autotest_finish() -> void:
	await Net.shot("10_game_base")
	# exercise the same code paths real input uses
	for id in info:
		if info[id][1] == my_slot and _is_unit(info[id][0]):
			selected[id] = true
	_train(0)
	_train(1)
	_train(2)
	_box_select(Vector2(0, 0), Vector2(1280, 720))
	await get_tree().create_timer(0.4).timeout
	await Net.shot("11_selection")
	_right_click(Vector2(640, 360))
	_finish_drag(Vector2(100, 100))
	# base building: ghost, placement, construction
	selected.clear()
	for id in info:
		if info[id][1] == my_slot and info[id][0] == 6:
			selected[id] = true
	_build_key(9)
	await get_tree().create_timer(0.2).timeout
	_cancel_placing()
	var hq_at: Vector3 = Data.slot_pos(my_slot)
	var built_ok: bool = _cast_build(7, hq_at + Vector3(20, 0, 18))
	print("AUTOTEST BUILD placed=%s" % str(built_ok))
	_upgrade_key(2)
	_power_key(3)
	_handle_fx(PackedFloat32Array([5.0, hq_at.x + 25.0, hq_at.z + 25.0, 6.0, hq_at.x + 40.0, hq_at.z + 25.0, 7.0, hq_at.x, hq_at.z]))
	await get_tree().create_timer(0.8).timeout
	await Net.shot("17_base")
	# overview of the whole map
	var keep_pivot: Vector3 = cam_pivot.position
	zoom = 140.0
	_update_cam()
	cam_pivot.position = Vector3.ZERO
	await get_tree().create_timer(0.4).timeout
	await Net.shot("12_overview")
	zoom = 50.0
	_update_cam()
	cam_pivot.position = keep_pivot
	# force the combat visuals that a real fight would trigger
	var any_id: int = views.keys()[0] if not views.is_empty() else -1
	var at: Vector3 = keep_pivot
	_spawn_shot(any_id, at + Vector3(-8, 0, 0), at + Vector3(14, 0, 3), 1)
	_spawn_shot(any_id, at + Vector3(-6, 0, 4), at + Vector3(18, 0, -4), 2)
	_burst(at + Vector3(14, 1, 3), 20, 0.5, 0.3, Color(1, 0.5, 0.1), 8.0, Vector3(0, -9, 0))
	await get_tree().create_timer(0.15).timeout
	await Net.shot("13_combat")
	_update_projectiles(0.05)
	_update_projectiles(1.0)
	# sound, hotkeys, groups, stop and the scoreboard
	for k in ["shot", "cannon", "boom", "click", "coin", "capture", "alarm", "ready"]:
		_play3d(k, Vector3(3, 0, 3), -10.0)
		_play_ui(k, -20.0)
	_group_key(1, true)
	_group_key(1, false)
	_center_on_hq()
	_stop_selected()
	_handle_fx(PackedFloat32Array([1.0, keep_pivot.x + 12.0, keep_pivot.z + 4.0, 2.0, keep_pivot.x + 12.0, keep_pivot.z + 4.0, 3.0, keep_pivot.x, keep_pivot.z]))
	if any_id != -1:
		_update_rank(any_id, 2)
	_cast_power(1, Vector3.ZERO)
	_cast_power(0, keep_pivot + Vector3(30, 0, 0))
	await get_tree().create_timer(0.4).timeout
	await Net.shot("16_powers")
	# simulate a click-drag pan
	drag_start = Vector2(400, 300)
	pan_anchor = _ground_point(drag_start)
	moved = true
	box_mode = false
	dragging = true
	await get_tree().create_timer(0.3).timeout
	dragging = false
	_show_end("VICTORY", true)
	print("AUTOTEST FEATURES stats=%d groups=%d" % [stats.size(), groups.size()])
	await get_tree().create_timer(0.3).timeout
	await Net.shot("14_scoreboard")
	end_layer.visible = false
	pause_layer.visible = true
	await get_tree().create_timer(0.3).timeout
	await Net.shot("15_pause")
	await get_tree().create_timer(1.0).timeout
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

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.shadow_enabled = Net.shadows
	add_child(sun)

	var ground: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(320, 320)
	ground.mesh = pm
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	ground_tex = _make_ground_texture()
	gm.albedo_texture = ground_tex
	gm.roughness = 1.0
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



func _make_ground_texture() -> ImageTexture:
	# desert map: light edge strips, a sunken dark centre and a dark road across the middle
	var n: int = 384
	var img: Image = Image.create(n, n, false, Image.FORMAT_RGB8)
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 0.035
	var sand: Color = Color(0.80, 0.70, 0.50)
	var light: Color = Color(0.89, 0.81, 0.63)
	var dark: Color = Color(0.46, 0.37, 0.26)
	var road: Color = Color(0.25, 0.20, 0.15)
	for py in n:
		for px in n:
			var x: float = (float(px) / n - 0.5) * 320.0
			var z: float = (float(py) / n - 0.5) * 320.0
			var nz: float = noise.get_noise_2d(x, z)
			var c: Color = sand
			if (absf(x) < 60.0 + nz * 8.0 and absf(z) > 72.0) or (absf(z) < 60.0 + nz * 8.0 and absf(x) > 78.0):
				c = light
			if absf(x) < 78.0 + nz * 10.0 and absf(z) < 66.0 + nz * 10.0:
				c = dark
			if absf(z - 7.0 * sin(x * 0.035)) < 6.0 + nz * 2.5:
				c = road if absf(x) < 90.0 else road.lerp(sand, 0.35)
			var g: float = nz * 0.04
			c = Color(clampf(c.r + g, 0.0, 1.0), clampf(c.g + g, 0.0, 1.0), clampf(c.b + g, 0.0, 1.0))
			if absf(x) > 152.0 or absf(z) > 152.0:
				c = c.darkened(0.35)
			img.set_pixel(px, py, c)
	return ImageTexture.create_from_image(img)


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
	minimap.bg = ground_tex
	bh.add_child(minimap)
	var bv: VBoxContainer = VBoxContainer.new()
	bv.add_theme_constant_override("separation", 8)
	bh.add_child(bv)
	bv.add_child(UI.label("TRAIN", 14, Color("8b98a9")))
	if my_slot >= 0:
		var country: String = Net.slots[my_slot]["country"]
		for idx in 3:
			var st: Dictionary = Data.unit(country, idx)
			var b: Button = Button.new()
			b.text = "[%s]  %s   $%d" % [["Q", "E", "R"][idx], st["name"], st["cost"]]
			b.custom_minimum_size = Vector2(250, 46)
			b.pressed.connect(_train.bind(idx))
			bv.add_child(b)
			train_buttons.append(b)
	var help: Label = UI.label("Click select   Right-drag = box select   Right-click = move / attack / harvest\nLeft-drag = move map   WASD pan   Wheel zoom   F army   F11 fullscreen   Esc menu", 13, Color("8b98a9"))
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


func _sb(fill: Color, border: Color, bw: int, radius: int, margin: int) -> StyleBoxFlat:
	var sb: StyleBoxFlat = UI.box(fill, border, bw, radius)
	sb.set_content_margin_all(margin)
	return sb


## A command tile: live 3D portrait on top, name and price below. Call _tile_ready() once it is in the tree.
func _tile(text: String, cb: Callable, entries: Array = []) -> Button:
	var b: Button = Button.new()
	b.custom_minimum_size = Vector2(98, 98)
	b.pressed.connect(cb)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 0)
	b.add_child(vb)
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not entries.is_empty():
		var p: Portrait = Portrait.new()
		vb.add_child(p)
		b.set_meta("portrait", p)
		b.set_meta("entries", entries)
	var parts: PackedStringArray = text.split("\n")
	for i in parts.size():
		var l: Label = UI.label(parts[i], 15 if i == 0 else 13, UI.TEXT if i == 0 else Color("b9c6d6"))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(l)
		if i == 1:
			b.set_meta("sub", l)
	return b


func _tile_ready(b: Button) -> void:
	if b.has_meta("portrait"):
		var p: Portrait = b.get_meta("portrait")
		p.setup(b.get_meta("entries"), Vector2i(90, 54), 0.5)


func _empty_tile() -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	p.custom_minimum_size = Vector2(98, 98)
	p.add_theme_stylebox_override("panel", _sb(Color(0.05, 0.08, 0.12), Color(0.16, 0.22, 0.30), 2, 4, 4))
	return p


func _msg(text: String, col: Color = Color(1, 1, 1), ttl: float = 6.0) -> void:
	msgs.append([text, ttl, col])
	if msgs.size() > 5:
		msgs.pop_front()


func _tip(id: String, text: String) -> void:
	if not Net.tips or tips_shown.has(id):
		return
	tips_shown[id] = true
	_msg(text, Color(0.75, 0.92, 1.0), 9.0)


func _tips_tick() -> void:
	if my_slot < 0 or info.is_empty():
		return
	var elapsed: float = Time.get_ticks_msec() / 1000.0 - t0
	if elapsed > 3.0:
		_tip("t1", "Tip: click a unit to select it, right-click to give orders. Hold the LEFT mouse button on empty ground and drag to move the map.")
	if elapsed > 16.0:
		_tip("t2", "Tip: farmers (R) carry money from the green $ fields back to your base. More farmers, more income.")
	if elapsed > 30.0 and not _has_complete(7):
		_tip("t3", "Tip: click your Builder, then press Y to put down a Power Plant. Buildings need power.")
	if _has_complete(7):
		_tip("t4", "Power online. Next: Barracks (I) for faster infantry, then a War Factory (O) to unlock tanks.")
	if _has_complete(10):
		_tip("t5", "War Factory ready. Move combat units onto the oil derricks in the middle to capture them for extra income.")
	if _has_complete(12):
		_tip("t6", "Superweapon ready. Press J, then click where it should land.")


func _challenge_go(stage: int) -> void:
	Net.challenge_resume = {"stage": stage, "nation": str(Net.challenge["nation"])}
	Net.challenge_autostart = true
	_leave()


func _select_kinds(kinds: Array) -> void:
	selected.clear()
	for id in info:
		if info[id][1] == my_slot and kinds.has(info[id][0]):
			selected[id] = true


func _build_hud_v2() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var root: Control = Control.new()
	root.theme = UI.make_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# event messages, top-left
	msg_label = RichTextLabel.new()
	msg_label.bbcode_enabled = true
	msg_label.fit_content = true
	msg_label.scroll_active = false
	msg_label.custom_minimum_size = Vector2(560, 0)
	msg_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	msg_label.add_theme_font_size_override("normal_font_size", 22)
	msg_label.add_theme_constant_override("outline_size", 6)
	msg_label.add_theme_color_override("font_outline_color", Color.BLACK)
	msg_label.position = Vector2(16, 12)
	root.add_child(msg_label)

	fps_label = UI.label("", 16, Color(0.6, 1.0, 0.6))
	root.add_child(fps_label)

	# players list, top-right
	var pl: PanelContainer = _panel(root)
	pl.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pl.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	pl.offset_top = 10
	pl.offset_right = -10
	players_label = RichTextLabel.new()
	players_label.bbcode_enabled = true
	players_label.fit_content = true
	players_label.scroll_active = false
	players_label.custom_minimum_size = Vector2(300, 0)
	players_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pl.add_child(players_label)

	# bottom command bar
	bottom_bar = PanelContainer.new()
	var bsb: StyleBoxFlat = _sb(Color(0.07, 0.11, 0.17, 0.97), Color(0.42, 0.55, 0.70), 0, 0, 8)
	bsb.border_width_top = 5
	bottom_bar.add_theme_stylebox_override("panel", bsb)
	root.add_child(bottom_bar)
	bottom_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom_bar.custom_minimum_size = Vector2(0, 190)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bottom_bar.add_child(row)

	# minimap in a steel frame
	var frame: PanelContainer = PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _sb(Color(0.02, 0.03, 0.05), Color(0.45, 0.58, 0.72), 5, 6, 4))
	row.add_child(frame)
	minimap = MiniMap.new()
	minimap.game = self
	minimap.bg = ground_tex
	minimap.custom_minimum_size = Vector2(200, 200)
	frame.add_child(minimap)

	# command tiles in the centre
	var centre: VBoxContainer = VBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.add_theme_constant_override("separation", 6)
	row.add_child(centre)
	sel_label = UI.label("", 16, Color("b9c6d6"))
	centre.add_child(sel_label)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	centre.add_child(grid)
	power_row = HBoxContainer.new()
	power_row.add_theme_constant_override("separation", 6)
	centre.add_child(power_row)
	build_row = HBoxContainer.new()
	build_row.add_theme_constant_override("separation", 6)
	build_row.visible = false
	centre.add_child(build_row)
	if my_slot >= 0:
		var country: String = Net.slots[my_slot]["country"]
		for idx in 4:
			var st: Dictionary = Data.unit(country, idx)
			var vis: Array = Data.unit_visual(country, idx)
			var b: Button = _tile("%s\n$%d  [%s]" % [st["name"], st["cost"], ["Q", "E", "R", "B"][idx]], _train.bind(idx), [[vis[0], vis[1], 3.2 if vis[1] else 5.0]])
			grid.add_child(b)
			_tile_ready(b)
			train_buttons.append(b)
			b.tooltip_text = "%s\nHP %d   Damage %d   Range %d" % [Data.TRAIN_TIPS[idx], st["hp"], st["dmg"], st["rng"]] if idx < 2 else str(Data.TRAIN_TIPS[idx])
		var army_vis: Array = Data.VISUALS[country]["units"][0]
		var t_army: Button = _tile("Select army\n[F]", _select_kinds.bind([1, 2]), [[army_vis[0], true, 3.2]])
		grid.add_child(t_army)
		_tile_ready(t_army)
		var t_farm: Button = _tile("Select farmers\n[G]", _select_kinds.bind([3]), [[Data.FARMER_VISUAL[0], true, 3.2]])
		grid.add_child(t_farm)
		_tile_ready(t_farm)

		var pnames: Array = Data.COUNTRIES[country]["powers"]
		for pi in 3:
			var pt: Button = _tile("%s\n1 pt  [%s]" % [pnames[pi], ["Z", "C", "V"][pi]], _power_key.bind(pi), [])
			var icon: PowerIcon = PowerIcon.new()
			icon.kind = pi
			var pvb: Node = pt.get_child(0)
			pvb.add_child(icon)
			pvb.move_child(icon, 0)
			power_row.add_child(pt)
			power_tiles.append(pt)
			pt.tooltip_text = Data.POWER_TIPS[pi]
		super_tile = _tile("%s\n[J]" % pnames[3], _power_key.bind(3), [])
		var sicon: PowerIcon = PowerIcon.new()
		sicon.kind = 4
		var svb: Node = super_tile.get_child(0)
		svb.add_child(sicon)
		svb.move_child(sicon, 0)
		power_row.add_child(super_tile)
		super_tile.tooltip_text = Data.POWER_TIPS[3]
		for ui in 3:
			var up: Dictionary = Data.UPGRADES[ui]
			var ut: Button = _tile("%s\n$%d" % [up["name"], up["cost"]], _upgrade_key.bind(ui), [])
			var uicon: PowerIcon = PowerIcon.new()
			uicon.kind = 5 + ui
			var uvb: Node = ut.get_child(0)
			uvb.add_child(uicon)
			uvb.move_child(uicon, 0)
			power_row.add_child(ut)
			upg_tiles.append(ut)
			ut.tooltip_text = "%s  ($%d, %ds)\n%s" % [up["name"], up["cost"], int(up["time"]), Data.UPGRADE_TIPS[ui]]

		var bkeys: Array = ["Y", "U", "I", "O", "P", "T"]
		var btypes: Array = [7, 8, 9, 10, 11, 12]
		for bi in 6:
			var def: Dictionary = Data.BUILD[btypes[bi]]
			var entries: Array = []
			if Data.BUILD_VISUAL.has(btypes[bi]):
				var bv: Array = Data.BUILD_VISUAL[btypes[bi]]
				entries = [[bv[0], bv[1], 4.6 if bv[1] else 5.6]]
			var bt: Button = _tile("%s\n$%d  [%s]" % [def["name"], def["cost"], bkeys[bi]], _build_key.bind(btypes[bi]), entries)
			if entries.is_empty():
				var bicon: PowerIcon = PowerIcon.new()
				bicon.kind = 3
				var bvb: Node = bt.get_child(0)
				bvb.add_child(bicon)
				bvb.move_child(bicon, 0)
			build_row.add_child(bt)
			_tile_ready(bt)
			build_tiles.append(bt)
			bt.tooltip_text = "%s  ($%d)\n%s" % [def["name"], def["cost"], Data.BUILD_TIPS[btypes[bi]]]

	# nation panel on the right
	var right: PanelContainer = PanelContainer.new()
	right.add_theme_stylebox_override("panel", _sb(Color(0.05, 0.08, 0.12), Color(0.45, 0.58, 0.72), 3, 6, 10))
	row.add_child(right)
	var rh: HBoxContainer = HBoxContainer.new()
	rh.add_theme_constant_override("separation", 10)
	right.add_child(rh)
	var rv: VBoxContainer = VBoxContainer.new()
	rv.custom_minimum_size = Vector2(230, 0)
	rh.add_child(rv)
	var cname: String = Net.slots[my_slot]["country"] if my_slot >= 0 else "Spectator"
	var ccol: Color = Data.PLAYER_COLORS[maxi(my_slot, 0)]
	rv.add_child(UI.label(cname.to_upper(), 30, ccol))
	info_label = RichTextLabel.new()
	info_label.bbcode_enabled = true
	info_label.fit_content = true
	info_label.scroll_active = false
	info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rv.add_child(info_label)
	unit_bar = ProgressBar.new()
	unit_bar.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
	unit_bar.show_percentage = false
	unit_bar.max_value = int(Net.options.get("unit_cap", Data.UNIT_CAP))
	unit_bar.custom_minimum_size = Vector2(22, 120)
	rh.add_child(unit_bar)

	# money plate above the bar
	plate = PanelContainer.new()
	plate.add_theme_stylebox_override("panel", _sb(Color(0.05, 0.08, 0.12, 0.97), Color(0.55, 0.70, 0.85), 3, 8, 8))
	root.add_child(plate)
	money_label = UI.label("$ 0", 30, Color(0.4, 1.0, 0.5))
	plate.add_child(money_label)

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


func _update_hud(dt: float) -> void:
	_update_ghost()
	_tips_tick()
	var vs: Vector2 = get_viewport().get_visible_rect().size
	plate.position = Vector2((vs.x - plate.size.x) * 0.5, vs.y - bottom_bar.size.y - plate.size.y + 6.0)
	fps_label.visible = Net.show_fps
	fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	fps_label.position = Vector2(vs.x * 0.5 - 30.0, 8.0)
	# event messages fade out
	var text: String = ""
	var i: int = msgs.size() - 1
	while i >= 0:
		msgs[i][1] -= dt
		if msgs[i][1] <= 0.0:
			msgs.remove_at(i)
		i -= 1
	for m in msgs:
		text += "[color=#%s]%s[/color]\n" % [m[2].to_html(false), m[0]]
	msg_label.text = text
	# selection summary and nation stats
	var light: int = 0
	var heavy: int = 0
	var farm: int = 0
	for id in selected:
		if info.has(id):
			match int(info[id][0]):
				1:
					light += 1
				2:
					heavy += 1
				3, 6:
					farm += 1
	sel_label.text = "" if selected.is_empty() else "Selected: %d   (%d light, %d heavy, %d workers)" % [selected.size(), light, heavy, farm]
	var units: int = 0
	var farmers: int = 0
	var oil: int = 0
	var cp_text: String = "0"
	if stats.size() >= 5 and my_slot >= 0 and my_slot < stats[3].size():
		var cpv: float = float(stats[3][my_slot])
		cp_text = "%.1f" % cpv
		for pi in power_tiles.size():
			var cd: float = float(stats[4][my_slot][pi])
			var sub: Label = power_tiles[pi].get_meta("sub")
			if cd > 0.0:
				sub.text = "ready in %ds" % ceili(cd)
			elif cpv < 1.0:
				sub.text = "needs 1 pt"
			else:
				sub.text = "1 pt  [%s]" % ["Z", "C", "V"][pi]
			power_tiles[pi].modulate = Color(1, 1, 1, 1.0 if (cd <= 0.0 and cpv >= 1.0) else 0.55)
	for id in info:
		var k: int = info[id][0]
		if info[id][1] != my_slot:
			continue
		if k == 4:
			oil += 1
		elif k == 3:
			farmers += 1
			units += 1
		elif k == 1 or k == 2:
			units += 1
	info_label.text = "Units  %d / %d\nFarmers  %d\n[color=#e3b341]Oil derricks  %d[/color]\n[color=#7dd3fc]Commander points  %s[/color]" % [units, int(Net.options.get("unit_cap", Data.UNIT_CAP)), farmers, oil, cp_text]
	unit_bar.value = units

	var has_builder: bool = not _selected_builders().is_empty()
	build_row.visible = has_builder or placing != -1
	power_row.visible = not build_row.visible
	var pw_text: String = ""
	if stats.size() >= 9 and my_slot >= 0 and my_slot < stats[5].size():
		var prod: int = int(stats[5][my_slot])
		var use: int = int(stats[6][my_slot])
		var low: bool = use > prod
		pw_text = "\n[color=%s]Power  %d / %d%s[/color]" % ["#ff6b5e" if low else "#9be564", use, prod, "   LOW POWER" if low else ""]
		var my_money: float = float(money[my_slot]) if my_slot < money.size() else 0.0
		for idx in train_buttons.size():
			var tb: Button = train_buttons[idx]
			var sub: Label = tb.get_meta("sub")
			var st2: Dictionary = Data.unit(Net.slots[my_slot]["country"], idx)
			var q: int = int(stats[7][my_slot][idx])
			var key: String = ["Q", "E", "R", "B"][idx]
			var locked: bool = idx == 1 and not _has_complete(10)
			if locked:
				sub.text = "needs Factory"
			elif q > 0:
				var frac: int = int(100.0 * float(stats[8][my_slot][idx]) / float(Data.TRAIN_TIME[idx]))
				sub.text = "x%d  %d%%" % [q, frac]
			else:
				sub.text = "$%d  [%s]" % [st2["cost"], key]
			tb.modulate = Color(1, 1, 1, 0.5 if (locked or my_money < float(st2["cost"])) else 1.0)
		var btypes: Array = [7, 8, 9, 10, 11, 12]
		for bi in build_tiles.size():
			var bd: Dictionary = Data.BUILD[btypes[bi]]
			var blocked: bool = (btypes[bi] == 10 and not _has_complete(9)) or (btypes[bi] == 12 and not _has_complete(10))
			build_tiles[bi].modulate = Color(1, 1, 1, 0.5 if (blocked or my_money < float(bd["cost"])) else 1.0)
	if stats.size() >= 12 and my_slot >= 0 and my_slot < stats[11].size() and super_tile != null:
		var my_m: float = float(money[my_slot]) if my_slot < money.size() else 0.0
		var scd: float = float(stats[11][my_slot])
		var ssub: Label = super_tile.get_meta("sub")
		if not _has_complete(12):
			ssub.text = "build it [T]"
		elif scd > 0.0:
			ssub.text = "ready in %ds" % ceili(scd)
		else:
			ssub.text = "[J] FIRE"
		super_tile.modulate = Color(1, 1, 1, 1.0 if (_has_complete(12) and scd <= 0.0) else 0.5)
		for ui in upg_tiles.size():
			var usub: Label = upg_tiles[ui].get_meta("sub")
			var ud: Dictionary = Data.UPGRADES[ui]
			var done: bool = bool(stats[9][my_slot][ui])
			var uprog: float = float(stats[10][my_slot][ui])
			var need_b: bool = ui < 2 and not _has_complete(9)
			if done:
				usub.text = "DONE"
			elif uprog >= 0.0:
				usub.text = "%d%%" % int(100.0 * uprog / float(ud["time"]))
			elif need_b:
				usub.text = "needs Barracks"
			else:
				usub.text = "$%d" % ud["cost"]
			upg_tiles[ui].modulate = Color(1, 1, 1, 0.5 if (done or need_b or uprog >= 0.0 or my_m < float(ud["cost"])) else 1.0)
	info_label.text += pw_text


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
	v.add_child(UI.settings_box(_apply_settings))
	var keys: Label = UI.label("Hotkeys:  Ctrl+1..9 set group,  1..9 select (twice = jump)  |  H base  |  X stop  |  Ctrl+right-click attack-move  |  double-click = all of that type  |  F army  |  G farmers  |  B builder  |  Y U I O P T build  |  J superweapon  |  K L M research", 13, Color("8b98a9"))
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	keys.custom_minimum_size = Vector2(300, 0)
	v.add_child(keys)
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
	if shake > 0.0:
		cam.h_offset = randf_range(-1.0, 1.0) * shake * 1.5
		cam.v_offset = randf_range(-1.0, 1.0) * shake * 1.5
		shake = maxf(0.0, shake - dt * 1.3)
		if shake == 0.0:
			cam.h_offset = 0.0
			cam.v_offset = 0.0

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
			elif kind_id == 3 and String(node.get_meta("work")) != "":
				want = String(node.get_meta("work"))
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
	_update_hud(dt)
	var oil_count: Dictionary = {}
	for oid in info:
		if info[oid][0] == 4 and info[oid][1] >= 0:
			oil_count[info[oid][1]] = int(oil_count.get(info[oid][1], 0)) + 1
	var lines: PackedStringArray = PackedStringArray()
	for i in Net.slots.size():
		var sl: Dictionary = Net.slots[i]
		if sl["type"] == "human" or sl["type"] == "bot":
			var n: String = str(sl["name"]) if str(sl["name"]) != "" else "Bot"
			var dead: bool = i < alive_arr.size() and not alive_arr[i]
			var col: String = Data.PLAYER_COLORS[i].to_html(false)
			var tag: String = ""
			if str(Net.options.get("teams", "ffa")) != "ffa":
				tag = " (%s)" % char(65 + int(sl.get("team", i)))
			var line: String = "[color=#%s]■[/color] %s%s  [color=#8b98a9]%s[/color]  [color=#e3b341]oil %d[/color]" % [col, n, tag, sl["country"], int(oil_count.get(i, 0))]
			if dead:
				line = "[s][color=#6b7280]%s  %s[/color][/s]  [color=#ff7b72]OUT[/color]" % [n, sl["country"]]
			lines.append(line)
	players_label.text = "\n".join(lines)
	status_label.text = ""
	_check_end()
	minimap.queue_redraw()

	if dragging:
		var m: Vector2 = get_viewport().get_mouse_position()
		if not moved and m.distance_to(drag_start) > 6.0:
			moved = true
		if moved and not box_mode and pan_anchor != null:
			var g = _ground_point(m)
			if g != null:
				cam_pivot.position += Vector3(pan_anchor.x - g.x, 0.0, pan_anchor.z - g.z)
				cam_pivot.position.x = clampf(cam_pivot.position.x, -150.0, 150.0)
				cam_pivot.position.z = clampf(cam_pivot.position.z, -150.0, 150.0)
		drag_rect.visible = moved and box_mode
		if drag_rect.visible:
			drag_rect.position = Vector2(minf(drag_start.x, m.x), minf(drag_start.y, m.y))
			drag_rect.size = (m - drag_start).abs()
		Input.set_default_cursor_shape(Input.CURSOR_DRAG if (moved and not box_mode) else Input.CURSOR_ARROW)
	elif rdragging:
		var mr: Vector2 = get_viewport().get_mouse_position()
		drag_rect.visible = rstart.distance_to(mr) > 6.0
		drag_rect.position = Vector2(minf(rstart.x, mr.x), minf(rstart.y, mr.y))
		drag_rect.size = (mr - rstart).abs()
	else:
		drag_rect.visible = false


func _physics_process(dt: float) -> void:
	if sim == null or not running:
		return
	if Net.offline and pause_layer.visible:
		return # single-player: the pause menu really pauses the game
	sim.step(dt * float(Net.options.get("speed", 1.0)))
	snap_timer += dt
	if snap_timer >= 1.0 / SNAP_HZ:
		snap_timer = 0.0
		var snap: PackedFloat32Array = sim.snapshot()
		var shots: PackedFloat32Array = sim.shots
		sim.shots = PackedFloat32Array()
		var mp: PackedFloat32Array = sim.money_packed()
		var st: Array = sim.stats()
		var fxp: PackedFloat32Array = sim.fx
		sim.fx = PackedFloat32Array()
		on_snapshot.rpc(snap, shots, mp, sim.alive, sim.status, st, fxp)
		on_snapshot(snap, shots, mp, sim.alive, sim.status, st, fxp)


@rpc("authority", "unreliable_ordered")
func on_snapshot(snap: PackedFloat32Array, shots: PackedFloat32Array, money_p: PackedFloat32Array, alive_p: Array, status: String, stats_p: Array, fx_p: PackedFloat32Array) -> void:
	var now_s: float = Time.get_ticks_msec() / 1000.0
	if my_slot >= 0 and my_slot < money_p.size() and my_slot < money.size():
		if money_p[my_slot] - money[my_slot] >= 30.0 and now_s - last_coin > 0.35:
			last_coin = now_s
			_play_ui("coin", -12.0)
	money = money_p
	alive_arr = alive_p
	status_text = status
	stats = stats_p
	var seen: Dictionary = {}
	var n: int = floori(snap.size() / 7.0)
	for k in n:
		var o: int = k * 7
		var id: int = int(snap[o])
		var kind: int = int(snap[o + 1])
		var owner: int = int(snap[o + 2])
		var p: Vector3 = Vector3(snap[o + 3], 0.0, snap[o + 4])
		var frac: float = snap[o + 5]
		var rank: int = int(snap[o + 6])
		seen[id] = true
		if not views.has(id):
			_make_view(id, kind, owner)
			views[id].position = p
			if owner == my_slot and kind >= 1 and kind <= 3 and now_s - t0 > 3.0 and now_s - last_ready > 0.2:
				last_ready = now_s
				_play_ui("ready", -10.0)
		targets[id] = p
		if kind == 0 and owner == my_slot and info.has(id) and frac < float(info[id][2]) - 0.001:
			var now: float = Time.get_ticks_msec() / 1000.0
			if now - last_alert > 10.0 and msg_label != null:
				last_alert = now
				_msg("Your base is under attack!", Color(1.0, 0.4, 0.35))
				_play_ui("alarm", -4.0)
		info[id] = [kind, owner, frac, rank]
		if int(views[id].get_meta("owner", -99)) != owner:
			_set_owner(id, owner)
		_update_hp(id, kind, frac)
		_update_rank(id, rank)
	for id in views.keys():
		if not seen.has(id):
			var kd: int = info[id][0]
			var bpos: Vector3 = views[id].position + Vector3(0, 1.5, 0)
			if kd == 5:
				_msg("A money field has run dry", Color(0.8, 0.8, 0.8))
				_burst(bpos, 12, 0.6, 0.2, Color(1.0, 0.85, 0.2), 5.0, Vector3(0, -9, 0))
			elif kd == 0:
				_play3d("boom", bpos, 4.0)
				_burst(bpos, 60, 1.0, 0.6, Color(1.0, 0.45, 0.1), 14.0, Vector3(0, -8, 0))
			elif kd == 2 or kd >= 7:
				_play3d("boom", bpos, -4.0)
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
	_handle_fx(fx_p)


func _make_view(id: int, kind: int, owner: int) -> void:
	var root: Node3D = Node3D.new()
	add_child(root)
	var pivot: Node3D = Node3D.new()
	pivot.name = "pivot"
	root.add_child(pivot)

	var country: String = Net.slots[owner]["country"] if owner >= 0 else ""
	var col: Color = Data.PLAYER_COLORS[owner] if owner >= 0 else Color(0.6, 0.6, 0.6)
	var bar_w: float = 3.0
	var bar_y: float = 5.2
	var ring_r: float = 2.7
	var disc_r: float = 1.9
	var model_path: String = ""
	var by_h: bool = true
	var size: float = 2.4
	if kind == 0:
		model_path = Data.VISUALS[country]["hq"]
		by_h = false
		size = 15.0
		bar_w = 11.0
		bar_y = 11.0
		ring_r = 10.0
		disc_r = 10.0
	elif kind == 3:
		model_path = Data.FARMER_VISUAL[0]
		by_h = Data.FARMER_VISUAL[1]
		size = Data.FARMER_VISUAL[2]
	elif kind == 4:
		bar_w = 6.0
		bar_y = 11.5
		disc_r = 5.0
	elif kind == 5:
		bar_w = 5.0
		bar_y = 5.0
		disc_r = 0.1
	elif kind == 6:
		model_path = Data.BUILDER_VISUAL[0]
		by_h = Data.BUILDER_VISUAL[1]
		size = Data.BUILDER_VISUAL[2]
	elif kind >= 7:
		var br: float = float(Data.BUILD[kind]["radius"])
		if Data.BUILD_VISUAL.has(kind):
			var bv2: Array = Data.BUILD_VISUAL[kind]
			model_path = bv2[0]
			by_h = bv2[1]
			size = bv2[2]
		bar_w = br * 1.7
		bar_y = 10.0
		ring_r = br + 1.8
		disc_r = br + 1.5
	else:
		var v: Array = Data.VISUALS[country]["units"][kind - 1]
		model_path = v[0]
		by_h = v[1]
		size = v[2]
		if not by_h:
			bar_w = 4.8
			bar_y = 5.2
			ring_r = 4.6
			disc_r = 3.9

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
	disc.visible = kind != 5
	pivot.add_child(disc)
	root.set_meta("disc", dmat)
	root.set_meta("owner", owner)

	if kind == 4 or kind == 5:
		_static_visual(pivot, kind)
	elif kind == 11:
		_turret_visual(pivot)
	else:
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

func _set_owner(id: int, owner: int) -> void:
	var v: Node3D = views[id]
	var prev: int = int(v.get_meta("owner", -1))
	if info.has(id) and info[id][0] == 4 and msg_label != null:
		if owner == my_slot:
			_msg("Oil derrick captured", Color(0.5, 1.0, 0.5))
			_play_ui("capture", -6.0)
		elif prev == my_slot:
			_msg("Oil derrick lost!", Color(1.0, 0.45, 0.4))
			_play_ui("alarm", -8.0)
		elif owner >= 0:
			_msg("%s captured an oil derrick" % str(Net.slots[owner]["country"]), Color(1.0, 0.85, 0.3))
	v.set_meta("owner", owner)
	var mat: StandardMaterial3D = v.get_meta("disc")
	mat.albedo_color = Data.PLAYER_COLORS[owner] if owner >= 0 else Color(0.6, 0.6, 0.6)


func _label3d(text: String, col: Color, y: float, px: float) -> Label3D:
	var l: Label3D = Label3D.new()
	l.text = text
	l.font_size = 96
	l.pixel_size = px
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.modulate = col
	l.outline_size = 16
	l.outline_modulate = Color(0, 0, 0)
	l.no_depth_test = true
	l.position.y = y
	return l


func _turret_visual(pivot: Node3D) -> void:
	var steel: StandardMaterial3D = StandardMaterial3D.new()
	steel.albedo_color = Color(0.32, 0.36, 0.42)
	steel.metallic = 0.5
	steel.roughness = 0.5
	var base: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 2.0
	cyl.bottom_radius = 2.5
	cyl.height = 1.4
	base.mesh = cyl
	base.material_override = steel
	base.position.y = 0.7
	pivot.add_child(base)
	var dome: MeshInstance3D = MeshInstance3D.new()
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 1.5
	sm.height = 2.4
	dome.mesh = sm
	dome.material_override = steel
	dome.position.y = 1.9
	pivot.add_child(dome)
	var barrel: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = Vector3(0.6, 0.6, 4.6)
	barrel.mesh = bm
	barrel.material_override = steel
	barrel.position = Vector3(0, 2.1, 2.6)
	pivot.add_child(barrel)


func _static_visual(pivot: Node3D, kind: int) -> void:
	if kind == 5:
		# pile of gold bars + floating $
		var gold: StandardMaterial3D = StandardMaterial3D.new()
		gold.albedo_color = Color(1.0, 0.78, 0.15)
		gold.metallic = 0.6
		gold.roughness = 0.35
		var offs: Array = [Vector3(0, 0, 0), Vector3(1.7, 0, 1.0), Vector3(-1.6, 0, 0.9), Vector3(0.3, 0, -1.8), Vector3(0.2, 0.9, 0.1)]
		for k in offs.size():
			var bx: MeshInstance3D = MeshInstance3D.new()
			var bm: BoxMesh = BoxMesh.new()
			bm.size = Vector3(2.4, 0.9, 1.6)
			bx.mesh = bm
			bx.material_override = gold
			bx.position = offs[k] + Vector3(0, 0.45, 0)
			bx.rotation.y = 0.6 * k
			pivot.add_child(bx)
		pivot.add_child(_label3d("$", Color(0.3, 1.0, 0.4), 5.0, 0.05))
	else:
		# oil derrick: dark base, tower, crossbar, barrels and an OIL tag
		var steel: StandardMaterial3D = StandardMaterial3D.new()
		steel.albedo_color = Color(0.12, 0.12, 0.14)
		var base: MeshInstance3D = MeshInstance3D.new()
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = 3.2
		cyl.bottom_radius = 3.6
		cyl.height = 0.8
		base.mesh = cyl
		base.material_override = steel
		base.position.y = 0.4
		pivot.add_child(base)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var leg: MeshInstance3D = MeshInstance3D.new()
				var lm: BoxMesh = BoxMesh.new()
				lm.size = Vector3(0.35, 9.0, 0.35)
				leg.mesh = lm
				leg.material_override = steel
				leg.position = Vector3(sx * 1.1, 4.5, sz * 1.1)
				leg.rotation = Vector3(sz * -0.06, 0.0, sx * 0.06)
				pivot.add_child(leg)
		var bar: MeshInstance3D = MeshInstance3D.new()
		var bm2: BoxMesh = BoxMesh.new()
		bm2.size = Vector3(6.0, 0.5, 0.5)
		bar.mesh = bm2
		bar.material_override = steel
		bar.position.y = 8.2
		bar.rotation.y = 0.5
		pivot.add_child(bar)
		for k in 3:
			var holder: Node3D = Node3D.new()
			holder.position = Vector3(3.4 * cos(k * 2.1 + 0.6), 0.0, 3.4 * sin(k * 2.1 + 0.6))
			pivot.add_child(holder)
			var res = load("res://assets/props/oil_pump.glb")
			if res != null:
				var inst: Node3D = res.instantiate()
				holder.add_child(inst)
				_fit(inst, 1.8, false)
		pivot.add_child(_label3d("OIL", Color(1.0, 0.85, 0.1), 11.0, 0.045))



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
	var work: String = ""
	for n in ap.get_animation_list():
		var low: String = String(n).to_lower()
		if idle == "" and low.ends_with("idle"):
			idle = String(n)
		if run == "" and (low.ends_with("|run") or low.ends_with("tank_forward")):
			run = String(n)
		if shoot == "" and (low.ends_with("idle_gun_shoot") or low.ends_with("idle_shoot")):
			shoot = String(n)
		if work == "" and low.ends_with("interact"):
			work = String(n)
	for nm in [idle, run, shoot, work]:
		if nm != "":
			ap.get_animation(nm).loop_mode = Animation.LOOP_LINEAR
	root.set_meta("ap", ap)
	root.set_meta("idle", idle)
	root.set_meta("run", run)
	root.set_meta("shoot", shoot)
	root.set_meta("shoot_t", 0.0)
	root.set_meta("work", work)
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
	while placed < (50 if Net.low_fx else 100) and attempts < 800:
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
		for mp in Data.MONEY_NODES:
			if p.distance_to(mp) < 16.0:
				blocked = true
		for op in Data.OIL_NODES:
			if p.distance_to(op) < 16.0:
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
	if _kind == 4:
		bar.visible = frac > 0.07 # capture progress
	else:
		bar.visible = frac < 0.999 or Net.always_bars or (info.has(id) and int(info[id][3]) == 9)
	bar.scale.x = maxf(frac, 0.01)


func _play3d(kind: String, pos: Vector3, vol: float = 0.0) -> void:
	if get_tree().get_nodes_in_group("sfx").size() > (14 if Net.low_fx else 28):
		return
	var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	p.add_to_group("sfx")
	p.stream = Net.sfx(kind)
	p.volume_db = vol
	p.unit_size = 70.0
	p.max_distance = 420.0
	p.position = pos
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _play_ui(kind: String, vol: float = -6.0) -> void:
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.stream = Net.sfx(kind)
	p.volume_db = vol
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _apply_settings() -> void:
	if sun != null:
		sun.shadow_enabled = Net.shadows


func _group_key(n: int, assign: bool) -> void:
	if assign:
		if selected.is_empty():
			return
		groups[n] = selected.keys()
		_msg("Group %d set (%d units)" % [n, selected.size()], Color(0.7, 0.85, 1.0))
		return
	if not groups.has(n):
		return
	selected.clear()
	var sum: Vector3 = Vector3.ZERO
	var cnt: int = 0
	for id in groups[n]:
		if info.has(id):
			selected[id] = true
			sum += targets[id]
			cnt += 1
	var now_g: float = Time.get_ticks_msec() / 1000.0
	if cnt > 0 and now_g - float(group_tap.get(n, -9.0)) < 0.4:
		cam_pivot.position = Vector3(sum.x / cnt, 0.0, sum.z / cnt)
	group_tap[n] = now_g


func _center_on_hq() -> void:
	for id in info:
		if info[id][0] == 0 and info[id][1] == my_slot:
			cam_pivot.position = Vector3(targets[id].x, 0.0, targets[id].z)
			return


func _stop_selected() -> void:
	if selected.is_empty() or my_slot < 0:
		return
	var ids: Array = selected.keys()
	if multiplayer.is_server():
		if sim != null:
			sim.cmd_stop(my_slot, ids)
	else:
		srv_stop.rpc_id(1, ids)


@rpc("any_peer", "reliable")
func srv_stop(ids: Array) -> void:
	if not multiplayer.is_server() or sim == null or ids.size() > 200:
		return
	var slot: int = _slot_of(multiplayer.get_remote_sender_id())
	if slot >= 0:
		sim.cmd_stop(slot, ids)


func _check_end() -> void:
	if my_slot < 0 or alive_arr.size() <= my_slot:
		return
	var me_alive: bool = alive_arr[my_slot]
	if status_text != "" and not final_shown:
		final_shown = true
		elim_shown = true
		var title: String = "DRAW"
		if status_text.begins_with("WINNER"):
			title = "VICTORY" if me_alive else "DEFEAT"
		_show_end(title, true)
	elif status_text == "" and not me_alive and not elim_shown:
		elim_shown = true
		_show_end("DEFEAT", false)


func _show_end(title: String, final: bool) -> void:
	if end_layer != null:
		end_layer.queue_free()
	end_layer = CanvasLayer.new()
	end_layer.layer = 9
	add_child(end_layer)
	var root: Control = Control.new()
	root.theme = UI.make_theme()
	end_layer.add_child(root)
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

	var tcol: Color = UI.ACCENT if title == "VICTORY" else (Color(1.0, 0.4, 0.35) if title == "DEFEAT" else Color(0.8, 0.8, 0.8))
	var t: Label = UI.label(title, 72, tcol)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var secs: int = int(Time.get_ticks_msec() / 1000.0 - t0)
	var sub: Label = UI.label(("Match time %d:%02d" % [secs / 60, secs % 60]) + ("" if final else "   -   you have been eliminated, the match goes on"), 16, Color("8b98a9"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)

	if Net.challenge.get("active", false):
		var cs: int = int(Net.challenge["stage"])
		var cl: Label = UI.label("CHALLENGE  -  STAGE %d of %d  -  %s" % [cs + 1, Data.CHALLENGE.size(), str(Data.CHALLENGE[cs]["title"]).to_upper()], 17, UI.ACCENT)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(cl)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	for h in ["Commander", "Nation", "Kills", "Lost", "Earned"]:
		grid.add_child(UI.label(h, 16, Color("8b98a9")))
	var order: Array = []
	for i in Net.slots.size():
		if Net.slots[i]["type"] == "human" or Net.slots[i]["type"] == "bot":
			order.append(i)
	if stats.size() >= 3:
		order.sort_custom(func(a: int, b: int): return stats[0][a] > stats[0][b])
	for i in order:
		var nm: String = str(Net.slots[i]["name"]) if str(Net.slots[i]["name"]) != "" else "Bot"
		var out: bool = i < alive_arr.size() and not alive_arr[i]
		var col: Color = Data.PLAYER_COLORS[i] if not out else Color("6b7280")
		var k_: String = str(stats[0][i]) if stats.size() >= 3 else "-"
		var l_: String = str(stats[1][i]) if stats.size() >= 3 else "-"
		var e_: String = "$" + str(stats[2][i]) if stats.size() >= 3 else "-"
		grid.add_child(UI.label(nm + ("  (you)" if i == my_slot else ""), 18, col))
		grid.add_child(UI.label(str(Net.slots[i]["country"]), 18, col))
		grid.add_child(UI.label(k_, 18, col))
		grid.add_child(UI.label(l_, 18, col))
		grid.add_child(UI.label(e_, 18, col))

	var bar: HBoxContainer = HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 16)
	v.add_child(bar)
	if final and Net.challenge.get("active", false):
		var cst: int = int(Net.challenge["stage"])
		if title == "VICTORY":
			Net.challenge_complete(cst)
			if cst + 1 < Data.CHALLENGE.size():
				var nxt: Button = Button.new()
				nxt.text = "NEXT STAGE"
				nxt.custom_minimum_size = Vector2(240, 50)
				nxt.pressed.connect(_challenge_go.bind(cst + 1))
				bar.add_child(nxt)
			else:
				v.add_child(UI.label("You have completed the whole Challenge!", 20, UI.ACCENT))
		else:
			var retry: Button = Button.new()
			retry.text = "RETRY STAGE"
			retry.custom_minimum_size = Vector2(240, 50)
			retry.pressed.connect(_challenge_go.bind(cst))
			bar.add_child(retry)
	if not final:
		var keep: Button = Button.new()
		keep.text = "KEEP WATCHING"
		keep.custom_minimum_size = Vector2(240, 50)
		keep.pressed.connect(func(): end_layer.visible = false)
		bar.add_child(keep)
	var leave: Button = Button.new()
	leave.text = "RETURN TO MENU"
	leave.custom_minimum_size = Vector2(240, 50)
	leave.pressed.connect(_leave)
	bar.add_child(leave)


func _selected_builders() -> Array:
	var out: Array = []
	for id in selected:
		if info.has(id) and info[id][0] == 6 and info[id][1] == my_slot:
			out.append(id)
	return out


func _has_complete(kind: int) -> bool:
	for id in info:
		if info[id][0] == kind and info[id][1] == my_slot and int(info[id][3]) != 9:
			return true
	return false


func _own_hq_pos() -> Vector3:
	for id in info:
		if info[id][0] == 0 and info[id][1] == my_slot:
			return targets[id]
	return Vector3.ZERO


func _spot_ok_client(pos: Vector3, r: float) -> bool:
	if absf(pos.x) > 140.0 or absf(pos.z) > 140.0:
		return false
	var hq: Vector3 = _own_hq_pos()
	if Vector2(pos.x - hq.x, pos.z - hq.z).length() > Sim.BASE_ZONE:
		return false
	for id in info:
		var k: int = info[id][0]
		var d: float = Vector2(pos.x - targets[id].x, pos.z - targets[id].z).length()
		if k == 4:
			if d < r + 4.0 + 4.0:
				return false
		elif k == 5:
			if d < r + 2.5 + 4.0:
				return false
		elif k == 0 or k >= 7:
			var rad: float = 7.5 if k == 0 else float(Data.BUILD[k]["radius"])
			if d < r + rad + 1.5:
				return false
	return true


func _build_key(btype: int) -> void:
	if my_slot < 0 or stats.size() < 9:
		return
	if _selected_builders().is_empty():
		_msg("Select a builder first", Color(1.0, 0.8, 0.4))
		return
	var def: Dictionary = Data.BUILD[btype]
	if money.size() > my_slot and float(money[my_slot]) < float(def["cost"]):
		_msg("Not enough money for a %s" % def["name"], Color(1.0, 0.6, 0.4))
		return
	if btype == 10 and not _has_complete(9):
		_msg("The War Factory needs a Barracks first", Color(1.0, 0.8, 0.4))
		return
	if btype == 12 and not _has_complete(10):
		_msg("The Superweapon needs a War Factory first", Color(1.0, 0.8, 0.4))
		return
	_cancel_placing()
	placing = btype
	ghost = MeshInstance3D.new()
	var cm: CylinderMesh = CylinderMesh.new()
	cm.top_radius = float(def["radius"])
	cm.bottom_radius = float(def["radius"])
	cm.height = 0.3
	ghost.mesh = cm
	ghost_mat = _fx_material(Color(0.3, 1.0, 0.4, 0.45))
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost.material_override = ghost_mat
	add_child(ghost)
	_msg("Click to place the %s   (Shift = place several, Esc cancels)" % def["name"], Color(0.7, 0.9, 1.0))


func _cancel_placing() -> void:
	placing = -1
	if ghost != null:
		ghost.queue_free()
		ghost = null


func _update_ghost() -> void:
	if placing == -1 or ghost == null:
		return
	var g = _ground_point(get_viewport().get_mouse_position())
	if g == null:
		return
	ghost.position = Vector3(g.x, 0.25, g.z)
	var ok: bool = _spot_ok_client(g, float(Data.BUILD[placing]["radius"]))
	ghost_mat.albedo_color = Color(0.3, 1.0, 0.4, 0.45) if ok else Color(1.0, 0.25, 0.2, 0.45)


func _cast_build(btype: int, pos: Vector3) -> bool:
	var ids: Array = _selected_builders()
	if ids.is_empty():
		return false
	if multiplayer.is_server():
		return sim != null and sim.cmd_build(my_slot, ids, btype, pos)
	srv_build.rpc_id(1, ids, btype, pos)
	return true


func _upgrade_key(idx: int) -> void:
	if my_slot < 0:
		return
	if multiplayer.is_server():
		if sim != null and not sim.cmd_upgrade(my_slot, idx):
			_msg("Can't research that right now", Color(1.0, 0.8, 0.4))
	else:
		srv_upgrade.rpc_id(1, idx)


@rpc("any_peer", "reliable")
func srv_upgrade(idx: int) -> void:
	if not multiplayer.is_server() or sim == null:
		return
	var slot: int = _slot_of(multiplayer.get_remote_sender_id())
	if slot >= 0:
		sim.cmd_upgrade(slot, idx)


## Right-click on the minimap: send the selected units there (Ctrl = attack-move).
func minimap_order(pos: Vector3) -> void:
	if selected.is_empty() or my_slot < 0:
		return
	var ids: Array = selected.keys()
	if ids.size() > 200:
		ids = ids.slice(0, 200)
	var amove: bool = Input.is_key_pressed(KEY_CTRL)
	if multiplayer.is_server():
		if sim != null:
			sim.cmd_move(my_slot, ids, pos, amove)
	else:
		srv_move.rpc_id(1, ids, pos, amove)


func _cast_assist(bid: int) -> void:
	var ids: Array = _selected_builders()
	if multiplayer.is_server():
		if sim != null:
			sim.cmd_assist(my_slot, ids, bid)
	else:
		srv_assist.rpc_id(1, ids, bid)


@rpc("any_peer", "reliable")
func srv_build(ids: Array, btype: int, pos: Vector3) -> void:
	if not multiplayer.is_server() or sim == null or ids.size() > 50:
		return
	var slot: int = _slot_of(multiplayer.get_remote_sender_id())
	if slot >= 0:
		sim.cmd_build(slot, ids, btype, pos)


@rpc("any_peer", "reliable")
func srv_assist(ids: Array, bid: int) -> void:
	if not multiplayer.is_server() or sim == null or ids.size() > 50:
		return
	var slot: int = _slot_of(multiplayer.get_remote_sender_id())
	if slot >= 0:
		sim.cmd_assist(slot, ids, bid)


func _power_ready(idx: int) -> bool:
	if my_slot < 0 or stats.size() < 5 or my_slot >= stats[3].size():
		return false
	if idx == 3:
		return stats.size() >= 12 and _has_complete(12) and float(stats[11][my_slot]) <= 0.0
	return float(stats[3][my_slot]) >= 1.0 and float(stats[4][my_slot][idx]) <= 0.0


func _power_key(idx: int) -> void:
	if idx == 3 and not _has_complete(12):
		_msg("Build a Superweapon first (select a builder, then T)", Color(1.0, 0.8, 0.4))
		return
	if not _power_ready(idx):
		_msg("That power is not ready yet", Color(1.0, 0.8, 0.4))
		return
	if idx == 0 or idx == 3:
		targeting = idx
		Input.set_default_cursor_shape(Input.CURSOR_CROSS)
		_msg("Click the map to fire the superweapon  (Esc cancels)" if idx == 3 else "Click the map to call in the strike  (Esc cancels)", Color(1.0, 0.85, 0.4))
	else:
		_cast_power(idx, Vector3.ZERO)


func _cast_power(idx: int, pos: Vector3) -> void:
	if multiplayer.is_server():
		if sim != null:
			sim.cmd_power(my_slot, idx, pos)
	else:
		srv_power.rpc_id(1, idx, pos)


@rpc("any_peer", "reliable")
func srv_power(idx: int, pos: Vector3) -> void:
	if not multiplayer.is_server() or sim == null:
		return
	var slot: int = _slot_of(multiplayer.get_remote_sender_id())
	if slot >= 0:
		sim.cmd_power(slot, idx, pos)


func _update_rank(id: int, rank: int) -> void:
	var v: Node3D = views[id]
	var prev: int = int(v.get_meta("rank", 0))
	if rank == 9: # still under construction: the building rises with its progress
		var prog: float = float(info[id][2]) if info.has(id) else 0.5
		v.get_node("pivot").scale = Vector3(1.0, clampf(0.2 + 0.8 * prog, 0.2, 1.0), 1.0)
		v.set_meta("rank", 9)
		return
	if prev == 9:
		v.get_node("pivot").scale = Vector3.ONE
		v.set_meta("rank", 0)
		prev = 0
	if prev == rank:
		return
	v.set_meta("rank", rank)
	var old: Node = v.get_node_or_null("rank")
	if old != null:
		old.name = "rank_old"
		old.queue_free()
	if rank > 0:
		var l: Label3D = _label3d("^".repeat(rank), Color(1.0, 0.85, 0.2), 0.0, 0.07)
		l.name = "rank"
		l.position.y = float(v.get_node("hp").position.y) + 1.1
		v.add_child(l)


func _handle_fx(fx_p: PackedFloat32Array) -> void:
	var n: int = floori(fx_p.size() / 3.0)
	for k in n:
		var t: int = int(fx_p[k * 3])
		var pos: Vector3 = Vector3(fx_p[k * 3 + 1], 0.0, fx_p[k * 3 + 2])
		if t == 1: # incoming strike: red warning ring
			var ring: MeshInstance3D = MeshInstance3D.new()
			var cm: CylinderMesh = CylinderMesh.new()
			cm.top_radius = 16.0
			cm.bottom_radius = 16.0
			cm.height = 0.12
			ring.mesh = cm
			var mat: StandardMaterial3D = _fx_material(Color(1.0, 0.2, 0.15, 0.35))
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ring.material_override = mat
			ring.position = pos + Vector3(0, 0.3, 0)
			add_child(ring)
			get_tree().create_timer(2.5).timeout.connect(ring.queue_free)
			_play3d("alarm", pos, -8.0)
		elif t == 2: # strike lands
			_play3d("boom", pos, 4.0)
			_burst(pos + Vector3(0, 1, 0), 80, 1.1, 0.8, Color(1.0, 0.5, 0.12), 20.0, Vector3(0, -9, 0))
			_burst(pos + Vector3(0, 2, 0), 40, 1.4, 1.2, Color(0.25, 0.22, 0.2), 9.0, Vector3(0, 1, 0))
		elif t == 3: # promotion sparkle
			_burst(pos + Vector3(0, 3, 0), 10, 0.6, 0.2, Color(1.0, 0.9, 0.3), 5.0, Vector3(0, -2, 0))
		elif t == 5: # superweapon incoming: big warning ring
			var bring: MeshInstance3D = MeshInstance3D.new()
			var bcm: CylinderMesh = CylinderMesh.new()
			bcm.top_radius = Data.SUPER_RADIUS
			bcm.bottom_radius = Data.SUPER_RADIUS
			bcm.height = 0.12
			bring.mesh = bcm
			var bmat: StandardMaterial3D = _fx_material(Color(1.0, 0.15, 0.1, 0.3))
			bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			bring.material_override = bmat
			bring.position = pos + Vector3(0, 0.3, 0)
			add_child(bring)
			get_tree().create_timer(Data.SUPER_DELAY).timeout.connect(bring.queue_free)
			_msg("A superweapon has been launched!", Color(1.0, 0.4, 0.3))
			_play_ui("alarm", -2.0)
		elif t == 6: # superweapon impact
			_play3d("boom", pos, 10.0)
			_burst(pos + Vector3(0, 1, 0), 160, 1.6, 1.2, Color(1.0, 0.55, 0.15), 30.0, Vector3(0, -8, 0))
			_burst(pos + Vector3(0, 3, 0), 80, 2.2, 2.0, Color(0.3, 0.27, 0.25), 14.0, Vector3(0, 2, 0))
			shake = 0.9
		elif t == 7: # research finished
			_burst(pos + Vector3(0, 6, 0), 40, 1.0, 0.3, Color(0.5, 0.9, 1.0), 10.0, Vector3(0, -3, 0))
			if _own_hq_pos().distance_to(pos) < 1.0:
				_msg("Research complete", Color(0.6, 0.9, 1.0))
				_play_ui("capture", -8.0)
		elif t == 4: # construction finished
			_burst(pos + Vector3(0, 4, 0), 30, 0.8, 0.35, Color(0.6, 0.9, 1.0), 9.0, Vector3(0, -6, 0))
			_play3d("ready", pos, -2.0)


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
	if dv.length() >= 0.5:
		_play3d("cannon" if kind == 2 else "shot", from, -2.0 if kind == 2 else -9.0)
	if projectiles.size() >= (30 if Net.low_fx else 60) or dv.length() < 0.5:
		return
	var heavy: bool = kind == 2
	var a: Vector3 = Vector3(from.x, 2.3 if heavy else 1.5, from.z)
	var b: Vector3 = Vector3(to.x, 1.4, to.z)
	var node: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = Vector3(0.45, 0.45, 3.0) if heavy else Vector3(0.18, 0.18, 2.2)
	node.mesh = bm
	node.material_override = _fx_material(Color(1.0, 0.65, 0.15) if heavy else Color(1.0, 0.95, 0.5))
	add_child(node)
	node.position = a
	node.look_at(b)
	projectiles.append({"n": node, "a": a, "b": b, "t": 0.0, "d": maxf(0.04, a.distance_to(b) / (40.0 if heavy else 85.0)), "heavy": heavy})
	_burst(a, 8 if heavy else 5, 0.14, 0.5 if heavy else 0.28, Color(1.0, 0.9, 0.35), 4.0, Vector3.ZERO)


func _burst(pos: Vector3, amount: int, life: float, size: float, col: Color, vel: float, grav: Vector3) -> void:
	if get_tree().get_nodes_in_group("fx").size() > (25 if Net.low_fx else 50):
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
			_burst(p["b"], 18 if heavy else 8, 0.45, 0.4 if heavy else 0.22, Color(1.0, 0.5, 0.12), 7.0 if heavy else 4.0, Vector3(0, -12, 0))
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
	if Net.edge_pan and Rect2(Vector2.ZERO, sz).has_point(m):
		if m.x <= 4.0:
			dir.x -= 1.0
		if m.x >= sz.x - 4.0:
			dir.x += 1.0
		if m.y <= 4.0:
			dir.y -= 1.0
		if m.y >= sz.y - 4.0:
			dir.y += 1.0
	cam_pivot.position += Vector3(dir.x, 0, dir.y) * zoom * 1.2 * dt * Net.cam_speed
	cam_pivot.position.x = clampf(cam_pivot.position.x, -150.0, 150.0)
	cam_pivot.position.z = clampf(cam_pivot.position.z, -150.0, 150.0)


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
				if not moved and placing != -1:
					var pg = _ground_point(ev.position)
					if pg != null and _spot_ok_client(pg, float(Data.BUILD[placing]["radius"])):
						_cast_build(placing, pg)
						if not Input.is_key_pressed(KEY_SHIFT):
							_cancel_placing()
					else:
						_msg("You can't build there", Color(1.0, 0.5, 0.4))
				elif not moved and targeting != -1:
					var tg = _ground_point(ev.position)
					if tg != null:
						_cast_power(targeting, tg)
					targeting = -1
					Input.set_default_cursor_shape(Input.CURSOR_ARROW)
				elif not moved or box_mode:
					_finish_drag(ev.position)
		elif ev.button_index == MOUSE_BUTTON_RIGHT:
			if ev.pressed:
				rdragging = true
				rstart = ev.position
			elif rdragging:
				rdragging = false
				if rstart.distance_to(ev.position) > 6.0:
					_box_select(rstart, ev.position)
				else:
					_right_click(ev.position)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
			zoom = clampf(zoom - 6.0 * Net.zoom_speed, 20.0, 140.0)
			_update_cam()
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
			zoom = clampf(zoom + 6.0 * Net.zoom_speed, 20.0, 140.0)
			_update_cam()
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.keycode == KEY_Q:
			_train(0)
		elif ev.keycode == KEY_E:
			_train(1)
		elif ev.keycode == KEY_F:
			selected.clear()
			for id in info:
				if info[id][1] == my_slot and (info[id][0] == 1 or info[id][0] == 2):
					selected[id] = true
		elif ev.keycode == KEY_R:
			_train(2)
		elif ev.keycode == KEY_G:
			_select_kinds([3])
		elif ev.keycode >= KEY_1 and ev.keycode <= KEY_9:
			_group_key(ev.keycode - KEY_0, ev.ctrl_pressed)
		elif ev.keycode == KEY_H or ev.keycode == KEY_HOME:
			_center_on_hq()
		elif ev.keycode == KEY_X:
			_stop_selected()
		elif ev.keycode == KEY_Z:
			_power_key(0)
		elif ev.keycode == KEY_C:
			_power_key(1)
		elif ev.keycode == KEY_V:
			_power_key(2)
		elif ev.keycode == KEY_B:
			_train(3)
		elif ev.keycode == KEY_Y:
			_build_key(7)
		elif ev.keycode == KEY_U:
			_build_key(8)
		elif ev.keycode == KEY_I:
			_build_key(9)
		elif ev.keycode == KEY_O:
			_build_key(10)
		elif ev.keycode == KEY_P:
			_build_key(11)
		elif ev.keycode == KEY_T:
			_build_key(12)
		elif ev.keycode == KEY_J:
			_power_key(3)
		elif ev.keycode == KEY_K:
			_upgrade_key(0)
		elif ev.keycode == KEY_L:
			_upgrade_key(1)
		elif ev.keycode == KEY_M:
			_upgrade_key(2)
		elif ev.keycode == KEY_ESCAPE:
			if placing != -1:
				_cancel_placing()
			elif targeting != -1:
				targeting = -1
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
			else:
				pause_layer.visible = not pause_layer.visible


func _is_enemy(owner: int) -> bool:
	if owner < 0 or my_slot < 0 or owner >= Net.slots.size():
		return false
	return int(Net.slots[owner].get("team", owner)) != int(Net.slots[my_slot].get("team", my_slot))


func _is_unit(k: int) -> bool:
	return Sim.is_unit_kind(k)


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
			if info[id][1] == my_slot and _is_unit(info[id][0]):
				var d: float = Vector2(targets[id].x - g.x, targets[id].z - g.z).length()
				if d < best_d:
					best_d = d
					best = id
		if best != -1:
			selected[best] = true
		var now_c: float = Time.get_ticks_msec() / 1000.0
		if best != -1 and now_c - last_click_t < 0.35 and last_click_kind == int(info[best][0]):
			var vr: Rect2 = get_viewport().get_visible_rect()
			for id2 in info:
				if info[id2][1] == my_slot and info[id2][0] == info[best][0]:
					if vr.has_point(cam.unproject_position(views[id2].position)):
						selected[id2] = true
		last_click_t = now_c
		last_click_kind = int(info[best][0]) if best != -1 else -1
	else:
		_box_select(drag_start, end)


func _box_select(a: Vector2, b: Vector2) -> void:
	selected.clear()
	if my_slot < 0:
		return
	var rect: Rect2 = Rect2(a, Vector2.ZERO).expand(b)
	for id in info:
		if info[id][1] == my_slot and _is_unit(info[id][0]):
			if rect.has_point(cam.unproject_position(views[id].position)):
				selected[id] = true


func _right_click(sp: Vector2) -> void:
	if placing != -1:
		_cancel_placing()
		return
	if targeting != -1:
		targeting = -1
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		return
	if selected.is_empty() or my_slot < 0:
		return
	var g = _ground_point(sp)
	if g == null:
		return
	var enemy: int = -1
	var field: int = -1
	var oil: bool = false
	var assist: int = -1
	var best_d: float = 100.0
	for id in info:
		var k: int = info[id][0]
		var d: float = Vector2(targets[id].x - g.x, targets[id].z - g.z).length()
		if k == 5:
			if d < 4.5 and d < best_d:
				best_d = d
				field = id
		elif k == 4:
			if d < 7.0:
				oil = true
		elif k >= 7 and info[id][1] == my_slot and int(info[id][3]) == 9:
			if d < float(Data.BUILD[k]["radius"]) + 2.0:
				assist = id
		elif _is_enemy(info[id][1]):
			var reach: float = 2.5
			if k == 0:
				reach = 8.0
			elif k >= 7:
				reach = float(Data.BUILD[k]["radius"]) + 1.5
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
	elif assist != -1 and not _selected_builders().is_empty():
		_cast_assist(assist)
	elif field != -1:
		if multiplayer.is_server():
			sim.cmd_harvest(my_slot, ids, field)
		else:
			srv_harvest.rpc_id(1, ids, field)
	else:
		var amove: bool = oil or Input.is_key_pressed(KEY_CTRL)
		if multiplayer.is_server():
			sim.cmd_move(my_slot, ids, g, amove)
		else:
			srv_move.rpc_id(1, ids, g, amove)


func _train(idx: int) -> void:
	if my_slot < 0:
		return
	if multiplayer.is_server():
		if sim != null:
			sim.cmd_train(my_slot, idx)
	else:
		srv_train.rpc_id(1, idx)


@rpc("any_peer", "reliable")
func srv_move(ids: Array, pos: Vector3, amove: bool) -> void:
	if not multiplayer.is_server() or sim == null or ids.size() > 200:
		return
	var slot: int = _slot_of(multiplayer.get_remote_sender_id())
	if slot >= 0:
		sim.cmd_move(slot, ids, pos, amove)


@rpc("any_peer", "reliable")
func srv_harvest(ids: Array, node_id: int) -> void:
	if not multiplayer.is_server() or sim == null or ids.size() > 200:
		return
	var slot: int = _slot_of(multiplayer.get_remote_sender_id())
	if slot >= 0:
		sim.cmd_harvest(slot, ids, node_id)


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
