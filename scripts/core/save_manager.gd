extends Node

const VERSION := 1
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const ROOT := "user://saves"

var active: Dictionary = {}
var play_time := 0.0


func has_active() -> bool:
	return not str(active.get("id", "")).is_empty()


func has_player_state() -> bool:
	return has_active() and active.has("player")


func active_seed() -> int:
	return int(active.get("seed", 0))


func state() -> Dictionary:
	return active


func progression() -> Dictionary:
	var value: Variant = active.get("progression", {})
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


func terrain_path() -> String:
	if not has_active():
		return ""
	return "%s/%s/terrain/edits.json" % [ROOT, str(active["id"])]


func clear_runtime() -> void:
	active = {}
	play_time = 0.0


func create_game(save_name: String) -> void:
	var now := int(Time.get_unix_time_from_system())
	var seed_value := randi()
	if seed_value == 0:
		seed_value = 1
	active = {
		"save_version": VERSION,
		"id": "s%d_%d" % [now, randi() % 1000000],
		"name": save_name,
		"seed": seed_value,
		"created_at": now,
		"saved_at": now,
		"play_time": 0.0,
		"progression": {},
	}
	play_time = 0.0
	_write_save(active)


func activate(save_id: String) -> bool:
	var data := _read(save_id)
	if data.is_empty():
		return false
	active = data
	play_time = float(data.get("play_time", 0.0))
	return true


func list_games() -> Array:
	var listed: Array = []
	for folder in DirAccess.get_directories_at(ROOT):
		var data := _read(folder)
		if data.is_empty():
			continue
		listed.append(data)
	listed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("saved_at", 0)) > int(b.get("saved_at", 0))
	)
	return listed


func delete_game(save_id: String) -> void:
	if save_id.is_empty() or save_id.contains("/") or save_id.contains("\\"):
		return
	var folder := ProjectSettings.globalize_path("%s/%s" % [ROOT, save_id])
	var terrain := folder.path_join("terrain")
	DirAccess.remove_absolute(terrain.path_join("edits.json"))
	DirAccess.remove_absolute(terrain)
	DirAccess.remove_absolute(folder.path_join("save.json"))
	DirAccess.remove_absolute(folder)
	if str(active.get("id", "")) == save_id:
		clear_runtime()


func delete_all_games() -> void:
	clear_runtime()
	var root := ProjectSettings.globalize_path(ROOT)
	if not DirAccess.dir_exists_absolute(root):
		return
	for folder in DirAccess.get_directories_at(ROOT):
		delete_game(folder)


func write_state(payload: Dictionary) -> void:
	if not has_active():
		return
	for key in payload:
		active[key] = payload[key]
	active["save_version"] = VERSION
	active["saved_at"] = int(Time.get_unix_time_from_system())
	active["play_time"] = play_time
	_write_save(active)


func write_terrain(blob: Dictionary) -> void:
	var path := terrain_path()
	if path.is_empty():
		return
	_ensure_dir("%s/%s/terrain" % [ROOT, str(active["id"])])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(blob))


static func format_duration(seconds: float) -> String:
	var total := int(maxf(seconds, 0.0))
	var hours := int(float(total) / 3600.0)
	var minutes := int(float(total % 3600) / 60.0)
	if hours > 0:
		return "%dh %02dm" % [hours, minutes]
	return "%dm" % minutes


static func format_date(unix: int) -> String:
	if unix <= 0:
		return "-"
	return Time.get_datetime_string_from_unix_time(unix, true).replace("T", " ")


func _write_save(data: Dictionary) -> void:
	var save_id := str(data.get("id", ""))
	if save_id.is_empty():
		return
	_ensure_dir("%s/%s" % [ROOT, save_id])
	var file := FileAccess.open("%s/%s/save.json" % [ROOT, save_id], FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(data, "\t"))


func _read(save_id: String) -> Dictionary:
	var path := "%s/%s/save.json" % [ROOT, save_id]
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return _normalize(parsed)


func _normalize(data: Dictionary) -> Dictionary:
	var version := int(data.get("save_version", 0))
	if version <= 0 or version > VERSION:
		return {}
	var current := data.duplicate(true)
	while version < VERSION:
		current = _migrate(current, version)
		version += 1
		current["save_version"] = version
	return current


func _migrate(data: Dictionary, _from_version: int) -> Dictionary:
	return data


func _ensure_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
