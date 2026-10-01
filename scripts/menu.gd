extends Control
## Main menu -> nation select -> (lobby) -> game.

const OFFLINE := 1
const HOST := 2
const JOIN := 3
const CHALLENGE := 4

var pending: int = 0
var chosen: String = "USA"
var name_edit: LineEdit
var ip_edit: LineEdit
var msg: Label
var screens: Dictionary = {}
var card_group: ButtonGroup = ButtonGroup.new()
var rows: VBoxContainer
var start_btn: Button
var wait_label: Label
var lobby_info: Label
var country_title: Label
var cam3d: Camera3D
var orbit: float = 0.3
var overlay_left: TextureRect
var overlay_full: ColorRect
var pending_portraits: Array = []
var opt_controls: Dictionary = {}


func _ready() -> void:
	theme = UI.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_diorama()

	overlay_full = ColorRect.new()
	overlay_full.color = Color(0.02, 0.04, 0.08, 0.66)
	overlay_full.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay_full)
	overlay_full.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var grad: Gradient = Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.3, 0.8])
	grad.colors = PackedColorArray([Color(0.02, 0.04, 0.08, 0.95), Color(0.02, 0.04, 0.08, 0.86), Color(0.02, 0.04, 0.08, 0.0)])
	var gtex: GradientTexture2D = GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill_from = Vector2(0, 0)
	gtex.fill_to = Vector2(1, 0)
	gtex.width = 256
	gtex.height = 4
	overlay_left = TextureRect.new()
	overlay_left.texture = gtex
	overlay_left.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	overlay_left.stretch_mode = TextureRect.STRETCH_SCALE
	overlay_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay_left)
	overlay_left.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_build_main()
	_build_country()
	_build_lobby()
	_build_settings()
	_build_challenge()

	Net.lobby_changed.connect(_refresh)
	Net.game_started.connect(_on_started)
	Net.connection_failed.connect(_on_connect_failed)
	Net.server_lost.connect(_on_server_lost)
	_show("main")
	_refresh()

	if Net.challenge_autostart:
		Net.challenge_autostart = false
		_resume_challenge.call_deferred()

	if "--autotest" in OS.get_cmdline_user_args():
		if "--offline" in OS.get_cmdline_user_args():
			print("AUTOTEST MENU main_visible=%s" % screens["main"].visible)
			Net.my_name = "Commander"
			Net.start_challenge.call_deferred(0, "USA")
		else:
			_run_autotest()


func _run_autotest() -> void:
	print("AUTOTEST MENU main_visible=%s" % screens["main"].visible)
	await get_tree().create_timer(0.6).timeout
	await Net.shot("01_main_menu")
	_show("settings")
	await get_tree().create_timer(0.3).timeout
	await Net.shot("02_settings")
	pending = CHALLENGE
	chosen = "USA"
	_confirm()
	await get_tree().create_timer(0.3).timeout
	await Net.shot("05_challenge")
	_pick(HOST)
	await get_tree().create_timer(0.5).timeout
	await Net.shot("03_nation_select")
	pending = HOST
	chosen = "USA"
	_confirm() # opens the multiplayer lobby
	await get_tree().create_timer(0.4).timeout
	for i in range(1, Data.MAX_SLOTS):
		Net.host_set_type(i, "bot")
	await get_tree().create_timer(0.4).timeout
	await Net.shot("04_lobby")
	Net.start_game()


# ------------------------------------------------------------------ 3D background

func _process(dt: float) -> void:
	if cam3d == null:
		return
	orbit += dt * 0.06
	var c: Vector3 = Vector3(2, 0, 2)
	cam3d.position = c + Vector3(sin(orbit) * 62.0, 19.0, cos(orbit) * 62.0)
	cam3d.look_at(c + Vector3(0, 5, 0))


