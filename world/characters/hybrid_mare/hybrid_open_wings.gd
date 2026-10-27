extends Node
## Optional original open wing meshes on the EXISTING body skeleton; no second rig.
## Shared by the flight review and lazy gameplay takeoff.
const SCENE := "res://world/characters/body_shapes/mare_wings.scn"
## The open wings unfold from, and fold back into, a tucked pose that lies over the folded wing
## mesh (dev 2026-10-26: they snapped between folded and open). Offsets from each bone's rest,
## made by tools/wings/extract_wing_tuck.gd. A modifier blends the open-wing bones toward it on
## top of whatever pose flight or excitement set; the folded mesh swaps in once fully tucked.
const TUCK := "res://world/characters/hybrid_mare/wing_tuck.json"
const UNFOLD_SECONDS := 0.35
const FOLD_SECONDS := 0.3
static var _tuck_offsets: Dictionary = {}
var meshes: Array[MeshInstance3D] = []
var folded: Array[MeshInstance3D] = []
var opened := false
var bind_error := 0.0
## 1 = fully tucked, 0 = the pose set by flight or excitement.
var tuck := 1.0
var _modifier: SkeletonModifier3D

class TuckModifier extends SkeletonModifier3D:
	var wings: Node
	var bones: Array[int] = []
	var poses: Array[Quaternion] = []
	func _process_modification_with_delta(_delta: float) -> void:
		var weight := smoothstep(0.0, 1.0, float(wings.tuck))
		if weight <= 0.0: return
		var skeleton := get_skeleton()
		for i in bones.size():
			skeleton.set_bone_pose_rotation(bones[i], skeleton.get_bone_pose_rotation(bones[i]).slerp(poses[i], weight))

func bind(pony: CharacterBody3D) -> bool:
	if not meshes.is_empty() or not pony.identity.has_wings(): return false
	var source: Node3D = load(pony.get_meta("open_wing_scene", SCENE)).instantiate()
	add_child(source)
	var source_sk: Skeleton3D = source.find_children("*", "Skeleton3D", true, false)[0]
	var target: Skeleton3D = pony.skeleton
	for node in target.find_children("*", "MeshInstance3D", true, false):
		if String(node.name).begins_with("wing folded"): folded.append(node)
	if folded.size() != 2: source.free(); return false
	for original: MeshInstance3D in source.find_children("*", "MeshInstance3D", true, false):
		if not String(original.name).begins_with("wing open"): continue
		var skin: Skin = original.skin.duplicate()
		for i in skin.get_bind_count():
			var bone_name := skin.get_bind_name(i)
			if bone_name == &"": bone_name = source_sk.get_bone_name(skin.get_bind_bone(i))
			var b := target.find_bone(bone_name)
			if b < 0: source.free(); return false
			var original_b := source_sk.find_bone(bone_name)
			var a := source_sk.get_bone_global_rest(original_b)
			var expected := target.get_bone_global_rest(b)
			bind_error = maxf(bind_error, a.origin.distance_to(expected.origin))
			for axis in 3: bind_error = maxf(bind_error, a.basis[axis].distance_to(expected.basis[axis]))
			skin.set_bind_name(i, bone_name); skin.set_bind_bone(i, b)
		if bind_error > .00001: source.free(); return false
		var mi := MeshInstance3D.new(); mi.name = original.name
		mi.mesh = original.mesh; mi.skin = skin
		target.add_child(mi); mi.skeleton = NodePath("..")
		mi.transform = source_sk.global_transform.affine_inverse() * original.global_transform
		# Exactly the existing folded-wing coat/shadow/outline material, no new shader.
		for surface in mi.mesh.get_surface_count(): mi.set_surface_override_material(surface, folded[0].get_active_material(0))
		mi.extra_cull_margin = 1.0
		meshes.append(mi)
	source.free()
	_add_tuck(target)
	set_open(false)
	return meshes.size() == 2

func _add_tuck(target: Skeleton3D) -> void:
	if _tuck_offsets.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TUCK))
		if parsed is Dictionary and parsed.get("rest_offsets") is Dictionary: _tuck_offsets = parsed.rest_offsets
	if _tuck_offsets.is_empty(): return
	var modifier := TuckModifier.new()
	modifier.name = "WingTuck"
	modifier.wings = self
	for bone: String in _tuck_offsets:
		var b := target.find_bone(bone)
		if b < 0: modifier.free(); return
		var offset: Array = _tuck_offsets[bone]
		modifier.bones.append(b)
		modifier.poses.append(target.get_bone_rest(b).basis.get_rotation_quaternion() * Quaternion(offset[0], offset[1], offset[2], offset[3]))
	# Last child: it runs after every other modifier, on top of the flight pose.
	target.add_child(modifier)
	_modifier = modifier

func set_open(value: bool) -> void:
	opened = value
	if _modifier == null or not is_inside_tree():
		tuck = 0.0 if value else 1.0
		_show(value)
		return
	if value: _show(true)
	set_process(true)

func _process(delta: float) -> void:
	var goal := 0.0 if opened else 1.0
	tuck = move_toward(tuck, goal, delta / (UNFOLD_SECONDS if opened else FOLD_SECONDS))
	if tuck != goal: return
	set_process(false)
	if not opened: _show(false)

func _show(open: bool) -> void:
	for mi in meshes: mi.visible = open
	for mi in folded: mi.visible = not open

func _exit_tree() -> void:
	if is_instance_valid(_modifier) and not _modifier.is_queued_for_deletion(): _modifier.queue_free()
	for mi in meshes:
		if is_instance_valid(mi) and not mi.is_queued_for_deletion(): mi.queue_free()
	for mi in folded:
		if is_instance_valid(mi): mi.visible = true
