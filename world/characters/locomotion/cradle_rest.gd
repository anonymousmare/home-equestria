extends Node
## Asleep in his arms (bridal carry, pony_carry.gd cradle). Past her bedtime, a pony who is
## comfortable with Anon grows drowsy while he holds her calmly: heavy eyelids, a yawn or two, her
## face settling against his chest (pony_carry.gd snuggle), then sleep. A pony picked up asleep
## stays asleep. A kiss only stirs her: still drowsy, she soon dozes off again (her eyes stay shut
## until her first breath). Each thing he says keeps a drowsy pony up a little longer. His running or
## a jump stirs her back to the first heavy eyelids; a throw or her hooves on the ground wake her. Laid on any bed asleep or drowsy
## (interactor.gd leans down with her), she lies straight down asleep: her own bed is night_rest.gd's
## as if it had tucked her in; his bed, a guest bed or one nopony owns she sleeps in until her
## morning, then hops down beside it. Another pony's bed wakes her: she gets up and goes to her own.
## One per pony, added on her first pickup (pony_carry.gd begin). night_rest.gd stays the owner of
## the night: its bedtime, its "asleep" phase and its wake-up.

const MATTRESS := preload("res://world/life/couch/mattress.gd")
const BED_SLOT := preload("res://world/buildings/bed_slot.gd")
const BED_SIZE := Vector3(2.05, 1.1, 2.1) # house_beds.gd BED_SIZE, for beds without their own.
## Calm seconds in his arms before her eyelids grow heavy, and until she is asleep.
const DROWSY_AFTER := 20.0
const ASLEEP_AFTER := 75.0
const FILLY_ASLEEP_AFTER := 45.0
## Faster than his walk by this much he is running; rising this fast (m/s) he jumped. Either sets
## her back to DROWSY_AFTER: heavy-eyed, not wide awake.
const ROUGH_SPEED := 1.15
const JUMP_SPEED := 1.0
## Woken properly in his arms, she stays awake at least this long.
const WOKEN_REST := 120.0
## Only stirred (a voice, a kiss, her own wake_up()): this share of the way to sleep stays, and a
## short while later she can drift off again.
const STIRRED_CALM := .75
const STIRRED_REST := 15.0
## Calm seconds each thing he says to her takes back while she dozes (conversation_director.gd
## transcript): like a voice keeping somepony from nodding off.
const SPOKEN_SETBACK := 8.0
## Laid in another pony's bed, she stirs, sees whose it is and gets up after this long.
const NOT_MINE_SECONDS := 4.0
## Her first breath in a kiss from sleep: the kiss pose's pause past this opens her eyes.
const KISS_BREATH := .3
## Drowsy enough to tuck in: she falls asleep in the bed.
const TUCK_DROWSE := .5
const YAWN_SECONDS := 2.2
const YAWN_AT := [.15, .55]
## Slow, heavy blinks while drowsy.
const BLINK_EVERY := 6.0
const BLINK_SECONDS := .9
## Cradled this long after his first "carried" event, she hears about the bridal carry too.
const CRADLE_TELL_AFTER := 3.0

## The situation, in the same voice as director_contacts.gd and pony_awareness.gd.
const CARRIED_EVENT := "Anon is holding you cradled in his arms like a bride: your back across one arm, your legs over the other, your belly toward him. You may simply enjoy being held in silence. If words add something, one or two can be enough. Do not invent where he intends to take you."
const CARRIED_AWAY_EVENT := "Anon is carrying you cradled in his arms like a bride, moving away from where he picked you up. You may enjoy the ride silently; speak only if something needs saying. You do not yet know his destination or intent."
const BODY_WORDS := "cradled in the player's arms right now, carried like a bride: your back across one arm, your legs over the other"
const DROWSY_LINE := "- It is past your bedtime and you are growing sleepy in Anon's arms: your eyelids are heavy and your head keeps settling against his chest. You may let yourself drift off; nothing needs saying."
const ASLEEP_LINE := "- It is night and you are fast asleep in Anon's arms, held against him with your eyes shut. A voice has half-woken you: you are drowsy, yawning, and would rather go back to sleep. If you decide to wake up properly, use wake_up(); otherwise you doze on in his arms."

