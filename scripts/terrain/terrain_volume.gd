extends Node3D

const STYLIZED := preload("res://scripts/resources/stylized_material.gd")
const WATER := preload("res://scripts/terrain/water_volume.gd")
const OCEAN := preload("res://scripts/terrain/ocean_surface.gd")
const TerrainDebugOverlay := preload("res://scripts/terrain/terrain_debug_overlay.gd")
const TerrainEdit := preload("res://scripts/terrain/terrain_edit.gd")
const TerrainMeshJob := preload("res://scripts/terrain/terrain_mesh_job.gd")
const TerrainStream := preload("res://scripts/terrain/terrain_stream.gd")
const TerrainCollision := preload("res://scripts/terrain/terrain_collision.gd")

const VOXEL := 0.7
const CHUNK_SIZE := 8
const ISO := 0.0
const RENDER_RADIUS := 22.0
const WATER_PRELOAD_RADIUS := 34.0
const TERRAIN_GENERATION_RADIUS := 36.0
const COLLISION_RADIUS := 13.0
const DIRT_DEPTH := 4.2
## Gabarit joueur (capsule h=1.7 r=0.3) → volume de creusage sur grille VOXEL.
## Largeur ≥1 voxel pour toucher 2 colonnes de coins MC ; profondeur 2 voxels / coup.
const BRUSH_RADIUS := 0.95
const BRUSH_STRENGTH := 4.0
const DIG_TARGET_VOXELS := 96
const DIG_WIDTH := 0.95
const DIG_HEIGHT := 2.1
const DIG_DEPTH := 1.4
const DIG_UNDER_DEPTH := 1.05
const DIG_MIN_SHELL := 0.35
const DIG_AIR_DENSITY := -0.65
const MAT_AIR := 0
const MAT_DIRT := 1
const MAT_STONE := 2

const DROPS := {
	MAT_DIRT: "dirt",
	MAT_STONE: "stone",
}
const TOOLS := {
	"shovel": [MAT_DIRT],
	"stone_shovel": [MAT_DIRT, MAT_STONE],
}

var _planet: Node3D
var _material: ShaderMaterial
var _xray := false
var _edits: Dictionary = {}
var _edit_dirty := false
var _edited_chunks: Dictionary = {}
var _density_cache: Dictionary = {}
var _height_cache: Dictionary = {}
var _chunks: Dictionary = {}
var _faces: Dictionary = {}
var _empty: Dictionary = {}
var _pending: Array[Vector3i] = []
var _pending_set: Dictionary = {}
var _support_cache_ok := false
var _support_cache_at := Vector3.ZERO
var _support_cache_r := 0.0
var _player_node: Node3D
var _stream_anchor := Vector3(1.0e20, 0.0, 0.0)
var _views: Dictionary = {}
var _bins: Dictionary = {}
var _colliding: Dictionary = {}
var _tri_counts: Dictionary = {}
var _tri_total := 0
var _collision_count := 0
var _collision_dirty := false
var _rendered := 0
var _rebuild_us := 0
var _rebuild_n := 0
var _builds_sec := 0
var _builds_shown := 0
var _builds_timer := 0.0
var _debug := TerrainDebugOverlay.new()
var _mesh_job := TerrainMeshJob.new()
var _water: Node
var _ocean: Node
var _boot := false
var _boot_hold := false
var _boot_layer: CanvasLayer


func is_edit_dirty() -> bool:
	return _edit_dirty


func mark_edits_saved() -> void:
	_edit_dirty = false


func export_edits() -> Dictionary:
	var rows: Array = []
	for key in _edits:
		var voxel := key as Vector3i
		rows.append([voxel.x, voxel.y, voxel.z, float(_edits[key])])
	var water: Array = []
	var springs: Array = []
	if _water != null:
		water = _water.call(&"export_rows")
		springs = _water.call(&"export_springs")
	return {"save_version": 2, "voxel": VOXEL, "edits": rows, "water": water, "springs": springs}


func setup(planet: Node3D) -> void:
	_planet = planet
	_material = STYLIZED.create(Color.WHITE)
	_water = WATER.new()
	_water.name = "Water"
	add_child(_water)
	_water.call(&"setup", self, planet, VOXEL, CHUNK_SIZE)
	_water.call(&"set_render_radius", RENDER_RADIUS)
	_ocean = OCEAN.new()
	_ocean.name = "Ocean"
	add_child(_ocean)
	_ocean.call(&"setup", planet, _water)
	_ocean.call(&"set_render_radius", RENDER_RADIUS)
	_mesh_job.configure(VOXEL, ISO, CHUNK_SIZE)
	_load()
	add_child(_debug)
	_debug.ensure(self)


func note_water_edit() -> void:
	_edit_dirty = true


func cell_is_solid(cell: Vector3i) -> bool:
	var pos := (Vector3(cell) + Vector3(0.5, 0.5, 0.5)) * VOXEL
	return density_at(pos) > ISO


func cell_is_procedural_solid(cell: Vector3i) -> bool:
	var pos := (Vector3(cell) + Vector3(0.5, 0.5, 0.5)) * VOXEL
	return _density_procedural(pos) > ISO


