extends Control

const WORLD := "res://scenes/world/test_planet.tscn"
const SAVE := preload("res://scripts/core/save_manager.gd")

var _body: VBoxContainer
var _screen := "home"
var _name_edit: LineEdit
var _language_row: HBoxContainer
var _confirm_id := ""
var _delete_all := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SaveManager.clear_runtime()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color(0.05, 0.06, 0.08)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_body = VBoxContainer.new()
	_body.custom_minimum_size = Vector2(440, 0)
	_body.add_theme_constant_override(&"separation", 12)
	center.add_child(_body)
	Settings.language_changed.connect(_on_language)
	_show_home()


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel") or event.is_echo() or _screen == "home":
		return
	_back()
	get_viewport().set_input_as_handled()


func _back() -> void:
	AudioManager.ui("close")
	match _screen:
		"play", "settings":
			_show_home()
		"new", "load":
			_show_play()
		"confirm":
			_show_load()


func _show_home() -> void:
	_screen = "home"
	_clear()
	_body.add_child(_title("MENU_TITLE"))
	_body.add_child(_button("MENU_PLAY", _show_play, "open"))
	_body.add_child(_button("MENU_SETTINGS", _show_settings, "open"))
	_body.add_child(_button("MENU_QUIT", func() -> void: get_tree().quit(), "click"))


func _show_play() -> void:
	_screen = "play"
	_clear()
	_body.add_child(_title("MENU_PLAY"))
	_body.add_child(_button("MENU_NEW_GAME", _show_new, "open"))
	_body.add_child(_button("MENU_LOAD_GAME", _show_load, "open"))
	_body.add_child(_button("MENU_BACK", _show_home, "close"))


func _show_new() -> void:
	_screen = "new"
	_clear()
	_body.add_child(_title("MENU_NEW_GAME"))
	_body.add_child(_label("SAVE_NAME_PROMPT"))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = tr("SAVE_DEFAULT_NAME")
	_name_edit.custom_minimum_size = Vector2(320, 40)
	_name_edit.max_length = 32
	_body.add_child(_name_edit)
	_body.add_child(_button("SAVE_START", _start_new, "click"))
	_body.add_child(_button("MENU_BACK", _show_play, "close"))
	_name_edit.grab_focus()


func _show_load() -> void:
	_screen = "load"
	_confirm_id = ""
	_delete_all = false
	_clear()
	_body.add_child(_title("MENU_LOAD_GAME"))
	var saves := SaveManager.list_games()
	if saves.is_empty():
		_body.add_child(_label("SAVE_EMPTY"))
	else:
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(440, 380)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_body.add_child(scroll)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override(&"separation", 8)
		scroll.add_child(list)
		for save in saves:
			list.add_child(_save_card(save))
		_body.add_child(_button("SAVE_DELETE_ALL", _ask_delete_all, "open"))
	_body.add_child(_button("MENU_BACK", _show_play, "close"))


func _show_settings() -> void:
	_screen = "settings"
	_clear()
	_body.add_child(_title("MENU_SETTINGS"))
	_body.add_child(_label("SETTINGS_LANGUAGE"))
	_language_row = Settings.make_language_row()
	_body.add_child(_language_row)
	_body.add_child(Settings.make_audio_box())
	_body.add_child(_button("MENU_BACK", _show_home, "close"))


func _ask_delete_all() -> void:
	_screen = "confirm"
	_confirm_id = ""
	_delete_all = true
	_clear()
	_body.add_child(_label("SAVE_CONFIRM_ALL"))
	_body.add_child(_value_label("SAVE_CONFIRM_ALL_DETAIL", str(SaveManager.list_games().size())))
	_body.add_child(_button("SAVE_DELETE", _do_delete, "click"))
	_body.add_child(_button("MENU_BACK", _show_load, "close"))


func _ask_delete(save_id: String) -> void:
	_screen = "confirm"
	_delete_all = false
	_confirm_id = save_id
	var save_name := save_id
	for save in SaveManager.list_games():
		if str(save.get("id", "")) == save_id:
			save_name = str(save.get("name", save_id))
			break
	_clear()
	_body.add_child(_label("SAVE_CONFIRM"))
	var who := Label.new()
	who.text = save_name
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(who)
	_body.add_child(_button("SAVE_DELETE", _do_delete, "click"))
	_body.add_child(_button("MENU_BACK", _show_load, "close"))


func _start_new() -> void:
	var save_name := ""
	if _name_edit != null:
		save_name = _name_edit.text.strip_edges()
	if save_name.is_empty():
		save_name = tr("SAVE_DEFAULT_NAME")
	SaveManager.create_game(save_name)
	get_tree().change_scene_to_file(WORLD)


func _play_save(save_id: String) -> void:
	if not SaveManager.activate(save_id):
		return
	get_tree().change_scene_to_file(WORLD)


func _do_delete() -> void:
	if _delete_all:
		SaveManager.delete_all_games()
	else:
		SaveManager.delete_game(_confirm_id)
	_confirm_id = ""
	_delete_all = false
	_show_load()


func _save_card(save: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.13, 0.15)
	style.set_content_margin_all(10)
	style.set_corner_radius_all(4)
	card.add_theme_stylebox_override(&"panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 4)
	card.add_child(box)
	var name_label := Label.new()
	name_label.text = str(save.get("name", ""))
	name_label.add_theme_font_size_override(&"font_size", 18)
	box.add_child(name_label)
	box.add_child(_value_label("SAVE_WHEN", SAVE.format_date(int(save.get("saved_at", 0)))))
	box.add_child(_value_label("SAVE_TIME", SAVE.format_duration(float(save.get("play_time", 0.0)))))
	box.add_child(_value_label("SAVE_SEED", str(int(save.get("seed", 0)))))
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	box.add_child(row)
	var play := _button("SAVE_PLAY", _play_save.bind(str(save.get("id", ""))), "click")
	play.custom_minimum_size = Vector2(140, 36)
	var remove := _button("SAVE_DELETE", _ask_delete.bind(str(save.get("id", ""))), "open")
	remove.custom_minimum_size = Vector2(140, 36)
	row.add_child(play)
	row.add_child(remove)
	return card


func _on_language() -> void:
	_walk(self)
	if _name_edit != null:
		_name_edit.placeholder_text = tr("SAVE_DEFAULT_NAME")
	if _language_row != null:
		Settings.refresh_language_row(_language_row)


func _walk(node: Node) -> void:
	if node.has_meta(&"key") and (node is Label or node is Button):
		var key := str(node.get_meta(&"key"))
		if node.has_meta(&"value"):
			node.set(&"text", tr(key) % str(node.get_meta(&"value")))
		else:
			node.set(&"text", tr(key))
	for child in node.get_children():
		_walk(child)


func _clear() -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_name_edit = null
	_language_row = null


func _title(key: String) -> Label:
	var label := _label(key)
	label.add_theme_font_size_override(&"font_size", 40)
	return label


func _label(key: String) -> Label:
	var label := Label.new()
	label.set_meta(&"key", key)
	label.text = tr(key)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _value_label(key: String, value: String) -> Label:
	var label := Label.new()
	label.set_meta(&"key", key)
	label.set_meta(&"value", value)
	label.text = tr(key) % value
	return label


func _button(key: String, callback: Callable, cue: String = "click") -> Button:
	var button := Button.new()
	button.set_meta(&"key", key)
	button.text = tr(key)
	button.custom_minimum_size = Vector2(320, 48)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void:
		if not cue.is_empty():
			AudioManager.ui(cue)
		callback.call()
	)
	AudioManager.bind_hover(button)
	return button
