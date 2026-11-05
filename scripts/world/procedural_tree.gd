extends RefCounted
class_name ProceduralTree

const TRUNK_SCENE := preload("res://assets/models/tronc_arbre.glb")
const FOLIAGE_01_SCENE := preload("res://assets/models/feuillage_01.glb")
const FOLIAGE_02_SCENE := preload("res://assets/models/feuillage_02.glb")

## Hauteur native du GLB tronc (Y=0 → Y=max), pivot à la base.
const TRUNK_HEIGHT := 0.8401
const TRUNK_RADIUS := 0.485
const FOLIAGE_MIN_Y := 1.0
const FOLIAGE_EXTENT := 1.02

static var _meshes_ready := false
static var _trunk_mesh: Mesh
static var _foliage_meshes: Array[Mesh] = []


static func ensure_meshes() -> void:
	if _meshes_ready:
		return
	_trunk_mesh = _extract_mesh(TRUNK_SCENE)
	_foliage_meshes = [
		_extract_mesh(FOLIAGE_01_SCENE),
		_extract_mesh(FOLIAGE_02_SCENE),
	]
	_meshes_ready = _trunk_mesh != null and _foliage_meshes.size() == 2


static func build(seed_value: int, stage: int, archetype: int = 0) -> Dictionary:
	ensure_meshes()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value as int
	stage = clampi(stage, 0, 3)
	archetype = posmod(archetype, 4)

	var trunk_xforms: Array[Transform3D] = []
	var foliage_a: Array[Transform3D] = []
	var foliage_b: Array[Transform3D] = []

	var trunk_segs := rng.randi_range(_stage_value(stage, 2, 3, 5, 7), _stage_value(stage, 3, 5, 7, 11))
	var primary_count := rng.randi_range(_stage_value(stage, 2, 3, 5, 8), _stage_value(stage, 4, 6, 9, 14))
	var secondary_count := rng.randi_range(_stage_value(stage, 0, 2, 4, 8), _stage_value(stage, 2, 5, 10, 16))
	var tip_foliage := rng.randi_range(_stage_value(stage, 3, 6, 9, 14), _stage_value(stage, 6, 11, 18, 28))

	match archetype:
		0: # étalé
			primary_count += rng.randi_range(1, 2)
			tip_foliage += rng.randi_range(2, 5)
		1: # dressé
			trunk_segs += rng.randi_range(0, 1)
			primary_count = maxi(primary_count - 1, 2)
		2: # asymétrique
			primary_count += rng.randi_range(0, 3)
		3: # buissonnant
			trunk_segs = maxi(trunk_segs - 1, 2)
			tip_foliage += rng.randi_range(3, 8)
			secondary_count += rng.randi_range(1, 4)

	var trunk_path: Array[Dictionary] = []
	_build_trunk(rng, trunk_segs, trunk_xforms, trunk_path)

	var branch_tips: Array[Vector3] = []
	_build_primary_branches(
		rng, stage, archetype, trunk_path, primary_count, trunk_xforms, foliage_a, foliage_b, branch_tips
	)
	_build_secondary_branches(
		rng, stage, archetype, trunk_path, branch_tips, secondary_count, trunk_xforms, foliage_a, foliage_b
	)
	_build_crown_foliage(rng, trunk_path, branch_tips, tip_foliage, foliage_a, foliage_b)

	var height := 0.0
	var reach := TRUNK_RADIUS
	for xf in trunk_xforms:
		height = maxf(height, xf.origin.y + absf(xf.basis.y.y) * TRUNK_HEIGHT)
		reach = maxf(reach, Vector2(xf.origin.x, xf.origin.z).length() + TRUNK_RADIUS * 0.85)
	for xf in foliage_a:
		height = maxf(height, xf.origin.y + FOLIAGE_EXTENT * 0.55)
		reach = maxf(reach, Vector2(xf.origin.x, xf.origin.z).length() + FOLIAGE_EXTENT * 0.62)
	for xf in foliage_b:
		height = maxf(height, xf.origin.y + FOLIAGE_EXTENT * 0.55)
		reach = maxf(reach, Vector2(xf.origin.x, xf.origin.z).length() + FOLIAGE_EXTENT * 0.62)

	var root := Node3D.new()
	root.name = "ProceduralTreeVisual"
	fill_visual(root, trunk_xforms, foliage_a, foliage_b)

	return {
		"root": root,
		"reach": reach,
		"height": height,
		"trunk_height": maxf(height * 0.72, TRUNK_HEIGHT * float(trunk_segs) * 0.85),
		"trunk_radius": TRUNK_RADIUS * rng.randf_range(0.72, 0.92),
		"trunk_xforms": trunk_xforms,
		"foliage_a": foliage_a,
		"foliage_b": foliage_b,
		"trunk_path_count": trunk_segs,
	}


