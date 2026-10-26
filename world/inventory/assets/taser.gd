extends Node3D
## Anon's taser (dev 2026-10-26: "Hi id like a taser to ragdoll ponies with"). Click (desktop) or
## trigger (VR) fires two probes on thin wires up to RANGE metres. A pony they hit locks up, tips
## over away from you and lies limp and twitching (pony_throw.gd knock) while the current runs,
## then gets up by herself. Cartoon: no injury. She does remember it, trusts Anon less and her AI
## reacts (director_contacts.gd, relationship_runtime.gd "tased").
## It never fires at a foal (identity.filly): the age rules (AGENT_HANDOFF.md) stay hard-coded.
## No model or icon files: the shape and the briefcase icon are built here, like spray_bottle.gd.
const RANGE := 7.0
## A shot that just misses a pony's body still counts within this many metres of her chest.
const AIM_SLACK := 0.35
## Seconds the current runs down the wires (one trigger pull), and how long she then lies limp.
const CYCLE := 3.0
const STUN := 4.0
const RELOAD := 1.5
var next_shot := 0.0
var muzzle: Node3D
var trigger: MeshInstance3D
var _shot: Dictionary = {}
var _buzz: AudioStreamWAV
static var _icon: Texture2D
static var _scene: PackedScene


static func scene() -> PackedScene:
	if _scene == null:
		var root := Node3D.new(); root.name = "Taser"
		root.set_script(load("res://world/inventory/assets/taser.gd"))
		_scene = PackedScene.new(); _scene.pack(root)
		root.free()
	return _scene


## The briefcase icon: a yellow taser on its side, drawn here (a .svg would need importing).
static func icon() -> Texture2D:
	if _icon != null: return _icon
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var ink := Color("2b2b38")
	for part: Array in [[Rect2i(8, 18, 48, 18), ink], [Rect2i(10, 20, 44, 14), Color("f2c230")],
			[Rect2i(46, 20, 8, 14), Color("3a3a48")], [Rect2i(14, 34, 14, 22), ink], [Rect2i(16, 34, 10, 20), Color("4a4a58")],
			[Rect2i(28, 34, 4, 8), ink], [Rect2i(56, 22, 6, 3), Color("8fd8ff")], [Rect2i(56, 29, 6, 3), Color("8fd8ff")]]:
		image.fill_rect(part[0], part[1])
	_icon = ImageTexture.create_from_image(image)
	return _icon


func _ready() -> void:
	var body := BoxMesh.new(); body.size = Vector3(.036, .046, .15)
	_part(body, Vector3(0, .05, -.045), Color("f2c230"))
	var cartridge := BoxMesh.new(); cartridge.size = Vector3(.04, .05, .035)
	_part(cartridge, Vector3(0, .05, -.135), Color("3a3a48"))
	var grip := BoxMesh.new(); grip.size = Vector3(.03, .09, .036)
	var handle := _part(grip, Vector3(0, -.005, .01), Color("2b2b38")); handle.rotation.x = .28
	var lever := BoxMesh.new(); lever.size = Vector3(.01, .028, .01)
	trigger = _part(lever, Vector3(0, .013, -.035), Color("2b2b38")); trigger.rotation.x = .2
	muzzle = Node3D.new(); muzzle.position = Vector3(0, .05, -.155); add_child(muzzle)


