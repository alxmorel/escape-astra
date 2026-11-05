extends RefCounted
class_name PlayerInteract

var _host: CharacterBody3D


func setup(host: CharacterBody3D) -> void:
	_host = host


func collect_nearby() -> void:
	var up: Vector3 = _host.call(&"_get_surface_up")
	var hand := _host.global_position + up * 1.0
	var inventory = _host.get(&"inventory")
	var pickup_collect := float(_host.get(&"pickup_collect_distance"))
	var pickup_radius := float(_host.get(&"pickup_radius"))
	for node in _host.get_tree().get_nodes_in_group(&"ground_item"):
		var item := node as Node3D
		if item == null:
			continue
		var distance := item.global_position.distance_to(hand)
		if distance <= pickup_collect:
			var resource_id := str(item.get(&"resource_id"))
			var qty := int(item.get(&"quantity"))
			var left := int(inventory.call(&"add_resource", resource_id, qty))
			if left < qty:
				AudioManager.item_pickup()
			if left <= 0:
				item.queue_free()
			else:
				item.set(&"quantity", left)
				item.set(&"pulled", false)
		elif distance <= pickup_radius and item.has_method(&"pull_toward"):
			item.call(&"pull_toward", hand)
		else:
			item.set(&"pulled", false)


func try_interact() -> void:
	var build = _host.get(&"_build")
	var chest: Node3D = build.find_target() if build != null else null
	if chest != null and chest.get("storage") != null and chest.has_method(&"open_storage"):
		chest.call(&"open_storage")
		return
	if try_open_aimed_furnace():
		return
	var ui_machine := _nearest_machine_with(&"open_ui")
	if ui_machine != null:
		ui_machine.call(&"open_ui")
		return
	var inventory = _host.get(&"inventory")
	var best := _nearest_machine_with(&"take_contents")
	if best == null:
		return
	var amount := int(best.call(&"take_contents"))
	if amount <= 0:
		return
	inventory.call(&"add_resource", str(best.get(&"output_id")), amount)


## Clic droit (ou E) : ouvre le four visé dans le rayon d’outil.
func try_open_aimed_furnace() -> bool:
	var furnace := _furnace_from_aim()
	if furnace == null:
		return false
	furnace.call(&"open_ui")
	return true


func _furnace_from_aim() -> Node3D:
	var hit := _aim_hit()
	if hit.is_empty():
		return _nearest_machine_with(&"open_ui")
	var machine := _machine_from(hit.get("collider") as Node)
	if machine == null or not machine.has_method(&"open_ui"):
		return null
	var radius := 2.6
	if "interact_radius" in machine:
		radius = float(machine.interact_radius)
	if machine.global_position.distance_to(_host.global_position) > radius:
		return null
	return machine


func _aim_hit() -> Dictionary:
	var camera := _host.get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var reach := _tool_reach()
	var origin := camera.global_position
	var forward := -camera.global_basis.z
	var space := _host.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin + forward * (reach + origin.distance_to(_host.global_position)),
		1 | 8,
		[_host.get_rid()]
	)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return {}
	if hit.position.distance_to(_host.global_position) > reach:
		return {}
	return hit


func _tool_reach() -> float:
	var body_shape: CollisionShape3D = _host.get_node_or_null(^"CollisionShape3D")
	var shape := body_shape.shape if body_shape != null else null
	if shape is CapsuleShape3D:
		var cap := shape as CapsuleShape3D
		return (cap.height + cap.radius * 2.0) * 2.0
	return 3.4


func _machine_from(node: Node) -> Node3D:
	var current := node
	while current != null:
		if current.is_in_group(&"machine"):
			return current as Node3D
		current = current.get_parent()
	return null


func _nearest_machine_with(method_name: StringName) -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for node in _host.get_tree().get_nodes_in_group(&"machine"):
		var machine := node as Node3D
		if machine == null or not machine.has_method(method_name):
			continue
		var distance := machine.global_position.distance_to(_host.global_position)
		var radius := 2.6
		if "interact_radius" in machine:
			radius = float(machine.interact_radius)
		if distance <= radius and distance < best_distance:
			best = machine
			best_distance = distance
	return best