func point_in_water(local_position: Vector3) -> bool:
	return _water != null and bool(_water.call(&"contains_point", local_position))


func has_edits() -> bool:
	return not _edits.is_empty()


func warm_start() -> void:
	_sync_stream()
	_stream_anchor = _player_local()


func begin_boot() -> void:
	_boot = true
	var layer := CanvasLayer.new()
	layer.layer = 80
	add_child(layer)
	_boot_layer = layer
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(root)
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.03, 0.045, 0.06)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(backdrop)
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = "Chargement…"
	label.add_theme_font_size_override(&"font_size", 28)
	label.add_theme_color_override(&"font_color", Color(0.9, 0.93, 0.88))
	root.add_child(label)
	var player := get_tree().get_first_node_in_group(&"player")
	if player != null:
		player.set(&"controls_locked", true)
		player.set_physics_process(false)
	if _water != null:
		_water.call(&"set_boot", true)
	if _ocean != null:
		_ocean.call(&"set_boot", true)


func surface_ready(point: Vector3) -> bool:
	var coord := _chunk_of_voxel(_voxel_at(point))
	if _chunk_center(coord).distance_squared_to(_player_local()) > RENDER_RADIUS * RENDER_RADIUS:
		return true
	if not _water_ready(coord):
		return false
	return _bins.has(coord) or _empty.has(coord)


func chunk_surface(coord: Vector3i) -> PackedVector3Array:
	return _faces.get(coord, PackedVector3Array())


func chunk_grass_ready(coord: Vector3i) -> bool:
	if not _faces.has(coord):
		return false
	var limit := WATER_PRELOAD_RADIUS * WATER_PRELOAD_RADIUS
	if _chunk_center(coord).distance_squared_to(_player_local()) > limit:
		return false
	return _water_ready(coord)


func grass_chunk_list() -> Array:
	var out: Array = []
	var player := _player_local()
	var limit := WATER_PRELOAD_RADIUS * WATER_PRELOAD_RADIUS
	for key in _faces:
		var coord := key as Vector3i
		if _chunk_center(coord).distance_squared_to(player) <= limit:
			out.append(coord)
	return out


func surface_covered(origin: Vector3, direction: Vector3, reach: float) -> bool:
	if reach <= 0.0 or direction.length_squared() < 0.0001:
		return false
	var end := origin + direction.normalized() * reach
	var ray := end - origin
	for cell in _cells_along(origin, end):
		var coord := _chunk_of_voxel(cell)
		if not _bins.has(coord) or not _faces.has(coord):
			continue
		var bins: Dictionary = _bins[coord]
		if not bins.has(cell):
			continue
		var ids: PackedInt32Array = bins[cell]
		var tris: PackedVector3Array = _faces[coord]
		for id in ids:
			var hit := _ray_tri(origin, ray, tris[id * 3], tris[id * 3 + 1], tris[id * 3 + 2])
			if hit > 0.05 and hit <= 1.0:
				return true
	return false


func ground_point(point: Vector3) -> Vector3:
	var dist := point.length()
	if dist < 0.001:
		return point
	var dir := point / dist
	var from := dir * (dist + 1.6)
	var to := dir * maxf(dist - 2.2, 1.0)
	var ray := to - from
	var best_t := 2.0
	for cell in _cells_along(from, to):
		var coord := _chunk_of_voxel(cell)
		if not _bins.has(coord) or not _faces.has(coord):
			continue
		var bins: Dictionary = _bins[coord]
		if not bins.has(cell):
			continue
		var ids: PackedInt32Array = bins[cell]
		var tris: PackedVector3Array = _faces[coord]
		for id in ids:
			var hit_t := _ray_tri(from, ray, tris[id * 3], tris[id * 3 + 1], tris[id * 3 + 2])
			if hit_t >= 0.0 and hit_t < best_t:
				best_t = hit_t
	if best_t > 1.0:
		return point
	return from + ray * best_t


func support_radius(local_offset: Vector3) -> float:
	if _support_cache_ok and local_offset.distance_squared_to(_support_cache_at) < 0.04:
		return _support_cache_r
	var radius := _compute_support(local_offset)
	_support_cache_at = local_offset
	_support_cache_r = radius
	_support_cache_ok = true
	return radius


func near_edit(point: Vector3, radius: float) -> bool:
	if _edits.is_empty():
		return false
	var min_v := _voxel_at(point - Vector3.ONE * radius)
	var max_v := _voxel_at(point + Vector3.ONE * radius)
	for x in range(min_v.x, max_v.x + 1):
		for y in range(min_v.y, max_v.y + 1):
			for z in range(min_v.z, max_v.z + 1):
				if _edits.has(Vector3i(x, y, z)):
					return true
	return false


func material_id_at(pos: Vector3) -> int:
	var dist := pos.length()
	if dist < 0.001:
		return MAT_STONE
	var height := _planet.call(&"sample_terrain_height", pos / dist) as float
	return _material_from_depth(pos, height - dist)


func set_xray(enabled: bool) -> void:
	if _xray == enabled:
		return
	_xray = enabled
	_material = STYLIZED.create_xray(0.14) if enabled else STYLIZED.create(Color.WHITE)
	for key in _views:
		var view := _views[key] as MeshInstance3D
		if view != null:
			view.material_override = _material


