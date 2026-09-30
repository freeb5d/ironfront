extends Control

var name_edit: LineEdit
var ip_edit: LineEdit
var msg: Label
var connect_box: VBoxContainer
var lobby_box: VBoxContainer
var rows: VBoxContainer
var start_btn: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.08, 0.1, 0.14)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center: CenterContainer = CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var root: VBoxContainer = VBoxContainer.new()
	root.custom_minimum_size = Vector2(600, 0)
	root.add_theme_constant_override("separation", 10)
	center.add_child(root)

	var title: Label = Label.new()
	title.text = "IRONFRONT"
	title.add_theme_font_size_override("font_size", 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	msg = Label.new()
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(msg)

	# --- connect panel ---
	connect_box = VBoxContainer.new()
	connect_box.add_theme_constant_override("separation", 8)
	root.add_child(connect_box)

	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Your name"
	name_edit.text = "Player"
	connect_box.add_child(name_edit)

	var solo: Button = Button.new()
	solo.text = "Play offline vs 7 bots"
	solo.pressed.connect(_solo)
	connect_box.add_child(solo)

	var host: Button = Button.new()
	host.text = "Host LAN / online game (UDP port %d)" % Net.PORT
	host.pressed.connect(_host)
	connect_box.add_child(host)

	var ips: Label = Label.new()
	ips.text = "Your addresses (give one to friends): " + ", ".join(_local_ips())
	ips.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	connect_box.add_child(ips)

	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "Host IP address, e.g. 192.168.1.20"
	connect_box.add_child(ip_edit)

	var join: Button = Button.new()
	join.text = "Join game"
	join.pressed.connect(_join)
	connect_box.add_child(join)

	# --- lobby panel ---
	lobby_box = VBoxContainer.new()
	lobby_box.visible = false
	root.add_child(lobby_box)
	rows = VBoxContainer.new()
	lobby_box.add_child(rows)
	start_btn = Button.new()
	start_btn.text = "START GAME"
	start_btn.pressed.connect(Net.start_game)
	lobby_box.add_child(start_btn)

	Net.lobby_changed.connect(_refresh)
	Net.game_started.connect(_on_started)
	Net.connection_failed.connect(func(): msg.text = "Could not connect.")
	Net.server_lost.connect(_on_server_lost)
	_refresh()


func _local_ips() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out


func _pname() -> String:
	var n: String = name_edit.text.strip_edges()
	return n if n != "" else "Player"


func _solo() -> void:
	if Net.host_game(_pname()) != OK:
		msg.text = "Could not start (is the port in use?)"
		return
	for i in range(1, Data.MAX_SLOTS):
		Net.host_set_type(i, "bot")
	Net.start_game()


func _host() -> void:
	if Net.host_game(_pname()) != OK:
		msg.text = "Could not host (is the port in use?)"


func _join() -> void:
	var ip: String = ip_edit.text.strip_edges()
	if ip == "":
		msg.text = "Enter the host's IP address."
		return
	msg.text = "Connecting..."
	if Net.join_game(ip, _pname()) != OK:
		msg.text = "Invalid address."


func _on_server_lost() -> void:
	msg.text = "Disconnected from host."
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	Net.reset()
	_refresh()


func _on_started() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _refresh() -> void:
	if Net.slots.is_empty():
		connect_box.visible = true
		lobby_box.visible = false
		return
	msg.text = ""
	connect_box.visible = false
	lobby_box.visible = true
	start_btn.visible = multiplayer.is_server()
	for c in rows.get_children():
		rows.remove_child(c)
		c.queue_free()
	var me: int = multiplayer.get_unique_id()
	var names: Array = Data.country_names()
	for i in Net.slots.size():
		var s: Dictionary = Net.slots[i]
		var row: HBoxContainer = HBoxContainer.new()
		var swatch: ColorRect = ColorRect.new()
		swatch.color = Data.PLAYER_COLORS[i]
		swatch.custom_minimum_size = Vector2(18, 18)
		row.add_child(swatch)

		var who: Label = Label.new()
		who.custom_minimum_size = Vector2(180, 0)
		if s["type"] == "human":
			who.text = " " + str(s["name"]) + (" (host)" if s["peer"] == 1 else "")
			row.add_child(who)
		elif multiplayer.is_server():
			row.add_child(who)
			var tb: OptionButton = OptionButton.new()
			tb.custom_minimum_size = Vector2(180, 0)
			for t in ["Open", "Bot", "Closed"]:
				tb.add_item(t)
			tb.selected = ["open", "bot", "closed"].find(s["type"])
			tb.item_selected.connect(func(idx: int): Net.host_set_type(i, ["open", "bot", "closed"][idx]))
			row.add_child(tb)
		else:
			who.text = " " + str(s["type"]).capitalize()
			row.add_child(who)

		if s["type"] == "human" or s["type"] == "bot":
			var cb: OptionButton = OptionButton.new()
			for c in names:
				cb.add_item(c)
			cb.selected = names.find(s["country"])
			cb.disabled = not (multiplayer.is_server() or s["peer"] == me)
			cb.item_selected.connect(func(idx: int): Net.set_country(i, names[idx]))
			row.add_child(cb)
		rows.add_child(row)
