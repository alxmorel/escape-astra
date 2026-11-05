extends Node3D

const FARM := preload("res://scripts/farming/farming_config.gd")
const PLOT := preload("res://scripts/farming/farm_plot.gd")
const STEPS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

var _wild: Dictionary = {}
var _cells: Dictionary = {}
var _tick := 0.0
var _leveling := false


func _ready() -> void:
	add_to_group(&"farming")
	var saved: Variant = SaveManager.state().get("wild_wheat", {})
	if saved is Dictionary:
		var now := SaveManager.play_time
		for key in (saved as Dictionary):
			var at := float((saved as Dictionary)[key])
			if now - at < FARM.WILD_RESPAWN:
				_wild[key] = at
	var planet := get_parent()
	if planet != null and planet.has_signal(&"terrain_edited"):
		planet.connect(&"terrain_edited", on_terrain_edited)


func _process(delta: float) -> void:
	_tick += delta
	if _tick < 0.5:
		return
	_tick = 0.0
	for key in _cells.keys():
		var plot: Node = _cells[key]
		if not is_instance_valid(plot):
			_cells.erase(key)
			continue
		if plot.has_method(&"refresh_soil"):
			plot.call(&"refresh_soil")
		if plot.has_method(&"sync_growth"):
			plot.call(&"sync_growth")


func note_wild(key: String) -> void:
	if key.is_empty():
		return
	_wild[key] = SaveManager.play_time


func export_wild() -> Dictionary:
	return _wild.duplicate()


func inspect(point: Vector3) -> Dictionary:
	var planet := get_parent() as Node3D
	var result := {"ok": false, "reason": "empty", "cell": Vector3i.ZERO}
	if planet == null:
		return result
	var local := planet.to_local(point)
	var volume := planet.get_node_or_null(^"TerrainVolume")
	if volume == null or not volume.has_method(&"triangles_in_aabb"):
		return result
	var cell := _surface_cell(planet, local)
	result["cell"] = cell
	if _cells.has(cell) or _overlaps(cell):
		result["reason"] = "taken"
		return result
	var box_min := Vector3(cell) * FARM.CELL
	var box_max := box_min + Vector3.ONE * FARM.CELL
	var tris: PackedVector3Array = volume.call(&"triangles_in_aabb", box_min, box_max)
	var kept := _kept(tris)
	if kept.is_empty():
		return result
	var analyzed := _analyze(volume, kept)
	analyzed["cell"] = cell
	return analyzed


func try_till(point: Vector3) -> bool:
	var info := inspect(point)
	if not bool(info.get("ok", false)):
		return false
	var cell: Vector3i = info["cell"]
	if _cells.has(cell):
		return false
	var plot := PLOT.new() as Node
	add_child(plot)
	plot.call(&"bind_cell", cell)
	_cells[cell] = plot
	level_patch(cell)
	return true


func blocks_voxels(voxels: Array, voxel_size: float) -> bool:
	if _cells.is_empty():
		return false
	for item in voxels:
		var voxel := item as Vector3i
		var a0 := Vector3(voxel) * voxel_size
		var a1 := a0 + Vector3.ONE * voxel_size
		for key in _cells:
			var cell := key as Vector3i
			var b0 := Vector3(cell) * FARM.CELL
			var b1 := b0 + Vector3.ONE * FARM.CELL
			if a0.x <= b1.x and a1.x >= b0.x and a0.y <= b1.y and a1.y >= b0.y and a0.z <= b1.z and a1.z >= b0.z:
				return true
	return false


func release_cell(cell: Vector3i) -> void:
	_cells.erase(cell)


func patch_level(cell: Vector3i) -> float:
	var volume := _volume()
	var level := 100000.0
	for next in _connected(cell):
		level = minf(level, _cell_radius(volume, next))
	if level > 90000.0:
		return -1.0
	return level


