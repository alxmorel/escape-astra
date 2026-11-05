extends RefCounted
class_name WaterMeshBuild

## Builds water chunk meshes for WaterVolume.

var last_tri_count := 0

var _verts := PackedVector3Array()
var _norms := PackedVector3Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()
var _vert_map: Dictionary = {}
var _sheet_cache: Dictionary = {}
var _floor_cache: Dictionary = {}

var _host: Node
var _chunk := 8
var _voxel := 0.7
var _cascade := 0.34
var _water_max := 7
var _neighbors: Array[Vector3i] = []


func build(
	host: Node,
	coord: Vector3i,
	chunk: int,
	voxel: float,
	neighbors: Array[Vector3i],
	cascade: float,
	water_max: int
) -> ArrayMesh:
	_host = host
	_chunk = chunk
	_voxel = voxel
	_neighbors = neighbors
	_cascade = cascade
	_water_max = water_max
	last_tri_count = 0
	_verts = PackedVector3Array()
	_norms = PackedVector3Array()
	_colors = PackedColorArray()
	_indices = PackedInt32Array()
	_vert_map.clear()
	_sheet_cache.clear()
	_floor_cache.clear()
	var origin := coord * _chunk
	for z in _chunk:
		for y in _chunk:
			for x in _chunk:
				var cell := origin + Vector3i(x, y, z)
				var level := _level(cell)
				if level <= 0:
					continue
				var up := _cell_up(cell)
				if _top_open(cell, up, level):
					_emit_sheet(cell, up)
				if _bottom_open(cell, up):
					_emit_bottom(cell, up)
				for offset in _neighbors:
					if offset == up or offset == -up:
						continue
					_emit_side(cell, up, offset)
	if _verts.is_empty() or _indices.is_empty():
		return null
	last_tri_count = int(_indices.size() / 3)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _norms
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_INDEX] = _indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _emit_sheet(cell: Vector3i, up: Vector3i) -> void:
	var corners := _ordered_face(cell, up)
	var ids: Array[int] = [
		_sheet_index(corners[0], cell),
		_sheet_index(corners[1], cell),
		_sheet_index(corners[2], cell),
		_sheet_index(corners[3], cell),
	]
	var a := _verts[ids[0]]
	var b := _verts[ids[1]]
	var d := _verts[ids[3]]
	var outward := (_verts[ids[0]] + _verts[ids[1]] + _verts[ids[2]] + _verts[ids[3]]).normalized()
	if (b - a).cross(d - a).dot(outward) < 0.0:
		var swap := ids[1]
		ids[1] = ids[3]
		ids[3] = swap
	_indices.append(ids[0])
	_indices.append(ids[1])
	_indices.append(ids[2])
	_indices.append(ids[0])
	_indices.append(ids[2])
	_indices.append(ids[3])


func _emit_bottom(cell: Vector3i, up: Vector3i) -> void:
	var corners := _ordered_face(cell, -up)
	_add_shell(
		_floor_point(corners[0]),
		_floor_point(corners[1]),
		_floor_point(corners[2]),
		_floor_point(corners[3]),
		0.0,
		_shade(cell),
		-1.0
	)


func _emit_side(cell: Vector3i, up: Vector3i, side: Vector3i) -> void:
	var next := cell + side
	if _solid(next):
		return
	var edge := _shared_edge(cell, up, side)
	if edge.size() < 2:
		return
	var high0 := _sheet_point(edge[0], cell)
	var high1 := _sheet_point(edge[1], cell)
	var nlevel := _level(next)
	if nlevel > 0:
		var gap0 := _sheet_radius(edge[0], cell) - _sheet_radius(edge[0], next)
		var gap1 := _sheet_radius(edge[1], cell) - _sheet_radius(edge[1], next)
		var gap := maxf(gap0, gap1)
		var shares := _sheet_owns(edge[0], next) and _sheet_owns(edge[1], next)
		if shares and gap <= _cascade:
			return
		if not shares and absf(gap) <= _cascade and not _before(cell, next):
			return
		if not shares and gap < -_cascade:
			return
		_add_wall(
			high0,
			high1,
			_sheet_point(edge[1], next),
			_sheet_point(edge[0], next),
			cell,
			_shade(cell)
		)
		return
	var below := cell - up
	var below_level := _level(below)
	var low0: Vector3
	var low1: Vector3
	var inner := _ordered_face(cell, -up)
	var side_axis := _axis_of(side)
	var face := cell[side_axis] + (1 if side[side_axis] > 0 else 0)
	var floor_edge: Array[Vector3i] = []
	for corner in inner:
		if corner[side_axis] == face:
			floor_edge.append(corner)
	if floor_edge.size() < 2:
		return
	if below_level > 0 and not _solid(below):
		low0 = _sheet_point(floor_edge[0], below)
		low1 = _sheet_point(floor_edge[1], below)
	else:
		low0 = _floor_point(floor_edge[0])
		low1 = _floor_point(floor_edge[1])
	if not _same_column(edge[0], floor_edge[0], up):
		var swap_floor := low0
		low0 = low1
		low1 = swap_floor
	_add_wall(high0, high1, low1, low0, cell, _shade(cell))


