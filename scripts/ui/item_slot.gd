extends Panel

signal clicked(index: int)
signal shift_clicked(index: int)
signal dropped_on(from_index: int, to_index: int)
signal transferred(from_tag: String, from_index: int, to_tag: String, to_index: int)
signal cancel_requested
signal pointer_entered(index: int)
signal primary_pressed(index: int)
signal primary_released(index: int, double_click: bool)
signal secondary_pressed(index: int)
signal secondary_released(index: int)

const ICONS := preload("res://scripts/ui/item_icons.gd")
const PREVIEW := preload("res://scripts/ui/build_preview.gd")
const RECIPES := preload("res://scripts/resources/recipe_catalog.gd")
const DOUBLE_CLICK_MS := 320

@export var slot_index: int = -1
@export var interactive: bool = true
@export var hotbar: bool = false
var drag_tag: String = ""
var resource_id: String = ""

var _icon: TextureRect
var _qty: Label
var _key: Label
var _dur_bg: ColorRect
var _dur_fill: ColorRect
var _did_drag := false
var _primary_down := false
var _last_primary_release_ms := -1


func _ready() -> void:
	if custom_minimum_size.x < 48.0:
		custom_minimum_size = Vector2(48, 48)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	mouse_entered.connect(_on_mouse_entered)
	_ensure_ui()


func set_item(
	id: String,
	amount: int,
	selected: bool,
	_picked: bool,
	durability: int = -1,
	max_durability: int = 0
) -> void:
	_ensure_ui()
	resource_id = id
	var tip := "" if id.is_empty() else RECIPES.tooltip_text(id)
	if max_durability > 0 and durability >= 0 and not id.is_empty():
		tip = "%s\nDurabilité %d / %d" % [tip, durability, max_durability]
	tooltip_text = tip
	_icon.texture = _texture_for(id)
	_qty.text = "" if id.is_empty() or amount <= 1 else "x%d" % amount
	_key.text = str(slot_index + 1) if hotbar and id.is_empty() else ""
	_set_durability_bar(durability, max_durability)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.12, 0.13) if id.is_empty() else Color(0.16, 0.17, 0.18)
	style.set_corner_radius_all(2)
	var border := Color(0.3, 0.32, 0.34)
	var width := 1
	if selected:
		border = Color(0.95, 0.78, 0.25)
		width = 2
	style.border_color = border
	style.set_border_width_all(width)
	add_theme_stylebox_override(&"panel", style)


func _texture_for(id: String) -> Texture2D:
	if id.is_empty():
		return null
	var preview := PREVIEW.texture_for(id)
	if preview != null:
		return preview
	return ICONS.get_texture(id)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if not interactive or resource_id.is_empty() or drag_tag.is_empty():
		return null
	_did_drag = true
	var preview := TextureRect.new()
	preview.texture = _icon.texture
	preview.custom_minimum_size = Vector2(36, 36)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_drag_preview(preview)
	return slot_index


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not interactive:
		return false
	if data is int:
		return int(data) != slot_index
	if data is Dictionary and not drag_tag.is_empty():
		return true
	return false


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if data is Dictionary:
		transferred.emit(str(data.get("tag", "")), int(data.get("index", -1)), drag_tag, slot_index)
		return
	dropped_on.emit(int(data), slot_index)


func _gui_input(event: InputEvent) -> void:
	if not interactive or not event is InputEventMouseButton:
		return
	var button := event as InputEventMouseButton
	if button.button_index == MOUSE_BUTTON_RIGHT:
		if button.pressed:
			secondary_pressed.emit(slot_index)
		else:
			secondary_released.emit(slot_index)
		accept_event()
		return
	if button.button_index != MOUSE_BUTTON_LEFT:
		return
	if button.pressed:
		_did_drag = false
		_primary_down = true
		primary_pressed.emit(slot_index)
		return
	_primary_down = false
	if _did_drag:
		_did_drag = false
		accept_event()
		return
	if button.shift_pressed:
		shift_clicked.emit(slot_index)
		accept_event()
		return
	var now := Time.get_ticks_msec()
	var double_click := _last_primary_release_ms >= 0 and now - _last_primary_release_ms <= DOUBLE_CLICK_MS
	_last_primary_release_ms = now
	primary_released.emit(slot_index, double_click)
	clicked.emit(slot_index)
	accept_event()


func _on_mouse_entered() -> void:
	pointer_entered.emit(slot_index)


func _set_durability_bar(durability: int, max_durability: int) -> void:
	var show := max_durability > 0 and durability >= 0 and not resource_id.is_empty()
	_dur_bg.visible = show
	_dur_fill.visible = show
	if not show:
		return
	var ratio := clampf(float(durability) / float(max_durability), 0.0, 1.0)
	_dur_fill.anchor_right = ratio
	_dur_fill.offset_right = 0.0
	if ratio > 0.5:
		_dur_fill.color = Color(0.35, 0.85, 0.4)
	elif ratio > 0.25:
		_dur_fill.color = Color(0.95, 0.75, 0.2)
	else:
		_dur_fill.color = Color(0.9, 0.28, 0.22)


func _ensure_ui() -> void:
	if _icon != null:
		return
	_icon = TextureRect.new()
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon.offset_left = 6
	_icon.offset_top = 6
	_icon.offset_right = -6
	_icon.offset_bottom = -10
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_icon)

	_dur_bg = ColorRect.new()
	_dur_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dur_bg.color = Color(0.08, 0.08, 0.09, 0.95)
	_dur_bg.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_dur_bg.offset_left = 4
	_dur_bg.offset_right = -4
	_dur_bg.offset_top = -5
	_dur_bg.offset_bottom = -2
	_dur_bg.visible = false
	add_child(_dur_bg)

	_dur_fill = ColorRect.new()
	_dur_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dur_fill.color = Color(0.35, 0.85, 0.4)
	_dur_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dur_fill.offset_left = 0
	_dur_fill.offset_top = 0
	_dur_fill.offset_right = 0
	_dur_fill.offset_bottom = 0
	_dur_bg.add_child(_dur_fill)

	_qty = Label.new()
	_qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_qty.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_qty.offset_left = -46
	_qty.offset_top = -18
	_qty.offset_right = -2
	_qty.offset_bottom = -5
	_qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_qty.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_qty.add_theme_font_size_override(&"font_size", 11)
	_qty.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.95))
	_qty.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 1))
	_qty.add_theme_constant_override(&"outline_size", 4)
	add_child(_qty)

	_key = Label.new()
	_key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_key.position = Vector2(4, 1)
	_key.add_theme_font_size_override(&"font_size", 11)
	_key.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.35))
	add_child(_key)