func _build_diorama() -> void:
	var sky_mat: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.20, 0.36, 0.66)
	sky_mat.sky_horizon_color = Color(0.80, 0.72, 0.60)
	sky_mat.ground_horizon_color = Color(0.80, 0.72, 0.60)
	sky_mat.ground_bottom_color = Color(0.45, 0.38, 0.28)
	var sky: Sky = Sky.new()
	sky.sky_material = sky_mat
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-26, 38, 0)
	sun.light_color = Color(1.0, 0.92, 0.80)
	sun.light_energy = 1.5
	sun.shadow_enabled = Net.shadows
	add_child(sun)

	var ground: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color(0.78, 0.66, 0.46)
	gm.roughness = 1.0
	ground.material_override = gm
	add_child(ground)

	var kit: String = "res://assets/buildings/kenney_city_industrial/"
	var units: String = "res://assets/units/"
	var props: String = "res://assets/props/"
	Models.place(self, Data.VISUALS["USA"]["hq"], Vector3(-16, 0, -10), 26.0, false, 0.5)
	Models.place(self, Data.VISUALS["China"]["hq"], Vector3(26, 0, -28), 22.0, false, -0.4)
	Models.place(self, Data.VISUALS["Russia"]["hq"], Vector3(-44, 0, -30), 20.0, false, 0.9)
	Models.place(self, units + "tank_a.glb", Vector3(-2, 0, 10), 10.0, false, 0.5)
	Models.place(self, units + "tank_b.glb", Vector3(10, 0, 15), 10.0, false, -0.3)
	Models.place(self, units + "tank_c.glb", Vector3(22, 0, 8), 10.5, false, 0.2)
	Models.place(self, units + "tank_d.glb", Vector3(-14, 0, 18), 10.0, false, 0.9)
	Models.place(self, units + "vehicle_x.glb", Vector3(34, 0, 14), 10.0, false, -0.8)
	for i in 9:
		var model: String = units + ("soldier_a.glb" if i % 2 == 0 else "soldier_b.glb")
		Models.place(self, model, Vector3(-8 + i * 2.6, 0, 24 + (i % 3) * 2.2), 5.2, true, 0.3 + i * 0.5)
	Models.place(self, units + "worker_a.glb", Vector3(6, 0, 4), 5.0, true, 2.0)
	Models.place(self, kit + "shipping-container-a.glb", Vector3(38, 0, -6), 9.0, false, 0.3)
	Models.place(self, kit + "shipping-container-b.glb", Vector3(44, 0, -2), 9.0, false, -0.2)
	Models.place(self, kit + "water-tower.glb", Vector3(-34, 0, -2), 24.0, true, 0.0)
	Models.place(self, kit + "detail-tank.glb", Vector3(-28, 0, 8), 8.0, false, 0.0)
	for i in 26:
		var a: float = float(i) * 2.399
		var rad: float = 62.0 + fmod(float(i) * 7.3, 60.0)
		var p: Vector3 = Vector3(cos(a) * rad, 0, sin(a) * rad)
		if i % 4 == 0:
			Models.place(self, props + "rocks-high.glb", p, 9.0 + fmod(float(i), 5.0), false, a)
		else:
			Models.place(self, props + ("tree.glb" if i % 2 == 0 else "tree-high.glb"), p, 13.0 + fmod(float(i) * 1.7, 7.0), true, a)

	cam3d = Camera3D.new()
	cam3d.fov = 48.0
	add_child(cam3d)
	cam3d.make_current()


# ------------------------------------------------------------------ helpers

func _screen_left(id: String) -> VBoxContainer:
	var m: MarginContainer = MarginContainer.new()
	add_child(m)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 100)
	m.add_theme_constant_override("margin_top", 24)
	m.add_theme_constant_override("margin_bottom", 14)
	var sc: ScrollContainer = ScrollContainer.new() # scrolls on very small screens instead of cutting the menu off
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	m.add_child(sc)
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	sc.add_child(v)
	m.visible = false
	screens[id] = m
	return v


func _screen(id: String) -> VBoxContainer:
	var c: CenterContainer = CenterContainer.new()
	add_child(c)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	c.add_child(v)
	c.visible = false
	screens[id] = c
	return v