var pony: Node3D
var calm := 0.0
var drowse := 0.0
## Asleep in his arms; the night's own sleep is night_rest.gd's.
var asleep := false
var _woken_until := 0.0
var _yawns := 0
var _yawn := -1.0
var _blink := 0.0
var _was_held := false
var _set_down_in := 0
var _cradled_for := 0.0
var _told := false
var _sent_seen := false
## A bed that is not hers she was tucked into, until she gets up from it.
var _bed: Node3D
var _bed_check := 0.0
## The words for the bed she was laid in (her memory of waking there), and how long until she gets
## up out of another pony's bed (negative: she sleeps on).
var _bed_words_now := ""
var _get_up_in := -1.0
## Kissed from sleep: eyes shut until her first breath (pony_carry.gd kiss_sleepy).
var _kiss_from_sleep := false
var _player: CharacterBody3D


static func of(owner_pony: Node3D) -> Node:
	if owner_pony == null or not "sleeping" in owner_pony or owner_pony.get("identity") == null: return null
	var existing := owner_pony.get_node_or_null("CradleRest")
	if existing != null: return existing
	var rest: Node = load("res://world/characters/locomotion/cradle_rest.gd").new()
	rest.name = "CradleRest"
	rest.set("pony", owner_pony)
	owner_pony.add_child(rest)
	return rest


## Bridal carried right now (interactor.gd sets cradle_goal).
static func cradled(actor: Object) -> bool:
	var carry: Variant = actor.get("carry") if actor != null else null
	return carry is RefCounted and carry.get("cradle_goal") == true and carry.get("active") == true


## For pony_awareness.gd: "", "cradled", "drowsy" or "asleep" (held asleep, cradled or not).
static func situation(actor: Object) -> String:
	if actor == null or actor.get("_held") != true: return ""
	if actor.get("sleeping") == true: return "asleep"
	if not cradled(actor): return ""
	var rest: Node = (actor as Node).get_node_or_null("CradleRest")
	return "drowsy" if rest != null and float(rest.get("drowse")) > .2 else "cradled"


## How far her face has settled against his chest, 0..1 (pony_carry.gd apply_pose).
func snuggle() -> float:
	return 1.0 if asleep else smoothstep(0.0, .6, drowse)


## pony_carry.gd begin, inside begin_grab: picking her up woke her there, so a pony asleep in her
## night's bed is put back to sleep before anything sees her awake. night_rest.gd would let her go
## at its next check (a held sleeper is "busy"); that is done here, the same way.
func picked_up() -> void:
	set_physics_process(true)
	if asleep and _was_held:
		pony.sleeping = true # Grabbed again without being let go (a second hand): still asleep.
		return
	_listen()
	_told = false; _sent_seen = false; _cradled_for = 0.0; _kiss_from_sleep = false
	_bed = null
	var rest := _night_rest()
	var id := _id()
	if rest == null or not rest.is_asleep(id): return
	var entry: Dictionary = rest._state.get(id, {})
	rest._release(entry, pony, false)
	entry.phase = ""
	asleep = true; calm = _asleep_after(); drowse = 1.0
	pony.sleeping = true
	# No "held for five seconds" reply from a sleeping pony (carry_reaction.gd).
	_told = true
	var reaction: Object = pony.get("_carry_reaction")
	if reaction != null: reaction.set("sent", true)


