extends Node
class_name AstraGrazerAnim

## Animation procédurale quadrupède pour buffalo_verdo.
## Axes modèle (avant yaw mount) : avant = +X, haut = +Y, droite = +Z.
## Origine de chaque mesh = pivot ; swing jambe = rotation locale Z (plan X/Y).

@export var walk_hz: float = 1.35
@export var flee_hz: float = 2.35
@export var leg_amp_deg: float = 22.0
@export var flee_leg_amp_deg: float = 30.0
@export var body_pitch_deg: float = 2.8
@export var body_roll_deg: float = 2.0
@export var head_nod_deg: float = 5.0
@export var head_yaw_deg: float = 3.5
@export var tail_wag_deg: float = 12.0
@export var idle_head_deg: float = 1.5
@export var flinch_pitch_deg: float = 8.0
@export var blend_speed: float = 10.0

var _model: Node3D
var _corps: Node3D
var _tete: Node3D
var _queue: Node3D
var _leg_fl: Node3D
var _leg_fr: Node3D
var _leg_bl: Node3D
var _leg_br: Node3D

var _rest: Dictionary = {}
var _phase: float = 0.0
var _weight: float = 0.0
var _flinch_t: float = 0.0
var _flinch_max: float = 0.18
var _ready_ok := false


func setup(model_root: Node3D) -> void:
	_model = model_root
	if _model == null:
		return
	_corps = _find("corps")
	_tete = _find("tete")
	_queue = _find("queue")
	_leg_fl = _find("jambe_avant_gauche")
	_leg_fr = _find("jambe_avant_droite")
	_leg_bl = _find("jambe_arriere_gauche")
	_leg_br = _find("jambe_arriere_droite")
	for part in [_corps, _tete, _queue, _leg_fl, _leg_fr, _leg_bl, _leg_br]:
		if part != null:
			_rest[part] = part.rotation
	_ready_ok = _corps != null and _leg_fl != null and _leg_fr != null and _leg_bl != null and _leg_br != null


func trigger_flinch(duration: float) -> void:
	_flinch_max = maxf(duration, 0.05)
	_flinch_t = _flinch_max


func tick(delta: float, moving: bool, fleeing: bool, speed_ratio: float) -> void:
	if not _ready_ok:
		return
	_flinch_t = maxf(_flinch_t - delta, 0.0)
	var flinching := _flinch_t > 0.0
	var target_w := 0.0
	if moving and not flinching:
		target_w = clampf(speed_ratio, 0.0, 1.35)
	_weight = move_toward(_weight, target_w, blend_speed * delta)

	var hz := flee_hz if fleeing else walk_hz
	if _weight > 0.02:
		_phase = fmod(_phase + TAU * hz * delta * maxf(_weight, 0.35), TAU)
	elif not flinching:
		_phase = lerp_angle(_phase, 0.0, 4.0 * delta)

	var leg_amp := deg_to_rad(flee_leg_amp_deg if fleeing else leg_amp_deg) * _weight
	# Alternance diagonale : FL+BR / FR+BL
	var swing_a := sin(_phase) * leg_amp
	var swing_b := sin(_phase + PI) * leg_amp
	_set_leg(_leg_fl, swing_a)
	_set_leg(_leg_br, swing_a)
	_set_leg(_leg_fr, swing_b)
	_set_leg(_leg_bl, swing_b)

	# Pitch/roll corps uniquement en déplacement (évite le tremblement vertical à l'arrêt).
	var gait := clampf(_weight, 0.0, 1.0)
	var body_pitch := sin(_phase * 2.0) * deg_to_rad(body_pitch_deg) * gait
	var body_roll := sin(_phase) * deg_to_rad(body_roll_deg) * gait

	var flinch_kick := 0.0
	if flinching:
		var u := 1.0 - (_flinch_t / _flinch_max)
		flinch_kick = sin(u * PI) * deg_to_rad(flinch_pitch_deg)

	_apply_rot(_corps, Vector3(
		_rest_x(_corps) + body_roll,
		_rest_y(_corps),
		_rest_z(_corps) + body_pitch - flinch_kick
	))

	if flinching:
		_apply_rot(_tete, Vector3(
			_rest_x(_tete),
			_rest_y(_tete),
			_rest_z(_tete) - flinch_kick * 1.25
		))
	elif gait > 0.02:
		var head_nod := sin(_phase * 2.0 + 0.4) * deg_to_rad(head_nod_deg) * gait
		var head_yaw := sin(_phase * 0.5) * deg_to_rad(head_yaw_deg) * gait
		_apply_rot(_tete, Vector3(
			_rest_x(_tete),
			_rest_y(_tete) + head_yaw,
			_rest_z(_tete) + head_nod
		))
	else:
		# Idle : micro yaw tête seulement (pas de pitch corps = pas de bob vertical).
		var idle_yaw := sin(Time.get_ticks_msec() * 0.0011) * deg_to_rad(idle_head_deg)
		_apply_rot(_tete, Vector3(_rest_x(_tete), _rest_y(_tete) + idle_yaw, _rest_z(_tete)))

	var wag := 0.0
	if flinching:
		wag = 0.0
	elif gait > 0.02:
		wag = sin(_phase * 2.0 + 1.1) * deg_to_rad(tail_wag_deg) * maxf(gait, 0.25)
	else:
		wag = sin(Time.get_ticks_msec() * 0.0022) * deg_to_rad(tail_wag_deg) * 0.28
	# Queue le long -X : wag latéral = rotation locale Y uniquement (pas de pitch).
	_apply_rot(_queue, Vector3(
		_rest_x(_queue),
		_rest_y(_queue) + wag,
		_rest_z(_queue)
	))


func _set_leg(leg: Node3D, swing_z: float) -> void:
	if leg == null:
		return
	_apply_rot(leg, Vector3(_rest_x(leg), _rest_y(leg), _rest_z(leg) + swing_z))


func _apply_rot(part: Node3D, euler: Vector3) -> void:
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
