extends RefCounted
class_name BuildHelpView

const RECIPES := preload("res://scripts/resources/recipe_catalog.gd")

var root: VBoxContainer


func ensure(host: Node) -> void:
	if root != null:
		return
	root = VBoxContainer.new()
	root.name = "BuildHelp"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.alignment = BoxContainer.ALIGNMENT_END
	root.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	root.offset_left = -260.0
	root.offset_right = 260.0
	root.offset_top = -300.0
	root.offset_bottom = -78.0
	root.visible = false
	host.add_child(root)


func set_visible(visible: bool) -> void:
	if root != null:
		root.visible = visible


func sync(player: Node, inventory, inventory_open: bool, build_menu_open: bool) -> void:
	if root == null:
		return
	if build_menu_open or inventory_open or player == null:
		root.visible = false
		return
	var demolish := bool(player.get(&"demolish_mode"))
	var piece := str(player.get(&"build_piece"))
	if not demolish and piece.is_empty():
		root.visible = false
		return
	for child in root.get_children():
		root.remove_child(child)
		child.free()
	if not demolish:
		root.add_child(_help_line(RECIPES.display_name(piece)))
		var cost: Dictionary = RECIPES.ingredients_of(piece)
		for resource_id in cost:
			var need := int(cost[resource_id])
			var have := int(inventory.call(&"get_amount", str(resource_id)))
			var color := Color(0.55, 0.85, 0.5) if have >= need else Color(0.85, 0.4, 0.38)
			root.add_child(_help_line("%s  %d / %d" % [RECIPES.display_name(str(resource_id)), have, need], color))
	for action in RECIPES.build_actions(piece, demolish):
		root.add_child(_help_line(RECIPES.build_action_text(action)))
	root.visible = true


func _help_line(text: String, color: Color = Color(1, 1, 1, 0.7)) -> Label:
	var line := Label.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.text = text
	line.add_theme_font_size_override(&"font_size", 14)
	line.add_theme_color_override(&"font_color", color)
	line.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
	line.add_theme_constant_override(&"outline_size", 4)
	return line
