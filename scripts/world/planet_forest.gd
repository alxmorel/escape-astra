extends RefCounted
class_name PlanetForest

const CHOPABLE_TREE_SCRIPT := preload("res://scripts/world/chopable_tree.gd")
const FARM := preload("res://scripts/farming/farming_config.gd")
const WILD_WHEAT := preload("res://scripts/farming/wild_wheat.gd")
const ProceduralTree := preload("res://scripts/world/procedural_tree.gd")
const TREE_ARCHETYPE_COUNT := 4
const TREE_STAGE_LANDMARK := 3
const TREE_LANDMARK_CHANCE := 0.06
const PLAYER_PASSAGE := 0.9
const OBSTACLE_LAYER := 8

var forests: Array[Dictionary] = []
var cut_trees: Dictionary = {}


func build_forests(host: Node) -> void:
	forests.clear()
	var forest_chance := float(host.get(&"forest_chance"))
	if forest_chance <= 0.0:
		return
	var cap := clampi(int(round(lerpf(2.0, 7.0, forest_chance))), 1, 8)
	for direction in host.call(&"_shuffled_directions", 480):
		if forests.size() >= cap:
			break
		if randf() > forest_chance:
			continue
		if not bool(host.call(&"_is_plantable", direction)):
			continue
		var height := float(host.call(&"_terrain_height", direction))
		if float(host.call(&"_crater_mask", direction)) > 0.4 or float(host.call(&"_spring_shore", direction, height)) > 0.5:
			continue
		if float(host.call(&"_rocky_amount", direction)) > 0.45:
			continue
		var radius := randf_range(0.16, 0.30)
		var crowded := false
		for other in forests:
			var gap := acos(clampf(direction.dot(other["dir"]), -1.0, 1.0))
			if gap < radius + float(other["radius"]) * 0.75:
				crowded = true
				break
		if crowded:
			continue
		forests.append({
			"dir": direction,
			"radius": radius,
			"variant": randi() % TREE_ARCHETYPE_COUNT,
		})


func forest_cover(dir: Vector3) -> float:
	var cover := 0.0
	for patch in forests:
		var gap := acos(clampf(dir.dot(patch["dir"]), -1.0, 1.0))
		var radius := float(patch["radius"])
		if gap >= radius:
			continue
		cover = maxf(cover, 1.0 - smoothstep(radius * 0.72, radius, gap))
	return cover


func spawn_forest_trees(
	host: Node,
	parent: Node3D,
	spawn_position: Vector3,
	tree_positions: Array[Vector3],
	tree_reaches: PackedFloat32Array
) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(host.get(&"world_seed")) + 9041
	var tree_target := int(host.get(&"tree_target"))
	var forest_density := float(host.get(&"forest_density"))
	var tree_cap := clampi(int(round(float(tree_target) * forest_density)), 40, 200)
	for patch in forests:
		if tree_positions.size() >= tree_cap:
			break
		var center: Vector3 = patch["dir"]
		var patch_radius := float(patch["radius"])
		var variant := int(patch["variant"])
		var basis: Basis = host.call(&"_basis_from_up", center)
		var patch_cap := clampi(int(round(16.0 * forest_density * patch_radius / 0.22)), 6, 28)
		var placed := 0
		for _attempt in 90:
			if placed >= patch_cap or tree_positions.size() >= tree_cap:
				break
			var ang := rng.randf() * TAU
			var dist := sqrt(rng.randf()) * patch_radius
			var offset := (basis.x * cos(ang) + basis.z * sin(ang)) * dist
			offset += (basis.x * rng.randf_range(-0.02, 0.02) + basis.z * rng.randf_range(-0.02, 0.02))
			var direction := (center + offset).normalized()
			if acos(clampf(direction.dot(center), -1.0, 1.0)) > patch_radius:
				continue
			if not place_tree(host, parent, direction, spawn_position, tree_positions, tree_reaches, rng, variant):
				continue
			placed += 1