func is_xray() -> bool:
	return _xray


func dig_global(
	point: Vector3,
	normal: Vector3,
	tool: String,
	underfoot: bool = false,
	player_local: Vector3 = Vector3.ZERO
) -> Dictionary:
	return TerrainEdit.dig(
		self,
		point,
		normal,
		tool,
		VOXEL,
		ISO,
		BRUSH_RADIUS,
		BRUSH_STRENGTH,
		TOOLS,
		DROPS,
		DIG_TARGET_VOXELS,
		DIG_DEPTH,
		underfoot,
		DIG_WIDTH,
		DIG_HEIGHT,
		DIG_DEPTH,
		DIG_UNDER_DEPTH,
		DIG_MIN_SHELL,
		player_local,
		DIG_AIR_DENSITY
	)


func clear_collision_for(chunks: Array) -> void:
	for item in chunks:
		TerrainCollision.clear(self, item as Vector3i)
	_collision_dirty = true


func plot_plane(cell: Vector3i, radius: float = -1.0) -> Dictionary:
	return TerrainEdit.plot_plane(cell, radius, Callable(self, &"_surface_radius"))


func flatten_plot(cell: Vector3i, radius: float = -1.0, normal: Vector3 = Vector3.ZERO) -> void:
	TerrainEdit.flatten_plot(self, cell, radius, normal, VOXEL)


func _surface_radius(dir: Vector3, guess: float) -> float:
	var outer := guess + 3.0
	var inner := maxf(guess - 3.0, 8.0)
	var previous := outer
	var previous_density := density_at(dir * previous)
	for step in 18:
		var radius := lerpf(outer, inner, float(step + 1) / 18.0)
		var sample := density_at(dir * radius)
		if previous_density <= 0.0 and sample > 0.0:
			var span := sample - previous_density
			if absf(span) < 0.0001:
				return previous
			return previous + (radius - previous) * (-previous_density / span)
		previous = radius
		previous_density = sample
	if _planet != null and _planet.has_method(&"sample_terrain_height"):
		return float(_planet.call(&"sample_terrain_height", dir))
	return guess


func triangles_in_aabb(box_min: Vector3, box_max: Vector3) -> PackedVector3Array:
	var lo := _voxel_at(box_min)
	var hi := _voxel_at(box_max - Vector3.ONE * 0.001)
	var chunk_lo := _chunk_of_voxel(lo - Vector3i.ONE)
	var chunk_hi := _chunk_of_voxel(hi + Vector3i.ONE)
	var out := PackedVector3Array()
	var seen: Dictionary = {}
	for cx in range(chunk_lo.x, chunk_hi.x + 1):
		for cy in range(chunk_lo.y, chunk_hi.y + 1):
			for cz in range(chunk_lo.z, chunk_hi.z + 1):
				var coord := Vector3i(cx, cy, cz)
				if not _faces.has(coord) or not _bins.has(coord):
					continue
				var faces: PackedVector3Array = _faces[coord]
				var bins: Dictionary = _bins[coord]
				for x in range(lo.x, hi.x + 1):
					for y in range(lo.y, hi.y + 1):
						for z in range(lo.z, hi.z + 1):
							var voxel := Vector3i(x, y, z)
							if not bins.has(voxel):
								continue
							var ids: PackedInt32Array = bins[voxel]
							for id in ids:
								var tri := int(id)
								if tri < 0 or tri * 3 + 2 >= faces.size():
									continue
								var token := "%d_%d_%d_%d" % [coord.x, coord.y, coord.z, tri]
								if seen.has(token):
									continue
								seen[token] = true
								var a := faces[tri * 3]
								var b := faces[tri * 3 + 1]
								var c := faces[tri * 3 + 2]
								if _tri_hits_box(a, b, c, box_min, box_max):
									out.append(a)
									out.append(b)
									out.append(c)
	return out


func march_global(origin: Vector3, direction: Vector3, reach: float) -> Dictionary:
	if _planet == null:
		return {}
	var local_origin := _planet.to_local(origin)
	var local_dir := _planet.to_local(origin + direction) - local_origin
	if local_dir.length_squared() < 0.0001:
		return {}
	local_dir = local_dir.normalized()
	var step := VOXEL * 0.5
	var traveled := 0.0
	var was_air := density_at(local_origin) <= ISO
	while traveled < reach and not was_air:
		traveled += step
		was_air = density_at(local_origin + local_dir * traveled) <= ISO
	while traveled < reach:
		var previous := traveled
		traveled += step
		var pos := local_origin + local_dir * traveled
		var solid := density_at(pos) > ISO
		if solid and was_air:
			var hit := _bisect_segment(local_origin + local_dir * previous, pos)
			var air := _air_normal(hit)
			return {
				"point": _planet.to_global(hit),
				"normal": _planet.global_transform.basis * air,
			}
		was_air = not solid
	return {}


