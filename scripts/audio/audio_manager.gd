extends Node

const AUDIO := "res://assets/audio"
const STEP_FOLDERS := {
	"grass": "footsteps/grass",
	"dirt": "footsteps/dirt",
	"stone": "footsteps/stone",
	"wood": "footsteps/wood",
	"carpet": "footsteps/carpet",
	"snow": "footsteps/snow",
	"sand": "footsteps/sand",
	"water": "footsteps/water",
}
const SWIM_FOLDER := "actions/swim"
const SONG_FOLDER := "song"
const MUSIC_GAP_MIN := 60.0
const MUSIC_GAP_MAX := 180.0
const TOOL_FOLDERS := {
	"axe": "tools/Axe",
	"pickaxe": "tools/Pickaxe",
	"shovel": "tools/Shovel",
}
const ACTION_FOLDERS := {
	"construct:wood": "actions/construct/wood",
	"construct:stone": "actions/construct/stone",
	"destruct:wood": "actions/destruct/wood",
	"destruct:stone": "actions/destruct/stone",
}
const UI_FILES := {
	"click": "interface/click_001.ogg",
	"open": "interface/open_001.ogg",
	"close": "interface/close_001.ogg",
	"select": "interface/select_002.ogg",
	"switch": "interface/switch_006.ogg",
	"hover": "interface/tick_onhover_002.ogg",
	"drop": "interface/drop_002.ogg",
}
const CUE_FILES := {
	"break_tree": "actions/break/tree/break_tree.ogg",
	"break_rock": "actions/break/rock/break_rock.ogg",
	"pickup": "actions/pickup/item_pickup.ogg",
}
const PICKUP_GAP_MSEC := 600
const PICKUP_PITCH_STEP := 0.06
const PICKUP_PITCH_MAX := 1.35
const AXE_MEDIUM_WEIGHT := 0.8
const THUNDER_KEYS: PackedStringArray = ["small_far", "medium_far", "strong_far", "medium", "strong"]
const WALKABLE: PackedStringArray = ["foundation", "floor", "stairs"]
const ENV_BUS := "Environment"
const PAUSE_EQ_BANDS := [-1.0, -3.0, -7.0, -12.0, -18.0, -24.0]

var _rng := RandomNumberGenerator.new()
var _weather: Node
var _step_clips: Dictionary = {}
var _swim_clips: Array = []
var _songs: Array = []
var _music: AudioStreamPlayer
var _music_gap := 0.0
var _music_waiting := false
var _music_active := false
var _step_last: Dictionary = {}
var _step_players: Array[AudioStreamPlayer] = []
var _step_slot := 0
var _tool_clips: Dictionary = {}
var _axe_medium: Array = []
var _axe_other: Array = []
var _action_clips: Dictionary = {}
var _ui_clips: Dictionary = {}
var _cues: Dictionary = {}
var _sfx_players: Array[AudioStreamPlayer] = []
var _pickup_pitch := 1.0
var _pickup_msec := -10000
var _sfx_slot := 0
var _ui_hover_id := 0
var _thunder: Dictionary = {}
var _thunder_players: Array[AudioStreamPlayer] = []
var _last_thunder := ""
var _last_thunder_cat := ""
var _rain_light: AudioStreamPlayer
var _rain_heavy: AudioStreamPlayer
var _wind_soft: AudioStreamPlayer
var _wind_strong: AudioStreamPlayer
var _rain_light_gain := 0.0
var _rain_heavy_gain := 0.0
var _wind_soft_gain := 0.0
var _wind_strong_gain := 0.0
var _pause_filter := 0.0
var _env_eq: AudioEffectEQ
var _env_eq_slot := -1


