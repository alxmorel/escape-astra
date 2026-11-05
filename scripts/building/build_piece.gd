extends StaticBody3D

const CATALOG := preload("res://scripts/building/build_catalog.gd")
const STRUCTURE := preload("res://scripts/building/build_structure_collision.gd")
const STYLIZED := preload("res://scripts/resources/stylized_material.gd")
const STORAGE := preload("res://scripts/storage/item_container.gd")
const GROUND_ITEM := preload("res://scenes/resources/ground_item.tscn")

const MAX_DROP := 8.0

var piece_id := ""
var kind := ""
var occupancy := ""
var material_id := ""
var sockets: Array = []
var used_sockets: Dictionary = {}
var _hosts: Array = []
var _guests: Array = []
var _highlighted := false
var storage = null


func setup(id: String) -> void:
	piece_id = id
	kind = CATALOG.kind_of(id)
	occupancy = CATALOG.occupancy_of(kind)
	material_id = CATALOG.material_of(id)
	sockets = CATALOG.sockets_of(kind)
	name = id
	collision_layer = 8
	collision_mask = 0
	add_to_group(&"construction")
	add_visual(self, 1.0, id)
	if kind == "chest" or kind == "double_chest":
		storage = STORAGE.new()
		storage.setup(STORAGE.capacity_for(kind == "double_chest"))
	if CATALOG.walkable_of(kind):
		return
	for solid in CATALOG.solids_of(kind):
		_add_collision(self, solid["position"], solid["size"], "Solid")


func apply_site(planet: Node3D) -> void:
	sync_site(self, piece_id, planet, 1.0, true)
	if kind == "stairs" and planet != null:
		_set_landing_socket(CATALOG.stair_rise())
	STRUCTURE.rebuild(self)
	if kind == "chest":
		_try_merge_chest(planet)


func linked_pieces() -> Array:
	var out: Array = []
	for link in _hosts:
		var host: Node = (link as Dictionary)["host"]
		if is_instance_valid(host):
			out.append(host)
	for link in _guests:
		var guest: Node = (link as Dictionary)["guest"]
		if is_instance_valid(guest):
			out.append(guest)
	return out


func aim_point() -> Vector3:
	return global_position + global_basis.y.normalized() * CATALOG.aim_height(kind)


func attach_to(host: Node, host_index: int, plug_index: int) -> void:
	use_socket(plug_index)
	if host != null and host.has_method(&"use_socket"):
		host.call(&"use_socket", host_index)
	_hosts.append({"host": host, "host_index": host_index, "plug_index": plug_index})
	if host != null and host.has_method(&"register_guest"):
		host.call(&"register_guest", self, host_index)


func register_guest(guest: Node, host_index: int) -> void:
	_guests.append({"guest": guest, "host_index": host_index})


func release_guest(guest: Node) -> void:
	var kept: Array = []
	for link in _guests:
		if (link as Dictionary)["guest"] == guest:
			used_sockets.erase(int((link as Dictionary)["host_index"]))
		else:
			kept.append(link)
	_guests = kept


func forget_host(host: Node) -> void:
	var kept: Array = []
	for link in _hosts:
		if (link as Dictionary)["host"] == host:
			used_sockets.erase(int((link as Dictionary)["plug_index"]))
		else:
			kept.append(link)
	_hosts = kept


func is_socket_free(index: int) -> bool:
	return not used_sockets.has(index)


func use_socket(index: int) -> void:
	used_sockets[index] = true


func _set_landing_socket(rise: float) -> void:
	for socket in sockets:
		var link := str(socket["link"])
		if link != "foundation" and link != "floor":
			continue
		socket["position"] = Vector3(0, -rise - CATALOG.top_of("floor"), CATALOG.TILE)
		socket["direction"] = Vector3(0, 0, 1)


func set_highlighted(enabled: bool) -> void:
	if _highlighted == enabled:
		return
	_highlighted = enabled
	_tint_meshes(self, enabled)


func aim_distance(origin: Vector3, direction: Vector3, max_distance: float) -> float:
	return _ray_meshes(self, origin, direction, max_distance)


