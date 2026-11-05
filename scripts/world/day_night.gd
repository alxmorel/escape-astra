extends Node3D

@export var day_duration: float = 300.0
@export var night_duration: float = 300.0
@export var day_light_energy: float = 1.0
@export var night_light_energy: float = 0.22
@export var sunset_light_energy: float = 0.7
@export var day_ambient_energy: float = 0.42
@export var night_ambient_energy: float = 0.14
@export var day_light_color: Color = Color(1, 0.96, 0.88)
@export var sunset_light_color: Color = Color(1, 0.52, 0.26)
@export var night_light_color: Color = Color(0.55, 0.66, 0.95)
@export var giant_radius: float = 850.0
@export var giant_distance: float = 3800.0

var _time: float = 0.0

@onready var _pivot: Node3D = $SunPivot
@onready var _light: DirectionalLight3D = $SunPivot/Sun

const _COLOR_EPS := 0.004
const _UP_DOT := 0.99995
const _SUN_DOT := 0.999995

var _environment: Environment
var _sky: ShaderMaterial
var _planet: Node3D
var _player: Node3D
var _sky_sent: Dictionary = {}


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_time = day_duration * 0.5
	var world := get_parent().get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	if world != null and world.environment != null:
		_environment = world.environment
		_sky = _environment.sky.sky_material as ShaderMaterial
	_planet = get_parent().get_node_or_null(^"Planet") as Node3D
	_player = get_parent().get_node_or_null(^"Player") as Node3D
	_spawn_giant()
	_apply_cycle()


func export_time() -> float:
	return _time


func import_time(value: float) -> void:
	var cycle := maxf(day_duration, 0.01) + maxf(night_duration, 0.01)
	_time = fposmod(value, cycle)
	_apply_cycle()


func _process(delta: float) -> void:
	var cycle := maxf(day_duration, 0.01) + maxf(night_duration, 0.01)
	_time = fposmod(_time + delta, cycle)
	_apply_cycle()


func _apply_cycle() -> void:
	_pivot.rotation.x = _sun_angle()
	var height := _sun_height()
	var day_weight := smoothstep(-0.05, 0.4, height)
	var sunset_weight := clampf(1.0 - absf(height) / 0.4, 0.0, 1.0) * smoothstep(-0.55, 0.1, height)
	var light_color := day_light_color.lerp(night_light_color, 1.0 - day_weight).lerp(sunset_light_color, sunset_weight)
	var light_energy := lerpf(night_light_energy, day_light_energy, day_weight)
	light_energy = lerpf(light_energy, sunset_light_energy, sunset_weight * 0.65)
	var ambient := lerpf(night_ambient_energy, day_ambient_energy, day_weight)
	var day_zenith := Color(0.4, 0.62, 0.9)
	var day_nadir := Color(0.5, 0.7, 0.93)
	var night_zenith := Color(0.08, 0.09, 0.16)
	var night_nadir := Color(0.11, 0.12, 0.19)
	var zenith := day_zenith.lerp(night_zenith, 1.0 - day_weight)
	var nadir := day_nadir.lerp(night_nadir, 1.0 - day_weight)
	var warm := Color(0.72, 0.45, 0.4)
	zenith = zenith.lerp(warm, sunset_weight * 0.72)
	nadir = nadir.lerp(warm, sunset_weight * 0.72)
	var sunset_tint := Color(0.9, 0.48, 0.28)
	var sky_energy := lerpf(0.55, 1.0, day_weight)
	var mods := _weather_mods()
	var sun_mul := float(mods.get("sun", 1.0))
	var ambient_mul := float(mods.get("ambient", 1.0))
	var sky_mul := float(mods.get("sky", 1.0))
	var flash := float(mods.get("flash", 0.0))
	var gloom := clampf(1.0 - sky_mul, 0.0, 1.0) * 0.55
	var gray := Color(0.4, 0.44, 0.5)
	zenith = zenith.lerp(zenith.darkened(0.42).lerp(gray, 0.5), gloom)
	nadir = nadir.lerp(nadir.darkened(0.3).lerp(gray, 0.5), gloom)
	sunset_tint = sunset_tint.lerp(sunset_tint.darkened(0.35).lerp(gray, 0.45), gloom)
	if flash > 0.04:
		var kick := clampf(flash / 1.8, 0.0, 1.0)
		var bolt := Color(0.86, 0.9, 1.0)
		zenith = zenith.lerp(bolt, kick * 0.7)
		nadir = nadir.lerp(Color(0.78, 0.82, 0.9), kick * 0.5)
		sunset_tint = sunset_tint.lerp(bolt, kick * 0.35)
		light_color = light_color.lerp(Color(0.9, 0.94, 1.0), kick * 0.65)
	_light.light_color = light_color
	_light.light_energy = maxf(light_energy * sun_mul + flash, 0.0)
	if _environment != null:
		_environment.ambient_light_energy = maxf(ambient * ambient_mul + flash * 0.42, 0.0)
		var noon := smoothstep(0.25, 0.92, height)
		_environment.tonemap_exposure = lerpf(1.0, 0.68, noon)
	if _sky == null:
		return
	_push_dir(&"up", _local_up(), _UP_DOT)
	_push_dir(&"sun_dir", _toward_sun(), _SUN_DOT)
	_push_color(&"zenith_color", zenith)
	_push_color(&"nadir_color", nadir)
	_push_color(&"sun_color", light_color)
	_push_color(&"sunset_color", sunset_tint)
	_push_float(&"sunset", sunset_weight)
	_push_float(&"energy", maxf(sky_energy * sky_mul + flash * 0.22, 0.0))


