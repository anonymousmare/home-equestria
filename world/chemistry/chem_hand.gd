extends Node
## Anon holding a chemistry vessel (dev 2026-10-26: "i'd like to be able to give it to myself as
## an item"). The lab's "Hold it" puts a bottle in his hand (a vessel at the lower right of the
## view, chem_container.gd). Desktop controls while it is held:
##   Left click           drink it (the vessel tips up, the liquid sinks); looking at a pony's face
##                        within reach: give it to her to drink instead
##   Right click          looking at a pony: give it to her to keep for later; else put it away
## A held bottle is not an inventory item: it lives in the world's saved bottle list
## (pony_belongings.gd) until held, and goes back there when put away.
const CONTAINER := preload("res://world/chemistry/chem_container.gd")
const CATALOG := preload("res://world/chemistry/chem_catalog.gd")
const EFFECTS := preload("res://world/chemistry/pony_potion_effects.gd")
const PLAYER := preload("res://world/chemistry/player_potion_effects.gd")
const BELONGINGS := preload("res://world/chemistry/pony_belongings.gd")
const HOLD_POSITION := Vector3(0.24, -0.2, -0.45)
const HOLD_TURN := Vector3(-8.0, 22.0, 8.0)
const DRINK_POSITION := Vector3(0.03, -0.23, -0.31)
const DRINK_SECONDS := 2.0
## A pony's mouth this close to where you look is offered the bottle.
const REACH := 1.8
const OFF_AXIS := 0.4

var game: Node
var held: Dictionary = {}
var _vessel: Node3D
var _steam: CPUParticles3D
var _drinking := false
var _time := 0.0
var _target: Node3D
var _scan := 0.0
var _label: Label
var _note := ""
var _note_until := 0.0


func setup(host: Node) -> void:
	game = host
	add_to_group("chem_hand")
	var layer := CanvasLayer.new(); layer.layer = 92; add_child(layer)
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_label.position.y -= 70
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", Color("ffe9fb"))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 5)
	_label.hide()
	layer.add_child(_label)
	set_process(false)


func _camera() -> Node3D:
	return game._find_camera(game.player) if is_instance_valid(game) and is_instance_valid(game.get("player")) else null


## `bottle`: {"dose", "from", "container", "temp", "t0"} (pony_belongings.gd).
func hold(bottle: Dictionary) -> void:
	if not held.is_empty(): put_away()
	var camera := _camera()
	if camera == null or bottle.is_empty(): return
	held = bottle
	var container := CONTAINER.valid(str(bottle.get("container", CONTAINER.DEFAULT)))
	var fraction := clampf(BELONGINGS.total_of(bottle.dose) / CONTAINER.capacity(container), 0.1, 1.0)
	_vessel = CONTAINER.build(container, EFFECTS._mix_color(bottle.dose), fraction)
	camera.add_child(_vessel)
	_vessel.position = HOLD_POSITION
	_vessel.rotation_degrees = HOLD_TURN
	_steam = CONTAINER.add_steam(_vessel) if BELONGINGS.temp_now(bottle) >= 330.0 else null
	_drinking = false
	_time = 0.0
	set_process(true)
	_show_hint()


func _show_hint() -> void:
	var temp := BELONGINGS.temp_now(held)
	var main := BELONGINGS.main_of(held.dose)
	var text := "%s, %s" % [CATALOG.name_of(main), CATALOG.temp_words(temp)]
	if _target != null and is_instance_valid(_target):
		text += "\nClick: give %s a drink · Right-click: give it to her to keep" % EFFECTS.display_name(_target)
	else:
		text += "\nClick: drink · Right-click: put it away · Look at a pony to offer it"
	if Time.get_ticks_msec() * 0.001 < _note_until: text = _note + "\n" + text
	_label.text = text
	_label.show()


func put_away() -> void:
	if held.is_empty(): return
	var belongings: Node = get_tree().get_first_node_in_group("pony_belongings")
	if belongings != null:
		var bottles: Array = belongings.player_bottles()
		bottles.append(held)
		belongings.set_player_bottles(bottles)
		var lab: Node = game.get_node_or_null("ChemLab")
		if lab != null and lab.has_method("refresh_bottles"): lab.refresh_bottles()
	_clear()


func _clear() -> void:
	held = {}
	if is_instance_valid(_vessel): _vessel.queue_free()
	_vessel = null; _steam = null; _drinking = false; _target = null
	_label.hide()
	set_process(false)


