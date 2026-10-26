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
##   [use_item: ITEM, player]            offer it to Anon: it goes into his bottles and he decides
##                                       whether to drink it (player_potion_effects.gd)
##   [use_item: ITEM, self] on a plain reagent (lye, saltpetre, ...) uses it up for what it is
##                                       for: soap-making, the orchard, cleaning
## A use on somepony out of reach waits while she walks over (an approach is started for her).
## Ponies take any reagent to keep; whether they want it, know what it is for (Applejack knows
## lye makes soap; Apple Bloom may not) or hand it back is their own personality's call.
## Zecora starts each world with two of her own brews to offer (STARTER).
## Anon's own bottles live here too ("chem_bottles"), so they are saved and ponies can give
## him theirs.
const CATALOG := preload("res://world/chemistry/chem_catalog.gd")
const EFFECTS := preload("res://world/chemistry/pony_potion_effects.gd")
const BLAST := preload("res://world/chemistry/chem_blast.gd")
const CONTAINER := preload("res://world/chemistry/chem_container.gd")
const DRINK := preload("res://world/chemistry/chem_drink_visual.gd")
const MAX_CARRIED := 8
const MAX_BOTTLES := 40
## Close enough to hand something over.
const REACH := 2.6
## How long a use waits for her to get close.
const WAIT_SECONDS := 45.0
const MODES := ["", "drink", "secret", "keep", "set_off"]
## Brews a pony has from the start of a world (she made them herself).
const STARTER := {"zecora": [{"warmth_potion": 30.0}, {"focus_potion": 30.0}]}
const MODE_SPELLINGS := {"give": "drink", "drink": "drink", "secret": "secret", "secretly": "secret", "slip": "secret", "sneak": "secret",
	"hidden": "secret", "spike": "secret", "keep": "keep", "gift": "keep", "save": "keep", "later": "keep", "hand": "keep", "for_later": "keep",
	"set_off": "set_off", "light": "set_off", "explode": "set_off", "detonate": "set_off", "blow_up": "set_off", "ignite": "set_off", "throw": "set_off"}

var game: Node
var _pending: Array = []   # {user, key, recipient, mode, node: WeakRef, executor: WeakRef, action, until}
var _tick := 0.0
## Where something she is about to use comes from, instead of her side: "pony/item key" -> world
## point (a tea set, chem_tea.gd). Not saved.
var origins: Dictionary = {}


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
	if not bool(state.get("belongings_seeded", false)):
		state["belongings_seeded"] = true
		for owner: String in STARTER:
			var start: Array = []
			for dose: Dictionary in STARTER[owner]: start.append({"key": main_of(dose), "dose": dose.duplicate(), "from": owner})
			state.pony_belongings[owner] = start
		_changed()
	var raw: Variant = state.pony_belongings.get(pony_id, [])
	var items: Array = []
	if raw is Array:
		for row: Variant in raw:
			if not row is Dictionary or not row.get("key") is String: continue
			var dose := _clean_dose(row.get("dose"))
			if dose.is_empty(): continue
			var item := {"key": str(row.key).left(40), "dose": dose, "from": str(row.get("from", "player")).left(64)}
			item.merge(_vessel_of(row))
			items.append(item)
	return items.slice(0, MAX_CARRIED)


## The vessel fields of a saved row: container type, temperature in K and when it was that warm.
## Rows from before vessels hold a potion bottle at room temperature.
static func _vessel_of(row: Variant) -> Dictionary:
	var source: Dictionary = row if row is Dictionary else {}
	var temp: Variant = source.get("temp", CATALOG.ROOM)
	var when: Variant = source.get("t0", 0.0)
	return {"container": CONTAINER.valid(str(source.get("container", CONTAINER.DEFAULT))),
		"temp": clampf(float(temp), 0.0, 1500.0) if temp is float or temp is int else CATALOG.ROOM,
		"t0": float(when) if when is float or when is int else 0.0}


## {"container", "temp", "t0"} for a bottle made now at `temp` K.
static func vessel_now(container: String, temp: float) -> Dictionary:
	return {"container": CONTAINER.valid(container), "temp": temp, "t0": Time.get_unix_time_from_system()}


## The temperature of a saved vessel right now.
static func temp_now(vessel: Dictionary) -> float:
	return CATALOG.cooled(float(vessel.get("temp", CATALOG.ROOM)), float(vessel.get("t0", 0.0)), Time.get_unix_time_from_system())


func _set_items(pony_id: String, items: Array) -> void:
	var state := _state()
	if state.is_empty(): return
	if not state.get("pony_belongings") is Dictionary: state["pony_belongings"] = {}
	if items.is_empty(): state.pony_belongings.erase(pony_id)
	else: state.pony_belongings[pony_id] = items
	_changed()


func keys_for(pony_id: String) -> Array:
	return items_for(pony_id).map(func(row: Dictionary) -> String: return row.key)


