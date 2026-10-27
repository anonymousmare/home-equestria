extends RefCounted
## Compliant chest lift with finite hind-leg reach and damped head/limb motion.

const SOLVER := preload("res://world/characters/locomotion/limb_solver.gd")
const CRADLE_REST := preload("res://world/characters/locomotion/cradle_rest.gd")
const REST_FLEX := {"lowerArm": 15.0, "wrist": -15.0, "hand": -8.0, "finger": -4.0,
	"tibia": -5.0, "legLower": 15.0, "tarsal": -10.0, "hoof": -5.0}
var pony: CharacterBody3D
var active := false
var blend := 0.0
var pitch := 0.0
var pitch_velocity := 0.0
var swing := Vector2.ZERO
var swing_velocity := Vector2.ZERO
var head_angles := Vector3.ZERO
var head_velocity := Vector3.ZERO
## Eye rotation left after the neck has aimed, in model-forward coordinates.
var eye_angles := Vector3.ZERO
var initial_grip := Vector3.ZERO
var grip_name := "chest"
var look_target := Vector3.ZERO
var grips: Dictionary = {}
var supports: Array[bool] = [false, false, false, false]
var anchors: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var anchor_bases: Array[Basis] = [Basis.IDENTITY, Basis.IDENTITY, Basis.IDENTITY, Basis.IDENTITY]
var release_blends := [1.0, 1.0, 1.0, 1.0]
var release_poses: Array = [[], [], [], []]
var start_pose: Array[Transform3D] = []
var rejected_contacts := 0
var pivot_center := Vector3.ZERO
var start_pivot := Transform3D.IDENTITY
var grip_angles := Vector2.ZERO
var grip_angular_velocity := Vector2.ZERO
## Forelegs dangle loosely while she is carried (dev 2026-09-28: "they've been broken for a
## while"). The joint-limited standing pose hung them as stiff, pressed-together columns. After
## the joint limits, each upper arm turns its leg toward a point below and a little in front of
## her chest, slightly apart; carpus and fetlock fold softly; a damped spring swings them when
## she moves and settles them again.
const DANGLE_FORWARD := .35 # How far in front of her chest the hooves hang, per unit of drop.
const DANGLE_LAG := .015 # Leg swing per m/s² of her acceleration (the legs trail behind).
## Bridal carry (desktop, player/interactor.gd): she lies across his chest in a shallow V, rump
## lowest, belly toward him and up; chest and head rise on his left, her upper back along his left
## arm; hind legs rise on his right, over his right forearm, hooves up by his right shoulder.
## `cradle` eases 0..1 toward `cradle_goal`; it turns her body, moves the held point from her chest
## to the middle of her barrel, and aims the legs (_cradle_legs).
## "His frame" below: x his right, y up, z toward him. Her root is turned a quarter left of him
## (interactor CRADLE_YAW), so his (x, y, z) is her root's (-z, y, x).
const CRADLE_SECONDS := .45
const CRADLE_HEAD := Vector3(-1.0, 0.6, 0.15) # His frame: her head, up toward his left shoulder.
const CRADLE_BELLY := Vector3(0.0, 0.5, 1.0) # His frame: her belly, toward him and up.
const CRADLE_GRIP := Vector3(0.0, 0.54, 0.05) # Middle of her barrel, skeleton rest space.
const CRADLE_SCALE := 0.88 # Her size in his arms: full size she looked too massive to carry.
## Leg sections aimed past the joint limits (the gait-measured range is far shallower than a tuck):
## [bone, the bone its section ends at ("" = the hoof tip), direction].
## Forelegs, in her body frame (-Z head, -Y belly, +x outward): upper leg forward so the elbow sits
## in front of her chest; forearm sharply back up toward her chin; the knee leads and the cannon
## folds back to her upper chest, hooves close together. CRADLE_FORELEG_DOWN then swings the whole
## fold down her chest toward her belly, clear of her face while she looks up at him.
const CRADLE_FORELEG := [["upperArm", "lowerArm", Vector3(0.1, -0.35, -1.0)], ["lowerArm", "wrist", Vector3(0.0, 0.7, -0.7)],
	["wrist", "", Vector3(-0.15, -0.2, 1.0)], ["finger", "", Vector3(-0.1, -0.6, 0.8)]]