func _density_procedural(pos: Vector3) -> float:
	var grid := pos / VOXEL
	var x0 := floori(grid.x)
	var y0 := floori(grid.y)
	var z0 := floori(grid.z)
	var tx := grid.x - float(x0)
	var ty := grid.y - float(y0)
	var tz := grid.z - float(z0)
	var c00 := lerpf(_procedural_density(Vector3i(x0, y0, z0)), _procedural_density(Vector3i(x0 + 1, y0, z0)), tx)
	var c10 := lerpf(_procedural_density(Vector3i(x0, y0 + 1, z0)), _procedural_density(Vector3i(x0 + 1, y0 + 1, z0)), tx)
	var c01 := lerpf(_procedural_density(Vector3i(x0, y0, z0 + 1)), _procedural_density(Vector3i(x0 + 1, y0, z0 + 1)), tx)
	var c11 := lerpf(_procedural_density(Vector3i(x0, y0 + 1, z0 + 1)), _procedural_density(Vector3i(x0 + 1, y0 + 1, z0 + 1)), tx)
	return lerpf(lerpf(c00, c10, ty), lerpf(c01, c11, ty), tz)


func density_at(pos: Vector3) -> float:
	var grid := pos / VOXEL
	var x0 := floori(grid.x)
	var y0 := floori(grid.y)
	var z0 := floori(grid.z)
	var tx := grid.x - float(x0)
	var ty := grid.y - float(y0)
	var tz := grid.z - float(z0)
	var c00 := lerpf(_corner_density(Vector3i(x0, y0, z0)), _corner_density(Vector3i(x0 + 1, y0, z0)), tx)
	var c10 := lerpf(_corner_density(Vector3i(x0, y0 + 1, z0)), _corner_density(Vector3i(x0 + 1, y0 + 1, z0)), tx)
	var c01 := lerpf(_corner_density(Vector3i(x0, y0, z0 + 1)), _corner_density(Vector3i(x0 + 1, y0, z0 + 1)), tx)
	var c11 := lerpf(_corner_density(Vector3i(x0, y0 + 1, z0 + 1)), _corner_density(Vector3i(x0 + 1, y0 + 1, z0 + 1)), tx)
	return lerpf(lerpf(c00, c10, ty), lerpf(c01, c11, ty), tz)


func _process(delta: float) -> void:
	if _planet == null:
		return
	var player := _player_local()
	if _stream_anchor.distance_squared_to(player) > 0.64:
		_sync_stream()
		_collision_dirty = true
		_stream_anchor = player
	if _boot_hold:
		_finish_boot()
	_pump()
	_pump_collision()
	_apply_horizon()
	if _boot and _boot_ready():
		_boot_hold = true
	_builds_timer += delta
	if _builds_timer >= 1.0:
		_builds_shown = _builds_sec
		_builds_sec = 0
		_builds_timer = 0.0
	_debug.tick(delta, _debug_stats())


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or key.physical_keycode != KEY_F3:
		return
	_debug.toggle()
	if _debug.enabled:
		_debug.refresh(_debug_stats())
	get_viewport().set_input_as_handled()


func _compute_support(local_offset: Vector3) -> float:
	var dist := local_offset.length()
	var dir := local_offset / dist if dist > 0.001 else Vector3.UP
	var height := float(_planet.call(&"sample_terrain_height", dir))
	var directional := dist < float(_planet.base_radius) * 0.5
	if not _column_edited(dir, dist, directional, height):
		return height
	if directional:
		return _march_inward(dir, height + 1.5, 6.0, height)
	if density_at(dir * dist) > ISO:
		return _march_outward(dir, dist, height + 3.0, height)
	return _march_inward(dir, dist, maxf(dist - 24.0, 6.0), height)


func _column_edited(dir: Vector3, dist: float, directional: bool, height: float) -> bool:
	if _edited_chunks.is_empty():
		return false
	var lo := height - 10.0
	var hi := height + 4.0
	if not directional:
		lo = minf(lo, dist - 3.0)
		hi = maxf(hi, dist + 3.0)
	var reach := float(CHUNK_SIZE) * VOXEL
	var reach2 := reach * reach
	for key in _edited_chunks:
		var center := _chunk_center(key)
		var along := clampf(center.dot(dir), lo, hi)
		if center.distance_squared_to(dir * along) <= reach2:
			return true
	return false


func _march_inward(dir: Vector3, start_r: float, end_r: float, fallback: float) -> float:
	var step := VOXEL
	var radius := start_r
	while radius > end_r:
		var previous := radius
		radius -= step
		if density_at(dir * radius) > ISO:
			return _iso_between(dir, radius, previous)
	return fallback


func _march_outward(dir: Vector3, start_r: float, end_r: float, fallback: float) -> float:
	var step := VOXEL
	var radius := start_r
	while radius < end_r:
		var previous := radius
		radius += step
		if density_at(dir * radius) <= ISO:
			return _iso_between(dir, previous, radius)
	return fallback


func _iso_between(dir: Vector3, solid_r: float, air_r: float) -> float:
	var solid := solid_r
	var air := air_r
	for _i in 10:
		var mid := (solid + air) * 0.5
		if density_at(dir * mid) > ISO:
			solid = mid
		else:
			air = mid
	return (solid + air) * 0.5


