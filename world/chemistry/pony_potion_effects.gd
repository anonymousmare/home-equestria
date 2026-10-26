extends Node
## What a pony feels after drinking something Anon brewed (world/chemistry/chem_lab_gui.gd,
## dev 2026-10-26: "i'd like to be able to give the ponies potions"), from his hoof or from
## another pony's (pony_belongings.gd: a bottle she kept and gave on, maybe slipped in secretly). One of these rides on each
## pony who has drunk something, as a child named PotionEffects, while anything is active.
##
## - Her AI knows: the situation block carries the "potion_context" meta (director_prompts.gd),
##   she reacts to the drink right away ("potion:<id>:<giver>:<secret>" physical reaction,
##   director_contacts.gd),
##   and it is remembered (a world event when given, another when it wears off).
## - The six whimsical potions show: a soft glow in the potion's colour around her, love
##   potion flusters, invisibility hides every mesh she has (render layers 0) until it ends.
## - She refuses what is not a drink (acids, metals, cleaners, ...), fillies refuse adult
##   brews, and a pony who is cross with Anon or asked for space turns her head away.
const CATALOG := preload("res://world/chemistry/chem_catalog.gd")
const SFX := preload("res://world/audio/interaction_sounds.gd")
const CONTAINER := preload("res://world/chemistry/chem_container.gd")
const DRINK := preload("res://world/chemistry/chem_drink_visual.gd")
const META := "potion_context"
## Below this many units a sip does nothing.
const MIN_UNITS := 1.0
## Refused when this share of the bottle is not drinkable.
const UNDRINKABLE_SHARE := 0.2
const TICK := 0.25

var game: Node
var pony: Node3D
var active: Dictionary = {}   # reagent id -> {"until": seconds, "units": float}
var _light: OmniLight3D
var _hidden: Dictionary = {}  # GeometryInstance3D instance id -> [node, original layers]
var _tick := 0.0
var _fluster_wait := 3.0


static func pony_id(pony: Node) -> String:
	var id := str(pony.get_meta("relationship_id", ""))
	if id.is_empty() and pony.get("identity") != null: id = str(pony.identity.id)
	return id


