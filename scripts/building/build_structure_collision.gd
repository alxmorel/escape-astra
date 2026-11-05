extends RefCounted

# Collision praticable d'une structure connectée. Les meshes restent sur chaque BuildPiece.

const CATALOG := preload("res://scripts/building/build_catalog.gd")
const STYLIZED := preload("res://scripts/resources/stylized_material.gd")

const DEBUG_COLLISIONS := false
const JOIN := 0.04

static var _owner: Dictionary = {}
static var _bodies: Array = []


static func rebuild(piece: Node) -> void:
	rebuild_seeds([piece], null)


static func rebuild_seeds(seeds: Array, removed: Node) -> void:
	if removed != null:
		_owner.erase(removed.get_instance_id())
	var seen: Dictionary = {}
	var components: Array = []
	for seed in seeds:
		var node := seed as Node
		if not is_instance_valid(node) or node == removed or seen.has(node.get_instance_id()):
			continue
		var component := _collect(node, removed)
		for member in component:
			seen[(member as Node).get_instance_id()] = true
		components.append(component)
	for id in seen:
		_owner.erase(id)
	for component in components:
		_build(component as Array)
	_drop_unused()


static func _collect(seed: Node, removed: Node) -> Array:
	var out: Array = []
	var stack: Array = [seed]
	var seen: Dictionary = {seed.get_instance_id(): true}
	while not stack.is_empty():
		var piece: Node = stack.pop_back()
		if not is_instance_valid(piece) or piece == removed:
			continue
		out.append(piece)
		if not piece.has_method(&"linked_pieces"):
			continue
		for other in piece.call(&"linked_pieces"):
			var next := other as Node
			if not is_instance_valid(next) or next == removed or seen.has(next.get_instance_id()):
				continue
			seen[next.get_instance_id()] = true
			stack.append(next)
	return out


static func _build(component: Array) -> void:
	if component.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "BuildStructure"
	body.collision_layer = 8
	body.collision_mask = 0
	_scene_of(component[0] as Node).add_child(body)
	_bodies.append(body)
	var frame := _frame(component)
	body.global_transform = frame
	for box in _floor_boxes(component, frame):
		_add_box(body, box)
	for member in component:
		if str(member.get("kind")) == "stairs":
			_add_stair(body, member as Node3D, frame)
	if body.get_child_count() == 0:
		_release(body)
		return
	for member in component:
		_owner[(member as Node).get_instance_id()] = body


static func _frame(component: Array) -> Transform3D:
	for member in component:
		var piece := member as Node3D
		if piece != null and _is_floor(piece):
			return piece.global_transform
	return (component[0] as Node3D).global_transform


static func _floor_boxes(component: Array, frame: Transform3D) -> Array:
	var groups: Dictionary = {}
	var boxes: Array = []
	for member in component:
		var piece := member as Node3D
		if piece == null or not _is_floor(piece):
			continue
		if not _aligned(piece, frame):
			boxes.append(_solo_box(piece, frame))
			continue
		var top := _surface_local_y(piece, frame)
		var key := "%s:%s" % [str(piece.get("kind")), roundi(top * 1000.0)]
		if not groups.has(key):
			groups[key] = []
		var bucket: Array = groups[key]
		bucket.append(piece)
		groups[key] = bucket
	for key in groups:
		boxes.append_array(_rectangles(groups[key], frame))
	return boxes


static func _rectangles(pieces: Array, frame: Transform3D) -> Array:
	var cells: Dictionary = {}
	for member in pieces:
		var piece := member as Node3D
		var local: Vector3 = frame.affine_inverse() * piece.global_position
		cells[Vector2i(roundi(local.x / CATALOG.TILE), roundi(local.z / CATALOG.TILE))] = piece
	var keys: Array = cells.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.x == b.x:
			return a.y < b.y
		return a.x < b.x
	)
	var used: Dictionary = {}
	var spans: Array = []
	for key in keys:
		var cell: Vector2i = key
		if used.has(cell):
			continue
		var x1 := cell.x
		while _open(cells, used, Vector2i(x1 + 1, cell.y)):
			x1 += 1
		var z1 := cell.y
		while _row_open(cells, used, cell.x, x1, z1 + 1):
			z1 += 1
		var index := spans.size()
		for x in range(cell.x, x1 + 1):
			for z in range(cell.y, z1 + 1):
				used[Vector2i(x, z)] = index
		spans.append({"x0": cell.x, "x1": x1, "z0": cell.y, "z1": z1, "sample": cells[cell]})
	var rects: Array = []
	for span in spans:
		rects.append(_rect_box(span["sample"], frame, int(span["x0"]), int(span["x1"]), int(span["z0"]), int(span["z1"])))
	rects.append_array(_joint_pads(cells, used, frame))
	return rects


