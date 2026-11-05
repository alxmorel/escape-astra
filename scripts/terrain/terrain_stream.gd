extends RefCounted
class_name TerrainStream

## Chunk streaming: gather / enqueue / drop / pending pick.


static func sync(host: Node, gen_radius: float, water_preload_radius: float) -> void:
	var player: Vector3 = host.call(&"_player_local")
	var keep := gather(host, player, gen_radius)
	var chunks: Dictionary = host.get(&"_chunks")
	var empty: Dictionary = host.get(&"_empty")
	var pending_set: Dictionary = host.get(&"_pending_set")
	var pending: Array = host.get(&"_pending")
	for key in keep:
		var coord := key as Vector3i
		if chunks.has(coord) or empty.has(coord) or pending_set.has(coord):
			continue
		if not bool(host.call(&"_should_mesh", coord)):
			empty[coord] = true
			continue
		pending.append(coord)
		pending_set[coord] = true
	drop_outside(host, keep)
	var water = host.get(&"_water")
	if water != null:
		water.call(&"retain", gather(host, player, water_preload_radius))


static func drop_outside(host: Node, keep: Dictionary) -> void:
	var chunks: Dictionary = host.get(&"_chunks")
	var empty: Dictionary = host.get(&"_empty")
	var pending: Array = host.get(&"_pending")
	var pending_set: Dictionary = host.get(&"_pending_set")
	var stale: Array[Vector3i] = []
	for key in chunks:
		var coord := key as Vector3i
		if not keep.has(coord):
			stale.append(coord)
	for coord in stale:
		host.call(&"_free_chunk", coord)
	stale.clear()
	for key in empty:
		var empty_coord := key as Vector3i
		if not keep.has(empty_coord):
			stale.append(empty_coord)
	for empty_coord2 in stale:
		empty.erase(empty_coord2)
	var kept: Array[Vector3i] = []
	for pending_coord in pending:
		if keep.has(pending_coord):
			kept.append(pending_coord)
		else:
			pending_set.erase(pending_coord)
	host.set(&"_pending", kept)
	var mesh_job = host.get(&"_mesh_job")
	if mesh_job != null and mesh_job.active and not keep.has(mesh_job.coord):
		mesh_job.request_discard()


static func should_mesh(host: Node, coord: Vector3i, chunk_size: int, voxel: float) -> bool:
	var edited: Dictionary = host.get(&"_edited_chunks")
	if edited.has(coord):
		return true
	var planet: Node3D = host.get(&"_planet")
	var center: Vector3 = host.call(&"_chunk_center", coord)
	var dist := center.length()
	var half := float(chunk_size) * voxel * 0.9 + 3.5
	var base := float(planet.base_radius)
	if dist > base + 16.0 + half or dist < base - 20.0 - half or dist < 0.001:
		return false
	var height := float(planet.call(&"sample_terrain_height", center / dist))
	return absf(dist - height) <= half


static func take_pending(host: Node) -> Vector3i:
	var pending: Array = host.get(&"_pending")
	var pending_set: Dictionary = host.get(&"_pending_set")
	var player: Vector3 = host.call(&"_player_local")
	var direction: Vector3 = host.call(&"_travel_dir")
	var best := 0
	var best_score := INF
	for i in pending.size():
		var center: Vector3 = host.call(&"_chunk_center", pending[i])
		var score := stream_score(center, player, direction)
		if score < best_score:
			best_score = score
			best = i
	var coord: Vector3i = pending[best]
	pending.remove_at(best)
	pending_set.erase(coord)
	return coord


static func enqueue(host: Node, chunks: Array, gen_radius: float) -> void:
	var player: Vector3 = host.call(&"_player_local")
	var limit2 := (gen_radius + 1.0) * (gen_radius + 1.0)
	var empty: Dictionary = host.get(&"_empty")
	var pending_set: Dictionary = host.get(&"_pending_set")
	var pending: Array = host.get(&"_pending")
	var mesh_job = host.get(&"_mesh_job")
	for item in chunks:
		var coord := item as Vector3i
		var center: Vector3 = host.call(&"_chunk_center", coord)
		if center.distance_squared_to(player) > limit2:
			host.call(&"_free_chunk", coord)
			continue
		empty.erase(coord)
		if mesh_job != null:
			mesh_job.request_discard_at(coord)
		if pending_set.has(coord):
			continue
		pending_set[coord] = true
		pending.push_front(coord)


static func gather(host: Node, player: Vector3, radius: float) -> Dictionary:
	var min_c: Vector3i = host.call(
		&"_chunk_of_voxel", host.call(&"_voxel_at", player - Vector3.ONE * radius)
	)
	var max_c: Vector3i = host.call(
		&"_chunk_of_voxel", host.call(&"_voxel_at", player + Vector3.ONE * radius)
	)
	var keep: Dictionary = {}
	var limit := radius * radius
	for x in range(min_c.x, max_c.x + 1):
		for y in range(min_c.y, max_c.y + 1):
			for z in range(min_c.z, max_c.z + 1):
				var coord := Vector3i(x, y, z)
				var center: Vector3 = host.call(&"_chunk_center", coord)
				if center.distance_squared_to(player) > limit:
					continue
				keep[coord] = true
	return keep


static func stream_score(center: Vector3, player: Vector3, direction: Vector3) -> float:
	var offset := center - player
	var dist := offset.length()
	if direction == Vector3.ZERO or dist <= 0.001:
		return dist
	return dist - offset.normalized().dot(direction) * 8.0
