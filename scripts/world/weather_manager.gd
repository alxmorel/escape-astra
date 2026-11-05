extends Node3D

enum Weather { CLEAR, CLOUDY, OVERCAST, FOG, RAIN, STORM }

# Poids de transition. CLEAR ne peut pas sauter directement à STORM.
const TRANSITIONS: Array = [
	[[Weather.CLOUDY, 75], [Weather.FOG, 25]],
	[[Weather.CLEAR, 40], [Weather.OVERCAST, 45], [Weather.FOG, 15]],
	[[Weather.CLOUDY, 25], [Weather.RAIN, 55], [Weather.FOG, 20]],
	[[Weather.CLEAR, 28], [Weather.CLOUDY, 47], [Weather.OVERCAST, 25]],
	[[Weather.OVERCAST, 62], [Weather.STORM, 38]],
	[[Weather.RAIN, 70], [Weather.OVERCAST, 30]],
]

const NAMES: PackedStringArray = ["CLEAR", "CLOUDY", "OVERCAST", "FOG", "RAIN", "STORM"]
# Ancien fog de la météo FOG : atmosphère permanente (depth, début 9, fin 34).
const base_fog := {
	"begin": 9.0,
	"end": 34.0,
	"curve": 1.25,
	"energy": 0.95,
	"aerial": 0.4,
	"sky_affect": 0.5,
}
const KEYS: PackedStringArray = [
	"cloud_coverage",
	"cloud_density",
	"weather_fog_multiplier",
	"rain_intensity",
	"ambient_light_multiplier",
	"sun_light_multiplier",
	"sky_brightness",
	"storm_intensity",
]
const CLOUD_COUNT := 96
const CLOUD_DRIFT_MIN := 0.14
const CLOUD_DRIFT_MAX := 6.6
const BUILD_MASK := 8
const TERRAIN := preload("res://scripts/terrain/terrain_volume.gd")
const WeatherDebugConsole := preload("res://scripts/world/weather_debug_console.gd")
const WeatherProfiles := preload("res://scripts/world/weather_profiles.gd")
const DEBUG_TRANSITION := 12.0

signal thunder

@export var weather_min_duration: float = 120.0
@export var weather_max_duration: float = 420.0
@export var transition_min: float = 30.0
@export var transition_max: float = 90.0

var player_exposed_to_rain := false
var console_open := false
var wind_direction := Vector3(1.0, 0.0, 0.0)

var _rng := RandomNumberGenerator.new()
var _planet: Node3D
var _player: Node3D
var _flora: Node
var _env: Environment
var _current_id := Weather.CLEAR
var _target_id := Weather.CLEAR
var _from: Dictionary = {}
var _current: Dictionary = {}
var _target: Dictionary = {}
var _transition_u := 1.0
var _transition_span := 45.0
var _hold_left := 180.0
var _wind_yaw := 0.0
var _wind_yaw_target := 0.0
var _wind_intensity := 0.0
var _wind_intensity_target := 0.0
var _wind_gust_amp := 0.0
var _wind_gust_target := 0.0
var _wind_hold := 120.0
var _time := 0.0
var _gust := 0.0
var _applied_wind := 0.0
var _flash := 0.0
var _flash_hold := 0.0
var _lightning_in := 16.0
var _sheltered := false
var _shelter_hold := 0.0
var _chunk_reach := -1.0
var _rain_aligned := false
var _rain_up := Vector3.UP
var _rain_tangent := Vector3.RIGHT
var _cloud_noise := FastNoiseLite.new()
var _clouds: MultiMeshInstance3D
var _multi: MultiMesh
var _cloud_mat: ShaderMaterial
var _dirs := PackedVector3Array()
var _alt := PackedFloat32Array()
var _bulk := PackedFloat32Array()
var _yaw := PackedFloat32Array()
var _rank := PackedFloat32Array()
var _rain: GPUParticles3D
var _rain_mat: ParticleProcessMaterial
var _drop_mat: StandardMaterial3D
var _debug_console: WeatherDebugConsole


func _ready() -> void:
	process_priority = 10
	add_to_group(&"weather")
	_bind_world()
	_boot_state()
	_boot_clouds()
	_boot_rain()
	_debug_console = WeatherDebugConsole.new()
	add_child(_debug_console)
	_debug_console.setup(self)


