class_name Models
extends RefCounted
## Helpers for placing glTF models at a chosen size (used by the menu scene and portraits).


static func bounds(inst: Node3D) -> AABB:
	var parent: Node3D = inst.get_parent() as Node3D
	var inv: Transform3D = parent.global_transform.affine_inverse()
	var have: bool = false
	var box: AABB = AABB()
	var skels: Array = inst.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		for sk in skels:
			for b in sk.get_bone_count():
				var p: Vector3 = inv * (sk.global_transform * sk.get_bone_global_rest(b).origin)
				if not have:
					box = AABB(p, Vector3.ZERO)
					have = true
				else:
					box = box.expand(p)
		return box.grow(maxf(box.size.x, maxf(box.size.y, box.size.z)) * 0.06)
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var b2: AABB = (inv * mi.global_transform) * mi.get_aabb()
		if not have:
			box = b2
			have = true
		else:
			box = box.merge(b2)
	return box


## Scales and re-centres `inst` (which must already be in the tree) so its footprint / height equals `target`.
static func fit(inst: Node3D, target: float, by_height: bool) -> void:
	var box: AABB = bounds(inst)
	var dim: float = box.size.y if by_height else maxf(box.size.x, box.size.z)
	if dim < 0.0001:
		return
	var k: float = target / dim
	inst.scale = Vector3.ONE * k
	inst.position = Vector3(-(box.position.x + box.size.x * 0.5) * k, -box.position.y * k, -(box.position.z + box.size.z * 0.5) * k)


static func play_idle(inst: Node) -> void:
	var aps: Array = inst.find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		return
	var ap: AnimationPlayer = aps[0]
	for n in ap.get_animation_list():
		if String(n).to_lower().ends_with("idle"):
			ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
			ap.play(n)
			return


## Loads `path`, adds it under `parent` (must be in the tree) and returns the holder node, or null if the file is missing.
static func place(parent: Node, path: String, pos: Vector3, size: float, by_h: bool, yaw: float = 0.0) -> Node3D:
	var res = load(path)
	if res == null:
		return null
	var holder: Node3D = Node3D.new()
	holder.position = pos
	holder.rotation.y = yaw
	parent.add_child(holder)
	var inst: Node3D = res.instantiate()
	holder.add_child(inst)
	fit(inst, size, by_h)
	play_idle(inst)
	return holder