func _show(id: String) -> void:
	for k in screens:
		screens[k].visible = (k == id)
	overlay_left.visible = (id == "main")
	overlay_full.visible = (id != "main")


func _btn(text: String, cb: Callable, width: float = 360.0, left: bool = false) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 48)
	if left:
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(cb)
	return b


func _center(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _local_ips() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out


func _pname() -> String:
	var n: String = name_edit.text.strip_edges()
	return n if n != "" else "Player"


# ------------------------------------------------------------------ main screen

func _build_main() -> void:
	var v: VBoxContainer = _screen_left("main")
	var title: Label = Label.new()
	title.text = "IRONFRONT"
	title.add_theme_font_override("font", UI.spaced("bold", 12))
	title.add_theme_font_size_override("font_size", 82)
	title.add_theme_color_override("font_color", UI.ACCENT)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("outline_size", 10)
	v.add_child(title)
	var sub: Label = UI.label("REAL-TIME STRATEGY  |  8 PLAYERS  |  5 NATIONS", 20, Color("9fb0c4"))
	sub.add_theme_font_override("font", UI.spaced("semibold", 4))
	v.add_child(sub)
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	v.add_child(gap)

	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Commander name"
	name_edit.text = "Commander"
	name_edit.custom_minimum_size = Vector2(420, 42)
	v.add_child(name_edit)

	v.add_child(_btn("PLAY OFFLINE  -  VS 7 BOTS", _pick.bind(OFFLINE), 420.0, true))
	v.add_child(_btn("CHALLENGE  -  5 SINGLE-PLAYER STAGES", _pick.bind(CHALLENGE), 420.0, true))
	v.add_child(_btn("HOST MULTIPLAYER GAME", _pick.bind(HOST), 420.0, true))

	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "Host IP address  (e.g. 192.168.1.20)"
	ip_edit.custom_minimum_size = Vector2(420, 42)
	v.add_child(ip_edit)
	v.add_child(_btn("JOIN GAME", _on_join_pressed, 420.0, true))
	v.add_child(_btn("SETTINGS", _show.bind("settings"), 420.0, true))
	v.add_child(_btn("QUIT", get_tree().quit, 420.0, true))

	msg = UI.label("", 18, Color("ff7b72"))
	v.add_child(msg)
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var ips: Label = UI.label("Your address: " + ", ".join(_local_ips()) + "    UDP port %d    F11 fullscreen    v%s" % [Net.PORT, str(ProjectSettings.get_setting("application/config/version", ""))], 15, Color("7d8a9b"))
	v.add_child(ips)
	var made: HBoxContainer = HBoxContainer.new()
	made.add_theme_constant_override("separation", 6)
	made.add_child(UI.label("Made with", 14, Color("8a97a8")))
	var heart: Heart = Heart.new()
	made.add_child(heart)
	made.add_child(UI.label("by Kaveh", 14, Color("8a97a8")))
	v.add_child(made)


func _on_join_pressed() -> void:
	if ip_edit.text.strip_edges() == "":
		msg.text = "Enter the host's IP address first."
		return
	msg.text = ""
	_pick(JOIN)


func _pick(action: int) -> void:
	pending = action
	country_title.text = "CHOOSE YOUR NATION" + ("  -  JOINING " + ip_edit.text.strip_edges() if action == JOIN else "")
	_show("country")


# ------------------------------------------------------------------ nation select

func _build_country() -> void:
	var v: VBoxContainer = _screen("country")
	country_title = _center(UI.label("CHOOSE YOUR NATION", 44, UI.ACCENT))
	v.add_child(country_title)
	var hb: HBoxContainer = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	v.add_child(hb)
	var first: bool = true
	for cname in Data.country_names():
		hb.add_child(_card(cname, first))
		first = false
	for pp in pending_portraits: # portraits need their card to be in the tree first
		pp[0].setup(pp[1], Vector2i(206, 140), 0.6)
	pending_portraits.clear()
	var bar: HBoxContainer = HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 16)
	bar.add_child(_btn("BACK", _show.bind("main"), 200.0))
	bar.add_child(_btn("CONFIRM", _confirm, 260.0))
	v.add_child(bar)


