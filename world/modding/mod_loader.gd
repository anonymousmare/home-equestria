extends RefCounted
## Mods (dev 2026-10-26: "anything moddable. ANYTHING"). A mod is a resource pack (.pck) that
## carries res://mods/<id>/mod.json and anything else. Settings._init calls boot() right after
## the game's own packs (tools/build/packs.gd) and before any other game script loads, so a mod can:
## - replace any game file (a file in the pack at the game's own path; fragile across updates),
## - deep-merge JSON into game data (res://mods/<id>/merge/<path under res://>),
## - extend any game script (mod.json "extends": scripts that `extends "res://<game script>"`),
## - run its own code (mod.json "entry": a Node the Mods autoload adds, world/modding/mods.gd).
## Packs come from the mods folders (user://mods/, and mods/ beside the executable) and, as
## before, loose .pck files beside the executable that are not the game's own. They load in file
## name order, after the game's packs. Switches in Settings → Mods are kept in user://mods/mods.cfg
## and apply on the next launch. Guide for modders and their AI agents: res://mods/README.md,
## res://mods/AGENTS.md (source repository only).

const USER_DIR := "user://mods"
const SETTINGS := "user://mods/mods.cfg"
const MERGED := "user://mods/.merged"
const MODS_ROOT := "res://mods"
const PACKS := preload("res://tools/build/packs.gd")
const ID_PATTERN := "^[a-z0-9_]{1,40}$"
## Marker the build tool adds to a mod's folder inside its pack.
const BUILT := "mod.built.json"

## Every pack seen this launch: {file, path, enabled, loose, ids, mounted, error}.
static var packs: Array = []
## Every mod found: {id, name, version, author, description, game_version, entry, extends, file,
## enabled, errors: Array[String]}. Only mods with no errors run.
static var mods: Array = []
static var booted := false

static func boot(dirs: Array = [], loose_dirs: Array = [], disabled_override: Variant = null) -> void:
	booted = true
	packs.clear(); mods.clear()
	if dirs.is_empty(): dirs = mod_dirs()
	if loose_dirs.is_empty() and OS.has_feature("template") and not OS.has_feature("android"):
		loose_dirs = [OS.get_executable_path().get_base_dir()]
	var disabled: PackedStringArray = disabled_override if disabled_override is PackedStringArray else disabled_files()
	var seen := {}
	for dir: String in dirs + loose_dirs:
		if not DirAccess.dir_exists_absolute(dir): continue
		var names := DirAccess.get_files_at(dir)
		names.sort()
		var loose := dir in loose_dirs
		for name: String in names:
			if name.get_extension().to_lower() != "pck" or seen.has(name) or (loose and PACKS.is_game_pack(name)): continue
			seen[name] = true
			var row := {"file": name, "path": dir.path_join(name), "enabled": name not in disabled, "loose": loose, "ids": [], "mounted": false, "error": ""}
			packs.append(row)
			if row.enabled: _mount(row)
	# Source runs (development, mod authors): `-- --mod-src <id>` runs res://mods/<id> unpacked.
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--mod-src" and i + 1 < args.size() and DirAccess.dir_exists_absolute(MODS_ROOT.path_join(args[i + 1])):
			var row := {"file": "(source) " + args[i + 1], "path": "", "enabled": true, "loose": false, "ids": [args[i + 1]], "mounted": true, "error": ""}
			packs.append(row)
	for row: Dictionary in packs:
		for id: String in row.ids: mods.append(read_manifest(id, row))
	for mod: Dictionary in mods:
		if mod.enabled and mod.errors.is_empty(): print("[mods] %s %s (%s)" % [mod.id, mod.version, mod.file])
		elif not mod.errors.is_empty(): push_warning("[mods] %s not loaded: %s" % [mod.id, "; ".join(mod.errors)])
	apply_merges(active())
	apply_extensions(active())

## Mods that load and run this launch.
static func active() -> Array:
	return mods.filter(func(mod: Dictionary) -> bool: return mod.enabled and mod.errors.is_empty())

static func mod_dirs() -> Array:
	var dirs: Array = [ProjectSettings.globalize_path(USER_DIR)]
	if OS.has_feature("template") and not OS.has_feature("android"):
		dirs.append(OS.get_executable_path().get_base_dir().path_join("mods"))
	if OS.has_feature("android"):
		for dir: String in PACKS.android_directories(OS.get_user_data_dir()):
			var mods_dir := dir.path_join("mods")
			if mods_dir not in dirs: dirs.append(mods_dir)
	return dirs


static func disabled_files() -> PackedStringArray:
	var config := ConfigFile.new()
	if config.load(SETTINGS) != OK: return PackedStringArray()
	var value: Variant = config.get_value("mods", "disabled", PackedStringArray())
	return PackedStringArray(value) if value is Array or value is PackedStringArray else PackedStringArray()

## Settings → Mods switch; takes effect on the next launch.
static func set_enabled(file: String, enabled: bool) -> void:
	var disabled := disabled_files()
	if enabled:
		if file in disabled: disabled.remove_at(disabled.find(file))
	elif file not in disabled: disabled.append(file)
	var config := ConfigFile.new()
	config.load(SETTINGS)
	config.set_value("mods", "disabled", disabled)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(USER_DIR))
	config.save(SETTINGS)