func _process(delta: float) -> void:
	var step := delta if _running() else 0.0
	if step > 0.0:
		_simulate(step)
	_apply_wind()
	_apply_clouds(step)
	_apply_fog()
	_apply_rain(step)


func lighting_modifiers() -> Dictionary:
	return {
		"sun": float(_current.get("sun_light_multiplier", 1.0)),
		"ambient": float(_current.get("ambient_light_multiplier", 1.0)),
		"sky": float(_current.get("sky_brightness", 1.0)),
		"flash": _flash,
	}


func audio_levels() -> Vector3:
	return Vector3(
		float(_current.get("rain_intensity", 0.0)),
		clampf(_wind_intensity, 0.0, 1.0),
		clampf(_gust, 0.0, 1.0)
	)


func debug_lines() -> String:
	return "Weather: %s -> %s\nTransition: %d%%\nRain: %.2f\nClouds: %.2f\nFog: %.2f\nWind: %.2f\nNext weather: %ds\nCommande: / help" % [
		NAMES[_current_id],
		NAMES[_target_id],
		int(round(_transition_u * 100.0)),
		float(_current.get("rain_intensity", 0.0)),
		float(_current.get("cloud_coverage", 0.0)),
		float(_current.get("weather_fog_multiplier", 1.0)),
		_applied_wind,
		int(maxf(_hold_left, 0.0)),
	]


func export_state() -> Dictionary:
	return {
		"current": NAMES[_current_id],
		"target": NAMES[_target_id],
		"transition": _transition_u,
		"transition_span": _transition_span,
		"hold_left": _hold_left,
		"seed": _rng.seed,
		"rng_state": str(_rng.state),
		"wind_yaw": _wind_yaw,
		"wind_yaw_target": _wind_yaw_target,
		"wind_intensity": _wind_intensity,
		"wind_intensity_target": _wind_intensity_target,
		"wind_gust": _wind_gust_amp,
		"wind_gust_target": _wind_gust_target,
		"wind_hold": _wind_hold,
		"clock": _time,
		"lightning_in": _lightning_in,
		"values": _current.duplicate(),
		"from": _from.duplicate(),
		"cloud_dirs": _export_dirs(),
	}


func import_state(data: Dictionary) -> void:
	if data.is_empty():
		return
	_current_id = _id_of(str(data.get("current", "CLEAR")))
	_target_id = _id_of(str(data.get("target", "CLEAR")))
	_transition_u = clampf(float(data.get("transition", 1.0)), 0.0, 1.0)
	_transition_span = maxf(float(data.get("transition_span", 45.0)), 0.05)
	_hold_left = maxf(float(data.get("hold_left", weather_min_duration)), 0.0)
	_wind_yaw = float(data.get("wind_yaw", _wind_yaw))
	_wind_yaw_target = float(data.get("wind_yaw_target", _wind_yaw))
	if data.has("wind_intensity"):
		_wind_intensity = clampf(float(data["wind_intensity"]), 0.0, 1.0)
		_wind_intensity_target = clampf(float(data.get("wind_intensity_target", _wind_intensity)), 0.0, 1.0)
		_wind_gust_amp = clampf(float(data.get("wind_gust", 0.0)), 0.0, 1.0)
		_wind_gust_target = clampf(float(data.get("wind_gust_target", _wind_gust_amp)), 0.0, 1.0)
		_wind_hold = maxf(float(data.get("wind_hold", 90.0)), 0.0)
	_time = float(data.get("clock", 0.0))
	_lightning_in = maxf(float(data.get("lightning_in", 12.0)), 0.0)
	if data.has("seed"):
		_rng.seed = int(data["seed"])
	if data.has("rng_state"):
		_rng.state = int(str(data["rng_state"]))
	_target = _profile(_target_id)
	var values: Variant = data.get("values", {})
	var source: Variant = data.get("from", {})
	_current = _sanitize(values if values is Dictionary else {})
	_from = _sanitize(source if source is Dictionary else _current)
	if not (source is Dictionary) or (source as Dictionary).is_empty():
		_from = _current.duplicate()
	_import_dirs(data.get("cloud_dirs", []))
	_update_wind_vector()
	_update_gust()
	_flash = 0.0


func _bind_world() -> void:
	var world := get_parent().get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	if world != null:
		_env = world.environment
	_planet = get_tree().get_first_node_in_group(&"planet") as Node3D


