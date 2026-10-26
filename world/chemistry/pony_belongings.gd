extends Node
## Bottles a pony keeps for later (dev 2026-10-26: "they should be able to take potions without
## consuming them. Like how the CMC made love potions to drug Cheerilee. Or just making smth for
## a friend so they can 'use' it later"). Anon gives a bottle "to keep" from the chemistry lab;
## she carries it (saved with the world, "pony_belongings") and her AI sees it in her situation
## block with the [use_item] tag:
##   [use_item: ITEM, self]              drink it, or light an explosive, herself
##   [use_item: ITEM, PONY_ID]           a potion: hand it over and she drinks it; an explosive:
##                                       set it off beside her
##   [use_item: ITEM, PONY_ID, secret]   slip a potion into her drink without saying what it is
##   [use_item: ITEM, PONY_ID, keep]     give it to her to keep for later
##   [use_item: ITEM, player]            hand it to Anon (back into his bottles)
## A use on somepony out of reach waits while she walks over (an approach is started for her).
## Anon's own bottles live here too ("chem_bottles"), so they are saved and ponies can give
## him theirs.
const CATALOG := preload("res://world/chemistry/chem_catalog.gd")
const EFFECTS := preload("res://world/chemistry/pony_potion_effects.gd")
const BLAST := preload("res://world/chemistry/chem_blast.gd")
const MAX_CARRIED := 8
const MAX_BOTTLES := 40
## Close enough to hand something over.
const REACH := 2.6
## How long a use waits for her to get close.
const WAIT_SECONDS := 45.0
const MODES := ["", "drink", "secret", "keep", "set_off"]
const MODE_SPELLINGS := {"give": "drink", "drink": "drink", "secret": "secret", "secretly": "secret", "slip": "secret", "sneak": "secret",
	"hidden": "secret", "spike": "secret", "keep": "keep", "gift": "keep", "save": "keep", "later": "keep", "hand": "keep", "for_later": "keep",
	"set_off": "set_off", "light": "set_off", "explode": "set_off", "detonate": "set_off", "blow_up": "set_off", "ignite": "set_off", "throw": "set_off"}

var game: Node
var _pending: Array = []   # {user, key, recipient, mode, node: WeakRef, executor: WeakRef, action, until}
var _tick := 0.0


func setup(host: Node) -> void:
	game = host
	add_to_group("pony_belongings")


static func mode_of(raw: String) -> String:
	var name := raw.strip_edges().to_lower().replace(" ", "_").replace("-", "_")
	return str(MODE_SPELLINGS.get(name, name if name in MODES else ""))


func _state() -> Dictionary:
	var context: Node = game.get("world_context") if is_instance_valid(game) else null
	return context.state if context != null and context.get("state") is Dictionary else {}


func has_world() -> bool:
	return not _state().is_empty()


func _changed() -> void:
	var context: Node = game.get("world_context") if is_instance_valid(game) else null
	if context != null and context.has_method("_changed"): context._changed()


## A saved dose, checked: known reagents with sensible units only.
static func _clean_dose(value: Variant) -> Dictionary:
	var dose := {}
	if not value is Dictionary: return dose
	for id: Variant in value:
		if id is String and CATALOG.has(id) and (value[id] is float or value[id] is int) and is_finite(float(value[id])) and float(value[id]) > 0.0:
			dose[id] = minf(float(value[id]), 200.0)
	return dose


static func main_of(dose: Dictionary) -> String:
	var best := ""; var most := 0.0
	for id: String in dose:
		if float(dose[id]) > most: most = float(dose[id]); best = id
	return best


static func total_of(dose: Dictionary) -> float:
	var sum := 0.0
	for id: String in dose: sum += float(dose[id])
	return sum


static func label_of(dose: Dictionary) -> String:
	var main := main_of(dose)
	return "%s (%.0fu)" % [CATALOG.name_of(main), total_of(dose)] + (" + %d more" % (dose.size() - 1) if dose.size() > 1 else "")


## What `pony_id` carries: [{"key", "dose", "from"}], keys unique ("love_potion", "love_potion_2").
func items_for(pony_id: String) -> Array:
	var state := _state()
	if state.is_empty(): return []
	if not state.get("pony_belongings") is Dictionary: state["pony_belongings"] = {}
	var raw: Variant = state.pony_belongings.get(pony_id, [])
	var items: Array = []
	if raw is Array:
		for row: Variant in raw:
			if not row is Dictionary or not row.get("key") is String: continue
			var dose := _clean_dose(row.get("dose"))
			if dose.is_empty(): continue
			items.append({"key": str(row.key).left(40), "dose": dose, "from": str(row.get("from", "player")).left(64)})
	return items.slice(0, MAX_CARRIED)


