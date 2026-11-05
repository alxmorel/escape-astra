extends RefCounted
class_name PlanetRocks

const HARVESTABLE_SCRIPT := preload("res://scripts/resources/harvestable.gd")
const STYLIZED := preload("res://scripts/resources/stylized_material.gd")
const ROCK_SCENES: Array = [
	preload("res://assets/models/rock_01.glb"),
	preload("res://assets/models/rock_02.glb"),
	preload("res://assets/models/rock_03.glb"),
]
const IRON_SCENES: Array = [
	preload("res://assets/models/iron_rock_01.glb"),
	preload("res://assets/models/iron_rock_02.glb"),
	preload("res://assets/models/iron_rock_03.glb"),
]
const COAL_SCENES: Array = [
	preload("res://assets/models/coal_rock_01.glb"),
	preload("res://assets/models/coal_rock_02.glb"),
]
const OBSTACLE_LAYER := 8

var rock_mesh: BoxMesh
var rock_material: ShaderMaterial
var cut_rocks: Dictionary = {}


func ensure_resources() -> void:
	if rock_mesh != null:
		return
	rock_mesh = BoxMesh.new()
	rock_material = STYLIZED.create(Color(0.46, 0.46, 0.48))


func rock_key(direction: Vector3) -> String:
	var dir := direction.normalized()
	return "%d_%d_%d" % [int(round(dir.x * 1000.0)), int(round(dir.y * 1000.0)), int(round(dir.z * 1000.0))]


func iron_key(direction: Vector3) -> String:
	return "iron_%s" % rock_key(direction)


func coal_key(direction: Vector3) -> String:
	return "coal_%s" % rock_key(direction)


func note_cut_rock(key: String) -> void:
	if key.is_empty():
		return
	cut_rocks[key] = true


func export_cut_rocks() -> Dictionary:
	var keys: Array[String] = []
	for key in cut_rocks:
		keys.append(str(key))
	return {"keys": keys}


func import_cut_rocks(raw: Variant) -> void:
	cut_rocks.clear()
	if not raw is Dictionary:
		return
	var keys: Variant = (raw as Dictionary).get("keys", [])
	if keys is Array:
		for key in keys:
			var id := str(key)
			if not id.is_empty():
				cut_rocks[id] = true


func is_rock_cut(key: String) -> bool:
	return not key.is_empty() and cut_rocks.has(key)


func burn_harvestable_rng() -> void:
	randi()
	randf()
	randf()
	randf()


func burn_iron_rng(rng: RandomNumberGenerator) -> void:
	rng.randi()
	rng.randf()
	rng.randf()


func burn_coal_rng(rng: RandomNumberGenerator) -> void:
	rng.randi()
	rng.randf()
	rng.randf()


func spawn_harvestable(host: Node, parent: Node3D, direction: Vector3, position: Vector3, key: String = "") -> void:
	var up := direction.normalized()
	var variant := randi() % ROCK_SCENES.size()
	var uniform_scale := randf_range(0.85, 1.15)
	var yaw := randf() * TAU
	var rock := Node3D.new()
	rock.set_script(HARVESTABLE_SCRIPT)
	rock.name = "Rock"
	rock.resource_id = "stone"
	rock.required_tool = "pickaxe"
	rock.max_hits = 5
	rock.hits_per_drop = 1
	rock.drop_quantity = 1
	rock.chip_color = Color(0.62, 0.62, 0.66)
	rock.cut_key = key if not key.is_empty() else rock_key(direction)
	var basis: Basis = host.call(&"_basis_from_up", up)
	rock.global_transform = Transform3D(basis.rotated(up, yaw), position)
	var visual := instantiate(variant, uniform_scale)
	rock.add_child(visual)
	var fitted: AABB = host.call(&"_ground_fit", visual)
	visual.position.y -= fitted.size.y * randf_range(0.0, 1.0)
	rock.aim_height = maxf(fitted.size.y * 0.55, 0.35)
	add_collision(host, rock)
	parent.add_child(rock)