func export_links() -> Array:
	var out: Array = []
	for link in _hosts:
		var host: Node = (link as Dictionary)["host"]
		if not is_instance_valid(host):
			continue
		out.append({
			"host_id": host.get_instance_id(),
			"host_index": int((link as Dictionary)["host_index"]),
			"plug_index": int((link as Dictionary)["plug_index"]),
		})
	return out


func export_storage() -> Dictionary:
	if storage == null:
		return {}
	return storage.export_state()


func import_storage(data: Dictionary) -> void:
	if storage == null or data.is_empty():
		return
	var leftovers: Array = storage.import_state(data)
	for stack in leftovers:
		_give_or_drop(str(stack["id"]), int(stack["qty"]))


func open_storage() -> void:
	if storage == null:
		return
	var hud := get_tree().get_first_node_in_group(&"hud")
	if hud != null and hud.has_method(&"open_container"):
		hud.call(&"open_container", self)


func demolish() -> void:
	var seeds := linked_pieces()
	_unlink()
	_spill_storage()
	var payout: Dictionary = CATALOG.refund_of(piece_id)
	for resource_id in payout:
		_give_or_drop(str(resource_id), int(payout[resource_id]))
	STRUCTURE.rebuild_seeds(seeds, self)
	AudioManager.build_remove(material_id)
	_spawn_chips()
	queue_free()


func _try_merge_chest(planet: Node3D) -> void:
	var other := _chest_partner()
	if other == null:
		return
	var merged := (get_script() as GDScript).new() as StaticBody3D
	get_tree().current_scene.add_child(merged)
	merged.global_transform = Transform3D(global_basis, (global_position + other.global_position) * 0.5)
	merged.setup("wood_double_chest")
	for stack in merged.storage.absorb(storage):
		_give_or_drop(str(stack["id"]), int(stack["qty"]))
	for stack in merged.storage.absorb(other.storage):
		_give_or_drop(str(stack["id"]), int(stack["qty"]))
	merged.apply_site(planet)
	other._discard_quiet()
	_discard_quiet()


func _chest_partner() -> Node:
	var up := global_basis.y.normalized()
	var side := global_basis.x.normalized()
	var forward := global_basis.z.normalized()
	for node in get_tree().get_nodes_in_group(&"construction"):
		var piece := node as Node3D
		if piece == null or piece == self or str(piece.get("kind")) != "chest":
			continue
		if piece.is_queued_for_deletion():
			continue
		if global_basis.y.dot(piece.global_basis.y) < 0.92:
			continue
		if forward.dot(piece.global_basis.z.normalized()) < 0.92:
			continue
		var delta := piece.global_position - global_position
		delta -= up * delta.dot(up)
		var gap := delta.length()
		if gap < 0.85 or gap > 1.35:
			continue
		if absf(delta.normalized().dot(side)) < 0.92:
			continue
		return piece
	return null


func _discard_quiet() -> void:
	var seeds := linked_pieces()
	_unlink()
	STRUCTURE.rebuild_seeds(seeds, self)
	queue_free()


func _unlink() -> void:
	var hosts := _hosts.duplicate()
	var guests := _guests.duplicate()
	_hosts.clear()
	_guests.clear()
	for link in hosts:
		var host: Node = (link as Dictionary)["host"]
		if is_instance_valid(host) and host.has_method(&"release_guest"):
			host.call(&"release_guest", self)
	for link in guests:
		var guest: Node = (link as Dictionary)["guest"]
		if is_instance_valid(guest) and guest.has_method(&"forget_host"):
			guest.call(&"forget_host", self)


func _spill_storage() -> void:
	if storage == null:
		return
	for stack in storage.stacks():
		_give_or_drop(str(stack["id"]), int(stack["qty"]))
	storage.clear()