func _say(text: String) -> void:
	_note = text
	_note_until = Time.get_ticks_msec() * 0.001 + 6.0


## The pony whose face you are looking at, within arm's reach (as in hand_feeding.gd).
func _find_target() -> Node3D:
	var camera := _camera() as Camera3D
	if camera == null: return null
	var mares: Array = game.get("mares") if game.get("mares") is Array else []
	var best: Node3D = null; var best_gap := OFF_AXIS
	for pony: Variant in mares:
		if not is_instance_valid(pony) or not (pony as Node3D).is_inside_tree() or not (pony as Node3D).is_visible_in_tree() or bool(pony.get("sleeping")): continue
		var affection: Node = (pony as Node).get_node_or_null("Affection")
		if affection == null or not affection.has_method("mouth_point"): continue
		var to: Vector3 = affection.mouth_point() - camera.global_position
		var ahead := to.dot(-camera.global_basis.z)
		if to.length() > REACH or to.length() < 0.1 or ahead <= 0.0: continue
		var off := (to - (-camera.global_basis.z) * ahead).length()
		if off >= best_gap: continue
		best = pony; best_gap = off
	return best


func _process(delta: float) -> void:
	if held.is_empty() or not is_instance_valid(_vessel):
		_clear(); return
	if _drinking:
		_time += delta
		var p := clampf(_time / DRINK_SECONDS, 0.0, 1.0)
		var lift := smoothstep(0.0, 0.25, p) * (1.0 - smoothstep(0.88, 1.0, p))
		var tilt := smoothstep(0.2, 0.45, p) * (1.0 - smoothstep(0.82, 0.92, p))
		_vessel.position = HOLD_POSITION.lerp(DRINK_POSITION, lift)
		var turn := HOLD_TURN.lerp(Vector3(68.0, 0.0, 0.0), tilt)
		turn.x += 4.0 * sin(p * 30.0) * tilt
		_vessel.rotation_degrees = turn
		CONTAINER.set_level(_vessel, 1.0 - smoothstep(0.3, 0.85, p))
		if is_instance_valid(_steam): _steam.emitting = tilt < 0.2
		if p >= 1.0: _finish_drink()
		return
	_scan -= delta
	if _scan <= 0.0:
		_scan = 0.12
		_target = _find_target()
		_show_hint()
	# A gentle sway so the vessel feels held.
	_vessel.position.y = HOLD_POSITION.y + sin(Time.get_ticks_msec() * 0.0021) * 0.003


func _finish_drink() -> void:
	var result: Dictionary = PLAYER.drink(game, held.dose, str(held.get("from", "player")), held)
	_say(str(result.text))
	if bool(result.ok): _clear()
	else:
		_drinking = false; _time = 0.0
		_vessel.position = HOLD_POSITION; _vessel.rotation_degrees = HOLD_TURN
		CONTAINER.set_level(_vessel, clampf(BELONGINGS.total_of(held.dose) / CONTAINER.capacity(str(held.get("container", CONTAINER.DEFAULT))), 0.1, 1.0))


func _input(event: InputEvent) -> void:
	if held.is_empty() or _drinking or not event is InputEventMouseButton or not event.pressed: return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: return
	var player: Variant = game.get("player")
	if is_instance_valid(player) and "controls_locked" in player and player.controls_locked: return
	var click := event as InputEventMouseButton
	if click.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		if _target != null and is_instance_valid(_target):
			var result: Dictionary = EFFECTS.give(game, _target, held.dose, "player", false, _camera(), held)
			_say(str(result.text))
			if bool(result.ok): _clear()
			return
		var problem := PLAYER.check(held.dose, held)
		if problem != "": _say(problem); return
		_drinking = true; _time = 0.0
	elif click.button_index == MOUSE_BUTTON_RIGHT:
		get_viewport().set_input_as_handled()
		if _target != null and is_instance_valid(_target):
			var belongings: Node = get_tree().get_first_node_in_group("pony_belongings")
			if belongings == null: return
			var result: Dictionary = belongings.keep(_target, held.dose, "player", held)
			_say(str(result.text))
			if bool(result.ok): _clear()
		else:
			_say("You put it away.")
			put_away()
			_note_until = 0.0


func _exit_tree() -> void:
	if is_instance_valid(_vessel): _vessel.queue_free()
