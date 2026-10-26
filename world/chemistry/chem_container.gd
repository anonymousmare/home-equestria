extends RefCounted
## Vessels for the chemistry set (dev 2026-10-26: "make basic test tubes and potion bottles and
## cups and have a dropdown menu for beaker type"). Built from plain primitives like the spray
## bottle (world/inventory/assets/spray_bottle.gd), so there are no model files: glass you can
## see through, ceramic you cannot, and the liquid tinted by what is inside and sinking as it is
## drunk. Origin at the middle of the base, +Y up, real-world metres (a pony's scale is applied
## by whoever shows it).
const TYPES := {
	"test_tube": {"name": "Test tube", "capacity": 10.0, "height": 0.15, "glass": true},
	"potion_bottle": {"name": "Potion bottle", "capacity": 30.0, "height": 0.13, "glass": true},
	"cup": {"name": "Cup", "capacity": 25.0, "height": 0.08, "glass": false},
	"mug": {"name": "Mug", "capacity": 35.0, "height": 0.10, "glass": false},
	"flask": {"name": "Flask", "capacity": 60.0, "height": 0.16, "glass": true},
	"beaker": {"name": "Beaker", "capacity": 100.0, "height": 0.12, "glass": true},
}
const ORDER := ["test_tube", "potion_bottle", "cup", "mug", "flask", "beaker"]
const DEFAULT := "potion_bottle"
const GLASS := Color(0.82, 0.93, 1.0, 0.22)
const CERAMIC := Color(0.93, 0.9, 0.84)
const MUG := Color(0.62, 0.4, 0.26)
const CORK := Color(0.72, 0.52, 0.32)


static func has(type: String) -> bool:
	return TYPES.has(type)


static func valid(type: String) -> String:
	return type if TYPES.has(type) else DEFAULT


static func name_of(type: String) -> String:
	return str(TYPES.get(type, TYPES[DEFAULT]).name)


## "bottle", "mug"...: what to call it in "a mug of tea".
static func noun(type: String) -> String:
	return "bottle" if type == "potion_bottle" else name_of(type).to_lower()


static func capacity(type: String) -> float:
	return float(TYPES.get(type, TYPES[DEFAULT]).capacity)


static func height(type: String) -> float:
	return float(TYPES.get(type, TYPES[DEFAULT]).height)


