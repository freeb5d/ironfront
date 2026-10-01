class_name Heart
extends Control
## A small red heart drawn as a polygon (no font needs to contain a heart glyph).


func _init() -> void:
	custom_minimum_size = Vector2(18, 16)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i in 41:
		var t: float = float(i) / 40.0 * TAU
		var x: float = 16.0 * pow(sin(t), 3.0)
		var y: float = 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		pts.append(Vector2(9.0 + x * 0.52, 7.0 - y * 0.52))
	draw_colored_polygon(pts, Color("ef4444"))