func _bisect_segment(air_point: Vector3, solid_point: Vector3) -> Vector3:
	var air := air_point
	var solid := solid_point
	for _i in 8:
		var mid := (air + solid) * 0.5
		if density_at(mid) > ISO:
			solid = mid
		else:
			air = mid
	return air


func _air_normal(pos: Vector3) -> Vector3:
	var e := VOXEL
	var gradient := Vector3(
		density_at(pos + Vector3(e, 0, 0)) - density_at(pos - Vector3(e, 0, 0)),
		density_at(pos + Vector3(0, e, 0)) - density_at(pos - Vector3(0, e, 0)),
		density_at(pos + Vector3(0, 0, e)) - density_at(pos - Vector3(0, 0, e))
	)
	if gradient.length_squared() < 0.000001:
		return pos.normalized()
	return -gradient.normalized()


func _sync_stream() -> void:
	TerrainStream.sync(self, TERRAIN_GENERATION_RADIUS, WATER_PRELOAD_RADIUS)


func _should_mesh(coord: Vector3i) -> bool:
	return TerrainStream.should_mesh(self, coord, CHUNK_SIZE, VOXEL)


func _take_pending() -> Vector3i:
	return TerrainStream.take_pending(self)


func _enqueue(chunks: Array) -> void:
	TerrainStream.enqueue(self, chunks, TERRAIN_GENERATION_RADIUS)


func _pump_collision() -> void:
	TerrainCollision.pump(self, _boot, COLLISION_RADIUS)


func _pump() -> void:
	_mesh_job.pump(self, _boot)


func _apply_mesh(coord: Vector3i, built: Dictionary, t0: int) -> void:
	var verts: PackedVector3Array = built["verts"]
	var norms: PackedVector3Array = built["norms"]
	var mats: PackedByteArray = built["mats"]
	var faces: PackedVector3Array = built["faces"]
	var colors := PackedColorArray()
	colors.resize(verts.size())
	for i in verts.size():
		colors[i] = _color_for(verts[i], int(mats[i]))
	_free_chunk(coord, false, false)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var body := StaticBody3D.new()
	body.name = "C_%s_%s_%s" % [_token(coord.x), _token(coord.y), _token(coord.z)]
	body.collision_layer = 0
	body.collision_mask = 0
	var visual := MeshInstance3D.new()
	visual.name = "View"
	visual.mesh = mesh
	visual.material_override = _material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.extra_cull_margin = 0.0
	visual.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	visual.visible = false
	body.add_child(visual)
	add_child(body)
	var tris := int(faces.size() / 3)
	_chunks[coord] = body
	_faces[coord] = faces
	_views[coord] = visual
	_tri_counts[coord] = tris
	_tri_total += tris
	_index_faces(coord, faces)
	_collision_dirty = true
	_tell_grass(coord)
	_rebuild_us += Time.get_ticks_usec() - t0
	_rebuild_n += 1
	_builds_sec += 1


func _index_faces(coord: Vector3i, faces: PackedVector3Array) -> void:
	var bins: Dictionary = {}
	var count := int(faces.size() / 3)
	for i in count:
		var a := faces[i * 3]
		var b := faces[i * 3 + 1]
		var c := faces[i * 3 + 2]
		var lo := _voxel_at(Vector3(minf(a.x, minf(b.x, c.x)), minf(a.y, minf(b.y, c.y)), minf(a.z, minf(b.z, c.z))))
		var hi := _voxel_at(Vector3(maxf(a.x, maxf(b.x, c.x)), maxf(a.y, maxf(b.y, c.y)), maxf(a.z, maxf(b.z, c.z))))
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				for z in range(lo.z, hi.z + 1):
					var cell := Vector3i(x, y, z)
					var ids: PackedInt32Array = bins.get(cell, PackedInt32Array())
					ids.append(i)
					bins[cell] = ids
	_bins[coord] = bins


func _apply_horizon() -> void:
	if _views.is_empty() or _planet == null:
		_rendered = 0
		return
	var eye := _player_local()
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		eye = _planet.to_local(cam.global_position)
	var dist := eye.length()
	if dist < 0.001:
		return
	var eye_n := eye / dist
	var limit := (float(_planet.base_radius) - 2.0) / dist
	var player := _player_local()
	var render2 := RENDER_RADIUS * RENDER_RADIUS
	var shown := 0
	for key in _views:
		var view := _views[key] as MeshInstance3D
		if view == null:
			continue
		var center := _chunk_center(key)
		var in_render := center.distance_squared_to(player) <= render2
		var facing := center.distance_squared_to(eye) <= 144.0 or center.normalized().dot(eye_n) >= limit - 0.04
		var show := in_render and facing and _water_ready(key)
		if view.visible != show:
			view.visible = show
		if show:
			shown += 1
	_rendered = shown


func _set_shadow(coord: Vector3i, near: bool) -> void:
	var view := _views.get(coord) as MeshInstance3D
	if view == null:
		return
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if near else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if view.cast_shadow != mode:
		view.cast_shadow = mode


