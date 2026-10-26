extends RefCounted
## Setting off something from the chemistry set (dev 2026-10-26: "fillies should accept and
## enjoy explosives, add explosives. adults too but ... more likely to be responsible and not as
## appreciative"). Cartoon explosives only: a flash, a bang, a puff of smoke, sparks, glitter or
## confetti, and soot at worst. Nopony is hurt and nothing breaks.
##
## Everypony within earshot reacts ("kaboom:<reagent>:<by>" physical reaction,
## director_contacts.gd, which tells fillies they may love it and grown-ups to be more sensible)
## and remembers it.
const CATALOG := preload("res://world/chemistry/chem_catalog.gd")
const BANG := "res://world/audio/designed/environment/thunder_01.ogg"
const FIZZ := "res://world/audio/designed/foley/steam_01.res"
## Ponies this close notice it; a bigger dose carries further.
const HEAR_BASE := 10.0
const STYLES := {
	"boom": {"light": Color(1.0, 0.75, 0.4), "energy": 6.0, "smoke": Color(0.25, 0.25, 0.25), "sparks": [], "sound": BANG, "pitch": 1.7},
	"sparks": {"light": Color(1.0, 0.95, 0.85), "energy": 9.0, "smoke": Color(0.5, 0.45, 0.4), "sparks": [Color(1, 0.9, 0.6), Color(1, 1, 1)], "sound": FIZZ, "pitch": 0.7},
	"firework": {"light": Color(1.0, 0.5, 0.9), "energy": 7.0, "smoke": Color(0.35, 0.35, 0.4), "sparks": [Color(1, 0.3, 0.6), Color(0.4, 0.7, 1), Color(1, 0.9, 0.3), Color(0.5, 1, 0.5)], "sound": BANG, "pitch": 2.1},
	"confetti": {"light": Color(1.0, 0.9, 0.6), "energy": 3.0, "smoke": Color(0, 0, 0, 0), "sparks": [Color(1, 0.4, 0.6), Color(0.4, 0.8, 1), Color(1, 0.85, 0.2), Color(0.6, 1, 0.5), Color(0.8, 0.5, 1)], "sound": BANG, "pitch": 3.0},
	"smoke": {"light": Color(0, 0, 0), "energy": 0.0, "smoke": Color(0.7, 0.7, 0.72), "sparks": [], "sound": FIZZ, "pitch": 0.9},
	"flash": {"light": Color(1, 1, 1), "energy": 16.0, "smoke": Color(0.8, 0.8, 0.8, 0.4), "sparks": [], "sound": FIZZ, "pitch": 1.4},
}


static func style_of(reagent: String) -> String:
	return str(CATALOG.reagent(reagent).get("blast", "boom"))


static func is_explosive(reagent: String) -> bool:
	return CATALOG.reagent(reagent).has("blast")


## The explosive with the most units in a dose, or "".
static func explosive_in(dose: Dictionary) -> String:
	var best := ""; var most := 0.0
	for id: String in dose:
		if is_explosive(id) and float(dose[id]) > most: most = float(dose[id]); best = id
	return best


## Sets off `units` of `reagent` at `at` (`game`: world/game.gd). `by` is who lit it ("player" or a pony id), `near` the
## pony it went off beside when it was a prank on her ("" otherwise).
static func blast(game: Node, at: Vector3, reagent: String, units: float, by: String, near: String = "") -> void:
	var tree := game.get_tree()
	var parent: Node = tree.current_scene if tree.current_scene != null else tree.root
	var style: Dictionary = STYLES.get(style_of(reagent), STYLES.boom)
	var scale := clampf(units / 10.0, 0.5, 3.0)
	var root := Node3D.new(); root.name = "ChemBlast"
	parent.add_child(root); root.global_position = at
	if float(style.energy) > 0.0:
		var light := OmniLight3D.new()
		light.light_color = style.light; light.light_energy = float(style.energy); light.omni_range = 6.0 * scale
		root.add_child(light)
		root.create_tween().tween_property(light, "light_energy", 0.0, 0.6)
	if (style.smoke as Color).a > 0.0: root.add_child(_puff(style.smoke, scale, 24, 1.4, 2.5))
	for color: Color in style.sparks: root.add_child(_burst(color, scale))
	_sound(root, str(style.sound), float(style.pitch))
	root.get_tree().create_timer(4.0).timeout.connect(root.queue_free)
	_witnesses(game, at, reagent, units, by, near)
	print("[chemistry] %s set off %.0fu %s at %s" % [by, units, reagent, at.round()])