func _ready() -> void:
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(pony): return
	var held: bool = pony.get("_held") == true
	if held: _held_step(delta)
	elif _was_held: _set_down_in = 2 # Let a throw start before deciding where she landed.
	_was_held = held
	if _set_down_in > 0 and not held:
		_set_down_in -= 1
		if _set_down_in == 0: _set_down()
	if _bed != null: _bed_step(delta)
	_face(delta)
	if not held and _set_down_in == 0 and _bed == null and drowse <= 0.0 and _yawn < 0.0 and not asleep and not _kiss_from_sleep:
		set_physics_process(false)


func _held_step(delta: float) -> void:
	var carry: RefCounted = pony.carry
	var is_cradled := cradled(pony)
	var now := Time.get_ticks_msec() * .001
	if _rough() and calm > DROWSY_AFTER:
		if asleep:
			pony.sleeping = false
			asleep = false
			print("[cradle rest] %s jostled half awake" % _id())
		calm = DROWSY_AFTER
	# Reaching for a kiss (interactor.gd kiss_reach_goal): she stirs to it, eyes still shut.
	if asleep and carry.kiss_reach_goal.is_finite():
		pony.sleeping = false
		_kiss_from_sleep = true
		carry.kiss_sleepy = true
		_woken("You were asleep in Anon's arms and stirred to him kissing you.", true)
	if asleep and pony.sleeping != true: _woken("", true) # A voice, her own wake_up(): she stirs.
	if _kiss_from_sleep:
		var affection: Node = pony.get_node_or_null("Affection")
		var kiss_pose: Object = affection.get("pose") if affection != null else null
		var pause: float = float(kiss_pose.get("pause")) if kiss_pose != null and kiss_pose.get("pause") != null else 0.0
		if pause > KISS_BREATH or (carry.kiss_reach <= 0.0 and not carry.kiss_reach_goal.is_finite()):
			_kiss_from_sleep = false
			carry.kiss_sleepy = false
	if not asleep:
		# Talking keeps her drifting; a kiss holds her where she is.
		var settling: bool = is_cradled and now >= _woken_until and _bedtime() and _comfortable()
		if settling and not _affection_busy(): calm += delta
		elif not settling: calm = maxf(0.0, calm - delta * (2.0 if is_cradled else 6.0))
		var was_drowsy := drowse > 0.0
		drowse = smoothstep(DROWSY_AFTER, _asleep_after(), calm)
		if drowse > 0.0 and not was_drowsy: print("[cradle rest] %s is getting drowsy" % _id())
		if calm >= _asleep_after() and not pony.is_speaking() and not _affection_busy(): _fall_asleep()
	_cradle_told(delta, is_cradled)


## His sprint or a jump (desktop_player.gd), while carrying her.
func _rough() -> bool:
	if not is_instance_valid(_player):
		var node: Node = preload("res://world/player_view.gd").camera(pony)
		while node != null and not node is CharacterBody3D: node = node.get_parent()
		_player = node as CharacterBody3D
	if _player == null: return false
	var walk: float = float(_player.get("walk_speed")) if _player.get("walk_speed") != null else 4.0
	return Vector2(_player.velocity.x, _player.velocity.z).length() > walk * ROUGH_SPEED or _player.velocity.y > JUMP_SPEED


func _listen() -> void:
	var director: Node = get_tree().get_first_node_in_group("conversation_director") if is_inside_tree() else null
	if director != null and director.has_signal("transcript") and not director.transcript.is_connected(_heard):
		director.transcript.connect(_heard)


## He said something while she dozes in his arms: it keeps her up a little longer. Asleep, she sleeps
## on (her own wake_up() is how a voice wakes her, pony_awareness.gd).
func _heard(_text: String) -> void:
	if not is_instance_valid(pony) or pony.get("_held") != true or asleep or not cradled(pony): return
	calm = maxf(0.0, calm - SPOKEN_SETBACK)


func _fall_asleep() -> void:
	asleep = true; drowse = 1.0
	pony.sleeping = true
	print("[cradle rest] %s fell asleep in his arms" % _id())
	_remember("physical_contact", "Past your bedtime, you fell asleep in Anon's arms while he carried you.")