const CRADLE_FORELEG_DOWN := 41.0 # Degrees.
## Hind legs, in his frame, together and parallel: thighs up over his right forearm, hocks bent
## over it, cannons pointing up past his right shoulder.
const CRADLE_HINDLEG_SCALE := 0.85 # Gaskin to hoof, so they don't tower over his head.
const CRADLE_HINDLEG := [["femur", "tibia", Vector3(0.3, 0.7, 0.5)], ["tibia", "legLower", Vector3(0.6, 0.1, 0.2)],
	["legLower", "", Vector3(0.2, 1.0, 0.1)], ["tarsal", "", Vector3(0.2, 1.0, 0.1)]]
var cradle := 0.0
var cradle_goal := false
## Drowsy or asleep in his arms (cradle_rest.gd), her face settles against his chest: her look
## eases from his eyes to this point, in his frame from his eyes.
const SNUGGLE_CHEST := Vector3(-0.06, -0.30, -0.10)
var cradle_rest: Node
## Bridal kiss (player/interactor.gd, K held): her lips reach up to his mouth with her neck and a
## little of her chest, her body staying in his arms, so the kiss physically happens whoever she
## is; the kiss itself (pony_kisser.gd) begins when their lips touch. World point; INF = not asked.
var kiss_reach_goal := Vector3.INF
var kiss_reach := 0.0
var _reach_last := Vector3.INF
## Her lips in her head bone's frame, measured once as the reach begins (re-measuring every tick
## made the reach chase its own lag: her face is drawn on the linked head skeleton).
var _lips_in_head := Vector3.INF
var _skull_in_head := Vector3.INF
var _nose_in_head := Vector3.INF
var _skull_radius := 0.0
## His eyes (midpoint, and half the span to each), and the way she backs off from them (his
## heading, away from him); set with kiss_reach_goal.
var kiss_reach_eye := Vector3.INF
var kiss_reach_side := Vector3.ZERO
var kiss_reach_away := Vector3.FORWARD
const KISS_EYE_CLEAR := .03 # Past her skull's radius, as affection_pose.gd's eye_clear.
const KISS_NOSE_CLEAR := .05 # Her nose tip from each eye, as affection_pose.gd does while held.
const KISS_REACH_CLEAR_TRIES := 3
## The kiss itself, once it lands (pony_affection.gd): the bridal reach carries what the kiss pose
## (affection_pose.gd) does standing. Her head rolls to the side she leans to (side_now) and
## sways; in a breather (pose.pause) she draws back along his heading to gaze at him.
const KISS_ROLL := 14.0 # Degrees, toward her lean side.
const KISS_SWAY_ROLL := 5.0 # Degrees.
const KISS_SWAY_SIDE := .008 # Metres.
const KISS_SWAY_UP := .006 # Metres.
const KISS_PAUSE_BACK := .06 # Metres.
var _kiss_life := 0.0
## How far (metres) her lips fall short of where the reach wants them (pony_kisser.gd ends a kiss
## she cannot hold).
var kiss_reach_miss := 0.0
const KISS_REACH_SECONDS := .9
## Kissed from sleep (cradle_rest.gd): she comes up to him slowly, half asleep, while he leans down to her.
var kiss_sleepy := false
const KISS_SLEEPY_SECONDS := 1.6
## [bone, most it may turn (degrees)], head first (her muzzle turns to his lips), then the neck;
## the chest curls only a little.
const KISS_REACH_BONES := [["pony_head", 50.0], ["pony_neck2", 40.0], ["pony_neck1", 40.0], ["pony_spine3", 12.5], ["pony_spine2", 12.5]]
const KISS_REACH_PASSES := 6
var _dangle_offset: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _dangle_velocity: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _dangle_origin := Vector3.INF
var _dangle_speed := Vector3.ZERO