func _boot_state() -> void:
	var seed_value := SaveManager.active_seed()
	if seed_value == 0:
		seed_value = 1
	_rng.seed = seed_value
	_current_id = Weather.CLEAR
	_target_id = Weather.CLEAR
	_current = _profile(Weather.CLEAR)
	_from = _current.duplicate()
	_target = _current.duplicate()
	_transition_u = 1.0
	_transition_span = _rng.randf_range(transition_min, transition_max)
	_hold_left = _rng.randf_range(weather_min_duration, weather_max_duration)
	_wind_yaw = _rng.randf() * TAU
	_wind_yaw_target = _wind_yaw
	_lightning_in = _rng.randf_range(14.0, 28.0)
	_roll_wind(true)


func _boot_clouds() -> void:
	var seed_value := SaveManager.active_seed()
	if seed_value == 0:
		seed_value = 1
	var layout := RandomNumberGenerator.new()
	layout.seed = seed_value + 91
	_cloud_noise.seed = seed_value + 17
	_cloud_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_cloud_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_cloud_noise.fractal_octaves = 2
	_cloud_noise.frequency = 1.15
	_dirs.resize(CLOUD_COUNT)
	_alt.resize(CLOUD_COUNT)
	_bulk.resize(CLOUD_COUNT)
	_yaw.resize(CLOUD_COUNT)
	_rank.resize(CLOUD_COUNT)
	for i in CLOUD_COUNT:
		_dirs[i] = _fibonacci(i, CLOUD_COUNT)
		_alt[i] = layout.randf_range(10.0, 15.0)
		_bulk[i] = layout.randf()
		_yaw[i] = layout.randf() * TAU
		_rank[i] = (float(i) + 0.5) / float(CLOUD_COUNT)
	_cloud_mat = ShaderMaterial.new()
	_cloud_mat.shader = preload("res://shaders/cloud.gdshader")
	var mesh := WeatherProfiles.cloud_mesh()
	mesh.surface_set_material(0, _cloud_mat)
	_multi = MultiMesh.new()
	_multi.transform_format = MultiMesh.TRANSFORM_3D
	_multi.use_colors = true
	_multi.mesh = mesh
	_multi.instance_count = CLOUD_COUNT
	_clouds = MultiMeshInstance3D.new()
	_clouds.name = "Clouds"
	_clouds.multimesh = _multi
	_clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_clouds.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_clouds.custom_aabb = AABB(Vector3(-90.0, -90.0, -90.0), Vector3(180.0, 180.0, 180.0))
	_clouds.extra_cull_margin = 16.0
	_clouds.visible = false
	add_child(_clouds)
	_clouds.top_level = true


func _boot_rain() -> void:
	_rain_mat = ParticleProcessMaterial.new()
	_rain_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_rain_mat.emission_box_extents = Vector3(13.0, 4.2, 13.0)
	_rain_mat.emission_shape_offset = Vector3.ZERO
	_rain_mat.direction = Vector3(0.0, -1.0, 0.0)
	_rain_mat.spread = 2.0
	_rain_mat.initial_velocity_min = 8.0
	_rain_mat.initial_velocity_max = 12.0
	_rain_mat.gravity = Vector3(0.0, -10.0, 0.0)
	_rain_mat.scale_min = 0.75
	_rain_mat.scale_max = 1.2
	_rain_mat.particle_flag_align_y = true
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.8, 0.88, 0.95, 0.0))
	gradient.set_color(1, Color(0.72, 0.8, 0.9, 0.0))
	gradient.add_point(0.12, Color(0.8, 0.88, 0.95, 0.62))
	gradient.add_point(0.72, Color(0.74, 0.82, 0.9, 0.48))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	_rain_mat.color_ramp = ramp
	var drop := BoxMesh.new()
	drop.size = Vector3(0.028, 0.62, 0.028)
	_drop_mat = StandardMaterial3D.new()
	_drop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_drop_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_drop_mat.albedo_color = Color(0.78, 0.86, 0.95, 0.72)
	drop.material = _drop_mat
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = 1600
	_rain.lifetime = 0.95
	_rain.explosiveness = 0.0
	_rain.randomness = 0.35
	_rain.visibility_aabb = AABB(Vector3(-24.0, -28.0, -24.0), Vector3(48.0, 52.0, 48.0))
	_rain.local_coords = false
	_rain.emitting = false
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_rain.process_material = _rain_mat
	_rain.draw_pass_1 = drop
	add_child(_rain)
	_rain.top_level = true