func spawn_more_trees(
	host: Node,
	parent: Node3D,
	spawn_position: Vector3,
	tree_positions: Array[Vector3],
	tree_reaches: PackedFloat32Array
) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(host.get(&"world_seed")) + 14011
	var forest_tree_density := float(host.get(&"forest_tree_density"))
	if forest_tree_density > 0.0:
		var forest_cap := clampi(int(round(260.0 * forest_tree_density)), 0, 640)
		var forest_placed := 0
		for patch in forests:
			if forest_placed >= forest_cap:
				break
			var center: Vector3 = patch["dir"]
			var patch_radius := float(patch["radius"])
			var variant := int(patch["variant"])
			var basis: Basis = host.call(&"_basis_from_up", center)
			var patch_cap := clampi(int(round(40.0 * forest_tree_density * patch_radius / 0.22)), 0, 72)
			var patch_placed := 0
			for _attempt in 160:
				if patch_placed >= patch_cap or forest_placed >= forest_cap:
					break
				var ang := rng.randf() * TAU
				var dist := sqrt(rng.randf()) * patch_radius
				var offset := (basis.x * cos(ang) + basis.z * sin(ang)) * dist
				var direction := (center + offset).normalized()
				if acos(clampf(direction.dot(center), -1.0, 1.0)) > patch_radius:
					continue
				if not place_tree(host, parent, direction, spawn_position, tree_positions, tree_reaches, rng, variant):
					continue
				patch_placed += 1
				forest_placed += 1
	var tree_density := float(host.get(&"tree_density"))
	if tree_density <= 0.0:
		return
	var normal_cap := clampi(int(round(320.0 * tree_density)), 0, 640)
	var normal_placed := 0
	var attempts := clampi(int(round(3200.0 * maxf(tree_density, 0.25))), 0, 7200)
	for _attempt in attempts:
		if normal_placed >= normal_cap:
			break
		var direction := _rng_direction(rng)
		var height := float(host.call(&"_terrain_height", direction))
		if not bool(host.call(&"_is_plantable", direction)):
			continue
		if float(host.call(&"_crater_mask", direction)) > 0.4 or float(host.call(&"_spring_shore", direction, height)) > 0.5:
			continue
		if float(host.call(&"_rocky_amount", direction)) > 0.82:
			continue
		if not place_tree(host, parent, direction, spawn_position, tree_positions, tree_reaches, rng, rng.randi() % TREE_ARCHETYPE_COUNT):
			continue
		normal_placed += 1


func place_tree(
	host: Node,
	parent: Node3D,
	direction: Vector3,
	spawn_position: Vector3,
	tree_positions: Array[Vector3],
	tree_reaches: PackedFloat32Array,
	rng: RandomNumberGenerator,
	variant: int
) -> bool:
	if not bool(host.call(&"_is_plantable", direction)):
		return false
	var position: Vector3 = host.call(&"_surface_position", direction)
	if position.distance_to(spawn_position) < 6.0:
		return false
	var stage := roll_tree_stage_with(rng)
	var structure_seed := _tree_structure_seed(host, direction, stage, variant)
	var built: Dictionary = ProceduralTree.build(structure_seed, stage, variant)
	var reach := float(built["reach"])
	if tree_blocked(position, tree_positions, tree_reaches, reach, PLAYER_PASSAGE):
		(built["root"] as Node).free()
		return false
	var key := tree_key(direction)
	var yaw := rng.randf() * TAU
	if not is_tree_cut(key):
		_spawn_built_tree(host, parent, direction, position, true, stage, variant, yaw, built)
	else:
		(built["root"] as Node).free()
	tree_positions.append(position)
	tree_reaches.append(reach)
	return true


func spawn_wild_wheat(host: Node, parent: Node3D, spawn_position: Vector3, tree_positions: Array[Vector3]) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(host.get(&"world_seed")) + 88021
	var placed: Array[Vector3] = []
	var spawn_dir := spawn_position.normalized()
	var basis: Basis = host.call(&"_basis_from_up", spawn_dir)
	_place_wheat_ring(host, rng, parent, spawn_dir, basis, spawn_position, tree_positions, placed, FARM.WILD_NEAR_MIN, FARM.WILD_NEAR_MAX, FARM.WILD_PRAIRIE, FARM.WILD_NEAR_COUNT, 280)
	if placed.size() < FARM.WILD_NEAR_COUNT:
		_place_wheat_ring(host, rng, parent, spawn_dir, basis, spawn_position, tree_positions, placed, FARM.WILD_NEAR_MIN, FARM.WILD_NEAR_MAX * 1.35, FARM.WILD_PRAIRIE_SOFT, FARM.WILD_NEAR_COUNT, 220)
	if placed.size() < FARM.WILD_NEAR_COUNT:
		_place_wheat_ring(host, rng, parent, spawn_dir, basis, spawn_position, tree_positions, placed, 4.0, 70.0, 0.12, FARM.WILD_NEAR_COUNT, 420)
	var guard := 0
	while placed.size() < FARM.WILD_TARGET and guard < 1400:
		guard += 1
		_try_wheat(host, rng, parent, _random_unit(rng), spawn_position, tree_positions, placed, FARM.WILD_PRAIRIE)


