extends SceneTree
## Mod support (world/modding/, 2026-10-26): packs from the mods folder and loose packs mount in
## name order, Off switches skip a pack, a broken mod.json is listed but never runs, JSON merges,
## script extensions, entry scripts, world save sections, and the Dinnerbone example builds into a
## pack the loader recognises and turns a pony over. Packs are made in user:// by the test itself.
##   XDG_DATA_HOME=<scratch>/mod-loader-test python3 tools/run_owned_godot.py --project home-equestria-public \
##       --expect MOD_LOADER_DONE --log LOG res://tools/modding/test_mod_loader.gd
const LOADER := preload("res://world/modding/mod_loader.gd")
const BUILD := preload("res://tools/modding/build_mod.gd")
const MODS := preload("res://world/modding/mods.gd")
const EXTENDED := "res://world/characters/hybrid_mare/dock_tail_mount.gd"
var failures := 0
var checks := 0
var temp := ""

func _initialize() -> void: run.call_deferred()
func check(ok: bool, text: String) -> void:
	checks += 1
	print("[mods] ", "PASS " if ok else "FAIL ", text)
	if not ok: failures += 1

## A pack of {res:// path: text} written with PCKPacker.
func pack(path: String, files: Dictionary) -> void:
	var packer := PCKPacker.new()
	packer.pck_start(path)
	var n := 0
	for target: String in files:
		var source := temp.path_join("src_%s_%d" % [path.get_file(), n]); n += 1
		var file := FileAccess.open(source, FileAccess.WRITE); file.store_string(str(files[target])); file.close()
		packer.add_file(target, source)
	packer.flush()

