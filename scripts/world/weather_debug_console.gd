extends Node
class_name WeatherDebugConsole

const COMMANDS: PackedStringArray = [
	"help",
	"weather clear",
	"weather cloudy",
	"weather overcast",
	"weather fog",
	"weather rain",
	"weather storm",
	"time set day",
	"time set night",
	"xray",
	"xray on",
	"xray off",
	"hydro",
	"hydro on",
	"hydro off",
	"hydro stats",
]

signal opened
signal closed
signal notice(text: String, seconds: float)

var is_open := false

var _host: Node
var _console_bar: PanelContainer
var _console_line: LineEdit
var _console_notice: Label
var _suggest_box: VBoxContainer
var _suggest_buttons: Array[Button] = []
var _suggestions: PackedStringArray = PackedStringArray()
var _suggest_index := 0
var _suggest_picked := false
var _suggest_lock := false
var _notice_left := 0.0


func setup(host: Node) -> void:
	_host = host
	_boot_ui()


func _process(delta: float) -> void:
	if _notice_left > 0.0:
		_notice_left = maxf(_notice_left - delta, 0.0)
		if _notice_left == 0.0 and _console_notice != null:
			_console_notice.visible = false


func _input(event: InputEvent) -> void:
	if is_open and event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle_suggestion(-1)
			get_viewport().set_input_as_handled()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_suggestion(1)
			get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if is_open:
		if key.is_action_pressed(&"ui_cancel"):
			close()
			get_viewport().set_input_as_handled()
		elif key.is_action_pressed(&"ui_up"):
			_cycle_suggestion(-1)
			get_viewport().set_input_as_handled()
		elif key.is_action_pressed(&"ui_down"):
			_cycle_suggestion(1)
			get_viewport().set_input_as_handled()
		return
	if key.unicode != "/".unicode_at(0):
		return
	if not _can_open():
		return
	open()
	get_viewport().set_input_as_handled()


