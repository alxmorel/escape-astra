extends Node

const WATER_SHADER := preload("res://shaders/water.gdshader")
const WaterHydro := preload("res://scripts/terrain/water_hydro.gd")
const WaterMeshBuild := preload("res://scripts/terrain/water_mesh_build.gd")
const NEIGHBORS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
const WATER_MAX := 7
const SURFACE_SLOP := 0.02
const CASCADE := 0.34
const SETTLE_CAP := 12000
const BASIN_REACH := 96.0
const BASIN_CAP := 16000
const SEA_SAMPLES := 2048

var _host: Node
var _planet: Node
var _voxel := 0.7
var _chunk := 8
var _material: ShaderMaterial
var _grids: Dictionary = {}
var _views: Dictionary = {}
var _dry: Dictionary = {}
var _delta: Dictionary = {}
var _delta_chunks: Dictionary = {}
var _keep: Dictionary = {}
var _pending: Array[Vector3i] = []
var _pending_set: Dictionary = {}
var _mesh_dirty: Dictionary = {}
var _active: Array[Vector3i] = []
var _active_set: Dictionary = {}
var _head := 0
var _spring_left: Dictionary = {}
var water_updates_per_frame := 256
var _transfer_frame := 0
var _transfers_sec := 0
var _stat_clock := 0.0
var _test_solid: Dictionary = {}
var _mesh_build := WaterMeshBuild.new()
var _ready: Dictionary = {}
var _busy: Dictionary = {}
var _settle_steps: Dictionary = {}
var _tri_counts: Dictionary = {}
var _tri_total := 0
var _render_radius := 22.0
var _player_node: Node3D
var _boot_boost := false
var _hydro: Dictionary = {}
var _hydro_chunks: Dictionary = {}
var _hydro_built := false
var _lake_r: Dictionary = {}
var _sea_ready := false
var _sea_level := 0.0
var _sea_coverage := 0.0
var _ocean_cell_cache: Dictionary = {}


func setup(host: Node, planet: Node, voxel: float, chunk: int) -> void:
	_host = host
	_planet = planet
	_voxel = voxel
	_chunk = chunk
	_material = ShaderMaterial.new()
	_material.shader = WATER_SHADER
	_material.render_priority = 1


func active_count() -> int:
	return maxi(_active.size() - _head, 0)


func transfers_per_second() -> int:
	return _transfers_sec


func set_render_radius(radius: float) -> void:
	_render_radius = radius


func sea_level_radius() -> float:
	_ensure_sea()
	return _sea_level


func sea_coverage_ratio() -> float:
	_ensure_sea()
	return _sea_coverage


var _ensure_hydro_ms := 0


func set_boot(enabled: bool) -> void:
	_boot_boost = enabled
	if enabled:
		var t0 := Time.get_ticks_msec()
		_ensure_hydro()
		_ensure_hydro_ms = Time.get_ticks_msec() - t0
		print("water_ensure_hydro=%dms" % _ensure_hydro_ms)


func is_ready(coord: Vector3i) -> bool:
	if _ready.has(coord):
		return true
	if not _keep.has(coord):
		return true
	if _dry.has(coord):
		if _region_unsettled():
			return false
		_mark_ready(coord)
		return true
	if not _grids.has(coord) or _pending_set.has(coord) or _mesh_dirty.has(coord):
		return false
	if _chunk_busy(coord) or _region_unsettled():
		return false
	_mark_ready(coord)
	return true


func stat_preload() -> int:
	return _keep.size()


func stat_ready() -> int:
	var count := 0
	for key in _keep:
		if is_ready(key as Vector3i):
			count += 1
	return count


func stat_pending() -> int:
	var count := 0
	for key in _keep:
		if not _ready.has(key):
			count += 1
	return count


func stat_triangles() -> int:
	return _tri_total


func unstable_count() -> int:
	var count := 0
	for key in _grids:
		var coord := key as Vector3i
		var grid: PackedByteArray = _grids[coord]
		var origin := coord * _chunk
		for z in _chunk:
			for y in _chunk:
				for x in _chunk:
					if grid[x + _chunk * (y + _chunk * z)] <= 0:
						continue
					if _can_leave(origin + Vector3i(x, y, z)):
						count += 1
	return count


func export_rows() -> Array:
	var rows: Array = []
	for key in _delta:
		var cell := key as Vector3i
		rows.append([cell.x, cell.y, cell.z, int(_delta[key])])
	return rows