func patch_frame(cell: Vector3i) -> Dictionary:
	var volume := _volume()
	var best := 100000.0
	var lowest := cell
	var reused := Vector3.ZERO
	for next in _connected(cell):
		var radius := _cell_radius(volume, next)
		if radius < best:
			best = radius
			lowest = next
		if reused.length_squared() > 0.5:
			continue
		var plot: Node = _cells.get(next)
		if plot == null:
			continue
		var face: Vector3 = plot.get(&"_face_normal")
		if float(plot.get(&"ground_radius")) > 1.0 and face.length_squared() > 0.5:
			reused = face
	if best > 90000.0:
		best = (Vector3(cell) + Vector3.ONE * 0.5).length()
	var normal := (Vector3(lowest) + Vector3.ONE * 0.5).normalized()
	var lowest_plot: Node = _cells.get(lowest)
	if lowest_plot != null and reused.length_squared() > 0.5:
		var stored := float(lowest_plot.get(&"ground_radius"))
		if stored > 1.0 and absf(stored - best) < 0.05:
			normal = reused.normalized()
	return {"normal": normal, "radius": best}


func level_patch(cell: Vector3i) -> void:
	if _leveling or not _cells.has(cell):
		return
	if _volume() == null:
		return
	_leveling = true
	var frame := patch_frame(cell)
	var level := float(frame["radius"])
	var normal: Vector3 = frame["normal"]
	var group := _connected(cell)
	_collapse(group, normal, level)
	for next in group:
		if not _cells.has(next):
			continue
		var plot: Node = _cells[next]
		if is_instance_valid(plot) and plot.has_method(&"apply_level"):
			plot.call(&"apply_level", level, normal)
	_leveling = false
	_refresh_grass(FARM.cell_on_plane(cell, normal, level))


func _connected(start: Vector3i) -> Array[Vector3i]:
	var pending: Array[Vector3i] = [start]
	var seen: Dictionary = {}
	var out: Array[Vector3i] = []
	while not pending.is_empty():
		var current: Vector3i = pending.pop_back()
		if seen.has(current):
			continue
		seen[current] = true
		if current != start and not _cells.has(current):
			continue
		out.append(current)
		for step in STEPS:
			var next: Vector3i = current + step
			if _cells.has(next) and not seen.has(next):
				pending.append(next)
	return out


func covers_point(local: Vector3) -> bool:
	if _cells.is_empty():
		return false
	var planet := get_parent() as Node3D
	var cell := _surface_cell(planet, local)
	if _cells.has(cell):
		return true
	for key in _cells:
		var other := key as Vector3i
		if Vector3(other).distance_squared_to(Vector3(cell)) > 12.0:
			continue
		var frame := patch_frame(other)
		var normal: Vector3 = frame["normal"]
		var radius := float(frame["radius"])
		if normal.length_squared() < 0.01 or radius < 1.0:
			continue
		normal = normal.normalized()
		var center := FARM.cell_on_plane(other, normal, radius)
		var halves: Array = FARM.tangent_halves(normal)
		var half_u: Vector3 = halves[0]
		var half_v: Vector3 = halves[1]
		var delta := local - center
		var span_u := half_u.length_squared()
		var span_v := half_v.length_squared()
		if span_u < 0.0001 or span_v < 0.0001:
			continue
		if absf(delta.dot(half_u) / span_u) <= 1.05 and absf(delta.dot(half_v) / span_v) <= 1.05 and absf(delta.dot(normal)) < 1.25:
			return true
	return false


func _surface_cell(planet: Node, local: Vector3) -> Vector3i:
	var radius := local.length()
	if planet != null and local.length_squared() > 0.001 and planet.has_method(&"sample_terrain_height"):
		radius = float(planet.call(&"sample_terrain_height", local.normalized()))
	return FARM.surface_cell(local, radius)


func _refresh_grass(local: Vector3) -> void:
	var volume := _volume()
	if volume != null and volume.has_method(&"refresh_grass_near"):
		volume.call(&"refresh_grass_near", local, 2.2)


