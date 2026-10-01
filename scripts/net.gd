extends Node
## Autoload "Net": lobby + connection handling. The host is the authoritative server.

signal lobby_changed
signal game_started
signal connection_failed
signal server_lost
signal peer_left(slot: int)

const PORT := 24680

var slots: Array = [] # {type: open|bot|closed|human, peer: int, name: String, country: String}
var seed_value: int = 0
var in_game: bool = false
var offline: bool = false # single-player: no network socket is opened at all
var my_name: String = "Player"
var my_country: String = "USA"

# player settings (saved to user://settings.cfg)
var volume: float = 0.8
var shadows: bool = false
var edge_pan: bool = true
var difficulty: int = 1 # bots: 0 easy, 1 normal, 2 hard
var ui_scale: float = 1.0
var vsync: bool = true
var show_fps: bool = false
var cam_speed: float = 1.0
var zoom_speed: float = 1.0
var always_bars: bool = false
var low_fx: bool = false
var tips: bool = true

# single-player challenge ladder
var challenge: Dictionary = {"active": false, "stage": 0, "nation": "USA"}
var challenge_progress: Dictionary = {} # nation -> number of completed stages
var challenge_autostart: bool = false
var challenge_resume: Dictionary = {}
var match_difficulty: int = 1

# match options, chosen by the host in the lobby and synced to everyone
var options: Dictionary = Data.DEFAULT_OPTIONS.duplicate()

var _sfx_cache: Dictionary = {}
var _click_player: AudioStreamPlayer = null


func _ready() -> void:
	if OS.get_environment("IRONFRONT_MAP") != "": # CI uses this to screenshot the second map
		options["map"] = int(OS.get_environment("IRONFRONT_MAP"))
	load_settings()
	apply_audio()
	apply_video()
	_click_player = AudioStreamPlayer.new()
	_click_player.stream = sfx("click")
	_click_player.volume_db = -8.0
	add_child(_click_player)
	get_tree().node_added.connect(_on_node_added)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): connection_failed.emit())
	multiplayer.server_disconnected.connect(func(): server_lost.emit())


func _input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_F11:
		toggle_fullscreen()


func _on_node_added(n: Node) -> void:
	if n is BaseButton and not n.pressed.is_connected(play_click):
		n.pressed.connect(play_click)


## Saves a screenshot (only when a real renderer is running). Used by the CI visual check.
func shot(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		return
	var dir: String = OS.get_environment("SHOT_DIR")
	if dir == "":
		dir = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	img.save_png("%s/%s.png" % [dir, label])


func play_click() -> void:
	if _click_player != null:
		_click_player.play()


func sfx(kind: String) -> AudioStream:
	if not _sfx_cache.has(kind):
		_sfx_cache[kind] = Sfx.make(kind)
	return _sfx_cache[kind]


func apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))


func load_settings() -> void:
	var c: ConfigFile = ConfigFile.new()
	if c.load("user://settings.cfg") != OK:
		return
	volume = clampf(float(c.get_value("audio", "volume", volume)), 0.0, 1.0)
	shadows = bool(c.get_value("video", "shadows", shadows))
	edge_pan = bool(c.get_value("input", "edge_pan", edge_pan))
	difficulty = clampi(int(c.get_value("game", "difficulty", difficulty)), 0, 2)
	ui_scale = clampf(float(c.get_value("video", "ui_scale", ui_scale)), 0.7, 1.5)
	vsync = bool(c.get_value("video", "vsync", vsync))
	show_fps = bool(c.get_value("video", "show_fps", show_fps))
	low_fx = bool(c.get_value("video", "low_fx", low_fx))
	cam_speed = clampf(float(c.get_value("input", "cam_speed", cam_speed)), 0.4, 2.5)
	zoom_speed = clampf(float(c.get_value("input", "zoom_speed", zoom_speed)), 0.4, 2.5)
	always_bars = bool(c.get_value("game", "always_bars", always_bars))
	tips = bool(c.get_value("game", "tips", tips))
	var prog = c.get_value("challenge", "progress", {})
	if prog is Dictionary:
		challenge_progress = prog


func save_settings() -> void:
	var c: ConfigFile = ConfigFile.new()
	c.set_value("audio", "volume", volume)
	c.set_value("video", "shadows", shadows)
	c.set_value("input", "edge_pan", edge_pan)
	c.set_value("game", "difficulty", difficulty)
	c.set_value("video", "ui_scale", ui_scale)
	c.set_value("video", "vsync", vsync)
	c.set_value("video", "show_fps", show_fps)
	c.set_value("video", "low_fx", low_fx)
	c.set_value("input", "cam_speed", cam_speed)
	c.set_value("input", "zoom_speed", zoom_speed)
	c.set_value("game", "always_bars", always_bars)
	c.set_value("game", "tips", tips)
	c.set_value("challenge", "progress", challenge_progress)
	c.save("user://settings.cfg")