func export_springs() -> Array:
	var rows: Array = []
	for key in _spring_left:
		rows.append([int(key), int(_spring_left[key])])
	return rows


func import_rows(rows: Array) -> void:
	_ensure_hydro()
	_delta.clear()
	_delta_chunks.clear()
	for item in rows:
		if not item is Array:
			continue
		var row: Array = item
		if row.size() < 4:
			continue
		var cell := Vector3i(int(row[0]), int(row[1]), int(row[2]))
		var level := clampi(int(row[3]), 0, WATER_MAX)
		if _generated(cell) == level:
			continue
		_delta[cell] = level
		_count_delta(cell, 1)


func import_springs(rows: Array) -> void:
	_spring_left.clear()
	for item in rows:
		if not item is Array:
			continue
		var row: Array = item
		if row.size() < 2:
			continue
		_spring_left[int(row[0])] = int(row[1])


func retain(keep: Dictionary) -> void:
	_keep = keep
	var stale: Array[Vector3i] = []
	for key in _grids:
		var coord := key as Vector3i
		if not keep.has(coord):
			stale.append(coord)
	for coord in stale:
		_drop_chunk(coord)
	stale.clear()
	for key in _dry:
		var coord := key as Vector3i
		if not keep.has(coord):
			stale.append(coord)
	for coord in stale:
		_dry.erase(coord)
	var kept_pending: Array[Vector3i] = []
	for coord in _pending:
		if keep.has(coord):
			kept_pending.append(coord)
		else:
			_pending_set.erase(coord)
	_pending = kept_pending
	_trim_active()
	for key in keep:
		var coord := key as Vector3i
		if _grids.has(coord) or _dry.has(coord) or _pending_set.has(coord):
			continue
		if not _interesting(coord):
			_dry[coord] = true
			continue
		_pending.append(coord)
		_pending_set[coord] = true


func disturb(center: Vector3, radius: float) -> void:
	_ocean_cell_cache.clear()
	var min_v := _voxel_of(center - Vector3.ONE * radius)
	var max_v := _voxel_of(center + Vector3.ONE * radius)
	var seen: Dictionary = {}
	for x in range(min_v.x, max_v.x + 1):
		for y in range(min_v.y, max_v.y + 1):
			for z in range(min_v.z, max_v.z + 1):
				var cell := Vector3i(x, y, z)
				var coord := _chunk_of(cell)
				if not seen.has(coord):
					seen[coord] = true
					_dry.erase(coord)
					_enqueue(coord)
					if _grids.has(coord):
						_mesh_dirty[coord] = true
				if _level(cell) > 0:
					_wake(cell)
					continue
				for offset in NEIGHBORS:
					var next := cell + offset
					if _level(next) > 0:
						_wake(next)


func contains_point(pos: Vector3) -> bool:
	if pos.length_squared() < 1.0:
		return false
	var cell := _voxel_of(pos)
	var level := _level(cell)
	if level > 0:
		if level >= WATER_MAX:
			return true
		if pos.length() <= _cell_surface_radius(cell, level) + 0.04:
			return true
	# Océan = volume entre terrain et mer (pas « sous sea_level » seul).
	if not _is_ocean_cell(cell):
		return false
	_ensure_sea()
	return pos.length() <= _sea_level + 0.04


func _process(_delta: float) -> void:
	_stat_clock += _delta
	if _stat_clock >= 1.0:
		_transfers_sec = _transfer_frame
		_transfer_frame = 0
		_stat_clock = 0.0
	var idle := _pending.is_empty() and _head >= _active.size() and _mesh_dirty.is_empty()
	if not idle:
		var start := Time.get_ticks_usec()
		var settling := _boot_boost or _needs_settle()
		var fill_us := 6000 if settling else 2000
		while not _pending.is_empty() and Time.get_ticks_usec() - start < fill_us:
			_fill_next()
		if _head > 48:
			_compact_active()
		var end := _active.size()
		var steps := 0
		var budget := 2048 if _boot_boost else (768 if settling else maxi(water_updates_per_frame, 1))
		var sim_us := 14000 if settling else 8000
		while _head < end and steps < budget and Time.get_ticks_usec() - start < sim_us:
			var cell := _pop_active()
			var coord := _chunk_of(cell)
			if not _ready.has(coord):
				_settle_steps[coord] = int(_settle_steps.get(coord, 0)) + 1
			_flow(cell)
			steps += 1
		var mesh_cap := 8 if settling else 2
		var mesh_us := 20000 if settling else 5500
		var built := 0
		while not _mesh_dirty.is_empty() and built < mesh_cap and Time.get_ticks_usec() - start < mesh_us:
			_flush_mesh()
			built += 1
	_update_views()


