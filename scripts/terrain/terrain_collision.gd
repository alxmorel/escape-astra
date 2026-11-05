extends RefCounted
class_name TerrainCollision

## Collision shapes for streamed terrain chunks.


static func clear(host: Node, coord: Vector3i) -> void:
	var chunks: Dictionary = host.get(&"_chunks")
	var colliding: Dictionary = host.get(&"_colliding")
	var body := chunks.get(coord) as StaticBody3D
	if body == null:
		return
	var hit := body.get_node_or_null(^"Hit")
	if hit != null:
		hit.queue_free()
	body.collision_layer = 0
	if colliding.erase(coord):
		host.set(&"_collision_count", maxi(int(host.get(&"_collision_count")) - 1, 0))
	host.call(&"_set_shadow", coord, false)


static func pump(host: Node, boot: bool, collision_radius: float) -> void:
	if not bool(host.get(&"_collision_dirty")):
		return
	var chunks: Dictionary = host.get(&"_chunks")
	var faces: Dictionary = host.get(&"_faces")
	var colliding: Dictionary = host.get(&"_colliding")
	var added := 0
	var cap := 48 if boot else 4
	var pending := false
	for key in chunks:
		var coord := key as Vector3i
		var want := wants(host, coord, collision_radius) and faces.has(coord)
		var has := colliding.has(coord)
		if want == has:
			continue
		if want and added >= cap:
			pending = true
			continue
		if want:
			added += 1
		update(host, coord, collision_radius)
	host.set(&"_collision_dirty", pending)


static func wants(host: Node, coord: Vector3i, collision_radius: float) -> bool:
	var center: Vector3 = host.call(&"_chunk_center", coord)
	var player: Vector3 = host.call(&"_player_local")
	return center.distance_squared_to(player) <= collision_radius * collision_radius


static func update(host: Node, coord: Vector3i, collision_radius: float) -> void:
	var chunks: Dictionary = host.get(&"_chunks")
	var faces: Dictionary = host.get(&"_faces")
	var colliding: Dictionary = host.get(&"_colliding")
	var body := chunks.get(coord) as StaticBody3D
	if body == null:
		return
	var want := wants(host, coord, collision_radius) and faces.has(coord)
	var has := colliding.has(coord)
	if want == has:
		host.call(&"_set_shadow", coord, want)
		return
	if want:
		add(body, faces[coord] as PackedVector3Array)
		body.collision_layer = 1
		colliding[coord] = true
		host.set(&"_collision_count", int(host.get(&"_collision_count")) + 1)
	else:
		var collision := body.get_node_or_null(^"Hit")
		if collision != null:
			collision.queue_free()
		body.collision_layer = 0
		if colliding.erase(coord):
			host.set(&"_collision_count", maxi(int(host.get(&"_collision_count")) - 1, 0))
	host.call(&"_set_shadow", coord, want)


static func add(body: StaticBody3D, faces: PackedVector3Array) -> void:
	var shape := ConcavePolygonShape3D.new()
	shape.data = faces
	shape.backface_collision = true
	shape.margin = 0.02
	var collision := CollisionShape3D.new()
	collision.name = "Hit"
	collision.shape = shape
	body.add_child(collision)
