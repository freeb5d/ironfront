class_name PowerIcon
extends Control
## Little vector icon for the commander power tiles: 0 strike, 1 reinforcements, 2 repair.

var kind: int = 0


func _init() -> void:
	custom_minimum_size = Vector2(90, 50)
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
		3:
			var steel: Color = Color(0.75, 0.82, 0.9)
			draw_circle(c + Vector2(-4, 4), 13.0, steel)
			draw_rect(Rect2(c + Vector2(2, -2), Vector2(24, 7)), steel)
			draw_rect(Rect2(c + Vector2(-20, 14), Vector2(32, 5)), Color(0.4, 0.46, 0.55))
		4:
			var gold: Color = Color(1.0, 0.85, 0.2)
			for a in [0.0, 2.094, 4.188]:
				draw_arc(c, 13.0, a - 0.5, a + 0.5, 10, gold, 9.0)
			draw_circle(c, 4.0, gold)
			draw_arc(c, 22.0, 0.0, TAU, 40, Color(1.0, 0.85, 0.2, 0.4), 2.0)
		5:
			var blue: Color = Color(0.45, 0.65, 1.0)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-16, -18), c + Vector2(16, -18), c + Vector2(16, 4), c + Vector2(0, 20), c + Vector2(-16, 4)]), blue)
		6:
			var steel2: Color = Color(0.85, 0.88, 0.95)
			draw_line(c + Vector2(-18, 16), c + Vector2(18, -16), steel2, 5.0)
			draw_line(c + Vector2(-10, -4), c + Vector2(4, 10), Color(0.9, 0.6, 0.2), 4.0)
		7:
			var crate: Color = Color(0.85, 0.65, 0.35)
			draw_rect(Rect2(c + Vector2(-18, -14), Vector2(36, 28)), crate)
			draw_line(c + Vector2(-18, -14), c + Vector2(18, 14), Color(0.3, 0.2, 0.1), 2.0)
			draw_line(c + Vector2(18, -14), c + Vector2(-18, 14), Color(0.3, 0.2, 0.1), 2.0)
		2:
			var cyan: Color = Color(0.45, 0.85, 1.0)
			draw_rect(Rect2(c + Vector2(-5, -20), Vector2(10, 40)), cyan)
			draw_rect(Rect2(c + Vector2(-20, -5), Vector2(40, 10)), cyan)
