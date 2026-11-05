extends RefCounted
class_name InventoryPanelView

signal dim_clicked

const ITEM_SLOT := preload("res://scripts/ui/item_slot.gd")
const Capacities := preload("res://scripts/inventory/capacities.gd")
const HudChrome := preload("res://scripts/ui/hud_chrome.gd")

var dim: ColorRect
var panel: PanelContainer
var craft_col: VBoxContainer
var backpack_slots: Array = []


func ensure(host: Node, bind_slot: Callable) -> void:
	if panel != null:
		return
	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.visible = false
	dim.gui_input.connect(_on_dim_input)
	host.add_child(dim)

	panel = PanelContainer.new()
	panel.z_index = 1
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.clip_contents = true
	panel.visible = false
	panel.add_theme_stylebox_override(&"panel", HudChrome.window_style(Color(0.07, 0.08, 0.09, 0.97)))
	host.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	panel.add_child(margin)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override(&"separation", 20)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(columns)

	var storage := VBoxContainer.new()
	var backpack_span := float(Capacities.GRID_COLUMNS) * 58.0 + float(Capacities.GRID_COLUMNS - 1) * 8.0
	storage.custom_minimum_size = Vector2(backpack_span + 16.0, 0)
	storage.add_theme_constant_override(&"separation", 12)
	columns.add_child(storage)
	storage.add_child(HudChrome.section_title("INVENTORY"))
	var caption := Label.new()
	caption.set_meta(&"key", "BACKPACK")
	caption.text = TranslationServer.translate("BACKPACK")
	caption.add_theme_font_size_override(&"font_size", 13)
	caption.add_theme_color_override(&"font_color", Color(0.7, 0.73, 0.76))
	storage.add_child(caption)
	var grid := GridContainer.new()
	grid.columns = Capacities.GRID_COLUMNS
	grid.add_theme_constant_override(&"h_separation", 8)
	grid.add_theme_constant_override(&"v_separation", 8)
	storage.add_child(grid)
	for i in Capacities.BACKPACK:
		var backpack_slot = ITEM_SLOT.new()
		backpack_slot.slot_index = Capacities.HOTBAR + i
		backpack_slot.hotbar = false
		backpack_slot.custom_minimum_size = Vector2(58, 58)
		grid.add_child(bind_slot.call(backpack_slot, backpack_slots))

	var crafting := PanelContainer.new()
	crafting.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crafting.size_flags_vertical = Control.SIZE_EXPAND_FILL
	crafting.add_theme_stylebox_override(&"panel", HudChrome.window_style(Color(0.1, 0.11, 0.12, 1)))
	columns.add_child(crafting)
	var craft_margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		craft_margin.add_theme_constant_override(side, 12)
	crafting.add_child(craft_margin)
	craft_col = VBoxContainer.new()
	craft_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	craft_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	craft_col.add_theme_constant_override(&"separation", 8)
	craft_margin.add_child(craft_col)
	craft_col.add_child(HudChrome.section_title("CRAFTING"))


func set_open(open: bool) -> void:
	if dim != null:
		dim.visible = open
	if panel != null:
		panel.visible = open


func apply_bounds(view: Vector2) -> int:
	if panel == null:
		return 2
	var width := minf(1100.0, maxf(view.x - 32.0, 720.0))
	var height := minf(620.0, maxf(view.y - 130.0, 360.0))
	panel.offset_left = -width * 0.5
	panel.offset_right = width * 0.5
	panel.offset_top = -height * 0.5 - 28.0
	panel.offset_bottom = height * 0.5 - 28.0
	var backpack_span := float(Capacities.GRID_COLUMNS) * 58.0 + float(Capacities.GRID_COLUMNS - 1) * 8.0 + 16.0
	var craft_width := width - backpack_span - 20.0 - 56.0
	return maxi(int(craft_width / 128.0), 2)


func _on_dim_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	var button := event as InputEventMouseButton
	if button.button_index == MOUSE_BUTTON_LEFT:
		dim_clicked.emit()
