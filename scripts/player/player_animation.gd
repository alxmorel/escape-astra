extends Node3D

const FIST_STRIKE := 1.25
const TOOL_STRIKE_X := 1.45
const JUMP_ARM := -0.8
const JUMP_LEG := 0.42
const BOW_AIM_BLEND_SPEED := 9.0
## Bras local −Y (mesh vers le bas) ; rot X aligne −Y sur la visée (repère Torso).
const BOW_AIM_Z_MAX := 0.55

@onready var _player: Player = get_parent() as Player
@onready var _torso: Node3D = $Torso
@onready var _left_arm: Node3D = $Torso/LeftArmPivot
@onready var _right_arm: Node3D = $Torso/RightArmPivot
@onready var _left_leg: Node3D = $LeftLegPivot
@onready var _right_leg: Node3D = $RightLegPivot

var _phase := 0.0
var _bob := 0.0
var _lean := 0.0
var _left_arm_x := 0.0
var _right_arm_x := 0.0
var _right_arm_z := 0.0
var _left_leg_x := 0.0
var _right_leg_x := 0.0
var _step_sign := 0.0
var _stroke_sign := 0.0
var _bow_aim_w := 0.0


func _physics_process(delta: float) -> void:
	var speed := _player.planar_speed
	var walk_speed := maxf(_player.walk_speed, 0.1)
	var run_speed := maxf(_player.run_speed, walk_speed)
	var airborne := _player.airborne
	var jumping := _player.jumping
	var swimming := _player.swimming
	var radial := _player.radial_speed
	var punch_weight := clampf(_player.punch_weight, 0.0, 1.0)
	var punch_phase := clampf(_player.punch_phase, 0.0, 1.0)
	var tool := _player.tool_held
	var move := smoothstep(0.2, walk_speed * 0.65, speed)
	var gait := clampf((speed - walk_speed * 0.7) / (run_speed - walk_speed * 0.7), 0.0, 1.0)
	var falling := airborne and not jumping and radial < -0.3
	if swimming:
		_phase += delta * lerpf(4.2, 7.0, move)
		_step_sign = 0.0
		if _player.swim_moving:
			_poll_stroke()
		else:
			_stroke_sign = 0.0
	elif not jumping and not falling:
		_stroke_sign = 0.0
		_phase += speed * delta * lerpf(1.7, 2.15, gait)
		if move > 0.35:
			_poll_step()
		else:
			_step_sign = 0.0
	else:
		_stroke_sign = 0.0
		_step_sign = 0.0
	var swing := sin(_phase) * move
	var arm_amp := lerpf(0.5, 0.95, gait)
	var leg_amp := lerpf(0.42, 0.78, gait)
	var left_arm := swing * arm_amp
	var right_arm := -swing * arm_amp
	var left_leg := -swing * leg_amp
	var right_leg := swing * leg_amp
	var bob := (1.0 - cos(_phase * 2.0)) * 0.5 * lerpf(0.03, 0.06, gait) * move
	var lean := lerpf(0.0, -0.16, gait) * move
	if swimming:
		var paddle := sin(_phase)
		left_arm = paddle * 0.75
		right_arm = -paddle * 0.75
		left_leg = -paddle * 0.32
		right_leg = paddle * 0.32
		bob = 0.0
		lean = -0.22
	elif jumping or falling:
		left_arm = -0.35 if falling else JUMP_ARM
		right_arm = left_arm
		left_leg = 0.15 if falling else JUMP_LEG
		right_leg = left_leg
		bob = 0.0
		lean = 0.08 if falling else -0.04
	var right_z := 0.0
	if tool and punch_weight > 0.0:
		var chop := _tool_chop(punch_phase)
		right_arm = lerpf(right_arm, chop.x, punch_weight)
		right_z = chop.y * punch_weight
	elif punch_weight > 0.0:
		right_arm = lerpf(right_arm, _punch_angle(punch_phase, _player.impact_ratio), punch_weight)
	_bow_aim_w = _approach(
		_bow_aim_w, 1.0 if _is_bow_aiming() else 0.0, delta, BOW_AIM_BLEND_SPEED
	)
	var fps_w := _fps_blend()
	# Pose FPS générique outils / poings — pas pendant la visée arc (pose dédiée).
	if fps_w > 0.001 and _bow_aim_w < 0.99:
		var cam_pitch := _camera_pitch()
		var fps_apply := fps_w * (1.0 - _bow_aim_w)
		if tool:
			var hold_x := cam_pitch + 0.35
			var hold_z := -0.12
			if punch_weight > 0.0:
				var chop_fps := _tool_chop(punch_phase)
				hold_x = lerpf(hold_x, cam_pitch + chop_fps.x, punch_weight)
				hold_z = lerpf(hold_z, chop_fps.y, punch_weight)
			right_arm = lerpf(right_arm, hold_x, fps_apply)
			right_z = lerpf(right_z, hold_z, fps_apply)
			left_arm = lerpf(left_arm, cam_pitch * 0.25 - 0.08, fps_apply)
		else:
			var fist_x := right_arm + cam_pitch
			if punch_weight > 0.0:
				fist_x = cam_pitch + _punch_angle(punch_phase, _player.impact_ratio)
			right_arm = lerpf(right_arm, fist_x, fps_apply)
			left_arm = lerpf(left_arm, left_arm + cam_pitch * 0.45, fps_apply)
		bob = lerpf(bob, 0.0, fps_apply)
		lean = lerpf(lean, 0.0, fps_apply)
	if _bow_aim_w > 0.001:
		var aim_xz := _bow_aim_arm_angles()
		# Épaule : −Y du pivot → direction réticule (yaw Visual + pitch caméra).
		right_arm = lerpf(right_arm, aim_xz.x, _bow_aim_w)
		right_z = lerpf(right_z, aim_xz.y, _bow_aim_w)
		left_arm = lerpf(left_arm, aim_xz.x * 0.82, _bow_aim_w)
		bob = lerpf(bob, 0.0, _bow_aim_w)
		lean = lerpf(lean, 0.0, _bow_aim_w)
	var follow := lerpf(10.0, 14.0, maxf(fps_w, _bow_aim_w))
	_left_arm_x = _approach(_left_arm_x, left_arm, delta, follow)
	_left_leg_x = _approach(_left_leg_x, left_leg, delta, follow)
	_right_leg_x = _approach(_right_leg_x, right_leg, delta, follow)
	if _bow_aim_w > 0.85 or fps_w > 0.85 or punch_weight >= 0.999:
		_right_arm_x = right_arm
		_right_arm_z = right_z
		if _bow_aim_w > 0.85:
			_left_arm_x = left_arm
	else:
		_right_arm_x = _approach(_right_arm_x, right_arm, delta, follow)
		_right_arm_z = _approach(_right_arm_z, right_z, delta, follow)
	_bob = _approach(_bob, bob, delta, 8.0)
	_lean = _approach(_lean, lean, delta, 8.0)
	position.y = _bob
	_torso.rotation.x = _lean
	_left_arm.rotation.x = _left_arm_x
	_right_arm.rotation.x = _right_arm_x
	_right_arm.rotation.z = _right_arm_z
	_left_leg.rotation.x = _left_leg_x
	_right_leg.rotation.x = _right_leg_x
	# Après pose épaule : resync arc / flèche sur la direction de tir.
	if _bow_aim_w > 0.05:
		var tools = _player.get(&"_tools")
		if tools != null and tools.has_method(&"sync_bow_aim_visual"):
			tools.call(&"sync_bow_aim_visual")