func _shared_edge(cell: Vector3i, up: Vector3i, side: Vector3i) -> Array[Vector3i]:
	var side_axis := _axis_of(side)
	var face := cell[side_axis] + (1 if side[side_axis] > 0 else 0)
	var edge: Array[Vector3i] = []
	for corner in _ordered_face(cell, up):
		if corner[side_axis] == face:
			edge.append(corner)
	return edge


func _ordered_face(cell: Vector3i, dir: Vector3i) -> Array[Vector3i]:
	var axis := _axis_of(dir)
	var u := (axis + 1) % 3
	var v := (axis + 2) % 3
	var face := cell[axis] + (1 if dir[axis] > 0 else 0)
	var c00 := cell
	c00[axis] = face
	var c10 := c00
	c10[u] += 1
	var c11 := c10
	c11[v] += 1
	var c01 := c00
	c01[v] += 1
	if dir[axis] > 0:
		return [c00, c10, c11, c01]
	return [c00, c01, c11, c10]


func _sheet_index(corner: Vector3i, cell: Vector3i) -> int:
	var info := _sheet_info(corner, cell)
	var anchor := info["anchor"] as Vector3i
	if not _vert_map.has(corner):
		_vert_map[corner] = {}
	var bucket: Dictionary = _vert_map[corner]
	if bucket.has(anchor):
		return int(bucket[anchor])
	var point := _on_sphere(corner, float(info["radius"]))
	var idx := _push_vert(point, point.normalized(), Color(1.0, _shade(anchor), 0.0))
	bucket[anchor] = idx
	return idx


func _sheet_owns(corner: Vector3i, cell: Vector3i) -> bool:
	if not _sheet_cache.has(corner):
		_sheet_cache[corner] = _sheet_groups(corner)
	return (_sheet_cache[corner] as Dictionary).has(cell)


func _sheet_point(corner: Vector3i, cell: Vector3i) -> Vector3:
	return _on_sphere(corner, _sheet_radius(corner, cell))


func _sheet_radius(corner: Vector3i, cell: Vector3i) -> float:
	return float(_sheet_info(corner, cell)["radius"])


func _sheet_info(corner: Vector3i, cell: Vector3i) -> Dictionary:
	if not _sheet_cache.has(corner):
		_sheet_cache[corner] = _sheet_groups(corner)
	var table: Dictionary = _sheet_cache[corner]
	if table.has(cell):
		return table[cell]
	var level := _level(cell)
	return {"anchor": cell, "radius": _cell_surface_radius(cell, level)}


func _sheet_groups(corner: Vector3i) -> Dictionary:
	var exposed: Array[Vector3i] = []
	var radii: Dictionary = {}
	for dz in 2:
		for dy in 2:
			for dx in 2:
				var other := corner - Vector3i(dx, dy, dz)
				var level := _level(other)
				if level <= 0:
					continue
				var up := _cell_up(other)
				if not _on_top_face(other, corner, up) or not _top_open(other, up, level):
					continue
				exposed.append(other)
				radii[other] = _cell_surface_radius(other, level)
	var used: Dictionary = {}
	var table: Dictionary = {}
	for seed in exposed:
		if used.has(seed):
			continue
		var queue: Array[Vector3i] = [seed]
		var group: Array[Vector3i] = []
		used[seed] = true
		var cursor := 0
		while cursor < queue.size():
			var member := queue[cursor]
			cursor += 1
			group.append(member)
			var height := float(radii[member])
			for other in exposed:
				if used.has(other):
					continue
				if absf(float(radii[other]) - height) <= _cascade:
					used[other] = true
					queue.append(other)
		var anchor := group[0]
		var sum := 0.0
		for member in group:
			if _before(member, anchor):
				anchor = member
			sum += float(radii[member])
		var info := {"anchor": anchor, "radius": sum / float(group.size())}
		for member in group:
			table[member] = info
	return table