func spawn_iron_deposit(
	host: Node,
	parent: Node3D,
	direction: Vector3,
	surface_position: Vector3,
	burial_depth: float,
	rng: RandomNumberGenerator,
	key: String = ""
) -> void:
	var up := direction.normalized()
	var variant := rng.randi() % IRON_SCENES.size()
	var uniform_scale := rng.randf_range(0.9, 1.2)
	var yaw := rng.randf() * TAU
	var rock := Node3D.new()
	rock.set_script(HARVESTABLE_SCRIPT)
	rock.name = "IronDeposit"
	rock.resource_id = "iron_ore"
	rock.required_tool = "pickaxe"
	rock.max_hits = 5
	rock.hits_per_drop = 1
	rock.drop_quantity = 1
	rock.chip_color = Color(0.55, 0.42, 0.36)
	rock.cut_key = key if not key.is_empty() else iron_key(direction)
	rock.set_meta(&"skip_terrain_snap", true)
	var visual := instantiate_iron(variant, uniform_scale)
	rock.add_child(visual)
	var fitted: AABB = host.call(&"_ground_fit", visual)
	var bury := maxf(burial_depth, 0.2) + fitted.size.y
	var basis: Basis = host.call(&"_basis_from_up", up)
	rock.global_transform = Transform3D(basis.rotated(up, yaw), surface_position - up * bury)
	rock.aim_height = maxf(fitted.size.y * 0.55, 0.35)
	add_collision(host, rock)
	parent.add_child(rock)


func spawn_coal_deposit(
	host: Node,
	parent: Node3D,
	direction: Vector3,
	surface_position: Vector3,
	burial_depth: float,
	rng: RandomNumberGenerator,
	key: String = ""
) -> void:
	var up := direction.normalized()
	var variant := rng.randi() % COAL_SCENES.size()
	var uniform_scale := rng.randf_range(0.9, 1.2)
	var yaw := rng.randf() * TAU
	var rock := Node3D.new()
	rock.set_script(HARVESTABLE_SCRIPT)
	rock.name = "CoalDeposit"
	rock.resource_id = "coal"
	rock.required_tool = "pickaxe"
	rock.max_hits = 5
	rock.hits_per_drop = 1
	rock.drop_quantity = 1
	rock.chip_color = Color(0.18, 0.18, 0.2)
	rock.cut_key = key if not key.is_empty() else coal_key(direction)
	rock.set_meta(&"skip_terrain_snap", true)
	var visual := instantiate_coal(variant, uniform_scale)
	rock.add_child(visual)
	var fitted: AABB = host.call(&"_ground_fit", visual)
	var bury := maxf(burial_depth, 0.15) + fitted.size.y
	var basis: Basis = host.call(&"_basis_from_up", up)
	rock.global_transform = Transform3D(basis.rotated(up, yaw), surface_position - up * bury)
	rock.aim_height = maxf(fitted.size.y * 0.55, 0.35)
	add_collision(host, rock)
	parent.add_child(rock)


func instantiate(variant: int, uniform_scale: float) -> Node3D:
	var scene: PackedScene = ROCK_SCENES[posmod(variant, ROCK_SCENES.size())]
	var visual := scene.instantiate() as Node3D
	visual.scale = Vector3.ONE * uniform_scale
	return visual


func instantiate_iron(variant: int, uniform_scale: float) -> Node3D:
	var scene: PackedScene = IRON_SCENES[posmod(variant, IRON_SCENES.size())]
	var visual := scene.instantiate() as Node3D
	visual.scale = Vector3.ONE * uniform_scale
	return visual


func instantiate_coal(variant: int, uniform_scale: float) -> Node3D:
	var scene: PackedScene = COAL_SCENES[posmod(variant, COAL_SCENES.size())]
	var visual := scene.instantiate() as Node3D
	visual.scale = Vector3.ONE * uniform_scale
	return visual


func add_collision(host: Node, rock: Node3D) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = OBSTACLE_LAYER
	body.collision_mask = 0
	for node in rock.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		var local_box := mesh_node.get_aabb()
		var xform: Transform3D = host.call(&"_mesh_transform", rock, mesh_node)
		var scale := xform.basis.get_scale()
		var collision := CollisionShape3D.new()
		collision.transform = Transform3D(xform.basis.orthonormalized(), xform * local_box.get_center())
		var box := BoxShape3D.new()
		box.size = local_box.size * scale
		collision.shape = box
		body.add_child(collision)
	rock.add_child(body)


