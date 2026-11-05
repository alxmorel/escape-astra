extends RefCounted
class_name WaterHydro

## Procedural sea level + lake basins for WaterVolume.


static func ensure(host: Node, neighbors: Array[Vector3i], basin_reach: float, basin_cap: int, sea_samples: int, water_max: int) -> void:
	if bool(host.get(&"_hydro_built")):
		return
	ensure_sea(host, sea_samples)
	host.set(&"_hydro_built", true)
	var hydro: Dictionary = host.get(&"_hydro")
	var hydro_chunks: Dictionary = host.get(&"_hydro_chunks")
	var lake_r: Dictionary = host.get(&"_lake_r")
	hydro.clear()
	hydro_chunks.clear()
	lake_r.clear()
	var planet: Node = host.get(&"_planet")
	if planet == null or not planet.has_method(&"sample_terrain_height"):
		return
	var pits := terrain_pits(host, neighbors, sea_samples)
	for i in pits.size():
		var best := i
		var best_floor := floor_r(host, pits[i])
		for j in range(i + 1, pits.size()):
			var floor_j := floor_r(host, pits[j])
			if floor_j < best_floor:
				best_floor = floor_j
				best = j
		if best != i:
			var swap := pits[i]
			pits[i] = pits[best]
			pits[best] = swap
	for pit in pits:
		if hydro.has(pit):
			continue
		fill_basin(host, pit, neighbors, basin_reach, basin_cap, water_max)
	var stale: Array[Vector3i] = []
	for key in hydro:
		var cell := key as Vector3i
		if int(hydro[cell]) <= 0:
			stale.append(cell)
			continue
		hydro_chunks[host.call(&"_chunk_of", cell)] = true
	for cell in stale:
		hydro.erase(cell)


static func ensure_sea(host: Node, sea_samples: int) -> void:
	if bool(host.get(&"_sea_ready")):
		return
	host.set(&"_sea_ready", true)
	host.set(&"_sea_level", 0.0)
	host.set(&"_sea_coverage", 0.0)
	var planet: Node = host.get(&"_planet")
	if planet == null or not planet.has_method(&"sample_terrain_height"):
		return
	var dirs := sphere_dirs(sea_samples)
	var heights := PackedFloat32Array()
	heights.resize(sea_samples)
	for i in sea_samples:
		heights[i] = float(planet.call(&"sample_terrain_height", dirs[i]))
	heights.sort()
	var index := clampi(int(float(sea_samples) * sea_cover_target(host)) - 1, 0, sea_samples - 1)
	var sea_level := float(heights[index])
	host.set(&"_sea_level", sea_level)
	var under := 0
	for height in heights:
		if height < sea_level:
			under += 1
	host.set(&"_sea_coverage", float(under) / float(sea_samples))


static func sea_cover_target(host: Node) -> float:
	var target := 0.45
	var planet: Node = host.get(&"_planet")
	if planet != null:
		var value = planet.get(&"target_water_coverage")
		if value != null:
			target = float(value)
	var seed_id := 0
	if planet != null:
		seed_id = int(planet.get(&"world_seed"))
	var wobble := float(posmod(seed_id, 9) - 4) * 0.006
	return clampf(target + wobble, 0.02, 0.95)


static func terrain_pits(host: Node, neighbors: Array[Vector3i], _sea_samples: int) -> Array[Vector3i]:
	var count := 640
	var dirs := sphere_dirs(count)
	var planet: Node = host.get(&"_planet")
	var height := PackedFloat32Array()
	height.resize(count)
	for i in count:
		height[i] = float(planet.call(&"sample_terrain_height", dirs[i]))
	var pits: Array[Vector3i] = []
	var seen: Dictionary = {}
	for i in count:
		var lowest := true
		for j in count:
			if i == j:
				continue
			var gap := acos(clampf(dirs[i].dot(dirs[j]), -1.0, 1.0))
			if gap > 0.11:
				continue
			if height[j] < height[i] - 0.04:
				lowest = false
				break
		if not lowest:
			continue
		var pit := basin_pit(host, dirs[i], neighbors)
		if seen.has(pit) or proc_solid(host, pit):
			continue
		seen[pit] = true
		pits.append(pit)
	return pits


static func sphere_dirs(count: int) -> Array[Vector3]:
	var dirs: Array[Vector3] = []
	var golden := PI * (3.0 - sqrt(5.0))
	for i in count:
		var y := 1.0 - (float(i) / float(count - 1)) * 2.0
		var ring := sqrt(maxf(0.0, 1.0 - y * y))
		var theta := golden * float(i)
		dirs.append(Vector3(cos(theta) * ring, y, sin(theta) * ring))
	return dirs


static func basin_pit(host: Node, axis: Vector3, neighbors: Array[Vector3i]) -> Vector3i:
	var planet: Node = host.get(&"_planet")
	var voxel := float(host.get(&"_voxel"))
	var dir := axis.normalized()
	var radius := voxel
	if planet.has_method(&"sample_terrain_height"):
		radius = float(planet.call(&"sample_terrain_height", dir))
	var cell: Vector3i = host.call(&"_voxel_of", dir * radius)
	for _step in 8:
		if not proc_solid(host, cell):
			break
		radius += voxel * 0.5
		cell = host.call(&"_voxel_of", dir * radius)
	for _step in 48:
		var best := cell
		var best_r: float = (host.call(&"_center", cell) as Vector3).length()
		for offset in neighbors:
			var next := cell + offset
			if proc_solid(host, next):
				continue
			var next_r: float = (host.call(&"_center", next) as Vector3).length()
			if next_r < best_r - 0.001:
				best_r = next_r
				best = next
		if best == cell:
			break
		cell = best
	return cell