func bind(owner_pony: CharacterBody3D) -> void:
	pony = owner_pony
	var bone: int = pony.skeleton.find_bone("pony_spine3")
	var rest: Transform3D = pony.skeleton.get_bone_global_rest(bone)
	pivot_center = (pony.skeleton.get_bone_global_rest(pony.skeleton.find_bone("pony_flank_L")).origin
		+ pony.skeleton.get_bone_global_rest(pony.skeleton.find_bone("pony_flank_R")).origin) * 0.5
	for name in ["chest", "left_chest", "right_chest"]:
		var x := -0.14 if name == "left_chest" else (0.14 if name == "right_chest" else 0.0)
		grips[name] = {"bone": bone, "offset": rest.affine_inverse() * Vector3(x, 0.56, -0.02)}
	grips["cradle"] = {"bone": bone, "offset": rest.affine_inverse() * CRADLE_GRIP}


## While cradled, "chest" (the grip the hands lock to) slides to the middle of her barrel.
func grip_transform(name: String = "chest") -> Transform3D:
	var grip: Dictionary = grips.get(name, grips.chest)
	var frame: Transform3D = pony.skeleton.global_transform * pony.skeleton.get_bone_global_pose(grip.bone)
	var point: Vector3 = frame * Vector3(grip.offset)
	if name == "chest" and cradle > 0.0:
		point = point.lerp(frame * Vector3(grips.cradle.offset), smoothstep(0.0, 1.0, cradle))
	return Transform3D(frame.basis.orthonormalized(), point)


## Her body's tilt while held: the lift/two-hand tilt, eased into the cradle roll.
func body_rotation() -> Quaternion:
	var lifted := Basis.from_euler(Vector3(pitch, grip_angles.x, grip_angles.y)).get_rotation_quaternion()
	if cradle <= 0.0: return lifted
	var forward := _from_his(CRADLE_HEAD).normalized()
	var belly := _from_his(CRADLE_BELLY)
	belly = (belly - forward * belly.dot(forward)).normalized()
	var cradled := Basis(belly.cross(forward), -belly, -forward).get_rotation_quaternion()
	return lifted.slerp(cradled, smoothstep(0.0, 1.0, cradle))


## Her size while cradled, 1 out of it.
func cradle_scale() -> float:
	return lerpf(1.0, CRADLE_SCALE, smoothstep(0.0, 1.0, cradle))


## A direction in his frame (x his right, y up, z toward him) in her root's frame while cradled.
static func _from_his(direction: Vector3) -> Vector3:
	return Vector3(-direction.z, direction.y, direction.x)


func begin(name: String, target: Vector3) -> void:
	active = true
	grip_name = name if grips.has(name) else "chest"
	initial_grip = grip_transform(grip_name).origin
	look_target = target
	start_pose = pony.corrected_pose.duplicate() if not pony.corrected_pose.is_empty() else pony.profile.rest.duplicate()
	start_pivot = pony.pivot.transform
	if cradle_rest == null: cradle_rest = CRADLE_REST.of(pony)
	if cradle_rest != null: cradle_rest.picked_up()
	blend = 0.0
	pitch = 0.0
	pitch_velocity = 0.0
	swing = Vector2.ZERO
	swing_velocity = Vector2.ZERO
	grip_angles = Vector2.ZERO
	grip_angular_velocity = Vector2.ZERO
	rejected_contacts = 0
	# No hoof stays planted on the ground (dev 2026-09-28): anchored hind hooves held until the
	# lift outreached them, then the whole body snapped up at once. All four legs leave the
	# ground together and ease into the carry pose over the blend.
	for i in 4:
		supports[i] = false
		release_blends[i] = 1.0
		release_poses[i] = []


func end() -> void:
	active = false
	cradle_goal = false
	supports.fill(false)
	kiss_reach_goal = Vector3.INF


func reset() -> void:
	end()
	blend = 0.0
	pitch = 0.0
	pitch_velocity = 0.0
	_dangle_offset = [Vector3.ZERO, Vector3.ZERO]; _dangle_velocity = [Vector3.ZERO, Vector3.ZERO]; _dangle_origin = Vector3.INF
	head_angles = Vector3.ZERO
	head_velocity = Vector3.ZERO
	eye_angles = Vector3.ZERO
	swing = Vector2.ZERO
	swing_velocity = Vector2.ZERO
	grip_angles = Vector2.ZERO
	grip_angular_velocity = Vector2.ZERO
	cradle = 0.0
	kiss_reach = 0.0
	_kiss_life = 0.0
	kiss_reach_miss = 0.0
	_lips_in_head = Vector3.INF
	_mane_follow()


