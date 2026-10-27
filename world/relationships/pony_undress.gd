extends Node
## Taking clothes off a pony on desktop (dev 2026-10-27: "i need a way to take clothes off of her in
## desktop mode"). Look at a pony within reach who wears something and press O: the newest piece
## comes off. A gift from Anon goes back into his briefcase (offer it again to put it back on); her
## own seasonal or show piece stays off for the rest of the season
## (world/characters/accessories/pony_wardrobe.gd take_off). Only the accessories the wardrobe
## dresses her in (scarves, hats, socks, glasses, ties...). A pony who is cross with Anon or asked
## for space steps back instead, as with feeding (hand_feeding.gd), and a sleeping pony is left be.
## The pony hint (player/desktop_interactions.gd) shows "O · Take off her <piece>".
const SFX := preload("res://world/audio/interaction_sounds.gd")
const KEY := KEY_O
const REACH := 2.2
var game: Node

func setup(host: Node) -> void:
	game = host
	add_to_group("pony_undress")

func _wardrobe() -> Node:
	return get_tree().get_first_node_in_group("pony_wardrobe")

func _ready_for_input() -> bool:
	var inventory: Node = game.get("inventory") if game != null else null
	if not is_instance_valid(inventory) or not bool(inventory.get("_desktop")) or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: return false
	if inventory.case == null or inventory.case.visible or (inventory.customizer != null and inventory.customizer.opened): return false
	if inventory.has_meta("desktop_activity_owner") and is_instance_valid(inventory.get_meta("desktop_activity_owner")): return false
	var body: Variant = inventory.get("player_body")
	return not (is_instance_valid(body) and body.get("controls_locked") == true)

## The awake pony in view within reach who wears something Anon can take off. Her head or her
## body under the crosshair both count.
func desktop_target() -> Node3D:
	var wardrobe := _wardrobe()
	if wardrobe == null or not _ready_for_input(): return null
	var camera: Camera3D = game.inventory.camera
	if not is_instance_valid(camera): return null
	var forward := -camera.global_basis.z
	var best: Node3D = null; var best_gap := 0.45
	for pony: Variant in game.mares:
		if not is_instance_valid(pony) or not (pony as Node3D).is_inside_tree() or not (pony as Node3D).is_visible_in_tree() or pony.get("sleeping") == true: continue
		var affection: Node = (pony as Node).get_node_or_null("Affection")
		if affection == null or not affection.has_method("mouth_point"): continue
		if wardrobe.removable(pony).is_empty(): continue
		var mouth: Vector3 = affection.mouth_point()
		for point: Vector3 in [mouth, (pony as Node3D).global_position.lerp(mouth, 0.5)]:
			var to := point - camera.global_position
			var ahead := to.dot(forward)
			if to.length() > REACH or to.length() < 0.1 or ahead <= 0.0: continue
			var gap := (to - forward * ahead).length()
			if gap >= best_gap or not _in_sight(camera, point, pony): continue
			best = pony; best_gap = gap
	return best

## Nothing but her (or nothing) between Anon's eyes and the point.
func _in_sight(camera: Camera3D, point: Vector3, pony: Node3D) -> bool:
	var excluded: Array[RID] = []
	var body: Variant = game.inventory.get("player_body")
	if body is CollisionObject3D: excluded.append((body as CollisionObject3D).get_rid())
	var held: Variant = game.inventory.held.get("desktop")
	if held is CollisionObject3D: excluded.append((held as CollisionObject3D).get_rid())
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(camera.global_position, point, 1, excluded))
	if hit.is_empty(): return true
	var collider: Variant = hit.get("collider")
	return collider is Node and (collider == pony or pony.is_ancestor_of(collider))

## "her scarf" for the next piece O takes off her, "" when there is none.
func next_piece_name(pony: Node3D) -> String:
	var wardrobe := _wardrobe()
	if wardrobe == null or pony == null: return ""
	var rows: Array = wardrobe.removable(pony)
	if rows.is_empty(): return ""
	var name := str(wardrobe.WORN_NAMES.get(rows[0][0], rows[0][0]))
	for article: String in ["a ", "an "]:
		if name.begins_with(article): name = name.substr(article.length()); break
	return "her " + name

## Appended to the desktop pony hint while she is the one O would undress.
func hint_suffix(pony: Node3D) -> String:
	if pony == null or desktop_target() != pony: return ""
	return "   O · Take off " + next_piece_name(pony)

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or (event as InputEventKey).physical_keycode != KEY: return
	var pony := desktop_target()
	if pony == null: return
	get_viewport().set_input_as_handled()
	take_off(pony)

func take_off(pony: Node3D) -> bool:
	var wardrobe := _wardrobe()
	var identity: Resource = pony.get("identity")
	if wardrobe == null or identity == null: return false
	var rows: Array = wardrobe.removable(pony)
	if rows.is_empty(): return false
	var kind := str(rows[0][0]); var gift := str(rows[0][1])
	var pony_id := str(identity.id)
	var bonds: Node = game.world_context.get("player_bonds") if game.world_context != null else null
	if bonds != null:
		var record: Dictionary = bonds.record_for(pony_id)
		if bonds.anger(pony_id) >= 35.0 or Time.get_unix_time_from_system() < float(record.get("cooldowns", {}).get("boundary", 0.0)):
			if pony.has_method("set_action_gaze"): pony.set_action_gaze(null)
			print("[undress] %s steps back from Anon's hand" % pony_id)
			return false
	var inventory: Node = game.inventory
	if not gift.is_empty() and inventory.inventory.grant(gift) < 0:
		inventory.inventory.last_error = "No room in the briefcase for it."; inventory._error()
		return false
	var name := next_piece_name(pony).trim_prefix("her ")
	wardrobe.take_off(pony, kind, gift)
	SFX.play_event(pony, "prop_clothing", {}, pony.get_node("Affection").mouth_point())
	var expressions: Variant = pony.get("expressions")
	if expressions != null and expressions.has_method("fluster"): expressions.fluster(0.6)
	if pony.has_method("set_action_gaze"): pony.set_action_gaze(game._find_camera(game.player))
	var memory := "Anon took off your %s%s." % [name, " and put it back in the briefcase" if not gift.is_empty() else ""]
	game.world_context.record("wardrobe", memory, [pony_id, "player"], [pony_id, "player"])
	print("[undress] Anon took %s off %s%s" % [kind, pony_id, " (gift %s back to the briefcase)" % gift if not gift.is_empty() else ""])
	return true
