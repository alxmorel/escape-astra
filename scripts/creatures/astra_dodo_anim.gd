extends Node
class_name AstraDodoAnim

## Animation procédurale bipède pour dodo.glb.
## Axes modèle (avant yaw mount) : avant = +Z, haut = +Y, droite = +X.
## Nœuds importés : corps_002, tete_002, bas_machoire, aile_*, jambe_*.
## Swing patte = rotation locale X (plan Y/Z).

enum IdleAct { NONE, CHIRP, GLANCE, LOOK_GROUND, PECK }

@export var walk_hz: float = 1.7
@export var flee_hz: float = 2.8
@export var leg_amp_deg: float = 28.0
@export var flee_leg_amp_deg: float = 36.0
@export var body_bob_deg: float = 3.0
@export var wing_amp_deg: float = 10.0
@export var flee_wing_amp_deg: float = 18.0
@export var flinch_pitch_deg: float = 10.0
@export var blend_speed: float = 10.0

@export var chirp_duration: float = 0.45
@export var chirp_jaw_deg: float = 16.0
@export var chirp_rate: float = 14.0
@export var glance_duration: float = 0.7
@export var glance_yaw_deg: float = 28.0
@export var look_ground_duration: float = 1.1
@export var look_ground_pitch_deg: float = 22.0
@export var peck_duration: float = 0.55
@export var peck_pitch_deg: float = 35.0
@export var peck_jaw_deg: float = 12.0
@export var idle_act_min_gap: float = 1.6
@export var idle_act_max_gap: float = 4.2

var _model: Node3D
var _corps: Node3D
var _tete: Node3D
var _machoire: Node3D
var _aile_d: Node3D
var _aile_g: Node3D
var _jambe_d: Node3D
var _jambe_g: Node3D

var _rest: Dictionary = {}
var _phase: float = 0.0
var _weight: float = 0.0
var _flinch_t: float = 0.0
var _flinch_max: float = 0.18
var _ready_ok := false

var _act: IdleAct = IdleAct.NONE
var _act_t: float = 0.0
var _act_dur: float = 0.0
var _act_sign: float = 1.0
var _next_act_in: float = 2.0
var _rng := RandomNumberGenerator.new()


func setup(model_root: Node3D) -> void:
	_model = model_root
	if _model == null:
		return
	_rng.randomize()
	_corps = _find("corps_002")
	_tete = _find("tete_002")
	_machoire = _find("bas_machoire")
	_aile_d = _find("aile_droite")
	_aile_g = _find("aile_gauche")
	_jambe_d = _find("jambe_droite")
	_jambe_g = _find("jambe_gauche")
	for part in [_corps, _tete, _machoire, _aile_d, _aile_g, _jambe_d, _jambe_g]:
		if part != null:
			_rest[part] = part.rotation
	_ready_ok = _corps != null and _jambe_d != null and _jambe_g != null and _tete != null
	_next_act_in = _rng.randf_range(idle_act_min_gap, idle_act_max_gap)


func trigger_flinch(duration: float) -> void:
	_flinch_max = maxf(duration, 0.05)
	_flinch_t = _flinch_max
	_cancel_act()


func tick(delta: float, moving: bool, fleeing: bool, speed_ratio: float) -> void:
	if not _ready_ok:
		return
	_flinch_t = maxf(_flinch_t - delta, 0.0)
	var flinching := _flinch_t > 0.0
	var busy_locomotion := moving or fleeing or flinching

	var target_w := 0.0
	if moving and not flinching:
		target_w = clampf(speed_ratio, 0.0, 1.35)
	_weight = move_toward(_weight, target_w, blend_speed * delta)
	var gait := clampf(_weight, 0.0, 1.0)

	var hz := flee_hz if fleeing else walk_hz
	if gait > 0.02:
		_phase = fmod(_phase + TAU * hz * delta * maxf(gait, 0.35), TAU)
	elif not flinching:
		_phase = lerp_angle(_phase, 0.0, 5.0 * delta)

	if busy_locomotion:
		_cancel_act()
	else:
		_tick_idle_schedule(delta)

	var leg_amp := deg_to_rad(flee_leg_amp_deg if fleeing else leg_amp_deg) * gait
	var swing_l := sin(_phase) * leg_amp
	var swing_r := sin(_phase + PI) * leg_amp
	# Swing avant/arrière autour de X local (plan Y/Z, avant = +Z).
	_set_euler(_jambe_g, Vector3(_rest_x(_jambe_g) + swing_l, _rest_y(_jambe_g), _rest_z(_jambe_g)))
	_set_euler(_jambe_d, Vector3(_rest_x(_jambe_d) + swing_r, _rest_y(_jambe_d), _rest_z(_jambe_d)))

	var body_pitch := sin(_phase * 2.0) * deg_to_rad(body_bob_deg) * gait
	var flinch_kick := 0.0
	if flinching:
		var u := 1.0 - (_flinch_t / _flinch_max)
		flinch_kick = sin(u * PI) * deg_to_rad(flinch_pitch_deg)
	_set_euler(_corps, Vector3(
		_rest_x(_corps) + body_pitch - flinch_kick * 0.35,
		_rest_y(_corps),
		_rest_z(_corps)
	))

	var wing_amp := deg_to_rad(flee_wing_amp_deg if fleeing else wing_amp_deg) * maxf(gait, 0.15 if not busy_locomotion else 0.0)
	var wing_swing := sin(_phase * 2.0 + 0.3) * wing_amp
	if not busy_locomotion and gait < 0.02:
		wing_swing = sin(Time.get_ticks_msec() * 0.002) * deg_to_rad(wing_amp_deg) * 0.25
	# Balancement d’ailes : rotation locale Z (plan X/Y).
	_set_euler(_aile_d, Vector3(_rest_x(_aile_d), _rest_y(_aile_d), _rest_z(_aile_d) + wing_swing))
	_set_euler(_aile_g, Vector3(_rest_x(_aile_g), _rest_y(_aile_g), _rest_z(_aile_g) - wing_swing))

	var head_x := _rest_x(_tete)
	var head_y := _rest_y(_tete)
	var head_z := _rest_z(_tete)
	var jaw_x := _rest_x(_machoire)

	if flinching:
		head_x -= flinch_kick
	elif gait > 0.02:
		head_x += sin(_phase * 2.0) * deg_to_rad(4.0) * gait
	else:
		var overlay := _act_overlay()
		head_x += overlay.x
		head_y += overlay.y
		jaw_x += overlay.z

	_set_euler(_tete, Vector3(head_x, head_y, head_z))
	_set_euler(_machoire, Vector3(jaw_x, _rest_y(_machoire), _rest_z(_machoire)))