func _handle_debug_command(line: String) -> void:
	var parts := line.split(" ", false)
	var cmd := str(parts[0]).to_lower()
	if cmd == "help":
		_show_notice(
			"help\nweather <clear|cloudy|overcast|fog|rain|storm>\ntime set <day|night>\nxray [on|off]\nhydro [on|off|stats]",
			8.0
		)
		return
	if cmd == "weather":
		if parts.size() < 2:
			_show_notice("Usage : weather storm")
			return
		var weather_name := str(parts[1]).to_upper()
		if NAMES.find(weather_name) < 0:
			_show_notice("Météo inconnue")
			return
		_force(_id_of(weather_name))
		_show_notice("Météo : %s" % weather_name)
		return
	if cmd == "time":
		var phase := ""
		if parts.size() >= 3 and str(parts[1]).to_lower() == "set":
			phase = str(parts[2]).to_lower()
		if phase != "day" and phase != "night":
			_show_notice("Usage : time set day")
			return
		_set_phase(phase)
		return
	if cmd == "xray":
		_handle_xray(parts)
		return
	if cmd == "hydro":
		_handle_hydro(parts)
		return
	_show_notice("Commande inconnue")


func _handle_xray(parts: PackedStringArray) -> void:
	var planet := get_tree().get_first_node_in_group(&"planet")
	if planet == null or not planet.has_method(&"toggle_xray"):
		_show_notice("Planète introuvable")
		return
	var enabled := false
	if parts.size() >= 2:
		var mode := str(parts[1]).to_lower()
		if mode != "on" and mode != "off":
			_show_notice("Usage : xray [on|off]")
			return
		enabled = bool(planet.call(&"set_xray", mode == "on"))
	else:
		enabled = bool(planet.call(&"toggle_xray"))
	_show_notice("Vision X : %s" % ("ON" if enabled else "OFF"))


func _handle_hydro(parts: PackedStringArray) -> void:
	var planet := get_tree().get_first_node_in_group(&"planet")
	if planet == null or not planet.has_method(&"toggle_hydro_debug"):
		_show_notice("Planète introuvable")
		return
	if parts.size() >= 2 and str(parts[1]).to_lower() == "stats":
		if planet.has_method(&"hydro_metrics"):
			var m: Dictionary = planet.call(&"hydro_metrics")
			_show_notice(str(m.get("report", "hydro stats")), 10.0)
		else:
			_show_notice("Métriques hydro indisponibles")
		return
	var enabled := false
	if parts.size() >= 2:
		var mode := str(parts[1]).to_lower()
		if mode != "on" and mode != "off":
			_show_notice("Usage : hydro [on|off|stats]")
			return
		enabled = bool(planet.call(&"set_hydro_debug", mode == "on"))
	else:
		enabled = bool(planet.call(&"toggle_hydro_debug"))
	var extra := ""
	if planet.has_method(&"hydro_metrics"):
		var m2: Dictionary = planet.call(&"hydro_metrics")
		var after: Dictionary = m2.get("after", {})
		extra = " — s=%d r=%d lakes=%d" % [
			int(after.get("streams", 0)),
			int(after.get("rivers", 0)),
			int(after.get("lakes", 0)),
		]
	_show_notice("Hydro debug : %s%s" % ["ON" if enabled else "OFF", extra])


func _set_phase(phase: String) -> void:
	var sky := get_parent().get_node_or_null(^"SkySystem")
	if sky == null or not sky.has_method(&"import_time"):
		_show_notice("Cycle introuvable")
		return
	var moment := 0.0
	if phase == "night":
		moment = float(sky.get(&"day_duration"))
	sky.call(&"import_time", moment)
	_show_notice("Temps : %s" % ("jour" if phase == "day" else "nuit"))


func _show_notice(text: String, seconds: float = 4.0) -> void:
	if _debug_console != null:
		_debug_console.show_notice(text, seconds)


func _running() -> bool:
	var session := get_tree().get_first_node_in_group(&"world_session")
	return session == null or not bool(session.get(&"paused"))