func _on_surface(volume: Node, cell: Vector3i) -> Vector3i:
	if volume == null or not volume.has_method(&"plot_plane"):
		return cell
	var plane: Dictionary = volume.call(&"plot_plane", cell)
	var origin: Vector3 = plane["origin"]
	var normal: Vector3 = plane["normal"]
	var dom := 0
	if absf(normal.y) > absf(normal.x):
		dom = 1
	if absf(normal.z) > absf(normal[dom]):
		dom = 2
	var snapped := cell
	snapped[dom] = floori(origin[dom])
	return snapped


func _overlaps(cell: Vector3i) -> bool:
	var frame := patch_frame(cell)
	var normal: Vector3 = frame["normal"]
	var radius := float(frame["radius"])
	var pos := FARM.cell_on_plane(cell, normal, radius)
	for key in _cells:
		var other := key as Vector3i
		if other == cell:
			return true
		if Vector3(other).distance_squared_to(Vector3(cell)) > 16.0:
			continue
		if pos.distance_squared_to(FARM.cell_on_plane(other, normal, radius)) < 0.49:
			return true
	return false


func _collapse(group: Array[Vector3i], normal: Vector3, radius: float) -> void:
	var consider: Array[Vector3i] = []
	for key in _cells.keys():
		var candidate := key as Vector3i
		if _near(candidate, group):
			consider.append(candidate)
	var placed: Array[Vector3i] = []
	var remove: Array[Vector3i] = []
	for candidate in consider:
		var pos := FARM.cell_on_plane(candidate, normal, radius)
		var clash := -1
		for i in placed.size():
			var other: Vector3i = placed[i]
			if pos.distance_squared_to(FARM.cell_on_plane(other, normal, radius)) < 0.49:
				clash = i
				break
		if clash < 0:
			placed.append(candidate)
			continue
		var keep := _prefer(placed[clash], candidate, normal, radius)
		if keep != placed[clash]:
			remove.append(placed[clash])
			placed[clash] = keep
		else:
			remove.append(candidate)
	for candidate in remove:
		_discard_cell(candidate)


func _near(cell: Vector3i, group: Array[Vector3i]) -> bool:
	var point := Vector3(cell)
	for other in group:
		if point.distance_squared_to(Vector3(other)) <= 16.0:
			return true
	return false


func _prefer(a: Vector3i, b: Vector3i, normal: Vector3, radius: float) -> Vector3i:
	var pa: Node = _cells[a]
	var pb: Node = _cells[b]
	var a_crop := str(pa.get(&"crop_id")) != ""
	var b_crop := str(pb.get(&"crop_id")) != ""
	if a_crop != b_crop:
		return a if a_crop else b
	var plane := normal.normalized() * radius
	var da := absf((Vector3(a) + Vector3.ONE * 0.5 - plane).dot(normal))
	var db := absf((Vector3(b) + Vector3.ONE * 0.5 - plane).dot(normal))
	return a if da <= db else b


func _discard_cell(cell: Vector3i) -> void:
	var plot: Node = _cells.get(cell)
	if plot == null:
		_cells.erase(cell)
		return
	if str(plot.get(&"crop_id")) != "" and plot.has_method(&"demolish"):
		plot.call(&"demolish")
		return
	_cells.erase(cell)
	plot.set(&"_bound", false)
	plot.queue_free()


func _cell_radius(volume: Node, cell: Vector3i) -> float:
	var plot: Node = _cells.get(cell)
	if plot != null:
		var stored := float(plot.get(&"ground_radius"))
		if stored > 1.0:
			return stored
	if volume != null and volume.has_method(&"plot_plane"):
		var plane: Dictionary = volume.call(&"plot_plane", cell)
		var origin: Vector3 = plane["origin"]
		return origin.length()
	return (Vector3(cell) + Vector3.ONE * 0.5).length()


func _volume() -> Node:
	var planet := get_parent()
	if planet == null:
		return null
	return planet.get_node_or_null(^"TerrainVolume")