func note_cut_tree(key: String) -> void:
	if key.is_empty():
		return
	cut_trees[key] = true


func export_cut_trees() -> Dictionary:
	var keys: Array[String] = []
	for key in cut_trees:
		keys.append(str(key))
	return {"keys": keys}


func import_cut_trees(raw: Variant) -> void:
	cut_trees.clear()
	if not raw is Dictionary:
		return
	var keys: Variant = (raw as Dictionary).get("keys", [])
	if keys is Array:
		for key in keys:
			var id := str(key)
			if not id.is_empty():
				cut_trees[id] = true


func is_tree_cut(key: String) -> bool:
	return not key.is_empty() and cut_trees.has(key)


func tree_key(direction: Vector3) -> String:
	var dir := direction.normalized()
	return "%d_%d_%d" % [int(round(dir.x * 1000.0)), int(round(dir.y * 1000.0)), int(round(dir.z * 1000.0))]


func tree_blocked(position: Vector3, positions: Array[Vector3], reaches: PackedFloat32Array, own_reach: float, passage: float) -> bool:
	for i in positions.size():
		var gap := own_reach + reaches[i] + passage
		if position.distance_squared_to(positions[i]) < gap * gap:
			return true
	return false


func spawn_tree(
	host: Node,
	parent: Node3D,
	direction: Vector3,
	position: Vector3,
	harvestable: bool,
	stage: int,
	variant: int,
	yaw := -1.0
) -> void:
	var structure_seed := _tree_structure_seed(host, direction, stage, variant)
	var built: Dictionary = ProceduralTree.build(structure_seed, stage, variant)
	_spawn_built_tree(host, parent, direction, position, harvestable, stage, variant, yaw, built)


func _spawn_built_tree(
	host: Node,
	parent: Node3D,
	direction: Vector3,
	position: Vector3,
	harvestable: bool,
	stage: int,
	variant: int,
	yaw: float,
	built: Dictionary
) -> void:
	var tree := Node3D.new()
	if harvestable:
		tree.set_script(CHOPABLE_TREE_SCRIPT)
		tree.name = "Tree"
		tree.resource_id = "wood"
		tree.required_tool = "axe"
		tree.max_hits = 5
		tree.hits_per_drop = 0
		tree.drop_quantity = 1
		tree.cut_key = tree_key(direction)
	else:
		tree.name = "LandmarkTree"
	tree.set_meta(&"growth_stage", stage)
	tree.set_meta(&"tree_variant", variant)
	var up: Vector3 = host.call(&"_slope_up", direction)
	var spin := randf() * TAU if yaw < 0.0 else yaw
	var basis: Basis = host.call(&"_basis_from_up", up)
	basis = basis.rotated(up, spin)
	tree.global_transform = Transform3D(basis, position)
	var visual := built["root"] as Node3D
	tree.add_child(visual)
	if harvestable:
		tree.aim_height = float(built["height"]) * 0.55
		tree.call(
			&"setup_procedural",
			visual,
			built["trunk_xforms"],
			built["foliage_a"],
			built["foliage_b"],
			float(built["trunk_radius"]),
			int(built.get("trunk_path_count", 2))
		)
	else:
		_add_tree_collision(tree, float(built["trunk_height"]), float(built["trunk_radius"]))
	parent.add_child(tree)


func roll_tree_stage_with(rng: RandomNumberGenerator) -> int:
	if rng.randf() < TREE_LANDMARK_CHANCE:
		return TREE_STAGE_LANDMARK
	var roll := rng.randf()
	if roll < 0.4:
		return 0
	if roll < 0.75:
		return 1
	return 2


func _tree_structure_seed(host: Node, direction: Vector3, stage: int, variant: int) -> int:
	var world_seed := int(host.get(&"world_seed"))
	var key := tree_key(direction)
	return int(hash("%s:%d:%d:%d" % [key, world_seed, stage, variant]))


