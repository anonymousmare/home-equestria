extends Node
## Anon drinking from a bottle (dev 2026-10-26: "can ponies offer u potions?"): his own from the
## lab, or one a pony handed him ([use_item: ITEM, player], pony_belongings.gd). One node on the
## game, PlayerPotions, while anything is active.
## - What shows: a corner list of what he is under; the potion's glow around him; invisibility
##   hides his body; the energy potion speeds his walk and sprint; ethanol counts as cider
##   (player_needs.gd).
## - Ponies notice what they could see (situation_line, director_prompts.gd), and the pony who
##   gave it remembers that he drank it.
const CATALOG := preload("res://world/chemistry/chem_catalog.gd")
const EFFECTS := preload("res://world/chemistry/pony_potion_effects.gd")
const ENERGY_SPEED := 1.35
## Ethanol units per mug of cider (player_needs.gd counts a mug as 1.0).
const ETHANOL_PER_MUG := 10.0
const TICK := 0.25
## What a pony can tell by looking at him, per potion.
const SEEN := {"love_potion": "he has a faint pink glow and a dopey, smitten look", "warmth_potion": "he glows a cozy orange",
	"energy_potion": "he glows yellow and can't keep still", "focus_potion": "he has a soft blue glow and a calm, sharp look",
	"sleek_potion": "his hair is glossy and shimmering", "invisibility_potion": "he is invisible: you can hear him but not see him"}

var game: Node
var active: Dictionary = {}   # reagent id -> {"until": seconds, "from": giver name}
var _light: OmniLight3D
var _hidden: Dictionary = {}
var _boosted := false
var _label: Label
var _tick := 0.0


## Anon drinks `dose`; `giver` is who brewed or handed it ("player" for his own). Returns
## {"ok", "text"} for the lab log.
static func drink(game: Node, dose: Dictionary, giver := "player") -> Dictionary:
	var units := 0.0
	for id: String in dose: units += float(dose[id])
	if units < EFFECTS.MIN_UNITS: return {"ok": false, "text": "The bottle is empty."}
	var undrinkable := 0.0
	for id: String in dose: if CATALOG.drink_of(id) == "no": undrinkable += float(dose[id])
	if undrinkable / units >= EFFECTS.UNDRINKABLE_SHARE: return {"ok": false, "text": "You are not drinking %s." % EFFECTS._names(dose, "no")}
	var node: Node = game.get_node_or_null("PlayerPotions")
	if node == null:
		node = load("res://world/chemistry/player_potion_effects.gd").new()
		node.name = "PlayerPotions"; node.game = game
		node.add_to_group("player_potions")
		game.add_child(node)
	var felt: PackedStringArray = []
	for id: String in dose:
		if float(dose[id]) < EFFECTS.MIN_UNITS or CATALOG.drink_of(id) == "no": continue
		node.add(id, float(dose[id]), EFFECTS.giver_name(game, giver))
		felt.append(str(CATALOG.reagent(id).get("felt", "")))
	var context: Node = game.get("world_context")
	if giver != "player" and context != null:
		context.record("gift", "Anon drank the %s you gave him." % EFFECTS._names(dose, ""), [giver], [giver, "player"])
	print("[chemistry] Anon drank %.0fu (%s) from %s" % [units, EFFECTS._names(dose, ""), giver])
	return {"ok": true, "text": "You drink the %s: %s." % [EFFECTS._names(dose, ""), "; ".join(felt)]}


func add(id: String, units: float, from: String) -> void:
	if id == "ethanol":
		var needs: Node = game.get("needs")
		if needs != null and "drunk" in needs: needs.drunk += units / ETHANOL_PER_MUG
	var seconds := float(CATALOG.reagent(id).get("minutes", 1)) * 60.0 * clampf(units / 10.0, 0.5, 3.0)
	var row: Dictionary = active.get(id, {"until": EFFECTS._now()})
	row.until = maxf(float(row.until), EFFECTS._now()) + seconds
	row.from = from
	active[id] = row
	_tick = TICK


func cure() -> void:
	for id: String in active: active[id].until = 0.0
	_tick = TICK


## What ponies near him can see ("" when nothing shows).
func situation_line() -> String:
	var seen: PackedStringArray = []
	for id: String in active:
		if SEEN.has(id): seen.append(SEEN[id])
	if seen.is_empty(): return ""
	return "- Anon drank a potion a little while ago and it shows: " + "; ".join(seen) + "."


func _process(delta: float) -> void:
	_tick += delta
	if _tick < TICK: return
	_tick = 0.0
	var now := EFFECTS._now()
	for id: String in active.keys():
		if now >= float(active[id].until): active.erase(id); print("[chemistry] Anon: %s wore off" % id)
	var body: Node3D = game.get("player")
	if not is_instance_valid(body): return
	_update_light(body)
	_update_invisibility(body)
	_update_speed(body)
	_update_label(now)
	if active.is_empty(): queue_free()


func _exit_tree() -> void:
	var body: Node3D = game.get("player") if is_instance_valid(game) else null
	active.clear()
	if is_instance_valid(body):
		_update_invisibility(body); _update_speed(body)


func _update_light(body: Node3D) -> void:
	var mix := Color(0, 0, 0); var count := 0
	for id: String in active:
		var aura := str(CATALOG.reagent(id).get("aura", ""))
		if aura.is_empty() or active.has("invisibility_potion"): continue
		mix += Color.from_string(aura, Color.WHITE); count += 1
	if count == 0:
		if is_instance_valid(_light): _light.queue_free()
		_light = null
		return
	if not is_instance_valid(_light):
		_light = OmniLight3D.new(); _light.name = "PotionGlow"
		_light.omni_range = 1.8; _light.light_energy = 0.8; _light.shadow_enabled = false
		_light.position = Vector3(0.0, 1.0, 0.0)
		body.add_child(_light)
	_light.light_color = Color(mix.r / count, mix.g / count, mix.b / count)


## His body and its clothes drop to render layer 0; the view (camera) is untouched.
func _update_invisibility(body: Node3D) -> void:
	if not active.has("invisibility_potion"):
		for key: int in _hidden:
			var row: Array = _hidden[key]
			if is_instance_valid(row[0]) and (row[0] as VisualInstance3D).layers == 0: (row[0] as VisualInstance3D).layers = int(row[1])
		_hidden.clear()
		return
	for node: Node in body.find_children("*", "GeometryInstance3D", true, false):
		var visual := node as GeometryInstance3D
		if visual.layers == 0: continue
		_hidden[visual.get_instance_id()] = [visual, visual.layers]
		visual.layers = 0


func _update_speed(body: Node3D) -> void:
	var want := active.has("energy_potion")
	if want == _boosted or not ("walk_speed" in body and "sprint_speed" in body): return
	var factor := ENERGY_SPEED if want else 1.0 / ENERGY_SPEED
	body.walk_speed *= factor; body.sprint_speed *= factor
	_boosted = want


func _update_label(now: float) -> void:
	if not is_instance_valid(_label):
		var layer := CanvasLayer.new(); layer.layer = 90; add_child(layer)
		_label = Label.new(); _label.position = Vector2(16, 120)
		_label.add_theme_color_override("font_color", Color("ffd6f0"))
		_label.add_theme_color_override("font_outline_color", Color.BLACK); _label.add_theme_constant_override("outline_size", 4)
		layer.add_child(_label)
	var rows: PackedStringArray = []
	for id: String in active:
		var left := maxi(0, int(float(active[id].until) - now))
		rows.append("%s  %d:%02d" % [CATALOG.name_of(id), left / 60, left % 60])
	_label.text = "\n".join(rows)