func _tick_idle_schedule(delta: float) -> void:
	if _act != IdleAct.NONE:
		_act_t += delta
		if _act_t >= _act_dur:
			_cancel_act()
			_next_act_in = _rng.randf_range(idle_act_min_gap, idle_act_max_gap)
		return
	_next_act_in -= delta
	if _next_act_in > 0.0:
		return
	_start_random_act()


func _start_random_act() -> void:
	var roll := _rng.randi_range(0, 3)
	match roll:
		0:
			_act = IdleAct.CHIRP
			_act_dur = chirp_duration
		1:
			_act = IdleAct.GLANCE
			_act_dur = glance_duration
			_act_sign = -1.0 if _rng.randf() < 0.5 else 1.0
		2:
			_act = IdleAct.LOOK_GROUND
			_act_dur = look_ground_duration
		_:
			_act = IdleAct.PECK
			_act_dur = peck_duration
	_act_t = 0.0


func _cancel_act() -> void:
	_act = IdleAct.NONE
	_act_t = 0.0
	_act_dur = 0.0


## Retourne Vector3(head_pitch, head_yaw, jaw_pitch) en radians, overlay ponctuel.
func _act_overlay() -> Vector3:
	if _act == IdleAct.NONE or _act_dur <= 0.001:
		return Vector3.ZERO
	var u := clampf(_act_t / _act_dur, 0.0, 1.0)
	match _act:
		IdleAct.CHIRP:
			var envelope := sin(u * PI)
			var flap := absf(sin(_act_t * chirp_rate * TAU * 0.5))
			return Vector3(0.0, 0.0, deg_to_rad(chirp_jaw_deg) * envelope * flap)
		IdleAct.GLANCE:
			var yaw_w := sin(u * PI)
			return Vector3(0.0, deg_to_rad(glance_yaw_deg) * _act_sign * yaw_w, 0.0)
		IdleAct.LOOK_GROUND:
			var hold := 1.0
			if u < 0.25:
				hold = u / 0.25
			elif u > 0.75:
				hold = 1.0 - (u - 0.75) / 0.25
			return Vector3(deg_to_rad(look_ground_pitch_deg) * hold, 0.0, 0.0)
		IdleAct.PECK:
			var dip := 0.0
			var jaw := 0.0
			if u < 0.35:
				dip = u / 0.35
				jaw = dip
			elif u < 0.5:
				dip = 1.0
				jaw = 1.0
			else:
				dip = 1.0 - (u - 0.5) / 0.5
				jaw = maxf(0.0, 1.0 - (u - 0.45) / 0.35)
			return Vector3(
				deg_to_rad(peck_pitch_deg) * dip,
				0.0,
				deg_to_rad(peck_jaw_deg) * jaw
			)
		_:
			return Vector3.ZERO


func _set_euler(part: Node3D, euler: Vector3) -> void:
	if part == null:
		return
	part.rotation = euler


func _rest_x(part: Node3D) -> float:
	return (_rest[part] as Vector3).x if _rest.has(part) else 0.0


func _rest_y(part: Node3D) -> float:
	return (_rest[part] as Vector3).y if _rest.has(part) else 0.0


func _rest_z(part: Node3D) -> float:
	return (_rest[part] as Vector3).z if _rest.has(part) else 0.0


func _find(part_name: String) -> Node3D:
	if _model == null:
		return null
	return _model.find_child(part_name, true, false) as Node3D
