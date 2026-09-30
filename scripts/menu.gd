extends Control
## Main menu -> nation select -> (lobby) -> game.

const OFFLINE := 1
const HOST := 2
const JOIN := 3

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


func _ready() -> void:
	theme = UI.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg: TextureRect = UI.gradient_bg()
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_build_main()
	_build_country()
	_build_lobby()
	_build_settings()

	Net.lobby_changed.connect(_refresh)
	Net.game_started.connect(_on_started)
	Net.connection_failed.connect(_on_connect_failed)
	Net.server_lost.connect(_on_server_lost)
	_show("main")
	_refresh()

	if "--autotest" in OS.get_cmdline_user_args():
		_run_autotest()


func _run_autotest() -> void:
	print("AUTOTEST MENU main_visible=%s" % screens["main"].visible)
	await get_tree().create_timer(0.6).timeout
	await Net.shot("01_main_menu")
	_show("settings")
	await get_tree().create_timer(0.3).timeout
	await Net.shot("02_settings")
	_pick(OFFLINE)
	await get_tree().create_timer(0.3).timeout
	await Net.shot("03_nation_select")
	pending = OFFLINE
	chosen = "USA"
	_confirm()


# ------------------------------------------------------------------ helpers

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


func _btn(text: String, cb: Callable, width: float = 360.0) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 52)
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
	var v: VBoxContainer = _screen("main")
	v.add_child(_center(UI.label("IRONFRONT", 84, UI.ACCENT)))
	v.add_child(_center(UI.label("REAL-TIME STRATEGY  -  UP TO 8 PLAYERS  -  5 NATIONS", 18, Color("8b98a9"))))
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(0, 24)
	v.add_child(gap)

	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Commander name"
	name_edit.text = "Commander"
	name_edit.custom_minimum_size = Vector2(360, 44)
	v.add_child(name_edit)

	v.add_child(_btn("PLAY OFFLINE  (vs 7 bots)", _pick.bind(OFFLINE)))
	v.add_child(_btn("HOST MULTIPLAYER GAME", _pick.bind(HOST)))

	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "Host IP address  (e.g. 192.168.1.20)"
	ip_edit.custom_minimum_size = Vector2(360, 44)
	v.add_child(ip_edit)
	v.add_child(_btn("JOIN GAME", _on_join_pressed))
	v.add_child(_btn("SETTINGS", _show.bind("settings")))
	v.add_child(_btn("QUIT", get_tree().quit))

	msg = _center(UI.label("", 18, Color("ff7b72")))
	v.add_child(msg)
	var ips: Label = _center(UI.label("Your address: " + ", ".join(_local_ips()) + "   |   port UDP %d   |   F11 fullscreen" % Net.PORT, 14, Color("6b7280")))
	v.add_child(ips)


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
	b.custom_minimum_size = Vector2(220, 340)
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
	var blurb: Label = UI.label(d["blurb"], 15, Color("aab4c2"))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(190, 0)
	vb.add_child(blurb)
	var sp: Control = Control.new()
	sp.custom_minimum_size = Vector2(0, 8)
	vb.add_child(sp)
	for u in d["units"]:
		vb.add_child(UI.label(str(u["name"]), 18, UI.TEXT))
		vb.add_child(UI.label("$%d   HP %d   DMG %d   RNG %d" % [u["cost"], u["hp"], u["dmg"], u["rng"]], 13, Color("8b98a9")))

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
			if Net.host_game(_pname()) != OK:
				_show("main")
				msg.text = "Could not start (is the network port already in use?)"
				return
			var names: Array = Data.country_names()
			for i in range(1, Data.MAX_SLOTS):
				Net.host_set_type(i, "bot")
				Net.set_country(i, names[randi() % names.size()])
			Net.start_game()
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
	v.add_child(panel)
	wait_label = _center(UI.label("Waiting for the host to start the game...", 18, UI.ACCENT))
	v.add_child(wait_label)
	var bar: HBoxContainer = HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 16)
	bar.add_child(_btn("LEAVE", _leave_lobby, 200.0))
	start_btn = _btn("START GAME", Net.start_game, 260.0)
	bar.add_child(start_btn)
	v.add_child(bar)


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
	wait_label.visible = not multiplayer.is_server()
	lobby_info.text = "Friends join with your address: " + ", ".join(_local_ips()) + "  (UDP %d)" % Net.PORT if multiplayer.is_server() else "Connected. Pick your nation below."
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
