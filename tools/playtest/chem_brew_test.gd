extends SceneTree
## Brews each reagent's recipe in a fresh beaker and checks the product appears.

func _init() -> void:
	var CATALOG = load("res://world/chemistry/chem_catalog.gd")
	var BEAKER = load("res://world/chemistry/chem_beaker.gd")
	var failures := 0
	# Every recipe's reagents and products exist.
	for reaction: Dictionary in CATALOG.data().reactions:
		for id in reaction.requires.keys() + reaction.makes.keys() + reaction.get("catalysts", {}).keys():
			if not CATALOG.has(id): print("UNKNOWN reagent ", id, " in ", reaction.id); failures += 1
	for id in CATALOG.dispenser():
		if not CATALOG.has(id): print("UNKNOWN dispenser ", id); failures += 1
	# Every non-element reagent can be made, from scratch, using only dispenser elements.
	for target: String in CATALOG.reagents():
		if target in CATALOG.dispenser(): continue
		var b = BEAKER.new()
		var plan: Array = []
		if not _plan(CATALOG, target, 1.0, plan, 0): print("NO ROUTE ", target); failures += 1; continue
		# Brew each intermediate in its own beaker, then pour into the main one (a chemist's workflow).
		var made := _brew(CATALOG, BEAKER, target, 4.0)
		if made < 0.5: print("FAILED ", target, " got ", made); failures += 1
		else: print("ok %-22s %.1fu" % [target, made])
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)


func _plan(CATALOG, target: String, _u: float, plan: Array, depth: int) -> bool:
	if depth > 8: return false
	if target in CATALOG.dispenser(): return true
	var r: Dictionary = CATALOG.recipe_for(target)
	if r.is_empty(): return false
	for id in r.requires: if not _plan(CATALOG, id, 1.0, plan, depth + 1): return false
	return true


## Makes `target` by brewing each non-dispenser ingredient separately first. Returns units made.
func _brew(CATALOG, BEAKER, target: String, batches: float) -> float:
	var r: Dictionary = CATALOG.recipe_for(target)
	var parts: Dictionary = {}
	for id in r.requires:
		var need := float(r.requires[id]) * batches
		if id in CATALOG.dispenser(): parts[id] = need
		else:
			var sub := _brew_units(CATALOG, BEAKER, id, need)
			if sub < need * 0.99: print("   short of ", id, " ", sub, "/", need); return 0.0
			parts[id] = need
	var b = BEAKER.new()
	for id in r.get("catalysts", {}): b.contents[id] = float(r.catalysts[id])
	for id in parts: b.contents[id] = float(b.contents.get(id, 0.0)) + parts[id]
	b.heater = true
	b.target = (float(r.min_temp) + 20.0) if r.has("min_temp") else ((float(r.max_temp) - 20.0) if r.has("max_temp") else 300.0)
	b.react()
	for i in 200: b.step(0.05)
	return float(b.contents.get(target, 0.0))


func _brew_units(CATALOG, BEAKER, id: String, need: float) -> float:
	var r: Dictionary = CATALOG.recipe_for(id)
	var per_batch := float(r.makes[id])
	return _brew(CATALOG, BEAKER, id, ceilf(need / per_batch * 100.0) / 100.0)