## Out of her sleep in his arms: stirred (still drowsy, soon asleep again) or properly awake.
func _woken(memory: String, stirred: bool) -> void:
	print("[cradle rest] %s %s" % [_id(), "stirs" if stirred else "wakes up"])
	asleep = false
	calm = _asleep_after() * STIRRED_CALM if stirred else 0.0
	drowse = smoothstep(DROWSY_AFTER, _asleep_after(), calm)
	_woken_until = Time.get_ticks_msec() * .001 + (STIRRED_REST if stirred else WOKEN_REST)
	if not memory.is_empty(): _remember("physical_contact", memory)


## His first "carried" event (carry_reaction.gd) already uses the bridal words if she was
## cradled by then (director_contacts.gd); cradled only later, she hears about it once more.
func _cradle_told(delta: float, is_cradled: bool) -> void:
	_cradled_for = _cradled_for + delta if is_cradled else 0.0
	var reaction: Object = pony.get("_carry_reaction")
	if _told or reaction == null or pony.sleeping == true: return
	var sent: bool = reaction.get("sent") == true
	if sent and not _sent_seen:
		_sent_seen = true
		if is_cradled: _told = true; return
	if sent and _cradled_for >= CRADLE_TELL_AFTER:
		_told = true
		pony.emit_signal("physical_reaction", "carried")


## Out of his arms without being laid in bed (interactor.gd): a throw or her hooves on the
## ground wake her; over a bed she lies down asleep there all the same.
func _set_down() -> void:
	_kiss_from_sleep = false
	pony.carry.kiss_sleepy = false
	if not asleep and drowse < TUCK_DROWSE:
		calm = 0.0; drowse = 0.0
		return
	var was_asleep := asleep
	var thrown: Object = pony.get("thrown")
	var spot: Dictionary = {} if thrown != null and thrown.active() else bed_spot(Vector3.INF, Vector3.ZERO)
	if spot.is_empty():
		pony.sleeping = false
		_woken("You were asleep in Anon's arms; when he set you down, you woke up groggy." if was_asleep else "", false)
		calm = 0.0; drowse = 0.0
		return
	lay_down(spot)


## Where she would sleep if laid down now: asleep or drowsy at her bedtime, over a bed (under her
## body, else where his eyes meet one within reach). {} when not; else {bed, own (her own bed),
## spot (her rest on it: night_rest.gd's in her own bed)}.
func bed_spot(eye: Vector3, look: Vector3) -> Dictionary:
	if (not asleep and drowse < TUCK_DROWSE) or not _bedtime(): return {}
	var from: Vector3 = pony.carry.grip_transform("chest").origin
	var hit := _bed_hit(from + Vector3.UP * .2, from + Vector3.DOWN * 2.0)
	if hit.is_empty() and eye.is_finite(): hit = _bed_hit(eye, eye + look.normalized() * 2.5)
	if hit.is_empty(): return {}
	var bed: Node3D = hit.bed
	var id := _id()
	var rest := _night_rest()
	var house: Node3D = rest.population.home_house(id) if rest != null and rest.population != null and rest.population.has_method("home_house") else null
	var own: bool = house != null and house.has_method("ensure_bed") and house.ensure_bed(id) == bed
	var spot: Transform3D = house.bed_rest(id) if own else _spot_on(bed, hit.point)
	return {"bed": bed, "own": own, "spot": spot, "owner": "" if own else _bed_owner(bed)}


## Another pony whose bed this is (a resident of the house it stands in), else "": his own bed,
## a guest bed and an unowned bed belong to nopony.
func _bed_owner(bed: Node3D) -> String:
	var game := _game()
	var population: Node = game.get("population") if game != null else null
	var house: Node3D = load("res://world/buildings/house_interior.gd").at(pony.get_tree(), bed.global_position)
	if house == null or population == null or not population.has_method("residents_of") or not house.has_method("ensure_bed"): return ""
	for resident: String in population.residents_of(house.place_id()):
		if resident != _id() and house.ensure_bed(resident) == bed: return resident
	return ""