func _fill_next() -> void:
	var guard := _pending.size()
	while guard > 0 and not _pending.is_empty():
		guard -= 1
		var coord := _take_pending()
		if not _keep.has(coord) or _grids.has(coord) or _dry.has(coord):
			continue
		_fill_grid(coord)
		return


func _fill_grid(coord: Vector3i) -> void:
	if _grids.has(coord) or not _keep.has(coord):
		return
	_dry.erase(coord)
	var total := _chunk * _chunk * _chunk
	var grid := PackedByteArray()
	grid.resize(total)
	var origin := coord * _chunk
	var count := 0
	for z in _chunk:
		for y in _chunk:
			for x in _chunk:
				var cell := origin + Vector3i(x, y, z)
				var level := int(_delta[cell]) if _delta.has(cell) else _generated(cell)
				grid[x + _chunk * (y + _chunk * z)] = level
				if level > 0:
					count += 1
	if count == 0 and not _delta_chunks.has(coord):
		_dry[coord] = true
		return
	_grids[coord] = grid
	if count > 0:
		_mesh_dirty[coord] = true
	for z in _chunk:
		for y in _chunk:
			for x in _chunk:
				var cell := origin + Vector3i(x, y, z)
				if _level(cell) <= 0:
					continue
				_dirty_for(cell)


func _flow(cell: Vector3i) -> void:
	if not _keep.has(_chunk_of(cell)):
		return
	if not _grids.has(_chunk_of(cell)):
		_enqueue(_chunk_of(cell))
		_wake(cell)
		return
	var level := _level(cell)
	if level <= 0:
		return
	if _solid(cell):
		_commit(cell, 0)
		_wake_donors(cell)
		return
	var target := _pick_target(cell, level)
	if target == cell:
		return
	_transfer(cell, level, target, _level(target), 1)


func _transfer(source: Vector3i, source_level: int, dest: Vector3i, dest_level: int, amount: int) -> void:
	if _is_ocean_cell(dest):
		return
	var created := 0
	var spring := _spring_id(source)
	if spring >= 0:
		var left := _spring_remaining(spring)
		created = mini(amount, left)
		if created > 0:
			_spring_left[spring] = left - created
			_host.call(&"note_water_edit")
	_commit(source, source_level - (amount - created))
	_commit(dest, dest_level + amount)
	_transfer_frame += 1
	_wake(source)
	_wake(dest)
	_wake_donors(source)
	_wake_donors(dest)
	_open_around(source)
	_open_around(dest)


func _can_leave(cell: Vector3i) -> bool:
	var level := _level(cell)
	if level <= 0:
		return false
	if _solid(cell):
		return true
	return _pick_target(cell, level) != cell


func _pick_target(cell: Vector3i, level: int) -> Vector3i:
	var origin := _center(cell).length()
	var down := cell
	var down_radius := origin
	var side := cell
	var side_surface := INF
	for offset in NEIGHBORS:
		var next := cell + offset
		if _solid(next):
			continue
		var next_level := _flow_level(next)
		if not _worth_move(cell, level, next, next_level):
			continue
		var next_radius := _center(next).length()
		if next_radius < origin - 0.001:
			if next_radius < down_radius:
				down_radius = next_radius
				down = next
		else:
			var height := _cell_surface_radius(next, next_level)
			if height < side_surface:
				side_surface = height
				side = next
	if down != cell:
		return down
	return side


func _worth_move(source: Vector3i, source_level: int, dest: Vector3i, dest_level: int) -> bool:
	if source_level <= 0 or dest_level >= WATER_MAX:
		return false
	var slop := SURFACE_SLOP
	if _cell_surface_radius(source, source_level) <= _cell_surface_radius(dest, dest_level) + slop:
		return false
	if _center(dest).length() < _center(source).length() - 0.001:
		return true
	var next_source := _cell_surface_radius(source, source_level - 1)
	var next_dest := _cell_surface_radius(dest, dest_level + 1)
	return next_dest <= next_source + slop