func _give_or_drop(resource_id: String, qty: int) -> void:
	if qty <= 0 or resource_id.is_empty():
		return
	var player := get_tree().get_first_node_in_group(&"player") as Node
	var inventory: Node = null if player == null else player.get_node_or_null(^"Inventory")
	if inventory != null and bool(inventory.call(&"fits", resource_id)):
		inventory.call(&"add_resource", resource_id, qty)
		return
	var drop := GROUND_ITEM.instantiate() as Node3D
	drop.set(&"resource_id", resource_id)
	drop.set(&"quantity", qty)
	get_tree().current_scene.add_child(drop)
	var up := global_basis.y.normalized()
	drop.global_position = aim_point() + up * 0.35


func _tint_meshes(node: Node, enabled: bool) -> void:
	if node is MeshInstance3D:
		var material := (node as MeshInstance3D).material_override as ShaderMaterial
		if material != null:
			if enabled:
				var current: Color = material.get_shader_parameter(&"albedo")
				material.set_meta(&"saved_albedo", current)
				material.set_shader_parameter(&"albedo", Color(1.0, 0.2, 0.16, current.a))
			elif material.has_meta(&"saved_albedo"):
				var saved: Color = material.get_meta(&"saved_albedo")
				material.set_shader_parameter(&"albedo", saved)
				material.remove_meta(&"saved_albedo")
	for child in node.get_children():
		_tint_meshes(child, enabled)


func _ray_meshes(node: Node, origin: Vector3, direction: Vector3, best: float) -> float:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		var inverse := mesh.global_transform.affine_inverse()
		var local_origin: Vector3 = inverse * origin
		var local_dir: Vector3 = inverse.basis * direction
		var length := local_dir.length()
		if length > 0.0001:
			var hit: Variant = mesh.get_aabb().grow(0.04).intersects_ray(local_origin, local_dir / length)
			if hit is Vector3:
				var point: Vector3 = mesh.global_transform * (hit as Vector3)
				var along := (point - origin).dot(direction)
				if along > 0.05 and along < best:
					best = along
	for child in node.get_children():
		best = _ray_meshes(child, origin, direction, best)
	return best


func _spawn_chips() -> void:
	var style: Dictionary = CATALOG.material_style(material_id)
	var origin := aim_point()
	var up := global_basis.y.normalized()
	for _i in 4:
		var chip := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3.ONE * 0.08
		chip.mesh = box
		chip.material_override = STYLIZED.create(style["color"])
		get_tree().current_scene.add_child(chip)
		chip.global_position = origin
		var spray := (up * 0.35 + Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))).normalized()
		var tween := chip.create_tween()
		tween.tween_property(chip, "global_position", origin + spray * 0.5, 0.16)
		tween.parallel().tween_property(chip, "scale", Vector3.ZERO, 0.16)
		tween.tween_callback(chip.queue_free)


static func sync_site(parent: Node3D, item_id: String, planet: Node3D, alpha: float, with_collision: bool) -> Array:
	_clear_site(parent)
	if planet == null:
		return []
	var kind_name := CATALOG.kind_of(item_id)
	var style: Dictionary = CATALOG.material_style(CATALOG.material_of(item_id))
	var materials: Array = []
	var root := StaticBody3D.new() if with_collision else Node3D.new()
	root.name = "Site"
	if root is StaticBody3D:
		root.collision_layer = 8
		root.collision_mask = 0
	parent.add_child(root)
	if kind_name == "foundation":
		var info := inspect_foundation(parent.global_transform, planet, parent.get_tree())
		var lengths: Array = info["lengths"]
		var inset := CATALOG.TILE * 0.36
		var corners: Array[Vector2] = [Vector2(inset, inset), Vector2(inset, -inset), Vector2(-inset, inset), Vector2(-inset, -inset)]
		for i in lengths.size():
			var length := float(lengths[i])
			if length < 0.08:
				continue
			var corner: Vector2 = corners[i]
			var pos := Vector3(corner.x, -length * 0.5, corner.y)
			var size := Vector3(0.16, length, 0.16)
			_add_box(root, pos, size, style["seam"], alpha, materials)
			if with_collision:
				_add_collision(root, pos, size, "Stilt")
	elif kind_name == "stairs":
		_add_stair_meshes(root, item_id, alpha, materials)
	if root.get_child_count() == 0:
		root.free()
	return materials


