extends Node

signal language_changed

const PATH := "user://settings.json"
const LOCALES: PackedStringArray = ["fr", "en"]
const AUDIO_DEFAULTS := {
	"master_volume": 100.0,
	"sfx_volume": 100.0,
	"environment_volume": 80.0,
	"footsteps_volume": 70.0,
	"music_volume": 70.0,
}
const AUDIO_BUSES := {
	"master_volume": "Master",
	"sfx_volume": "SFX",
	"environment_volume": "Environment",
	"footsteps_volume": "Footsteps",
	"music_volume": "Music",
}
const AUDIO_LABELS := {
	"master_volume": "AUDIO_MASTER",
	"sfx_volume": "AUDIO_SFX",
	"environment_volume": "AUDIO_ENVIRONMENT",
	"footsteps_volume": "AUDIO_FOOTSTEPS",
	"music_volume": "AUDIO_MUSIC",
}

var language := "fr"
var audio: Dictionary = {}
var graphics: Dictionary = {}
var controls: Dictionary = {}


func _ready() -> void:
	_register_translations()
	_load()
	_apply_locale()
	apply_volumes()


func set_language(locale: String) -> void:
	if not LOCALES.has(locale) or locale == language:
		return
	language = locale
	_apply_locale()
	_store()
	language_changed.emit()
	AudioManager.ui("select")


func make_language_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 8)
	for locale in LOCALES:
		var button := Button.new()
		button.set_meta(&"locale", locale)
		button.set_meta(&"key", "LANG_FR" if locale == "fr" else "LANG_EN")
		button.text = tr(str(button.get_meta(&"key")))
		button.custom_minimum_size = Vector2(150, 44)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(set_language.bind(locale))
		AudioManager.bind_hover(button)
		row.add_child(button)
	refresh_language_row(row)
	return row


func refresh_language_row(row: Node) -> void:
	if row == null:
		return
	for child in row.get_children():
		if not child.has_meta(&"locale"):
			continue
		var active := str(child.get_meta(&"locale")) == language
		(child as CanvasItem).modulate = Color(1, 0.92, 0.55) if active else Color(0.82, 0.84, 0.86)


func audio_value(key: String) -> float:
	if audio.has(key):
		return clampf(float(audio[key]), 0.0, 100.0)
	return float(AUDIO_DEFAULTS.get(key, 100.0))


func set_audio(key: String, value: float) -> void:
	if not AUDIO_DEFAULTS.has(key):
		return
	audio[key] = clampf(value, 0.0, 100.0)
	_apply_bus(key)
	_store()


func apply_volumes() -> void:
	for key in AUDIO_BUSES:
		_apply_bus(key)


func camera_mode() -> int:
	if graphics.has("camera_mode"):
		return clampi(int(graphics["camera_mode"]), 0, 2)
	return 0 if bool(graphics.get("first_person", false)) else 1


func set_camera_mode(mode: int) -> void:
	mode = clampi(mode, 0, 2)
	if camera_mode() == mode and graphics.has("camera_mode"):
		return
	graphics["camera_mode"] = mode
	if graphics.has("first_person"):
		graphics.erase("first_person")
	_store()


func make_audio_box() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	for key in AUDIO_LABELS:
		box.add_child(_volume_row(str(AUDIO_LABELS[key]), key))
	return box


func _volume_row(label_key: String, setting: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 2)
	var label := Label.new()
	label.set_meta(&"key", label_key)
	label.text = tr(label_key)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = audio_value(setting)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(200, 22)
	slider.focus_mode = Control.FOCUS_ALL
	AudioManager.bind_hover(slider)
	var percent := Label.new()
	percent.custom_minimum_size = Vector2(48, 0)
	percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	percent.text = "%d %%" % int(slider.value)
	slider.value_changed.connect(func(value: float) -> void:
		percent.text = "%d %%" % int(value)
		set_audio(setting, value)
	)
	row.add_child(slider)
	row.add_child(percent)
	box.add_child(row)
	return box


func _apply_bus(key: String) -> void:
	var bus := str(AUDIO_BUSES.get(key, ""))
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, _volume_db(audio_value(key)))


func _volume_db(percent: float) -> float:
	var linear := clampf(percent, 0.0, 100.0) / 100.0
	if linear <= 0.001:
		return -80.0
	return linear_to_db(linear)


func _apply_locale() -> void:
	TranslationServer.set_locale(language)


func _load() -> void:
	if not FileAccess.file_exists(PATH):
		_fill_audio()
		_store()
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fill_audio()
		return
	var saved := str(parsed.get("language", "fr"))
	language = saved if LOCALES.has(saved) else "fr"
	if parsed.get("audio", {}) is Dictionary:
		audio = parsed.get("audio", {})
	if parsed.get("graphics", {}) is Dictionary:
		graphics = parsed.get("graphics", {})
	if parsed.get("controls", {}) is Dictionary:
		controls = parsed.get("controls", {})
	if _fill_audio():
		_store()


func _fill_audio() -> bool:
	var filled := false
	for key in AUDIO_DEFAULTS:
		if audio.has(key):
			audio[key] = clampf(float(audio[key]), 0.0, 100.0)
		else:
			audio[key] = AUDIO_DEFAULTS[key]
			filled = true
	return filled


func _store() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"version": 1,
		"language": language,
		"audio": audio,
		"graphics": graphics,
		"controls": controls,
	}, "\t"))


func _register_translations() -> void:
	var text := FileAccess.get_file_as_string("res://locale/game.csv")
	if text.is_empty():
		return
	var lines := text.split("\n", false)
	if lines.size() < 2:
		return
	var header := lines[0].strip_edges().split(",")
	var tables: Dictionary = {}
	for i in range(1, header.size()):
		var locale := header[i].strip_edges()
		var catalog := Translation.new()
		catalog.locale = locale
		tables[locale] = catalog
	for line_i in range(1, lines.size()):
		var line := lines[line_i].strip_edges()
		if line.is_empty():
			continue
		var cols := line.split(",")
		var key := cols[0].strip_edges()
		for i in range(1, mini(cols.size(), header.size())):
			var locale := header[i].strip_edges()
			if tables.has(locale):
				(tables[locale] as Translation).add_message(key, cols[i].strip_edges())
	for catalog in tables.values():
		TranslationServer.add_translation(catalog)
