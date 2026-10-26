extends RefCounted
## Chemistry reagents and recipes (dev 2026-10-26: "add this", the Space Station 13 Guide to
## Chemistry). world/chemistry/reagents.json holds the real chemicals from tgstation's recipe
## files, station science left out, plus six whimsical potions a pony can drink
## (world/chemistry/pony_potion_effects.gd). Temperatures are kelvin; a beaker starts at ROOM.
const PATH := "res://world/chemistry/reagents.json"
const ROOM := 300.0
static var _data: Dictionary = {}
static var _ordered: Array = []

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary: _data = parsed
	return _data

static func reagents() -> Dictionary:
	return data().get("reagents", {})

static func has(id: String) -> bool:
	return reagents().has(id)

static func reagent(id: String) -> Dictionary:
	return reagents().get(id, {})

static func name_of(id: String) -> String:
	return str(reagent(id).get("name", id.capitalize()))

static func color_of(id: String) -> Color:
	return Color.from_string(str(reagent(id).get("color", "#cccccc")), Color(0.8, 0.8, 0.8))

static func kind_of(id: String) -> String:
	return str(reagent(id).get("kind", "compound"))

## "potion" (a whimsical brew with a visible effect), "safe" (drinkable, a feeling only) or
## "no" (a pony will not drink it).
static func drink_of(id: String) -> String:
	return str(reagent(id).get("drink", "no"))

static func dispenser() -> Array:
	return data().get("dispenser", [])

## Recipes, most ingredients first: the more specific recipe wins when two could use the same
## reagents (sugar, epinephrine and gold make a love potion, not just stay sugar and adrenaline).
static func reactions() -> Array:
	if _ordered.is_empty():
		_ordered = (data().get("reactions", []) as Array).duplicate()
		var order: Dictionary = {}
		for i in _ordered.size(): order[_ordered[i].id] = i
		_ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var na: int = (a.requires as Dictionary).size(); var nb: int = (b.requires as Dictionary).size()
			return na > nb if na != nb else int(order[a.id]) < int(order[b.id]))
	return _ordered

## The recipe that makes `id` (the first, in file order), or {}.
static func recipe_for(id: String) -> Dictionary:
	for reaction: Dictionary in data().get("reactions", []):
		if (reaction.get("makes", {}) as Dictionary).has(id): return reaction
	return {}

## "Sugar 2 · Epinephrine 1 · Gold 1 · above 330 K"
static func recipe_text(reaction: Dictionary) -> String:
	var parts: PackedStringArray = []
	for id: String in reaction.requires: parts.append("%s %d" % [name_of(id), int(reaction.requires[id])])
	for id: String in reaction.get("catalysts", {}): parts.append("(catalyst: %s %d)" % [name_of(id), int(reaction.catalysts[id])])
	if reaction.has("min_temp"): parts.append("above %d K" % int(reaction.min_temp))
	if reaction.has("max_temp"): parts.append("below %d K" % int(reaction.max_temp))
	return " · ".join(parts)