static func inspect_foundation(xform: Transform3D, planet: Node3D, tree: SceneTree) -> Dictionary:
	var down := -xform.basis.y.normalized()
	var half := CATALOG.TILE * 0.48
	var samples: Array[Vector3] = [
		Vector3.ZERO,
		Vector3(half, 0, half),
		Vector3(half, 0, -half),
		Vector3(-half, 0, half),
		Vector3(-half, 0, -half),
	]
	var lengths: Array = []
	var blocked := false
	for i in samples.size():
		var drop := _drop(planet, xform * samples[i], down)
		if drop < -0.06 or drop > CATALOG.max_foundation_lift() + 0.08:
			blocked = true
		if i > 0:
			lengths.append(0.0 if drop < 0.08 else drop)
	if _hits_obstacle(tree, xform, 0.0, CATALOG.FLOOR_H, CATALOG.TILE * 0.52, -1.0, lengths):
		blocked = true
	return {"ok": not blocked, "lengths": lengths, "rise": 0.0}


static func inspect_stairs(xform: Transform3D, _planet: Node3D, tree: SceneTree) -> Dictionary:
	var rise := CATALOG.stair_rise()
	var blocked := _hits_obstacle(tree, xform, -rise, 0.3, CATALOG.TILE * 0.48, CATALOG.stair_run() + 0.2, [])
	return {"ok": not blocked, "lengths": [], "rise": rise}


static func _hits_obstacle(tree: SceneTree, xform: Transform3D, low_y: float, high_y: float, reach: float, forward: float, lengths: Array) -> bool:
	if tree == null:
		return false
	var inverse := xform.affine_inverse()
	for group in [&"harvestable", &"machine"]:
		for node in tree.get_nodes_in_group(group):
			var body := node as Node3D
			if body == null or body.global_position.distance_to(xform.origin) > CATALOG.TILE * 2.0 + MAX_DROP:
				continue
			var local: Vector3 = inverse * body.global_position
			if absf(local.x) > reach:
				continue
			if forward < 0.0:
				if absf(local.z) > reach:
					continue
			elif local.z < -0.2 or local.z > forward:
				continue
			var top := local.y + 2.4
			if top > low_y and local.y < high_y:
				return true
			if lengths.is_empty():
				continue
			var inset := CATALOG.TILE * 0.36
			var corners: Array[Vector2] = [Vector2(inset, inset), Vector2(inset, -inset), Vector2(-inset, inset), Vector2(-inset, -inset)]
			for i in lengths.size():
				if float(lengths[i]) < 0.08:
					continue
				var corner: Vector2 = corners[i]
				if Vector2(local.x, local.z).distance_to(corner) > 0.55:
					continue
				if top > -float(lengths[i]) and local.y < 0.15:
					return true
	return false


static func _drop(planet: Node3D, point: Vector3, down: Vector3) -> float:
	var start := _altitude(planet, point)
	if start < -0.05:
		return start
	var prev := start
	var travelled := 0.0
	var step := 0.25
	while travelled < MAX_DROP:
		travelled += step
		var altitude := _altitude(planet, point + down * travelled)
		if altitude <= 0.0:
			var span := prev - altitude
			if span < 0.001:
				return travelled
			return travelled - step + step * (prev / span)
		prev = altitude
	return 99.0


static func _altitude(planet: Node3D, point: Vector3) -> float:
	var offset := point - planet.global_position
	var distance := offset.length()
	if distance < 0.001 or not planet.has_method(&"get_land_radius"):
		return -1.0
	return distance - float(planet.call(&"get_land_radius", offset))


static func _clear_site(parent: Node3D) -> void:
	for child in parent.get_children():
		if str(child.name) == "Site":
			parent.remove_child(child)
			child.free()


static func _add_collision(parent: Node3D, pos: Vector3, size: Vector3, shape_name: String = "Solid") -> void:
	var shape_node := CollisionShape3D.new()
	shape_node.name = shape_name
	var box := BoxShape3D.new()
	box.size = size
	shape_node.shape = box
	shape_node.position = pos
	parent.add_child(shape_node)


