extends Node3D

const FARM := preload("res://scripts/farming/farming_config.gd")
const DROPS := preload("res://scripts/farming/drops.gd")

var cell := Vector3i.ZERO
var crop_id := ""
var planted_at := -1.0

var _crop: Node3D
var _soil: MeshInstance3D
var _shape: CollisionShape3D
var _material: StandardMaterial3D
var _tris := PackedVector3Array()
var _shown := -2
var _soil_ready := false
var _anchored := false
var _bound := false
const PAD_VERSION := 5
var ground_radius := 0.0
var _pad_version := 0
var _face_normal := Vector3.UP


func _ready() -> void:
	add_to_group(&"farm_plot")
	_crop = Node3D.new()
	_crop.name = "Crop"
	add_child(_crop)
	_soil = MeshInstance3D.new()
	_soil.name = "Soil"
	_soil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.45, 0.28, 0.12)
	_material.roughness = 1.0
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_soil.material_override = _material
	add_child(_soil)
	var body := StaticBody3D.new()
	body.collision_layer = 8
	body.collision_mask = 0
	_shape = CollisionShape3D.new()
	body.add_child(_shape)
	add_child(body)


func _exit_tree() -> void:
	if not _bound:
		return
	var farming := get_parent()
	if farming != null and farming.has_method(&"release_cell"):
		farming.call(&"release_cell", cell)


func soil_ready() -> bool:
	return _soil_ready


func bind_cell(next: Vector3i) -> void:
	cell = next
	_bound = true


func bind(next: Vector3i, tris: PackedVector3Array, anchor: Vector3, up: Vector3) -> void:
	cell = next
	_bound = true
	refresh_soil()
	if not _soil_ready:
		_set_anchor(anchor, up)


func apply_level(radius: float, normal: Vector3) -> void:
	ground_radius = radius
	_face_normal = normal.normalized()
	var planet := _planet()
	if planet == null:
		return
	_pad_version = PAD_VERSION
	var volume := planet.get_node_or_null(^"TerrainVolume")
	if volume != null and volume.has_method(&"flatten_plot"):
		volume.call(&"flatten_plot", cell, radius, _face_normal)
	var seat := _apply_mesh(planet)
	_set_anchor(seat, _face_normal)
	_soil_ready = true


func refresh_soil() -> void:
	if _pad_version == PAD_VERSION and ground_radius > 0.0:
		return
	var farming := get_parent()
	if farming != null and farming.has_method(&"level_patch"):
		farming.call(&"level_patch", cell)


func is_empty() -> bool:
	return crop_id.is_empty()


func is_mature() -> bool:
	return FARM.is_mature(crop_id, planted_at, SaveManager.play_time)


func plant(id: String) -> bool:
	if not is_empty() or not FARM.crop_known(id):
		return false
	crop_id = id
	planted_at = SaveManager.play_time
	_shown = -2
	sync_growth()
	return true


func harvest() -> void:
	if not is_mature():
		return
	DROPS.spawn_list(_drop_origin(), _drop_up(), FARM.crop_drops(crop_id), self)
	_clear_crop()


func import_crop(id: String, at: float) -> void:
	if id.is_empty() or not FARM.crop_known(id):
		_clear_crop()
		return
	crop_id = id
	planted_at = at
	_shown = -2
	sync_growth()


func sync_growth() -> void:
	if _crop == null:
		return
	var stage := -1
	if not crop_id.is_empty():
		stage = FARM.stage_index(crop_id, planted_at, SaveManager.play_time)
	if stage == _shown:
		return
	_shown = stage
	var previous: Array = _crop.get_children()
	for child in previous:
		_crop.remove_child(child)
		child.free()
	if stage < 0:
		return
	var scene := FARM.stage_scene(crop_id, stage)
	if scene == null:
		return
	var visual := scene.instantiate()
	visual.name = "Visual"
	_crop.add_child(visual)


func demolish() -> void:
	_release_contents()
	var farming := get_parent()
	if farming != null and farming.has_method(&"release_cell"):
		farming.call(&"release_cell", cell)
	_bound = false
	queue_free()


func aim_distance(origin: Vector3, direction: Vector3, max_distance: float) -> float:
	var planet := _planet()
	if planet == null:
		return max_distance
	var dir := direction.normalized()
	if dir.length_squared() < 0.001:
		return max_distance
	var local_origin := planet.to_local(origin)
	var local_dir := planet.global_transform.basis.inverse() * dir
	if local_dir.length_squared() < 0.0001:
		return max_distance
	local_dir = local_dir.normalized()
	if not _tris.is_empty():
		var best := max_distance
		var count := int(_tris.size() / 3)
		for i in count:
			var hit := _ray_tri(local_origin, local_dir, _tris[i * 3], _tris[i * 3 + 1], _tris[i * 3 + 2], best)
			if hit >= 0.0:
				best = hit
		return best
	var box_min := Vector3(cell) * FARM.CELL
	var box_max := box_min + Vector3.ONE * FARM.CELL
	return _ray_aabb(local_origin, local_dir, box_min, box_max, max_distance)


func set_highlighted(enabled: bool) -> void:
	if _material == null:
		return
	_material.emission_enabled = enabled
	_material.emission = Color(1.0, 0.86, 0.35)
	_material.emission_energy_multiplier = 0.55 if enabled else 0.0