## The first bed along a ray, past Anon and other ponies: {bed, point}, or {}.
func _bed_hit(from: Vector3, to: Vector3) -> Dictionary:
	var space := pony.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	var exclude: Array[RID] = [pony.get_rid()]
	for attempt in 4:
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty(): return {}
		var bed: Node3D = MATTRESS.bed_of(hit.collider)
		if bed != null and bed.has_meta("mattress_top"): return {"bed": bed, "point": hit.position}
		if not (hit.collider is CharacterBody3D): return {}
		exclude.append(hit.rid)
	return {}


## Where she lies on a bed that is not hers: along it like a bed_rest (house_beds.gd), on the
## side of the mattress he laid her over.
func _spot_on(bed: Node3D, over: Vector3) -> Transform3D:
	var size: Vector3 = bed.get_meta("bed_size", BED_SIZE)
	var top := float(bed.get_meta("mattress_top", .6))
	var across: float = bed.to_local(over).x
	var room := maxf(0.0, size.x * .5 - .32)
	return BED_SLOT.rest(bed, Vector3(clampf(across, -room, room), top, .15))


## Laid on the mattress (out of his arms already): she lands lying and asleep, the way
## posture.impact_flop lands a pony prone, and her sleep pose eases in. night_rest.gd's "asleep"
## phase keeps her there until her wake-up time.
func lay_down(spot: Dictionary) -> void:
	_kiss_from_sleep = false
	pony.carry.kiss_sleepy = false
	var rest := _night_rest()
	var id := _id()
	var entry: Dictionary = rest._state.get(id, {}) if rest != null else {}
	var how := "asleep" if asleep else "half asleep"
	asleep = false; calm = 0.0; drowse = 0.0
	if entry.is_empty():
		pony.sleeping = false
		return
	var bed: Node3D = spot.bed
	var own: bool = spot.own
	var owner_id := str(spot.get("owner", ""))
	_bed_words_now = _bed_words(bed, own, owner_id)
	print("[cradle rest] %s laid in %s" % [id, "her own bed" if own else str(bed.name) + (" (%s's)" % owner_id if owner_id != "" else "")])
	if owner_id.is_empty():
		_remember("home", "Anon carried you, %s in his arms, and tucked you into %s." % [how, _bed_words_now])
	else:
		_remember("home", "Anon carried you, %s in his arms, and laid you in %s. You stirred, saw it was not your bed, and got up to go to your own." % [how, _bed_words_now])
	if "sleep_style" in pony:
		pony.sleep_style = "side" if randf() < .5 else "head_down"
		# Limbs within each mattress lane when sharing with family (night_rest.gd _settle).
		if own and entry.get("shared_bed", false): pony.sleep_style = "head_down"
	pony.reset_motion(spot.spot)
	var nav := pony.get_node_or_null("Navigator")
	if nav != null:
		nav.stay(); nav.command_owner = "sleep:" + id
	pony.sleeping = true
	pony.request_posture("lie_down")
	if pony.get("posture") != null: pony.posture.impact_flop()
	entry.phase = "asleep"
	_bed = null if own else bed
	_bed_check = 0.0
	_get_up_in = NOT_MINE_SECONDS if not owner_id.is_empty() else -1.0
	set_physics_process(true)


