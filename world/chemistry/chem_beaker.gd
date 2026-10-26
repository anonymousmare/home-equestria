extends RefCounted
## One beaker: reagent units, a temperature and the reactions they set off (the tgstation
## rules, simplified: a recipe runs whenever all its reagents and catalysts are in the beaker
## and the temperature allows, converting as much as the scarcest reagent allows at once).
const CATALOG := preload("res://world/chemistry/chem_catalog.gd")
const CAPACITY := 100.0
## How fast the heater moves the beaker toward its target, kelvin per second.
const HEAT_RATE := 120.0
## Amounts smaller than this are dust and are dropped.
const EPSILON := 0.01

var contents: Dictionary = {}   # reagent id -> units
var temperature := CATALOG.ROOM
var target := CATALOG.ROOM
var heater := false
signal reacted(message: String)

func total() -> float:
	var sum := 0.0
	for id: String in contents: sum += float(contents[id])
	return sum

func space() -> float:
	return maxf(0.0, CAPACITY - total())

## Adds up to `units` of `id`; returns how much fit.
func add(id: String, units: float) -> float:
	if not CATALOG.has(id) or units <= 0.0: return 0.0
	var amount := minf(units, space())
	if amount <= 0.0: return 0.0
	contents[id] = float(contents.get(id, 0.0)) + amount
	react()
	return amount

func remove(id: String, units: float) -> float:
	var amount := minf(units, float(contents.get(id, 0.0)))
	contents[id] = float(contents.get(id, 0.0)) - amount
	if float(contents[id]) <= EPSILON: contents.erase(id)
	return amount

func clear() -> void:
	contents.clear()
	temperature = CATALOG.ROOM

## Pours out up to `units` in proportion, as a {id: units} dose (a bottle's contents).
func pour(units: float) -> Dictionary:
	var whole := total()
	if whole <= 0.0: return {}
	var share := minf(1.0, units / whole)
	var dose: Dictionary = {}
	for id: String in contents.keys():
		var amount := float(contents[id]) * share
		dose[id] = amount
		remove(id, amount)
	return dose

## The reagent with the most units, or "".
func main_reagent() -> String:
	var best := ""; var most := 0.0
	for id: String in contents:
		if float(contents[id]) > most: most = float(contents[id]); best = id
	return best

## The mixed colour of everything in the beaker, weighted by units.
func color() -> Color:
	var whole := total()
	if whole <= 0.0: return Color(1, 1, 1, 0.1)
	var mix := Color(0, 0, 0, 1)
	for id: String in contents:
		var c := CATALOG.color_of(id); var w := float(contents[id]) / whole
		mix.r += c.r * w; mix.g += c.g * w; mix.b += c.b * w
	return mix

func step(delta: float) -> void:
	if heater and not is_equal_approx(temperature, target):
		temperature = move_toward(temperature, target, HEAT_RATE * delta)
		react()
	elif not heater and not is_equal_approx(temperature, CATALOG.ROOM):
		# Off the heater the beaker drifts back to room temperature, slowly.
		temperature = move_toward(temperature, CATALOG.ROOM, HEAT_RATE * 0.15 * delta)
		react()

## Runs every recipe that can run, until none can (a product may feed the next recipe).
func react() -> void:
	for _pass in 16:
		var ran := false
		for reaction: Dictionary in CATALOG.reactions():
			if _run(reaction): ran = true
		if not ran: return

func _run(reaction: Dictionary) -> bool:
	if reaction.has("min_temp") and temperature < float(reaction.min_temp): return false
	if reaction.has("max_temp") and temperature > float(reaction.max_temp): return false
	for id: String in reaction.get("catalysts", {}):
		if float(contents.get(id, 0.0)) < float(reaction.catalysts[id]): return false
	var batches := INF
	for id: String in reaction.requires:
		batches = minf(batches, float(contents.get(id, 0.0)) / float(reaction.requires[id]))
	if batches <= EPSILON or not is_finite(batches): return false
	for id: String in reaction.requires: remove(id, batches * float(reaction.requires[id]))
	for id: String in reaction.makes:
		contents[id] = float(contents.get(id, 0.0)) + batches * float(reaction.makes[id])
	var made: PackedStringArray = []
	for id: String in reaction.makes: made.append("%.1fu %s" % [batches * float(reaction.makes[id]), CATALOG.name_of(id)])
	var message := str(reaction.get("message", ""))
	if bool(reaction.get("empties", false)): contents.clear()
	reacted.emit((message + " " if message != "" else "") + ("(" + ", ".join(made) + ")" if not made.is_empty() else ""))
	return true