func _simulate(delta: float) -> void:
	_time += delta
	_advance_wind(delta)
	if _transition_u < 1.0:
		_transition_u = minf(1.0, _transition_u + delta / maxf(_transition_span, 0.05))
	if _transition_u >= 1.0:
		_current_id = _target_id
	_blend()
	_hold_left -= delta
	if _hold_left <= 0.0:
		_begin_next()
	_update_lightning(delta)


func _begin_next() -> void:
	_current_id = _target_id
	_from = _current.duplicate()
	_target_id = _pick_next(_current_id)
	_target = _profile(_target_id)
	_transition_u = 0.0
	_transition_span = _rng.randf_range(transition_min, transition_max)
	_hold_left = _rng.randf_range(weather_min_duration, weather_max_duration)


func _force(id: int) -> void:
	if id == _current_id and id == _target_id and _transition_u >= 1.0:
		_hold_left = weather_max_duration
		return
	_from = _current.duplicate()
	_target_id = id
	_target = _profile(id)
	_transition_u = 0.0
	_transition_span = DEBUG_TRANSITION
	_hold_left = weather_max_duration


func _blend() -> void:
	var k := smoothstep(0.0, 1.0, _transition_u)
	for key in KEYS:
		_current[key] = lerpf(float(_from[key]), float(_target[key]), k)


func _advance_wind(delta: float) -> void:
	_wind_hold -= delta
	if _wind_hold <= 0.0:
		_roll_wind(false)
	var follow := 1.0 - exp(-delta * 0.05)
	_wind_intensity = lerpf(_wind_intensity, _wind_intensity_target, follow)
	_wind_gust_amp = lerpf(_wind_gust_amp, _wind_gust_target, follow)
	_wind_yaw_target += delta * lerpf(0.0015, 0.008, _wind_intensity)
	_wind_yaw = lerp_angle(_wind_yaw, _wind_yaw_target, 1.0 - exp(-delta * 0.08))
	_update_wind_vector()
	_update_gust()


func _roll_wind(snap: bool) -> void:
	var sample := WeatherProfiles.wind_sample(_rng, _current_id)
	_wind_intensity_target = sample["intensity"]
	_wind_gust_target = sample["gust"]
	_wind_hold = sample["hold"]
	if snap:
		_wind_intensity = _wind_intensity_target
		_wind_gust_amp = _wind_gust_target
		_wind_yaw_target = _wind_yaw
	else:
		_wind_yaw_target = _wind_yaw + sample["turn"]
	_update_wind_vector()
	_update_gust()


func _update_wind_vector() -> void:
	wind_direction = Vector3(cos(_wind_yaw), 0.0, sin(_wind_yaw))


func _update_gust() -> void:
	var amp := clampf(_wind_gust_amp, 0.0, 1.0)
	var wave := sin(_time * lerpf(0.4, 1.0, amp)) * 0.5 + 0.5
	var burst := smoothstep(0.8, 0.97, sin(_time * 0.22 + 0.6) * 0.5 + 0.5)
	_gust = amp * (wave * 0.62 + burst * 0.38)
	_applied_wind = clampf(_wind_intensity + _gust * 0.4, 0.0, 1.25)


func _update_lightning(delta: float) -> void:
	if _flash > 0.0:
		_flash_hold -= delta
		if _flash_hold <= 0.0:
			_flash = maxf(0.0, _flash - delta * 7.5)
	if float(_current["storm_intensity"]) < 0.6:
		_lightning_in = maxf(_lightning_in, 9.0)
		return
	_lightning_in -= delta
	if _lightning_in > 0.0:
		return
	_flash = 1.75
	_flash_hold = 0.055
	_lightning_in = _rng.randf_range(12.0, 26.0)
	thunder.emit()


func _apply_wind() -> void:
	var flora := _flora_node()
	if flora == null:
		return
	var tilt := clampf(_wind_intensity, 0.0, 1.0)
	var gust := clampf(_wind_gust_amp, 0.0, 1.0)
	flora.set(&"wind_direction", wind_direction)
	flora.set(&"base_wind_strength", clampf(lerpf(0.006, 0.12, tilt) + _gust * 0.035, 0.0, 0.3))
	flora.set(&"gust_strength", lerpf(0.0, 0.38, gust))
	flora.set(&"gust_speed", lerpf(0.4, 1.7, gust))
	flora.set(&"turbulence_strength", lerpf(0.004, 0.06, maxf(tilt, gust)))


