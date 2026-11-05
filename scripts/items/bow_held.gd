extends Node3D

## Arc tenu : bandage procédural sur pivots Blender (manche ±Z, cordes).
## Nœuds : bas_manche_arc, centre_manche_arc, haut_manche_arc, corde_bas, corde_haut.

const ARROW_SCENE := preload("res://assets/models/wooden_arrow.glb")

@export var limb_bend_deg: float = 18.0
@export var string_pull: float = 0.12

var _model: Node3D
var _haut: Node3D
var _bas: Node3D
var _centre: Node3D
var _corde_haut: Node3D
var _corde_bas: Node3D
var _rest: Dictionary = {}
var _nocked: Node3D
var _draw := 0.0
var _aim_aligned := false


func _ready() -> void:
	_model = get_node_or_null(^"Model") as Node3D
	_cache_parts()
	set_draw(0.0)


func set_draw(amount: float) -> void:
	_draw = clampf(amount, 0.0, 1.0)
	if _haut == null:
		_cache_parts()
	var bend := deg_to_rad(limb_bend_deg) * _draw
	if _haut != null:
		_haut.rotation = _rest_of(_haut) + Vector3(0.0, 0.0, bend)
	if _bas != null:
		_bas.rotation = _rest_of(_bas) + Vector3(0.0, 0.0, -bend)
	var pull := Vector3(-string_pull * _draw, 0.0, 0.0)
	if _corde_haut != null:
		_corde_haut.position = _rest_pos(_corde_haut) + pull
		_corde_haut.scale = Vector3(1.0, 1.0 - 0.08 * _draw, 1.0)
	if _corde_bas != null:
		_corde_bas.position = _rest_pos(_corde_bas) + pull
		_corde_bas.scale = Vector3(1.0, 1.0 - 0.08 * _draw, 1.0)
	_update_nocked_arrow()


func show_nocked_arrow(show: bool) -> void:
	if show:
		_ensure_nocked()
		if _nocked != null:
			_nocked.visible = true
		_update_nocked_arrow()
	elif _nocked != null:
		_nocked.visible = false


func clear_nocked_arrow() -> void:
	if _nocked != null:
		_nocked.queue_free()
		_nocked = null


func muzzle_global() -> Vector3:
	if _centre == null:
		_cache_parts()
	if _centre != null:
		return _centre.global_position
	if _model != null:
		return _model.global_position
	return global_position


func align_to_shot(world_dir: Vector3, up: Vector3) -> void:
	## Oriente l’arc pour que l’axe de tir modèle (+X mesh → +Z local) suive le tir.
	var dir := world_dir.normalized()
	if dir.length_squared() < 0.001:
		return
	var world_up := up.normalized() if up.length_squared() > 0.001 else Vector3.UP
	var shoot_local := _shot_axis_local()
	var basis := _basis_aligning(shoot_local, dir, world_up)
	global_transform = Transform3D(basis, global_position)
	_aim_aligned = true


func clear_aim_align() -> void:
	if not _aim_aligned:
		return
	transform = Transform3D.IDENTITY
	_aim_aligned = false


func orient_nocked(world_dir: Vector3, up: Vector3) -> void:
	_update_nocked_arrow()
	if _nocked == null or not _nocked.visible:
		return
	var dir := world_dir.normalized()
	if dir.length_squared() < 0.001:
		return
	var world_up := up.normalized() if up.length_squared() > 0.001 else Vector3.UP
	var origin := _nocked.global_position
	var right := dir.cross(world_up)
	if right.length_squared() < 0.0001:
		right = dir.cross(Vector3.RIGHT)
	right = right.normalized()
	# Modèle : pointe en −Y, empennage en +Y → axe Y local = −direction de tir.
	var basis_y := -dir
	var basis_z := right.cross(basis_y).normalized()
	var basis_x := basis_y.cross(basis_z).normalized()
	_nocked.global_transform = Transform3D(Basis(basis_x, basis_y, basis_z), origin)


func _shot_axis_local() -> Vector3:
	# Mesh : tir le long de +X ; Model mappe +X → +Z du nœud arc.
	if _model != null:
		var axis := (_model.transform.basis * Vector3.RIGHT).normalized()
		if axis.length_squared() > 0.001:
			return axis
	return Vector3.FORWARD


func _basis_aligning(local_axis: Vector3, world_dir: Vector3, world_up: Vector3) -> Basis:
	var axis := local_axis.normalized()
	var dir := world_dir.normalized()
	var up := world_up.normalized()
	if absf(axis.dot(Vector3.FORWARD)) > 0.99:
		# local +Z → world dir.
		var right := up.cross(dir)
		if right.length_squared() < 0.0001:
			right = Vector3.RIGHT.cross(dir)
		right = right.normalized()
		var basis_y := dir.cross(right).normalized()
		return Basis(right, basis_y, dir)
	# Align arbitrary local_axis to dir via from-to, then twist so local +Y ≈ up.
	var rot := Quaternion(axis, dir)
	var basis := Basis(rot)
	var local_y := basis * Vector3.UP
	var desired_y := (up - dir * up.dot(dir))
	if desired_y.length_squared() > 0.0001 and local_y.length_squared() > 0.0001:
		desired_y = desired_y.normalized()
		var twist := Quaternion(local_y.normalized(), desired_y)
		basis = Basis(twist) * basis
	return basis


func _update_nocked_arrow() -> void:
	if _nocked == null or not _nocked.visible:
		return
	var mid_y := 0.0
	if _corde_haut != null and _corde_bas != null:
		mid_y = (_corde_haut.position.y + _corde_bas.position.y) * 0.5
	# Corde modèle en −X ; pointe (−Y) → +X (opposé à la corde) via rot Z +90°.
	_nocked.position = Vector3(-0.22 - string_pull * _draw, mid_y, 0.0)
	_nocked.rotation_degrees = Vector3(0.0, 0.0, 90.0)


func _ensure_nocked() -> void:
	if _nocked != null and is_instance_valid(_nocked):
		return
	var visual := ARROW_SCENE.instantiate() as Node3D
	if visual == null:
		return
	visual.name = "NockedArrow"
	visual.scale = Vector3.ONE * 0.95
	var parent: Node = _model if _model != null else self
	parent.add_child(visual)
	_nocked = visual


func _cache_parts() -> void:
	if _model == null:
		_model = get_node_or_null(^"Model") as Node3D
	_haut = find_child("haut_manche_arc", true, false) as Node3D
	_bas = find_child("bas_manche_arc", true, false) as Node3D
	_centre = find_child("centre_manche_arc", true, false) as Node3D
	_corde_haut = find_child("corde_haut", true, false) as Node3D
	_corde_bas = find_child("corde_bas", true, false) as Node3D
	for part in [_haut, _bas, _corde_haut, _corde_bas]:
		if part == null:
			continue
		_rest[part] = {"rot": part.rotation, "pos": part.position}


func _rest_of(part: Node3D) -> Vector3:
	if _rest.has(part):
		return (_rest[part] as Dictionary).get("rot", Vector3.ZERO)
	return Vector3.ZERO


func _rest_pos(part: Node3D) -> Vector3:
	if _rest.has(part):
		return (_rest[part] as Dictionary).get("pos", part.position)
	return part.position