func _set_items(pony_id: String, items: Array) -> void:
	var state := _state()
	if state.is_empty(): return
	if not state.get("pony_belongings") is Dictionary: state["pony_belongings"] = {}
	if items.is_empty(): state.pony_belongings.erase(pony_id)
	else: state.pony_belongings[pony_id] = items
	_changed()


func keys_for(pony_id: String) -> Array:
	return items_for(pony_id).map(func(row: Dictionary) -> String: return row.key)


func _add_item(pony_id: String, dose: Dictionary, from: String) -> bool:
	var items := items_for(pony_id)
	if items.size() >= MAX_CARRIED: return false
	var base := main_of(dose)
	var key := base; var n := 2
	var taken: Array = items.map(func(row: Dictionary) -> String: return row.key)
	while key in taken: key = "%s_%d" % [base, n]; n += 1
	items.append({"key": key, "dose": dose, "from": from})
	_set_items(pony_id, items)
	return true


func _take_item(pony_id: String, key: String) -> Dictionary:
	var items := items_for(pony_id)
	for i in items.size():
		if items[i].key == key:
			var row: Dictionary = items[i]
			items.remove_at(i)
			_set_items(pony_id, items)
			return row
	return {}


## The situation line: what she carries and from whom ("" when nothing).
func situation_line(pony_id: String) -> String:
	var items := items_for(pony_id)
	if items.is_empty(): return ""
	var parts: PackedStringArray = []
	for row: Dictionary in items:
		var main := main_of(row.dose)
		var kind := "explosive" if BLAST.is_explosive(main) else ("potion" if CATALOG.drink_of(main) == "potion" else CATALOG.kind_of(main))
		parts.append("%s = %s, %s (from %s)" % [row.key, label_of(row.dose), kind, EFFECTS.giver_name(game, row.from)])
		if CATALOG.drink_of(main) != "no": parts[-1] += ": " + str(CATALOG.reagent(main).get("description", ""))
	return "- You are carrying, kept for later (use with [use_item: ITEM, TARGET] whenever you like, or never): " + "; ".join(parts)


# ------------------------------------------------------------------ Anon's bottles

func player_bottles() -> Array:
	var state := _state()
	if state.is_empty(): return []
	var raw: Variant = state.get("chem_bottles", [])
	var bottles: Array = []
	if raw is Array:
		for row: Variant in raw:
			var dose := _clean_dose(row.get("dose") if row is Dictionary else null)
			if not dose.is_empty(): bottles.append({"dose": dose, "from": str(row.get("from", "player"))})
	return bottles


func set_player_bottles(bottles: Array) -> void:
	var state := _state()
	if state.is_empty(): return
	state["chem_bottles"] = bottles.slice(0, MAX_BOTTLES).map(func(row: Dictionary) -> Dictionary: return {"dose": row.dose, "from": str(row.get("from", "player"))})
	_changed()


# ------------------------------------------------------------------ giving to keep

## Anon (or a pony, `giver`) gives `pony` a bottle to keep. Returns {"ok", "text"}.
func keep(pony: Node3D, dose: Dictionary, giver := "player") -> Dictionary:
	var who := EFFECTS.display_name(pony)
	var id := EFFECTS.pony_id(pony)
	var main := main_of(dose)
	if id.is_empty() or main.is_empty(): return {"ok": false, "text": "Nothing to give."}
	if _state().is_empty(): return {"ok": false, "text": "No world is open."}
	if bool(pony.get("sleeping")): return {"ok": false, "text": "%s is asleep." % who}
	if CATALOG.drink_of(main) == "no" and not BLAST.is_explosive(main):
		return {"ok": false, "text": "%s doesn't want a bottle of %s." % [who, CATALOG.name_of(main).to_lower()]}
	var context: Node = game.get("world_context")
	var bonds: Node = context.get("player_bonds") if context != null else null
	if giver == "player" and bonds != null:
		var record: Dictionary = bonds.record_for(id)
		if bonds.anger(id) >= 35.0 or Time.get_unix_time_from_system() < float(record.get("cooldowns", {}).get("boundary", 0.0)):
			return {"ok": false, "text": "%s won't take anything from you right now." % who}
	if not _add_item(id, dose, giver): return {"ok": false, "text": "%s can't carry any more." % who}
	var from := EFFECTS.giver_name(game, giver)
	context.record("gift", "%s gave you a bottle of %s to keep: %s. It is yours to use whenever you like." % [from, CATALOG.name_of(main).to_lower(), str(CATALOG.reagent(main).get("description", "")).trim_suffix(".")], [id], [id, giver])
	if giver == "player" and bonds != null: bonds.experience(id, "gift", "kept_%d" % Time.get_ticks_usec())
	if pony.has_signal("physical_reaction"): pony.emit_signal("physical_reaction", "kept:%s:%s" % [main, giver])
	print("[chemistry] %s keeps %s from %s" % [id, label_of(dose), giver])
	return {"ok": true, "text": "%s takes the %s to keep." % [who, label_of(dose)]}


