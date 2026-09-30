class_name PowerIcon
extends Control
## Little vector icon for the commander power tiles: 0 strike, 1 reinforcements, 2 repair.

var kind: int = 0


func _init() -> void:
	custom_minimum_size = Vector2(106, 50)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c: Vector2 = size * 0.5
	if c.x <= 0.0:
		c = custom_minimum_size * 0.5
	match kind:
		0:
			var red: Color = Color(1.0, 0.42, 0.3)
			draw_arc(c, 19.0, 0.0, TAU, 40, red, 3.0)
			draw_arc(c, 9.0, 0.0, TAU, 28, red, 2.0)
			draw_line(c + Vector2(-26, 0), c + Vector2(26, 0), red, 2.0)
			draw_line(c + Vector2(0, -23), c + Vector2(0, 23), red, 2.0)
		1:
			var green: Color = Color(0.45, 0.9, 0.55)
			for off in [Vector2(-18, 8), Vector2(0, -10), Vector2(18, 8)]:
				draw_circle(c + off, 7.0, green)
				draw_rect(Rect2(c + off + Vector2(-6, 7), Vector2(12, 9)), green)
		2:
			var cyan: Color = Color(0.45, 0.85, 1.0)
			draw_rect(Rect2(c + Vector2(-5, -20), Vector2(10, 40)), cyan)
			draw_rect(Rect2(c + Vector2(-20, -5), Vector2(40, 10)), cyan)