func _ready() -> void:
	_rng.randomize()
	_ensure_buses()
	_ensure_pause_eq()
	_load_steps()
	_swim_clips = _load_clips(AUDIO.path_join(SWIM_FOLDER))
	_songs = _load_clips(AUDIO.path_join(SONG_FOLDER))
	_music = _player("Music")
	_music.finished.connect(_on_music_finished)
	_load_tools()
	_load_actions()
	_load_ui()
	_load_cues()
	_load_thunder()
	_step_players = [_player("Footsteps"), _player("Footsteps"), _player("Footsteps"), _player("Footsteps")]
	_sfx_players = [_player("SFX"), _player("SFX"), _player("SFX"), _player("SFX"), _player("SFX"), _player("SFX")]
	_thunder_players = [_player("Environment"), _player("Environment"), _player("Environment")]
	_rain_light = _loop_player("res://assets/audio/weather/rain_light.ogg")
	_rain_heavy = _loop_player("res://assets/audio/weather/rain_heavy.ogg")
	_wind_soft = _loop_player("res://assets/audio/weather/wind_soft.ogg")
	_wind_strong = _loop_player("res://assets/audio/weather/wind_strong.ogg")
	Settings.apply_volumes()


func _process(delta: float) -> void:
	_update_music(delta)
	var target := 1.0 if _paused() else 0.0
	_pause_filter = lerpf(_pause_filter, target, 1.0 - exp(-5.0 * delta))
	_apply_pause_eq()
	var weather := _weather_node()
	var rain := 0.0
	var wind := 0.0
	if weather != null and weather.has_method(&"audio_levels"):
		var levels: Vector3 = weather.call(&"audio_levels")
		rain = clampf(levels.x, 0.0, 1.0)
		wind = clampf(levels.y + levels.z * 0.35, 0.0, 1.0)
	var rain_on := smoothstep(0.03, 0.22, rain)
	var heavy := smoothstep(0.3, 0.75, rain)
	var wind_on := smoothstep(0.08, 0.24, wind)
	var strong := smoothstep(0.4, 0.8, wind)
	var rate := 2.4 if weather == null else 0.85
	var follow := 1.0 - exp(-rate * delta)
	_rain_light_gain = lerpf(_rain_light_gain, rain_on * (1.0 - heavy), follow)
	_rain_heavy_gain = lerpf(_rain_heavy_gain, rain_on * heavy, follow)
	_wind_soft_gain = lerpf(_wind_soft_gain, wind_on * (1.0 - strong), follow)
	_wind_strong_gain = lerpf(_wind_strong_gain, wind_on * strong, follow)
	_apply_loop(_rain_light, _rain_light_gain, -6.0)
	_apply_loop(_rain_heavy, _rain_heavy_gain, -3.0)
	_apply_loop(_wind_soft, _wind_soft_gain, -8.0)
	_apply_loop(_wind_strong, _wind_strong_gain, -4.0)


func footstep(_side: String = "") -> void:
	if _paused():
		return
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if player == null or bool(player.get(&"airborne")) or bool(player.get(&"swimming")):
		return
	var surface := _surface_under(player)
	var clips: Array = _step_clips.get(surface, [])
	var stream := _pick_clip(clips, surface)
	if stream == null:
		return
	var voice := _step_players[_step_slot]
	_step_slot = (_step_slot + 1) % _step_players.size()
	voice.stream = stream
	voice.pitch_scale = _rng.randf_range(0.94, 1.06)
	voice.volume_db = _rng.randf_range(-2.0, 0.8) - 6.0
	voice.play()


func swim_stroke() -> void:
	if _paused():
		return
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if player == null or not bool(player.get(&"swimming")):
		return
	var stream := _pick_clip(_swim_clips, "swim")
	_play_sfx(stream, _rng.randf_range(-1.5, 0.4) - 6.0, true)


func tool_impact(tool_id: String) -> void:
	if _paused():
		return
	var kind := _tool_kind(tool_id)
	if kind.is_empty():
		return
	var stream := _pick_tool(kind)
	_play_sfx(stream, _rng.randf_range(-1.5, 0.6) - 3.0, true)


func build_place(material: String) -> void:
	_play_action("construct", material)


func build_remove(material: String) -> void:
	_play_action("destruct", material)


func break_harvest(required_tool: String) -> void:
	if _paused():
		return
	var cue := ""
	if required_tool == "axe":
		cue = "break_tree"
	elif required_tool == "pickaxe":
		cue = "break_rock"
	else:
		return
	_play_sfx(_cues.get(cue) as AudioStream, -2.0, false)


