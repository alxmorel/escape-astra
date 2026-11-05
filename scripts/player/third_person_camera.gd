extends Node3D

enum Mode { FPS, TPS_NEAR, TPS_FAR }

@export var mouse_sensitivity: float = 0.003
@export var min_pitch_degrees: float = -55.0
@export var max_pitch_degrees: float = 35.0
@export var fps_min_pitch_degrees: float = -80.0
@export var fps_max_pitch_degrees: float = 75.0
@export var vertical_follow_speed: float = 5.0
@export var transition_speed: float = 12.0
@export var tps_near_distance: float = 2.0
@export var tps_far_distance: float = 4.0
@export var aim_fov_reduce: float = 14.0
@export var aim_zoom_speed: float = 10.0

@onready var _shoulder: Node3D = $Shoulder
@onready var _spring_arm: SpringArm3D = $Shoulder/SpringArm3D
@onready var _camera: Camera3D = $Shoulder/SpringArm3D/Camera3D

var _mode: int = Mode.TPS_NEAR
var _blend := 0.0
var _distance := 2.0
var _head_height: float = 1.35
var _smoothed_radius: float = 0.0
var _tps_shoulder: Vector3
var _tps_spring_pos: Vector3
var _hide_meshes: Array[MeshInstance3D] = []
var _base_fov: float = 75.0
var _aim_zoom_target := 0.0
var _aim_zoom := 0.0


func _ready() -> void:
	_head_height = position.y
	_smoothed_radius = _player_radius()
	_tps_shoulder = _shoulder.position
	_tps_spring_pos = _spring_arm.position
	_spring_arm.add_excluded_object(get_parent().get_rid())
	_camera.position = Vector3.ZERO
	_base_fov = _camera.fov
	_collect_hide_meshes()
	_mode = Settings.camera_mode()
	_blend = 1.0 if _mode == Mode.FPS else 0.0
	_distance = _target_distance()
	_apply_pose(_blend, _distance)
	_apply_mesh_visibility()


func set_bow_aim(active: bool) -> void:
	_aim_zoom_target = 1.0 if active else 0.0


func aim_pitch() -> float:
	return _spring_arm.rotation.x


func is_first_person() -> bool:
	return _mode == Mode.FPS


func fps_blend() -> float:
	return _blend


func camera_mode() -> int:
	return _mode


func cycle_view() -> void:
	set_mode((_mode + 1) % 3)


func set_mode(mode: int) -> void:
	mode = clampi(mode, Mode.FPS, Mode.TPS_FAR)
	if _mode == mode:
		return
	_mode = mode
	Settings.set_camera_mode(mode)
	_apply_mesh_visibility()


func _target_distance() -> float:
	match _mode:
		Mode.FPS:
			return 0.0
		Mode.TPS_NEAR:
			return tps_near_distance
		_:
			return tps_far_distance


func _collect_hide_meshes() -> void:
	_hide_meshes.clear()
	var visual := get_parent().get_node_or_null("Visual") as Node
	if visual == null:
		return
	var head := visual.get_node_or_null(^"Torso/Head") as Node3D
	if head != null:
		if head is MeshInstance3D:
			_hide_meshes.append(head as MeshInstance3D)
		for child in head.find_children("*", "MeshInstance3D", true, false):
			_hide_meshes.append(child as MeshInstance3D)
	var body := visual.get_node_or_null(^"Torso/Body") as MeshInstance3D
	if body != null:
		_hide_meshes.append(body)


func _apply_mesh_visibility() -> void:
	# FPS : invisible à la caméra mais ombres conservées (pas de géométrie dupliquée).
	var shadows_only := _mode == Mode.FPS or _blend > 0.2
	for mesh in _hide_meshes:
		if not is_instance_valid(mesh):
			continue
		mesh.visible = true
		mesh.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			if shadows_only
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		)


func _physics_process(delta: float) -> void:
	var radius := _player_radius()
	var follow := 1.0 - exp(-vertical_follow_speed * delta)
	_smoothed_radius = lerpf(_smoothed_radius, radius, follow)
	position.y = _head_height + _smoothed_radius - radius

	var blend_target := 1.0 if _mode == Mode.FPS else 0.0
	var distance_target := _target_distance()
	var step := 1.0 - exp(-transition_speed * delta)
	var dirty := false
	if not is_equal_approx(_blend, blend_target):
		_blend = lerpf(_blend, blend_target, step)
		if absf(_blend - blend_target) < 0.001:
			_blend = blend_target
		dirty = true
	if not is_equal_approx(_distance, distance_target):
		_distance = lerpf(_distance, distance_target, step)
		if absf(_distance - distance_target) < 0.001:
			_distance = distance_target
		dirty = true
	if dirty:
		_apply_pose(_blend, _distance)
		_apply_mesh_visibility()
	else:
		_apply_pose(_blend, _distance)
	_spring_arm.rotation.x = clampf(_spring_arm.rotation.x, _min_pitch(), _max_pitch())
	var zoom_step := 1.0 - exp(-aim_zoom_speed * delta)
	_aim_zoom = lerpf(_aim_zoom, _aim_zoom_target, zoom_step)
	_camera.fov = lerpf(_base_fov, _base_fov - aim_fov_reduce, _aim_zoom)


func _apply_pose(amount: float, distance: float) -> void:
	var t := smoothstep(0.0, 1.0, amount)
	# FPS : épaule + spring sur l'axe (plus de décalage latéral hérit du TPS).
	_shoulder.position = _tps_shoulder.lerp(Vector3.ZERO, t)
	_spring_arm.position = _tps_spring_pos.lerp(Vector3.ZERO, t)
	_spring_arm.spring_length = distance
	_spring_arm.margin = lerpf(0.2, 0.05, t)
	_camera.near = lerpf(0.05, 0.1, t)
	_camera.position = Vector3.ZERO



func _player_radius() -> float:
	var player := get_parent() as Node3D
	var planet := get_tree().get_first_node_in_group(&"planet") as Node3D
	var origin := planet.global_position if planet != null else Vector3.ZERO
	return player.global_position.distance_to(origin)


func _min_pitch() -> float:
	return deg_to_rad(lerpf(min_pitch_degrees, fps_min_pitch_degrees, _blend))


func _max_pitch() -> float:
	return deg_to_rad(lerpf(max_pitch_degrees, fps_max_pitch_degrees, _blend))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_camera") and not event.is_echo():
		var player := get_parent()
		if player != null and bool(player.get(&"controls_locked")):
			return
		cycle_view()
		get_viewport().set_input_as_handled()
		return

	if not (event is InputEventMouseMotion) or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	var motion := event as InputEventMouseMotion
	rotate_y(-motion.relative.x * mouse_sensitivity)
	_spring_arm.rotation.x = clampf(
		_spring_arm.rotation.x - motion.relative.y * mouse_sensitivity,
		_min_pitch(),
		_max_pitch()
	)
