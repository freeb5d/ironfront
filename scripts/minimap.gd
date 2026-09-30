class_name MiniMap
extends Control
## Corner minimap. Reads the view state of the owning Game node; click or drag to move the camera.

const WORLD := 300.0

var game: Node = null
var bg: Texture2D = null


func _init() -> void:
	custom_minimum_size = Vector2(190, 190)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _to_map(w: Vector3) -> Vector2:
	return Vector2((w.x + WORLD * 0.5) / WORLD * size.x, (w.z + WORLD * 0.5) / WORLD * size.y)


func _draw() -> void:
	if bg != null:
		# the ground texture covers -160..160, the playable map is -150..150
		var tw: float = float(bg.get_width())
		var margin: float = tw * 10.0 / 320.0
		draw_texture_rect_region(bg, Rect2(Vector2.ZERO, size), Rect2(margin, margin, tw - 2.0 * margin, tw - 2.0 * margin))
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.09, 0.15, 0.1))
	if game != null:
		for id in game.info:
			var p: Vector2 = _to_map(game.targets[id])
			var kind: int = game.info[id][0]
			var owner: int = game.info[id][1]
			var col: Color = Data.PLAYER_COLORS[owner] if owner >= 0 else Color(0.7, 0.7, 0.7)
			if kind == 0:
				draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), col)
			elif kind == 5:
				draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), Color(0.2, 0.9, 0.3))
			elif kind >= 7:
				draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), col)
				draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), Color(0, 0, 0, 0.6), false, 1.0)
			elif kind == 4:
				draw_circle(p, 5.0, col)
				draw_circle(p, 2.5, Color(1.0, 0.85, 0.1))
			else:
				draw_circle(p, 2.0, col)
		var c: Vector2 = _to_map(game.cam_pivot.position)
		draw_rect(Rect2(c - Vector2(14, 10), Vector2(28, 20)), Color(1, 1, 1), false, 1.5)
	draw_rect(Rect2(Vector2.ZERO, size), UI.BORDER, false, 2.0)


func _gui_input(ev: InputEvent) -> void:
	if game == null:
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
		game.minimap_order(Vector3(ev.position.x / size.x * WORLD - WORLD * 0.5, 0.0, ev.position.y / size.y * WORLD - WORLD * 0.5))
		accept_event()
		return
	var pressed: bool = false
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		pressed = true
	elif ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		pressed = true
	if pressed:
		game.cam_pivot.position = Vector3(ev.position.x / size.x * WORLD - WORLD * 0.5, 0.0, ev.position.y / size.y * WORLD - WORLD * 0.5)
		accept_event()