func _flow_level(cell: Vector3i) -> int:
	if _is_ocean_cell(cell):
		return WATER_MAX
	return _level(cell)


func _is_ocean_cell(cell: Vector3i) -> bool:
	if _ocean_cell_cache.has(cell):
		return bool(_ocean_cell_cache[cell])
	var ocean := false
	_ensure_sea()
	var center := _center(cell)
	var dist := center.length()
	if _sea_level > 1.0 and dist > 0.001 and dist <= _sea_level + _voxel and not _solid(cell):
		if _planet != null and _planet.has_method(&"sample_terrain_height"):
			var terrain := float(_planet.call(&"sample_terrain_height", center / dist))
			ocean = terrain < _sea_level and dist + _voxel * 0.45 >= terrain
	_ocean_cell_cache[cell] = ocean
	return ocean


func _spring_id(cell: Vector3i) -> int:
	if _planet == null:
		return -1
	return int(_planet.call(&"spring_id_at", _center(cell), _voxel))


func _spring_remaining(spring_id: int) -> int:
	if _spring_left.has(spring_id):
		return int(_spring_left[spring_id])
	if _planet == null:
		return 0
	return int(_planet.call(&"spring_budget", spring_id))


func _commit(cell: Vector3i, level: int) -> void:
	level = clampi(level, 0, WATER_MAX)
	if _level(cell) == level:
		return
	var coord := _chunk_of(cell)
	_store_delta(cell, level)
	if _keep.has(coord):
		if _grids.has(coord):
			_write(cell, level)
		else:
			_dry.erase(coord)
			_fill_grid(coord)
	_dirty_for(cell)
	_host.call(&"note_water_edit")


func _store_delta(cell: Vector3i, level: int) -> void:
	var generated := _generated(cell)
	var had := _delta.has(cell)
	if level == generated:
		if had:
			_delta.erase(cell)
			_count_delta(cell, -1)
		return
	_lake_r.erase(cell)
	if not had:
		_count_delta(cell, 1)
	_delta[cell] = level


func _write(cell: Vector3i, level: int) -> void:
	var coord := _chunk_of(cell)
	if not _grids.has(coord):
		return
	var grid: PackedByteArray = _grids[coord]
	grid[_index(cell, coord)] = level
	_grids[coord] = grid


func _open_around(cell: Vector3i) -> void:
	var coord := _chunk_of(cell)
	_enqueue(coord)
	var local := cell - coord * _chunk
	for axis in 3:
		var step := 0
		if local[axis] == 0:
			step = -1
		elif local[axis] == _chunk - 1:
			step = 1
		if step == 0:
			continue
		var offset := Vector3i.ZERO
		offset[axis] = step
		_enqueue(coord + offset)


func _wake(cell: Vector3i) -> void:
	if _level(cell) <= 0 or _active_set.has(cell):
		return
	if not _keep.has(_chunk_of(cell)):
		return
	_active_set[cell] = true
	_active.append(cell)
	var coord := _chunk_of(cell)
	_busy[coord] = int(_busy.get(coord, 0)) + 1


func _wake_donors(cell: Vector3i) -> void:
	for offset in NEIGHBORS:
		var next := cell + offset
		if _level(next) > 0:
			_wake(next)


func _pop_active() -> Vector3i:
	var cell := _active[_head]
	_head += 1
	_active_set.erase(cell)
	var coord := _chunk_of(cell)
	var left := int(_busy.get(coord, 0)) - 1
	if left <= 0:
		_busy.erase(coord)
	else:
		_busy[coord] = left
	return cell


func _compact_active() -> void:
	var fresh: Array[Vector3i] = []
	for i in range(_head, _active.size()):
		fresh.append(_active[i])
	_active = fresh
	_head = 0


func _trim_active() -> void:
	var fresh: Array[Vector3i] = []
	_active_set.clear()
	_busy.clear()
	for i in range(_head, _active.size()):
		var cell := _active[i]
		if not _keep.has(_chunk_of(cell)):
			continue
		fresh.append(cell)
		_active_set[cell] = true
		var coord := _chunk_of(cell)
		_busy[coord] = int(_busy.get(coord, 0)) + 1
	_active = fresh
	_head = 0