func restore_plots(rows: Array) -> void:
	var planet := get_parent() as Node3D
	if planet == null:
		return
	for row in rows:
		if not row is Dictionary:
			continue
		var info: Dictionary = row
		var cell := _cell_from(info, planet)
		if _cells.has(cell):
			continue
		var plot := PLOT.new() as Node
		add_child(plot)
		plot.call(&"bind_cell", cell)
		plot.call(&"import_crop", str(info.get("crop_id", "")), float(info.get("planted_at", -1.0)))
		_cells[cell] = plot
	for key in _cells.keys():
		var cell := key as Vector3i
		var plot: Node = _cells[cell]
		if is_instance_valid(plot) and float(plot.get(&"ground_radius")) <= 0.0:
			level_patch(cell)
		elif is_instance_valid(plot):
			_refresh_grass(FARM.cell_on_plane(cell, plot.get(&"_face_normal"), float(plot.get(&"ground_radius"))))


func on_terrain_edited(local_center: Vector3, radius: float) -> void:
	var reach := radius + 6.0
	for key in _cells.keys():
		var cell := key as Vector3i
		var center := Vector3(cell) * FARM.CELL + Vector3.ONE * (FARM.CELL * 0.5)
		if center.distance_to(local_center) > reach:
			continue
		var plot: Node = _cells[key]
		if is_instance_valid(plot) and plot.has_method(&"refresh_soil"):
			plot.call(&"refresh_soil")


func _analyze(volume: Node, tris: PackedVector3Array) -> Dictionary:
	var anchor := _centroid(tris)
	var up := anchor.normalized()
	var water := false
	var overhang := false
	var steep := false
	var dirt := true
	var count := int(tris.size() / 3)
	for i in count:
		var a := tris[i * 3]
		var b := tris[i * 3 + 1]
		var c := tris[i * 3 + 2]
		var mid := (a + b + c) / 3.0
		if bool(volume.call(&"point_in_water", mid)):
			water = true
		var normal := _outward(volume, a, b, c)
		var radial := mid.normalized()
		var align := clampf(normal.dot(radial), -1.0, 1.0)
		if align < 0.0:
			overhang = true
		elif rad_to_deg(acos(align)) > FARM.PLOT_MAX_SLOPE_DEG:
			steep = true
		if not _under_dirt(volume, mid, normal):
			dirt = false
	if _sheet_gap(tris):
		overhang = true
	var reason := ""
	if water:
		reason = "water"
	elif overhang:
		reason = "overhang"
	elif steep:
		reason = "slope"
	elif _components(tris) > 1:
		reason = "surfaces"
	elif not dirt:
		reason = "dirt"
	return {
		"ok": reason.is_empty(),
		"reason": reason,
		"triangles": tris,
		"anchor": anchor,
		"up": up if up.length_squared() > 0.01 else Vector3.UP,
	}