func _debug_stats() -> Dictionary:
	var avg := 0.0 if _rebuild_n == 0 else float(_rebuild_us) / float(_rebuild_n) / 1000.0
	var samples := (CHUNK_SIZE + 3) * (CHUNK_SIZE + 3) * (CHUNK_SIZE + 3)
	var dirty := _pending.size() + (1 if _mesh_job.active else 0)
	var stats := {
		"fps": Engine.get_frames_per_second(),
		"chunks": _chunks.size(),
		"rendered": _rendered,
		"collision": _collision_count,
		"dirty": dirty,
		"tris": _tri_total,
		"samples": samples,
		"rebuild_ms": avg,
		"rebuilds_s": _builds_shown,
		"water_active": 0,
		"water_transfers": 0,
		"water_unstable": 0,
		"water_preload": 0,
		"water_ready": 0,
		"water_pending": 0,
		"water_tris": 0,
		"weather_line": "",
		"ocean_patches": 0,
		"ocean_tris": 0,
	}
	if _water != null:
		stats["water_active"] = int(_water.call(&"active_count"))
		stats["water_transfers"] = int(_water.call(&"transfers_per_second"))
		stats["water_unstable"] = int(_water.call(&"unstable_count"))
		stats["water_preload"] = int(_water.call(&"stat_preload"))
		stats["water_ready"] = int(_water.call(&"stat_ready"))
		stats["water_pending"] = int(_water.call(&"stat_pending"))
		stats["water_tris"] = int(_water.call(&"stat_triangles"))
		if _water.has_method(&"sea_coverage_ratio"):
			stats["sea_coverage"] = int(round(float(_water.call(&"sea_coverage_ratio")) * 100.0))
			stats["sea_level"] = float(_water.call(&"sea_level_radius"))
	var weather := get_tree().get_first_node_in_group(&"weather")
	if weather != null and weather.has_method(&"debug_lines"):
		stats["weather_line"] = "\n" + str(weather.call(&"debug_lines"))
	if _ocean != null:
		stats["ocean_patches"] = int(_ocean.call(&"rendered_patches"))
		stats["ocean_tris"] = int(_ocean.call(&"triangle_count"))
	return stats


func _color_for(pos: Vector3, mat: int) -> Color:
	if mat == MAT_STONE:
		return Color(0.48, 0.46, 0.43)
	if mat > MAT_STONE:
		return Color(0.62, 0.42, 0.24)
	var dir := pos.normalized() if pos.length_squared() > 0.001 else Vector3.UP
	var height := float(_height_cache.get(_voxel_at(pos), pos.length()))
	return _planet.call(&"sample_ground_color", dir * height)


func _material_at_voxel(voxel: Vector3i) -> int:
	var pos := Vector3(voxel) * VOXEL
	if not _height_cache.has(voxel):
		_procedural_density(voxel)
	var depth := float(_height_cache.get(voxel, pos.length())) - pos.length()
	return _material_from_depth(pos, depth)


func _material_from_depth(pos: Vector3, depth: float) -> int:
	var ore := _ore_id(pos, depth)
	if ore != 0:
		return ore
	if depth < DIRT_DEPTH:
		return MAT_DIRT
	return MAT_STONE


func _ore_id(_pos: Vector3, _depth: float) -> int:
	return 0


func _corner_density(voxel: Vector3i) -> float:
	if _edits.has(voxel):
		return float(_edits[voxel])
	return _procedural_density(voxel)


func _procedural_density(voxel: Vector3i) -> float:
	if _density_cache.has(voxel) and _height_cache.has(voxel):
		return float(_density_cache[voxel])
	var pos := Vector3(voxel) * VOXEL
	var dist := pos.length()
	var height := float(_planet.base_radius)
	if dist > 0.001:
		height = float(_planet.call(&"sample_terrain_height", pos / dist))
	var density := height - dist
	_density_cache[voxel] = density
	_height_cache[voxel] = height
	return density


func _refresh_edit_chunks() -> void:
	_edited_chunks.clear()
	for key in _edits:
		for coord in _affected(key):
			_edited_chunks[coord] = true


func _chunks_for(voxels: Array[Vector3i]) -> Array:
	var unique: Dictionary = {}
	var out: Array = []
	for voxel in voxels:
		for coord in _affected(voxel):
			if unique.has(coord):
				continue
			unique[coord] = true
			out.append(coord)
	return out


func _affected(voxel: Vector3i) -> Array[Vector3i]:
	var lo := _chunk_of_voxel(voxel - Vector3i.ONE)
	var hi := _chunk_of_voxel(voxel)
	var out: Array[Vector3i] = []
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				out.append(Vector3i(x, y, z))
	return out


func _chunk_of_voxel(voxel: Vector3i) -> Vector3i:
	return Vector3i(_floor_div(voxel.x), _floor_div(voxel.y), _floor_div(voxel.z))


func _floor_div(value: int) -> int:
	if value >= 0:
		return int(value / CHUNK_SIZE)
	return int(floor(float(value) / float(CHUNK_SIZE)))


