extends Node
## Developer teleport (dev 2026-10-26: "i wanna be able to teleport on the map with
## ctrl+shift+click"). Developer builds, desktop rig (game_player_rig.gd):
## - Ctrl+Shift+click on the map (M, or the corner map) goes to that spot. Like the VR map
##   (world_map_vr.gd) the player hovers high above while the zone streams in, then lands on the
##   first solid ground under the spot.
## - Ctrl+Shift+click in the world goes where the crosshair points: straight there when it hits
##   something, else to the terrain the view ray meets, the same way as the map.
const SHUTDOWN := preload("res://world/shutdown_waits.gd")
const HOVER := 400.0
const TIMEOUT := 60.0
const RAY := 3000.0
var game: Node
var _generation := 0
var _priority_zone := ""
var _eat_release := false
## The rig's flying/controls_locked from before the hover, kept across a teleport that replaces another.
var _saved: Dictionary = {}


func setup(host: Node) -> void:
	game = host
	_connect_map.call_deferred()


func _connect_map() -> void:
	var map: Node = game.get("world_map")
	if is_instance_valid(map) and map.has_signal("teleport_requested") and not map.teleport_requested.is_connected(_on_map_teleport):
		map.teleport_requested.connect(_on_map_teleport)


func _on_map_teleport(xz: Vector2) -> void:
	var map: Node = game.get("world_map")
	if is_instance_valid(map) and map.has_method("set_expanded"): map.set_expanded(false)
	teleport_to(xz)


func _input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or click.button_index != MOUSE_BUTTON_LEFT: return
	if not click.pressed:
		if _eat_release: _eat_release = false; get_viewport().set_input_as_handled()
		return
	if not (click.ctrl_pressed and click.shift_pressed) or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: return
	var body := _body()
	var camera := get_viewport().get_camera_3d()
	if body == null or camera == null or bool(body.get("controls_locked")): return
	get_viewport().set_input_as_handled()
	_eat_release = true
	var from := camera.global_position
	var forward := -camera.global_basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + forward * RAY, 1, [(body as CollisionObject3D).get_rid()] if body is CollisionObject3D else [])
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var point: Vector3 = hit.position
		# A pony or another character: land just in front of her, not on her back.
		if hit.collider is CharacterBody3D: point -= Vector3(forward.x, 0.0, forward.z).normalized() * 1.2
		_generation += 1
		_place(body, point + Vector3.UP * 0.15)
		print("[teleport] to %s" % point.round())
		return
	var ground := _terrain_hit(from, forward)
	if ground.is_finite(): teleport_to(Vector2(ground.x, ground.z))
	else: print("[teleport] nothing under the crosshair")


## Where the view ray first dips under the terrain heightmap (collision is not streamed far out).
func _terrain_hit(from: Vector3, forward: Vector3) -> Vector3:
	if not is_instance_valid(WorldTerrain.instance): return Vector3.INF
	var step := 4.0
	var distance := step
	while distance < RAY * 2.0:
		var point := from + forward * distance
		var h: float = WorldTerrain.instance.height_at(point)
		if is_finite(h) and point.y <= h: return Vector3(point.x, h, point.z)
		distance += step
		step = minf(step * 1.05, 25.0)
	return Vector3.INF


func _body() -> CharacterBody3D:
	return game.get("player") as CharacterBody3D if game != null else null


func _place(body: CharacterBody3D, at: Vector3) -> void:
	if is_instance_valid(body.get("seat")) and body.has_method("stand_up"): body.stand_up()
	body.global_position = at
	body.velocity = Vector3.ZERO
	body.reset_physics_interpolation()
	if is_instance_valid(WorldTerrain.instance): WorldTerrain.instance.focus(at)


## Map teleport: hover above the spot until its zone and ground are there, then land.
func teleport_to(xz: Vector2) -> void:
	var body := _body()
	if body == null: return
	_generation += 1
	var generation := _generation
	var target := Vector3(xz.x, 0.0, xz.y)
	var ground: float = WorldTerrain.instance.height_at(target) if is_instance_valid(WorldTerrain.instance) else NAN
	if not is_finite(ground): ground = body.global_position.y
	var zone := ZoneManager.zone_contains(target, true)
	_release_priority()
	if zone != "":
		_priority_zone = zone
		ZoneManager.prioritize_zone(zone)
		# Cloudsdale's ground is its platforms, not the heightmap far below.
		ground = maxf(ground, ZoneManager.zone_origin(zone).y)
	if _saved.is_empty(): _saved = {"flying": bool(body.get("flying")), "controls_locked": bool(body.get("controls_locked"))}
	body.set("flying", true)
	body.set("controls_locked", true)
	_place(body, Vector3(target.x, ground + HOVER, target.z))
	print("[teleport] to X %.0f Z %.0f%s: waiting for the ground" % [xz.x, xz.y, (" (" + zone + ")") if zone != "" else ""])
	var landing := Vector3.INF
	var deadline := Time.get_ticks_msec() + int(TIMEOUT * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if not await SHUTDOWN.physics_frame(self) or generation != _generation or not is_instance_valid(body): return
		if zone != "" and not ZoneManager.is_ready(zone): continue
		landing = _landing_point(body, target, ground, zone)
		if landing.is_finite(): break
		if not await SHUTDOWN.seconds(self, 0.1) or generation != _generation or not is_instance_valid(body): return
	_restore(body)
	_release_priority()
	if not landing.is_finite():
		# No collider yet: the heightmap is the floor to come (player_ground_rescue.gd catches the rest).
		landing = Vector3(target.x, ground, target.z)
		print("[teleport] ground not ready; dropped onto the heightmap")
	_place(body, landing + Vector3.UP * 0.3)
	print("[teleport] landed at %s" % body.global_position.round())


func _restore(body: CharacterBody3D) -> void:
	for key: String in _saved: body.set(key, _saved[key])
	_saved.clear()


func _release_priority() -> void:
	if _priority_zone != "" and str(ZoneManager.get("_priority_zone")) == _priority_zone: ZoneManager.prioritize_zone("")
	_priority_zone = ""


## The first safe floor under `target`, searching outward a little (from world_map_vr.gd).
func _landing_point(body: CharacterBody3D, target: Vector3, ground: float, zone: String) -> Vector3:
	var space := body.get_world_3d().direct_space_state
	var sky := zone != "" and bool(ZoneManager._defs[zone].get("flight_only", false))
	for radius in [0.0, 2.0, 4.0, 8.0, 16.0]:
		for index in (1 if radius == 0.0 else 8):
			var point: Vector3 = target + Vector3(cos(index * TAU / 8), 0, sin(index * TAU / 8)) * radius
			var query := PhysicsRayQueryParameters3D.create(Vector3(point.x, ground + 1500.0, point.z), Vector3(point.x, ground - 100.0, point.z), 1, [body.get_rid()])
			var hit := space.intersect_ray(query)
			if hit.is_empty() or hit.collider is CharacterBody3D or hit.normal.y < 0.7: continue
			if sky and not ZoneManager._loaded[zone].is_ancestor_of(hit.collider): continue
			return hit.position
	return Vector3.INF


func _exit_tree() -> void:
	_generation += 1
	if is_instance_valid(_body()): _restore(_body())
	_release_priority()