static func fill_basin(
	host: Node,
	pit: Vector3i,
	neighbors: Array[Vector3i],
	basin_reach: float,
	basin_cap: int,
	water_max: int
) -> void:
	var pit_floor := floor_r(host, pit)
	var sea_level := float(host.get(&"_sea_level"))
	if pit_floor <= sea_level:
		return
	var hydro: Dictionary = host.get(&"_hydro")
	var lake_r: Dictionary = host.get(&"_lake_r")
	var origin: Vector3 = host.call(&"_center", pit)
	var reach2 := basin_reach * basin_reach
	var heap: Array[Vector3i] = []
	var floors: Array[float] = []
	var seen: Dictionary = {}
	seen[pit] = true
	heap_push(heap, floors, pit, pit_floor)
	var basin: Array[Vector3i] = []
	var spill := INF
	var closed := false
	while not heap.is_empty() and basin.size() < basin_cap:
		var cell := heap_pop(heap, floors)
		var floor_c := floor_r(host, cell)
		if floor_c >= spill:
			break
		var outlet := false
		for offset in neighbors:
			var next := cell + offset
			if proc_solid(host, next) or seen.has(next):
				continue
			if (host.call(&"_center", next) as Vector3).distance_squared_to(origin) > reach2:
				continue
			if hydro.has(next) or floor_r(host, next) + 0.18 < floor_c:
				spill = minf(spill, floor_c)
				outlet = true
				closed = true
				continue
			seen[next] = true
			heap_push(heap, floors, next, floor_r(host, next))
		if outlet and floor_c >= spill:
			break
		basin.append(cell)
	if not closed or spill == INF or basin.is_empty():
		return
	var depth := spill - pit_floor
	var surface := spill - 0.12
	if depth < 0.45 or surface <= sea_level or not basin_holds(host, pit, depth, basin.size()):
		return
	for cell2 in basin:
		if hydro.has(cell2) or floor_r(host, cell2) >= surface:
			continue
		var level := level_capped(host, cell2, surface, water_max)
		if level <= 0:
			continue
		hydro[cell2] = level
		lake_r[cell2] = surface


static func basin_holds(host: Node, pit: Vector3i, depth: float, count: int) -> bool:
	var wet := 0.0
	var planet: Node = host.get(&"_planet")
	if planet != null and planet.has_method(&"get_zone_weights"):
		var weights: Variant = planet.call(&"get_zone_weights", host.call(&"_center", pit))
		if weights is PackedFloat32Array and (weights as PackedFloat32Array).size() > 3:
			wet = (weights as PackedFloat32Array)[3]
	var chance := 0.06 + wet * 0.4 + clampf((depth - 0.5) / 2.2, 0.0, 0.42)
	if count > 180:
		chance += 0.28
	elif count < 18 and depth < 0.9:
		chance *= 0.12 + wet * 0.5
	return unit_hash(host, pit) < clampf(chance, 0.0, 0.9)


static func unit_hash(host: Node, cell: Vector3i) -> float:
	var salt := 0
	var planet: Node = host.get(&"_planet")
	if planet != null:
		salt = int(planet.get(&"world_seed"))
	var n := cell.x * 73856093 ^ cell.y * 19349663 ^ cell.z * 83492791 ^ salt * 374761393
	n = (n ^ (n >> 13)) * 1274126177
	return float(n & 0xffffff) / float(0xffffff)


static func heap_push(heap: Array[Vector3i], floors: Array[float], cell: Vector3i, floor_v: float) -> void:
	heap.append(cell)
	floors.append(floor_v)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if floors[parent] <= floors[i]:
			break
		var swap_cell := heap[parent]
		heap[parent] = heap[i]
		heap[i] = swap_cell
		var swap_floor := floors[parent]
		floors[parent] = floors[i]
		floors[i] = swap_floor
		i = parent


static func heap_pop(heap: Array[Vector3i], floors: Array[float]) -> Vector3i:
	var cell := heap[0]
	var last := heap.size() - 1
	heap[0] = heap[last]
	floors[0] = floors[last]
	heap.remove_at(last)
	floors.remove_at(last)
	var i := 0
	while true:
		var left := i * 2 + 1
		if left >= heap.size():
			break
		var right := left + 1
		var best := left
		if right < heap.size() and floors[right] < floors[left]:
			best = right
		if floors[i] <= floors[best]:
			break
		var swap_cell := heap[best]
		heap[best] = heap[i]
		heap[i] = swap_cell
		var swap_floor := floors[best]
		floors[best] = floors[i]
		floors[i] = swap_floor
		i = best
	return cell


static func level_capped(host: Node, cell: Vector3i, cap_surface: float, water_max: int) -> int:
	var dist: float = (host.call(&"_center", cell) as Vector3).length()
	if dist < 0.001:
		return 0
	var voxel := float(host.get(&"_voxel"))
	var step := voxel / float(water_max)
	var level := int(floor((cap_surface - dist + voxel * 0.5) / step + 0.0001))
	return clampi(level, 0, water_max)


static func floor_r(host: Node, cell: Vector3i) -> float:
	return float(host.call(&"_cell_surface_radius", cell, 0))


static func proc_solid(host: Node, cell: Vector3i) -> bool:
	var test_solid: Dictionary = host.get(&"_test_solid")
	if test_solid.has(cell):
		return true
	var terrain = host.get(&"_host")
	if terrain != null and terrain.has_method(&"cell_is_procedural_solid"):
		return bool(terrain.call(&"cell_is_procedural_solid", cell))
	return bool(host.call(&"_solid", cell))
