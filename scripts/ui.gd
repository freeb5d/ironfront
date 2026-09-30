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


static func _header(text: String) -> Label:
	var l: Label = label(text, 16, ACCENT)
	l.add_theme_font_override("font", spaced("bold", 3))
	return l


static func _slider(text: String, lo: float, hi: float, step: float, value: float, setter: Callable, on_change: Callable) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var l: Label = label(text, 18)
	l.custom_minimum_size = Vector2(170, 0)
	row.add_child(l)
	var sl: HSlider = HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = value
	sl.custom_minimum_size = Vector2(240, 28)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.value_changed.connect(func(x: float):
		setter.call(x)
		Net.save_settings()
		on_change.call())
	row.add_child(sl)
	return row


## Settings controls shared by the main menu and the in-game pause menu.
static func settings_box(on_change: Callable) -> Control:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(580, 400)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v: VBoxContainer = VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	scroll.add_child(v)

	v.add_child(_header("AUDIO"))
	v.add_child(_slider("Volume", 0.0, 1.0, 0.05, Net.volume, Net.set_volume, on_change))

	v.add_child(_header("DISPLAY"))
	v.add_child(_check("Fullscreen", DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, Net.set_fullscreen, on_change))
	v.add_child(_check("VSync", Net.vsync, Net.set_vsync, on_change))
	v.add_child(_slider("Interface scale", 0.7, 1.5, 0.05, Net.ui_scale, Net.set_ui_scale, on_change))
	v.add_child(_check("Show FPS counter", Net.show_fps, func(on: bool): Net.show_fps = on, on_change))

	v.add_child(_header("PERFORMANCE"))
	v.add_child(_check("Shadows (needs a stronger graphics card)", Net.shadows, func(on: bool): Net.shadows = on, on_change))
	v.add_child(_check("Reduced effects (faster on weak computers)", Net.low_fx, func(on: bool): Net.low_fx = on, on_change))

	v.add_child(_header("CONTROLS"))
	v.add_child(_check("Scroll the map at screen edges", Net.edge_pan, func(on: bool): Net.edge_pan = on, on_change))
	v.add_child(_slider("Camera speed", 0.4, 2.5, 0.1, Net.cam_speed, func(x: float): Net.cam_speed = x, on_change))
	v.add_child(_slider("Zoom speed", 0.4, 2.5, 0.1, Net.zoom_speed, func(x: float): Net.zoom_speed = x, on_change))
	v.add_child(_check("Always show health bars", Net.always_bars, func(on: bool): Net.always_bars = on, on_change))

	v.add_child(_header("GAME"))
	var diff_row: HBoxContainer = HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 16)
	var diff_label: Label = label("Bot difficulty", 18)
	diff_label.custom_minimum_size = Vector2(170, 0)
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
	return scroll


static func label(text: String, size: int = 18, color: Color = TEXT) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if size >= 26:
		l.add_theme_font_override("font", font("bold"))
	return l
