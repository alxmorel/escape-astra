extends SceneTree

const ChopableTree := preload("res://scripts/world/chopable_tree.gd")
const ProceduralTree := preload("res://scripts/world/procedural_tree.gd")
const FallingTreeBody := preload("res://scripts/world/falling_tree_body.gd")


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	current_scene = root
	var failed := false
	if not await _cut_segment_becomes_first_fall_log():
		failed = true
	if not await _first_fall_log_is_harvestable():
		failed = true
	quit(1 if failed else 0)


func _cut_segment_becomes_first_fall_log() -> bool:
	var tree: Node3D = ChopableTree.new()
	root.add_child(tree)
	var visual := Node3D.new()
	visual.name = "Visual"
	tree.add_child(visual)
	var trunks: Array[Transform3D] = []
	for i in 4:
		trunks.append(Transform3D(Basis.IDENTITY, Vector3(0.0, float(i) * ProceduralTree.TRUNK_HEIGHT, 0.0)))
	var empty: Array[Transform3D] = []
	tree.call(
		&"setup_procedural",
		visual,
		trunks,
		empty,
		empty,
		ProceduralTree.TRUNK_RADIUS,
		4
	)
	# Deux coups sur la 1re bûche → abattage (avec délai de bounce).
	var hit_a := tree.to_global(ProceduralTree.segment_mid(trunks[0]))
	tree.call(&"receive_hit", "wooden_axe", hit_a)
	tree.call(&"receive_hit", "wooden_axe", hit_a)
	await create_timer(0.12).timeout
	if not bool(tree.call(&"is_chop_falling")):
		push_error("l'arbre n'est pas tombé")
		return false
	var fall_trunks: Array = tree.get("_fall_trunks")
	if fall_trunks.is_empty():
		push_error("aucune bûche en chute")
		return false
	var first: Transform3D = fall_trunks[0]
	if not first.origin.is_equal_approx(trunks[0].origin):
		push_error("la 1re bûche coupée n'est pas dans la chute (origin=%s)" % first.origin)
		return false
	return true


func _first_fall_log_is_harvestable() -> bool:
	var body: RigidBody3D = FallingTreeBody.new()
	root.add_child(body)
	var visual := Node3D.new()
	visual.name = "FallVisual"
	body.add_child(visual)
	var trunks: Array[Transform3D] = []
	for i in 3:
		trunks.append(Transform3D(Basis.IDENTITY, Vector3(0.0, float(i) * ProceduralTree.TRUNK_HEIGHT, 0.0)))
	var empty: Array[Transform3D] = []
	ProceduralTree.fill_visual(visual, trunks, empty, empty)
	for i in trunks.size():
		var shape := CollisionShape3D.new()
		shape.name = "SegCollision_%d" % i
		var cylinder := CylinderShape3D.new()
		cylinder.height = 0.8
		cylinder.radius = 0.3
		shape.shape = cylinder
		shape.transform = Transform3D(Basis.IDENTITY, ProceduralTree.segment_mid(trunks[i]))
		body.add_child(shape)
	body.call(&"enable_ground_harvest", trunks, 0.4)
	var first_mid := body.to_global(ProceduralTree.segment_mid(trunks[0]))
	if not bool(body.call(&"receive_hit", "wooden_axe", first_mid)):
		push_error("1er coup sur la 1re bûche refusé")
		return false
	if not bool(body.call(&"receive_hit", "wooden_axe", first_mid)):
		push_error("2e coup sur la 1re bûche refusé")
		return false
	await create_timer(0.12).timeout
	var alive: Array = body.get("_alive")
	if alive.is_empty() or bool(alive[0]):
		push_error("la 1re bûche au sol n'a pas été détruite")
		return false
	if body.get_node_or_null("SegCollision_0") != null:
		push_error("collision de la 1re bûche encore présente")
		return false
	return true