## Separate manes (hybrid_hair_link.gd) follow her skull while cradled.
func _mane_follow() -> void:
	var link: Object = pony.get("hair_link") if pony != null else null
	if link != null: link.set("follow_head", smoothstep(0.0, 1.0, cradle))


func update(delta: float, world_acceleration: Vector3, grip_target: Vector3) -> void:
	blend = move_toward(blend, 1.0 if active else 0.0, delta / 0.35)
	cradle = move_toward(cradle, 1.0 if cradle_goal and active else 0.0, delta / CRADLE_SECONDS)
	var reaching := kiss_reach_goal.is_finite() and cradle_goal and active
	if reaching: _reach_last = kiss_reach_goal
	kiss_reach = move_toward(kiss_reach, 1.0 if reaching else 0.0, delta / (KISS_SLEEPY_SECONDS if kiss_sleepy else KISS_REACH_SECONDS))
	if kiss_reach <= 0.0:
		_lips_in_head = Vector3.INF
		_kiss_life = 0.0
		kiss_reach_miss = 0.0
	_mane_follow()
	var lift := maxf(0.0, grip_target.y - initial_grip.y)
	var want_pitch := asin(clampf(lift / 0.22, 0.0, sin(deg_to_rad(48.0)))) if active else 0.0
	var acceleration := pony.global_basis.orthonormalized().inverse() * world_acceleration.limit_length(12.0)
	var want_angles := Vector2.ZERO
	if active and pony._hand_targets.size() == 2:
		var span: Vector3 = pony.global_basis.orthonormalized().inverse() * (Vector3(pony._hand_targets.right_chest) - Vector3(pony._hand_targets.left_chest))
		want_angles.x = clampf(atan2(-span.z, span.x), deg_to_rad(-25.0), deg_to_rad(25.0))
		want_angles.y = clampf(atan2(span.y, Vector2(span.x, span.z).length()), deg_to_rad(-12.0), deg_to_rad(12.0))
	elif active:
		want_angles.y = deg_to_rad(-8.0 if grip_name == "left_chest" else (8.0 if grip_name == "right_chest" else 0.0))
	var steps := maxi(1, ceili(delta * 120.0))
	var dt := delta / steps
	for step in steps:
		grip_angular_velocity += ((want_angles - grip_angles) * 45.0 - grip_angular_velocity * 12.0) * dt
		grip_angles += grip_angular_velocity * dt
		pitch_velocity += ((want_pitch - pitch) * 45.0 - pitch_velocity * 12.0) * dt
		pitch = clampf(pitch + pitch_velocity * dt, 0.0, deg_to_rad(48.0))
		var force := Vector2(acceleration.z, -acceleration.x) * 0.12
		swing_velocity += (force - swing * 24.0 - swing_velocity * 7.5) * dt
		swing += swing_velocity * dt
		if swing.length() > deg_to_rad(12.0):
			swing = swing.limit_length(deg_to_rad(12.0))
			swing_velocity *= 0.5
	for i in 4:
		release_blends[i] = move_toward(release_blends[i], 1.0, delta / 0.2)