## Puts a bottle in her things (false when her hooves are full).
func add_item(pony_id: String, dose: Dictionary, from: String, vessel := {}) -> bool:
	return _add_item(pony_id, dose, from, vessel)


func _add_item(pony_id: String, dose: Dictionary, from: String, vessel := {}) -> bool:
	var items := items_for(pony_id)
	if items.size() >= MAX_CARRIED: return false
	var base := main_of(dose)
	var key := base; var n := 2
	var taken: Array = items.map(func(row: Dictionary) -> String: return row.key)
	while key in taken: key = "%s_%d" % [base, n]; n += 1
	var row := {"key": key, "dose": dose, "from": from}
	row.merge(_vessel_of(vessel))
	items.append(row)
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
		var temp := temp_now(row)
		var warmth := CATALOG.temp_words(temp)
		parts.append("%s = %s in a %s, %s, %s (%s)" % [row.key, label_of(row.dose), CONTAINER.name_of(row.container).to_lower(), kind, warmth, "you made it" if row.from == pony_id else "from " + EFFECTS.giver_name(game, row.from)])
		parts[-1] += ": " + about(main)
		var mismatch := CATALOG.serve_note(main, temp)
		if mismatch != "": parts[-1] += ". " + mismatch
	return "- You are carrying, kept for later (use with [use_item: ITEM, TARGET] whenever you like, or never): " + "; ".join(parts)


## "Sweet and sparkly ... Used for: soap-making ..." for prompts. Whether she knows the uses is
## up to who she is.
static func about(reagent: String) -> String:
	var entry := CATALOG.reagent(reagent)
	var text := str(entry.get("description", "")).trim_suffix(".")
	# Nopony has to find a flame: the item use itself lights it (a thermite pony once held off waiting for heat).
	if BLAST.is_explosive(reagent): text += "; it needs no match, heat or tools here: [use_item] with it sets it off"
	if entry.has("uses"): text += "; commonly used for " + str(entry.uses) + " (whether you know that depends on who you are)"
	return text


# ------------------------------------------------------------------ Anon's bottles

func player_bottles() -> Array:
	var state := _state()
	if state.is_empty(): return []
	var raw: Variant = state.get("chem_bottles", [])
	var bottles: Array = []
	if raw is Array:
		for row: Variant in raw:
			var dose := _clean_dose(row.get("dose") if row is Dictionary else null)
			if not dose.is_empty():
				var bottle := {"dose": dose, "from": str(row.get("from", "player"))}
				bottle.merge(_vessel_of(row))
				bottles.append(bottle)
	return bottles


func set_player_bottles(bottles: Array) -> void:
	var state := _state()
	if state.is_empty(): return
	state["chem_bottles"] = bottles.slice(0, MAX_BOTTLES).map(func(row: Dictionary) -> Dictionary:
		var saved := {"dose": row.dose, "from": str(row.get("from", "player"))}
		saved.merge(_vessel_of(row))
		return saved)
	_changed()


# ------------------------------------------------------------------ giving to keep

## Anon (or a pony, `giver`) gives `pony` a bottle to keep. Returns {"ok", "text"}.
func keep(pony: Node3D, dose: Dictionary, giver := "player", vessel := {}) -> Dictionary:
	var who := EFFECTS.display_name(pony)
	var id := EFFECTS.pony_id(pony)
	var main := main_of(dose)
	if id.is_empty() or main.is_empty(): return {"ok": false, "text": "Nothing to give."}
	if _state().is_empty(): return {"ok": false, "text": "No world is open."}
	if bool(pony.get("sleeping")): return {"ok": false, "text": "%s is asleep." % who}
	var context: Node = game.get("world_context")
	var bonds: Node = context.get("player_bonds") if context != null else null
	if giver == "player" and bonds != null:
		var record: Dictionary = bonds.record_for(id)
		if bonds.anger(id) >= 35.0 or Time.get_unix_time_from_system() < float(record.get("cooldowns", {}).get("boundary", 0.0)):
			return {"ok": false, "text": "%s won't take anything from you right now." % who}
	if not _add_item(id, dose, giver, vessel): return {"ok": false, "text": "%s can't carry any more." % who}
	var from := EFFECTS.giver_name(game, giver)
	var held := _vessel_of(vessel)
	var warmth := CATALOG.temp_words(temp_now(held))
	context.record("gift", "%s gave you a %s of %s (%s) to keep: %s. It is yours to use whenever you like." % [from, CONTAINER.noun(held.container), CATALOG.name_of(main).to_lower(), warmth, about(main)], [id], [id, giver])
	# She takes it in her hoof for a moment.
	DRINK.receive(game, pony, held.container, EFFECTS._mix_color(dose), clampf(total_of(dose) / CONTAINER.capacity(held.container), 0.15, 1.0), temp_now(held), EFFECTS.hand_point(game, giver))
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
		# She carries it in her hoof on the way over.
		var carried := _carry(user, actor, key)
		_pending.append({"user": user, "key": key, "recipient": recipient, "mode": mode, "node": weakref(node), "actor": weakref(actor),
			"executor": weakref(executor), "action": action, "until": Time.get_ticks_msec() + int(WAIT_SECONDS * 1000.0),
			"visual": weakref(carried) if carried != null else null})
		if executor.get("movement") is Dictionary and (executor.movement as Dictionary).is_empty():
			executor.submit([{"id": str(action.id) + "-near", "type": "approach", "target_id": recipient, "distance_m": 1.2}], {recipient: node}, int(executor.get("_latest_turn")))
		executor._report(action, "accepted", "Walking over to hand it over")
		return
	_finish(user, actor, key, recipient, mode, node, executor, action)