# ------------------------------------------------------------------ [use_item]

## pony_action_coordinator.gd: `user` uses one of her items. Reports through `executor`.
func use(user: String, actor: Node3D, action: Dictionary, targets: Dictionary, executor: Node) -> void:
	var key := str(action.get("item_id", ""))
	var recipient := str(action.get("recipient_id", "self"))
	var mode := str(action.get("mode", ""))
	if key not in keys_for(user): executor._report(action, "failed", "You are not carrying that"); return
	if recipient == user: recipient = "self"
	var node: Node3D = actor if recipient == "self" else (targets.get(recipient) as Node3D)
	if not is_instance_valid(node): executor._report(action, "failed", "They are not here"); return
	if recipient != "self" and actor.global_position.distance_to(node.global_position) > REACH:
		_pending.append({"user": user, "key": key, "recipient": recipient, "mode": mode, "node": weakref(node), "actor": weakref(actor),
			"executor": weakref(executor), "action": action, "until": Time.get_ticks_msec() + int(WAIT_SECONDS * 1000.0)})
		if executor.get("movement") is Dictionary and (executor.movement as Dictionary).is_empty():
			executor.submit([{"id": str(action.id) + "-near", "type": "approach", "target_id": recipient, "distance_m": 1.2}], {recipient: node}, int(executor.get("_latest_turn")))
		executor._report(action, "accepted", "Walking over to hand it over")
		return
	_finish(user, actor, key, recipient, mode, node, executor, action)


func _finish(user: String, actor: Node3D, key: String, recipient: String, mode: String, node: Node3D, executor: Node, action: Dictionary) -> void:
	var row := _take_item(user, key)
	if row.is_empty(): executor._report(action, "failed", "You are not carrying that any more"); return
	var dose: Dictionary = row.dose
	var main := main_of(dose)
	var explosive := BLAST.is_explosive(main)
	var result := {"ok": false, "text": ""}
	if recipient == "player":
		if explosive and mode == "set_off":
			BLAST.blast(game, node.global_position + Vector3(0, -1.2, 0), main, total_of(dose), user)
			result = {"ok": true, "text": "Set it off right beside Anon"}
		else:
			var bottles := player_bottles()
			bottles.append({"dose": dose, "from": user})
			set_player_bottles(bottles)
			var lab: Node = game.get_node_or_null("ChemLab")
			if lab != null and lab.has_method("refresh_bottles"): lab.refresh_bottles()
			game.world_context.record("gift", "You gave Anon your %s." % label_of(dose).to_lower(), [user], [user, "player"])
			result = {"ok": true, "text": "Handed it to Anon"}
	elif explosive and mode != "keep":
		var at := node.global_position + (-node.global_basis.z * 1.2 if recipient == "self" else Vector3.ZERO)
		BLAST.blast(game, at, main, total_of(dose), user, "" if recipient == "self" else recipient)
		result = {"ok": true, "text": "Set it off" + ("" if recipient == "self" else " beside " + EFFECTS.display_name(node))}
	elif mode == "keep" and recipient != "self":
		result = keep(node, dose, user)
	else:
		result = EFFECTS.give(game, node, dose, user, mode == "secret" and recipient != "self", actor)
	if not bool(result.ok): _add_item(user, dose, str(row.from))   # Refused: she still has it.
	executor._report(action, "completed" if result.ok else "failed", str(result.text))


func _physics_process(delta: float) -> void:
	if _pending.is_empty(): return
	_tick += delta
	if _tick < 0.25: return
	_tick = 0.0
	var now := Time.get_ticks_msec()
	for entry: Dictionary in _pending.duplicate():
		var node: Node3D = entry.node.get_ref()
		var actor: Node3D = entry.actor.get_ref()
		var executor: Node = entry.executor.get_ref()
		if not is_instance_valid(executor): _pending.erase(entry); continue
		if not is_instance_valid(node) or not is_instance_valid(actor):
			_pending.erase(entry); executor._report(entry.action, "failed", "They are gone"); continue
		if actor.global_position.distance_to(node.global_position) <= REACH:
			_pending.erase(entry)
			_finish(entry.user, actor, entry.key, entry.recipient, entry.mode, node, executor, entry.action)
		elif now > int(entry.until):
			_pending.erase(entry); executor._report(entry.action, "failed", "Could not get close enough to hand it over")