## A finished vessel with `liquid` colour filled to `fraction` (0..1). Meta: "type",
## "rim_local" (centre of the opening), "inner_height", "liquid" (the liquid mesh node).
static func build(type: String, liquid: Color, fraction := 1.0) -> Node3D:
	type = valid(type)
	var root := Node3D.new()
	root.name = "Chem_" + type
	root.set_meta("type", type)
	var spec: Dictionary = TYPES[type]
	var glass := Color(GLASS) if bool(spec.glass) else (MUG if type == "mug" else CERAMIC)
	var liquid_node: MeshInstance3D
	var inner := 0.1
	match type:
		"test_tube":
			_cylinder(root, 0.0115, 0.0115, 0.1385, Vector3(0, 0.08075, 0), glass)
			_sphere(root, 0.0115, Vector3(0, 0.0115, 0), glass)
			_torus(root, 0.0115, 0.0016, Vector3(0, 0.15, 0), glass)
			liquid_node = _liquid_cylinder(root, 0.0098, Vector3(0, 0.0115, 0))
			inner = 0.125
		"potion_bottle":
			_sphere(root, 0.04, Vector3(0, 0.04, 0), glass)
			_cylinder(root, 0.013, 0.013, 0.06, Vector3(0, 0.105, 0), glass)
			_cylinder(root, 0.0155, 0.0155, 0.014, Vector3(0, 0.138, 0), CORK)
			liquid_node = _liquid_sphere(root, 0.036, Vector3(0, 0.04, 0))
			inner = 0.072
			root.set_meta("rim_local", Vector3(0, 0.132, 0))
		"cup":
			_cylinder(root, 0.046, 0.032, 0.08, Vector3(0, 0.04, 0), glass)
			_torus(root, 0.046, 0.003, Vector3(0, 0.08, 0), glass)
			_handle(root, Vector3(0.048, 0.042, 0), glass)
			liquid_node = _liquid_cylinder(root, 0.029, Vector3(0, 0.006, 0))
			inner = 0.068
		"mug":
			_cylinder(root, 0.042, 0.04, 0.10, Vector3(0, 0.05, 0), glass)
			_torus(root, 0.042, 0.003, Vector3(0, 0.10, 0), glass)
			_handle(root, Vector3(0.046, 0.052, 0), glass)
			liquid_node = _liquid_cylinder(root, 0.033, Vector3(0, 0.007, 0))
			inner = 0.086
		"flask":
			_cylinder(root, 0.014, 0.05, 0.12, Vector3(0, 0.06, 0), glass)
			_cylinder(root, 0.015, 0.015, 0.04, Vector3(0, 0.14, 0), glass)
			_torus(root, 0.015, 0.0018, Vector3(0, 0.16, 0), glass)
			liquid_node = _liquid_cylinder(root, 0.04, Vector3(0, 0.004, 0))
			inner = 0.105
			root.set_meta("cone", true)
		_:
			_cylinder(root, 0.042, 0.04, 0.12, Vector3(0, 0.06, 0), glass)
			_torus(root, 0.042, 0.0025, Vector3(0, 0.12, 0), glass)
			liquid_node = _liquid_cylinder(root, 0.034, Vector3(0, 0.005, 0))
			inner = 0.105
	if not root.has_meta("rim_local"): root.set_meta("rim_local", Vector3(0, float(spec.height), 0))
	root.set_meta("inner_height", inner)
	root.set_meta("liquid", liquid_node)
	root.set_meta("liquid_base", liquid_node.position)
	root.set_meta("liquid_kind", "sphere" if type == "potion_bottle" else ("cone" if type == "flask" else "cylinder"))
	set_liquid(root, liquid)
	set_level(root, fraction)
	return root


## The liquid's colour (alpha kept see-through).
static func set_liquid(root: Node3D, color: Color) -> void:
	var node := root.get_meta("liquid") as MeshInstance3D
	if node == null: return
	var mat := node.material_override as StandardMaterial3D
	mat.albedo_color = Color(color.r, color.g, color.b, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b) * 0.18


## Fill level 0..1: the liquid shrinks from the top, staying on the base.
static func set_level(root: Node3D, fraction: float) -> void:
	var node := root.get_meta("liquid") as MeshInstance3D
	if node == null: return
	fraction = clampf(fraction, 0.0, 1.0)
	node.visible = fraction > 0.01
	var inner: float = root.get_meta("inner_height")
	var base: Vector3 = root.get_meta("liquid_base")
	var kind := str(root.get_meta("liquid_kind"))
	if kind == "sphere":
		# The round bottle's liquid is a sphere flattened toward its base.
		var s := clampf(fraction, 0.02, 1.0)
		node.scale = Vector3(1, s, 1)
		node.position = base + Vector3(0, -0.036 * (1.0 - s), 0)
	elif kind == "cone":
		# The flask narrows upward: the liquid is a cone whose top follows the wall.
		var h := maxf(0.001, inner * fraction)
		var wall_bottom := 0.05; var wall_top := 0.014; var wall_h := 0.12
		var mesh := node.mesh as CylinderMesh
		mesh.bottom_radius = (wall_bottom - (wall_bottom - wall_top) * (base.y / wall_h)) * 0.9
		mesh.top_radius = (wall_bottom - (wall_bottom - wall_top) * (minf(base.y + h, wall_h) / wall_h)) * 0.9
		node.scale = Vector3(1, h, 1)
		node.position = base + Vector3(0, h * 0.5, 0)
	else:
		var h := maxf(0.001, inner * fraction)
		node.scale = Vector3(1, h, 1)
		node.position = base + Vector3(0, h * 0.5, 0)


