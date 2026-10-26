extends CanvasLayer
## Developer chemistry lab (dev 2026-10-26: "make the chemistry button like. h or some shit
## thatll open a dev gui"; the in-game chemistry set comes later). L opens it (H is hug). A
## dispenser of real elements, one beaker on a heater, the tgstation recipes, bottles (saved
## with the world, pony_belongings.gd), "Give" for a nearby pony to drink one now
## (pony_potion_effects.gd), "Give to keep" for her to carry it and use it later, maybe on
## somepony else, and "Set off" for explosives (chem_blast.gd). Heating an explosive in the
## beaker sets it off in front of you too.
## Developer builds only (game_player_rig.gd); desktop only.
const CATALOG := preload("res://world/chemistry/chem_catalog.gd")
const BEAKER := preload("res://world/chemistry/chem_beaker.gd")
const EFFECTS := preload("res://world/chemistry/pony_potion_effects.gd")
const BLAST := preload("res://world/chemistry/chem_blast.gd")
const BELONGINGS := preload("res://world/chemistry/pony_belongings.gd")
const TOGGLE_KEY := KEY_L
const AMOUNTS := [1, 5, 10, 30]
const BOTTLE_UNITS := 30.0
## Ponies this close to the player are offered in the "Give to" menu.
const GIVE_RANGE := 8.0
const KIND_ORDER := ["element", "compound", "medicine", "pyro", "potion"]
const KIND_TITLES := {"element": "Dispenser", "compound": "Compounds", "medicine": "Medicine", "pyro": "Pyrotechnics", "potion": "Potions"}

var game: Node
var opened := false
var beaker: RefCounted = BEAKER.new()
var bottles: Array = []   # {"dose": {id: units}, "from": "player" or the pony who gave it}
var _amount := 10
var _cheat := false
var _previous_mouse := Input.MOUSE_MODE_CAPTURED
var _panel: PanelContainer
var _dispenser: VBoxContainer
var _contents: VBoxContainer
var _fill: ProgressBar
var _swatch: ColorRect
var _temperature: Label
var _heater: CheckButton
var _target: HSlider
var _target_label: Label
var _log: RichTextLabel
var _bottle_list: ItemList
var _ponies: OptionButton
var _pony_nodes: Array = []
var _recipes: ItemList
var _recipe_rows: Array = []
var _refresh := 0.0
var _shown_contents := ""


func setup(host: Node) -> void:
	game = host
	layer = 115
	beaker.reacted.connect(func(message: String): _say(message, Color("ffd27a")))
	beaker.blasted.connect(func(reagent: String, units: float): BLAST.blast(game, _ahead(2.5), reagent, units, "player"))
	_build()
	_panel.hide()
	set_process(false)