static func fill_visual(
	root: Node3D,
	trunk_xforms: Array[Transform3D],
	foliage_a: Array[Transform3D],
	foliage_b: Array[Transform3D]
) -> void:
	ensure_meshes()
	while root.get_child_count() > 0:
		root.get_child(0).free()
	if _trunk_mesh != null and not trunk_xforms.is_empty():
		root.add_child(_make_multimesh("tronc_arbre", _trunk_mesh, trunk_xforms))
	if _foliage_meshes.size() > 0 and not foliage_a.is_empty():
		root.add_child(_make_multimesh("feuillage_01", _foliage_meshes[0], foliage_a))
	if _foliage_meshes.size() > 1 and not foliage_b.is_empty():
		root.add_child(_make_multimesh("feuillage_02", _foliage_meshes[1], foliage_b))


static func trunk_mesh() -> Mesh:
	ensure_meshes()
	return _trunk_mesh


static func segment_mid(xf: Transform3D) -> Vector3:
	return xf.origin + xf.basis.y * (TRUNK_HEIGHT * 0.5)


static func segment_tip(xf: Transform3D) -> Vector3:
	return xf.origin + xf.basis.y * TRUNK_HEIGHT


static func _stage_value(stage: int, a: int, b: int, c: int, d: int) -> int:
	match clampi(stage, 0, 3):
		0:
			return a
		1:
			return b
		2:
			return c
		_:
			return d


static func _extract_mesh(scene: PackedScene) -> Mesh:
	var root := scene.instantiate()
	var mesh: Mesh = null
	if root is MeshInstance3D:
		mesh = (root as MeshInstance3D).mesh
	if mesh == null:
		for node in root.find_children("*", "MeshInstance3D", true, false):
			var mesh_node := node as MeshInstance3D
			if mesh_node != null and mesh_node.mesh != null:
				mesh = mesh_node.mesh
				break
	root.free()
	return mesh


