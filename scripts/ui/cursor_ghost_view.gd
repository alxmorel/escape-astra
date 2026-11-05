extends RefCounted
class_name CursorGhostView

const ICONS := preload("res://scripts/ui/item_icons.gd")
const PREVIEW := preload("res://scripts/ui/build_preview.gd")

var root: Control
var _icon: TextureRect
var _qty: Label


func ensure(host: Node) -> void:
	if root != null:
		return
	var ghost_layer := CanvasLayer.new()
	ghost_layer.name = "CursorGhostLayer"
	ghost_layer.layer = 50
	host.add_child(ghost_layer)
	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.visible = false
	ghost_layer.add_child(root)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(56, 56)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_icon)
	_qty = Label.new()
	_qty.position = Vector2(0, 44)
	_qty.custom_minimum_size = Vector2(72, 18)
	_qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_qty.add_theme_font_size_override(&"font_size", 14)
	_qty.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.98))
	_qty.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 1))
	_qty.add_theme_constant_override(&"outline_size", 5)
	_qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_qty)


func refresh(resource_id: String, shown: int, ui_open: bool) -> void:
	if root == null:
		return
	if resource_id.is_empty() or shown <= 0:
		root.visible = false
		return
	_icon.texture = ICONS.get_texture(resource_id)
	var preview := PREVIEW.texture_for(resource_id)
	if preview != null:
		_icon.texture = preview
	_qty.text = "×%d" % shown
	root.visible = ui_open and shown > 0


func follow_mouse(viewport: Viewport) -> void:
	if root == null or not root.visible:
		return
	root.global_position = viewport.get_mouse_position() + Vector2(12, 12)