func _build() -> void:
	var root := Control.new(); add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new(); root.add_child(_panel)
	var style := StyleBoxFlat.new(); style.bg_color = Color("1b1626f0"); style.border_color = Color("8a6fb5")
	style.set_border_width_all(1); style.set_corner_radius_all(8); style.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(1180, 680)
	_panel.position = -_panel.custom_minimum_size * 0.5
	_panel.resized.connect(func(): _panel.position = (root.size - _panel.size) * 0.5)
	root.resized.connect(func(): _panel.position = (root.size - _panel.size) * 0.5)

	var outer := VBoxContainer.new(); _panel.add_child(outer)
	var header := HBoxContainer.new(); outer.add_child(header)
	var title := Label.new(); title.text = "CHEMISTRY (dev)"; title.add_theme_color_override("font_color", Color("ffb3e6"))
	title.add_theme_font_size_override("font_size", 20); header.add_child(title)
	var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; header.add_child(spacer)
	header.add_child(_label("Dispense:"))
	var amounts := OptionButton.new(); amounts.focus_mode = Control.FOCUS_NONE
	for a: int in AMOUNTS: amounts.add_item("%du" % a)
	amounts.select(AMOUNTS.find(_amount)); amounts.item_selected.connect(func(i: int): _amount = AMOUNTS[i])
	header.add_child(amounts)
	var cheat := CheckButton.new(); cheat.text = "Every reagent"; cheat.focus_mode = Control.FOCUS_NONE
	cheat.tooltip_text = "Dispense compounds, medicines and potions directly, not only the elements."
	cheat.toggled.connect(func(on: bool): _cheat = on; _fill_dispenser()); header.add_child(cheat)
	header.add_child(_button("Close · L", close))

	var columns := HBoxContainer.new(); columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12); outer.add_child(columns)

	# Dispenser.
	var left := ScrollContainer.new(); left.custom_minimum_size = Vector2(330, 0)
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; columns.add_child(left)
	_dispenser = VBoxContainer.new(); _dispenser.size_flags_horizontal = Control.SIZE_EXPAND_FILL; left.add_child(_dispenser)
	_fill_dispenser()

	# Beaker and heater.
	var middle := VBoxContainer.new(); middle.custom_minimum_size = Vector2(390, 0); columns.add_child(middle)
	var beaker_row := HBoxContainer.new(); middle.add_child(beaker_row)
	_swatch = ColorRect.new(); _swatch.custom_minimum_size = Vector2(28, 28); beaker_row.add_child(_swatch)
	_fill = ProgressBar.new(); _fill.max_value = BEAKER.CAPACITY; _fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fill.custom_minimum_size.y = 28; beaker_row.add_child(_fill)
	var contents_scroll := ScrollContainer.new(); contents_scroll.custom_minimum_size.y = 170; middle.add_child(contents_scroll)
	_contents = VBoxContainer.new(); _contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL; contents_scroll.add_child(_contents)
	_temperature = _label(""); _temperature.add_theme_font_size_override("font_size", 18); middle.add_child(_temperature)
	var heat_row := HBoxContainer.new(); middle.add_child(heat_row)
	_heater = CheckButton.new(); _heater.text = "Heater"; _heater.focus_mode = Control.FOCUS_NONE
	_heater.toggled.connect(func(on: bool): beaker.heater = on); heat_row.add_child(_heater)
	_target = HSlider.new(); _target.min_value = 0; _target.max_value = 1000; _target.step = 5; _target.value = CATALOG.ROOM
	_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _target.focus_mode = Control.FOCUS_NONE
	_target.value_changed.connect(func(v: float): beaker.target = v; _target_label.text = "%d K" % int(v)); heat_row.add_child(_target)
	_target_label = _label("%d K" % int(CATALOG.ROOM)); _target_label.custom_minimum_size.x = 60; heat_row.add_child(_target_label)
	var presets := HBoxContainer.new(); middle.add_child(presets)
	for preset: Array in [["Freeze 200", 200], ["Room 300", 300], ["Warm 350", 350], ["Hot 400", 400], ["Boil 550", 550], ["Burn 800", 800]]:
		var kelvin: float = preset[1]
		presets.add_child(_button(preset[0], func(): _set_heat(kelvin)))
	var actions := HBoxContainer.new(); middle.add_child(actions)
	actions.add_child(_button("Bottle %du" % int(BOTTLE_UNITS), func(): _bottle(BOTTLE_UNITS)))
	actions.add_child(_button("Bottle all", func(): _bottle(BEAKER.CAPACITY)))
	actions.add_child(_button("Empty", func(): beaker.clear(); _say("Beaker emptied.", Color("aaaaaa"))))
	_log = RichTextLabel.new(); _log.scroll_following = true; _log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.custom_minimum_size.y = 120; _log.bbcode_enabled = true; middle.add_child(_log)

	# Bottles, giving, recipes.
	var tabs := TabContainer.new(); tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL; columns.add_child(tabs)
	var bottle_tab := VBoxContainer.new(); bottle_tab.name = "Bottles"; tabs.add_child(bottle_tab)
	_bottle_list = ItemList.new(); _bottle_list.size_flags_vertical = Control.SIZE_EXPAND_FILL; bottle_tab.add_child(_bottle_list)
	var give_row := HBoxContainer.new(); bottle_tab.add_child(give_row)
	give_row.add_child(_label("Give to"))
	_ponies = OptionButton.new(); _ponies.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _ponies.focus_mode = Control.FOCUS_NONE
	give_row.add_child(_ponies)
	var bottle_actions := HBoxContainer.new(); bottle_tab.add_child(bottle_actions)
	bottle_actions.add_child(_button("Give (drink now)", _give))
	var keep := _button("Give to keep", _give_keep)
	keep.tooltip_text = "She carries it and can use it later: drink it, give it to a friend, slip it to somepony, or set it off."
	bottle_actions.add_child(keep)
	bottle_actions.add_child(_button("Set off", _set_off))
	var more_actions := HBoxContainer.new(); bottle_tab.add_child(more_actions)
	more_actions.add_child(_button("Pour back", _pour_back))
	more_actions.add_child(_button("Discard", _discard))
	more_actions.add_child(_button("Cure pony", _cure))
	var recipe_tab := VBoxContainer.new(); recipe_tab.name = "Recipes"; tabs.add_child(recipe_tab)
	_recipes = ItemList.new(); _recipes.size_flags_vertical = Control.SIZE_EXPAND_FILL; recipe_tab.add_child(_recipes)
	var recipe_actions := HBoxContainer.new(); recipe_tab.add_child(recipe_actions)
	var fill := _button("Add ingredients ×5", func(): _fill_recipe(5))
	fill.tooltip_text = "Puts five batches of the selected recipe's ingredients in the beaker (any reagent, dev cheat) and sets the heater."
	recipe_actions.add_child(fill)
	_fill_recipes()


