extends RefCounted
class_name CraftCatalogView

signal changed

const RECIPES := preload("res://scripts/resources/recipe_catalog.gd")
const HudChrome := preload("res://scripts/ui/hud_chrome.gd")

var grid: GridContainer

var _host: Node
var _tab_row: HBoxContainer
var _sub_row: HBoxContainer
var _tab := ""
var _sub := "All"
var _inventory
var _cursor
var _pending


func mount(parent: Control, host: Node) -> void:
	if grid != null:
		return
	_host = host
	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override(&"separation", 4)
	parent.add_child(_tab_row)
	_sub_row = HBoxContainer.new()
	_sub_row.add_theme_constant_override(&"separation", 4)
	parent.add_child(_sub_row)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	parent.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override(&"h_separation", 8)
	grid.add_theme_constant_override(&"v_separation", 8)
	scroll.add_child(grid)
	_build_nav()
	rebuild()


func bind(inventory, cursor, pending) -> void:
	_inventory = inventory
	_cursor = cursor
	_pending = pending


func set_columns(count: int) -> void:
	if grid != null:
		grid.columns = count


func refresh_cards() -> void:
	if grid == null or _inventory == null:
		return
	for card in grid.get_children():
		var badge: Label = card.get_meta(&"badge")
		var recipe: Dictionary = card.get_meta(&"recipe")
		var limit := _craft_limit(recipe)
		var per_craft := maxi(int(recipe.get("result_amount", 1)), 1)
		badge.text = "x%d" % per_craft
		badge.add_theme_color_override(&"font_color", Color(0.55, 0.85, 0.5) if limit > 0 else Color(0.85, 0.4, 0.38))
		card.add_theme_stylebox_override(&"panel", HudChrome.window_style(Color(0.14, 0.15, 0.16)))
		card.modulate = Color(0.42, 0.3, 0.3, 0.72) if limit <= 0 else Color.WHITE
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


func rebuild() -> void:
	if grid == null:
		return
	for child in grid.get_children():
		grid.remove_child(child)
		child.free()
	var recipes := _recipes_for(_tab, _sub if _tab == "Construction" else "All")
	for recipe in recipes:
		grid.add_child(_make_card(recipe))
	_style_nav()
	refresh_cards()


func _build_nav() -> void:
	for tab in HudChrome.TABS:
		if _recipes_for(tab, "All").is_empty():
			continue
		var button := Button.new()
		button.set_meta(&"id", tab)
		button.set_meta(&"key", str(HudChrome.TAB_KEYS[tab]))
		button.text = TranslationServer.translate(str(HudChrome.TAB_KEYS[tab]))
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_select_tab.bind(tab))
		AudioManager.bind_hover(button)
		_tab_row.add_child(button)
	if _tab.is_empty() or _recipes_for(_tab, "All").is_empty():
		_tab = str((_tab_row.get_child(0) as Button).get_meta(&"id")) if _tab_row.get_child_count() > 0 else ""
	_rebuild_subs()


func _select_tab(tab: String) -> void:
	if tab == _tab:
		return
	AudioManager.ui("switch")
	_tab = tab
	if tab != "Construction":
		_sub = "All"
	_rebuild_subs()
	rebuild()


func _select_sub(sub: String) -> void:
	if sub == _sub:
		return
	AudioManager.ui("switch")
	_sub = sub
	rebuild()


func _rebuild_subs() -> void:
	for child in _sub_row.get_children():
		_sub_row.remove_child(child)
		child.free()
	_sub_row.visible = _tab == "Construction"
	if _tab != "Construction":
		return
	var shown := false
	for sub in HudChrome.SUBS:
		if sub != "All" and _recipes_for("Construction", sub).is_empty():
			continue
		var button := Button.new()
		button.set_meta(&"id", sub)
		button.set_meta(&"key", str(HudChrome.SUB_KEYS[sub]))
		button.text = TranslationServer.translate(str(HudChrome.SUB_KEYS[sub]))
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_select_sub.bind(sub))
		AudioManager.bind_hover(button)
		_sub_row.add_child(button)
		if sub == _sub:
			shown = true
	if not shown:
		_sub = "All"


func _make_card(recipe: Dictionary) -> PanelContainer:
	var result_id := str(recipe["result_id"])
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(120, 140)
	card.tooltip_text = RECIPES.tooltip_text(result_id)
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
	var badge := Label.new()
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override(&"font_size", 12)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(badge)
	card.set_meta(&"badge", badge)
	card.set_meta(&"costs", costs)
	card.set_meta(&"result_id", result_id)
	card.set_meta(&"recipe", recipe)
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
	if _craft_limit(recipe) <= 0:
		return
	if button.shift_pressed:
		if int(_inventory.call(&"craft_max_into_slots", recipe)) > 0:
			AudioManager.ui("click")
		changed.emit()
		_handle_input()
		return
	var result_id := str(recipe["result_id"])
	var crafted_qty := int(recipe["result_amount"])
	if not _cursor.is_empty() and _cursor.resource_id != result_id:
		return
	if _cursor.space_left() < crafted_qty:
		return
	var ingredients: Dictionary = recipe.get("ingredients", {})
	var stack: Dictionary = _inventory.call(&"try_craft_once", recipe)
	var crafted_id := str(stack["id"])
	var crafted_count := int(stack["count"])
	if crafted_id.is_empty() or crafted_count <= 0:
		return
	_pending.push(crafted_id, crafted_count, ingredients)
	var crafted_dur := int(stack.get("durability", -1))
	var overflow: int = _cursor.add(crafted_id, crafted_count, crafted_dur)
	if overflow > 0:
		_inventory.call(&"add_resource", crafted_id, overflow, crafted_dur)
		_pending.validate_deposited(crafted_id, overflow)
	AudioManager.ui("click")
	changed.emit()
	_handle_input()


func _handle_input() -> void:
	if _host != null:
		_host.get_viewport().set_input_as_handled()


func _craft_limit(recipe: Dictionary) -> int:
	return int(_inventory.call(&"max_craft_times", recipe))


func _recipes_for(tab: String, sub: String) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for recipe in RECIPES.all_recipes():
		if _matches(recipe, tab, sub):
			list.append(recipe)
	return list


func _matches(recipe: Dictionary, tab: String, sub: String) -> bool:
	var category := str(recipe.get("category", "Resources"))
	var subcategory := str(recipe.get("subcategory", ""))
	if tab == "Storage":
		return category == "Storage" or subcategory == "Storage"
	if tab == "Construction":
		var construction := category == "Construction" or subcategory == "Storage"
		if not construction:
			return false
		if sub == "All" or sub.is_empty():
			return true
		return subcategory == sub
	return category == tab


func _style_nav() -> void:
	for button in _tab_row.get_children():
		HudChrome.paint_tab(button as Button, str((button as Button).get_meta(&"id")) == _tab)
	for button in _sub_row.get_children():
		HudChrome.paint_tab(button as Button, str((button as Button).get_meta(&"id")) == _sub)