func apply_pose(pose: Array[Transform3D], delta: float) -> void:
	if blend <= 0.0:
		return
	var limits = pony.joint_limits
	var target: Array[Transform3D] = pony.profile.standing.duplicate()
	var body_angles: Vector3 = pony.pivot.transform.basis.get_euler()
	var cradled := smoothstep(0.0, 1.0, cradle)
	# Rolled onto her back, legs do not chase gravity through the shoulders and hips.
	body_angles *= 1.0 - cradled
	# Distributed proximal motion lets the limbs hang toward gravity without
	# asking one shoulder or hip joint to absorb the entire torso rotation.
	for side in ["L", "R"]:
		for part in ["shoulder", "flank", "upperArm", "femur"]:
			var name := "pony_%s_%s" % [part, side]
			var share := 0.42 if part in ["shoulder", "flank"] else 0.58
			if supports[2 if side == "L" else 3] and part in ["flank", "femur"]:
				share = 1.0 if part == "flank" else 0.0
			target[limits.names[name]].basis = limits.pose_basis(name, Vector3(-body_angles.x * share + swing.x * share, 0.0, -body_angles.z * share + swing.y * share))
		for part in REST_FLEX:
			if part in ["tibia", "legLower", "tarsal", "hoof"] and supports[2 if side == "L" else 3]:
				continue
			var name := "pony_%s_%s" % [part, side]
			target[limits.names[name]].basis = limits.pose_basis(name, Vector3(deg_to_rad(REST_FLEX[part]), 0.0, 0.0))
	for i in pose.size():
		pose[i] = (start_pose[i] if active and not start_pose.is_empty() else pose[i]).interpolate_with(target[i], blend)
	for leg_index in 4:
		if release_blends[leg_index] >= 1.0 or release_poses[leg_index].is_empty():
			continue
		var leg: Dictionary = pony.profile.legs[leg_index]
		for bone in leg.chain:
			pose[bone] = release_poses[leg_index][bone].interpolate_with(pose[bone], release_blends[leg_index])
	var frame: Transform3D = pony.global_transform * pony.pivot.transform * pony._model_frame
	var head: int = limits.names.pony_head
	var fk := SOLVER.forward_kinematics(pony.profile.parents, pose, frame)
	var look := look_target
	var snuggle: float = cradled * smoothstep(0.0, 1.0, cradle_rest.snuggle()) if cradle_rest != null else 0.0
	if snuggle > 0.0: look = look_target.lerp(look_target + pony.global_basis.orthonormalized() * _from_his(SNUGGLE_CHEST), snuggle)
	var direction := frame.basis.orthonormalized().inverse() * (look - fk[head].origin)
	var wanted := Vector3.ZERO
	# Cradled, the real roll is large: her neck takes back only part of it.
	body_angles.z = pony.pivot.transform.basis.get_euler().z * (1.0 - cradled * .6)
	if active and direction.length_squared() > 0.001:
		wanted = Vector3(clampf(atan2(direction.y, Vector2(direction.x, direction.z).length()), deg_to_rad(-65.0), deg_to_rad(65.0)),
			clampf(atan2(-direction.x, -direction.z), deg_to_rad(-70.0), deg_to_rad(70.0)), -body_angles.z * 0.6 + swing.y * 0.2)
	var steps := maxi(1, ceili(delta * 120.0))
	var dt := delta / steps
	for step in steps:
		var acceleration := ((wanted - head_angles) * 55.0 - head_velocity * 14.0).limit_length(deg_to_rad(360.0))
		head_velocity = (head_velocity + acceleration * dt).limit_length(deg_to_rad(80.0))
		head_angles += head_velocity * dt
	for name in ["pony_neck1", "pony_neck2", "pony_head"]:
		var share := 0.3 if name == "pony_head" else 0.35
		var current_basis:Basis=pose[limits.names[name]].basis
		pose[limits.names[name]].basis=current_basis.orthonormalized().slerp(limits.pose_basis(name,head_angles*share).orthonormalized(),blend).scaled_local(current_basis.get_scale())
	# Only the remaining aim belongs in the eyes; the ambient glance clock
	# previously made held eyes stare away from the player.
	fk = SOLVER.forward_kinematics(pony.profile.parents, pose, frame)
	var neutral: Basis = pony.skeleton.get_bone_global_rest(head).basis.orthonormalized()
	var facing: Basis = fk[head].basis.orthonormalized() * neutral.inverse()
	var residual: Vector3 = facing.inverse() * (look_target - fk[head].origin)
	eye_angles = Vector3(clampf(atan2(residual.y, Vector2(residual.x, residual.z).length()), -0.35, 0.35),
		clampf(atan2(-residual.x, -residual.z), -0.45, 0.45), 0.0) if active else Vector3.ZERO