## Up again on a bed that is not hers (her morning, her own wake_up(), or another pony's bed):
## night_rest.gd only knows the way down from her own bed, so she hops down beside this one.
func _bed_step(delta: float) -> void:
	_bed_check -= delta
	if _bed_check > 0.0: return
	_bed_check = 1.0
	if not is_instance_valid(_bed) or pony.get("_held") == true: _bed = null; _get_up_in = -1.0; return
	var entry := _night_entry()
	if _get_up_in >= 0.0:
		_get_up_in -= 1.0
		if _get_up_in >= 0.0: return
		# Not hers: awake, and once down from it night_rest.gd walks her to her own bed.
		print("[cradle rest] %s gets up from somepony else's bed" % _id())
		pony.sleeping = false
		pony.request_posture("stand")
		var nav := pony.get_node_or_null("Navigator")
		if nav != null and str(nav.command_owner).begins_with("sleep:"): nav.command_owner = ""
		entry.phase = "climbing"
		var theirs := _bed
		_bed = null
		_hop_down(theirs, func(): entry.phase = "")
		return
	if pony.sleeping == true or str(entry.get("phase", "")) in ["asleep", "settling"]: return
	var bed := _bed
	_bed = null
	if not BED_SLOT.on_mattress(bed, pony.global_position, BED_SIZE): return
	print("[cradle rest] %s wakes up in %s" % [_id(), bed.name])
	_remember("home", "You woke up in %s, where Anon had tucked you in, and got out of it." % _bed_words_now)
	_hop_down(bed, Callable())


## Stand up on the mattress, then hop down beside the bed (night_rest.gd _wake's hop).
func _hop_down(bed: Node3D, done: Callable) -> void:
	var side := _bed_side(bed)
	var from := [Vector3.ZERO]
	var tween := create_tween().bind_node(pony)
	tween.tween_interval(1.6)
	tween.tween_callback(func(): pony.motion_paused = true; from[0] = pony.global_position)
	tween.tween_method(func(t: float):
		pony.global_position = (from[0] as Vector3).lerp(side, t) + Vector3.UP * sin(PI * t) * .35 * pony.body_scale, 0.0, 1.0, .6)
	tween.tween_callback(func():
		pony.motion_paused = false
		pony.reset_motion(Transform3D(pony.global_basis, side + Vector3.UP * .02))
		if done.is_valid(): done.call())


## A clear floor spot beside the bed (house_beds.gd _pick_bed_side's candidates).
func _bed_side(bed: Node3D) -> Vector3:
	var size: Vector3 = bed.get_meta("bed_size", BED_SIZE)
	var candidates: Array[Vector3] = []
	if bed.has_meta("side_local"): candidates.append(bed.get_meta("side_local"))
	for local: Vector3 in [Vector3(size.x * .5 + .55, 0, .25), Vector3(-size.x * .5 - .55, 0, .25), Vector3(0, 0, size.z * .5 + .6)]:
		candidates.append(local)
	var shape := SphereShape3D.new(); shape.radius = .3
	var query := PhysicsShapeQueryParameters3D.new(); query.shape = shape; query.collision_mask = 1
	var exclude: Array[RID] = [pony.get_rid()]
	query.exclude = exclude
	var space := pony.get_world_3d().direct_space_state
	for local: Vector3 in candidates:
		var at := bed.to_global(local)
		query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * .45)
		if space.intersect_shape(query, 1).is_empty(): return at
	return bed.to_global(candidates[0])


func _bed_words(bed: Node3D, own: bool, owner_id: String) -> String:
	var game: Node = _game()
	var sleep: Object = game.get("sleep") if game != null else null
	var his: Node3D = sleep._home_bed() if sleep != null and sleep.has_method("_home_bed") else null
	if own: return "the bed you share with him" if his == bed else "your own bed"
	if not owner_id.is_empty(): return "%s's bed" % owner_id.capitalize()
	var guest := str(bed.name).to_lower().contains("guest")
	var house: Node3D = load("res://world/buildings/house_interior.gd").at(pony.get_tree(), bed.global_position)
	var population: Node = game.get("population") if game != null else null
	var residents: Array = population.residents_of(house.place_id()) if house != null and population != null and population.has_method("residents_of") else []
	# A guest bed in her own home was also his fallback bed (player_sleep.gd _home_bed): hers first.
	if _id() in residents: return "the guest bed in your own home" if guest else "a spare bed in your own home"
	if his == bed: return "his own bed"
	if not residents.is_empty(): return "the guest bed in somepony else's home" if guest else "a spare bed in somepony else's home"
	return "a bed"


