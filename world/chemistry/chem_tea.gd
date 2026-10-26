extends Node
## Tea sets (dev 2026-10-26: "figure out whats a teapot and let ais/players spawn mugs of hot
## tea with them... fluttershy keeps trying to offer me tea but ... lacks the mechanical ways").
## The game's teapot is the cottage tea set: a household prop ("cottage-tea-set", shop_items.gd)
## that interiors place on cafe tables (interior_kit.json, group "house_furniture", meta
## "furniture") and that Anon can buy and set down anywhere (a loose item, "goods:cottage-tea-set").
##
## - Anon: look at a tea set within reach and press E: a mug of hot tea (chem_container.gd, 346 K,
##   it cools) goes into his hand (chem_hand.gd): click to drink or offer it.
## - Ponies: [pour_tea] / [pour_tea: TARGET] (pony_action_schema.gd), offered only while a tea set
##   is within reach of her. She walks to it if she has to, pours a mug and drinks it (self) or
##   hands it to TARGET (Anon, or a pony), through the same hand-over as [use_item].
const SET_ID := "cottage-tea-set"
const SET_GOODS := "goods:cottage-tea-set"
const POUR_UNITS := 30.0
const HOT := 346.0
## A tea set this far from a pony lets her offer tea (she walks the rest of the way).
const RANGE := 9.0
## Close enough to pour.
const REACH := 1.6
const WAIT_SECONDS := 30.0
## Anon pours from a set he is looking at within this distance and angle.
const PLAYER_REACH := 2.8
const PLAYER_CONE := 0.9659   # cos 15 degrees

var game: Node
var _sets: Array = []
var _sets_at := -10.0
var _pending: Array = []
var _tick := 0.0
var _label: Label
var _target: Node3D


func setup(host: Node) -> void:
	game = host
	add_to_group("chem_tea")
	var layer := CanvasLayer.new(); layer.layer = 91; add_child(layer)
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_label.position.y -= 150
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", Color("fff0d8"))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 5)
	_label.hide()
	layer.add_child(_label)


## A fresh mug of hot tea, as a bottle (pony_belongings.gd rows).
static func mug() -> Dictionary:
	var bottle := {"dose": {"tea": POUR_UNITS}, "from": "tea_set"}
	bottle.merge(preload("res://world/chemistry/pony_belongings.gd").vessel_now("mug", HOT))
	return bottle


## Every tea set in the world right now (cached for a second).
func sets() -> Array:
	var now := Time.get_ticks_msec() * 0.001
	if now - _sets_at < 1.0: return _sets
	_sets_at = now
	_sets = []
	for node: Node in get_tree().get_nodes_in_group("house_furniture"):
		if node is Node3D and node.has_meta("furniture") and str(node.get_meta("furniture")) == SET_ID and node.is_visible_in_tree():
			_sets.append(node)
	# Ones Anon bought and set down: loose items with the shop's id.
	var inventory: Node = game.get("inventory") if is_instance_valid(game) else null
	if inventory != null and "loose" in inventory and inventory.loose is Dictionary:
		for item: Variant in inventory.loose.values():
			if is_instance_valid(item) and item is Node3D and str((item as Node).get_meta("item_id", "")) == SET_GOODS and (item as Node3D).is_visible_in_tree():
				_sets.append(item)
	return _sets


## The tea set nearest `point` within `limit`, or null.
func nearest(point: Vector3, limit: float) -> Node3D:
	var best: Node3D = null; var best_distance := limit
	for node: Variant in sets():
		if not is_instance_valid(node): continue
		var distance := point.distance_to((node as Node3D).global_position)
		if distance < best_distance: best_distance = distance; best = node
	return best


## Whether a pony can offer tea right now (pony_action_coordinator.gd lists [pour_tea] only then).
func sets_near(actor: Node3D) -> bool:
	return is_instance_valid(actor) and nearest(actor.global_position, RANGE) != null


# ------------------------------------------------------------------ Anon

func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0: return
	_tick = 0.15
	_target = _looked_at()
	if _target != null:
		_label.text = "E · Pour a mug of hot tea"
		_label.show()
	else:
		_label.hide()


