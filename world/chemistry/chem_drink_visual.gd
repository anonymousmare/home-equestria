extends Node3D
## A pony holding and drinking from a chemistry vessel (dev 2026-10-26: "have the pony be
## actually able to hold them and visually drink them"). The vessel (chem_container.gd) appears at
## her front hoof (the pony_hand_R bone, so it follows her while she walks), lifts to her mouth,
## tilts while the liquid sinks, and goes back down. A unicorn's horn lights and the vessel glows
## in her magic colour; steam rises from a hot drink. Visual only: what the drink does is
## pony_potion_effects.gd.
##
## hold(): the vessel stays in her hoof until release() (a pony walking over to hand something
##   to somepony, pony_belongings.gd).
## drink(): the whole sip, then it frees itself.
const CONTAINER := preload("res://world/chemistry/chem_container.gd")
const CATALOG := preload("res://world/chemistry/chem_catalog.gd")
const HAND_BONES := ["pony_hand_R", "pony_hand_L"]
## Fractions of one drink.
const LIFT := 0.22
const SIP_END := 0.78

var pony: Node3D
var vessel: Node3D
var mode := "hold"
var total := 3.4
var from_level := 1.0
var to_level := 0.0
var _time := 0.0
var _skeleton: Skeleton3D
var _bone := -1
var _steam: CPUParticles3D
var _hot := false
var _magic := false
var _releasing := false
var _fade := 0.0


## She holds `container` until release().
static func hold(host: Node, pony: Node3D, container: String, liquid: Color, fraction := 1.0, temp := CATALOG.ROOM) -> Node3D:
	return _start(host, pony, container, liquid, fraction, temp, "hold", 0.0, fraction, fraction)


## She lifts it, drinks from `fraction` down to `leave`, and puts it down. `seconds` for the lot.
static func drink(host: Node, pony: Node3D, container: String, liquid: Color, fraction := 1.0, temp := CATALOG.ROOM, seconds := 3.4, leave := 0.0) -> Node3D:
	return _start(host, pony, container, liquid, fraction, temp, "drink", seconds, fraction, leave)


static func _start(host: Node, pony: Node3D, container: String, liquid: Color, fraction: float, temp: float, how: String, seconds: float, from_l: float, to_l: float) -> Node3D:
	if not is_instance_valid(pony) or not pony.is_inside_tree(): return null
	# One at a time per pony: a new one replaces the old.
	for old: Node in pony.get_tree().get_nodes_in_group("chem_drink_visuals"):
		if old.get("pony") == pony: old.queue_free()
	var node: Node3D = load("res://world/chemistry/chem_drink_visual.gd").new()
	node.name = "ChemDrinkVisual"
	node.pony = pony; node.mode = how
	node.from_level = from_l; node.to_level = to_l
	if seconds > 0.0: node.total = seconds
	node.add_to_group("chem_drink_visuals")
	var parent: Node = pony.get_tree().current_scene if pony.get_tree().current_scene != null else pony.get_tree().root
	parent.add_child(node)
	node.top_level = true
	node.vessel = CONTAINER.build(container, liquid, from_l)
	node.add_child(node.vessel)
	node._hot = temp >= 330.0
	if node._hot: node._steam = CONTAINER.add_steam(node.vessel)
	node._find_hoof()
	# A unicorn lifts it with magic.
	if pony.get("magic") != null and pony.has_method("cast_magic"):
		node._magic = true
		pony.cast_magic(seconds if seconds > 0.0 else 4.0)
		var glow := OmniLight3D.new()
		glow.light_energy = 0.6; glow.omni_range = 0.5; glow.shadow_enabled = false
		var colour: Variant = pony.magic.get("color") if pony.magic != null else null
		glow.light_color = colour if colour is Color else Color(0.7, 0.8, 1.0)
		glow.position = node.vessel.get_meta("rim_local")
		node.vessel.add_child(glow)
	node._place(0.0)
	return node


func _find_hoof() -> void:
	for sk: Node in pony.find_children("*", "Skeleton3D", true, false):
		for name: String in HAND_BONES:
			var bone := (sk as Skeleton3D).find_bone(name)
			if bone >= 0:
				_skeleton = sk as Skeleton3D; _bone = bone
				return


## Stays in her hoof until she gives it away, then drops out of sight.
func release() -> void:
	_releasing = true


func _scale() -> float:
	return clampf(pony.global_basis.get_scale().x, 0.5, 1.5)


func _frame() -> Basis:
	return pony.global_basis.orthonormalized()


func _hoof() -> Vector3:
	if _skeleton != null and is_instance_valid(_skeleton):
		return (_skeleton.global_transform * _skeleton.get_bone_global_pose(_bone)).origin + Vector3.UP * 0.02 * _scale()
	var f := _frame()
	return pony.global_position + (-f.z) * 0.32 * _scale() + f.y * 0.55 * _scale()


func _mouth() -> Vector3:
	var affection: Node = pony.get_node_or_null("Affection")
	if affection != null and affection.has_method("mouth_point"): return affection.mouth_point()
	var f := _frame()
	return pony.global_position + (-f.z) * 0.35 * _scale() + f.y * 0.85 * _scale()


func _process(delta: float) -> void:
	if not is_instance_valid(pony) or not pony.is_inside_tree() or pony.get("sleeping") == true:
		queue_free(); return
	_time += delta
	if _releasing:
		_fade += delta
		if _fade > 0.35: queue_free(); return
	var progress := clampf(_time / total, 0.0, 1.0) if mode == "drink" else 0.0
	_place(progress)
	if mode == "drink" and _time >= total: queue_free()


## Where the vessel is at `progress` (0..1 of a drink; 0 while held).
func _place(progress: float) -> void:
	if vessel == null: return
	var s := _scale() * 1.1
	var frame := _frame()
	var forward := -frame.z
	var up := frame.y
	var hoof := _hoof()
	var rim_local: Vector3 = vessel.get_meta("rim_local")
	# Held at the hoof: the vessel's base rests on it, and bobs a little as she moves.
	var held_basis := frame
	var held_pos := hoof - held_basis * Vector3(0, 0.01 * s, 0)
	var pos := held_pos
	var orient := held_basis
	var level := from_level
	if mode == "drink":
		var lift := smoothstep(0.0, LIFT, progress)
		var lower := smoothstep(SIP_END, 1.0, progress)
		var tilt_amount := smoothstep(LIFT, LIFT + 0.14, progress) * (1.0 - smoothstep(SIP_END - 0.1, SIP_END, progress))
		var tilt := deg_to_rad(52.0) * tilt_amount
		# Small gulps: the tilt pulses a little while she drinks.
		tilt += deg_to_rad(5.0) * sin(progress * 38.0) * tilt_amount
		var axis := up.cross(-forward).normalized()
		var tilted := Basis(axis, tilt) * frame
		var rim_target := _mouth() + forward * 0.045 * s - up * 0.012 * s
		var raised_pos := rim_target - tilted * (rim_local * s)
		var up_mix := lift * (1.0 - lower)
		pos = held_pos.lerp(raised_pos, up_mix)
		orient = held_basis.slerp(tilted, up_mix) if up_mix > 0.0 else held_basis
		level = lerpf(from_level, to_level, smoothstep(LIFT + 0.05, SIP_END, progress))
	global_transform = Transform3D(orient.scaled(Vector3.ONE * s), pos)
	CONTAINER.set_level(vessel, level)
	if _steam != null and is_instance_valid(_steam):
		_steam.emitting = (orient * Vector3.UP).dot(Vector3.UP) > 0.8 and not _releasing
