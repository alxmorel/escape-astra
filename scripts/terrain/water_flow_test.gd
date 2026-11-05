extends SceneTree

const WATER := preload("res://scripts/terrain/water_volume.gd")


func _initialize() -> void:
	var failed := false
	if not _slope():
		failed = true
	if not _flat():
		failed = true
	if not _contains_point():
		failed = true
	if failed:
		push_error("water flow test failed")
	quit(1 if failed else 0)


func _slope() -> bool:
	var water = _volume()
	for x in range(-2, 10):
		for y in range(60, 76):
			for z in range(-2, 10):
				if x < 0 or x > 7 or z < 0 or z > 7 or y < 64 or y <= 64 + x:
					water._test_solid[Vector3i(x, y, z)] = true
	_open(water, Vector3i(-2, 60, -2), Vector3i(9, 75, 9))
	var source := Vector3i(6, 71, 3)
	water._write(source, 7)
	water._wake(source)
	if not _settle(water, "slope"):
		return false
	var total := 0
	var highest := -999
	var lowest := 999
	var peak := 0
	for cell in _cells(water):
		var level: int = water._level(cell)
		total += level
		highest = maxi(highest, cell.y)
		lowest = mini(lowest, cell.y)
		peak = maxi(peak, level)
		if water._can_leave(cell):
			push_error("slope unstable %s" % cell)
			return false
	var ok: bool = total == 7 and highest == 65 and lowest == 65 and peak <= 4 and water.active_count() == 0
	if not ok:
		push_error("slope end total=%d y=%d..%d peak=%d active=%d" % [total, lowest, highest, peak, water.active_count()])
	return ok


func _flat() -> bool:
	var water = _volume()
	for x in range(-4, 5):
		for z in range(-4, 5):
			for y in range(60, 70):
				water._test_solid[Vector3i(x, y, z)] = true
	_open(water, Vector3i(-4, 60, -4), Vector3i(4, 72, 4))
	var source := Vector3i(0, 70, 0)
	water._write(source, 7)
	water._wake(source)
	if not _settle(water, "flat"):
		return false
	var total := 0
	var used := 0
	var peak := 0
	for cell in _cells(water):
		var level: int = water._level(cell)
		total += level
		used += 1
		peak = maxi(peak, level)
		if cell.y != 70 or water._can_leave(cell):
			push_error("flat bad cell %s level %d" % [cell, level])
			return false
	var ok: bool = total == 7 and used >= 4 and peak <= 3 and water.active_count() == 0
	if not ok:
		push_error("flat end total=%d cells=%d peak=%d active=%d" % [total, used, peak, water.active_count()])
	return ok


func _contains_point() -> bool:
	var water = _volume()
	water._sea_ready = true
	water._sea_level = 100.0
	water._planet = _FakePlanet.new()
	water._ocean_cell_cache.clear()
	var ok := true
	# Sous la mer, bassin océanique, entre terrain (90) et mer (100) → immergé.
	for axis: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		var wet: Vector3 = axis.normalized() * 95.0
		if not water.contains_point(wet):
			push_error("ocean column should be wet %s" % wet)
			ok = false
		# Sous le fond océanique (creux sous terrain) → sec.
		var under: Vector3 = axis.normalized() * 80.0
		if water.contains_point(under):
			push_error("under ocean floor should be dry %s" % under)
			ok = false
		# Sous sea_level mais terrain terrestre (110) → sec.
		var land_cave: Vector3 = (-axis).normalized() * 95.0
		if water.contains_point(land_cave):
			push_error("land cave below sea should be dry %s" % land_cave)
			ok = false
		# Au-dessus de la mer → sec.
		var above: Vector3 = axis.normalized() * 105.0
		if water.contains_point(above):
			push_error("above sea should be dry %s" % above)
			ok = false
	# Lac hors colonne océan (rayon > mer) pour isoler le niveau voxel.
	var lake_cell := Vector3i(200, 0, 0)
	_open(water, lake_cell, lake_cell)
	water._write(lake_cell, 7)
	var lake_pos: Vector3 = water._center(lake_cell)
	if not water.contains_point(lake_pos):
		push_error("lake voxel should be wet %s" % lake_pos)
		ok = false
	water._write(lake_cell, 0)
	if water.contains_point(lake_pos):
		push_error("drained lake should be dry %s" % lake_pos)
		ok = false
	return ok


func _volume():
	var water = WATER.new()
	water._host = _Sink.new()
	water._voxel = 0.7
	water._chunk = 8
	return water


func _open(water, a: Vector3i, b: Vector3i) -> void:
	for x in range(a.x, b.x + 1):
		for y in range(a.y, b.y + 1):
			for z in range(a.z, b.z + 1):
				var coord: Vector3i = water._chunk_of(Vector3i(x, y, z))
				water._keep[coord] = true
				if water._grids.has(coord):
					continue
				var grid := PackedByteArray()
				grid.resize(512)
				water._grids[coord] = grid


func _settle(water, label: String) -> bool:
	var guard := 0
	while water.active_count() > 0 and guard < 20000:
		water._flow(water._pop_active())
		guard += 1
	if water.active_count() > 0:
		push_error("%s did not settle (%d)" % [label, water.active_count()])
		return false
	return true


func _cells(water) -> Array[Vector3i]:
	var found: Array[Vector3i] = []
	for key in water._grids:
		var coord := key as Vector3i
		var origin := coord * 8
		for z in 8:
			for y in 8:
				for x in 8:
					var cell := origin + Vector3i(x, y, z)
					if water._level(cell) > 0:
						found.append(cell)
	return found


class _Sink extends Node:
	func note_water_edit() -> void:
		pass


## +axes = océan (terrain 90), -axes = terre (terrain 110).
class _FakePlanet extends Node:
	func sample_terrain_height(dir: Vector3) -> float:
		var n := dir.normalized()
		if n.x + n.y + n.z >= 0.0:
			return 90.0
		return 110.0