func spawn_landmarks(host: Node) -> void:
	var landmark_count := int(host.get(&"landmark_count"))
	if landmark_count < 2:
		return
	ensure_resources()
	var root := Node3D.new()
	root.name = "Landmarks"
	host.add_child(root)
	var rocky_dir: Vector3 = host.call(&"_best_zone_direction", 2)
	if rocky_dir != Vector3.ZERO:
		spawn_formation(host, root, rocky_dir)
	if landmark_count < 3 or rocky_dir == Vector3.ZERO:
		return
	var side: Vector3 = (host.call(&"_basis_from_up", rocky_dir) as Basis).x
	var cave_dir := (rocky_dir + side * 0.18).normalized()
	if bool(host.call(&"_is_plantable", cave_dir)):
		spawn_cave_mouth(host, root, cave_dir)


func spawn_formation(host: Node, parent: Node3D, direction: Vector3) -> void:
	var up := direction.normalized()
	var origin: Vector3 = host.call(&"_surface_position", up)
	var basis: Basis = host.call(&"_basis_from_up", up)
	spawn_visual(host, parent, up, origin, 2.4)
	for i in 4:
		var offset := basis * Vector3(cos(float(i) * TAU / 4.0), 0.0, sin(float(i) * TAU / 4.0)) * 1.35
		var dir := (origin + offset).normalized()
		spawn_visual(host, parent, dir, host.call(&"_surface_position", dir), 1.15 + float(i % 2) * 0.35)


func spawn_visual(host: Node, parent: Node3D, direction: Vector3, position: Vector3, size: float) -> void:
	ensure_resources()
	var up := direction.normalized()
	var rock := StaticBody3D.new()
	rock.name = "RockFormation"
	rock.collision_layer = OBSTACLE_LAYER
	rock.collision_mask = 0
	var basis: Basis = host.call(&"_basis_from_up", up)
	rock.global_transform = Transform3D(basis.rotated(up, randf() * TAU), position + up * size * 0.28)
	rock.scale = Vector3(size * 0.85, size * 0.7, size)
	var mesh := MeshInstance3D.new()
	mesh.mesh = rock_mesh
	mesh.material_override = rock_material
	rock.add_child(mesh)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE
	collision.shape = box
	rock.add_child(collision)
	parent.add_child(rock)


func spawn_cave_mouth(host: Node, parent: Node3D, direction: Vector3) -> void:
	var up := direction.normalized()
	var root := Node3D.new()
	root.name = "CaveMouth"
	var basis: Basis = host.call(&"_basis_from_up", up)
	root.global_transform = Transform3D(basis, host.call(&"_surface_position", up))
	parent.add_child(root)
	var dark := StandardMaterial3D.new()
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dark.albedo_color = Color(0.04, 0.04, 0.05)
	var hole := MeshInstance3D.new()
	hole.mesh = BoxMesh.new()
	hole.material_override = dark
	hole.position = Vector3(0.0, 0.7, -0.2)
	hole.scale = Vector3(1.05, 1.15, 0.7)
	root.add_child(hole)
	add_arch_block(root, Vector3(-0.85, 0.75, 0.2), Vector3(0.38, 1.5, 0.42))
	add_arch_block(root, Vector3(0.85, 0.75, 0.2), Vector3(0.38, 1.5, 0.42))
	add_arch_block(root, Vector3(0.0, 1.55, 0.2), Vector3(2.05, 0.38, 0.46))


func add_arch_block(parent: Node3D, position: Vector3, box_scale: Vector3) -> void:
	ensure_resources()
	var block := StaticBody3D.new()
	block.collision_layer = OBSTACLE_LAYER
	block.collision_mask = 0
	block.position = position
	block.scale = box_scale
	var mesh := MeshInstance3D.new()
	mesh.mesh = rock_mesh
	mesh.material_override = rock_material
	block.add_child(mesh)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE
	collision.shape = box
	block.add_child(collision)
	parent.add_child(block)