func _card(cname: String, selected: bool) -> Control:
	var d: Dictionary = Data.COUNTRIES[cname]
	var col: Color = d["color"]
	var wrap: VBoxContainer = VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 4)
	var banner: ColorRect = ColorRect.new()
	banner.color = col
	banner.custom_minimum_size = Vector2(0, 10)
	wrap.add_child(banner)

	var b: Button = Button.new()
	b.toggle_mode = true
	b.button_group = card_group
	b.custom_minimum_size = Vector2(236, 440)
	wrap.add_child(b)

	var m: MarginContainer = MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(m)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 14)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 6)
	m.add_child(vb)

	vb.add_child(UI.label(cname.to_upper(), 28, col))
	var blurb: Label = UI.label(d["blurb"], 16, Color("aab4c2"))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(206, 0)
	vb.add_child(blurb)
	var portrait: Portrait = Portrait.new()
	vb.add_child(portrait)
	var ents: Array = []
	for k in 2:
		var vis: Array = Data.VISUALS[cname]["units"][k]
		ents.append([vis[0], vis[1], 3.4 if vis[1] else 5.0])
	pending_portraits.append([portrait, ents])
	var sp: Control = Control.new()
	sp.custom_minimum_size = Vector2(0, 6)
	vb.add_child(sp)
	for u in d["units"]:
		vb.add_child(UI.label(str(u["name"]), 18, UI.TEXT))
		vb.add_child(UI.label("$%d  HP %d  DMG %d  RNG %d" % [u["cost"], u["hp"], u["dmg"], u["rng"]], 12, Color("8b98a9")))

	b.toggled.connect(func(on: bool):
		if on:
			chosen = cname)
	if selected:
		b.button_pressed = true
	return wrap


func _confirm() -> void:
	Net.my_country = chosen
	match pending:
		OFFLINE:
			if Net.host_game(_pname(), true) != OK:
				_show("main")
				msg.text = "Could not start (is the network port already in use?)"
				return
			var names: Array = Data.country_names()
			for i in range(1, Data.MAX_SLOTS):
				Net.host_set_type(i, "bot")
				Net.set_country(i, names[randi() % names.size()])
		CHALLENGE:
			_refresh_challenge()
			_show("challenge")
		HOST:
			if Net.host_game(_pname()) != OK:
				_show("main")
				msg.text = "Could not host (is the network port already in use?)"
		JOIN:
			if Net.join_game(ip_edit.text.strip_edges(), _pname()) != OK:
				_show("main")
				msg.text = "Invalid address."
			else:
				country_title.text = "CONNECTING..."


func _on_connect_failed() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	Net.reset()
	_show("main")
	msg.text = "Could not connect to the host."


func _on_server_lost() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	Net.reset()
	_show("main")
	msg.text = "Disconnected from the host."


# ------------------------------------------------------------------ challenge ladder

var ch_rows: VBoxContainer
var ch_title: Label


func _build_challenge() -> void:
	var v: VBoxContainer = _screen("challenge")
	ch_title = _center(UI.label("CHALLENGE", 44, UI.ACCENT))
	v.add_child(ch_title)
	var panel: PanelContainer = PanelContainer.new()
	ch_rows = VBoxContainer.new()
	ch_rows.add_theme_constant_override("separation", 8)
	panel.add_child(ch_rows)
	v.add_child(panel)
	var bar: HBoxContainer = HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_child(_btn("BACK", _show.bind("main"), 240.0))
	v.add_child(bar)