static func _joint_pads(cells: Dictionary, used: Dictionary, frame: Transform3D) -> Array:
	var pads: Array = []
	for key in cells:
		var cell: Vector2i = key
		var right := Vector2i(cell.x + 1, cell.y)
		var ahead := Vector2i(cell.x, cell.y + 1)
		if cells.has(right) and int(used[cell]) != int(used[right]):
			pads.append(_pad(cells[cell], frame, cell, Vector2i(1, 0)))
		if cells.has(ahead) and int(used[cell]) != int(used[ahead]):
			pads.append(_pad(cells[cell], frame, cell, Vector2i(0, 1)))
	return pads


static func _pad(sample: Node3D, frame: Transform3D, cell: Vector2i, step: Vector2i) -> Dictionary:
	var kind := str(sample.get("kind"))
	var thick := _thickness(kind)
	var top := _surface_local_y(sample, frame)
	var pos := Vector3((float(cell.x) + float(step.x) * 0.5) * CATALOG.TILE, top - thick * 0.5, (float(cell.y) + float(step.y) * 0.5) * CATALOG.TILE)
	var size := Vector3(CATALOG.TILE, thick, JOIN * 2.0) if step.y != 0 else Vector3(JOIN * 2.0, thick, CATALOG.TILE)
	return {"position": pos, "size": size}


static func _rect_box(sample: Node3D, frame: Transform3D, x0: int, x1: int, z0: int, z1: int) -> Dictionary:
	var kind := str(sample.get("kind"))
	var thick := _thickness(kind)
	var extra := CATALOG.THICK if kind == "ceiling" else 0.0
	var top := _surface_local_y(sample, frame)
	var pos := Vector3((x0 + x1) * 0.5 * CATALOG.TILE, top - thick * 0.5, (z0 + z1) * 0.5 * CATALOG.TILE)
	var size := Vector3((x1 - x0 + 1) * CATALOG.TILE + extra, thick, (z1 - z0 + 1) * CATALOG.TILE + extra)
	return {"position": pos, "size": size}


static func _solo_box(piece: Node3D, frame: Transform3D) -> Dictionary:
	var kind := str(piece.get("kind"))
	var thick := _thickness(kind)
	var extra := CATALOG.THICK if kind == "ceiling" else 0.0
	var into: Transform3D = frame.affine_inverse() * piece.global_transform
	var pos := Vector3(0, _top(kind) - thick * 0.5, 0)
	return {
		"position": into * pos,
		"size": Vector3(CATALOG.TILE + extra, thick, CATALOG.TILE + extra),
		"basis": into.basis,
	}


static func _add_stair(body: StaticBody3D, stair: Node3D, frame: Transform3D) -> void:
	var rise := CATALOG.stair_rise()
	var half := CATALOG.TILE * 0.5
	var length := CATALOG.stair_run()
	var tread := length / float(CATALOG.stair_steps())
	var into: Transform3D = frame.affine_inverse() * stair.global_transform
	var slope := PackedVector3Array([
		Vector3(-half, 0.0, 0.0),
		Vector3(half, 0.0, 0.0),
		Vector3(-half, 0.0, tread),
		Vector3(half, 0.0, tread),
		Vector3(-half, -rise, length),
		Vector3(half, -rise, length),
	])
	_add_convex(body, slope, into, CATALOG.FLOOR_H, -rise)


static func _add_box(body: StaticBody3D, box: Dictionary) -> void:
	var shape_node := CollisionShape3D.new()
	shape_node.name = "Walk"
	var shape := BoxShape3D.new()
	shape.size = box["size"]
	shape_node.shape = shape
	shape_node.position = box["position"]
	if box.has("basis"):
		shape_node.basis = box["basis"]
	body.add_child(shape_node)
	if not DEBUG_COLLISIONS:
		return
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "CollisionDebug"
	var mesh := BoxMesh.new()
	mesh.size = box["size"]
	mesh_instance.mesh = mesh
	mesh_instance.position = box["position"]
	if box.has("basis"):
		mesh_instance.basis = box["basis"]
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.material_override = STYLIZED.create(Color(0.2, 0.9, 0.45), 0.3)
	body.add_child(mesh_instance)