func _carry(user: String, actor: Node3D, key: String) -> Node3D:
	for row: Dictionary in items_for(user):
		if row.key == key:
			return DRINK.hold(game, actor, row.container, EFFECTS._mix_color(row.dose), clampf(total_of(row.dose) / CONTAINER.capacity(row.container), 0.15, 1.0), temp_now(row))
	return null


func _finish(user: String, actor: Node3D, key: String, recipient: String, mode: String, node: Node3D, executor: Node, action: Dictionary, carried: Node = null) -> void:
	if is_instance_valid(carried) and carried.has_method("release"): carried.release()
	var row := _take_item(user, key)
	if row.is_empty(): executor._report(action, "failed", "You are not carrying that any more"); return
	var dose: Dictionary = row.dose
	var vessel := _vessel_of(row)
	var origin: Variant = origins.get(user + "/" + key)
	origins.erase(user + "/" + key)
	if origin is Vector3 and (origin as Vector3).is_finite(): vessel["origin"] = origin
	var main := main_of(dose)
	var explosive := BLAST.is_explosive(main)
	var result := {"ok": false, "text": ""}
	if recipient == "player":
		if explosive and mode == "set_off":
			BLAST.blast(game, node.global_position + Vector3(0, -1.2, 0), main, total_of(dose), user)
			result = {"ok": true, "text": "Set it off right beside Anon"}
		else:
			var offered := {"dose": dose, "from": user}
			offered.merge(vessel)
			offered.erase("origin")
			var hand: Node = get_tree().get_first_node_in_group("chem_hand")
			var given := "%s hands you a %s of %s." % [EFFECTS.display_name(actor), CONTAINER.noun(str(vessel.container)), CATALOG.name_of(main).to_lower()]
			if hand != null and hand.held.is_empty():
				# Straight into his hand: click to drink it, or offer it on.
				hand.hold(offered)
				hand.note(given)
			else:
				var bottles := player_bottles()
				bottles.append(offered)
				set_player_bottles(bottles)
				var lab: Node = game.get_node_or_null("ChemLab")
				if lab != null and lab.has_method("received"): lab.received(given)
			game.world_context.record("gift", "You gave Anon a %s of %s." % [CONTAINER.noun(str(vessel.container)), CATALOG.name_of(main).to_lower()], [user], [user, "player"])
			result = {"ok": true, "text": "Handed it to Anon"}
	elif explosive and mode != "keep":
		var at := node.global_position + (-node.global_basis.z * 1.2 if recipient == "self" else Vector3.ZERO)
		BLAST.blast(game, at, main, total_of(dose), user, "" if recipient == "self" else recipient)
		result = {"ok": true, "text": "Set it off" + ("" if recipient == "self" else " beside " + EFFECTS.display_name(node))}
	elif mode == "keep" and recipient != "self":
		result = keep(node, dose, user, vessel)
	elif CATALOG.drink_of(main) == "no":
		if recipient == "self":
			# Lye for soap, saltpetre for the orchard: used up doing what it is for, off screen.
			game.world_context.record("used", "You used your %s%s." % [CATALOG.name_of(main).to_lower(), (" (" + str(CATALOG.reagent(main).uses) + ")") if CATALOG.reagent(main).has("uses") else ""], [user], [user])
			result = {"ok": true, "text": "Used it up"}
		else: result = keep(node, dose, user, vessel)   # Not a drink: handing it over means giving it.
	else:
		result = EFFECTS.give(game, node, dose, user, mode == "secret" and recipient != "self", actor, vessel)
	if not bool(result.ok): _add_item(user, dose, str(row.from), vessel)   # Refused: she still has it.
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
			_pending.erase(entry); _drop_visual(entry); executor._report(entry.action, "failed", "They are gone"); continue
		if actor.global_position.distance_to(node.global_position) <= REACH:
			_pending.erase(entry)
			_finish(entry.user, actor, entry.key, entry.recipient, entry.mode, node, executor, entry.action, entry.visual.get_ref() if entry.visual != null else null)
		elif now > int(entry.until):
			_pending.erase(entry); _drop_visual(entry); executor._report(entry.action, "failed", "Could not get close enough to hand it over")


func _drop_visual(entry: Dictionary) -> void:
	var carried: Variant = entry.visual.get_ref() if entry.visual != null else null
	if is_instance_valid(carried) and carried.has_method("release"): carried.release()
