class_name UI
extends RefCounted
## Shared look & feel: one dark theme used by every screen.

const BG_TOP := Color("0b1220")
const BG_BOTTOM := Color("1b2a41")
const PANEL := Color(0.09, 0.11, 0.15, 0.94)
const BORDER := Color("2d3748")
const ACCENT := Color("e3b341")
const TEXT := Color("e6edf3")


static var _fonts: Dictionary = {}


## Rajdhani (SIL Open Font License) in four weights.
static func font(weight: String) -> Font:
	if not _fonts.has(weight):
		var file: String = {"regular": "Regular", "medium": "Medium", "semibold": "SemiBold", "bold": "Bold"}[weight]
		_fonts[weight] = load("res://assets/fonts/Rajdhani-%s.ttf" % file)
	return _fonts[weight]


static func spaced(weight: String, spacing: int) -> Font:
	var fv: FontVariation = FontVariation.new()
	fv.base_font = font(weight)
	fv.spacing_glyph = spacing
	return fv


static func box(fill: Color, border: Color = Color(0, 0, 0, 0), bw: int = 0, radius: int = 8) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(10)
	return s


static func make_theme() -> Theme:
	var t: Theme = Theme.new()
	t.default_font = font("medium")
	t.default_font_size = 20
	for cls in ["Button", "OptionButton"]:
		t.set_font("font", cls, font("semibold"))
		t.set_font_size("font_size", cls, 21)
		var hover: StyleBoxFlat = box(Color(0.13, 0.19, 0.28, 0.96), ACCENT, 1, 4)
		hover.border_width_left = 6
		var pressed: StyleBoxFlat = box(Color(0.05, 0.08, 0.12, 0.98), ACCENT, 1, 4)
		pressed.border_width_left = 6
		t.set_stylebox("normal", cls, box(Color(0.06, 0.09, 0.14, 0.82), Color(0.28, 0.37, 0.50, 0.85), 1, 4))
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("disabled", cls, box(Color("10141a"), Color("1c2430"), 1, 4))
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, ACCENT)
		t.set_color("font_pressed_color", cls, ACCENT)
		t.set_color("font_disabled_color", cls, Color("6b7280"))
	t.set_stylebox("panel", "PanelContainer", box(PANEL, BORDER, 2, 10))
	t.set_stylebox("normal", "LineEdit", box(Color("0d1117"), BORDER, 2, 6))
	t.set_stylebox("focus", "LineEdit", box(Color("0d1117"), ACCENT, 2, 6))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_stylebox("background", "ProgressBar", box(Color(0.05, 0.08, 0.12), BORDER, 2, 4))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, Color(0, 0, 0, 0), 0, 4))
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_color("font_hover_color", "CheckButton", ACCENT)
	t.set_color("font_pressed_color", "CheckButton", TEXT)
	t.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())
	return t


static func _check(text: String, value: bool, setter: Callable, on_change: Callable) -> CheckButton:
	var c: CheckButton = CheckButton.new()
	c.text = text
	c.button_pressed = value
	c.toggled.connect(func(on: bool):
		setter.call(on)
		Net.save_settings()
		on_change.call())
	return c


## Settings controls shared by the main menu and the in-game pause menu.
static func settings_box(on_change: Callable) -> VBoxContainer:
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)

	var vol_row: HBoxContainer = HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 16)
	var vol_label: Label = label("Volume", 18)
	vol_label.custom_minimum_size = Vector2(110, 0)
	vol_row.add_child(vol_label)
	var sl: HSlider = HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = Net.volume
	sl.custom_minimum_size = Vector2(240, 28)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.value_changed.connect(func(x: float):
		Net.volume = x
		Net.apply_audio()
		Net.save_settings()
		on_change.call())
	vol_row.add_child(sl)
	v.add_child(vol_row)

	v.add_child(_check("Fullscreen", DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, Net.set_fullscreen, on_change))
	v.add_child(_check("Shadows (needs a stronger graphics card)", Net.shadows, func(on: bool): Net.shadows = on, on_change))
	v.add_child(_check("Scroll the map at screen edges", Net.edge_pan, func(on: bool): Net.edge_pan = on, on_change))

	var diff_row: HBoxContainer = HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 16)
	var diff_label: Label = label("Bot difficulty", 18)
	diff_label.custom_minimum_size = Vector2(110, 0)
	diff_row.add_child(diff_label)
	var ob: OptionButton = OptionButton.new()
	for t in ["Easy", "Normal", "Hard"]:
		ob.add_item(t)
	ob.selected = Net.difficulty
	ob.custom_minimum_size = Vector2(160, 0)
	ob.item_selected.connect(func(idx: int):
		Net.difficulty = idx
		Net.save_settings()
		on_change.call())
	diff_row.add_child(ob)
	v.add_child(diff_row)
	return v


static func gradient_bg() -> TextureRect:
	var g: Gradient = Gradient.new()
	g.colors = PackedColorArray([BG_TOP, BG_BOTTOM])
	g.offsets = PackedFloat32Array([0.0, 1.0])
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 4
	tex.height = 256
	var r: TextureRect = TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	return r


static func label(text: String, size: int = 18, color: Color = TEXT) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if size >= 26:
		l.add_theme_font_override("font", font("bold"))
	return l
