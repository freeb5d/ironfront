class_name Portrait
extends SubViewportContainer
## A small live 3D portrait of one or more models, rendered in its own world.
## Add it to the tree first, then call setup().


## entries: [[model_path, fit_by_height, target_size], ...] laid out left to right.
func setup(entries: Array, px: Vector2i, spin: float = 0.7) -> void:
	stretch = true
	custom_minimum_size = Vector2(px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp: SubViewport = SubViewport.new()
	vp.size = px
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE
	add_child(vp)

	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.88, 1.0)
	env.ambient_light_energy = 0.8
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.light_energy = 1.3
	vp.add_child(sun)

	var n: int = entries.size()
	var spacing: float = 4.4
	for i in n:
		var tt: Turntable = Turntable.new()
		tt.speed = spin
		tt.position = Vector3((float(i) - (n - 1) * 0.5) * spacing, 0.0, 0.0)
		tt.rotation.y = 0.6 + i
		vp.add_child(tt)
		var e: Array = entries[i]
		Models.place(tt, e[0], Vector3.ZERO, e[2], e[1], 0.0)

	var cam: Camera3D = Camera3D.new()
	cam.fov = 32.0
	vp.add_child(cam)
	var dist: float = 7.2 if n == 1 else 9.0 + 2.8 * maxf(0.0, n - 1.0)
	cam.look_at_from_position(Vector3(0.0, 3.2, dist), Vector3(0.0, 1.5, 0.0))