func _cells_along(a: Vector3, b: Vector3) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	var g0 := a / VOXEL
	var g1 := b / VOXEL
	var cell := Vector3i(floori(g0.x), floori(g0.y), floori(g0.z))
	var last := Vector3i(floori(g1.x), floori(g1.y), floori(g1.z))
	var delta := g1 - g0
	var step := Vector3i(1 if delta.x >= 0.0 else -1, 1 if delta.y >= 0.0 else -1, 1 if delta.z >= 0.0 else -1)
	var tmax := Vector3(1.0e9, 1.0e9, 1.0e9)
	var tdelta := Vector3(1.0e9, 1.0e9, 1.0e9)
	for axis in 3:
		if absf(delta[axis]) < 0.00001:
			continue
		var border := float(cell[axis] + (1 if step[axis] > 0 else 0))
		tmax[axis] = (border - g0[axis]) / delta[axis]
		tdelta[axis] = float(step[axis]) / delta[axis]
	cells.append(cell)
	var guard := 0
	while cell != last and guard < 16:
		guard += 1
		if tmax.x <= tmax.y and tmax.x <= tmax.z:
			cell.x += step.x
			tmax.x += tdelta.x
		elif tmax.y <= tmax.z:
			cell.y += step.y
			tmax.y += tdelta.y
		else:
			cell.z += step.z
			tmax.z += tdelta.z
		cells.append(cell)
	return cells


