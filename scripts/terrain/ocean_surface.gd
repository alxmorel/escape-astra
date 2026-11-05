extends Node3D

const WATER_SHADER := preload("res://shaders/water.gdshader")

const FACES := 6
const DIV := 4
const QUADS := 8
const RES := DIV * QUADS
const SKIRT := 0.55

var _planet: Node
var _water: Node
var _radius := 28.0
var _sea := 0.0
var _boot := false
var _material: ShaderMaterial
var _views: Dictionary = {}
var _meshes: Dictionary = {}
var _queue: Array[int] = []
var _shown := 0
var _tris := 0
var _wet_cache: Dictionary = {}


func setup(planet: Node, water: Node) -> void:
	_planet = planet
	_water = water
	_material = ShaderMaterial.new()
	_material.shader = WATER_SHADER
	_material.render_priority = 1
	if planet.has_signal(&"terrain_edited"):
		planet.connect(&"terrain_edited", _on_terrain_edited)


func set_render_radius(radius: float) -> void:
	_radius = radius


func set_boot(enabled: bool) -> void:
	_boot = enabled


func is_ready() -> bool:
	if _water == null:
		return true
	if float(_water.call(&"sea_level_radius")) <= 1.0:
		return false
	_sync_queue()
	return _queue.is_empty()


func rendered_patches() -> int:
	return _shown


func triangle_count() -> int:
	return _tris


func _process(_delta: float) -> void:
	_sync_queue()
	var budget := 6 if _boot else 2
	var built := 0
	while not _queue.is_empty() and built < budget:
		_build_patch(_queue.pop_front())
		built += 1
	_apply_visibility()


func _sync_queue() -> void:
	if _planet == null or _water == null:
		return
	var sea := float(_water.call(&"sea_level_radius"))
	if sea <= 1.0:
		return
	if not is_equal_approx(sea, _sea):
		_sea = sea
		_meshes.clear()
		_queue.clear()
		_wet_cache.clear()
		for key in _views:
			var view := _views[key] as MeshInstance3D
			if view != null:
				view.mesh = null
	var wanted: Dictionary = {}
	var player := _player_local()
	for face in FACES:
		for py in DIV:
			for px in DIV:
				var id := _patch_id(face, px, py)
				if not _in_view(_patch_center(face, px, py), player):
					continue
				wanted[id] = true
				if _meshes.has(id):
					if not _views.has(id):
						_attach(id)
					continue
				if not _queue.has(id):
					_queue.append(id)
	var stale: Array[int] = []
	for key in _views:
		if not wanted.has(key):
			stale.append(int(key))
	for id in stale:
		var view := _views[id] as MeshInstance3D
		_views.erase(id)
		if view != null:
			view.queue_free()


func _apply_visibility() -> void:
	_shown = 0
	_tris = 0
	var player := _player_local()
	for key in _views:
		var view := _views[key] as MeshInstance3D
		if view == null or view.mesh == null:
			continue
		var id := int(key)
		var show := _in_view(_patch_center(_face_of(id), _px_of(id), _py_of(id)), player)
		view.visible = show
		if not show:
			continue
		var count := int(view.mesh.get_meta(&"tris", 0))
		if count > 0:
			_shown += 1
			_tris += count


func _build_patch(id: int) -> void:
	if _meshes.has(id):
		_attach(id)
		return
	var face := _face_of(id)
	var px := _px_of(id)
	var py := _py_of(id)
	var x0 := px * QUADS
	var y0 := py * QUADS
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for iy in QUADS:
		for ix in QUADS:
			var gx := x0 + ix
			var gy := y0 + iy
			if not _quad_wet(face, gx, gy):
				continue
			var a := _push(verts, norms, colors, face, gx, gy, true)
			var b := _push(verts, norms, colors, face, gx + 1, gy, true)
			var c := _push(verts, norms, colors, face, gx + 1, gy + 1, true)
			var d := _push(verts, norms, colors, face, gx, gy + 1, true)
			_quad(indices, verts, a, b, c, d, 1.0)
			_try_skirt(verts, norms, colors, indices, face, gx + 1, gy, gx + 1, gy + 1, gx + 1, gy)
			_try_skirt(verts, norms, colors, indices, face, gx, gy + 1, gx + 1, gy + 1, gx, gy + 1)
			_try_skirt(verts, norms, colors, indices, face, gx, gy, gx, gy + 1, gx - 1, gy)
			_try_skirt(verts, norms, colors, indices, face, gx, gy, gx + 1, gy, gx, gy - 1)
	var mesh := ArrayMesh.new()
	var tris := 0
	if verts.size() >= 3 and indices.size() >= 3:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		tris = int(indices.size() / 3)
	mesh.set_meta(&"tris", tris)
	_meshes[id] = mesh
	_attach(id)


func _try_skirt(verts: PackedVector3Array, norms: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, face: int, gx: int, gy: int, gx2: int, gy2: int, nqx: int, nqy: int) -> void:
	if nqx >= 0 and nqy >= 0 and nqx < RES and nqy < RES and _quad_wet(face, nqx, nqy):
		return
	if nqx < 0 or nqy < 0 or nqx >= RES or nqy >= RES:
		return
	var top0 := _push(verts, norms, colors, face, gx, gy, true)
	var top1 := _push(verts, norms, colors, face, gx2, gy2, true)
	var low0 := _push_skirt(verts, norms, colors, face, gx, gy)
	var low1 := _push_skirt(verts, norms, colors, face, gx2, gy2)
	_quad(indices, verts, top0, top1, low1, low0, -1.0)


