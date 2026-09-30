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
var my_name: String = "Player"


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): connection_failed.emit())
	multiplayer.server_disconnected.connect(func(): server_lost.emit())


func reset() -> void:
	slots.clear()
	in_game = false


func _default_slots() -> Array:
	var out: Array = []
	var names: Array = Data.country_names()
	for i in Data.MAX_SLOTS:
		out.append({"type": "open", "peer": 0, "name": "", "country": names[i % names.size()]})
	return out


func host_game(pname: String) -> int:
	my_name = pname
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: int = peer.create_server(PORT, Data.MAX_SLOTS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	slots = _default_slots()
	slots[0] = {"type": "human", "peer": 1, "name": pname, "country": slots[0]["country"]}
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
	srv_hello.rpc_id(1, my_name)


@rpc("any_peer", "reliable")
func srv_hello(pname: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	for i in slots.size():
		if slots[i]["type"] == "open" and not in_game:
			slots[i] = {"type": "human", "peer": sender, "name": pname.left(16), "country": slots[i]["country"]}
			_broadcast()
			return
	multiplayer.multiplayer_peer.disconnect_peer(sender)


func _broadcast() -> void:
	sync_slots.rpc(slots)
	lobby_changed.emit()


@rpc("authority", "reliable")
func sync_slots(s: Array) -> void:
	slots = s
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
	seed_value = randi()
	in_game = true
	begin.rpc(slots, seed_value)
	game_started.emit()


@rpc("authority", "reliable")
func begin(s: Array, sd: int) -> void:
	slots = s
	seed_value = sd
	in_game = true
	game_started.emit()