func _part(mesh: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new(); node.mesh = mesh; node.position = at
	var material := StandardMaterial3D.new(); material.albedo_color = color; material.roughness = .55
	node.material_override = material; add_child(node); return node


func configure_body(_body: RigidBody3D, collision: CollisionShape3D) -> void:
	var shape := BoxShape3D.new(); shape.size = Vector3(.045, .13, .17); collision.shape = shape
	collision.position = Vector3(0, .025, -.05)


## Fires along the muzzle, or along `aim` (desktop: the camera, so the shot goes where you look).
func fire(aim := Transform3D(Basis.IDENTITY, Vector3.INF)) -> void:
	var now := Time.get_ticks_msec() * .001
	if now < next_shot or muzzle == null or not is_inside_tree(): return
	next_shot = now + RELOAD
	trigger.rotation.x = -.35
	var squeeze := create_tween(); squeeze.tween_property(trigger, "rotation:x", .2, .25)
	var shot := aimed(aim)
	var pony: Node3D = shot.pony
	var from: Vector3 = shot.from
	var point: Vector3 = shot.point
	if pony != null and foal(pony):
		# The safety stays on: nothing leaves the cartridge (the hint says why, briefcase_inventory.gd).
		print("[taser] safety: %s is a foal; not firing" % str(pony.get("identity").get("id")))
		return
	_clear_shot()
	var tased := false
	if pony != null:
		tased = pony.call("tase", from, STUN) == true
		print("[taser] %s %s at %.1f m" % [str(pony.name), "down" if tased else "zapped (could not fall now)", from.distance_to(point)])
	_shot = {"pony": pony, "local": pony.to_local(point) if pony != null else point, "until": now + (CYCLE if pony != null else .8), "live": pony != null}
	_build_shot()
	set_process(true)


## Where a shot along `aim` (or the muzzle) goes: {"from", "point", "pony"} (pony may be null).
func aimed(aim := Transform3D(Basis.IDENTITY, Vector3.INF)) -> Dictionary:
	var from: Vector3 = aim.origin if aim.origin.is_finite() else muzzle.global_position
	var direction: Vector3 = -(aim.basis.z if aim.origin.is_finite() else muzzle.global_basis.z).normalized()
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * RANGE, 1 | 2)
	var body := get_parent() as CollisionObject3D
	if body != null: query.exclude = [body.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var reach: float = from.distance_to(hit.position) if not hit.is_empty() else RANGE
	var point: Vector3 = hit.position if not hit.is_empty() else from + direction * RANGE
	var pony: Node3D = null
	if not hit.is_empty():
		var actor: Node = hit.collider
		while actor != null and not actor.has_method("tase"): actor = actor.get_parent()
		pony = actor as Node3D
	if pony == null: pony = _near_ray(from, direction, reach)
	if pony != null and point.distance_to(_chest(pony)) > 1.0: point = _chest(pony)
	return {"from": from, "point": point, "pony": pony}


static func foal(pony: Node3D) -> bool:
	var identity: Resource = pony.get("identity")
	return identity != null and identity.get("filly") == true


## The pony closest to the shot's line within AIM_SLACK of her chest, nearer than the first wall.
func _near_ray(from: Vector3, direction: Vector3, reach: float) -> Node3D:
	var best: Node3D = null; var best_gap := INF
	for candidate: Node in get_tree().get_nodes_in_group("ai_characters"):
		var pony := candidate as Node3D
		if pony == null or not pony.has_method("tase") or not pony.is_visible_in_tree(): continue
		var to: Vector3 = _chest(pony) - from
		var along := to.dot(direction)
		if along <= 0.0 or along > reach + .5: continue
		var gap := (to - direction * along).length()
		var slack: float = AIM_SLACK * float(pony.get("body_scale") if pony.get("body_scale") != null else 1.0)
		if gap < slack and gap < best_gap: best = pony; best_gap = gap
	return best


static func _chest(pony: Node3D) -> Vector3:
	var scale: float = float(pony.get("body_scale")) if pony.get("body_scale") != null else 1.0
	return pony.global_position + Vector3.UP * .6 * scale


func _probe_point() -> Vector3:
	var pony: Node3D = _shot.get("pony")
	if is_instance_valid(pony): return pony.to_global(_shot.local)
	return _shot.local


func _build_shot() -> void:
	var root: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	var effect := Node3D.new(); effect.name = "TaserShot"; root.add_child(effect)
	_shot.node = effect
	var wires := MeshInstance3D.new(); wires.mesh = ImmediateMesh.new()
	var ink := StandardMaterial3D.new(); ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color = Color("c9b48a"); wires.material_override = ink
	wires.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	effect.add_child(wires); _shot.wires = wires
	if not _shot.live: return
	var sparks := CPUParticles3D.new()
	var dot := SphereMesh.new(); dot.radius = .006; dot.height = .012; dot.radial_segments = 4; dot.rings = 2
	var glow := StandardMaterial3D.new(); glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(.75, .9, 1.0)
	dot.material = glow; sparks.mesh = dot
	sparks.amount = 28; sparks.lifetime = .22; sparks.explosiveness = .2
	sparks.direction = Vector3.UP; sparks.spread = 180.0
	sparks.initial_velocity_min = .8; sparks.initial_velocity_max = 2.4
	sparks.gravity = Vector3(0, -6.0, 0); sparks.local_coords = false
	effect.add_child(sparks); _shot.sparks = sparks
	var light := OmniLight3D.new(); light.light_color = Color(.6, .8, 1.0); light.omni_range = 1.6
	light.shadow_enabled = false
	effect.add_child(light); _shot.light = light
	var sound := AudioStreamPlayer3D.new(); sound.stream = _buzz_stream()
	sound.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	sound.max_distance = 18.0; sound.unit_size = 2.0; sound.volume_db = -16.0
	effect.add_child(sound); sound.play(); _shot.sound = sound


func _process(_delta: float) -> void:
	if _shot.is_empty() or not is_instance_valid(_shot.get("node")) or (_shot.live and not is_instance_valid(_shot.get("pony"))):
		_clear_shot(); set_process(false); return
	var now := Time.get_ticks_msec() * .001
	var end := _probe_point()
	# Walking off past the wires' length pulls the probes out and ends the current.
	if now >= float(_shot.until) or not is_instance_valid(muzzle) or muzzle.global_position.distance_to(end) > RANGE * 1.3:
		_clear_shot(); set_process(false); return
	var start: Vector3 = muzzle.global_position
	var mesh: ImmediateMesh = (_shot.wires as MeshInstance3D).mesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var side: Vector3 = (end - start).cross(Vector3.UP).normalized() * .012
	var sag := clampf(start.distance_to(end) * .04, .01, .2)
	for wire in [-1.0, 1.0]:
		var previous: Vector3 = start + side * wire
		for i in range(1, 11):
			var t := i / 10.0
			var point: Vector3 = start.lerp(end, t) + side * wire * (1.0 - t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
			mesh.surface_add_vertex(previous); mesh.surface_add_vertex(point)
			previous = point
	mesh.surface_end()
	if _shot.live:
		(_shot.sparks as Node3D).global_position = end
		var light := _shot.light as OmniLight3D
		light.global_position = end
		light.light_energy = randf_range(.4, 3.0) if randf() < .7 else 0.0


func _clear_shot() -> void:
	if is_instance_valid(_shot.get("node")): (_shot.node as Node).queue_free()
	_shot = {}


func _exit_tree() -> void:
	_clear_shot()


## A looping electric crackle: mains-like hum under hard random snaps, made here (no sound file).
func _buzz_stream() -> AudioStreamWAV:
	if _buzz != null: return _buzz
	var rate := 22050
	var frames := rate / 2
	var data := PackedByteArray(); data.resize(frames * 2)
	var snap := 0.0
	for i in frames:
		var t := float(i) / rate
		if randf() < .004: snap = randf_range(.5, 1.0)
		snap *= .985
		var hum := sin(TAU * 120.0 * t) * .25 + (fmod(t * 240.0, 1.0) * 2.0 - 1.0) * .15
		var value := clampf(hum + randf_range(-1.0, 1.0) * (.12 + snap), -1.0, 1.0)
		data.encode_s16(i * 2, int(value * 26000.0))
	_buzz = AudioStreamWAV.new()
	_buzz.format = AudioStreamWAV.FORMAT_16_BITS; _buzz.mix_rate = rate; _buzz.stereo = false
	_buzz.data = data
	_buzz.loop_mode = AudioStreamWAV.LOOP_FORWARD; _buzz.loop_begin = 0; _buzz.loop_end = frames
	return _buzz