func item_pickup() -> void:
	if _paused():
		return
	var stream := _cues.get("pickup") as AudioStream
	if stream == null:
		return
	var now := Time.get_ticks_msec()
	if now - _pickup_msec > PICKUP_GAP_MSEC:
		_pickup_pitch = 1.0
	_play_sfx(stream, -4.0, false, _pickup_pitch)
	_pickup_pitch = minf(_pickup_pitch + PICKUP_PITCH_STEP, PICKUP_PITCH_MAX)
	_pickup_msec = now


func ui(cue: String) -> void:
	_play_sfx(_ui_clips.get(cue) as AudioStream, -6.0, false)


func ui_hover(source: Object) -> void:
	if source == null:
		return
	var id := source.get_instance_id()
	if id == _ui_hover_id:
		return
	_ui_hover_id = id
	ui("hover")


func ui_hover_exit(source: Object) -> void:
	if source != null and source.get_instance_id() == _ui_hover_id:
		_ui_hover_id = 0


func bind_hover(control: Control) -> void:
	if control == null or control.has_meta(&"ui_hover"):
		return
	control.set_meta(&"ui_hover", true)
	control.mouse_entered.connect(ui_hover.bind(control))
	control.mouse_exited.connect(ui_hover_exit.bind(control))


func _on_thunder() -> void:
	var cats: PackedStringArray = PackedStringArray()
	for key in THUNDER_KEYS:
		var clips: Array = _thunder.get(key, [])
		if not clips.is_empty():
			cats.append(key)
	if cats.is_empty():
		return
	var pool: PackedStringArray = PackedStringArray()
	for key in cats:
		if key == _last_thunder_cat and cats.size() > 1:
			continue
		pool.append(key)
	if pool.is_empty():
		pool = cats
	var cat := pool[_rng.randi() % pool.size()]
	var choices: Array = []
	for clip in _thunder[cat]:
		var clip_stream := clip as AudioStream
		if clip_stream != null and clip_stream.resource_path != _last_thunder:
			choices.append(clip_stream)
	if choices.is_empty():
		choices = _thunder[cat]
	var stream := choices[_rng.randi() % choices.size()] as AudioStream
	if stream == null:
		return
	_last_thunder = stream.resource_path
	_last_thunder_cat = cat
	var voice := _thunder_players[0]
	for candidate in _thunder_players:
		if not candidate.playing:
			voice = candidate
			break
	voice.stream = stream
	voice.pitch_scale = 1.0
	voice.volume_db = _rng.randf_range(-1.5, 0.5)
	voice.play()


func _surface_under(player: Node3D) -> String:
	var planet := get_tree().get_first_node_in_group(&"planet") as Node3D
	var up := Vector3.UP
	if planet != null:
		up = player.global_position - planet.global_position
		up = Vector3.UP if up.length_squared() < 0.001 else up.normalized()
	var built := _build_surface(player, up)
	if built != "":
		return built
	if planet != null and planet.has_method(&"ground_surface"):
		return str(planet.call(&"ground_surface", player.global_position))
	return "grass"


func _build_surface(player: Node3D, up: Vector3) -> String:
	var body := player as CollisionObject3D
	var world := player.get_world_3d()
	if body == null or world == null:
		return ""
	var from := player.global_position + up * 0.35
	var query := PhysicsRayQueryParameters3D.create(from, player.global_position - up * 1.4, 8, [body.get_rid()])
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return ""
	var collider := hit.collider as Node
	if collider != null and str(collider.get(&"material_id")) != "":
		return str(collider.get(&"material_id"))
	var point: Vector3 = hit.position
	var walk_mat := ""
	var walk_dist := 3.2
	var any_mat := ""
	var any_dist := 3.2
	for node in get_tree().get_nodes_in_group(&"construction"):
		var piece := node as Node3D
		if piece == null:
			continue
		var mat := str(piece.get(&"material_id"))
		if mat == "":
			continue
		var dist := piece.global_position.distance_to(point)
		if WALKABLE.has(str(piece.get(&"kind"))) and dist < walk_dist:
			walk_dist = dist
			walk_mat = mat
		elif dist < any_dist:
			any_dist = dist
			any_mat = mat
	return walk_mat if walk_mat != "" else any_mat


func _load_steps() -> void:
	for material in STEP_FOLDERS:
		_step_clips[material] = _load_clips(AUDIO.path_join(str(STEP_FOLDERS[material])))


