extends Control

const PANEL_WIDTH := 420

var _main: VBoxContainer
var _settings: VBoxContainer
var _notice: Label
var _language_row: HBoxContainer
var _title: Label


func _ready() -> void:
	name = "PauseMenu"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	z_index = 30

	var overlay := ColorRect.new()
	overlay.name = "Overlay"
	overlay.color = Color(0.02, 0.03, 0.05, 0.62)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override(&"panel", _panel_style())
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 28)
	margin.add_theme_constant_override(&"margin_right", 28)
	margin.add_theme_constant_override(&"margin_top", 26)
	margin.add_theme_constant_override(&"margin_bottom", 26)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 18)
	margin.add_child(column)

	_title = Label.new()
	_title.set_meta(&"key", "MENU_PAUSE")
	_title.text = tr("MENU_PAUSE")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override(&"font_size", 32)
	_title.add_theme_color_override(&"font_color", Color(0.92, 0.94, 0.96))
	_title.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.65))
	_title.add_theme_constant_override(&"outline_size", 4)
	column.add_child(_title)

	_main = VBoxContainer.new()
	_main.add_theme_constant_override(&"separation", 10)
	column.add_child(_main)
	_main.add_child(_button("MENU_RESUME", close))
	_main.add_child(_button("MENU_SAVE", _save, "click"))
	_main.add_child(_button("MENU_SETTINGS", _show_settings))
	_main.add_child(_button("MENU_QUIT_TO_MENU", _quit, "click"))
	_notice = Label.new()
	_notice.set_meta(&"key", "SAVE_DONE")
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.add_theme_font_size_override(&"font_size", 14)
	_notice.add_theme_color_override(&"font_color", Color(0.55, 0.82, 0.58))
	_notice.visible = false
	_main.add_child(_notice)

	_settings = VBoxContainer.new()
	_settings.visible = false
	_settings.add_theme_constant_override(&"separation", 12)
	column.add_child(_settings)
	var lang := Label.new()
	lang.set_meta(&"key", "SETTINGS_LANGUAGE")
	lang.text = tr("SETTINGS_LANGUAGE")
	lang.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lang.add_theme_font_size_override(&"font_size", 16)
	lang.add_theme_color_override(&"font_color", Color(0.78, 0.81, 0.84))
	_settings.add_child(lang)
	_language_row = Settings.make_language_row()
	_settings.add_child(_language_row)
	_settings.add_child(Settings.make_audio_box())
	_settings.add_child(_button("MENU_BACK", _show_main, "close"))
	Settings.language_changed.connect(_on_language)


func open() -> void:
	_show_main()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_set_paused(true)
	AudioManager.ui("open")


func close() -> void:
	if not visible:
		return
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_paused(false)
	AudioManager.ui("close")


func back() -> void:
	if not visible:
		return
	if _settings.visible:
		_show_main()
		AudioManager.ui("close")
		return
	close()


func _show_main() -> void:
	_main.visible = true
	_settings.visible = false
	_title.set_meta(&"key", "MENU_PAUSE")
	_title.text = tr("MENU_PAUSE")


func _show_settings() -> void:
	AudioManager.ui("open")
	_main.visible = false
	_settings.visible = true
	_title.set_meta(&"key", "MENU_SETTINGS")
	_title.text = tr("MENU_SETTINGS")
	Settings.refresh_language_row(_language_row)


func _save() -> void:
	var session := get_tree().get_first_node_in_group(&"world_session")
	if session != null:
		session.call(&"save_now")
	if not SaveManager.has_active():
		return
	_notice.text = tr("SAVE_DONE")
	_notice.visible = true
	get_tree().create_timer(1.6).timeout.connect(_hide_notice)


func _hide_notice() -> void:
	if is_instance_valid(_notice):
		_notice.visible = false


func _quit() -> void:
	var session := get_tree().get_first_node_in_group(&"world_session")
	if session != null:
		session.call(&"save_and_quit")


func _set_paused(enabled: bool) -> void:
	var session := get_tree().get_first_node_in_group(&"world_session")
	if session != null:
		session.set(&"paused", enabled)
	var player := get_tree().get_first_node_in_group(&"player")
	if player != null:
		player.set(&"controls_locked", enabled)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if enabled else Input.MOUSE_MODE_CAPTURED
	var hud := get_parent()
	if hud != null and hud.has_method(&"set_pause_overlay"):
		hud.call(&"set_pause_overlay", enabled)


func _on_language() -> void:
	_apply_tr(self)
	if _settings.visible:
		_title.set_meta(&"key", "MENU_SETTINGS")
		_title.text = tr("MENU_SETTINGS")
	else:
		_title.set_meta(&"key", "MENU_PAUSE")
		_title.text = tr("MENU_PAUSE")
	Settings.refresh_language_row(_language_row)


func _apply_tr(node: Node) -> void:
	if node.has_meta(&"key") and (node is Label or node is Button):
		node.set(&"text", tr(str(node.get_meta(&"key"))))
	for child in node.get_children():
		_apply_tr(child)


func _button(key: String, callback: Callable, cue: String = "") -> Button:
	var button := Button.new()
	button.set_meta(&"key", key)
	button.text = tr(key)
	button.custom_minimum_size = Vector2(PANEL_WIDTH - 56, 46)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override(&"font_size", 17)
	button.add_theme_color_override(&"font_color", Color(0.9, 0.92, 0.94))
	button.add_theme_color_override(&"font_hover_color", Color(1, 1, 1))
	button.add_theme_color_override(&"font_pressed_color", Color(0.82, 0.84, 0.86))
	button.add_theme_color_override(&"font_focus_color", Color(1, 1, 1))
	button.add_theme_stylebox_override(&"normal", _button_style(Color(0.14, 0.15, 0.17), Color(0.28, 0.3, 0.33)))
	button.add_theme_stylebox_override(&"hover", _button_style(Color(0.2, 0.22, 0.25), Color(0.42, 0.55, 0.62)))
	button.add_theme_stylebox_override(&"pressed", _button_style(Color(0.11, 0.12, 0.14), Color(0.34, 0.36, 0.4)))
	button.add_theme_stylebox_override(&"focus", _button_style(Color(0.18, 0.2, 0.23), Color(0.55, 0.72, 0.78), 2))
	button.pressed.connect(func() -> void:
		if not cue.is_empty():
			AudioManager.ui(cue)
		callback.call()
	)
	AudioManager.bind_hover(button)
	return button


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.1, 0.9)
	style.border_color = Color(0.26, 0.28, 0.32)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, 4)
	return style


func _button_style(bg: Color, border: Color, border_width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(6)
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.content_margin_left = 12
	style.content_margin_right = 12
	return style
