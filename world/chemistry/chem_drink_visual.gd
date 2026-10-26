extends Node3D
## A pony holding and drinking from a chemistry vessel (dev 2026-10-26: "have the pony be
## actually able to hold them and visually drink them"). The vessel (chem_container.gd) comes out
## of her side where she keeps it (or is handed over by whoever gave it), sits in her front hoof,
## lifts to her mouth, tilts while the liquid sinks, goes back down and is put away. Her foreleg
## reaches with it (pony_hoof_hold.gd reach/follow, as far as her joints allow). A unicorn's horn
## lights and the vessel glows in her magic colour; steam rises from a hot drink. Visual only:
## what the drink does is pony_potion_effects.gd.
##
## hold(): the vessel stays in her hoof until release() (a pony walking over to hand something
##   to somepony, pony_belongings.gd).
## drink(): the whole thing, then it frees itself. `origin` (a world point): it was handed to her
##   from there. `pocket`: she took it out of her own things.
## receive(): she is given something to keep: it comes from `origin` to her hoof, and she tucks
##   it away.
const CONTAINER := preload("res://world/chemistry/chem_container.gd")
const CATALOG := preload("res://world/chemistry/chem_catalog.gd")
const HAND_BONES := ["pony_hand_R", "pony_hand_L"]
## Fractions of one drink: taken out, lifted, sipped, lowered, put away.
const TAKE_END := 0.14
const LIFT_END := 0.34
const SIP_END := 0.78
const LOWER_END := 0.9
## The foreleg reaches with the cup (the lab's checkbox turns this off if a rig misbehaves).
static var legs_move := true

var pony: Node3D
var vessel: Node3D
var mode := "hold"
var total := 4.2
var from_level := 1.0
var to_level := 0.0
var origin := Vector3.INF
var pocket := false
var _time := 0.0
var _skeleton: Skeleton3D
var _bone := -1
var _steam: CPUParticles3D
var _hot := false
var _magic := false
var _releasing := false
var _fade := 0.0
var _rest_local := Vector3.INF   # her hoof at rest, in her own frame (set when a drink starts)
var _reaching := false
var _side := 1


## She holds `container` until release().
static func hold(host: Node, pony: Node3D, container: String, liquid: Color, fraction := 1.0, temp := CATALOG.ROOM) -> Node3D:
	return _start(host, pony, container, liquid, fraction, temp, "hold", 0.0, fraction, fraction, Vector3.INF, false)


## She is handed a vessel to keep (pony_belongings.gd keep()).
static func receive(host: Node, pony: Node3D, container: String, liquid: Color, fraction := 1.0, temp := CATALOG.ROOM, origin := Vector3.INF) -> Node3D:
	return _start(host, pony, container, liquid, fraction, temp, "receive", 2.2, fraction, fraction, origin, true)


## She drinks from `fraction` down to `leave`. `seconds` for the lot.
static func drink(host: Node, pony: Node3D, container: String, liquid: Color, fraction := 1.0, temp := CATALOG.ROOM, seconds := 4.2, leave := 0.0, origin := Vector3.INF, pocket := false) -> Node3D:
	return _start(host, pony, container, liquid, fraction, temp, "drink", seconds, fraction, leave, origin, pocket)


static func _start(host: Node, pony: Node3D, container: String, liquid: Color, fraction: float, temp: float, how: String, seconds: float, from_l: float, to_l: float, from_point: Vector3, from_pocket: bool) -> Node3D:
	if not is_instance_valid(pony) or not pony.is_inside_tree(): return null
	# One at a time per pony: a new one replaces the old.
	for old: Node in pony.get_tree().get_nodes_in_group("chem_drink_visuals"):
		if old.get("pony") == pony: old.queue_free()
	var node: Node3D = load("res://world/chemistry/chem_drink_visual.gd").new()
	node.name = "ChemDrinkVisual"
	node.pony = pony; node.mode = how
	node.from_level = from_l; node.to_level = to_l
	node.origin = from_point; node.pocket = from_pocket
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
	node._rest_local = pony.global_transform.affine_inverse() * node._hoof()
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
	node.reset_physics_interpolation()
	return node


func _find_hoof() -> void:
	for sk: Node in pony.find_children("*", "Skeleton3D", true, false):
		for i in HAND_BONES.size():
			var bone := (sk as Skeleton3D).find_bone(HAND_BONES[i])
			if bone >= 0:
				_skeleton = sk as Skeleton3D; _bone = bone
				_side = 1 if i == 0 else 0
				return


## Stays in her hoof until she gives it away, then drops out of sight.
func release() -> void:
	_releasing = true


func _scale() -> float:
	return clampf(pony.global_basis.get_scale().x, 0.5, 1.5)


func _frame() -> Basis:
	return pony.global_basis.orthonormalized()


## Where her hoof is now (a held vessel follows it as she walks).
func _hoof() -> Vector3:
	if _skeleton != null and is_instance_valid(_skeleton):
		return (_skeleton.global_transform * _skeleton.get_bone_global_pose(_bone)).origin + Vector3.UP * 0.02 * _scale()
	var f := _frame()
	return pony.global_position + (-f.z) * 0.32 * _scale() + f.y * 0.55 * _scale()


## Where it rests while she drinks: her hoof's resting place in her own frame, so the reaching
## leg does not chase the cup it is carrying.
func _rest() -> Vector3:
	return pony.global_transform * _rest_local if _rest_local.is_finite() else _hoof()


