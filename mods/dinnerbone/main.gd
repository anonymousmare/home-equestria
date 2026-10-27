extends Node
## Dinnerbone: the example mod. Every pony is drawn upside down, standing on her ears with her
## hooves in the air, and walks, sits, flies and talks like that. Her body, collision and AI are
## untouched; only her model node (the visual under her ModelPivot) is turned over.

const PONY := "res://world/characters/locomotion/pony_locomotion.gd"

## pony -> the model node already turned over, so a rebuilt model gets turned too.
var _turned: Dictionary = {}


func _ready() -> void:
	Mods.on_node(PONY, _turn)


func _process(_delta: float) -> void:
	# A pony's model is rebuilt when she changes clothes or her rig reloads.
	for pony: Variant in _turned.keys():
		if not is_instance_valid(pony): _turned.erase(pony); continue
		if pony.get("_model") != _turned[pony]: _turn(pony)


func _turn(pony: Node) -> void:
	var model: Variant = pony.get("_model")
	var skeleton: Variant = pony.get("skeleton")
	if not model is Node3D or not skeleton is Skeleton3D or not is_instance_valid(model): return
	if _turned.get(pony) == model: return
	# Her height in model space, from the highest bone at rest (the ear tips).
	var to_model: Transform3D = (model as Node3D).global_transform.affine_inverse() * (skeleton as Skeleton3D).global_transform
	var height := 0.0
	for bone in (skeleton as Skeleton3D).get_bone_count():
		height = maxf(height, (to_model * (skeleton as Skeleton3D).get_bone_global_rest(bone).origin).y)
	# Turn over about her forward axis, then lift so the ears touch the ground.
	(model as Node3D).transform = Transform3D(Basis(Vector3.BACK, PI), Vector3(0, height, 0)) * (model as Node3D).transform
	_turned[pony] = model