func _refresh_challenge() -> void:
	ch_title.text = "CHALLENGE  -  %s" % chosen.to_upper()
	for c in ch_rows.get_children():
		ch_rows.remove_child(c)
		c.queue_free()
	var done: int = int(Net.challenge_progress.get(chosen, 0))
	for i in Data.CHALLENGE.size():
		var st: Dictionary = Data.CHALLENGE[i]
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var num: Label = UI.label(str(i + 1), 34, UI.ACCENT if i <= done else Color("5b6472"))
		num.custom_minimum_size = Vector2(40, 0)
		row.add_child(num)
		var info: VBoxContainer = VBoxContainer.new()
		info.custom_minimum_size = Vector2(420, 0)
		info.add_child(UI.label(str(st["title"]), 22))
		var foes: Array = []
		var allies: Array = []
		for b in st["bots"]:
			if int(b["team"]) == 0:
				allies.append(b["country"])
			else:
				foes.append(b["country"])
		var line: String = "%s   |   vs %s" % [st["desc"], ", ".join(foes)]
		if not allies.is_empty():
			line += "   |   ally: " + ", ".join(allies)
		var dl: Label = UI.label(line, 14, Color("8b98a9"))
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.custom_minimum_size = Vector2(420, 0)
		info.add_child(dl)
		row.add_child(info)
		var status: Label = UI.label("COMPLETED" if i < done else ("READY" if i == done else "LOCKED"), 16, Color("7ee787") if i < done else (UI.ACCENT if i == done else Color("6b7280")))
		status.custom_minimum_size = Vector2(120, 0)
		row.add_child(status)
		var go: Button = _btn("START" if i >= done else "REPLAY", _start_stage.bind(i), 140.0)
		go.disabled = i > done
		row.add_child(go)
		ch_rows.add_child(row)


func _start_stage(i: int) -> void:
	Net.my_name = _pname()
	if not Net.start_challenge(i, chosen):
		msg.text = "Could not start the stage."
		_show("main")


func _resume_challenge() -> void:
	Net.start_challenge(int(Net.challenge_resume["stage"]), str(Net.challenge_resume["nation"]))


# ------------------------------------------------------------------ settings

func _build_settings() -> void:
	var v: VBoxContainer = _screen("settings")
	v.add_child(_center(UI.label("SETTINGS", 44, UI.ACCENT)))
	var panel: PanelContainer = PanelContainer.new()
	panel.add_child(UI.settings_box(func(): pass))
	v.add_child(panel)
	v.add_child(_btn("BACK", _show.bind("main"), 260.0))


# ------------------------------------------------------------------ lobby

func _build_lobby() -> void:
	var v: VBoxContainer = _screen("lobby")
	v.add_child(_center(UI.label("GAME LOBBY", 44, UI.ACCENT)))
	lobby_info = _center(UI.label("", 16, Color("8b98a9")))
	v.add_child(lobby_info)
	var panel: PanelContainer = PanelContainer.new()
	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	panel.add_child(rows)
	var hb: HBoxContainer = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	v.add_child(hb)
	hb.add_child(panel)
	var opt_panel: PanelContainer = PanelContainer.new()
	var ov: VBoxContainer = VBoxContainer.new()
	ov.add_theme_constant_override("separation", 2)
	opt_panel.add_child(ov)
	hb.add_child(opt_panel)
	ov.add_child(UI.label("MATCH OPTIONS", 16, UI.ACCENT))
	var og: GridContainer = GridContainer.new()
	og.columns = 2
	og.add_theme_constant_override("h_separation", 12)
	og.add_theme_constant_override("v_separation", 4)
	ov.add_child(og)
	for key in Data.OPTION_DEFS.keys():
		var def: Dictionary = Data.OPTION_DEFS[key]
		var cell: VBoxContainer = VBoxContainer.new()
		cell.add_theme_constant_override("separation", 0)
		cell.add_child(UI.label(str(def["label"]), 15, Color("8b98a9")))
		var ob: OptionButton = OptionButton.new()
		ob.custom_minimum_size = Vector2(212, 0)
		for nm in def["names"]:
			ob.add_item(str(nm))
		ob.item_selected.connect(_on_option.bind(key))
		cell.add_child(ob)
		og.add_child(cell)
		opt_controls[key] = ob
	var dcell: VBoxContainer = VBoxContainer.new()
	dcell.add_theme_constant_override("separation", 0)
	dcell.add_child(UI.label("Bot difficulty", 15, Color("8b98a9")))
	var dob: OptionButton = OptionButton.new()
	dob.custom_minimum_size = Vector2(212, 0)
	for nm in ["Easy", "Normal", "Hard"]:
		dob.add_item(nm)
	dob.item_selected.connect(func(idx: int):
		Net.difficulty = idx
		Net.save_settings())
	dcell.add_child(dob)
	og.add_child(dcell)
	opt_controls["difficulty"] = dob
	wait_label = _center(UI.label("Waiting for the host to start the game...", 18, UI.ACCENT))
	v.add_child(wait_label)
	var bar: HBoxContainer = HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 16)
	bar.add_child(_btn("LEAVE", _leave_lobby, 200.0))
	start_btn = _btn("START GAME", Net.start_game, 260.0)
	bar.add_child(start_btn)
	v.add_child(bar)