func _flush_mesh() -> void:
	var coord := _mesh_dirty.keys()[0] as Vector3i
	_mesh_dirty.erase(coord)
	_tri_total -= int(_tri_counts.get(coord, 0))
	_tri_counts.erase(coord)
	if not _keep.has(coord) or not _grids.has(coord):
		_clear_view(coord)
		return
	var mesh := _mesh_build.build(self, coord, _chunk, _voxel, NEIGHBORS, CASCADE, WATER_MAX)
	if mesh == null:
		_clear_view(coord)
		return
	var tris := _mesh_build.last_tri_count
	_tri_counts[coord] = tris
	_tri_total += tris
	var view := _views.get(coord) as MeshInstance3D
	if view == null:
		view = MeshInstance3D.new()
		view.name = "W_%s_%s_%s" % [_token(coord.x), _token(coord.y), _token(coord.z)]
		view.material_override = _material
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		view.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		view.extra_cull_margin = 1.0
		view.visible = false
		add_child(view)
		_views[coord] = view
	view.mesh = mesh
	view.visible = _show_view(coord)


func _cell_surface_radius(cell: Vector3i, level: int) -> float:
	if level > 0 and _lake_r.has(cell) and not _delta.has(cell):
		return float(_lake_r[cell])
	var center := _center(cell)
	var dist := center.length()
	if dist < 0.001:
		return _voxel
	return dist + _voxel * (float(level) / float(WATER_MAX) - 0.5)


func _level(cell: Vector3i) -> int:
	var coord := _chunk_of(cell)
	if _grids.has(coord):
		return int((_grids[coord] as PackedByteArray)[_index(cell, coord)])
	if _delta.has(cell):
		return int(_delta[cell])
	if _dry.has(coord):
		return 0
	return _generated(cell)


func _generated(cell: Vector3i) -> int:
	_ensure_hydro()
	return int(_hydro.get(cell, 0))


func _interesting(coord: Vector3i) -> bool:
	if _delta_chunks.has(coord):
		return true
	_ensure_hydro()
	return _hydro_chunks.has(coord)


func _solid(cell: Vector3i) -> bool:
	if _test_solid.has(cell):
		return true
	if _host != null and _host.has_method(&"cell_is_solid"):
		return bool(_host.call(&"cell_is_solid", cell))
	return false


func _take_pending() -> Vector3i:
	var player := _player_pos()
	var direction := _move_dir()
	var best := 0
	var best_score := INF
	for i in _pending.size():
		var score := _stream_score(_chunk_center(_pending[i]), player, direction)
		if score < best_score:
			best_score = score
			best = i
	var coord := _pending[best]
	_pending.remove_at(best)
	_pending_set.erase(coord)
	return coord


func _stream_score(center: Vector3, player: Vector3, direction: Vector3) -> float:
	var offset := center - player
	var dist := offset.length()
	if direction == Vector3.ZERO or dist <= 0.001:
		return dist
	return dist - offset.normalized().dot(direction) * 8.0


func _cached_player() -> Node3D:
	if _player_node == null or not is_instance_valid(_player_node):
		_player_node = get_tree().get_first_node_in_group(&"player") as Node3D
	return _player_node


func _move_dir() -> Vector3:
	var body := _cached_player() as CharacterBody3D
	if body == null or _planet == null:
		return Vector3.ZERO
	var velocity := (_planet as Node3D).global_transform.basis.inverse() * body.velocity
	if velocity.length_squared() < 1.0:
		return Vector3.ZERO
	return velocity.normalized()


func _player_pos() -> Vector3:
	var player := _cached_player()
	if player == null or _planet == null:
		return Vector3.ZERO
	return (_planet as Node3D).to_local(player.global_position)


func _needs_settle() -> bool:
	for key in _keep:
		var coord := key as Vector3i
		if _ready.has(coord):
			continue
		if _dry.has(coord):
			continue
		if int(_settle_steps.get(coord, 0)) < SETTLE_CAP:
			return true
	return false


func _chunk_busy(coord: Vector3i) -> bool:
	return int(_busy.get(coord, 0)) > 0


func _region_unsettled() -> bool:
	if not _pending.is_empty():
		return true
	if _head < _active.size():
		return true
	if not _mesh_dirty.is_empty():
		return true
	return false


func _mark_ready(coord: Vector3i) -> void:
	_ready[coord] = true


func _update_views() -> void:
	for key in _views.keys():
		var coord := key as Vector3i
		var view := _views[key] as MeshInstance3D
		if view == null or not is_instance_valid(view):
			continue
		var show := _show_view(coord)
		if view.visible != show:
			view.visible = show