## Heavy lids, slow blinks and a yawn or two while she grows drowsy (the face's own touch
## channel, as pony_affection.gd's yawn fidget; that one waits for her to stand on the ground).
func _face(delta: float) -> void:
	var expressions: Object = pony.get("expressions")
	if expressions == null: return
	if _kiss_from_sleep:
		expressions.touch("drowse", 0.0, 1.0)
		return
	if drowse <= 0.0 and _yawn < 0.0:
		expressions.release_touch("drowse")
		_yawns = 0
		return
	var lids := drowse * .7
	if asleep: lids = .6 # Shut by her sleep; half-woken by a voice she stays heavy-lidded.
	elif drowse > .25:
		_blink += delta
		var blink := fmod(_blink, BLINK_EVERY)
		if blink < BLINK_SECONDS: lids = maxf(lids, sin(PI * blink / BLINK_SECONDS))
	if not asleep and _yawn < 0.0 and _yawns < YAWN_AT.size() and drowse >= float(YAWN_AT[_yawns]) and not pony.is_speaking():
		_yawn = 0.0; _yawns += 1
	var mouth: Object = pony.head.mouth if pony.get("head") != null else null
	if _yawn >= 0.0:
		_yawn += delta
		var a := minf(smoothstep(0.0, YAWN_SECONDS * .3, _yawn), 1.0 - smoothstep(YAWN_SECONDS * .7, YAWN_SECONDS, _yawn))
		lids = maxf(lids, a)
		var done: bool = _yawn >= YAWN_SECONDS or pony.is_speaking()
		if done: a = 0.0; _yawn = -1.0
		if mouth != null:
			mouth.set_expression("open", a); mouth.set_expression("open_soft", .7 * a)
	expressions.touch("drowse", 0.0, lids)


func _affection_busy() -> bool:
	var affection: Node = pony.get_node_or_null("Affection")
	return affection != null and (str(affection.get("kind")) != "" or float(affection.get("afterglow_left")) > 0.0)


## Her bedtime tonight has come (night_rest.gd).
func _bedtime() -> bool:
	var rest := _night_rest()
	if rest == null or rest.get("clock") == null: return false
	var times: Vector2 = rest.bedtime(_id(), rest._night_key())
	return rest._is_night({"bed_time": times.x, "wake_time": times.y})


## Easy in his arms: the hug rule (player_bonds.gd welcomes). Fillies, whom that rule leaves to
## the grown-ups, need to be friends or trust him.
func _comfortable() -> bool:
	var runtime := _runtime()
	if runtime == null or runtime.get("bonds") == null: return false
	var id := str(pony.get_meta("relationship_id", _id()))
	if runtime.bonds.welcomes(id, "hug"): return true
	if not pony.identity.filly: return false
	var record: Dictionary = runtime.bonds.record_for(id)
	return str(record.get("stage", "acquaintance")) != "acquaintance" or float(record.get("trust", 0.0)) >= 10.0


func _asleep_after() -> float:
	return FILLY_ASLEEP_AFTER if pony.identity.filly else ASLEEP_AFTER


func _remember(kind: String, text: String) -> void:
	var game := _game()
	var context: Object = game.get("world_context") if game != null else null
	if context != null: context.record(kind, text, [_id()], [_id()])


func _id() -> String:
	return str(pony.identity.id)


func _night_rest() -> Node:
	return get_tree().get_first_node_in_group("night_rest") if is_inside_tree() else null


func _night_entry() -> Dictionary:
	var rest := _night_rest()
	return rest._state.get(_id(), {}) if rest != null else {}


func _runtime() -> Node:
	return pony.get_meta("relationship_runtime") if pony.has_meta("relationship_runtime") else null


func _game() -> Node:
	var runtime := _runtime()
	return runtime.get("game") if runtime != null else null