static func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_color = color
	return mat


## A soft cloud of smoke rising and spreading.
static func _puff(color: Color, scale: float, amount: int, size: float, life: float) -> CPUParticles3D:
	var puff := CPUParticles3D.new()
	var quad := QuadMesh.new(); quad.size = Vector2.ONE * size * 0.5 * scale; quad.material = _material(color)
	puff.mesh = quad
	puff.amount = amount; puff.one_shot = true; puff.explosiveness = 0.9; puff.lifetime = life
	puff.direction = Vector3.UP; puff.spread = 70.0
	puff.initial_velocity_min = 0.8 * scale; puff.initial_velocity_max = 2.2 * scale
	puff.gravity = Vector3(0, 0.6, 0); puff.damping_min = 1.5; puff.damping_max = 2.5
	puff.scale_amount_min = 0.8; puff.scale_amount_max = 2.0
	var fade := Gradient.new(); fade.set_color(0, color); fade.set_color(1, Color(color, 0.0))
	puff.color_ramp = fade
	puff.emitting = true
	return puff


## Sparks, glitter or confetti flying out and falling.
static func _burst(color: Color, scale: float) -> CPUParticles3D:
	var burst := CPUParticles3D.new()
	var quad := QuadMesh.new(); quad.size = Vector2.ONE * 0.06; quad.material = _material(color)
	burst.mesh = quad
	burst.amount = int(40 * scale); burst.one_shot = true; burst.explosiveness = 1.0; burst.lifetime = 1.6
	burst.direction = Vector3.UP; burst.spread = 180.0
	burst.initial_velocity_min = 3.0 * scale; burst.initial_velocity_max = 7.0 * scale
	burst.gravity = Vector3(0, -6.0, 0); burst.damping_min = 0.5; burst.damping_max = 1.5
	var fade := Gradient.new(); fade.set_color(0, color); fade.set_color(1, Color(color, 0.0))
	burst.color_ramp = fade
	burst.emitting = true
	return burst


static func _sound(root: Node3D, path: String, pitch: float) -> void:
	if not ResourceLoader.exists(path): return
	var player := AudioStreamPlayer3D.new()
	player.stream = load(path); player.pitch_scale = pitch; player.volume_db = 2.0
	player.unit_size = 8.0; player.max_distance = 80.0
	root.add_child(player); player.play()


## Ponies nearby react and remember it.
static func _witnesses(game: Node, at: Vector3, reagent: String, units: float, by: String, near: String) -> void:
	var mares: Array = game.get("mares") if game.get("mares") is Array else []
	var hear := HEAR_BASE * clampf(units / 10.0, 0.7, 2.5)
	var context: Node = game.get("world_context")
	var witnesses: Array = []
	for pony: Variant in mares:
		if not is_instance_valid(pony) or not (pony as Node3D).is_inside_tree(): continue
		if (pony as Node3D).global_position.distance_to(at) > hear: continue
		var id := str((pony as Node).get_meta("relationship_id", ""))
		if id.is_empty() and pony.get("identity") != null: id = str(pony.identity.id)
		if id.is_empty(): continue
		witnesses.append(id)
		if bool(pony.get("sleeping")): continue
		var expressions: Variant = pony.get("expressions")
		if expressions != null and expressions.has_method("boop"): expressions.boop()
		if pony.has_signal("physical_reaction"): pony.emit_signal("physical_reaction", "kaboom:%s:%s:%s" % [reagent, by, "you" if id == near else ""])
	if context != null and not witnesses.is_empty():
		var who := "Anon" if by == "player" else by.replace("_", " ").capitalize()
		var subjects: Array = witnesses.duplicate()
		if by not in subjects: subjects.append(by)
		context.record("explosion", "%s set off some %s nearby: %s. Nopony was hurt." % [who, CATALOG.name_of(reagent).to_lower(), str(CATALOG.reagent(reagent).get("description", "a bang")).trim_suffix(".")], witnesses, subjects)