func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").contains("mod-loader-test"):
		printerr("MOD_LOADER_REFUSED requires an isolated XDG_DATA_HOME"); quit(1); return
	temp = ProjectSettings.globalize_path("user://mod_test")
	var mods_dir := temp.path_join("mods"); var loose_dir := temp.path_join("exe")
	DirAccess.make_dir_recursive_absolute(mods_dir); DirAccess.make_dir_recursive_absolute(loose_dir)
	var built := BUILD.build("dinnerbone", mods_dir.path_join("dinnerbone.pck"))
	check(FileAccess.file_exists(built), "Dinnerbone builds (%s)" % built)
	pack(mods_dir.path_join("b_merge.pck"), {
		"res://mods/merge_test/mod.json": JSON.stringify({"id": "merge_test", "name": "Merge test", "version": "2.0", "author": "Tester", "entry": "res://mods/merge_test/main.gd", "extends": ["res://mods/merge_test/ext.gd"]}),
		"res://mods/merge_test/main.gd": "extends Node\nvar started := true\n",
		"res://mods/merge_test/ext.gd": "extends \"%s\"\nconst MODDED := true\n" % EXTENDED,
		"res://mods/merge_test/merge/world/food/definitions.json": JSON.stringify({"mod_cake": {"name": "Mod Cake", "price_bits": 3}, "hayburger": {"price_bits": 99}})})
	pack(mods_dir.path_join("c_broken.pck"), {"res://mods/broken_test/mod.json": "{not json"})
	pack(mods_dir.path_join("d_off.pck"), {"res://mods/off_test/mod.json": JSON.stringify({"id": "off_test", "name": "Off"})})
	pack(loose_dir.path_join("loose_override.pck"), {"res://mods/loose_marker.txt": "loose"})
	pack(loose_dir.path_join("HomeEquestria-data.pck"), {"res://mods/game_pack_marker.txt": "game"})
	LOADER.boot([mods_dir], [loose_dir], PackedStringArray(["d_off.pck"]))
	var files: Array = LOADER.packs.map(func(row: Dictionary) -> String: return row.file)
	check(files == ["b_merge.pck", "c_broken.pck", "d_off.pck", "dinnerbone.pck", "loose_override.pck"], "packs in name order, the game's own pack skipped (%s)" % str(files))
	var ids: Array = LOADER.mods.map(func(mod: Dictionary) -> String: return mod.id)
	check("dinnerbone" in ids, "the built Dinnerbone pack is recognised although res://mods/dinnerbone exists in the source")
	var active: Array = LOADER.active().map(func(mod: Dictionary) -> String: return mod.id)
	check(active.has("merge_test") and active.has("dinnerbone") and not active.has("broken_test"), "valid mods run, the broken one does not (%s)" % str(active))
	var broken: Array = LOADER.mods.filter(func(mod: Dictionary) -> bool: return mod.id == "broken_test")
	check(broken.size() == 1 and not broken[0].errors.is_empty(), "the broken mod is listed with a reason")
	check(not FileAccess.file_exists("res://mods/off_test/mod.json") and "off_test" not in ids, "a switched-off pack is not mounted")
	check(FileAccess.get_file_as_string("res://mods/loose_marker.txt") == "loose", "a loose pack beside the executable still mounts")
	var food: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/food/definitions.json"))
	check(food.get("mod_cake", {}).get("name") == "Mod Cake" and int(food.hayburger.price_bits) == 99 and str(food.hayburger.name) == "Hayburger", "JSON merge adds and overrides keys, keeps the rest")
	check(food.size() > 2, "merged data keeps the game's entries (%d)" % food.size())
	var script := load(EXTENDED) as Script
	check(script != null and script.get_script_constant_map().get("MODDED") == true and script.get_base_script() != null, "the game script path now loads the mod's extension")
	check(LOADER.deep_merge([1], [2]) == [1, 2] and LOADER.deep_merge({"a": {"b": 1}}, {"a": {"c": 2}}) == {"a": {"b": 1, "c": 2}}, "lists append, objects merge")
	LOADER.set_enabled("dinnerbone.pck", false)
	check("dinnerbone.pck" in LOADER.disabled_files(), "a switch is saved")
	LOADER.set_enabled("dinnerbone.pck", true)
	check("dinnerbone.pck" not in LOADER.disabled_files(), "and switched back on")
	# The autoload part: entry scripts run, matchers, save sections.
	var mods: Node = MODS.new(); mods.name = "ModsUnderTest"; root.add_child(mods)
	await process_frame
	check(mods.get_node_or_null("merge_test") != null and bool(mods.get_node("merge_test").get("started")), "entry script added and started")
	var grouped := Node.new(); grouped.add_to_group("ponies_test"); root.add_child(grouped)
	var seen: Array = []
	mods.on_node("group:ponies_test", func(n: Node) -> void: seen.append(n))
	var later := Node.new(); later.add_to_group("ponies_test"); root.add_child(later)
	await process_frame
	check(seen.size() == 2 and seen.has(grouped) and seen.has(later), "on_node finds existing and later nodes (%d)" % seen.size())
	check(MODS.matches(later, "class:Node") and not MODS.matches(later, "class:Node3D"), "class matcher")
	var context: Node = preload("res://world/ai/world_context.gd").new()
	var game_script := GDScript.new(); game_script.source_code = "extends Node\nvar world_context: Node\n"; game_script.reload()
	var game := Node.new(); game.set_script(game_script)
	game.set("world_context", context); mods.game = game
	mods.state("merge_test").score = 3
	check(int(context.state.mods.merge_test.score) == 3, "state() writes the mod's world save section")
	var saved := {"version": context.VERSION, "world_id": "w", "events": [], "relationships": {}, "lore": {}, "removed_lore": [], "mods": {"merge_test": {"score": 3}}}
	check(context._valid_state(saved, "w"), "a save with a mods section is valid")
	saved.mods = {"merge_test": 3}
	check(not context._valid_state(saved, "w"), "a malformed mods section is refused")
	# Dinnerbone on a stand-in pony: one bone 1.2 m up, the model turned over and lifted by it.
	var pony_script := GDScript.new(); pony_script.source_code = "extends Node3D\nvar _model: Node3D\nvar skeleton: Skeleton3D\n"; pony_script.reload()
	var pony := Node3D.new(); pony.set_script(pony_script); root.add_child(pony)
	var model := Node3D.new(); pony.add_child(model)
	var skeleton := Skeleton3D.new(); model.add_child(skeleton)
	skeleton.add_bone("ear"); skeleton.set_bone_rest(0, Transform3D(Basis(), Vector3(0, 1.2, 0)))
	pony.set("_model", model); pony.set("skeleton", skeleton)
	var dinnerbone: Node = mods.get_node_or_null("dinnerbone")
	check(dinnerbone != null, "Dinnerbone's entry script runs from its pack")
	if dinnerbone != null:
		dinnerbone.call("_turn", pony)
		check(model.transform.basis.y.is_equal_approx(Vector3.DOWN) and is_equal_approx(model.transform.origin.y, 1.2), "Dinnerbone turns the model over and stands it on its ears (%s)" % str(model.transform))
		dinnerbone.call("_turn", pony)
		check(model.transform.basis.y.is_equal_approx(Vector3.DOWN), "turning twice does not turn her back")
	print("MOD_LOADER_DONE ", "PASS" if failures == 0 else "FAIL", " checks=", checks, " failures=", failures)
	mods.queue_free(); pony.queue_free(); grouped.queue_free(); later.queue_free(); context.free(); game.free()
	await process_frame
	quit(0 if failures == 0 else 1)