## Mounts one pack and notes which mods it brought: res://mods/<id> folders that are new, or that
## gained a BUILT marker (tools/modding/build_mod.gd writes it into the pack only, so a pack built
## from a source project that also holds res://mods/<id> is still recognised).
static func _mount(row: Dictionary) -> void:
	var folders := _mod_folders()
	var built := _built_ids()
	if not ProjectSettings.load_resource_pack(row.path, true):
		row.error = "could not be read as a resource pack"; push_warning("[mods] could not load %s" % row.path); return
	row.mounted = true
	for id: String in _mod_folders():
		if id not in folders or (id not in built and FileAccess.file_exists(MODS_ROOT.path_join(id).path_join(BUILT))): row.ids.append(id)

static func _built_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in _mod_folders():
		if FileAccess.file_exists(MODS_ROOT.path_join(id).path_join(BUILT)): out.append(id)
	return out

static func _mod_folders() -> PackedStringArray:
	return DirAccess.get_directories_at(MODS_ROOT) if DirAccess.dir_exists_absolute(MODS_ROOT) else PackedStringArray()

static func read_manifest(id: String, row: Dictionary) -> Dictionary:
	var mod := {"id": id, "name": id, "version": "", "author": "", "description": "", "game_version": "",
		"entry": "", "extends": [], "file": row.file, "enabled": row.enabled, "errors": []}
	var errors: Array = mod.errors
	var regex := RegEx.create_from_string(ID_PATTERN)
	if regex.search(id) == null: errors.append("folder name must be lower-case letters, digits or _")
	var path := MODS_ROOT.path_join(id).path_join("mod.json")
	var doc: Variant = parse(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not doc is Dictionary: errors.append("no readable %s" % path); return mod
	for key: String in ["name", "version", "author", "description", "game_version", "entry"]:
		if doc.has(key):
			if doc[key] is String: mod[key] = str(doc[key]).strip_edges()
			else: errors.append("%s must be text" % key)
	if doc.has("id") and str(doc.id) != id: errors.append("id \"%s\" does not match its folder" % str(doc.id))
	if doc.has("extends"):
		if doc.extends is Array and (doc.extends as Array).all(func(p: Variant) -> bool: return p is String): mod.extends = doc.extends.duplicate()
		else: errors.append("extends must be a list of script paths")
	if not str(mod.entry).is_empty() and not ResourceLoader.exists(str(mod.entry)): errors.append("entry %s is missing" % mod.entry)
	return mod

## Deep-merges each mod's res://mods/<id>/merge/<path>.json over the game's res://<path>.json
## (dictionaries merge key by key, lists append, anything else replaces; later mods win) and mounts
## the results as one more pack, so every reader sees the merged data.
static func apply_merges(list: Array) -> void:
	var merged := {}   # res:// target -> Variant
	for mod: Dictionary in list:
		var root := MODS_ROOT.path_join(mod.id).path_join("merge")
		for source: String in _files_under(root):
			if source.get_extension().to_lower() != "json": continue
			var target := "res://" + source.trim_prefix(root + "/")
			var patch: Variant = parse(FileAccess.get_file_as_string(source))
			if patch == null: push_warning("[mods] %s: %s is not valid JSON" % [mod.id, source]); continue
			var base: Variant = merged.get(target, JSON.parse_string(FileAccess.get_file_as_string(target)) if FileAccess.file_exists(target) else null)
			merged[target] = deep_merge(base, patch)
	if merged.is_empty(): return
	var folder := ProjectSettings.globalize_path(MERGED)
	DirAccess.make_dir_recursive_absolute(folder)
	var packer := PCKPacker.new()
	var pack := folder.path_join("merged.pck")
	if packer.pck_start(pack) != OK: push_warning("[mods] could not write %s" % pack); return
	var n := 0
	for target: String in merged:
		var file_path := folder.path_join("%d.json" % n); n += 1
		var file := FileAccess.open(file_path, FileAccess.WRITE)
		if file == null: continue
		file.store_string(JSON.stringify(merged[target], "\t")); file.close()
		packer.add_file(target, file_path)
	packer.flush()
	if not ProjectSettings.load_resource_pack(pack, true): push_warning("[mods] could not mount merged data")
	else: print("[mods] merged %d data file(s)" % merged.size())

## JSON text, or null when it is not valid (quietly: a broken mod must not flood the log).
static func parse(text: String) -> Variant:
	var json := JSON.new()
	return json.data if json.parse(text) == OK else null

static func deep_merge(base: Variant, patch: Variant) -> Variant:
	if base is Dictionary and patch is Dictionary:
		var out: Dictionary = (base as Dictionary).duplicate(true)
		for key: Variant in patch: out[key] = deep_merge(out.get(key), patch[key])
		return out
	if base is Array and patch is Array: return (base as Array) + (patch as Array)
	return patch

## Script extensions: each listed script `extends "res://<game script>"` and takes over that path,
## so everything that loads the game script afterwards gets the mod's subclass. Two mods extending
## one script chain in load order. Scripts already loaded before boot() (Settings' own preloads,
## XR tools) cannot be extended.
static func apply_extensions(list: Array) -> void:
	for mod: Dictionary in list:
		for path: String in mod.extends:
			var script := load(path) as Script
			var base: Script = script.get_base_script() if script != null else null
			if base == null or base.resource_path.is_empty():
				push_warning("[mods] %s: %s does not extend a game script" % [mod.id, path]); continue
			var target := base.resource_path
			script.take_over_path(target)
			print("[mods] %s extends %s" % [mod.id, target])

static func _files_under(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir): return out
	for name: String in DirAccess.get_files_at(dir): out.append(dir.path_join(name))
	for sub: String in DirAccess.get_directories_at(dir): out.append_array(_files_under(dir.path_join(sub)))
	return out