func _load_tools() -> void:
	for kind in TOOL_FOLDERS:
		var clips := _load_clips(AUDIO.path_join(str(TOOL_FOLDERS[kind])))
		_tool_clips[kind] = clips
		if str(kind) != "axe":
			continue
		_axe_medium = []
		_axe_other = []
		for clip in clips:
			var stream := clip as AudioStream
			var stem := "" if stream == null else stream.resource_path.get_file().get_basename().to_lower()
			if "medium" in stem:
				_axe_medium.append(clip)
			else:
				_axe_other.append(clip)


func _load_actions() -> void:
	for key in ACTION_FOLDERS:
		_action_clips[key] = _load_clips(AUDIO.path_join(str(ACTION_FOLDERS[key])))


func _load_ui() -> void:
	for cue in UI_FILES:
		var stream := _load_ogg(AUDIO.path_join(str(UI_FILES[cue])))
		if stream != null:
			_ui_clips[cue] = stream


func _load_cues() -> void:
	for cue in CUE_FILES:
		var stream := _load_ogg(AUDIO.path_join(str(CUE_FILES[cue])))
		if stream != null:
			_cues[cue] = stream


func _load_clips(folder: String) -> Array:
	var clips: Array = []
	for path in _ogg_paths(folder):
		var stream := _load_ogg(path)
		if stream != null:
			clips.append(stream)
	return clips


func _load_thunder() -> void:
	for key in THUNDER_KEYS:
		_thunder[key] = []
	for path in _ogg_paths("res://assets/audio/weather/thunder"):
		var stem := path.get_file().get_basename().to_lower()
		for key in THUNDER_KEYS:
			if key in stem:
				var stream := _load_ogg(path)
				if stream != null:
					(_thunder[key] as Array).append(stream)
				break


func _tool_kind(tool_id: String) -> String:
	if tool_id.ends_with("pickaxe"):
		return "pickaxe"
	if tool_id.ends_with("shovel"):
		return "shovel"
	if tool_id.ends_with("hoe") or tool_id.ends_with("rake"):
		return "shovel"
	if tool_id.ends_with("axe"):
		return "axe"
	return ""


func _pick_tool(kind: String) -> AudioStream:
	if kind != "axe":
		var clips: Array = _tool_clips.get(kind, [])
		return _pick_clip(clips, "tool:" + kind)
	var pool: Array = _axe_medium
	var key := "tool:axe:medium"
	if _axe_medium.is_empty():
		pool = _tool_clips.get("axe", [])
		key = "tool:axe"
	elif not _axe_other.is_empty() and _rng.randf() > AXE_MEDIUM_WEIGHT:
		pool = _axe_other
		key = "tool:axe:other"
	return _pick_clip(pool, key)


func _play_action(action: String, material: String) -> void:
	if _paused() or material.is_empty():
		return
	var key := "%s:%s" % [action, material]
	var clips: Array = _action_clips.get(key, [])
	_play_sfx(_pick_clip(clips, key), _rng.randf_range(-1.5, 0.4) - 2.0, true)


func _play_sfx(stream: AudioStream, volume_db: float, vary_pitch: bool, pitch: float = 1.0) -> void:
	if stream == null or _sfx_players.is_empty():
		return
	var voice := _sfx_players[_sfx_slot]
	_sfx_slot = (_sfx_slot + 1) % _sfx_players.size()
	voice.stream = stream
	voice.pitch_scale = _rng.randf_range(0.97, 1.03) if vary_pitch else pitch
	voice.volume_db = volume_db
	voice.play()


func _pick_clip(clips: Array, key: String) -> AudioStream:
	var count := clips.size()
	if count == 0:
		return null
	var last := int(_step_last.get(key, -1))
	var idx := 0
	if last < 0 or count == 1:
		idx = _rng.randi() % count
	else:
		idx = _rng.randi_range(0, count - 2)
		if idx >= last:
			idx += 1
	_step_last[key] = idx
	return clips[idx] as AudioStream