func _fps_blend() -> float:
	var camera_yaw := _player.get_node_or_null(^"CameraYaw")
	if camera_yaw != null and camera_yaw.has_method(&"fps_blend"):
		return clampf(float(camera_yaw.call(&"fps_blend")), 0.0, 1.0)
	return 0.0


func _camera_pitch() -> float:
	var camera_yaw := _player.get_node_or_null(^"CameraYaw")
	if camera_yaw != null and camera_yaw.has_method(&"aim_pitch"):
		return float(camera_yaw.call(&"aim_pitch"))
	return 0.0


func _is_bow_aiming() -> bool:
	var tools = _player.get(&"_tools")
	return tools != null and tools.has_method(&"is_bow_aiming") and bool(tools.call(&"is_bow_aiming"))


func _bow_aim_arm_angles() -> Vector2:
	## x = rotation.x, y = rotation.z du RightArmPivot pour viser le réticule.
	var camera := _player.get_viewport().get_camera_3d()
	if camera == null or _torso == null:
		return Vector2(PI * 0.5, 0.0)
	var look := -camera.global_basis.z
	if look.length_squared() < 0.0001:
		return Vector2(PI * 0.5, 0.0)
	look = look.normalized()
	# Direction de visée dans l’espace du parent du pivot (Torso / Visual).
	var look_local := _torso.global_transform.basis.inverse() * look
	# Rx : R_x*(0,-1,0)=(0,-cos,-sin) → cos=−look.y, sin=−look.z.
	var rx := atan2(-look_local.z, -look_local.y)
	var horiz := sqrt(look_local.y * look_local.y + look_local.z * look_local.z)
	var rz := atan2(look_local.x, maxf(horiz, 0.001))
	rz = clampf(rz, -BOW_AIM_Z_MAX, BOW_AIM_Z_MAX)
	return Vector2(rx, rz)


func _poll_step() -> void:
	var sign_now := 1.0 if sin(_phase) >= 0.0 else -1.0
	if _step_sign != 0.0 and sign_now != _step_sign:
		var side := "left" if cos(_phase) >= 0.0 else "right"
		var audio := get_node_or_null(^"/root/AudioManager")
		if audio != null and audio.has_method(&"footstep"):
			audio.call(&"footstep", side)
	_step_sign = sign_now


func _poll_stroke() -> void:
	var sign_now := 1.0 if sin(_phase) >= 0.0 else -1.0
	if _stroke_sign != 0.0 and sign_now != _stroke_sign:
		var audio := get_node_or_null(^"/root/AudioManager")
		if audio != null and audio.has_method(&"swim_stroke"):
			audio.call(&"swim_stroke")
	_stroke_sign = sign_now


func _punch_angle(phase: float, impact_ratio: float) -> float:
	return lerpf(0.0, FIST_STRIKE, _tool_arc(phase, impact_ratio))


func _tool_chop(phase: float) -> Vector2:
	var raised := Vector2(TOOL_STRIKE_X, 0.0)
	var chopped := Vector2(0.02, 0.0)
	var held := Vector2.ZERO
	if phase < 0.68:
		var t := phase / 0.68
		t = t * t * (3.0 - 2.0 * t)
		return held.lerp(raised, t)
	if phase < 0.84:
		var t := (phase - 0.68) / 0.16
		t = 1.0 - (1.0 - t) * (1.0 - t)
		return raised.lerp(chopped, t)
	var recover := (phase - 0.84) / 0.16
	recover = clampf(recover, 0.0, 1.0)
	recover = recover * recover * (3.0 - 2.0 * recover)
	return chopped.lerp(held, recover)


func _tool_arc(phase: float, impact_ratio: float) -> float:
	var ratio := clampf(impact_ratio, 0.05, 0.95)
	var t := phase / ratio if phase <= ratio else (1.0 - phase) / (1.0 - ratio)
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _approach(current: float, target: float, delta: float, speed: float) -> float:
	return lerpf(current, target, 1.0 - exp(-speed * delta))