static func display_name(pony: Node) -> String:
	if pony.get("identity") != null: return str(pony.identity.display_name)
	return str(pony.name)


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Offers `dose` ({reagent id: units}, one bottle) to `pony` to drink now. `giver` is "player"
## (Anon) or the id of the pony handing it over (pony_belongings.gd [use_item]); `secret`: slipped
## into her drink, so she does not know what it was. Returns {"ok": bool, "text": String}.
## `info`: the vessel it came in ("container", "temp" K, "t0" unix time it was that warm); a hot
## drink she holds, sips and tastes, a scalding one she will not drink.
static func give(game: Node, pony: Node3D, dose: Dictionary, giver := "player", secret := false, giver_node: Node3D = null, info := {}) -> Dictionary:
	var who := display_name(pony)
	var from := "yourself" if giver == pony_id(pony) else giver_name(game, giver)
	var units := 0.0
	var undrinkable := 0.0
	var adult := false
	var main := ""; var most := 0.0
	for id: String in dose:
		var u := float(dose[id])
		units += u
		if CATALOG.drink_of(id) == "no": undrinkable += u
		if bool(CATALOG.reagent(id).get("adult", false)) and u >= MIN_UNITS: adult = true
		if u > most: most = u; main = id
	if units < MIN_UNITS: return {"ok": false, "text": "The bottle is empty."}
	if bool(pony.get("sleeping")): return {"ok": false, "text": "%s is asleep." % who}
	var container := CONTAINER.valid(str(info.get("container", CONTAINER.DEFAULT)))
	var temp := CATALOG.cooled(float(info.get("temp", CATALOG.ROOM)), float(info.get("t0", 0.0)), Time.get_unix_time_from_system())
	var warmth := CATALOG.temp_words(temp)
	var identity: Resource = pony.get("identity")
	var filly: bool = identity != null and bool(identity.get("filly"))
	var id := pony_id(pony)
	var context: Node = game.get("world_context") if game != null else null
	var bonds: Node = context.get("player_bonds") if context != null else null
	var witnesses: Array = [id, giver]
	if undrinkable / units >= UNDRINKABLE_SHARE:
		# Slipped in or not, it tastes wrong at the first sip.
		var names := _names(dose, "no")
		if pony.has_signal("physical_reaction"): pony.emit_signal("physical_reaction", "potion_refused:%s:%s" % [names, giver])
		if context != null and id != "":
			context.record("gift", "%s offered you a bottle of %s to drink. That is not something to drink, so you refused." % [from, names], witnesses, witnesses)
		return {"ok": false, "text": "%s sniffs the %s and pushes it away. Not a drink!" % [who, names]}
	if filly and adult: return {"ok": false, "text": "%s is a filly: not for her." % who}
	if temp >= CATALOG.SCALDING:
		var hot_names := _names(dose, "")
		if pony.has_signal("physical_reaction"): pony.emit_signal("physical_reaction", "potion_toohot:%s:%s" % [hot_names, giver])
		if context != null and id != "":
			context.record("gift", "%s offered you a %s of %s, %s. It was far too hot to drink, so you did not." % [from, CONTAINER.noun(container), hot_names, warmth], witnesses, witnesses)
		return {"ok": false, "text": "%s pulls back: the %s is %s." % [who, hot_names, warmth]}
	if giver == "player" and bonds != null and id != "" and not filly:
		var record: Dictionary = bonds.record_for(id)
		if bonds.anger(id) >= 35.0 or Time.get_unix_time_from_system() < float(record.get("cooldowns", {}).get("boundary", 0.0)):
			if pony.has_method("set_action_gaze"): pony.set_action_gaze(null)
			return {"ok": false, "text": "%s turns her head away." % who}
	var effects: Node = pony.get_node_or_null("PotionEffects")
	if effects == null:
		effects = load("res://world/chemistry/pony_potion_effects.gd").new()
		effects.name = "PotionEffects"
		effects.game = game; effects.pony = pony
		pony.add_child(effects)
	var felt: PackedStringArray = []
	var mismatch := CATALOG.serve_note(main, temp)
	for reagent: String in dose:
		if float(dose[reagent]) < MIN_UNITS or CATALOG.drink_of(reagent) == "no": continue
		effects.add(reagent, float(dose[reagent]), from, secret)
		felt.append(str(CATALOG.reagent(reagent).get("felt", CATALOG.name_of(reagent).to_lower())))
	var mouth: Vector3 = pony.get_node("Affection").mouth_point() if pony.get_node_or_null("Affection") != null else pony.global_position + Vector3.UP
	SFX.play_event(pony, "prop_sip", {"intensity": 0.8}, mouth)
	if giver_node == null and giver == "player" and game.has_method("_find_camera"): giver_node = game._find_camera(game.player)
	# Where it comes from: her own things, or the hand of whoever gave it (Anon's view, or a pony).
	var pocket := giver == id
	var from_point := Vector3.INF
	var given_from: Variant = info.get("origin")
	if given_from is Vector3 and (given_from as Vector3).is_finite():
		# Poured from a tea set: it comes off the set, not out of her side.
		from_point = given_from; pocket = false
	elif not pocket and giver_node != null and is_instance_valid(giver_node):
		from_point = giver_node.global_position + (-giver_node.global_basis.z * 0.45 + Vector3.DOWN * 0.25 if giver == "player" else Vector3.UP * 0.7)
	DRINK.drink(game, pony, container, _mix_color(dose), clampf(units / CONTAINER.capacity(container), 0.15, 1.0), temp, 4.2, 0.0, from_point, pocket)
	if pony.has_method("set_action_gaze") and giver_node != null: pony.set_action_gaze(giver_node)
	if pony.has_signal("physical_reaction"): pony.emit_signal("physical_reaction", "potion:%s:%s:%s:%s" % [main, giver, "secret" if secret else "", warmth.replace(" ", "_")])
	if context != null and id != "":
		var drank := ("%s gave you something to drink and you drank it, not knowing what was in it" % from) if secret else ("%s gave you a %s of %s and you drank it" % [from, CONTAINER.noun(container), _names(dose, "")])
		if giver == id: drank = "You drank your %s of %s" % [CONTAINER.noun(container), _names(dose, "")]
		var taste := " It was %s" % warmth + (" (" + mismatch + ")" if mismatch != "" else "") + "."
		context.record("gift", "%s.%s You felt %s." % [drank, taste, "; ".join(felt)], [id], witnesses)
		if giver != "player" and giver != id and not secret:
			context.record("gift", "You gave %s a %s of %s to drink." % [who, CONTAINER.noun(container), _names(dose, "")], [giver], witnesses)
		if giver == "player" and bonds != null: bonds.experience(id, "gift", "potion_%d" % Time.get_ticks_usec())
	print("[chemistry] %s drank %.0fu (%s) from %s%s" % [id, units, _names(dose, ""), giver, " secretly" if secret else ""])
	return {"ok": true, "text": "%s drinks the %s." % [who, _names(dose, "")]}


