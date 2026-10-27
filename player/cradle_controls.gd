extends CanvasLayer
## Bridal carry controls (desktop): a small stack of controls in the bottom right corner instead of the
## row under the crosshair, which sat where her subtitles go while she is cradled
## (overhead_dialogue.gd lifts them). desktop_interactions.gd fills and shows it.
## Rows are [key, "tap" | "hold" | "", action]; colours as the prompt row (interaction_hints.gd).

const INK := Color("f4f1ff")
const SHADE := Color("1a1624")
const MUTED := Color(0.957, 0.945, 1.0, 0.6)
const MARGIN := 28.0
const FADE_SECONDS := .15

var _card: PanelContainer
var _rows: VBoxContainer
var _shown: Array = []


func _ready() -> void:
	layer = 5
	_card = PanelContainer.new()
	# No backing: outlined words over the world, like the prompt row.
	_card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)
	# Pinned to the corner, growing left and up as rows come and go.
	_card.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_card.offset_left = -MARGIN; _card.offset_right = -MARGIN
	_card.offset_top = -MARGIN; _card.offset_bottom = -MARGIN
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(stack)
	var title := _label("BRIDAL CARRY", 14, MUTED)
	title.add_theme_color_override("font_outline_color", SHADE)
	title.add_theme_constant_override("outline_size", 5)
	stack.add_child(title)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 7)
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(_rows)
	_card.modulate.a = 0.0
	_card.visible = false


func update(on: bool, rows: Array, delta: float) -> void:
	if on and rows != _shown: _build(rows)
	_card.modulate.a = move_toward(_card.modulate.a, 1.0 if on else 0.0, delta / FADE_SECONDS)
	_card.visible = _card.modulate.a > 0.0


func _build(rows: Array) -> void:
	_shown = rows.duplicate(true)
	for child: Node in _rows.get_children(): child.queue_free()
	for row: Array in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(_keycap(str(row[0])))
		var mode := _label(str(row[1]), 15, MUTED)
		mode.add_theme_color_override("font_outline_color", SHADE)
		mode.add_theme_constant_override("outline_size", 5)
		mode.custom_minimum_size.x = 38.0
		mode.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(mode)
		var action := _label(str(row[2]), 21, INK)
		action.add_theme_color_override("font_outline_color", SHADE)
		action.add_theme_constant_override("outline_size", 6)
		action.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(action)
		_rows.add_child(line)


## A light keycap with the key in dark ink, like the prompt icons.
func _keycap(key: String) -> Control:
	var cap := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = INK
	style.border_color = SHADE
	style.set_border_width_all(2)
	style.border_width_bottom = 4
	style.set_corner_radius_all(7)
	style.content_margin_left = 9.0; style.content_margin_right = 9.0
	style.content_margin_top = 2.0; style.content_margin_bottom = 2.0
	cap.add_theme_stylebox_override("panel", style)
	cap.custom_minimum_size = Vector2(36, 34)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var text := _label(key, 19, SHADE)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cap.add_child(text)
	return cap


func _label(text: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