func _apply_clouds(delta: float) -> void:
	if _multi == null:
		return
	var planet := _planet_node()
	if planet == null:
		return
	var coverage := float(_current["cloud_coverage"])
	var density := clampf(float(_current["cloud_density"]), 0.0, 1.0)
	var wind := clampf(_applied_wind, 0.0, 1.0)
	var speed := lerpf(CLOUD_DRIFT_MIN, CLOUD_DRIFT_MAX, wind * wind)
	var orbit := _wind_orbit_axis()
	var turn := speed / 58.0 * delta
	var gloom := clampf(1.0 - float(_current["sky_brightness"]), 0.0, 1.0)
	var color := Color(0.9, 0.93, 0.97).lerp(Color(0.2, 0.22, 0.26), gloom)
	color.a = lerpf(0.34, 0.88, density)
	_cloud_mat.set_shader_parameter(&"albedo", color)
	_cloud_mat.set_shader_parameter(&"shadow_tint", Color(0.52, 0.58, 0.66).lerp(Color(0.1, 0.11, 0.13), gloom))
	_clouds.global_position = planet.global_position
	_clouds.global_basis = Basis.IDENTITY
	_clouds.visible = true
	for i in _dirs.size():
		var dir := _dirs[i].rotated(orbit, turn)
		if dir.length_squared() < 0.001:
			dir = Vector3.UP
		_dirs[i] = dir
		var radius := _shell(dir, _alt[i])
		var field := _cloud_field(dir)
		var edge := 1.0 - coverage
		var cover := smoothstep(edge - 0.1, edge + 0.14, field)
		var span := lerpf(5.2, 8.6, _bulk[i]) * lerpf(0.7, 1.12, density) * lerpf(0.84, 1.16, field) * cover
		var up := dir
		var axis := orbit.cross(up)
		if axis.length_squared() < 0.0001:
			axis = Vector3.FORWARD.cross(up)
		axis = axis.normalized()
		var z := up.cross(axis).normalized()
		var basis := Basis(axis, up, z).rotated(up, _yaw[i]).scaled(Vector3(span, span * 0.42, span * 0.8))
		_multi.set_instance_transform(i, Transform3D(basis, up * radius))
		_multi.set_instance_color(i, Color(1.0, 1.0, 1.0, clampf(cover * lerpf(0.72, 1.0, field), 0.0, 1.0)))


func _apply_fog() -> void:
	if _env == null:
		return
	var multiplier := maxf(float(_current["weather_fog_multiplier"]), 1.0)
	var extra := multiplier - 1.0
	var weight := clampf(extra / 2.4, 0.0, 1.0)
	var begin := lerpf(float(base_fog["begin"]), 6.5, weight)
	var base_end := _base_fog_end()
	var span := maxf(base_end - float(base_fog["begin"]), 8.0)
	var end := maxf(begin + span / multiplier, begin + 4.5)
	var storm := float(_current["storm_intensity"])
	_env.fog_enabled = true
	_env.fog_mode = Environment.FOG_MODE_DEPTH
	_env.fog_depth_begin = begin
	_env.fog_depth_end = end
	_env.fog_depth_curve = lerpf(float(base_fog["curve"]), 0.95, weight)
	_env.fog_light_energy = lerpf(float(base_fog["energy"]), 1.0, weight)
	_env.fog_aerial_perspective = lerpf(float(base_fog["aerial"]), 0.62, weight)
	_env.fog_sky_affect = lerpf(float(base_fog["sky_affect"]), 0.72, weight)
	var horizon := Color(0.68, 0.72, 0.78)
	if _env.sky != null and _env.sky.sky_material is ShaderMaterial:
		var body: Variant = (_env.sky.sky_material as ShaderMaterial).get_shader_parameter(&"nadir_color")
		if body is Color:
			horizon = body
	var tint := Color(0.66, 0.72, 0.78).lerp(Color(0.5, 0.54, 0.58), clampf(0.22 + float(_current["rain_intensity"]) + extra * 0.15, 0.0, 1.0))
	tint = tint.lerp(Color(0.26, 0.28, 0.32), storm)
	_env.fog_light_color = horizon.lerp(tint, clampf(0.85 + extra * 0.04, 0.0, 0.95))
	var sat := lerpf(1.0, 0.74, clampf((1.0 - float(_current["sky_brightness"])) * 0.9 + storm * 0.15, 0.0, 1.0))
	_env.adjustment_enabled = sat < 0.995
	_env.adjustment_saturation = sat


