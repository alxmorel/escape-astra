extends RefCounted

const GROUND_ITEM := preload("res://scenes/resources/ground_item.tscn")


static func spawn_list(origin: Vector3, up: Vector3, rows: Array, host: Node = null) -> void:
	var lift := up.normalized()
	if lift.length_squared() < 0.001:
		lift = Vector3.UP
	var side := lift.cross(Vector3.FORWARD if absf(lift.dot(Vector3.UP)) > 0.9 else Vector3.UP)
	if side.length_squared() < 0.001:
		side = lift.cross(Vector3.RIGHT)
	side = side.normalized()
	var count := rows.size()
	for i in count:
		if not rows[i] is Dictionary:
			continue
		var row: Dictionary = rows[i]
		var offset := side * (float(i) - float(count - 1) * 0.5) * 0.28
		spawn_drop(origin + offset, lift, str(row.get("id", "")), int(row.get("qty", 1)), host)


static func spawn_drop(origin: Vector3, up: Vector3, resource_id: String, quantity: int, host: Node = null) -> void:
	if resource_id.is_empty() or quantity <= 0:
		return
	var parent := _scene_root(host)
	if parent == null:
		return
	var item := GROUND_ITEM.instantiate()
	item.set(&"resource_id", resource_id)
	item.set(&"quantity", quantity)
	parent.add_child(item)
	var lift := up.normalized()
	if lift.length_squared() < 0.001:
		lift = Vector3.UP
	var side := lift.cross(Vector3.RIGHT)
	if side.length_squared() < 0.001:
		side = lift.cross(Vector3.FORWARD)
	side = side.normalized()
	item.global_position = origin + lift * 0.65 + side * randf_range(-0.12, 0.12)
	if item is RigidBody3D:
		(item as RigidBody3D).linear_velocity = side * randf_range(0.35, 0.9) + lift * 1.25


static func _scene_root(host: Node) -> Node:
	if host != null and is_instance_valid(host):
		var tree := host.get_tree()
		if tree != null and tree.current_scene != null:
			return tree.current_scene
	var main := Engine.get_main_loop() as SceneTree
	if main != null:
		return main.current_scene
	return null