func _label(text: String) -> Label:
	var label := Label.new(); label.text = text
	return label


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new(); button.text = text; button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	return button


func _fill_dispenser() -> void:
	for child in _dispenser.get_children(): child.queue_free()
	var groups: Dictionary = {}
	var ids: Array = CATALOG.reagents().keys() if _cheat else CATALOG.dispenser()
	for id: String in ids:
		var kind := CATALOG.kind_of(id)
		if not groups.has(kind): groups[kind] = []
		groups[kind].append(id)
	for kind: String in KIND_ORDER:
		if not groups.has(kind): continue
		var heading := _label(KIND_TITLES.get(kind, kind.capitalize()))
		heading.add_theme_color_override("font_color", Color("c9b3ff")); _dispenser.add_child(heading)
		var grid := GridContainer.new(); grid.columns = 2; _dispenser.add_child(grid)
		for id: String in groups[kind]:
			var button := _button(CATALOG.name_of(id), func(): _dispense(id))
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.tooltip_text = str(CATALOG.reagent(id).get("description", ""))
			button.add_theme_color_override("font_color", CATALOG.color_of(id).lightened(0.25))
			grid.add_child(button)


func _fill_recipes() -> void:
	_recipes.clear(); _recipe_rows.clear()
	var rows: Array = (CATALOG.data().get("reactions", []) as Array).duplicate()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return KIND_ORDER.find(_recipe_kind(a)) > KIND_ORDER.find(_recipe_kind(b)) if _recipe_kind(a) != _recipe_kind(b) else str(a.id) < str(b.id))
	for reaction: Dictionary in rows:
		var makes: Array = (reaction.makes as Dictionary).keys()
		var result := ", ".join(makes.map(func(id: String) -> String: return CATALOG.name_of(id))) if not makes.is_empty() else str(reaction.get("message", reaction.id)).left(28)
		_recipes.add_item("%s  ←  %s" % [result, CATALOG.recipe_text(reaction)])
		_recipes.set_item_tooltip(_recipes.item_count - 1, str(reaction.get("message", "")))
		if not makes.is_empty(): _recipes.set_item_custom_fg_color(_recipes.item_count - 1, CATALOG.color_of(makes[0]).lightened(0.3))
		_recipe_rows.append(reaction)


func _recipe_kind(reaction: Dictionary) -> String:
	var makes: Array = (reaction.makes as Dictionary).keys()
	return CATALOG.kind_of(makes[0]) if not makes.is_empty() else "pyro"


func _dispense(id: String) -> void:
	var added: float = beaker.add(id, _amount)
	if added <= 0.0: _say("The beaker is full.", Color("ff8080"))
	else: _say("+%.0fu %s" % [added, CATALOG.name_of(id)], Color("dddddd"))


func _set_heat(kelvin: float) -> void:
	_target.value = kelvin
	_heater.button_pressed = true


func _fill_recipe(batches: int) -> void:
	var picked := _recipes.get_selected_items()
	if picked.is_empty(): _say("Pick a recipe first.", Color("ff8080")); return
	var reaction: Dictionary = _recipe_rows[picked[0]]
	if reaction.has("min_temp"): _set_heat(float(reaction.min_temp) + 20.0)
	elif reaction.has("max_temp"): _set_heat(maxf(0.0, float(reaction.max_temp) - 20.0))
	# Catalysts are not used up; one dose is enough.
	for id: String in reaction.get("catalysts", {}): beaker.add(id, float(reaction.catalysts[id]))
	for id: String in reaction.requires: beaker.add(id, float(reaction.requires[id]) * batches)
	_say("Added the ingredients for %s." % CATALOG.recipe_text(reaction), Color("dddddd"))


func _bottle(units: float) -> void:
	var dose: Dictionary = beaker.pour(units)
	if dose.is_empty(): _say("Nothing to bottle.", Color("ff8080")); return
	bottles.append({"dose": dose, "from": "player"})
	_save_bottles()
	_bottle_list.select(bottles.size() - 1)
	_say("Bottled: " + BELONGINGS.label_of(dose), Color("b3ffb3"))