static func add_preview_visual(parent: Node3D, item_id: String) -> void:
	add_visual(parent, 1.0, item_id)
	if CATALOG.kind_of(item_id) != "stairs":
		return
	_add_stair_meshes(parent, item_id, 1.0, [])


static func _add_stair_meshes(parent: Node3D, item_id: String, alpha: float, materials: Array) -> void:
	var style: Dictionary = CATALOG.material_style(CATALOG.material_of(item_id))
	var rise := CATALOG.stair_rise()
	var run := CATALOG.stair_run()
	var count := CATALOG.stair_steps()
	var width := run * 0.9
	var planked := CATALOG.material_of(item_id) == "wood"
	for i in count:
		var top_y := -float(i) / float(count) * rise
		var bot_y := -float(i + 1) / float(count) * rise
		var pos := Vector3(0, (top_y + bot_y) * 0.5, run * (float(i) + 0.5) / float(count))
		var size := Vector3(width, top_y - bot_y, run / float(count))
		var boxes: Array = _planks({"position": pos, "size": size}) if planked else [{"position": pos, "size": size}]
		for box in boxes:
			var color: Color = style["seam"] if planked and materials.size() % 2 == 1 else style["color"]
			_add_box(parent, box["position"], box["size"], color, alpha, materials)


static func add_visual(parent: Node3D, alpha: float, item_id: String = "") -> Array:
	var materials: Array = []
	var kind_name := CATALOG.kind_of(item_id)
	var style: Dictionary = CATALOG.material_style(CATALOG.material_of(item_id))
	if kind_name == "chest" or kind_name == "double_chest":
		_add_chest_visual(parent, kind_name == "double_chest", style, alpha, materials)
		return materials
	var planked := CATALOG.material_of(item_id) == "wood"
	for solid in CATALOG.solids_of(kind_name):
		var boxes: Array = _planks(solid) if planked else [solid]
		for i in boxes.size():
			var box: Dictionary = boxes[i]
			var color: Color = style["seam"] if planked and i % 2 == 1 else style["color"]
			_add_box(parent, box["position"], box["size"], color, alpha, materials)
	return materials


static func _add_chest_visual(parent: Node3D, wide: bool, style: Dictionary, alpha: float, materials: Array) -> void:
	var width := 2.16 if wide else 1.08
	var body := Color(style["color"])
	var lid := Color(style["seam"])
	_add_box(parent, Vector3(0, 0.28, 0), Vector3(width, 0.5, 0.66), body, alpha, materials)
	_add_box(parent, Vector3(0, 0.64, 0), Vector3(width, 0.22, 0.66), lid, alpha, materials)
	_add_box(parent, Vector3(0, 0.5, 0.34), Vector3(0.1, 0.1, 0.05), Color(0.78, 0.64, 0.28), alpha, materials)
	if wide:
		_add_box(parent, Vector3(0, 0.39, 0), Vector3(0.04, 0.78, 0.7), lid, alpha, materials)


static func _planks(solid: Dictionary) -> Array:
	var size: Vector3 = solid["size"]
	var origin: Vector3 = solid["position"]
	var dims := [size.x, size.y, size.z]
	dims.sort()
	if dims[1] < 1.15:
		return [solid]
	var axis := 0
	var span := size.x
	if size.y > span:
		axis = 1
		span = size.y
	if size.z > span:
		axis = 2
		span = size.z
	var count := clampi(int(span / 0.52), 2, 7)
	var gap := 0.02
	var thickness := (span - gap * float(count - 1)) / float(count)
	var cursor := -span * 0.5 + thickness * 0.5
	var boxes: Array = []
	for _i in count:
		var position := origin
		var box_size := size
		if axis == 0:
			position.x += cursor
			box_size.x = thickness
		elif axis == 1:
			position.y += cursor
			box_size.y = thickness
		else:
			position.z += cursor
			box_size.z = thickness
		boxes.append({"position": position, "size": box_size})
		cursor += thickness + gap
	return boxes


static func _add_box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, alpha: float, materials: Array) -> void:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.position = pos
	if alpha < 0.99:
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := STYLIZED.create(color, alpha)
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)
	materials.append(material)
