extends SceneTree

const ProceduralTree := preload("res://scripts/world/procedural_tree.gd")
const FallingTreeBody := preload("res://scripts/world/falling_tree_body.gd")


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var failed := false
	if not await _shed_once_and_clear():
		failed = true
	quit(1 if failed else 0)


func _shed_once_and_clear() -> bool:
	var body: RigidBody3D = FallingTreeBody.new()
	body.name = "FallingTree"
	root.add_child(body)
	var visual := Node3D.new()
	visual.name = "FallVisual"
	body.add_child(visual)
	var trunks: Array[Transform3D] = [Transform3D(Basis.IDENTITY, Vector3(0.0, 0.2, 0.0))]
	var leaves_a: Array[Transform3D] = []
	var leaves_b: Array[Transform3D] = []
	for i in 3:
		leaves_a.append(Transform3D(Basis.IDENTITY, Vector3(0.4 + 0.2 * i, 1.6, 0.2)))
		leaves_b.append(Transform3D(Basis.IDENTITY, Vector3(-0.5 - 0.15 * i, 1.9, -0.2)))
	ProceduralTree.fill_visual(visual, trunks, leaves_a, leaves_b)
	if visual.get_node_or_null(^"tronc_arbre") == null:
		push_error("tronc absent")
		return false
	if _foliage_nodes(visual).is_empty():
		push_error("feuillage multimesh absent")
		return false
	var shape := CollisionShape3D.new()
	shape.name = "SegCollision_0"
	var cylinder := CylinderShape3D.new()
	cylinder.height = 0.8
	cylinder.radius = 0.3
	shape.shape = cylinder
	body.add_child(shape)
	body.mass = 4.4
	body.freeze = false
	body.collision_layer = 8
	body.collision_mask = 1
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = Vector3(0.2, 1.1, 0.0)
	var snap := _physics_snap(body)

	body.call(&"enable_ground_harvest", trunks, 0.4)
	body.call(&"strip_foliage")
	body.call(&"strip_foliage")

	var leaves := _leaf_bodies(root)
	if leaves.size() != 6:
		push_error("feuilles physiques %d au lieu de 6" % leaves.size())
		return false
	if not _foliage_nodes(visual).is_empty():
		push_error("multimesh feuillage encore dans FallVisual")
		return false
	if not _same_physics(body, snap):
		return false
	for leaf in leaves:
		if leaf.get_parent() == body:
			push_error("feuille encore enfant du tronc")
			return false
		if leaf.collision_layer != 0:
			push_error("feuille peut pousser le tronc (layer=%d)" % leaf.collision_layer)
			return false
		if leaf.gravity_scale != 0.0:
			push_error("feuille utilise la gravité Godot au lieu de la planétaire")
			return false
		if leaf.find_children("*", "CollisionShape3D", true, false).is_empty():
			push_error("feuille sans collision sol")
			return false

	body.call(&"_refresh_trunk_visual_only")
	var hit: bool = body.call(&"receive_hit", "wooden_axe", body.global_position)
	if not hit or _shapes(body) != 1 or not body.is_in_group(&"harvestable"):
		push_error("tronc non découpable pendant la chute du feuillage")
		return false
	if not _same_physics(body, snap):
		return false

	await create_timer(1.0).timeout
	if _leaf_bodies(root).size() != 6:
		push_error("disparition trop tôt : %d" % _leaf_bodies(root).size())
		return false

	await create_timer(1.3).timeout
	await process_frame
	if not _leaf_bodies(root).is_empty():
		push_error("feuillage restant après 2 s : %d" % _leaf_bodies(root).size())
		return false
	if not is_instance_valid(body) or not body.is_in_group(&"harvestable") or not _same_physics(body, snap):
		push_error("tronc altéré à la fin")
		return false
	body.call(&"strip_foliage")
	if not _leaf_bodies(root).is_empty():
		push_error("la séquence a redémarré")
		return false
	return true


func _physics_snap(body: RigidBody3D) -> Dictionary:
	return {
		"mass": body.mass,
		"freeze": body.freeze,
		"layer": body.collision_layer,
		"mask": body.collision_mask,
		"com": body.center_of_mass,
		"shapes": _shapes(body),
	}


func _same_physics(body: RigidBody3D, snap: Dictionary) -> bool:
	var ok := (
		is_equal_approx(body.mass, float(snap["mass"]))
		and body.freeze == bool(snap["freeze"])
		and body.collision_layer == int(snap["layer"])
		and body.collision_mask == int(snap["mask"])
		and body.center_of_mass.is_equal_approx(snap["com"])
		and _shapes(body) == int(snap["shapes"])
	)
	if not ok:
		push_error(
			"physique modifiée mass=%s freeze=%s layer=%s shapes=%s"
			% [body.mass, body.freeze, body.collision_layer, _shapes(body)]
		)
	return ok


func _shapes(body: Node) -> int:
	var n := 0
	for child in body.get_children():
		if child is CollisionShape3D:
			n += 1
	return n


func _foliage_nodes(visual: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in visual.get_children():
		if str(child.name).to_lower().begins_with("feuillage"):
			out.append(child)
	return out


func _leaf_bodies(_node: Node) -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = []
	for node in get_nodes_in_group(&"foliage_leaf"):
		if is_instance_valid(node) and node is RigidBody3D and not node.is_queued_for_deletion():
			out.append(node as RigidBody3D)
	return out