static func _make_multimesh(mesh_name: String, mesh: Mesh, xforms: Array[Transform3D]) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = xforms.size()
	for i in xforms.size():
		multi.set_instance_transform(i, xforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = mesh_name
	instance.multimesh = multi
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return instance


static func _basis_along_y(direction: Vector3) -> Basis:
	var y := direction.normalized()
	if y.length_squared() < 0.0001:
		y = Vector3.UP
	var reference := Vector3.RIGHT if absf(y.dot(Vector3.UP)) > 0.92 else Vector3.UP
	var x := reference.cross(y).normalized()
	if x.length_squared() < 0.0001:
		x = Vector3.FORWARD.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


static func _build_trunk(
	rng: RandomNumberGenerator,
	seg_count: int,
	trunk_xforms: Array[Transform3D],
	trunk_path: Array[Dictionary]
) -> void:
	var pos := Vector3.ZERO
	var basis := Basis.IDENTITY
	for i in seg_count:
		var twist := rng.randf_range(-0.18, 0.18)
		var seg_basis := basis.rotated(basis.y, twist)
		trunk_xforms.append(Transform3D(seg_basis, pos))
		trunk_path.append({"origin": pos, "basis": seg_basis, "index": i})
		pos += seg_basis.y * TRUNK_HEIGHT
		if i >= seg_count - 1:
			break
		# Lean plafonné pour les longs troncs (évite les silhouettes de 12 m+).
		var lean_max := lerpf(3.6, 1.6, clampf(float(i) / 8.0, 0.0, 1.0))
		var lean := deg_to_rad(rng.randf_range(0.35, lean_max))
		var yaw := rng.randf() * TAU
		var axis := (seg_basis.x * cos(yaw) + seg_basis.z * sin(yaw)).normalized()
		basis = seg_basis.rotated(axis, lean)


static func _sample_trunk(trunk_path: Array[Dictionary], t: float) -> Dictionary:
	var count := trunk_path.size()
	if count == 0:
		return {"origin": Vector3.ZERO, "basis": Basis.IDENTITY}
	var clamped := clampf(t, 0.0, 0.999)
	var scaled := clamped * float(count)
	var idx := mini(int(scaled), count - 1)
	var local_t := scaled - float(idx)
	var sample: Dictionary = trunk_path[idx]
	var origin: Vector3 = sample["origin"]
	var basis: Basis = sample["basis"]
	return {
		"origin": origin + basis.y * (local_t * TRUNK_HEIGHT),
		"basis": basis,
	}


static func _build_primary_branches(
	rng: RandomNumberGenerator,
	stage: int,
	archetype: int,
	trunk_path: Array[Dictionary],
	count: int,
	trunk_xforms: Array[Transform3D],
	foliage_a: Array[Transform3D],
	foliage_b: Array[Transform3D],
	branch_tips: Array[Vector3]
) -> void:
	if trunk_path.is_empty() or count <= 0:
		return
	var used_angles: Array[float] = []
	for _i in count:
		# Branches / feuillage surtout au-dessus d'environ 1 m.
		var t_min := 0.42 if stage > 0 else 0.52
		var t := rng.randf_range(t_min, 0.97)
		var sample := _sample_trunk(trunk_path, t)
		var origin: Vector3 = sample["origin"]
		if origin.y < FOLIAGE_MIN_Y * 0.75:
			continue
		var trunk_basis: Basis = sample["basis"]
		var ang := _next_branch_angle(rng, used_angles, archetype)
		used_angles.append(ang)
		var elev := _branch_elevation(rng, archetype, true)
		var outward := (trunk_basis.x * cos(ang) + trunk_basis.z * sin(ang)).normalized()
		var branch_dir := (outward * cos(elev) + trunk_basis.y * sin(elev)).normalized()
		var max_segs := _stage_value(stage, 1, 2, 3, 4)
		if archetype == 1:
			max_segs = maxi(max_segs - 1, 1)
		if archetype == 0:
			max_segs += 1
		var segs := rng.randi_range(1, max_segs)
		# Branches hautes un peu plus courtes / « fines » (moins de segments).
		if t > 0.78:
			segs = mini(segs, maxi(max_segs - 1, 1))
		var tip := _emit_branch(
			rng, origin, trunk_basis.y, outward, branch_dir, segs, true, trunk_xforms, foliage_a, foliage_b
		)
		if tip.y >= FOLIAGE_MIN_Y:
			branch_tips.append(tip)


static func _build_secondary_branches(
	rng: RandomNumberGenerator,
	stage: int,
	archetype: int,
	trunk_path: Array[Dictionary],
	branch_tips: Array[Vector3],
	count: int,
	trunk_xforms: Array[Transform3D],
	foliage_a: Array[Transform3D],
	foliage_b: Array[Transform3D]
) -> void:
	if count <= 0:
		return
	var sources: Array[Vector3] = branch_tips.duplicate()
	for tip in branch_tips:
		var mid := Vector3(tip.x * 0.62, tip.y * rng.randf_range(0.55, 0.9), tip.z * 0.62)
		sources.append(mid)
	if sources.is_empty():
		for _j in mini(count, 3):
			var sample := _sample_trunk(trunk_path, rng.randf_range(0.55, 0.95))
			sources.append(sample["origin"])
	for _i in count:
		if sources.is_empty():
			break
		var origin: Vector3 = sources[rng.randi_range(0, sources.size() - 1)]
		if origin.y < FOLIAGE_MIN_Y:
			continue
		var up := Vector3.UP
		var outward := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0))
		if outward.length_squared() < 0.01:
			outward = Vector3.RIGHT
		outward = outward.normalized()
		var elev := _branch_elevation(rng, archetype, false)
		var branch_dir := (outward * cos(elev) + up * sin(elev)).normalized()
		var segs := 1 if stage < 2 else rng.randi_range(1, 2)
		_emit_branch(rng, origin, up, outward, branch_dir, segs, false, trunk_xforms, foliage_a, foliage_b)