## Where she keeps her things: her right side, behind the withers.
func _pocket() -> Vector3:
	var f := _frame()
	return pony.global_position + f.y * 0.7 * _scale() + f.x * 0.18 * _scale() + f.z * 0.05 * _scale()


func _mouth() -> Vector3:
	var affection: Node = pony.get_node_or_null("Affection")
	if affection != null and affection.has_method("mouth_point"): return affection.mouth_point()
	var f := _frame()
	return pony.global_position + (-f.z) * 0.35 * _scale() + f.y * 0.85 * _scale()


## In the physics step, like the pony: the engine then smooths the vessel between steps exactly as it
## smooths her, so it does not stutter beside her while she walks.
func _physics_process(delta: float) -> void:
	if not is_instance_valid(pony) or not pony.is_inside_tree() or pony.get("sleeping") == true:
		_let_go(); queue_free(); return
	_time += delta
	if _releasing:
		_fade += delta
		if _fade > 0.35: queue_free(); return
	var timed := mode != "hold"
	var progress := clampf(_time / total, 0.0, 1.0) if timed else 0.0
	_place(progress)
	if timed and _time >= total: queue_free()


func _exit_tree() -> void:
	_let_go()


func _let_go() -> void:
	if _reaching and is_instance_valid(pony) and pony.get("hoof_hold") != null and pony.hoof_hold.has_method("gesturing") and pony.hoof_hold.gesturing():
		pony.hoof_hold.release()
	_reaching = false


## Where the vessel is at `progress` (0..1 of a drink; 0 while held).
func _place(progress: float) -> void:
	if vessel == null: return
	var s := _scale() * 1.1
	var frame := _frame()
	var forward := -frame.z
	var up := frame.y
	var rim_local: Vector3 = vessel.get_meta("rim_local")
	var drinking := mode == "drink"
	var receiving := mode == "receive"
	# Resting in her hoof: followed live while only held, from her resting hoof while drinking.
	var hoof := _rest() if drinking or receiving else _hoof()
	var rest_pos := hoof - frame * Vector3(0, 0.01 * s, 0)
	var size := 1.0
	var pos := rest_pos
	var orient := frame
	var level := from_level
	if receiving:
		# Given to her: it travels from the giver to her hoof, she holds it a moment, tucks it away.
		var arrive := smoothstep(0.0, 0.35, progress)
		var tuck := smoothstep(0.62, 1.0, progress)
		var from_there := origin if origin.is_finite() else _pocket()
		pos = from_there.lerp(rest_pos, arrive).lerp(_pocket(), tuck)
		size = lerpf(1.0, 0.15, tuck)
	elif drinking:
		var take := smoothstep(0.0, TAKE_END, progress)
		var lift := smoothstep(TAKE_END, LIFT_END, progress) * (1.0 - smoothstep(SIP_END, LOWER_END, progress))
		var stow := smoothstep(LOWER_END, 1.0, progress)
		# Taken out of her side, or handed over from where it was given; put away after.
		var start := origin if origin.is_finite() else (_pocket() if pocket else rest_pos)
		var away := _pocket() if pocket else (origin if origin.is_finite() else rest_pos)
		if pocket: size = lerpf(0.15, 1.0, take) * lerpf(1.0, 0.15, stow)
		var base := start.lerp(rest_pos, take).lerp(away, stow)
		var tilt_amount := smoothstep(LIFT_END - 0.04, LIFT_END + 0.08, progress) * (1.0 - smoothstep(SIP_END - 0.08, SIP_END, progress))
		var tilt := deg_to_rad(52.0) * tilt_amount
		# Small gulps: the tilt pulses a little while she drinks.
		tilt += deg_to_rad(5.0) * sin(progress * 38.0) * tilt_amount
		var axis := up.cross(-forward).normalized()
		var tilted := Basis(axis, tilt) * frame
		var rim_target := _mouth() + forward * 0.045 * s - up * 0.012 * s
		var raised_pos := rim_target - tilted * (rim_local * s)
		pos = base.lerp(raised_pos, lift)
		orient = frame.slerp(tilted, lift) if lift > 0.0 else frame
		level = lerpf(from_level, to_level, smoothstep(LIFT_END, SIP_END, progress))
		_reach(progress, pos, orient, s)
	global_transform = Transform3D(orient.scaled(Vector3.ONE * s * size), pos)
	CONTAINER.set_level(vessel, level)
	if _steam != null and is_instance_valid(_steam):
		_steam.emitting = (orient * Vector3.UP).dot(Vector3.UP) > 0.8 and not _releasing


## Her foreleg follows the vessel from the moment she has it until it is being put away.
func _reach(progress: float, pos: Vector3, orient: Basis, s: float) -> void:
	if not legs_move or pony.get("hoof_hold") == null or not pony.hoof_hold.has_method("reach"): return
	var hold_on: bool = progress >= TAKE_END * 0.7 and progress < LOWER_END
	var grip := pos + orient * Vector3(0, CONTAINER.height(str(vessel.get_meta("type"))) * 0.4 * s, 0)
	if hold_on and not _reaching:
		_reaching = pony.hoof_hold.reach(_side, total, grip, true)
	elif hold_on and _reaching:
		pony.hoof_hold.follow(grip)
	elif not hold_on and _reaching:
		_let_go()
