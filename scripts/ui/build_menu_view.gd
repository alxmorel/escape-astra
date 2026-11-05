extends RefCounted
class_name BuildMenuView

signal piece_chosen(piece_id: String)

const RECIPES := preload("res://scripts/resources/recipe_catalog.gd")
const HudChrome := preload("res://scripts/ui/hud_chrome.gd")

var dim: ColorRect
var panel: PanelContainer

var _sub_row: HBoxContainer
var _grid: GridContainer
var _sub := "All"
var _inventory


func ensure(host: Node) -> void:
	if panel != null:
		return
	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.visible = false
	dim.z_index = 6
	host.add_child(dim)
	panel = PanelContainer.new()
	panel.z_index = 7
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
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override(&"separation", 8)
	margin.add_child(column)
	column.add_child(HudChrome.section_title("TAB_CONSTRUCTION"))
	_sub_row = HBoxContainer.new()
	_sub_row.add_theme_constant_override(&"separation", 4)
	column.add_child(_sub_row)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	column.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override(&"h_separation", 8)
	_grid.add_theme_constant_override(&"v_separation", 8)
	scroll.add_child(_grid)
	rebuild_subs()
	rebuild_catalog()
	apply_bounds(host.get_viewport().get_visible_rect().size)


func set_inventory(inventory) -> void:
	_inventory = inventory


func set_open(open: bool) -> void:
	if dim != null:
		dim.visible = open
	if panel != null:
		panel.visible = open
	if open:
		rebuild_subs()
		rebuild_catalog()


func apply_bounds(view: Vector2) -> void:
	if panel == null:
		return
	var width := minf(920.0, maxf(view.x - 48.0, 640.0))
	var height := minf(560.0, maxf(view.y - 96.0, 380.0))
	panel.offset_left = -width * 0.5
	panel.offset_right = width * 0.5
	panel.offset_top = -height * 0.5
	panel.offset_bottom = height * 0.5
	if _grid != null:
		_grid.columns = maxi(int((width - 64.0) / 160.0), 3)


func refresh_cards() -> void:
	if _grid == null or _inventory == null:
		return
	for card in _grid.get_children():
		var recipe: Dictionary = card.get_meta(&"recipe")
		var ready := _recipe_ready(recipe)
		card.modulate = Color.WHITE if ready else Color(0.42, 0.3, 0.3, 0.72)
		card.mouse_filter = Control.MOUSE_FILTER_STOP if ready else Control.MOUSE_FILTER_IGNORE
		var costs: Array = card.get_meta(&"costs")
		for cell in costs:
			var control := cell as Control
			if control == null:
				continue
			var resource_id := str(control.get_meta(&"id"))
			var need := int(control.get_meta(&"need"))
			var have := int(_inventory.call(&"get_amount", resource_id))
			var qty: Label = control.get_meta(&"qty")
			qty.text = "%d/%d" % [have, need]
			var color := Color(0.55, 0.85, 0.5) if have >= need else Color(0.85, 0.4, 0.38)
			qty.add_theme_color_override(&"font_color", color)
	_style_nav()


func rebuild_subs() -> void:
	if _sub_row == null:
		return
	for child in _sub_row.get_children():
		_sub_row.remove_child(child)
		child.free()
	var shown := false
	for sub in HudChrome.SUBS:
		if sub != "All" and _entries(sub).is_empty():
			continue
		var button := Button.new()
		button.set_meta(&"id", sub)
		button.set_meta(&"key", str(HudChrome.SUB_KEYS[sub]))
		button.text = tr(str(HudChrome.SUB_KEYS[sub]))
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_select_sub.bind(sub))
		AudioManager.bind_hover(button)
		_sub_row.add_child(button)
		if sub == _sub:
			shown = true
	if not shown:
		_sub = "All"
	_style_nav()


func rebuild_catalog() -> void:
	if _grid == null:
		return
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.free()
	for recipe in _entries(_sub):
		_grid.add_child(_make_card(recipe))
	_style_nav()
	refresh_cards()


func _select_sub(sub: String) -> void:
	if sub == _sub:
		return
	AudioManager.ui("switch")
	_sub = sub
	rebuild_catalog()


func _entries(sub: String) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for recipe in RECIPES.build_recipes():
		var subcategory := str(recipe.get("subcategory", ""))
		if sub != "All" and subcategory != sub:
			continue
		list.append(recipe)
	return list


func _make_card(recipe: Dictionary) -> PanelContainer:
	var result_id := str(recipe["result_id"])
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(120, 140)
	card.tooltip_text = RECIPES.display_name(result_id)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(_on_card_input.bind(recipe))
	var body := VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_theme_constant_override(&"separation", 4)
	card.add_child(body)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(72, 72)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = HudChrome.item_texture(result_id)
	body.add_child(icon)
	var costs_row := HBoxContainer.new()
	costs_row.alignment = BoxContainer.ALIGNMENT_CENTER
	costs_row.add_theme_constant_override(&"separation", 4)
	costs_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(costs_row)
	var costs: Array = []
	var ingredients: Dictionary = recipe.get("ingredients", {})
	for resource_id in ingredients:
		var cell := _make_cost_cell(str(resource_id), int(ingredients[resource_id]))
		costs_row.add_child(cell)
		costs.append(cell)
	card.set_meta(&"recipe", recipe)
	card.set_meta(&"costs", costs)
	AudioManager.bind_hover(card)
	return card


func _make_cost_cell(resource_id: String, need: int) -> VBoxContainer:
	var cell := VBoxContainer.new()
	cell.alignment = BoxContainer.ALIGNMENT_CENTER
	cell.add_theme_constant_override(&"separation", 0)
	cell.mouse_filter = Control.MOUSE_FILTER_PASS
	cell.tooltip_text = RECIPES.display_name(resource_id)
	cell.set_meta(&"id", resource_id)
	cell.set_meta(&"need", need)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(28, 28)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = HudChrome.item_texture(resource_id)
	cell.add_child(icon)
	var qty := Label.new()
	qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qty.add_theme_font_size_override(&"font_size", 10)
	qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(qty)
	cell.set_meta(&"qty", qty)
	return cell


func _on_card_input(event: InputEvent, recipe: Dictionary) -> void:
	if not event is InputEventMouseButton:
		return
	var button := event as InputEventMouseButton
	if not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if not _recipe_ready(recipe):
		return
	AudioManager.ui("click")
	piece_chosen.emit(str(recipe["result_id"]))


func _recipe_ready(recipe: Dictionary) -> bool:
	var ingredients: Dictionary = recipe.get("ingredients", {})
	if ingredients.is_empty() or _inventory == null:
		return false
	return bool(_inventory.call(&"can_craft", recipe))


func _style_nav() -> void:
	if _sub_row == null:
		return
	for button in _sub_row.get_children():
		HudChrome.paint_tab(button as Button, str((button as Button).get_meta(&"id")) == _sub)