func _clear_crop() -> void:
	crop_id = ""
	planted_at = -1.0
	_shown = -2
	sync_growth()


func _release_contents() -> void:
	if crop_id.is_empty():
		return
	if is_mature():
		DROPS.spawn_list(_drop_origin(), _drop_up(), FARM.crop_drops(crop_id), self)
	else:
		DROPS.spawn_drop(_drop_origin(), _drop_up(), "wheat_seeds", 1, self)
	crop_id = ""
	planted_at = -1.0


func _apply_mesh(planet: Node3D) -> Vector3:
	var normal := _face_normal.normalized()
	if normal.length_squared() < 0.01:
		normal = (Vector3(cell) + Vector3.ONE * 0.5).normalized()
		_face_normal = normal
	var halves: Array = FARM.tangent_halves(normal)
	var half_u: Vector3 = halves[0]
	var half_v: Vector3 = halves[1]
	var lift := FARM.cell_on_plane(cell, normal, ground_radius) + normal * 0.03
	var p00 := lift - half_u - half_v
	var p10 := lift + half_u - half_v
	var p11 := lift + half_u + half_v
	var p01 := lift - half_u + half_v
	if (p10 - p00).cross(p01 - p00).dot(normal) < 0.0:
		var swap := p10
		p10 = p01
		p01 = swap
	var faces := PackedVector3Array()
	faces.append(p00)
	faces.append(p10)
	faces.append(p11)
	faces.append(p00)
	faces.append(p11)
	faces.append(p01)
	_tris = faces
	var local := PackedVector3Array()
	local.resize(faces.size())
	for i in faces.size():
		local[i] = to_local(planet.to_global(faces[i]))
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.add_vertex(local[0])
	tool.add_vertex(local[1])
	tool.add_vertex(local[2])
	tool.add_vertex(local[3])
	tool.add_vertex(local[4])
	tool.add_vertex(local[5])
	tool.generate_normals()
	_soil.mesh = tool.commit()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(local)
	_shape.shape = shape
	return lift


func _set_anchor(anchor: Vector3, up: Vector3) -> void:
	var planet := _planet()
	if planet == null or _crop == null:
		return
	var y := up.normalized()
	if y.length_squared() < 0.01:
		y = anchor.normalized()
	_anchored = true
	var basis := planet.global_transform.basis * _basis_from_up(y)
	_crop.global_transform = Transform3D(basis, planet.to_global(anchor))


func _drop_origin() -> Vector3:
	if _anchored and _crop != null:
		return _crop.global_position
	var planet := _planet()
	if planet == null:
		return global_position
	var center := Vector3(cell) * FARM.CELL + Vector3.ONE * (FARM.CELL * 0.5)
	return planet.to_global(center)


func _drop_up() -> Vector3:
	if _anchored and _crop != null:
		return _crop.global_basis.y
	return _drop_origin().normalized()


func _planet() -> Node3D:
	var node := get_parent()
	while node != null:
		if node.get_node_or_null(^"TerrainVolume") != null:
			return node as Node3D
		node = node.get_parent()
	return null


func _centroid(tris: PackedVector3Array) -> Vector3:
	var count := int(tris.size() / 3)
	if count == 0:
		return Vector3(cell) * FARM.CELL + Vector3.ONE * (FARM.CELL * 0.5)
	var acc := Vector3.ZERO
	for i in count:
		acc += (tris[i * 3] + tris[i * 3 + 1] + tris[i * 3 + 2]) / 3.0
	return acc / float(count)


func _basis_from_up(up: Vector3) -> Basis:
	var y := up.normalized()
	var reference := Vector3.FORWARD if absf(y.dot(Vector3.UP)) > 0.99 else Vector3.UP
	var x := reference.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _ray_tri(origin: Vector3, dir: Vector3, a: Vector3, b: Vector3, c: Vector3, max_distance: float) -> float:
	var edge1 := b - a
	var edge2 := c - a
	var pvec := dir.cross(edge2)
	var det := edge1.dot(pvec)
	if absf(det) < 0.000001:
		return -1.0
	var inv := 1.0 / det
	var tvec := origin - a
	var u := tvec.dot(pvec) * inv
	if u < 0.0 or u > 1.0:
		return -1.0
	var qvec := tvec.cross(edge1)
	var v := dir.dot(qvec) * inv
	if v < 0.0 or u + v > 1.0:
		return -1.0
	var t := edge2.dot(qvec) * inv
	if t < 0.0 or t > max_distance:
		return -1.0
	return t


func _ray_aabb(origin: Vector3, dir: Vector3, box_min: Vector3, box_max: Vector3, max_distance: float) -> float:
	var tmin := 0.0
	var tmax := max_distance
	for axis in 3:
		var o: float = origin[axis]
		var d: float = dir[axis]
		var b0: float = box_min[axis]
		var b1: float = box_max[axis]
		if absf(d) < 0.000001:
			if o < b0 or o > b1:
				return max_distance
			continue
		var inv := 1.0 / d
		var t0 := (b0 - o) * inv
		var t1 := (b1 - o) * inv
		if t0 > t1:
			var swap := t0
			t0 = t1
			t1 = swap
		tmin = maxf(tmin, t0)
		tmax = minf(tmax, t1)
		if tmin > tmax:
			return max_distance
	if tmin < 0.0 or tmin > max_distance:
		return max_distance
	return tmin