func _base_fog_end() -> float:
	var begin := float(base_fog["begin"])
	var reach := _chunk_render_radius()
	var end := minf(float(base_fog["end"]), reach + 3.0)
	if end < reach:
		end = reach + 3.0
	return maxf(end, begin + 12.0)


func _chunk_render_radius() -> float:
	if _chunk_reach > 0.0:
		return _chunk_reach
	var planet := _planet_node()
	if planet != null:
		var volume := planet.get_node_or_null(^"TerrainVolume")
		if volume != null and volume.get_script() != null:
			var constants: Dictionary = volume.get_script().get_script_constant_map()
			if constants.has("RENDER_RADIUS"):
				_chunk_reach = float(constants["RENDER_RADIUS"])
				return _chunk_reach
	return TERRAIN.RENDER_RADIUS


func _apply_rain(delta: float) -> void:
	if _rain == null:
		return
	var player := _player_node()
	var planet := _planet_node()
	var intensity := float(_current["rain_intensity"])
	var raining := intensity > 0.02
	if not raining or player == null or planet == null:
		_sheltered = false
		_shelter_hold = 0.0
		player_exposed_to_rain = false
		_rain.emitting = false
		_rain.visible = false
		_rain.amount_ratio = 0.0
		return
	_update_shelter(player, planet, delta)
	var covered := _sheltered or _shelter_hold > 0.0
	player_exposed_to_rain = not covered
	var show := not covered
	var local_up := player.global_position - planet.global_position
	if local_up.length_squared() < 0.001:
		local_up = Vector3.UP
	else:
		local_up = local_up.normalized()
	if not _rain_aligned:
		_rain_up = local_up
		_rain_aligned = true
	else:
		var weight := 1.0 - exp(-4.0 * delta)
		_rain_up = _rain_up.slerp(local_up, weight).normalized()
	var frame := _rain_frame(_rain_up)
	var local_down := -_rain_up
	var tangential := wind_direction - _rain_up * wind_direction.dot(_rain_up)
	var rain_direction := (local_down + tangential * clampf(_applied_wind, 0.0, 1.2) * 0.7).normalized()
	_rain.global_basis = frame
	_rain.global_position = player.global_position + _rain_up * 9.0
	_rain.emitting = show
	_rain.visible = show
	if not show:
		_rain.amount_ratio = 0.0
		return
	var storm := float(_current["storm_intensity"])
	var heavy := maxf(intensity, storm)
	var local_dir := Vector3(rain_direction.dot(frame.x), rain_direction.dot(frame.y), rain_direction.dot(frame.z)).normalized()
	_rain.amount_ratio = clampf(intensity, 0.0, 1.0)
	_rain.lifetime = lerpf(1.05, 0.72, heavy)
	_rain_mat.direction = local_dir
	_rain_mat.spread = lerpf(1.5, 7.0, storm)
	_rain_mat.initial_velocity_min = lerpf(8.0, 14.0, heavy)
	_rain_mat.initial_velocity_max = lerpf(12.0, 20.0, heavy)
	_rain_mat.gravity = rain_direction * lerpf(8.0, 14.0, heavy)
	_rain_mat.scale_min = lerpf(0.7, 0.95, storm)
	_rain_mat.scale_max = lerpf(1.15, 1.6, storm)
	var drop := Color(0.8, 0.88, 0.95).lerp(Color(0.62, 0.68, 0.76), storm)
	_drop_mat.albedo_color = Color(drop.r, drop.g, drop.b, lerpf(0.45, 0.75, intensity))


func _update_shelter(player: Node3D, planet: Node3D, delta: float) -> void:
	var world := get_world_3d()
	if world == null:
		return
	var up := (player.global_position - planet.global_position).normalized()
	if up.length_squared() < 0.001:
		up = Vector3.UP
	var from := player.global_position + up * 1.15
	var query := PhysicsRayQueryParameters3D.create(from, from + up * 6.5, BUILD_MASK)
	query.collide_with_areas = false
	query.exclude = [player.get_rid()]
	var hit := world.direct_space_state.intersect_ray(query)
	var blocked := false
	if not hit.is_empty():
		blocked = (hit["normal"] as Vector3).dot(up) < -0.4
	if blocked:
		_sheltered = true
		_shelter_hold = 0.35
	else:
		_sheltered = false
		_shelter_hold = maxf(_shelter_hold - delta, 0.0)