func _selected_bottle() -> int:
	var picked := _bottle_list.get_selected_items()
	return picked[0] if not picked.is_empty() and picked[0] < bottles.size() else -1


func _give() -> void:
	var index := _selected_bottle()
	if index < 0: _say("Pick a bottle first.", Color("ff8080")); return
	var pony_index := _ponies.selected
	if pony_index < 0 or pony_index >= _pony_nodes.size() or not is_instance_valid(_pony_nodes[pony_index]):
		_say("No pony nearby to give it to.", Color("ff8080")); return
	var result: Dictionary = EFFECTS.give(game, _pony_nodes[pony_index], bottles[index].dose)
	_say(str(result.text), Color("b3ffb3") if result.ok else Color("ffb380"))
	if result.ok:
		bottles.remove_at(index)
		_save_bottles()


func _give_keep() -> void:
	var index := _selected_bottle()
	if index < 0: _say("Pick a bottle first.", Color("ff8080")); return
	var pony_index := _ponies.selected
	var belongings: Node = get_tree().get_first_node_in_group("pony_belongings")
	if belongings == null or pony_index < 0 or pony_index >= _pony_nodes.size() or not is_instance_valid(_pony_nodes[pony_index]):
		_say("No pony nearby to give it to.", Color("ff8080")); return
	var result: Dictionary = belongings.keep(_pony_nodes[pony_index], bottles[index].dose)
	_say(str(result.text), Color("b3ffb3") if result.ok else Color("ffb380"))
	if result.ok:
		bottles.remove_at(index)
		_save_bottles()


## Explosive bottles go off a few steps in front of you.
func _set_off() -> void:
	var index := _selected_bottle()
	if index < 0: _say("Pick a bottle first.", Color("ff8080")); return
	var dose: Dictionary = bottles[index].dose
	var explosive := BLAST.explosive_in(dose)
	if explosive.is_empty(): _say("That's not an explosive.", Color("ff8080")); return
	BLAST.blast(game, _ahead(3.0), explosive, float(dose[explosive]), "player")
	_say("You set off the %s." % CATALOG.name_of(explosive).to_lower(), Color("ffd27a"))
	bottles.remove_at(index)
	_save_bottles()


## A point `metres` ahead of the camera, at its feet height.
func _ahead(metres: float) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera == null: return Vector3.ZERO
	var forward := -camera.global_basis.z; forward.y = 0.0
	var feet: Vector3 = (game.player as Node3D).global_position if is_instance_valid(game.get("player")) else camera.global_position
	return feet + forward.normalized() * metres + Vector3.UP * 0.3


func _pour_back() -> void:
	var index := _selected_bottle()
	if index < 0: return
	for id: String in bottles[index].dose: beaker.add(id, float(bottles[index].dose[id]))
	bottles.remove_at(index); _save_bottles()


func _discard() -> void:
	var index := _selected_bottle()
	if index < 0: return
	bottles.remove_at(index); _save_bottles()


func _cure() -> void:
	var pony_index := _ponies.selected
	if pony_index < 0 or pony_index >= _pony_nodes.size() or not is_instance_valid(_pony_nodes[pony_index]): return
	var effects: Node = (_pony_nodes[pony_index] as Node).get_node_or_null("PotionEffects")
	if effects == null: _say("%s isn't under any potion." % EFFECTS.display_name(_pony_nodes[pony_index]), Color("aaaaaa")); return
	effects.cure()
	_say("%s's potions wear off." % EFFECTS.display_name(_pony_nodes[pony_index]), Color("aaaaaa"))


## Saved with the world (pony_belongings.gd "chem_bottles"); ponies can hand theirs to Anon.
func _save_bottles() -> void:
	var belongings: Node = get_tree().get_first_node_in_group("pony_belongings")
	if belongings != null: belongings.set_player_bottles(bottles)
	_refresh_bottles()


## A pony handed Anon a bottle: reload them.
func refresh_bottles() -> void:
	var belongings: Node = get_tree().get_first_node_in_group("pony_belongings")
	if belongings != null and belongings.has_world(): bottles = belongings.player_bottles()
	_refresh_bottles()


func _refresh_bottles() -> void:
	_bottle_list.clear()
	for bottle: Dictionary in bottles:
		var from := str(bottle.get("from", "player"))
		_bottle_list.add_item(BELONGINGS.label_of(bottle.dose) + ("" if from == "player" else "  · from " + EFFECTS.giver_name(game, from)))
		_bottle_list.set_item_custom_fg_color(_bottle_list.item_count - 1, CATALOG.color_of(BELONGINGS.main_of(bottle.dose)).lightened(0.3))