func dangle_forelegs(pose: Array[Transform3D], frame: Transform3D, delta: float) -> void:
	if blend <= 0.0 or delta <= 0.0:
		_dangle_origin = Vector3.INF
		return
	# Cradled, the legs take the bridal pose instead; the hanging fades back in on the way out.
	if cradle > 0.0: _cradle_legs(pose, frame, blend * smoothstep(0.0, 1.0, cradle))
	if kiss_reach > 0.0: _reach_for_kiss(pose, frame, blend * smoothstep(0.0, 1.0, kiss_reach), delta)
	var weight := blend * (1.0 - smoothstep(0.0, 1.0, cradle))
	if weight <= 0.0:
		_dangle_origin = Vector3.INF
		return
	var speed := (frame.origin - _dangle_origin) / delta if _dangle_origin.is_finite() else Vector3.ZERO
	var acceleration := ((speed - _dangle_speed) / delta).limit_length(25.0) if _dangle_origin.is_finite() else Vector3.ZERO
	_dangle_origin = frame.origin; _dangle_speed = speed
	var facing: Vector3 = -pony.global_basis.z; facing.y = 0.0
	facing = facing.normalized() if facing.length_squared() > .0001 else Vector3.FORWARD
	# Joints bend about her side axis; a relaxed leg folds its hoof back toward her belly.
	var hinge := facing.cross(Vector3.DOWN).normalized()
	var parents: PackedInt32Array = pony.profile.parents
	var limits = pony.joint_limits
	var fk := SOLVER.forward_kinematics(parents, pose, frame)
	var front: Array[Dictionary] = []
	for leg: Dictionary in pony.profile.legs:
		if String(leg.name).begins_with("F"): front.append(leg)
	if front.size() != 2: return
	var middle: Vector3 = (fk[front[0].proximal].origin + fk[front[1].proximal].origin) * .5
	for k in 2:
		var leg: Dictionary = front[k]
		var steps := maxi(1, ceili(delta * 120.0))
		for step in steps:
			_dangle_velocity[k] += ((-acceleration * DANGLE_LAG - _dangle_offset[k]) * 70.0 - _dangle_velocity[k] * 7.0) * (delta / steps)
			_dangle_offset[k] = (_dangle_offset[k] + _dangle_velocity[k] * (delta / steps)).limit_length(.4)
		# Upper arm: toward a point below and a little in front of her chest, legs slightly apart.
		var top: Vector3 = fk[leg.proximal].origin
		var outward: Vector3 = top - middle; outward.y = 0.0
		outward = outward.normalized() * .12 if outward.length_squared() > .000001 else Vector3.ZERO
		var want: Vector3 = Vector3.DOWN + facing * DANGLE_FORWARD + outward + _dangle_offset[k]
		_turn_bone(pose, fk, leg.proximal, fk[leg.end].origin - top, want, weight)
		fk = SOLVER.forward_kinematics(parents, pose, frame)
		# Relaxed carpus and fetlock: a soft fold, a little more while she swings.
		var sway := clampf(_dangle_offset[k].length() * 2.0, 0.0, .35)
		for part: Array in [["wrist", 32.0], ["finger", 18.0]]:
			var name := "pony_%s_%s" % [part[0], "L" if String(leg.name).ends_with("L") else "R"]
			if not limits.names.has(name): continue
			var bone: int = limits.names[name]
			var distal: Vector3 = fk[leg.end].origin - fk[bone].origin
			if distal.length_squared() < .000001: continue
			var angle := deg_to_rad(float(part[1])) * (1.0 + sway) * weight
			var forward := Basis(hinge, angle) * distal
			var back := Basis(hinge, -angle) * distal
			var turn := Basis(hinge, angle if forward.dot(-facing) > back.dot(-facing) else -angle)
			var parent: Basis = fk[parents[bone]].basis
			pose[bone].basis = parent.inverse() * turn * parent * pose[bone].basis
			fk = SOLVER.forward_kinematics(parents, pose, frame)