func _place_wheat_ring(
	host: Node,
	rng: RandomNumberGenerator,
	parent: Node3D,
	spawn_dir: Vector3,
	basis: Basis,
	spawn_position: Vector3,
	tree_positions: Array[Vector3],
	placed: Array[Vector3],
	dist_min: float,
	dist_max: float,
	prairie: float,
	goal: int,
	attempts: int
) -> void:
	var radius := maxf(spawn_position.length(), 1.0)
	for _attempt in attempts:
		if placed.size() >= goal:
			return
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(dist_min, dist_max)
		var offset := (basis.x * cos(ang) + basis.z * sin(ang)) * (dist / radius)
		_try_wheat(host, rng, parent, (spawn_dir + offset).normalized(), spawn_position, tree_positions, placed, prairie)


func _try_wheat(
	host: Node,
	rng: RandomNumberGenerator,
	parent: Node3D,
	direction: Vector3,
	spawn_position: Vector3,
	tree_positions: Array[Vector3],
	placed: Array[Vector3],
	prairie: float
) -> bool:
	if not bool(host.call(&"_is_plantable", direction)):
		return false
	var dir := direction.normalized()
	var weights: PackedFloat32Array = host.call(&"_zone_weights_from", dir, host.call(&"_terrain_height", dir))
	if weights[0] < prairie:
		return false
	if not _wheat_flat(host, dir):
		return false
	var position: Vector3 = host.call(&"_surface_position", dir)
	if position.distance_to(spawn_position) < FARM.WILD_CLEARANCE:
		return false
	if bool(host.call(&"_is_near", position, placed, FARM.WILD_SPACING)):
		return false
	if bool(host.call(&"_is_near", position, tree_positions, FARM.WILD_TREE_GAP)):
		return false
	var key := FARM.wild_key(dir)
	placed.append(position)
	if _wild_on_cooldown(key):
		return false
	var node := Node3D.new()
	node.set_script(WILD_WHEAT)
	node.name = "WildWheat"
	node.set(&"wheat_key", key)
	parent.add_child(node)
	var basis: Basis = host.call(&"_basis_from_up", dir)
	node.global_transform = Transform3D(basis.rotated(dir, rng.randf() * TAU), position)
	return true


func _wheat_flat(host: Node, dir: Vector3) -> bool:
	var up := dir.normalized()
	var height := float(host.call(&"_terrain_height", up))
	var basis: Basis = host.call(&"_basis_from_up", up)
	var step := 1.4
	var axes: Array[Vector3] = [basis.x, basis.z]
	for axis in axes:
		var tangent := axis as Vector3
		var ahead := (up * height + tangent * step).normalized()
		var behind := (up * height - tangent * step).normalized()
		if absf(float(host.call(&"_terrain_height", ahead)) - height) > FARM.WILD_FLAT:
			return false
		if absf(float(host.call(&"_terrain_height", behind)) - height) > FARM.WILD_FLAT:
			return false
	return true


func _wild_on_cooldown(key: String) -> bool:
	var saved: Variant = SaveManager.state().get("wild_wheat", {})
	if not saved is Dictionary or not (saved as Dictionary).has(key):
		return false
	return SaveManager.play_time - float((saved as Dictionary)[key]) < FARM.WILD_RESPAWN


func _random_unit(rng: RandomNumberGenerator) -> Vector3:
	var z := rng.randf_range(-1.0, 1.0)
	var ang := rng.randf_range(0.0, TAU)
	var ring := sqrt(maxf(0.0, 1.0 - z * z))
	return Vector3(ring * cos(ang), z, ring * sin(ang))


func _rng_direction(rng: RandomNumberGenerator) -> Vector3:
	var y := rng.randf_range(-1.0, 1.0)
	var ring := sqrt(maxf(0.0, 1.0 - y * y))
	var theta := rng.randf() * TAU
	return Vector3(cos(theta) * ring, y, sin(theta) * ring)


func _add_tree_collision(tree: Node3D, trunk_height: float, trunk_radius: float) -> void:
	var body := StaticBody3D.new()
	body.name = "TrunkCollision"
	body.collision_layer = OBSTACLE_LAYER
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.height = maxf(trunk_height, ProceduralTree.TRUNK_HEIGHT)
	cylinder.radius = maxf(trunk_radius, 0.2)
	collision.shape = cylinder
	collision.position = Vector3(0.0, cylinder.height * 0.5, 0.0)
	body.add_child(collision)
	tree.add_child(body)