func _ogg_paths(folder: String) -> PackedStringArray:
	var out := PackedStringArray()
	var normalized := folder.replace("\\", "/")
	if normalized.ends_with("/old") or "/old/" in normalized:
		return out
	var dir := DirAccess.open(folder)
	if dir == null:
		return out
	for file_name in dir.get_files():
		var clean := file_name
		if clean.ends_with(".import"):
			clean = clean.trim_suffix(".import")
		elif clean.ends_with(".remap"):
			clean = clean.trim_suffix(".remap")
		if not clean.to_lower().ends_with(".ogg"):
			continue
		var path := folder.path_join(clean)
		if not out.has(path) and ResourceLoader.exists(path):
			out.append(path)
	return out


func _load_ogg(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream


func _loop_player(path: String) -> AudioStreamPlayer:
	var player := _player("Environment")
	var stream := _load_ogg(path)
	if stream is AudioStreamOggVorbis:
		var looped := stream.duplicate() as AudioStreamOggVorbis
		looped.loop = true
		player.stream = looped
	return player


func _player(bus: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus
	add_child(player)
	return player


func _apply_loop(player: AudioStreamPlayer, gain: float, peak_db: float) -> void:
	if player == null or player.stream == null:
		return
	if gain <= 0.001:
		player.volume_db = -80.0
		return
	player.volume_db = linear_to_db(gain) + peak_db
	if not player.playing:
		player.play()


func _weather_node() -> Node:
	if _weather != null and is_instance_valid(_weather):
		return _weather
	_weather = get_tree().get_first_node_in_group(&"weather")
	if _weather != null and _weather.has_signal(&"thunder") and not _weather.thunder.is_connected(_on_thunder):
		_weather.thunder.connect(_on_thunder)
	return _weather


func _paused() -> bool:
	var session := get_tree().get_first_node_in_group(&"world_session")
	return session != null and bool(session.get(&"paused"))


func _update_music(delta: float) -> void:
	if _music == null:
		return
	if not _in_world():
		_music_active = false
		_music_waiting = false
		_music_gap = 0.0
		if _music.playing:
			_music.stop()
		return
	if not _music_active:
		_music_active = true
		_start_song()
		return
	if _music.playing or not _music_waiting:
		return
	_music_gap -= delta
	if _music_gap > 0.0:
		return
	_music_waiting = false
	_start_song()


func _start_song() -> void:
	var stream := _pick_clip(_songs, "music")
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		var once := stream.duplicate() as AudioStreamOggVorbis
		once.loop = false
		stream = once
	_music.stream = stream
	_music.pitch_scale = 1.0
	_music.volume_db = 0.0
	_music.play()


func _on_music_finished() -> void:
	if not _in_world():
		return
	_music_waiting = true
	_music_gap = _rng.randf_range(MUSIC_GAP_MIN, MUSIC_GAP_MAX)


func _in_world() -> bool:
	return get_tree().get_first_node_in_group(&"world_session") != null


func _ensure_buses() -> void:
	_bus("SFX", "Master")
	_bus("Music", "Master")
	_bus("Footsteps", "SFX")
	_bus(ENV_BUS, "SFX")


func _ensure_pause_eq() -> void:
	var idx := AudioServer.get_bus_index(ENV_BUS)
	if idx == -1:
		return
	for i in AudioServer.get_bus_effect_count(idx):
		var fx := AudioServer.get_bus_effect(idx, i)
		if fx is AudioEffectEQ:
			_env_eq = fx as AudioEffectEQ
			_env_eq_slot = i
			return
	_env_eq = AudioEffectEQ.new()
	_env_eq_slot = AudioServer.get_bus_effect_count(idx)
	AudioServer.add_bus_effect(idx, _env_eq)
	AudioServer.set_bus_effect_enabled(idx, _env_eq_slot, false)


func _apply_pause_eq() -> void:
	if _env_eq == null or _env_eq_slot < 0:
		return
	var idx := AudioServer.get_bus_index(ENV_BUS)
	if idx == -1:
		return
	var on := _pause_filter > 0.02
	AudioServer.set_bus_effect_enabled(idx, _env_eq_slot, on)
	if not on:
		return
	for band in PAUSE_EQ_BANDS.size():
		_env_eq.set_band_gain_db(band, PAUSE_EQ_BANDS[band] * _pause_filter)


func _bus(bus_name: String, send: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, send)
