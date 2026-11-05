extends RefCounted
class_name HudVitalsView

var health_label: Label
var hunger_label: Label

var _hp := 100.0
var _hp_max := 100.0
var _hunger := 100.0
var _hunger_max := 100.0


func ensure(host: Node, player: Node) -> void:
	if health_label != null:
		return
	health_label = Label.new()
	health_label.position = Vector2(16, 12)
	health_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_label.add_theme_font_size_override(&"font_size", 20)
	health_label.add_theme_color_override(&"font_color", Color(0.93, 0.95, 0.96))
	health_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 1))
	health_label.add_theme_constant_override(&"outline_size", 6)
	host.add_child(health_label)
	if player.has_signal(&"health_changed"):
		player.connect(&"health_changed", on_health_changed)
	on_health_changed(float(player.get(&"health")), float(player.get(&"max_health")))
	hunger_label = Label.new()
	hunger_label.position = Vector2(16, 40)
	hunger_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hunger_label.add_theme_font_size_override(&"font_size", 20)
	hunger_label.add_theme_color_override(&"font_color", Color(0.95, 0.78, 0.32))
	hunger_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 1))
	hunger_label.add_theme_constant_override(&"outline_size", 6)
	host.add_child(hunger_label)
	if player.has_signal(&"hunger_changed"):
		player.connect(&"hunger_changed", on_hunger_changed)
	on_hunger_changed(float(player.get(&"hunger")), float(player.get(&"max_hunger")))


func set_visible(visible: bool) -> void:
	if health_label != null:
		health_label.visible = visible
	if hunger_label != null:
		hunger_label.visible = visible


func refresh_language() -> void:
	on_health_changed(_hp, _hp_max)
	on_hunger_changed(_hunger, _hunger_max)


func on_health_changed(current: float, maximum: float) -> void:
	_hp = current
	_hp_max = maximum
	if health_label != null:
		health_label.text = TranslationServer.translate("HUD_HP") % [int(round(current)), int(round(maximum))]


func on_hunger_changed(current: float, maximum: float) -> void:
	_hunger = current
	_hunger_max = maximum
	if hunger_label != null:
		hunger_label.text = TranslationServer.translate("HUD_HUNGER") % [int(round(current)), int(round(maximum))]