## Where a giver's hand is: Anon's view (the camera), or a pony's chest. INF when unknown.
static func hand_point(game: Node, giver: String) -> Vector3:
	if giver == "player":
		var camera: Node3D = game._find_camera(game.player) if game.has_method("_find_camera") and is_instance_valid(game.get("player")) else null
		return camera.global_position + (-camera.global_basis.z * 0.45 + Vector3.DOWN * 0.25) if camera != null else Vector3.INF
	var mares: Array = game.get("mares") if game.get("mares") is Array else []
	for pony: Variant in mares:
		if is_instance_valid(pony) and pony_id(pony) == giver: return (pony as Node3D).global_position + Vector3.UP * 0.7
	return Vector3.INF


## The mixed colour of a dose, weighted by units.
static func _mix_color(dose: Dictionary) -> Color:
	var whole := 0.0
	for id: String in dose: whole += float(dose[id])
	if whole <= 0.0: return Color(0.8, 0.9, 1.0)
	var mix := Color(0, 0, 0)
	for id: String in dose:
		var c := CATALOG.color_of(id); var w := float(dose[id]) / whole
		mix.r += c.r * w; mix.g += c.g * w; mix.b += c.b * w
	return mix


## "Anon", or a pony's own name from her id.
static func giver_name(game: Node, giver: String) -> String:
	if giver == "player": return "Anon"
	var mares: Array = game.get("mares") if game != null and game.get("mares") is Array else []
	for pony: Variant in mares:
		if is_instance_valid(pony) and pony_id(pony) == giver: return display_name(pony)
	return giver.replace("_", " ").capitalize()


## "love potion and sugar": the names of the reagents in a dose, largest first.
static func _names(dose: Dictionary, only_drink: String) -> String:
	var ids: Array = dose.keys().filter(func(r: String) -> bool:
		return float(dose[r]) >= MIN_UNITS * 0.5 and (only_drink == "" or CATALOG.drink_of(r) == only_drink))
	ids.sort_custom(func(a: String, b: String) -> bool: return float(dose[a]) > float(dose[b]))
	var names: PackedStringArray = []
	for r: String in ids.slice(0, 3): names.append(CATALOG.name_of(r).to_lower())
	return " and ".join(names) if not names.is_empty() else "mixture"


## Ten units last the reagent's "minutes"; half a dose or less half as long, at most three times.
func add(id: String, units: float, from := "Anon", secret := false) -> void:
	var seconds := float(CATALOG.reagent(id).get("minutes", 1)) * 60.0 * clampf(units / 10.0, 0.5, 3.0)
	var row: Dictionary = active.get(id, {"until": _now(), "units": 0.0})
	row.from = from; row.secret = secret
	row.until = maxf(float(row.until), _now()) + seconds
	row.units = float(row.units) + units
	active[id] = row
	if id == "love_potion" and pony.get("expressions") != null and pony.expressions.has_method("fluster"): pony.expressions.fluster(1.5)
	_tick = TICK


## Clears everything at once (the lab window's "cure" button).
func cure() -> void:
	for id: String in active.keys(): active[id].until = 0.0
	_tick = TICK