func _flora_node() -> Node:
	if _flora != null and is_instance_valid(_flora):
		return _flora
	var planet := _planet_node()
	if planet == null:
		return null
	_flora = planet.get_node_or_null(^"Flora")
	return _flora


func _planet_node() -> Node3D:
	if _planet != null and is_instance_valid(_planet):
		return _planet
	_planet = get_tree().get_first_node_in_group(&"planet") as Node3D
	return _planet


func _player_node() -> Node3D:
	if _player != null and is_instance_valid(_player):
		return _player
	_player = get_tree().get_first_node_in_group(&"player") as Node3D
	return _player


func _wind_orbit_axis() -> Vector3:
	var axis := wind_direction.cross(Vector3.UP)
	if axis.length_squared() < 0.001:
		axis = wind_direction.cross(Vector3.RIGHT)
	return axis.normalized()


func _cloud_field(dir: Vector3) -> float:
	return _cloud_noise.get_noise_3d(dir.x, dir.y, dir.z) * 0.5 + 0.5


func _rain_frame(up: Vector3) -> Basis:
	var tangent := wind_direction - up * wind_direction.dot(up)
	if tangent.length_squared() < 0.0008:
		tangent = _rain_tangent - up * _rain_tangent.dot(up)
	if tangent.length_squared() < 0.0008:
		tangent = up.cross(Vector3.RIGHT)
		if tangent.length_squared() < 0.0008:
			tangent = up.cross(Vector3.FORWARD)
	tangent = tangent.normalized()
	if _rain_tangent.length_squared() > 0.5 and tangent.dot(_rain_tangent) < 0.0:
		tangent = -tangent
	_rain_tangent = tangent
	var z := tangent.cross(up).normalized()
	var x := up.cross(z).normalized()
	return Basis(x, up, z)


func _shell(dir: Vector3, extra: float) -> float:
	var planet := _planet_node()
	var base := 62.0
	if planet != null and planet.has_method(&"sample_terrain_height"):
		base = float(planet.call(&"sample_terrain_height", dir))
	elif planet != null:
		base = float(planet.get(&"base_radius")) + 8.0
	return base + extra


func _pick_next(id: int) -> int:
	var row: Array = TRANSITIONS[clampi(id, 0, TRANSITIONS.size() - 1)]
	var total := 0
	for entry in row:
		total += int(entry[1])
	var roll := _rng.randi_range(1, maxi(total, 1))
	var acc := 0
	for entry in row:
		acc += int(entry[1])
		if roll <= acc:
			return int(entry[0])
	return int(row[0][0])


func _profile(id: int) -> Dictionary:
	return WeatherProfiles.profile(id)


func _sanitize(raw: Dictionary) -> Dictionary:
	return WeatherProfiles.sanitize(raw, KEYS)


func _id_of(weather_name: String) -> int:
	var idx := NAMES.find(weather_name)
	return Weather.CLEAR if idx < 0 else idx


func _export_dirs() -> Array:
	var out: Array = []
	for dir in _dirs:
		out.append(dir.x)
		out.append(dir.y)
		out.append(dir.z)
	return out


func _import_dirs(raw: Variant) -> void:
	if not raw is Array or (raw as Array).size() != _dirs.size() * 3:
		return
	var values: Array = raw
	var sum := Vector3.ZERO
	for i in _dirs.size():
		var dir := Vector3(float(values[i * 3]), float(values[i * 3 + 1]), float(values[i * 3 + 2]))
		dir = dir.normalized() if dir.length_squared() > 0.001 else Vector3.UP
		_dirs[i] = dir
		sum += dir
	if sum.length() > float(_dirs.size()) * 0.45:
		for i in _dirs.size():
			_dirs[i] = _fibonacci(i, _dirs.size())


func _fibonacci(i: int, count: int) -> Vector3:
	var y := 1.0 - (float(i) + 0.5) / float(count) * 2.0
	var ring := sqrt(maxf(0.0, 1.0 - y * y))
	var theta := PI * (3.0 - sqrt(5.0)) * float(i)
	return Vector3(cos(theta) * ring, y, sin(theta) * ring)