static func _build_crown_foliage(
	rng: RandomNumberGenerator,
	trunk_path: Array[Dictionary],
	branch_tips: Array[Vector3],
	count: int,
	foliage_a: Array[Transform3D],
	foliage_b: Array[Transform3D]
) -> void:
	var anchors: Array[Vector3] = []
	for tip in branch_tips:
		anchors.append(tip)
	if not trunk_path.is_empty():
		var top: Dictionary = trunk_path[trunk_path.size() - 1]
		var top_origin: Vector3 = top["origin"]
		var top_basis: Basis = top["basis"]
		anchors.append(top_origin + top_basis.y * TRUNK_HEIGHT)
		for _k in 3:
			var sample := _sample_trunk(trunk_path, rng.randf_range(0.62, 0.98))
			var o: Vector3 = sample["origin"]
			if o.y >= FOLIAGE_MIN_Y:
				anchors.append(o)
	if anchors.is_empty():
		return
	for i in count:
		var base: Vector3 = anchors[rng.randi_range(0, anchors.size() - 1)]
		var jitter := Vector3(
			rng.randf_range(-0.55, 0.55),
			rng.randf_range(-0.25, 0.55),
			rng.randf_range(-0.55, 0.55)
		)
		# Évite une couronne sphérique : biais radial irrégulier + clusters irréguliers.
		if rng.randf() < 0.35:
			jitter *= rng.randf_range(1.1, 1.7)
		var pos := base + jitter
		if pos.y < FOLIAGE_MIN_Y:
			pos.y = FOLIAGE_MIN_Y + rng.randf_range(0.05, 0.35)
		_add_foliage(rng, pos, foliage_a, foliage_b)
		if rng.randf() < 0.28:
			_add_foliage(
				rng,
				pos + Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.15, 0.35), rng.randf_range(-0.4, 0.4)),
				foliage_a,
				foliage_b
			)


static func _emit_branch(
	rng: RandomNumberGenerator,
	attach: Vector3,
	trunk_up: Vector3,
	outward: Vector3,
	branch_dir: Vector3,
	segs: int,
	primary: bool,
	trunk_xforms: Array[Transform3D],
	foliage_a: Array[Transform3D],
	foliage_b: Array[Transform3D]
) -> Vector3:
	var dir := branch_dir.normalized()
	var pos := attach + outward * (TRUNK_RADIUS * rng.randf_range(0.18, 0.42))
	var tip := pos
	for i in segs:
		var twist := rng.randf_range(-0.45, 0.45)
		var basis := _basis_along_y(dir).rotated(dir, twist)
		trunk_xforms.append(Transform3D(basis, pos))
		tip = pos + dir * TRUNK_HEIGHT
		pos = tip
		# Légère courbure / fléchissement vers le bas du tronc local.
		var droop := rng.randf_range(0.03, 0.12) if primary else rng.randf_range(0.05, 0.16)
		dir = (dir - trunk_up.normalized() * droop).normalized()
		if i == segs - 1 or (primary and i == segs - 2 and segs > 1):
			if tip.y >= FOLIAGE_MIN_Y:
				_add_foliage(rng, tip + dir * rng.randf_range(0.1, 0.35), foliage_a, foliage_b)
				if primary and rng.randf() < 0.55:
					_add_foliage(
						rng,
						tip + Vector3(rng.randf_range(-0.35, 0.35), rng.randf_range(0.0, 0.4), rng.randf_range(-0.35, 0.35)),
						foliage_a,
						foliage_b
					)
	return tip


static func _add_foliage(
	rng: RandomNumberGenerator,
	pos: Vector3,
	foliage_a: Array[Transform3D],
	foliage_b: Array[Transform3D]
) -> void:
	if pos.y < FOLIAGE_MIN_Y:
		return
	var basis := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU))
	# Pas de scale : dimensions natives des GLB.
	var xf := Transform3D(basis, pos)
	if (foliage_a.size() + foliage_b.size()) % 2 == 0:
		if rng.randf() < 0.52:
			foliage_a.append(xf)
		else:
			foliage_b.append(xf)
	else:
		if foliage_a.size() <= foliage_b.size():
			foliage_a.append(xf)
		else:
			foliage_b.append(xf)


static func _next_branch_angle(rng: RandomNumberGenerator, used: Array[float], archetype: int) -> float:
	if archetype == 2 and rng.randf() < 0.45:
		# Cluster asymétrique : favorise un secteur.
		var side := 0.0 if rng.randf() < 0.5 else PI
		return side + rng.randf_range(-0.9, 0.9)
	for _attempt in 12:
		var ang := rng.randf() * TAU
		var ok := true
		for other in used:
			var delta := absf(angle_difference(ang, other))
			if delta < 0.45:
				ok = false
				break
		if ok:
			return ang
	return rng.randf() * TAU


static func _branch_elevation(rng: RandomNumberGenerator, archetype: int, primary: bool) -> float:
	# 0 = horizontal, PI/2 = vertical vers le haut.
	var lo := 0.18
	var hi := 0.72
	match archetype:
		0:
			lo = 0.08
			hi = 0.48
		1:
			lo = 0.35
			hi = 0.85
		2:
			lo = 0.12
			hi = 0.78
		3:
			lo = 0.15
			hi = 0.55
	if not primary:
		lo *= 0.85
		hi = minf(hi, 0.62)
	return rng.randf_range(lo, hi)