func _process(delta: float) -> void:
	if not is_instance_valid(pony): queue_free(); return
	_love(delta)
	_tick += delta
	if _tick < TICK: return
	_tick = 0.0
	var now := _now()
	for id: String in active.keys():
		if now < float(active[id].until): continue
		var row: Dictionary = active[id]
		active.erase(id)
		_wore_off(id, row)
	_update_light()
	_update_invisibility()
	_update_context()
	if active.is_empty(): queue_free()


func _exit_tree() -> void:
	_restore_visibility()
	if is_instance_valid(pony) and pony.has_meta(META): pony.remove_meta(META)


func _love(delta: float) -> void:
	if not active.has("love_potion"): return
	_fluster_wait -= delta
	if _fluster_wait > 0.0: return
	_fluster_wait = randf_range(6.0, 11.0)
	if pony.get("expressions") != null and pony.expressions.has_method("fluster"): pony.expressions.fluster(1.0)


func _wore_off(id: String, row: Dictionary) -> void:
	var context: Node = game.get("world_context") if is_instance_valid(game) else null
	var who := pony_id(pony)
	if CATALOG.drink_of(id) == "potion" and context != null and who != "":
		var what := ("whatever %s slipped you" % row.get("from", "somepony")) if bool(row.get("secret", false)) else ("the %s %s gave you" % [CATALOG.name_of(id).to_lower(), row.get("from", "Anon")])
		context.record("potion", "%s%s has worn off; you feel like your usual self again." % [what.left(1).to_upper(), what.substr(1)], [who], [who])
	print("[chemistry] %s: %s wore off" % [who, id])


## One soft glow in the mixed colour of every visible potion she has drunk.
func _update_light() -> void:
	var mix := Color(0, 0, 0); var count := 0
	for id: String in active:
		var aura := str(CATALOG.reagent(id).get("aura", ""))
		if aura.is_empty() or active.has("invisibility_potion"): continue
		var c := Color.from_string(aura, Color.WHITE)
		mix += c; count += 1
	if count == 0:
		if is_instance_valid(_light): _light.queue_free()
		_light = null
		return
	if not is_instance_valid(_light):
		_light = OmniLight3D.new()
		_light.name = "PotionGlow"
		_light.omni_range = 1.6
		_light.light_energy = 0.9
		_light.shadow_enabled = false
		_light.position = Vector3(0.0, 0.9, 0.0)
		pony.add_child(_light)
	_light.light_color = Color(mix.r / count, mix.g / count, mix.b / count)


## Invisible: every mesh, label and sprite under her drops to render layer 0 (no camera or
## shadow draws it). New meshes (a near/far mesh swap) are caught on the next tick.
func _update_invisibility() -> void:
	if not active.has("invisibility_potion"):
		_restore_visibility()
		return
	for node: Node in pony.find_children("*", "VisualInstance3D", true, false):
		var visual := node as VisualInstance3D
		if visual is Light3D or visual.layers == 0: continue
		_hidden[visual.get_instance_id()] = [visual, visual.layers]
		visual.layers = 0


func _restore_visibility() -> void:
	for key: int in _hidden:
		var row: Array = _hidden[key]
		if is_instance_valid(row[0]) and (row[0] as VisualInstance3D).layers == 0: (row[0] as VisualInstance3D).layers = int(row[1])
	_hidden.clear()


func _update_context() -> void:
	var lines: PackedStringArray = []
	for id: String in active:
		var left := maxi(1, ceili((float(active[id].until) - _now()) / 60.0))
		var row: Dictionary = active[id]
		var what := ("a drink from %s (you don't know what was in it)" % row.get("from", "somepony")) if bool(row.get("secret", false)) else ("%s from %s" % [CATALOG.name_of(id), row.get("from", "Anon")])
		lines.append("%s (about %d min left): you feel %s" % [what, left, str(CATALOG.reagent(id).get("felt", ""))])
	if lines.is_empty(): return
	pony.set_meta(META, "- You drank something and are still feeling it. Let it colour how you act and talk, in your own way: " + " | ".join(lines))