func _looked_at() -> Node3D:
	if not is_instance_valid(game) or not is_instance_valid(game.get("player")): return null
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: return null
	var player: Variant = game.player
	if "controls_locked" in player and player.controls_locked: return null
	var hand: Node = get_tree().get_first_node_in_group("chem_hand")
	if hand != null and not hand.held.is_empty(): return null
	var camera := game._find_camera(game.player) as Node3D
	if camera == null: return null
	var best: Node3D = null; var best_dot := PLAYER_CONE
	for node: Variant in sets():
		if not is_instance_valid(node): continue
		var to: Vector3 = (node as Node3D).global_position - camera.global_position
		var distance := to.length()
		if distance > PLAYER_REACH or distance < 0.05: continue
		# Up close the cone widens: a set on the table under your nose is still "looked at".
		var dot := to.normalized().dot(-camera.global_basis.z)
		if distance < 0.9: dot = maxf(dot, 0.97)
		if dot > best_dot: best_dot = dot; best = node
	return best


func _input(event: InputEvent) -> void:
	if _target == null or not is_instance_valid(_target): return
	if not event is InputEventKey or not event.pressed or event.echo: return
	if (event as InputEventKey).physical_keycode != KEY_E: return
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed or event.shift_pressed: return
	if get_viewport().gui_get_focus_owner() is LineEdit: return
	get_viewport().set_input_as_handled()
	_pour_for_player()


func _pour_for_player() -> void:
	var bottle := mug()
	var hand: Node = get_tree().get_first_node_in_group("chem_hand")
	if hand != null and hand.held.is_empty():
		hand.hold(bottle)
		hand.note("You pour a mug of hot tea.")
	else:
		# No free hand (or no hand in VR): it goes to the saved bottles.
		var belongings: Node = get_tree().get_first_node_in_group("pony_belongings")
		if belongings == null: return
		var bottles: Array = belongings.player_bottles()
		bottles.append(bottle)
		belongings.set_player_bottles(bottles)
	_label.hide(); _target = null
	print("[tea] Anon poured a mug of hot tea")


# ------------------------------------------------------------------ ponies

## `user` (a pony id) pours tea: [pour_tea: self | player | PONY_ID]. Walks to the tea set first
## if she is not beside it; then pours and drinks it herself, or hands it over (pony_belongings.gd).
func pour_for(user: String, actor: Node3D, action: Dictionary, targets: Dictionary, executor: Node) -> void:
	var set := nearest(actor.global_position, RANGE)
	if set == null: executor._report(action, "failed", "There is no tea set within reach"); return
	if actor.global_position.distance_to(set.global_position) > REACH:
		_pending.append({"user": user, "actor": weakref(actor), "set": weakref(set), "action": action, "targets": targets,
			"executor": weakref(executor), "until": Time.get_ticks_msec() + int(WAIT_SECONDS * 1000.0)})
		executor.submit([{"id": str(action.id) + "-tea", "type": "approach", "target_id": "tea_set", "distance_m": 1.0}],
			{"tea_set": set}, int(executor.get("_latest_turn")))
		executor._report(action, "accepted", "Walking to the tea set")
		return
	_pour(user, actor, action, targets, executor, set)


func _pour(user: String, actor: Node3D, action: Dictionary, targets: Dictionary, executor: Node, set: Node3D) -> void:
	var belongings: Node = get_tree().get_first_node_in_group("pony_belongings")
	if belongings == null: executor._report(action, "failed", "Nothing to pour into"); return
	var bottle := mug()
	if not belongings.add_item(user, bottle.dose, user, bottle):
		executor._report(action, "failed", "Your hooves are full; there is nowhere to put a mug"); return
	var items: Array = belongings.items_for(user)
	var key: String = str(items[-1].key)
	# It comes off the tea set, not out of her side.
	belongings.origins[user + "/" + key] = set.global_position + Vector3.UP * 0.3
	var use := action.duplicate(true)
	use.item_id = key
	use.recipient_id = str(action.get("recipient_id", "self"))
	use.mode = ""
	print("[tea] %s pours a mug of hot tea for %s" % [user, use.recipient_id])
	belongings.use(user, actor, use, targets, executor)


func _physics_process(delta: float) -> void:
	if _pending.is_empty(): return
	var now := Time.get_ticks_msec()
	for entry: Dictionary in _pending.duplicate():
		var actor: Node3D = entry.actor.get_ref()
		var set: Node3D = entry.set.get_ref()
		var executor: Node = entry.executor.get_ref()
		if not is_instance_valid(executor): _pending.erase(entry); continue
		if not is_instance_valid(actor) or not is_instance_valid(set):
			_pending.erase(entry); executor._report(entry.action, "failed", "The tea set is gone"); continue
		if actor.global_position.distance_to(set.global_position) <= REACH + 0.4:
			_pending.erase(entry)
			_pour(entry.user, actor, entry.action, entry.targets, executor, set)
		elif now > int(entry.until):
			_pending.erase(entry); executor._report(entry.action, "failed", "Could not get to the tea set")