func open() -> void:
	is_open = true
	_console_bar.visible = true
	_suggest_picked = false
	_console_line.text = ""
	_refresh_suggestions("")
	var player := _player_node()
	if player != null:
		player.set(&"controls_locked", true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_console_line.call_deferred(&"grab_focus")
	if _host != null:
		_host.set(&"console_open", true)
	opened.emit()


func close() -> void:
	is_open = false
	_suggestions = PackedStringArray()
	if _suggest_box != null:
		_suggest_box.visible = false
	if _console_bar != null:
		_console_bar.visible = false
	if _console_line != null:
		_console_line.release_focus()
	var player := _player_node()
	if player != null:
		player.set(&"controls_locked", false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _host != null:
		_host.set(&"console_open", false)
	closed.emit()


func show_notice(text: String, seconds: float = 4.0) -> void:
	if _console_notice == null:
		return
	_console_notice.text = text
	_console_notice.visible = true
	_notice_left = seconds
	notice.emit(text, seconds)


func _boot_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	root.offset_top = -360.0
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_constant_override(&"margin_left", 16)
	root.add_theme_constant_override(&"margin_right", 16)
	root.add_theme_constant_override(&"margin_bottom", 14)
	layer.add_child(root)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override(&"separation", 6)
	root.add_child(box)
	_console_notice = Label.new()
	_console_notice.visible = false
	_console_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_console_notice.add_theme_font_size_override(&"font_size", 16)
	_console_notice.add_theme_color_override(&"font_color", Color(0.93, 0.96, 0.9))
	_console_notice.add_theme_color_override(&"font_outline_color", Color(0, 0, 0))
	_console_notice.add_theme_constant_override(&"outline_size", 6)
	box.add_child(_console_notice)
	_suggest_box = VBoxContainer.new()
	_suggest_box.visible = false
	_suggest_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_suggest_box.add_theme_constant_override(&"separation", 2)
	box.add_child(_suggest_box)
	_console_bar = PanelContainer.new()
	_console_bar.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.07, 0.94)
	style.set_content_margin_all(8)
	_console_bar.add_theme_stylebox_override(&"panel", style)
	box.add_child(_console_bar)
	_console_line = LineEdit.new()
	_console_line.placeholder_text = "help"
	_console_line.caret_blink = true
	_console_line.text_changed.connect(_on_console_text)
	_console_line.text_submitted.connect(_submit_command)
	_console_line.focus_exited.connect(_refocus_console)
	_console_bar.add_child(_console_line)


func _can_open() -> bool:
	if _host == null or not bool(_host.call(&"_running")):
		return false
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	var player := _player_node()
	return player == null or not bool(player.get(&"controls_locked"))


func _player_node() -> Node:
	if _host != null and _host.has_method(&"_player_node"):
		return _host.call(&"_player_node")
	return get_tree().get_first_node_in_group(&"player")


func _refocus_console() -> void:
	if is_open:
		_refocus_console_later()


func _refocus_console_later() -> void:
	if is_open and _console_line != null:
		_console_line.call_deferred(&"grab_focus")


func _on_console_text(new_text: String) -> void:
	if _suggest_lock:
		return
	_suggest_picked = false
	_refresh_suggestions(new_text)


func _refresh_suggestions(raw: String) -> void:
	var text := raw.strip_edges()
	if text.begins_with("/"):
		text = text.substr(1).strip_edges()
	text = text.to_lower()
	_suggestions = PackedStringArray()
	for command in COMMANDS:
		if text.is_empty() or command.begins_with(text):
			_suggestions.append(command)
	_suggest_index = 0
	_rebuild_suggestions()


func _rebuild_suggestions() -> void:
	for button in _suggest_buttons:
		button.free()
	_suggest_buttons.clear()
	var show := is_open and not _suggestions.is_empty()
	_suggest_box.visible = show
	if not show:
		return
	for i in _suggestions.size():
		var button := Button.new()
		button.text = _suggestions[i]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override(&"font_size", 15)
		button.add_theme_color_override(&"font_color", Color(0.93, 0.96, 0.9))
		button.pressed.connect(_use_suggestion.bind(i))
		_suggest_box.add_child(button)
		_suggest_buttons.append(button)
	_mark_suggestion()


func _mark_suggestion() -> void:
	for i in _suggest_buttons.size():
		var selected := i == _suggest_index
		var style := _suggest_style(selected)
		var button := _suggest_buttons[i]
		button.add_theme_stylebox_override(&"normal", style)
		button.add_theme_stylebox_override(&"hover", style)
		button.add_theme_stylebox_override(&"pressed", _suggest_style(true))


func _suggest_style(selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.22, 0.28, 0.2, 0.96) if selected else Color(0.07, 0.08, 0.09, 0.92)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	return style


func _cycle_suggestion(direction: int) -> void:
	if _suggestions.is_empty():
		return
	if not _suggest_picked:
		_apply_suggestion(0 if direction > 0 else _suggestions.size() - 1)
		return
	_apply_suggestion(_suggest_index + direction)


func _apply_suggestion(index: int) -> void:
	if _suggestions.is_empty():
		return
	_suggest_index = posmod(index, _suggestions.size())
	_suggest_picked = true
	_suggest_lock = true
	_console_line.text = _suggestions[_suggest_index]
	_console_line.caret_column = _console_line.text.length()
	_suggest_lock = false
	_mark_suggestion()


func _use_suggestion(index: int) -> void:
	if index < 0 or index >= _suggestions.size():
		return
	_apply_suggestion(index)
	_submit_command(_console_line.text)


func _submit_command(text: String) -> void:
	close()
	var line := text.strip_edges()
	if line.begins_with("/"):
		line = line.substr(1).strip_edges()
	if line.is_empty() or _host == null:
		return
	if _host.has_method(&"_handle_debug_command"):
		_host.call(&"_handle_debug_command", line)