## Starts stage `stage` of the challenge ladder as `nation` (offline, no lobby).
func start_challenge(stage: int, nation: String) -> bool:
	var st: Dictionary = Data.CHALLENGE[stage]
	my_country = nation
	if host_game(my_name, true) != OK:
		return false
	challenge = {"active": true, "stage": stage, "nation": nation}
	for i in range(1, slots.size()):
		slots[i]["type"] = "closed"
		slots[i]["name"] = ""
	for b in st["bots"]:
		slots[b["slot"]] = {"type": "bot", "peer": 0, "name": "Bot", "country": b["country"], "team": b["team"]}
	slots[0]["team"] = 0
	options = Data.DEFAULT_OPTIONS.duplicate()
	options["teams"] = "custom"
	options["bot_money"] = st["bot_money"]
	start_game()
	return true


func challenge_complete(stage: int) -> void:
	var nation: String = str(challenge["nation"])
	challenge_progress[nation] = maxi(int(challenge_progress.get(nation, 0)), stage + 1)
	save_settings()


func set_volume(x: float) -> void:
	volume = x
	apply_audio()


func set_ui_scale(x: float) -> void:
	ui_scale = x
	apply_video()


func set_vsync(on: bool) -> void:
	vsync = on
	apply_video()


func apply_video() -> void:
	get_window().content_scale_factor = ui_scale
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


func set_fullscreen(on: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)


func toggle_fullscreen() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func reset() -> void:
	slots.clear()
	in_game = false
	offline = false
	challenge["active"] = false


func _default_slots() -> Array:
	var out: Array = []
	var names: Array = Data.country_names()
	for i in Data.MAX_SLOTS:
		out.append({"type": "open", "peer": 0, "name": "", "country": names[i % names.size()]})
	return out


func host_game(pname: String, is_offline: bool = false) -> int:
	my_name = pname
	offline = is_offline
	if is_offline:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	else:
		var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
		var err: int = peer.create_server(PORT, Data.MAX_SLOTS)
		if err != OK:
			return err
		multiplayer.multiplayer_peer = peer
	slots = _default_slots()
	slots[0] = {"type": "human", "peer": 1, "name": pname, "country": my_country}
	lobby_changed.emit()
	return OK


func join_game(ip: String, pname: String) -> int:
	my_name = pname
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: int = peer.create_client(ip, PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func _on_connected() -> void:
	srv_hello.rpc_id(1, my_name, my_country)


@rpc("any_peer", "reliable")
func srv_hello(pname: String, country: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	for i in slots.size():
		if slots[i]["type"] == "open" and not in_game:
			var c: String = country if Data.COUNTRIES.has(country) else slots[i]["country"]
			slots[i] = {"type": "human", "peer": sender, "name": pname.left(16), "country": c}
			_broadcast()
			return
	multiplayer.multiplayer_peer.disconnect_peer(sender)


func _broadcast() -> void:
	sync_slots.rpc(slots, options)
	lobby_changed.emit()


@rpc("authority", "reliable")
func sync_slots(s: Array, o: Dictionary) -> void:
	slots = s
	options = o
	lobby_changed.emit()


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	for i in slots.size():
		if slots[i]["peer"] == id:
			slots[i]["peer"] = 0
			slots[i]["name"] = "Bot" if in_game else ""
			slots[i]["type"] = "bot" if in_game else "open"
			peer_left.emit(i)
	_broadcast()


func set_option(key: String, value) -> void:
	if not multiplayer.is_server() or in_game or not Data.OPTION_DEFS.has(key):
		return
	options[key] = value
	_broadcast()


func _assign_teams() -> void:
	for i in slots.size():
		match str(options.get("teams", "ffa")):
			"2t":
				slots[i]["team"] = 0 if i < 4 else 1
			"4t":
				slots[i]["team"] = floori(i / 2.0)
			"custom":
				if not slots[i].has("team"):
					slots[i]["team"] = i
			_:
				slots[i]["team"] = i


func host_set_type(i: int, t: String) -> void:
	if not multiplayer.is_server() or in_game or slots[i]["type"] == "human":
		return
	if not (t in ["open", "bot", "closed"]):
		return
	slots[i]["type"] = t
	slots[i]["name"] = "Bot" if t == "bot" else ""
	_broadcast()


func set_country(i: int, c: String) -> void:
	if multiplayer.is_server():
		req_country(i, c)
	else:
		req_country.rpc_id(1, i, c)


@rpc("any_peer", "reliable")
func req_country(i: int, c: String) -> void:
	if not multiplayer.is_server() or in_game:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	if i < 0 or i >= slots.size() or not Data.COUNTRIES.has(c):
		return
	if sender == 1 or slots[i]["peer"] == sender:
		slots[i]["country"] = c
		_broadcast()


func start_game() -> void:
	if not multiplayer.is_server():
		return
	for s in slots:
		if s["type"] == "open":
			s["type"] = "closed"
	var actives: int = 0
	for s in slots:
		if s["type"] == "human" or s["type"] == "bot":
			actives += 1
	if actives < 1:
		return
	match_difficulty = int(Data.CHALLENGE[int(challenge["stage"])]["difficulty"]) if challenge["active"] else difficulty
	_assign_teams()
	seed_value = randi()
	in_game = true
	begin.rpc(slots, seed_value, options)
	game_started.emit()


@rpc("authority", "reliable")
func begin(s: Array, sd: int, o: Dictionary) -> void:
	slots = s
	options = o
	Data.map_id = int(o.get("map", 0))
	seed_value = sd
	in_game = true
	game_started.emit()