func _kept(tris: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	var count := int(tris.size() / 3)
	for i in count:
		var a := tris[i * 3]
		var b := tris[i * 3 + 1]
		var c := tris[i * 3 + 2]
		if (b - a).cross(c - a).length_squared() < 0.0000001:
			continue
		out.append(a)
		out.append(b)
		out.append(c)
	return out


func _outward(volume: Node, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var normal := (b - a).cross(c - a).normalized()
	var mid := (a + b + c) / 3.0
	var ahead := float(volume.call(&"density_at", mid + normal * 0.12))
	var behind := float(volume.call(&"density_at", mid - normal * 0.12))
	if ahead > behind:
		normal = -normal
	return normal


func _under_dirt(volume: Node, mid: Vector3, outward: Vector3) -> bool:
	var probe := mid
	var solid := false
	for _step in 5:
		probe -= outward * 0.16
		if float(volume.call(&"density_at", probe)) > 0.05:
			solid = true
			break
	if not solid or not volume.has_method(&"material_id_at"):
		return false
	return int(volume.call(&"material_id_at", probe)) == FARM.MAT_DIRT


func _components(tris: PackedVector3Array) -> int:
	var count := int(tris.size() / 3)
	if count <= 1:
		return count
	var parent: Array = []
	parent.resize(count)
	for i in count:
		parent[i] = i
	var edges: Dictionary = {}
	for i in count:
		var keys: Array[Vector3i] = [_q(tris[i * 3]), _q(tris[i * 3 + 1]), _q(tris[i * 3 + 2])]
		for edge in 3:
			var key := _edge_key(keys[edge], keys[(edge + 1) % 3])
			if edges.has(key):
				_union(parent, i, int(edges[key]))
			else:
				edges[key] = i
	var roots: Dictionary = {}
	for i in count:
		roots[_find(parent, i)] = true
	return roots.size()


func _sheet_gap(tris: PackedVector3Array) -> bool:
	var count := int(tris.size() / 3)
	if count <= 1:
		return false
	var parent: Array = []
	parent.resize(count)
	var radii: Array = []
	radii.resize(count)
	for i in count:
		parent[i] = i
		var mid := (tris[i * 3] + tris[i * 3 + 1] + tris[i * 3 + 2]) / 3.0
		radii[i] = mid.length()
	var edges: Dictionary = {}
	for i in count:
		var keys: Array[Vector3i] = [_q(tris[i * 3]), _q(tris[i * 3 + 1]), _q(tris[i * 3 + 2])]
		for edge in 3:
			var key := _edge_key(keys[edge], keys[(edge + 1) % 3])
			if edges.has(key):
				_union(parent, i, int(edges[key]))
			else:
				edges[key] = i
	var span: Dictionary = {}
	for i in count:
		var root := _find(parent, i)
		var radius := float(radii[i])
		if not span.has(root):
			span[root] = [radius, radius]
			continue
		var band: Array = span[root]
		band[0] = minf(float(band[0]), radius)
		band[1] = maxf(float(band[1]), radius)
		span[root] = band
	if span.size() <= 1:
		return false
	var bands: Array = span.values()
	for i in bands.size():
		var first: Array = bands[i]
		for j in range(i + 1, bands.size()):
			var second: Array = bands[j]
			var gap := maxf(float(first[0]), float(second[0])) - minf(float(first[1]), float(second[1]))
			if gap > 0.2:
				return true
	return false


func _q(point: Vector3) -> Vector3i:
	return Vector3i(roundi(point.x * 50.0), roundi(point.y * 50.0), roundi(point.z * 50.0))


func _edge_key(a: Vector3i, b: Vector3i) -> String:
	if a.x < b.x or (a.x == b.x and (a.y < b.y or (a.y == b.y and a.z <= b.z))):
		return "%d,%d,%d|%d,%d,%d" % [a.x, a.y, a.z, b.x, b.y, b.z]
	return "%d,%d,%d|%d,%d,%d" % [b.x, b.y, b.z, a.x, a.y, a.z]


func _find(parent: Array, index: int) -> int:
	var root := index
	while int(parent[root]) != root:
		root = int(parent[root])
	while int(parent[index]) != root:
		var next := int(parent[index])
		parent[index] = root
		index = next
	return root


func _union(parent: Array, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[rb] = ra


func _centroid(tris: PackedVector3Array) -> Vector3:
	var count := int(tris.size() / 3)
	if count == 0:
		return Vector3.ZERO
	var acc := Vector3.ZERO
	for i in count:
		acc += (tris[i * 3] + tris[i * 3 + 1] + tris[i * 3 + 2]) / 3.0
	return acc / float(count)


func _cell_from(info: Dictionary, planet: Node3D) -> Vector3i:
	var raw: Variant = info.get("cell", [])
	if raw is Array and (raw as Array).size() >= 3:
		var values: Array = raw
		return Vector3i(int(values[0]), int(values[1]), int(values[2]))
	return FARM.cell_at(planet.to_local(_vector_from(info.get("origin", []))))


func _vector_from(raw: Variant) -> Vector3:
	if not raw is Array or (raw as Array).size() < 3:
		return Vector3.ZERO
	var values: Array = raw
	return Vector3(float(values[0]), float(values[1]), float(values[2]))