func _show_view(coord: Vector3i) -> bool:
	if not is_ready(coord):
		return false
	if not _ground_shown(coord):
		return false
	var limit := _render_radius * _render_radius
	return _chunk_center(coord).distance_squared_to(_player_pos()) <= limit


func _ground_shown(coord: Vector3i) -> bool:
	if _host == null or not _host.has_method(&"chunk_view_visible"):
		return true
	return bool(_host.call(&"chunk_view_visible", coord))


func _ensure_hydro() -> void:
	WaterHydro.ensure(self, NEIGHBORS, BASIN_REACH, BASIN_CAP, SEA_SAMPLES, WATER_MAX)


func _ensure_sea() -> void:
	WaterHydro.ensure_sea(self, SEA_SAMPLES)


func _enqueue(coord: Vector3i) -> void:
	if not _keep.has(coord) or _grids.has(coord) or _pending_set.has(coord):
		return
	_dry.erase(coord)
	_pending_set[coord] = true
	_pending.append(coord)


func _count_delta(cell: Vector3i, amount: int) -> void:
	var coord := _chunk_of(cell)
	var count := int(_delta_chunks.get(coord, 0)) + amount
	if count <= 0:
		_delta_chunks.erase(coord)
	else:
		_delta_chunks[coord] = count


func _drop_chunk(coord: Vector3i) -> void:
	_grids.erase(coord)
	_mesh_dirty.erase(coord)
	_ready.erase(coord)
	_settle_steps.erase(coord)
	_busy.erase(coord)
	_tri_total -= int(_tri_counts.get(coord, 0))
	_tri_counts.erase(coord)
	_clear_view(coord)


func _clear_view(coord: Vector3i) -> void:
	var view := _views.get(coord) as MeshInstance3D
	_views.erase(coord)
	if view != null and is_instance_valid(view):
		view.queue_free()


func _cell_up(cell: Vector3i) -> Vector3i:
	var radial := _center(cell)
	var axis := 0
	var magnitude := absf(radial.x)
	if absf(radial.y) > magnitude:
		axis = 1
		magnitude = absf(radial.y)
	if absf(radial.z) > magnitude:
		axis = 2
	var up := Vector3i.ZERO
	up[axis] = 1 if radial[axis] >= 0.0 else -1
	return up


func _dirty_for(cell: Vector3i) -> void:
	var coord := _chunk_of(cell)
	var local := cell - coord * _chunk
	var rx: Array[int] = [0]
	var ry: Array[int] = [0]
	var rz: Array[int] = [0]
	if local.x == 0:
		rx.append(-1)
	elif local.x == _chunk - 1:
		rx.append(1)
	if local.y == 0:
		ry.append(-1)
	elif local.y == _chunk - 1:
		ry.append(1)
	if local.z == 0:
		rz.append(-1)
	elif local.z == _chunk - 1:
		rz.append(1)
	for x in rx:
		for y in ry:
			for z in rz:
				var next := coord + Vector3i(x, y, z)
				if _grids.has(next):
					_mesh_dirty[next] = true


func _axis_of(offset: Vector3i) -> int:
	if offset.x != 0:
		return 0
	if offset.y != 0:
		return 1
	return 2


func _center(cell: Vector3i) -> Vector3:
	return (Vector3(cell) + Vector3(0.5, 0.5, 0.5)) * _voxel


func _voxel_of(pos: Vector3) -> Vector3i:
	return Vector3i(floori(pos.x / _voxel), floori(pos.y / _voxel), floori(pos.z / _voxel))


func _chunk_of(cell: Vector3i) -> Vector3i:
	return Vector3i(_div(cell.x), _div(cell.y), _div(cell.z))


func _div(value: int) -> int:
	if value >= 0:
		return int(value / _chunk)
	return int(floor(float(value) / float(_chunk)))


func _chunk_center(coord: Vector3i) -> Vector3:
	var extent := float(_chunk) * _voxel
	return Vector3(coord * _chunk) * _voxel + Vector3.ONE * extent * 0.5


func _index(cell: Vector3i, coord: Vector3i) -> int:
	var local := cell - coord * _chunk
	return local.x + _chunk * (local.y + _chunk * local.z)


func _token(value: int) -> String:
	return ("n%s" % abs(value)) if value < 0 else str(value)