## The liquid surface is at this height above the base.
static func surface_height(root: Node3D, fraction: float) -> float:
	return (root.get_meta("liquid_base") as Vector3).y + float(root.get_meta("inner_height")) * clampf(fraction, 0.0, 1.0)


## A little steam rising from the opening (hot drinks). Returns the emitter.
static func add_steam(root: Node3D) -> CPUParticles3D:
	var steam := CPUParticles3D.new()
	steam.name = "Steam"
	var quad := QuadMesh.new(); quad.size = Vector2(0.03, 0.03)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = _puff_texture()
	quad.material = mat
	steam.mesh = quad
	steam.amount = 8; steam.lifetime = 1.6; steam.local_coords = false
	steam.direction = Vector3.UP; steam.spread = 12.0
	steam.initial_velocity_min = 0.03; steam.initial_velocity_max = 0.07
	steam.gravity = Vector3(0, 0.02, 0)
	steam.scale_amount_min = 0.7; steam.scale_amount_max = 1.6
	var fade := Gradient.new(); fade.set_color(0, Color(1, 1, 1, 0.35)); fade.set_color(1, Color(1, 1, 1, 0.0))
	steam.color_ramp = fade
	steam.position = root.get_meta("rim_local")
	root.add_child(steam)
	steam.emitting = true
	return steam


# ------------------------------------------------------------------ primitives

static var _puff: GradientTexture2D

## A soft round blob for steam, so the particles are not squares.
static func _puff_texture() -> GradientTexture2D:
	if _puff == null:
		var fade := Gradient.new()
		fade.set_color(0, Color(1, 1, 1, 1)); fade.set_color(1, Color(1, 1, 1, 0))
		_puff = GradientTexture2D.new()
		_puff.gradient = fade; _puff.fill = GradientTexture2D.FILL_RADIAL
		_puff.fill_from = Vector2(0.5, 0.5); _puff.fill_to = Vector2(1.0, 0.5)
		_puff.width = 64; _puff.height = 64
	return _puff

static func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.12 if color.a < 0.9 else 0.7
	if color.a < 0.9:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.metallic_specular = 0.9
	return mat


static func _part(root: Node3D, mesh: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh; node.position = at; node.material_override = _material(color)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)
	return node


static func _cylinder(root: Node3D, top: float, bottom: float, h: float, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top; mesh.bottom_radius = bottom; mesh.height = h
	mesh.radial_segments = 20; mesh.rings = 1
	return _part(root, mesh, at, color)


static func _sphere(root: Node3D, r: float, at: Vector3, color: Color, hemisphere := 1.0) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = r; mesh.height = r * 2.0 * (1.0 if hemisphere >= 1.0 else 1.0)
	mesh.radial_segments = 20; mesh.rings = 12
	var node := _part(root, mesh, at, color)
	return node


static func _torus(root: Node3D, radius: float, tube: float, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = maxf(0.001, radius - tube); mesh.outer_radius = radius + tube
	mesh.rings = 16; mesh.ring_segments = 6
	return _part(root, mesh, at, Color(color.r, color.g, color.b, maxf(color.a, 0.45)))


static func _handle(root: Node3D, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.012; mesh.outer_radius = 0.021
	mesh.rings = 14; mesh.ring_segments = 6
	var node := _part(root, mesh, at, color)
	node.rotation = Vector3(PI * 0.5, 0, 0)
	return node


static func _liquid_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.2
	return mat


static func _liquid_cylinder(root: Node3D, radius: float, base: Vector3) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius; mesh.bottom_radius = radius; mesh.height = 1.0
	mesh.radial_segments = 20; mesh.rings = 1
	var node := MeshInstance3D.new()
	node.mesh = mesh; node.position = base; node.material_override = _liquid_material()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)
	return node


static func _liquid_sphere(root: Node3D, radius: float, base: Vector3) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius; mesh.height = radius * 2.0
	mesh.radial_segments = 20; mesh.rings = 12
	var node := MeshInstance3D.new()
	node.mesh = mesh; node.position = base; node.material_override = _liquid_material()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)
	return node
