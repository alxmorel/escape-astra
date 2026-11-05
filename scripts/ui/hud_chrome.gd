extends RefCounted
class_name HudChrome

const ICONS := preload("res://scripts/ui/item_icons.gd")
const PREVIEW := preload("res://scripts/ui/build_preview.gd")

const TABS: PackedStringArray = ["Resources", "Tools", "Construction", "Machines", "Storage"]
const TAB_KEYS := {
	"Resources": "TAB_RESOURCES",
	"Tools": "TAB_TOOLS",
	"Construction": "TAB_CONSTRUCTION",
	"Machines": "TAB_MACHINES",
	"Storage": "TAB_STORAGE",
}
const SUBS: PackedStringArray = ["All", "Foundations", "Walls", "Floors", "Stairs", "Openings", "Storage"]
const SUB_KEYS := {
	"All": "SUB_ALL",
	"Foundations": "SUB_FOUNDATIONS",
	"Walls": "SUB_WALLS",
	"Floors": "SUB_FLOORS",
	"Stairs": "SUB_STAIRS",
	"Openings": "SUB_OPENINGS",
	"Storage": "SUB_STORAGE",
}


static func paint_tab(button: Button, active: bool) -> void:
	if button == null:
		return
	button.modulate = Color(1, 0.92, 0.55) if active else Color(0.82, 0.84, 0.86)


static func section_title(key: String) -> Label:
	var label := Label.new()
	label.set_meta(&"key", key)
	label.text = TranslationServer.translate(key)
	label.add_theme_font_size_override(&"font_size", 16)
	label.add_theme_color_override(&"font_color", Color(0.82, 0.84, 0.86))
	return label


static func window_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_border_width_all(1)
	style.border_color = Color(0.24, 0.25, 0.27)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	return style


static func item_texture(resource_id: String) -> Texture2D:
	var preview := PREVIEW.texture_for(resource_id)
	if preview != null:
		return preview
	return ICONS.get_texture(resource_id)