## Cradled legs: each section of CRADLE_FORELEG / CRADLE_HINDLEG turned in order, hip or shoulder
## first, so every joint bends where the pose wants it.
func _cradle_legs(pose: Array[Transform3D], frame: Transform3D, weight: float) -> void:
	var parents: PackedInt32Array = pony.profile.parents
	var root: Basis = pony.global_basis.orthonormalized()
	var body: Basis = (pony.global_basis * pony.pivot.transform.basis).orthonormalized()
	var fore: Basis = body * Basis(Vector3.RIGHT, deg_to_rad(-CRADLE_FORELEG_DOWN))
	var fk := SOLVER.forward_kinematics(parents, pose, frame)
	for leg: Dictionary in pony.profile.legs:
		var front := String(leg.name).begins_with("F")
		var side := "L" if String(leg.name).ends_with("L") else "R"
		var outward := -1.0 if side == "L" else 1.0
		for part: Array in (CRADLE_FORELEG if front else CRADLE_HINDLEG):
			var bone: int = pony.skeleton.find_bone("pony_%s_%s" % [part[0], side])
			var tip: int = leg.end if String(part[1]).is_empty() else pony.skeleton.find_bone("pony_%s_%s" % [part[1], side])
			if bone < 0 or tip < 0: continue
			var want: Vector3 = part[2]
			want = fore * Vector3(want.x * outward, want.y, want.z) if front else root * _from_his(want)
			_turn_bone(pose, fk, bone, fk[tip].origin - fk[bone].origin, want, weight)
			fk = SOLVER.forward_kinematics(parents, pose, frame)
		var gaskin: int = pony.skeleton.find_bone("pony_tibia_%s" % side)
		if not front and gaskin >= 0:
			pose[gaskin].basis = pose[gaskin].basis.scaled_local(Vector3.ONE * lerpf(1.0, CRADLE_HINDLEG_SCALE, weight))


## Bridal kiss: CCD over KISS_REACH_BONES bringing her lips toward his mouth (eased by `weight`),
## each bone capped, after the joint limits like the cradled legs. Like the kiss pose
## (affection_pose.gd), her skull and nose then stay clear of both his eyes: the goal backs off
## along his heading and the reach is solved again.
func _reach_for_kiss(pose: Array[Transform3D], frame: Transform3D, weight: float, delta: float) -> void:
	var affection: Node = pony.get_node_or_null("Affection")
	var head: int = pony.skeleton.find_bone("pony_head")
	if affection == null or head < 0 or not _reach_last.is_finite(): return
	var parents: PackedInt32Array = pony.profile.parents
	var fk := SOLVER.forward_kinematics(parents, pose, frame)
	if not _lips_in_head.is_finite():
		# Against this pose, not the skeleton's: outside its update the skeleton holds the unmodified
		# pose, while her drawn face (mouth_point) is the posed one. The reach has barely begun, so
		# this pose is still the one last drawn.
		var lips_world: Vector3 = affection.mouth_point()
		if not lips_world.is_finite(): return
		var to_head := fk[head].affine_inverse()
		_lips_in_head = to_head * lips_world
		var boop: Object = pony.get("boop_node")
		_skull_in_head = to_head * boop.skull_world() if boop != null else Vector3.INF
		_nose_in_head = to_head * boop.nose_world() if boop != null else Vector3.INF
		_skull_radius = boop.SKULL_RADIUS * maxf(boop.head_skeleton.global_basis.get_scale().x, .01) if boop != null else 0.0
	var start: Array[Transform3D] = pose.duplicate()
	var goal: Vector3 = (fk[head] * _lips_in_head).lerp(_reach_last, weight)
	# The kiss's life: sway, and breathers drawing her back (more of it once the kiss turns deep).
	var kissing: bool = affection.get("kind") == "kiss"
	_kiss_life = move_toward(_kiss_life, 1.0 if kissing else 0.0, delta * 2.0)
	var kiss_pose: Object = affection.get("pose")
	var pause: float = float(kiss_pose.get("pause")) if kiss_pose != null and kiss_pose.get("pause") != null else 0.0
	var side: float = float(kiss_pose.get("_side_now")) if kiss_pose != null and kiss_pose.get("_side_now") != null else 1.0
	var sway: float = _kiss_life * weight * (1.0 if affection.get("deep") == true else .4)
	var t := Time.get_ticks_msec() / 1000.0
	var right := kiss_reach_away.cross(Vector3.UP).normalized()
	goal += kiss_reach_away * KISS_PAUSE_BACK * pause * _kiss_life * weight
	goal += (right * KISS_SWAY_SIDE * sin(t * 1.1) + Vector3.UP * KISS_SWAY_UP * sin(t * .8 + 1.0)) * sway
	for attempt in KISS_REACH_CLEAR_TRIES:
		if attempt > 0:
			for entry: Array in KISS_REACH_BONES:
				var bone: int = pony.skeleton.find_bone(entry[0])
				if bone >= 0: pose[bone] = start[bone]
			fk = SOLVER.forward_kinematics(parents, pose, frame)
		fk = _reach_solve(pose, frame, fk, head, goal)
		var short := _eye_short(fk[head])
		if short <= .0005: break
		goal += kiss_reach_away * short
	kiss_reach_miss = (fk[head] * _lips_in_head).distance_to(goal)
	# Her head rolls about the line to her lips, so the lips stay where they are.
	var roll := deg_to_rad(KISS_ROLL * side * _kiss_life * weight + KISS_SWAY_ROLL * sin(t * .7) * sway)
	if absf(roll) > .0001:
		var axis := (fk[head] * _lips_in_head - fk[head].origin).normalized()
		var parent: Basis = fk[parents[head]].basis
		pose[head].basis = parent.inverse() * Basis(axis, roll) * parent * pose[head].basis