func _on_option(idx: int, key: String) -> void:
	Net.set_option(key, Data.OPTION_DEFS[key]["values"][idx])


func _leave_lobby() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	Net.reset()
	_show("main")


func _on_started() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _refresh() -> void:
	if Net.slots.is_empty():
		if screens["lobby"].visible:
			_show("main")
		return
	_show("lobby")
	start_btn.visible = multiplayer.is_server()
	for key in opt_controls:
		var ob2: OptionButton = opt_controls[key]
		if key == "difficulty":
			ob2.selected = Net.difficulty
		else:
			var at: int = Data.OPTION_DEFS[key]["values"].find(Net.options.get(key))
			if at >= 0:
				ob2.selected = at
		ob2.disabled = not multiplayer.is_server()
	wait_label.visible = not multiplayer.is_server()
	if Net.offline:
		lobby_info.text = "Skirmish - pick your opponents, adjust the match options and press START."
	elif multiplayer.is_server():
		lobby_info.text = "Friends join with your address: " + ", ".join(_local_ips()) + "  (UDP %d)" % Net.PORT
	else:
		lobby_info.text = "Connected. Pick your nation below."
	for c in rows.get_children():
		rows.remove_child(c)
		c.queue_free()
	var me: int = multiplayer.get_unique_id()
	var names: Array = Data.country_names()
	for i in Net.slots.size():
		var s: Dictionary = Net.slots[i]
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var swatch: ColorRect = ColorRect.new()
		swatch.color = Data.PLAYER_COLORS[i]
		swatch.custom_minimum_size = Vector2(8, 34)
		row.add_child(swatch)
		row.add_child(UI.label("P%d" % (i + 1), 18, Data.PLAYER_COLORS[i]))

		var who: Label = UI.label("", 18)
		who.custom_minimum_size = Vector2(190, 0)
		if s["type"] == "human":
			who.text = str(s["name"]) + ("  (host)" if s["peer"] == 1 else "")
			row.add_child(who)
			var pad: Control = Control.new()
			pad.custom_minimum_size = Vector2(150, 0)
			row.add_child(pad)
		elif multiplayer.is_server():
			row.add_child(who)
			var tb: OptionButton = OptionButton.new()
			tb.custom_minimum_size = Vector2(150, 0)
			for t in ["Open", "Bot", "Closed"]:
				tb.add_item(t)
			tb.selected = ["open", "bot", "closed"].find(s["type"])
			tb.item_selected.connect(func(idx: int): Net.host_set_type(i, ["open", "bot", "closed"][idx]))
			row.add_child(tb)
		else:
			who.text = str(s["type"]).capitalize()
			row.add_child(who)
			var pad2: Control = Control.new()
			pad2.custom_minimum_size = Vector2(150, 0)
			row.add_child(pad2)

		if s["type"] == "human" or s["type"] == "bot":
			var cb: OptionButton = OptionButton.new()
			cb.custom_minimum_size = Vector2(150, 0)
			for c in names:
				cb.add_item(c)
			cb.selected = names.find(s["country"])
			cb.disabled = not (multiplayer.is_server() or s["peer"] == me)
			cb.item_selected.connect(func(idx: int): Net.set_country(i, names[idx]))
			row.add_child(cb)
		rows.add_child(row)