static func _add_convex(body: StaticBody3D, local_points: PackedVector3Array, into: Transform3D, depth: float, floor_y: float) -> void:
	var points := PackedVector3Array()
	for point in local_points:
		points.append(into * point)
	for point in local_points:
		var sunk := point + Vector3(0.0, -depth, 0.0)
		sunk.y = maxf(sunk.y, floor_y)
		points.append(into * sunk)
	var shape_node := CollisionShape3D.new()
	shape_node.name = "StairWalk"
	var ramp := ConvexPolygonShape3D.new()
	ramp.points = points
	ramp.margin = 0.0
	shape_node.shape = ramp
	body.add_child(shape_node)
	_debug_ramp(body, points)


static func _debug_ramp(body: StaticBody3D, points: PackedVector3Array) -> void:
	if not DEBUG_COLLISIONS or points.size() < 8:
		return
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "CollisionDebug"
	var immediate := ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads: Array[PackedInt32Array] = [
		PackedInt32Array([0, 1, 3, 2]),
		PackedInt32Array([2, 3, 5, 4]),
	]
	for quad in quads:
		immediate.surface_add_vertex(points[quad[0]])
		immediate.surface_add_vertex(points[quad[1]])
		immediate.surface_add_vertex(points[quad[2]])
		immediate.surface_add_vertex(points[quad[0]])
		immediate.surface_add_vertex(points[quad[2]])
		immediate.surface_add_vertex(points[quad[3]])
	immediate.surface_end()
	mesh_instance.mesh = immediate
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.material_override = STYLIZED.create(Color(0.95, 0.7, 0.2), 0.35)
	body.add_child(mesh_instance)


static func _aligned(piece: Node3D, frame: Transform3D) -> bool:
	if piece.global_basis.y.dot(frame.basis.y) < 0.999:
		return false
	var local: Vector3 = frame.affine_inverse() * piece.global_position
	var err_x := absf(local.x / CATALOG.TILE - float(roundi(local.x / CATALOG.TILE)))
	var err_z := absf(local.z / CATALOG.TILE - float(roundi(local.z / CATALOG.TILE)))
	return err_x < 0.08 and err_z < 0.08


static func _is_floor(piece: Node3D) -> bool:
	var kind := str(piece.get("kind"))
	return kind == "foundation" or kind == "floor" or kind == "ceiling"


static func _surface_local_y(piece: Node3D, frame: Transform3D) -> float:
	var world: Vector3 = piece.global_position + piece.global_basis.y * _top(str(piece.get("kind")))
	return (frame.affine_inverse() * world).y


static func _top(kind: String) -> float:
	if kind == "ceiling":
		return CATALOG.CEIL_H - 0.05
	return CATALOG.FLOOR_H


static func _thickness(kind: String) -> float:
	return CATALOG.CEIL_H if kind == "ceiling" else CATALOG.FLOOR_H


static func _open(cells: Dictionary, used: Dictionary, cell: Vector2i) -> bool:
	return cells.has(cell) and not used.has(cell)


static func _row_open(cells: Dictionary, used: Dictionary, x0: int, x1: int, z: int) -> bool:
	for x in range(x0, x1 + 1):
		if not _open(cells, used, Vector2i(x, z)):
			return false
	return true


static func _scene_of(piece: Node) -> Node:
	var tree := piece.get_tree()
	if tree != null and tree.current_scene != null:
		return tree.current_scene
	return piece.get_parent()


static func _release(body: StaticBody3D) -> void:
	_bodies.erase(body)
	var ids: Array = _owner.keys()
	for id in ids:
		if _owner[id] == body:
			_owner.erase(id)
	if is_instance_valid(body):
		body.queue_free()


static func _drop_unused() -> void:
	var used: Dictionary = {}
	for id in _owner:
		used[_owner[id]] = true
	var leftover: Array = []
	for body in _bodies:
		if not used.has(body):
			leftover.append(body)
	for body in leftover:
		_release(body as StaticBody3D)