func _ray_tri(origin: Vector3, dir: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var e1 := b - a
	var e2 := c - a
	var p := dir.cross(e2)
	var det := e1.dot(p)
	if absf(det) < 0.0000001:
		return -1.0
	var inv := 1.0 / det
	var tvec := origin - a
	var u := tvec.dot(p) * inv
	if u < 0.0 or u > 1.0:
		return -1.0
	var q := tvec.cross(e1)
	var v := q.dot(dir) * inv
	if v < 0.0 or u + v > 1.0:
		return -1.0
	var t := q.dot(e2) * inv
	if t < 0.0 or t > 1.0:
		return -1.0
	return t


func _protected(changes: Array) -> bool:
	if _planet == null:
		return false
	var farming := _planet.get_node_or_null(^"Farming")
	if farming == null or not farming.has_method(&"blocks_voxels"):
		return false
	var voxels: Array[Vector3i] = []
	for change in changes:
		var row: Array = change
		voxels.append(row[0] as Vector3i)
	return bool(farming.call(&"blocks_voxels", voxels, VOXEL))


func _tri_hits_box(a: Vector3, b: Vector3, c: Vector3, box_min: Vector3, box_max: Vector3) -> bool:
	var center := (box_min + box_max) * 0.5
	var extents := (box_max - box_min) * 0.5
	var v0 := a - center
	var v1 := b - center
	var v2 := c - center
	if maxf(v0.x, maxf(v1.x, v2.x)) < -extents.x or minf(v0.x, minf(v1.x, v2.x)) > extents.x:
		return false
	if maxf(v0.y, maxf(v1.y, v2.y)) < -extents.y or minf(v0.y, minf(v1.y, v2.y)) > extents.y:
		return false
	if maxf(v0.z, maxf(v1.z, v2.z)) < -extents.z or minf(v0.z, minf(v1.z, v2.z)) > extents.z:
		return false
	var normal := (v1 - v0).cross(v2 - v0)
	var reach := extents.x * absf(normal.x) + extents.y * absf(normal.y) + extents.z * absf(normal.z)
	if absf(normal.dot(v0)) > reach:
		return false
	var e0 := v1 - v0
	var e1 := v2 - v1
	var e2 := v0 - v2
	if _box_separated(e0.cross(Vector3(1, 0, 0)), v0, v1, v2, extents):
		return false
	if _box_separated(e0.cross(Vector3(0, 1, 0)), v0, v1, v2, extents):
		return false
	if _box_separated(e0.cross(Vector3(0, 0, 1)), v0, v1, v2, extents):
		return false
	if _box_separated(e1.cross(Vector3(1, 0, 0)), v0, v1, v2, extents):
		return false
	if _box_separated(e1.cross(Vector3(0, 1, 0)), v0, v1, v2, extents):
		return false
	if _box_separated(e1.cross(Vector3(0, 0, 1)), v0, v1, v2, extents):
		return false
	if _box_separated(e2.cross(Vector3(1, 0, 0)), v0, v1, v2, extents):
		return false
	if _box_separated(e2.cross(Vector3(0, 1, 0)), v0, v1, v2, extents):
		return false
	if _box_separated(e2.cross(Vector3(0, 0, 1)), v0, v1, v2, extents):
		return false
	return true


func _box_separated(axis: Vector3, v0: Vector3, v1: Vector3, v2: Vector3, extents: Vector3) -> bool:
	if axis.length_squared() < 0.00000001:
		return false
	var p0 := v0.dot(axis)
	var p1 := v1.dot(axis)
	var p2 := v2.dot(axis)
	var mn := minf(p0, minf(p1, p2))
	var mx := maxf(p0, maxf(p1, p2))
	var reach := extents.x * absf(axis.x) + extents.y * absf(axis.y) + extents.z * absf(axis.z)
	return mn > reach or mx < -reach


func _voxel_at(pos: Vector3) -> Vector3i:
	return Vector3i(floori(pos.x / VOXEL), floori(pos.y / VOXEL), floori(pos.z / VOXEL))


func _chunk_center(coord: Vector3i) -> Vector3:
	var extent := float(CHUNK_SIZE) * VOXEL
	return Vector3(coord * CHUNK_SIZE) * VOXEL + Vector3.ONE * extent * 0.5


func chunk_view_visible(coord: Vector3i) -> bool:
	if _empty.has(coord) and not _chunks.has(coord):
		return true
	var view := _views.get(coord) as MeshInstance3D
	return view != null and view.visible


func _water_ready(coord: Vector3i) -> bool:
	if _water == null:
		return true
	return bool(_water.call(&"is_ready", coord))


func _boot_ready() -> bool:
	var player := _player_local()
	var render2 := RENDER_RADIUS * RENDER_RADIUS
	var hit2 := COLLISION_RADIUS * COLLISION_RADIUS
	if _mesh_job.active and _chunk_center(_mesh_job.coord).distance_squared_to(player) <= render2:
		return false
	for pending_coord in _pending:
		if _chunk_center(pending_coord).distance_squared_to(player) <= render2:
			return false
	for key in _chunks:
		var coord := key as Vector3i
		var dist2 := _chunk_center(coord).distance_squared_to(player)
		if dist2 > render2:
			continue
		if not _water_ready(coord):
			return false
		if dist2 <= hit2 and _faces.has(coord) and not _colliding.has(coord):
			return false
	for key in _empty:
		var empty_coord := key as Vector3i
		if _chunk_center(empty_coord).distance_squared_to(player) > render2:
			continue
		if not _water_ready(empty_coord):
			return false
	# Ocean patches continuent en arrière-plan — ne bloquent plus le premier contrôle.
	return true


func _finish_boot() -> void:
	_boot = false
	_boot_hold = false
	if _water != null:
		_water.call(&"set_boot", false)
	if _ocean != null:
		_ocean.call(&"set_boot", false)
	var player := get_tree().get_first_node_in_group(&"player")
	if player != null:
		player.set_physics_process(true)
		player.set(&"controls_locked", false)
	if _boot_layer != null:
		_boot_layer.queue_free()
		_boot_layer = null
	if _planet != null and _planet.has_method(&"on_terrain_boot_finished"):
		_planet.call(&"on_terrain_boot_finished")


func _travel_dir() -> Vector3:
	var body := _player_node as CharacterBody3D
	if body == null or _planet == null:
		return Vector3.ZERO
	var velocity := _planet.global_transform.basis.inverse() * body.velocity
	if velocity.length_squared() < 1.0:
		return Vector3.ZERO
	return velocity.normalized()


func _player_local() -> Vector3:
	if _player_node == null or not is_instance_valid(_player_node):
		_player_node = get_tree().get_first_node_in_group(&"player") as Node3D
	if _player_node == null or _planet == null:
		return Vector3.UP * 48.0
	return _planet.to_local(_player_node.global_position)


func refresh_grass_near(local: Vector3, radius: float) -> void:
	var lo := _voxel_at(local - Vector3.ONE * radius)
	var hi := _voxel_at(local + Vector3.ONE * radius)
	var seen: Dictionary = {}
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				var coord := _chunk_of_voxel(Vector3i(x, y, z))
				if seen.has(coord):
					continue
				seen[coord] = true
				_tell_grass(coord)


func _tell_grass(coord: Vector3i) -> void:
	if _planet == null:
		return
	var flora := _planet.get_node_or_null(^"Flora")
	if flora != null and flora.has_method(&"rebuild_grass"):
		flora.call(&"rebuild_grass", coord)


func _free_chunk(coord: Vector3i, cancel_job: bool = true, tell_grass: bool = true) -> void:
	if cancel_job:
		_mesh_job.request_discard_at(coord)
	if _colliding.erase(coord):
		_collision_count = maxi(_collision_count - 1, 0)
	_views.erase(coord)
	_bins.erase(coord)
	_tri_total -= int(_tri_counts.get(coord, 0))
	_tri_counts.erase(coord)
	_faces.erase(coord)
	if _chunks.has(coord):
		var node := _chunks[coord] as Node
		_chunks.erase(coord)
		if node != null and is_instance_valid(node):
			if node is CollisionObject3D:
				(node as CollisionObject3D).collision_layer = 0
			node.queue_free()
	if tell_grass:
		_tell_grass(coord)


func _token(value: int) -> String:
	return str(value).replace("-", "m")


func _load() -> void:
	if _planet == null:
		return
	var path := str(SaveManager.terrain_path())
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	if absf(float(parsed.get("voxel", 0.0)) - VOXEL) > 0.01:
		return
	var rows: Array = parsed.get("edits", [])
	for item in rows:
		if item is Array and (item as Array).size() >= 4:
			var voxel := Vector3i(int(item[0]), int(item[1]), int(item[2]))
			_edits[voxel] = float(item[3])
	var water_rows: Variant = parsed.get("water", [])
	var spring_rows: Variant = parsed.get("springs", [])
	if _water != null and water_rows is Array:
		_water.call(&"import_rows", water_rows)
	if _water != null and spring_rows is Array:
		_water.call(&"import_springs", spring_rows)
	_refresh_edit_chunks()
	_edit_dirty = false