func _weather_mods() -> Dictionary:
	var node := get_tree().get_first_node_in_group(&"weather")
	if node == null or not node.has_method(&"lighting_modifiers"):
		return {}
	var mods: Variant = node.call(&"lighting_modifiers")
	return mods if mods is Dictionary else {}


func _sun_angle() -> float:
	if _time <= day_duration:
		var day_u := 0.0 if day_duration <= 0.0 else _time / day_duration
		return lerpf(-PI * 0.5, PI * 0.5, day_u)
	var night_u := 0.0 if night_duration <= 0.0 else (_time - day_duration) / night_duration
	return lerpf(PI * 0.5, PI * 1.5, night_u)


func _sun_height() -> float:
	return clampf(_toward_sun().dot(_local_up()), -1.0, 1.0)


func _toward_sun() -> Vector3:
	return _light.global_transform.basis.z.normalized()


func _local_up() -> Vector3:
	if _planet == null or _player == null:
		return Vector3.UP
	var radial := _player.global_position - _planet.global_position
	if radial.length_squared() < 0.0001:
		return Vector3.UP
	return radial.normalized()


func _push_color(param: StringName, value: Color) -> void:
	var prev: Variant = _sky_sent.get(param)
	if prev is Color and _near_color(prev as Color, value):
		return
	_sky.set_shader_parameter(param, value)
	_sky_sent[param] = value


func _push_float(param: StringName, value: float) -> void:
	var prev: Variant = _sky_sent.get(param)
	if prev is float and absf(float(prev) - value) < 0.008:
		return
	_sky.set_shader_parameter(param, value)
	_sky_sent[param] = value


func _push_dir(param: StringName, value: Vector3, min_dot: float) -> void:
	var prev: Variant = _sky_sent.get(param)
	if prev is Vector3 and (prev as Vector3).dot(value) >= min_dot:
		return
	_sky.set_shader_parameter(param, value)
	_sky_sent[param] = value


func _near_color(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < _COLOR_EPS and absf(a.g - b.g) < _COLOR_EPS and absf(a.b - b.b) < _COLOR_EPS


func _spawn_giant() -> void:
	var planet := MeshInstance3D.new()
	planet.name = "GiantPlanet"
	var sphere := SphereMesh.new()
	sphere.radius = giant_radius
	sphere.height = giant_radius * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	planet.mesh = sphere
	planet.material_override = preload("res://scripts/resources/stylized_material.gd").create(Color(0.55, 0.4, 0.32))
	planet.position = Vector3(giant_distance, giant_radius * 0.35, -giant_distance * 0.45)
	add_child(planet)