func _refresh_ponies() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null: return
	var rows: Array = []
	var mares: Array = game.get("mares") if game.get("mares") is Array else []
	for pony: Variant in mares:
		if not is_instance_valid(pony) or not (pony as Node3D).is_inside_tree(): continue
		var distance := camera.global_position.distance_to((pony as Node3D).global_position)
		if distance <= GIVE_RANGE: rows.append([distance, pony])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var nodes: Array = rows.map(func(row: Array): return row[1])
	if nodes == _pony_nodes:
		for i in rows.size(): _ponies.set_item_text(i, _pony_text(rows[i][1], rows[i][0]))
		return
	var keep: Variant = _pony_nodes[_ponies.selected] if _ponies.selected >= 0 and _ponies.selected < _pony_nodes.size() else null
	_pony_nodes = nodes
	_ponies.clear()
	for row: Array in rows: _ponies.add_item(_pony_text(row[1], row[0]))
	if _pony_nodes.is_empty(): _ponies.add_item("(nopony within %d m)" % int(GIVE_RANGE)); _ponies.disabled = true
	else:
		_ponies.disabled = false
		_ponies.select(maxi(0, _pony_nodes.find(keep)))


func _pony_text(pony: Node, distance: float) -> String:
	var effects: Node = pony.get_node_or_null("PotionEffects")
	var under := ""
	if effects != null and not effects.active.is_empty():
		under = " · " + ", ".join((effects.active.keys() as Array).map(func(id: String) -> String: return CATALOG.name_of(id).to_lower()))
	var belongings: Node = get_tree().get_first_node_in_group("pony_belongings")
	var carried: Array = belongings.keys_for(EFFECTS.pony_id(pony)) if belongings != null else []
	if not carried.is_empty(): under += " · carrying " + ", ".join(carried)
	return "%s (%.1f m)%s" % [EFFECTS.display_name(pony), distance, under]


func _say(text: String, color: Color) -> void:
	if _log == null or text.strip_edges().is_empty(): return
	_log.append_text("[color=#%s]%s[/color]\n" % [color.to_html(false), text.replace("[", "[lb]")])


func _process(delta: float) -> void:
	beaker.step(delta)
	_refresh -= delta
	if _refresh > 0.0: return
	_refresh = 0.2
	_update_beaker()
	_refresh_ponies()


func _update_beaker() -> void:
	_fill.value = beaker.total()
	_swatch.color = beaker.color()
	var t: float = beaker.temperature
	_temperature.text = "%.0f K  (%.0f °C)%s" % [t, t - 273.15, "  · heating" if beaker.heater and absf(t - beaker.target) > 0.5 else ""]
	var ids: Array = beaker.contents.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return float(beaker.contents[a]) > float(beaker.contents[b]))
	# Rebuilt only when the contents change, so a click on a row's button is never lost.
	var shown := ",".join(ids.map(func(id: String) -> String: return "%s=%.1f" % [id, float(beaker.contents[id])]))
	if shown == _shown_contents: return
	_shown_contents = shown
	for child in _contents.get_children(): child.queue_free()
	if ids.is_empty(): _contents.add_child(_label("(empty beaker)"))
	for id: String in ids:
		var row := HBoxContainer.new(); _contents.add_child(row)
		var dot := ColorRect.new(); dot.color = CATALOG.color_of(id); dot.custom_minimum_size = Vector2(12, 12)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER; row.add_child(dot)
		var label := _label("%.1fu  %s" % [float(beaker.contents[id]), CATALOG.name_of(id)])
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(label)
		row.add_child(_button("−5", func(): beaker.remove(id, 5.0)))
		row.add_child(_button("×", func(): beaker.remove(id, INF)))


func open() -> void:
	if opened: return
	opened = true
	refresh_bottles()
	_previous_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(game.get("player")) and "controls_locked" in game.player: game.player.controls_locked = true
	_panel.show()
	_refresh = 0.0
	set_process(true)


func close() -> void:
	if not opened: return
	opened = false
	Input.mouse_mode = _previous_mouse
	if is_instance_valid(game.get("player")) and "controls_locked" in game.player: game.player.controls_locked = false
	_panel.hide()
	# The beaker waits, heater and all, while the window is shut.
	set_process(false)


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed: return
	if get_viewport().gui_get_focus_owner() is LineEdit: return
	if event.physical_keycode == TOGGLE_KEY:
		if opened: close()
		else: open()
		get_viewport().set_input_as_handled()
	elif opened and event.physical_keycode == KEY_ESCAPE:
		close(); get_viewport().set_input_as_handled()