func _before(a: Vector3i, b: Vector3i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	if a.y != b.y:
		return a.y < b.y
	return a.z < b.z


func _floor_point(corner: Vector3i) -> Vector3:
	return _on_sphere(corner, _welded_floor(corner))


func _on_sphere(corner: Vector3i, radius: float) -> Vector3:
	var dir := Vector3(corner)
	if dir.length_squared() < 0.001:
		dir = Vector3.UP
	else:
		dir = dir.normalized()
	return dir * radius


func _welded_floor(corner: Vector3i) -> float:
	if _floor_cache.has(corner):
		return float(_floor_cache[corner])
	var sum := 0.0
	var count := 0
	for dz in 2:
		for dy in 2:
			for dx in 2:
				var cell := corner - Vector3i(dx, dy, dz)
				if _level(cell) <= 0:
					continue
				var up := _cell_up(cell)
				if not _on_top_face(cell, corner, -up):
					continue
				sum += _cell_floor_radius(cell)
				count += 1
	var radius := sum / float(count) if count > 0 else _fallback_radius(corner, 0)
	_floor_cache[corner] = radius
	return radius


func _fallback_radius(corner: Vector3i, level: int) -> float:
	var dist := Vector3(corner).length() * _voxel
	return dist - _voxel * float(_water_max - level) / float(_water_max)


func _cell_floor_radius(cell: Vector3i) -> float:
	var center := _center(cell)
	var dist := center.length()
	if dist < 0.001:
		return _voxel * 0.5
	return dist - _voxel * 0.5


func _top_open(cell: Vector3i, up: Vector3i, level: int) -> bool:
	var above := cell + up
	if _solid(above):
		return false
	if level < _water_max:
		return true
	return _level(above) <= 0


func _bottom_open(cell: Vector3i, up: Vector3i) -> bool:
	var below := cell - up
	if _solid(below):
		return false
	return _level(below) <= 0


func _on_top_face(cell: Vector3i, corner: Vector3i, up: Vector3i) -> bool:
	var axis := _axis_of(up)
	var face := cell[axis] + (1 if up[axis] > 0 else 0)
	if corner[axis] != face:
		return false
	var u := (axis + 1) % 3
	var v := (axis + 2) % 3
	return (
		corner[u] >= cell[u]
		and corner[u] <= cell[u] + 1
		and corner[v] >= cell[v]
		and corner[v] <= cell[v] + 1
	)


func _add_shell(a: Vector3, b: Vector3, c: Vector3, d: Vector3, wave: float, depth: float, sign: float) -> void:
	var outward := (a + b + c + d).normalized() * sign
	if (b - a).cross(d - a).dot(outward) < 0.0:
		var swap := b
		b = d
		d = swap
	var color := Color(wave, depth, 0.0)
	var ia := _push_vert(a, a.normalized() * sign, color)
	var ib := _push_vert(b, b.normalized() * sign, color)
	var ic := _push_vert(c, c.normalized() * sign, color)
	var id := _push_vert(d, d.normalized() * sign, color)
	_indices.append(ia)
	_indices.append(ib)
	_indices.append(ic)
	_indices.append(ia)
	_indices.append(ic)
	_indices.append(id)


func _add_wall(a: Vector3, b: Vector3, c: Vector3, d: Vector3, cell: Vector3i, depth: float) -> void:
	var outward := (a + b + c + d) * 0.25 - _center(cell)
	if outward.length_squared() < 0.000001:
		outward = a.normalized()
	if (b - a).cross(d - a).dot(outward) < 0.0:
		var swap := b
		b = d
		d = swap
	var normal := (b - a).cross(d - a)
	if normal.length_squared() < 0.000001:
		return
	normal = normal.normalized()
	var color := Color(0.0, depth, 0.0)
	var ia := _push_vert(a, normal, color)
	var ib := _push_vert(b, normal, color)
	var ic := _push_vert(c, normal, color)
	var id := _push_vert(d, normal, color)
	_indices.append(ia)
	_indices.append(ib)
	_indices.append(ic)
	_indices.append(ia)
	_indices.append(ic)
	_indices.append(id)


func _push_vert(point: Vector3, normal: Vector3, color: Color) -> int:
	var idx := _verts.size()
	_verts.append(point)
	_norms.append(normal)
	_colors.append(color)
	return idx


func _same_column(a: Vector3i, b: Vector3i, up: Vector3i) -> bool:
	var axis := _axis_of(up)
	var u := (axis + 1) % 3
	var v := (axis + 2) % 3
	return a[u] == b[u] and a[v] == b[v]


func _shade(cell: Vector3i) -> float:
	var depth := 0
	var cursor := cell
	for _step in 4:
		var below := _steepest(cursor)
		if below == cursor or _level(below) <= 0:
			break
		depth += 1
		cursor = below
	return clampf(float(depth) / 4.0, 0.0, 1.0)


func _steepest(cell: Vector3i) -> Vector3i:
	var origin := _center(cell).length()
	var best := cell
	var best_drop := -0.18
	for offset in _neighbors:
		var next := cell + offset
		var drop := _center(next).length() - origin
		if drop < best_drop:
			best_drop = drop
			best = next
	return best


func _level(cell: Vector3i) -> int:
	return int(_host.call(&"_level", cell))


func _solid(cell: Vector3i) -> bool:
	return bool(_host.call(&"_solid", cell))


func _cell_up(cell: Vector3i) -> Vector3i:
	return _host.call(&"_cell_up", cell) as Vector3i


func _cell_surface_radius(cell: Vector3i, level: int) -> float:
	return float(_host.call(&"_cell_surface_radius", cell, level))


func _center(cell: Vector3i) -> Vector3:
	return _host.call(&"_center", cell) as Vector3


func _axis_of(offset: Vector3i) -> int:
	return int(_host.call(&"_axis_of", offset))
