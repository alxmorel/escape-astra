extends RefCounted
class_name TrunkSegmentBounce

## Léger squash visuel sur l'instance MultiMesh `tronc_arbre` frappée.
const SQUASH := Vector3(1.06, 0.92, 1.06)
const IN_TIME := 0.05
const OUT_TIME := 0.08

var _tween: Tween
var _mm_idx := -1
var _base := Transform3D.IDENTITY
var _mmi: MultiMeshInstance3D


func play(
	host: Node,
	visual: Node3D,
	trunk_xforms: Array[Transform3D],
	alive: Array[bool],
	idx: int
) -> void:
	if host == null or visual == null or idx < 0 or idx >= trunk_xforms.size():
		return
	var mmi := visual.get_node_or_null(^"tronc_arbre") as MultiMeshInstance3D
	if mmi == null or mmi.multimesh == null:
		return
	var mm_idx := visual_index_of(alive, idx)
	if mm_idx < 0 or mm_idx >= mmi.multimesh.instance_count:
		return
	clear()
	_mmi = mmi
	_mm_idx = mm_idx
	_base = trunk_xforms[idx]
	_tween = host.create_tween()
	_tween.tween_method(_set_amount, 0.0, 1.0, IN_TIME)
	_tween.tween_method(_set_amount, 1.0, 0.0, OUT_TIME)


func clear() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	if _mm_idx >= 0 and _mmi != null and is_instance_valid(_mmi) and _mmi.multimesh != null:
		if _mm_idx < _mmi.multimesh.instance_count:
			_mmi.multimesh.set_instance_transform(_mm_idx, _base)
	_mm_idx = -1
	_mmi = null


static func visual_index_of(alive: Array[bool], idx: int) -> int:
	var visual_i := 0
	for i in alive.size():
		if not alive[i]:
			continue
		if i == idx:
			return visual_i
		visual_i += 1
	return -1


func _set_amount(amount: float) -> void:
	if _mmi == null or not is_instance_valid(_mmi) or _mmi.multimesh == null:
		return
	if _mm_idx < 0 or _mm_idx >= _mmi.multimesh.instance_count:
		return
	var scale := Vector3(
		lerpf(1.0, SQUASH.x, amount),
		lerpf(1.0, SQUASH.y, amount),
		lerpf(1.0, SQUASH.z, amount)
	)
	_mmi.multimesh.set_instance_transform(
		_mm_idx,
		Transform3D(_base.basis.scaled(scale), _base.origin)
	)