func _reach_solve(pose: Array[Transform3D], frame: Transform3D, fk: Array[Transform3D], head: int, goal: Vector3) -> Array[Transform3D]:
	var parents: PackedInt32Array = pony.profile.parents
	var used := {}
	for step in KISS_REACH_PASSES:
		for entry: Array in KISS_REACH_BONES:
			var bone: int = pony.skeleton.find_bone(entry[0])
			if bone < 0: continue
			var from: Vector3 = fk[head] * _lips_in_head - fk[bone].origin
			var to: Vector3 = goal - fk[bone].origin
			var angle := from.angle_to(to)
			var left: float = deg_to_rad(entry[1]) - float(used.get(bone, 0.0))
			if angle < .001 or left <= 0.0: continue
			var turn := minf(angle, left)
			used[bone] = float(used.get(bone, 0.0)) + turn
			_turn_bone(pose, fk, bone, from, to, turn / angle)
			fk = SOLVER.forward_kinematics(parents, pose, frame)
	return fk


## Metres her skull or nose (her head bone's world transform) sits inside its clearance of his eyes.
func _eye_short(head_world: Transform3D) -> float:
	if not kiss_reach_eye.is_finite(): return 0.0
	var short := 0.0
	for side in [-1.0, 1.0]:
		var eye: Vector3 = kiss_reach_eye + kiss_reach_side * side
		if _skull_in_head.is_finite(): short = maxf(short, _skull_radius + KISS_EYE_CLEAR - (head_world * _skull_in_head).distance_to(eye))
		if _nose_in_head.is_finite(): short = maxf(short, KISS_NOSE_CLEAR - (head_world * _nose_in_head).distance_to(eye))
	return short


## Turn a bone in world space so `current` (a vector hanging from it) points along `want`.
func _turn_bone(pose: Array[Transform3D], fk: Array[Transform3D], bone: int, current: Vector3, want: Vector3, weight: float) -> void:
	if current.length_squared() < .000001 or want.length_squared() < .000001: return
	var turn := Quaternion.IDENTITY.slerp(Quaternion(current.normalized(), want.normalized()), weight)
	var parent: Basis = fk[pony.profile.parents[bone]].basis
	pose[bone].basis = parent.inverse() * Basis(turn) * parent * pose[bone].basis


func release_support(index: int, pose: Array[Transform3D]) -> void:
	if supports[index]:
		supports[index] = false
		rejected_contacts += 1
		release_poses[index] = pose.duplicate()
		release_blends[index] = 0.0