func _quad_wet(face: int, ix: int, iy: int) -> bool:
	if ix < 0 or iy < 0 or ix >= RES or iy >= RES:
		return false
	return (
		_wet_at(face, ix, iy)
		and _wet_at(face, ix + 1, iy)
		and _wet_at(face, ix, iy + 1)
		and _wet_at(face, ix + 1, iy + 1)
	)


func _wet_at(face: int, ix: int, iy: int) -> bool:
	return _surface_height(face, ix, iy) < _sea


func _surface_height(face: int, ix: int, iy: int) -> float:
	var key := face * 100000 + ix * 1000 + iy
	if _wet_cache.has(key):
		return float(_wet_cache[key])
	var height := _terrain(_dir(face, ix, iy))
	_wet_cache[key] = height
	return height


func _push(verts: PackedVector3Array, norms: PackedVector3Array, colors: PackedColorArray, face: int, ix: int, iy: int, wave: bool) -> int:
	var dir := _dir(face, ix, iy)
	var point := dir * _sea
	verts.append(point)
	norms.append(dir)
	var depth := clampf((_sea - _surface_height(face, ix, iy)) / 6.0, 0.0, 1.0)
	colors.append(Color((1.0 if wave else 0.0), depth, 0.0))
	return verts.size() - 1


func _push_skirt(verts: PackedVector3Array, norms: PackedVector3Array, colors: PackedColorArray, face: int, ix: int, iy: int) -> int:
	var dir := _dir(face, ix, iy)
	var point := dir * maxf(_sea - SKIRT, 0.5)
	verts.append(point)
	norms.append(dir)
	colors.append(Color(0.0, 1.0, 0.0))
	return verts.size() - 1


func _quad(indices: PackedInt32Array, verts: PackedVector3Array, a: int, b: int, c: int, d: int, sign: float) -> void:
	var outward := (verts[a] + verts[b] + verts[c] + verts[d]).normalized() * sign
	if (verts[b] - verts[a]).cross(verts[d] - verts[a]).dot(outward) < 0.0:
		var swap := b
		b = d
		d = swap
	indices.append(a)
	indices.append(b)
	indices.append(c)
	indices.append(a)
	indices.append(c)
	indices.append(d)


func _attach(id: int) -> void:
	var mesh: ArrayMesh = _meshes[id]
	var view := _views.get(id) as MeshInstance3D
	if view == null:
		view = MeshInstance3D.new()
		view.name = "Ocean_%d" % id
		view.material_override = _material
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		view.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		view.extra_cull_margin = 2.0
		add_child(view)
		_views[id] = view
	view.mesh = mesh


func _on_terrain_edited(local_position: Vector3, radius: float) -> void:
	_wet_cache.clear()
	var span := radius + _sea * PI * 0.5 / float(DIV)
	var drop: Array[int] = []
	for key in _meshes:
		var id := int(key)
		var center := _patch_center(_face_of(id), _px_of(id), _py_of(id))
		if center.distance_to(local_position) <= span:
			drop.append(id)
	for id in drop:
		_meshes.erase(id)
		_queue.erase(id)
		var view := _views.get(id) as MeshInstance3D
		if view != null:
			view.mesh = null


func _in_view(center: Vector3, player: Vector3) -> bool:
	var reach := _sea * sin(PI * 0.5 / float(DIV) * 0.8)
	if center.distance_to(player) > _radius + reach:
		return false
	var up := player
	if up.length_squared() < 0.01:
		up = Vector3.UP
	return center.normalized().dot(up.normalized()) > -0.05


func _terrain(dir: Vector3) -> float:
	if _planet == null or not _planet.has_method(&"sample_terrain_height"):
		return _sea
	var procedural := float(_planet.call(&"sample_terrain_height", dir))
	var host := get_parent()
	if host == null or not host.has_method(&"near_edit") or not host.has_method(&"density_at"):
		return procedural
	if not bool(host.call(&"near_edit", dir * procedural, 2.0)):
		return procedural
	var lo := procedural - 6.0
	var hi := procedural + 6.0
	for _step in 8:
		var mid := (lo + hi) * 0.5
		if float(host.call(&"density_at", dir * mid)) > 0.0:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


func _dir(face: int, ix: int, iy: int) -> Vector3:
	var u := float(ix) / float(RES) * 2.0 - 1.0
	var v := float(iy) / float(RES) * 2.0 - 1.0
	var cube := Vector3.ZERO
	match face:
		0:
			cube = Vector3(1.0, v, u)
		1:
			cube = Vector3(-1.0, v, -u)
		2:
			cube = Vector3(u, 1.0, v)
		3:
			cube = Vector3(u, -1.0, -v)
		4:
			cube = Vector3(u, v, 1.0)
		_:
			cube = Vector3(-u, v, -1.0)
	return cube.normalized()


func _patch_center(face: int, px: int, py: int) -> Vector3:
	var ix := px * QUADS + QUADS / 2
	var iy := py * QUADS + QUADS / 2
	return _dir(face, ix, iy) * _sea


func _player_local() -> Vector3:
	var body := get_tree().get_first_node_in_group(&"player") as Node3D
	if body == null or _planet == null or not _planet is Node3D:
		return Vector3.UP * _sea
	return (_planet as Node3D).to_local(body.global_position)


func _patch_id(face: int, px: int, py: int) -> int:
	return face * DIV * DIV + py * DIV + px


func _face_of(id: int) -> int:
	return int(id / (DIV * DIV))


func _py_of(id: int) -> int:
	return int((id % (DIV * DIV)) / DIV)


func _px_of(id: int) -> int:
	return id % DIV
