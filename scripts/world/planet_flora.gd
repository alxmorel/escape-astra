extends Node3D

const STYLIZED := preload("res://scripts/resources/stylized_material.gd")
const CHUNK_RINGS := 8
const CHUNK_SEGS := 16
const MAX_PER_CHUNK := 1200
const FLOWER_COLORS: Array[Color] = [
	Color(0.93, 0.45, 0.55),
	Color(0.95, 0.82, 0.28),
	Color(0.96, 0.78, 0.42),
	Color(0.55, 0.62, 0.95),
	Color(0.72, 0.48, 0.86),
]

const GRASS_CAP := 420
const WEED_CAP := 70
const GRASS_SEED_EVERY := 10
const GRASS_OFFSET := 0.02
const GRASS_SLOPE := 0.65
const GRASS_COVER := 1.2
const DROPS := preload("res://scripts/farming/drops.gd")
const WEEDS_SCENE := preload("res://assets/models/weeds.glb")
const BUSH_SCENE := preload("res://assets/models/buisson_01.glb")
const BUSH_CAP := 24
const BUSH_CLEARANCE := 1.6
const BUSH_TREE_CLEARANCE := 2.2
const BUSH_SPAWN_CLEARANCE := 5.0

@export_range(0.05, 1.0, 0.05) var grass_coverage: float = 0.4:
	set(value):
		grass_coverage = clampf(value, 0.05, 1.0)
		_request_rebuild()

@export_range(6.0, 48.0, 1.0) var patch_scale: float = 18.0:
	set(value):
		patch_scale = clampf(value, 6.0, 48.0)
		_apply_patch_scale()
		_request_rebuild()

@export_range(1.0, 12.0, 0.5) var grass_density: float = 5.0:
	set(value):
		grass_density = clampf(value, 1.0, 12.0)
		_request_rebuild()

@export_range(0.0, 3.0, 0.05) var bush_density: float = 1.0:
	set(value):
		bush_density = clampf(value, 0.0, 3.0)
		_request_rebuild()

@export_range(0.0, 1.0, 0.01) var bush_frequency: float = 0.55:
	set(value):
		bush_frequency = clampf(value, 0.0, 1.0)
		_request_rebuild()

@export_range(16.0, 70.0, 1.0) var render_distance: float = 32.0:
	set(value):
		render_distance = clampf(value, 16.0, 70.0)
		if is_node_ready():
			_apply_distance()

@export_range(0.4, 4.0, 0.1) var interaction_radius: float = 1.8:
	set(value):
		interaction_radius = clampf(value, 0.4, 4.0)
		_push_shader()

@export_range(0.0, 2.0, 0.05) var bend_strength: float = 0.8:
	set(value):
		bend_strength = clampf(value, 0.0, 2.0)
		_push_shader()

@export var wind_direction: Vector3 = Vector3(1.0, 0.0, 0.25):
	set(value):
		wind_direction = value
		_push_shader()

@export_range(0.0, 0.3, 0.005) var base_wind_strength: float = 0.06:
	set(value):
		base_wind_strength = clampf(value, 0.0, 0.3)
		_push_shader()

@export_range(0.0, 0.4, 0.005) var gust_strength: float = 0.2:
	set(value):
		gust_strength = clampf(value, 0.0, 0.4)
		_push_shader()

@export_range(0.05, 2.0, 0.05) var gust_speed: float = 0.9:
	set(value):
		gust_speed = clampf(value, 0.05, 2.0)
		_push_shader()

@export_range(0.02, 0.4, 0.01) var gust_scale: float = 0.16:
	set(value):
		gust_scale = clampf(value, 0.02, 0.4)
		_push_shader()

@export_range(0.0, 0.08, 0.005) var turbulence_strength: float = 0.02:
	set(value):
		turbulence_strength = clampf(value, 0.0, 0.08)
		_push_shader()

@export_range(8.0, 60.0, 1.0) var max_bend: float = 40.0:
	set(value):
		max_bend = clampf(value, 8.0, 60.0)
		_push_shader()

var _planet: Node3D
var _player: Node3D
var _material: ShaderMaterial
var _blade_mesh: ArrayMesh
var _tuft_mesh: ArrayMesh
var _flower_mesh: ArrayMesh
var _fern_mesh: ArrayMesh
var _reed_mesh: ArrayMesh
var _mushroom_mesh: ArrayMesh
var _pebble_mesh: ArrayMesh
var _bush_mesh: Mesh
var _bush_bottom := 0.0
var _stump_mesh: ArrayMesh
var _branch_mesh: ArrayMesh
var _weed_mesh: Mesh
var _solid: ShaderMaterial
var _radius := 48.0
var _patch_noise := FastNoiseLite.new()
var _clump_noise := FastNoiseLite.new()
var _block_pos := PackedVector3Array()
var _block_radius2 := PackedFloat32Array()
var _chunks := {}
var _empty := {}
var _pending: Array[Vector2i] = []
var _scan_wait := 0.0
var _grass := {}
var _grass_empty := {}
var _grass_wait: Array[Vector3i] = []
var _cut: Dictionary = {}
var _cut_since_seed := 0



func _ready() -> void:
	_planet = get_parent() as Node3D
	if _planet == null or not _planet.has_method(&"get_land_radius") or not _planet.has_method(&"is_land"):
		return
	_import_cuts(SaveManager.state().get("cut_grass", {}))
	_radius = float(_planet.get(&"base_radius"))
	_patch_noise.seed = int(_planet.get(&"world_seed"))
	_patch_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_patch_noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	_clump_noise.seed = int(_planet.get(&"world_seed")) + 9176
	_clump_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_clump_noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	_clump_noise.frequency = 0.28
	_apply_patch_scale()
	_collect_blockers()
	_weed_mesh = _first_mesh(WEEDS_SCENE)
	_bush_mesh = _first_mesh(BUSH_SCENE)
	if _bush_mesh != null:
		var bush_aabb := _bush_mesh.get_aabb()
		_bush_bottom = -bush_aabb.position.y
	_blade_mesh = _make_blade()
	_tuft_mesh = _make_cards(0.055, 0.85, 3)
	_flower_mesh = _make_flower()
	_fern_mesh = _make_cards(0.09, 0.8, 3)
	_reed_mesh = _make_cards(0.015, 1.0, 1)
	_mushroom_mesh = _make_mushroom()
	var pebble := BoxMesh.new()
	pebble.size = Vector3(0.16, 0.1, 0.14)
	var stump := CylinderMesh.new()
	stump.top_radius = 0.16
	stump.bottom_radius = 0.2
	stump.height = 0.32
	stump.radial_segments = 6
	var branch := CylinderMesh.new()
	branch.top_radius = 0.03
	branch.bottom_radius = 0.045
	branch.height = 0.65
	branch.radial_segments = 5
	_pebble_mesh = _with_white(pebble)
	_stump_mesh = _with_white(stump)
	_branch_mesh = _with_white(branch)
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/grass.gdshader")
	_solid = STYLIZED.create(Color.WHITE)
	_blade_mesh.surface_set_material(0, _material)
	_tuft_mesh.surface_set_material(0, _material)
	_flower_mesh.surface_set_material(0, _material)
	_fern_mesh.surface_set_material(0, _material)
	_reed_mesh.surface_set_material(0, _material)
	_mushroom_mesh.surface_set_material(0, _solid)
	_pebble_mesh.surface_set_material(0, _solid)
	_stump_mesh.surface_set_material(0, _solid)
	_branch_mesh.surface_set_material(0, _solid)
	_push_shader()
	if _planet.has_signal(&"terrain_edited"):
		_planet.terrain_edited.connect(_on_terrain_edited)
	_schedule()


func _process(delta: float) -> void:
	if _material == null:
		return
	_push_player()
	_scan_wait -= delta
	if _scan_wait <= 0.0:
		_scan_wait = 0.35
		_schedule()
	var budget := 2
	var skipped := 0
	var guard := _pending.size()
	while budget > 0 and skipped < guard and not _pending.is_empty():
		var key: Vector2i = _pending.pop_front()
		if not _surface_ready(key):
			_pending.append(key)
			skipped += 1
			continue
		budget -= 1
		_build_chunk(key)
	_pump_grass()


func _request_rebuild() -> void:
	if not is_node_ready() or _material == null:
		return
	for key in _chunks.keys():
		var node := _chunks[key] as Node
		node.queue_free()
	_chunks.clear()
	_empty.clear()
	_pending.clear()
	var grass_keys: Array[Vector3i] = []
	for key in _grass:
		grass_keys.append(key as Vector3i)
	for key in _grass_empty:
		grass_keys.append(key as Vector3i)
	_grass_empty.clear()
	for coord in grass_keys:
		rebuild_grass(coord)
	_schedule()


func _apply_patch_scale() -> void:
	_patch_noise.frequency = 1.0 / patch_scale


func _push_shader() -> void:
	if _material == null:
		return
	_material.set_shader_parameter(&"interaction_radius", interaction_radius)
	_material.set_shader_parameter(&"bend_strength", bend_strength)
	_material.set_shader_parameter(&"wind_direction", wind_direction)
	_material.set_shader_parameter(&"base_wind_strength", base_wind_strength)
	_material.set_shader_parameter(&"gust_strength", gust_strength)
	_material.set_shader_parameter(&"gust_speed", gust_speed)
	_material.set_shader_parameter(&"gust_scale", gust_scale)
	_material.set_shader_parameter(&"turbulence_strength", turbulence_strength)
	_material.set_shader_parameter(&"max_bend", deg_to_rad(max_bend))


func _push_player() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as Node3D
	if _player == null:
		return
	_material.set_shader_parameter(&"player_position", _player.global_position)


func _collect_blockers() -> void:
	_block_pos = PackedVector3Array()
	_block_radius2 = PackedFloat32Array()
	if _planet == null:
		return
	for node in get_tree().get_nodes_in_group(&"harvestable"):
		var item := node as Node3D
		if item == null:
			continue
		var resource_id := str(item.get(&"resource_id"))
		var clearance := BUSH_CLEARANCE
		if resource_id == "wood":
			clearance = BUSH_TREE_CLEARANCE
		elif resource_id == "iron_ore" or resource_id == "coal":
			clearance = BUSH_CLEARANCE * 0.9
		elif resource_id != "stone":
			continue
		_block_pos.append(_planet.to_local(item.global_position))
		_block_radius2.append(clearance * clearance)
	for node in get_tree().get_nodes_in_group(&"construction"):
		var build := node as Node3D
		if build == null:
			continue
		_block_pos.append(_planet.to_local(build.global_position))
		_block_radius2.append(2.4 * 2.4)
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if player != null:
		_block_pos.append(_planet.to_local(player.global_position))
		_block_radius2.append(BUSH_SPAWN_CLEARANCE * BUSH_SPAWN_CLEARANCE)


func _schedule() -> void:
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if player == null:
		return
	_collect_blockers()
	var player_local := _planet.to_local(player.global_position)
	var load_dist := render_distance + 12.0
	var drop_dist := load_dist + 8.0
	for ring in CHUNK_RINGS:
		for seg in CHUNK_SEGS:
			var key := Vector2i(ring, seg)
			var dist := player_local.distance_to(_chunk_center(ring, seg))
			if dist > drop_dist:
				_drop(key)
			elif dist <= load_dist and not _chunks.has(key) and not _empty.has(key) and not _pending.has(key):
				_pending.append(key)
	_queue_grass()


func _drop(key: Vector2i) -> void:
	_pending.erase(key)
	if not _chunks.has(key):
		return
	var node := _chunks[key] as Node
	_chunks.erase(key)
	node.queue_free()


func _build_chunk(key: Vector2i) -> void:
	if _chunks.has(key) or _empty.has(key):
		return
	var bounds := _chunk_bounds(key)
	var area := _radius * _radius * absf(sin(bounds.y) - sin(bounds.x)) * (bounds.w - bounds.z)
	var deco := _decoration_density()
	var grass := _scatter(bounds, mini(int(area * grass_density), MAX_PER_CHUNK), 0)
	var plants := _scatter(bounds, mini(int(area * grass_density * 0.012), 70), 1)
	var flowers := _scatter(bounds, mini(int(area * 0.055 * deco), 36), 2)
	var ferns := _scatter(bounds, mini(int(area * 0.05 * deco), 40), 3)
	var reeds := _scatter(bounds, mini(int(area * 0.04 * deco), 24), 4)
	var pebbles := _scatter(bounds, mini(int(area * 0.04 * deco), 28), 5)
	var mushrooms := _scatter(bounds, mini(int(area * 0.01 * deco), 8), 6)
	var bush_rate := _bush_density() * _bush_frequency() * deco
	var bushes := _scatter(bounds, mini(int(area * 0.028 * bush_rate), BUSH_CAP), 7)
	var stumps := _scatter(bounds, mini(int(area * 0.003 * deco), 4), 8)
	var branches := _scatter(bounds, mini(int(area * 0.005 * deco), 6), 9)
	if grass.is_empty() and plants.is_empty() and flowers.is_empty() and ferns.is_empty() and reeds.is_empty() and pebbles.is_empty() and mushrooms.is_empty() and bushes.is_empty() and stumps.is_empty() and branches.is_empty():
		_empty[key] = true
		return
	var chunk := Node3D.new()
	chunk.name = "Chunk_%d_%d" % [key.x, key.y]
	add_child(chunk)
	_add_multi(chunk, "Grass", _blade_mesh, grass)
	_add_multi(chunk, "Plants", _tuft_mesh, plants)
	_add_multi(chunk, "Flowers", _flower_mesh, flowers)
	_add_multi(chunk, "Ferns", _fern_mesh, ferns)
	_add_multi(chunk, "Reeds", _reed_mesh, reeds)
	_add_multi(chunk, "Pebbles", _pebble_mesh, pebbles, _solid)
	_add_multi(chunk, "Mushrooms", _mushroom_mesh, mushrooms, _solid)
	if _bush_mesh != null:
		_add_multi(chunk, "Bushes", _bush_mesh, bushes, null, true)
	_add_multi(chunk, "Stumps", _stump_mesh, stumps, _solid)
	_add_multi(chunk, "Branches", _branch_mesh, branches, _solid)
	_chunks[key] = chunk


func _scatter(bounds: Vector4, target: int, kind: int) -> Array:
	var batch: Array = []
	if target <= 0:
		return batch
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_planet.get(&"world_seed")) + int(bounds.x * 1000.0) + int(bounds.z * 7000.0) + kind * 97
	var transforms: Array[Transform3D] = []
	var colors := PackedColorArray()
	var phases := PackedFloat32Array()
	for _i in target:
		var lat := rng.randf_range(bounds.x, bounds.y)
		var lon := rng.randf_range(bounds.z, bounds.w)
		var dir := Vector3(cos(lon) * cos(lat), sin(lat), sin(lon) * cos(lat))
		if not bool(_planet.call(&"is_land", dir)):
			continue
		var point := dir * float(_planet.call(&"get_land_radius", dir))
		point = _on_ground(point)
		if _planet.has_method(&"terrain_edited_near") and bool(_planet.call(&"terrain_edited_near", point, 0.9)):
			continue
		if kind != 5 and _blocked(point):
			continue
		if kind == 7 and _on_plot(point):
			continue
		if kind == 7 and _planet.has_method(&"_slope_up"):
			var slope: Vector3 = _planet.call(&"_slope_up", dir)
			if slope.dot(dir) < GRASS_SLOPE:
				continue
		var weights := _zone_weights(dir)
		var factor := _zone_factor(kind, weights)
		if factor < 0.12:
			continue
		var field := _patch_noise.get_noise_3d(point.x, point.y, point.z) * 0.5 + 0.5
		var edge := 1.0 - grass_coverage
		var weight := smoothstep(edge - 0.16, edge + 0.22, field) * factor
		if kind <= 1:
			if kind == 1 and weight < 0.35:
				continue
			if rng.randf() > weight:
				continue
		elif kind == 7:
			if rng.randf() > factor * _bush_frequency():
				continue
		elif rng.randf() > factor:
			continue
		if kind == 2 and _patch_noise.get_noise_3d(point.x * 2.4, point.y * 2.4, point.z * 2.4) < 0.2:
			continue
		var placed := _place_kind(kind, weights, rng)
		var basis := _basis_from_up(dir).rotated(dir, rng.randf() * TAU)
		if bool(placed[2]):
			basis = basis.rotated(basis.x, PI * 0.5)
		var placed_scale := placed[0] as Vector3
		basis = basis.scaled(placed_scale)
		var lift := -0.012 if kind == 0 else 0.045
		if kind == 5:
			lift = 0.03
		elif kind == 7:
			# Aligne le pivot GLB sur le sol (AABB locale).
			lift = _bush_bottom * placed_scale.y - 0.04
		elif kind == 8:
			lift = 0.16 * placed_scale.y
		elif kind == 9:
			lift = 0.05
		transforms.append(Transform3D(basis, point + dir * lift))
		colors.append(placed[1] as Color)
		phases.append(rng.randf())
	if transforms.is_empty():
		return batch
	batch.append(transforms)
	batch.append(colors)
	batch.append(phases)
	return batch


func _place_kind(kind: int, weights: PackedFloat32Array, rng: RandomNumberGenerator) -> Array:
	var scale := Vector3.ONE
	var color := Color.WHITE
	var lay := false
	match kind:
		0:
			scale = Vector3(rng.randf_range(0.55, 0.9), rng.randf_range(0.08, 0.24), 1.0)
			scale.z = scale.x
			color = Color(0.22, 0.34, 0.15).lerp(Color(0.3, 0.42, 0.18), rng.randf())
			if weights[1] > 0.45:
				color = color.lerp(Color(0.12, 0.24, 0.08), 0.6)
			elif weights[3] > 0.4:
				color = color.lerp(Color(0.4, 0.48, 0.22), 0.5)
			elif weights[4] > 0.35:
				color = color.darkened(0.3)
		1:
			scale = Vector3(rng.randf_range(0.7, 1.05), rng.randf_range(0.1, 0.22), 1.0)
			scale.z = scale.x
			color = Color(0.2, 0.32, 0.14).lerp(Color(0.28, 0.4, 0.16), rng.randf())
			if weights[1] > 0.4:
				color = color.lerp(Color(0.14, 0.28, 0.1), 0.45)
		2:
			var flower_h := rng.randf_range(0.12, 0.26)
			scale = Vector3(flower_h, flower_h, flower_h)
			color = FLOWER_COLORS[rng.randi() % FLOWER_COLORS.size()]
		3:
			var fern_h := rng.randf_range(0.22, 0.42)
			scale = Vector3(fern_h, fern_h, fern_h)
			color = Color(0.16, 0.32, 0.12).lerp(Color(0.22, 0.4, 0.14), rng.randf())
		4:
			scale = Vector3(0.45, rng.randf_range(0.28, 0.52), 0.45)
			color = Color(0.42, 0.5, 0.22).lerp(Color(0.5, 0.56, 0.26), rng.randf())
		5:
			var pebble := rng.randf_range(0.45, 1.05)
			scale = Vector3(pebble, pebble * rng.randf_range(0.45, 0.8), pebble * rng.randf_range(0.7, 1.1))
			color = Color(0.52, 0.5, 0.46).lerp(Color(0.36, 0.34, 0.32), rng.randf())
		6:
			var mushroom := rng.randf_range(0.55, 1.05)
			scale = Vector3(mushroom, mushroom, mushroom)
			color = Color(0.62, 0.24, 0.18) if rng.randf() > 0.35 else Color(0.46, 0.3, 0.16)
		7:
			var bush := rng.randf_range(0.85, 1.2)
			scale = Vector3(bush, bush, bush)
			color = Color.WHITE
		8:
			var stump := rng.randf_range(0.5, 0.85)
			scale = Vector3(stump, stump * 0.75, stump)
			color = Color(0.34, 0.22, 0.12)
		9:
			scale = Vector3(rng.randf_range(0.75, 1.15), rng.randf_range(0.55, 1.1), rng.randf_range(0.75, 1.15))
			color = Color(0.3, 0.2, 0.12)
			lay = true
	return [scale, color, lay]


func _zone_weights(dir: Vector3) -> PackedFloat32Array:
	if _planet.has_method(&"get_zone_weights"):
		var weights: PackedFloat32Array = _planet.call(&"get_zone_weights", dir)
		if weights.size() >= 5:
			return weights
	return PackedFloat32Array([1.0, 0.0, 0.0, 0.0, 0.0])


func _zone_factor(kind: int, weights: PackedFloat32Array) -> float:
	match kind:
		0, 1:
			return weights[0] * 0.85 + weights[1] + weights[3] * 0.55 + weights[2] * 0.18 + weights[4] * 0.04
		2:
			return weights[0]
		3, 6, 8, 9:
			return weights[1]
		4:
			return weights[3]
		5:
			return maxf(weights[2], weights[4])
		7:
			# Prairies + lisières boisées ; évite roche / rivage dominant.
			return weights[0] * 0.75 + weights[1] * 0.95 + weights[3] * 0.25
	return 0.0


func _decoration_density() -> float:
	var value = _planet.get(&"decoration_density")
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return 1.0
	return clampf(float(value), 0.0, 2.0)


func _bush_density() -> float:
	var value = _planet.get(&"bush_density")
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		return clampf(float(value), 0.0, 3.0)
	return bush_density


func _bush_frequency() -> float:
	var value = _planet.get(&"bush_frequency")
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		return clampf(float(value), 0.0, 1.0)
	return bush_frequency


func _surface_ready(key: Vector2i) -> bool:
	var volume := _planet.get_node_or_null(^"TerrainVolume")
	if volume == null or not volume.has_method(&"surface_ready"):
		return true
	return bool(volume.call(&"surface_ready", _chunk_center(key.x, key.y)))


func _on_ground(point: Vector3) -> Vector3:
	var volume := _planet.get_node_or_null(^"TerrainVolume")
	if volume == null or not volume.has_method(&"ground_point"):
		return point
	return volume.call(&"ground_point", point)


func _on_plot(point: Vector3) -> bool:
	var farming := get_tree().get_first_node_in_group(&"farming")
	if farming == null or not farming.has_method(&"covers_point"):
		return false
	return bool(farming.call(&"covers_point", point))


func _blocked(point: Vector3) -> bool:
	for i in _block_pos.size():
		if point.distance_squared_to(_block_pos[i]) < _block_radius2[i]:
			return true
	return false


func _first_mesh(scene: PackedScene) -> Mesh:
	var root := scene.instantiate()
	var mesh: Mesh = null
	if root is MeshInstance3D:
		mesh = (root as MeshInstance3D).mesh
	if mesh == null:
		for node in root.find_children("*", "MeshInstance3D", true, false):
			var mesh_node := node as MeshInstance3D
			if mesh_node != null and mesh_node.mesh != null:
				mesh = mesh_node.mesh
				break
	root.free()
	return mesh


func _add_multi(parent: Node3D, mesh_name: String, mesh: Mesh, batch: Array, material: Material = null, keep_material := false) -> void:
	if batch.is_empty():
		return
	var transforms: Array = batch[0]
	var colors: PackedColorArray = batch[1]
	if transforms.is_empty():
		return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i])
		multi.set_instance_color(i, colors[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = mesh_name
	instance.multimesh = multi
	if not keep_material:
		instance.material_override = _material if material == null else material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	instance.visibility_range_end = render_distance
	parent.add_child(instance)


func _apply_distance() -> void:
	for key in _chunks.keys():
		var chunk := _chunks[key] as Node3D
		for child in chunk.get_children():
			var geom := child as GeometryInstance3D
			if geom != null:
				geom.visibility_range_end = render_distance



func _remember_grass(coord: Vector3i) -> void:
	if not _grass_wait.has(coord):
		_grass_wait.append(coord)


func _queue_grass() -> void:
	if _planet == null:
		return
	var volume := _planet.get_node_or_null(^"TerrainVolume")
	if volume == null or not volume.has_method(&"grass_chunk_list"):
		return
	for item in volume.call(&"grass_chunk_list"):
		var coord := item as Vector3i
		if _grass.has(coord) or _grass_empty.has(coord) or _grass_wait.has(coord):
			continue
		_grass_wait.append(coord)


func _pump_grass() -> void:
	var guard := _grass_wait.size()
	var built := 0
	var skipped := 0
	var start := Time.get_ticks_usec()
	while built < 4 and skipped < guard and not _grass_wait.is_empty() and Time.get_ticks_usec() - start < 2500:
		var coord: Vector3i = _grass_wait.pop_front()
		var volume: Node = null
		if _planet != null:
			volume = _planet.get_node_or_null(^"TerrainVolume")
		if volume == null or not bool(volume.call(&"chunk_grass_ready", coord)):
			_grass_wait.append(coord)
			skipped += 1
			continue
		rebuild_grass(coord)
		built += 1


func _clear_grass(coord: Vector3i) -> void:
	if not _grass.has(coord):
		return
	var node := _grass[coord] as Node
	_grass.erase(coord)
	if node != null and is_instance_valid(node):
		node.queue_free()


func cut_at(local_point: Vector3) -> bool:
	var best_pos := Vector3.ZERO
	var best_dist := 0.7 * 0.7
	var found := false
	for key in _grass:
		var chunk := _grass[key] as Node3D
		if chunk == null:
			continue
		for mesh_path in [^"Grass", ^"Weeds"]:
			var mesh_node := chunk.get_node_or_null(mesh_path) as MultiMeshInstance3D
			if mesh_node == null or mesh_node.multimesh == null:
				continue
			var multi := mesh_node.multimesh
			for i in multi.instance_count:
				var origin := multi.get_instance_transform(i).origin
				if _cut.has(_blade_key(origin)):
					continue
				var dist := origin.distance_squared_to(local_point)
				if dist >= best_dist:
					continue
				best_dist = dist
				best_pos = origin
				found = true
	if not found:
		return false
	var up := best_pos.normalized()
	for key in _grass:
		var chunk := _grass[key] as Node3D
		if chunk == null:
			continue
		for mesh_path in [^"Grass", ^"Weeds"]:
			var mesh_node := chunk.get_node_or_null(mesh_path) as MultiMeshInstance3D
			if mesh_node == null or mesh_node.multimesh == null:
				continue
			var multi := mesh_node.multimesh
			for i in multi.instance_count:
				var xf := multi.get_instance_transform(i)
				if xf.origin.distance_squared_to(best_pos) > 0.04:
					continue
				_cut[_blade_key(xf.origin)] = true
				multi.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(0.001, 0.001, 0.001)), xf.origin))
	_cut_since_seed += 1
	if _cut_since_seed >= GRASS_SEED_EVERY:
		_cut_since_seed = 0
		var planet := _planet
		DROPS.spawn_drop(planet.to_global(best_pos), planet.global_transform.basis * up, "wheat_seeds", 1, self)
	return true


func export_cuts() -> Dictionary:
	var keys: Array[String] = []
	for key in _cut:
		keys.append(str(key))
	return {"keys": keys, "count": _cut_since_seed}


func _import_cuts(raw: Variant) -> void:
	_cut.clear()
	_cut_since_seed = 0
	if not raw is Dictionary:
		return
	var data: Dictionary = raw
	var keys: Variant = data.get("keys", [])
	if keys is Array:
		for key in keys:
			_cut[str(key)] = true
	_cut_since_seed = int(data.get("count", 0))


func _blade_key(point: Vector3) -> String:
	return "%d_%d_%d" % [int(round(point.x * 50.0)), int(round(point.y * 50.0)), int(round(point.z * 50.0))]


func rebuild_grass(coord: Vector3i) -> void:
	_clear_grass(coord)
	_grass_wait.erase(coord)
	_grass_empty.erase(coord)
	if _blade_mesh == null or _planet == null:
		_remember_grass(coord)
		return
	var volume := _planet.get_node_or_null(^"TerrainVolume")
	if volume == null or not volume.has_method(&"chunk_surface"):
		return
	var faces: PackedVector3Array = volume.call(&"chunk_surface", coord)
	if faces.is_empty():
		return
	if volume.has_method(&"chunk_grass_ready") and not bool(volume.call(&"chunk_grass_ready", coord)):
		_remember_grass(coord)
		return
	var batch := _grass_batch(coord, faces, volume)
	var weeds := _weed_batch(coord, faces, volume)
	if batch.is_empty() and weeds.is_empty():
		_grass_empty[coord] = true
		return
	var chunk := Node3D.new()
	chunk.name = "Grass_%d_%d_%d" % [coord.x, coord.y, coord.z]
	add_child(chunk)
	if not batch.is_empty():
		_add_multi(chunk, "Grass", _blade_mesh, batch)
	if not weeds.is_empty() and _weed_mesh != null:
		_add_multi(chunk, "Weeds", _weed_mesh, weeds, null, true)
	_grass[coord] = chunk


func _grass_batch(coord: Vector3i, faces: PackedVector3Array, volume: Node) -> Array:
	var batch: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_planet.get(&"world_seed")) + 39001 + coord.x * 83492791 + coord.y * 19349663 + coord.z * 73856093
	var transforms: Array[Transform3D] = []
	var colors := PackedColorArray()
	var phases := PackedFloat32Array()
	var count := int(faces.size() / 3)
	for tri in count:
		if transforms.size() >= GRASS_CAP:
			break
		var a := faces[tri * 3]
		var b := faces[tri * 3 + 1]
		var c := faces[tri * 3 + 2]
		var cross := (b - a).cross(c - a)
		var span := cross.length()
		if span < 0.0001:
			continue
		var normal := cross / span
		var center := (a + b + c) / 3.0
		if center.length_squared() < 0.01:
			continue
		var up := center.normalized()
		if normal.dot(up) < GRASS_SLOPE:
			continue
		if bool(volume.call(&"surface_covered", center + normal * 0.08, up, GRASS_COVER)):
			continue
		var area := span * 0.5
		var expected := area * grass_density / 3.0
		var samples := int(expected)
		if rng.randf() < expected - float(samples):
			samples += 1
		for _sample in samples:
			if transforms.size() >= GRASS_CAP:
				break
			var u := rng.randf()
			var v := rng.randf()
			if u + v > 1.0:
				u = 1.0 - u
				v = 1.0 - v
			var point := a + (b - a) * u + (c - a) * v
			var dir := point
			if dir.length_squared() < 0.01:
				continue
			dir = dir.normalized()
			if bool(volume.call(&"point_in_water", point + normal * 0.15)):
				continue
			if _blocked(point):
				continue
			var weights := _zone_weights(dir)
			var factor := _zone_factor(0, weights)
			if factor < 0.12:
				continue
			var field := _patch_noise.get_noise_3d(point.x, point.y, point.z) * 0.5 + 0.5
			var clump := _clump_noise.get_noise_3d(point.x, point.y, point.z) * 0.5 + 0.5
			var weight := smoothstep(1.0 - grass_coverage - 0.16, 1.0 - grass_coverage + 0.22, field) * factor
			weight *= lerpf(0.45, 1.55, clump)
			if rng.randf() > weight:
				continue
			var placed := _place_kind(0, weights, rng)
			var base_scale := placed[0] as Vector3
			var base_color := placed[1] as Color
			var lo := int(round(lerpf(3.0, 6.0, clump)))
			var hi := int(round(lerpf(8.0, 15.0, clump)))
			var tuft := rng.randi_range(mini(lo, hi), maxi(lo, hi))
			var share := lerpf(0.32, 0.18, clump)
			var single_p := (share * float(tuft)) / (1.0 - share + share * float(tuft))
			var blades := 1 if rng.randf() < single_p else tuft
			var reference := Vector3.FORWARD if absf(normal.dot(Vector3.UP)) > 0.99 else Vector3.UP
			var tangent := reference.cross(normal).normalized()
			var bitangent := normal.cross(tangent).normalized()
			var spread := rng.randf_range(0.05, 0.1) * sqrt(float(blades))
			for _blade in blades:
				if transforms.size() >= GRASS_CAP:
					break
				var offset := Vector3.ZERO
				if blades > 1:
					var ang := rng.randf() * TAU
					var dist := sqrt(rng.randf()) * spread
					offset = (tangent * cos(ang) + bitangent * sin(ang)) * dist
					if _blocked(point + offset):
						continue
				var basis := _basis_from_up(dir).rotated(dir, rng.randf() * TAU)
				var tilt := rng.randf_range(-0.1, 0.16)
				var tilt_axis := basis.x
				if offset.length_squared() > 0.0004:
					var axis := dir.cross(offset)
					if axis.length_squared() > 0.0001:
						tilt_axis = axis.normalized()
						tilt = rng.randf_range(0.04, 0.22)
				basis = basis.rotated(tilt_axis, tilt)
				var scale := base_scale
				scale.x *= rng.randf_range(0.75, 1.2)
				scale.y *= rng.randf_range(0.7, 1.3)
				scale.z = scale.x
				basis = basis.scaled(scale)
				transforms.append(Transform3D(basis, point + offset + normal * GRASS_OFFSET))
				var color := base_color.darkened(rng.randf_range(0.0, 0.08)) if rng.randf() < 0.5 else base_color.lightened(rng.randf_range(0.0, 0.08))
				colors.append(color)
				phases.append(rng.randf())
	if transforms.is_empty():
		return batch
	batch.append(transforms)
	batch.append(colors)
	batch.append(phases)
	return batch


func _weed_batch(coord: Vector3i, faces: PackedVector3Array, volume: Node) -> Array:
	var batch: Array = []
	if _weed_mesh == null:
		return batch
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_planet.get(&"world_seed")) + 49001 + coord.x * 83492791 + coord.y * 19349663 + coord.z * 73856093
	var transforms: Array[Transform3D] = []
	var colors := PackedColorArray()
	var phases := PackedFloat32Array()
	var count := int(faces.size() / 3)
	for tri in count:
		if transforms.size() >= WEED_CAP:
			break
		var a := faces[tri * 3]
		var b := faces[tri * 3 + 1]
		var c := faces[tri * 3 + 2]
		var cross := (b - a).cross(c - a)
		var span := cross.length()
		if span < 0.0001:
			continue
		var normal := cross / span
		var center := (a + b + c) / 3.0
		if center.length_squared() < 0.01:
			continue
		var up := center.normalized()
		if normal.dot(up) < GRASS_SLOPE:
			continue
		if bool(volume.call(&"surface_covered", center + normal * 0.08, up, GRASS_COVER)):
			continue
		var area := span * 0.5
		var expected := area * grass_density * 0.012
		var samples := int(expected)
		if rng.randf() < expected - float(samples):
			samples += 1
		for _sample in samples:
			if transforms.size() >= WEED_CAP:
				break
			var u := rng.randf()
			var v := rng.randf()
			if u + v > 1.0:
				u = 1.0 - u
				v = 1.0 - v
			var point := a + (b - a) * u + (c - a) * v
			var dir := point.normalized()
			if dir.length_squared() < 0.01:
				continue
			if bool(volume.call(&"point_in_water", point + normal * 0.15)):
				continue
			if _blocked(point) or _on_plot(point):
				continue
			var weights := _zone_weights(dir)
			if _zone_factor(0, weights) < 0.12:
				continue
			var field := _patch_noise.get_noise_3d(point.x, point.y, point.z) * 0.5 + 0.5
			var weight := smoothstep(1.0 - grass_coverage - 0.16, 1.0 - grass_coverage + 0.22, field)
			if rng.randf() > weight:
				continue
			var spot := point + normal * GRASS_OFFSET
			if _cut.has(_blade_key(spot)):
				continue
			var basis := _basis_from_up(dir).rotated(dir, rng.randf() * TAU)
			var scale := rng.randf_range(0.9, 1.15)
			basis = basis.scaled(Vector3.ONE * scale)
			transforms.append(Transform3D(basis, spot))
			colors.append(Color.WHITE)
			phases.append(rng.randf())
	if transforms.is_empty():
		return batch
	batch.append(transforms)
	batch.append(colors)
	batch.append(phases)
	return batch


func _on_terrain_edited(local_position: Vector3, radius: float) -> void:
	var reach := radius + 8.0
	var drop_keys: Array[Vector2i] = []
	for key in _chunks:
		var coord := key as Vector2i
		if _chunk_center(coord.x, coord.y).distance_to(local_position) <= reach:
			drop_keys.append(coord)
	for key in drop_keys:
		_drop(key)
	var empty_keys: Array[Vector2i] = []
	for key in _empty:
		var coord := key as Vector2i
		if _chunk_center(coord.x, coord.y).distance_to(local_position) <= reach:
			empty_keys.append(coord)
	for key in empty_keys:
		_empty.erase(key)


func _chunk_bounds(key: Vector2i) -> Vector4:
	return Vector4(
		lerpf(-PI * 0.5, PI * 0.5, float(key.x) / float(CHUNK_RINGS)),
		lerpf(-PI * 0.5, PI * 0.5, float(key.x + 1) / float(CHUNK_RINGS)),
		TAU * float(key.y) / float(CHUNK_SEGS),
		TAU * float(key.y + 1) / float(CHUNK_SEGS)
	)


func _chunk_center(ring: int, seg: int) -> Vector3:
	var bounds := _chunk_bounds(Vector2i(ring, seg))
	var lat := (bounds.x + bounds.y) * 0.5
	var lon := (bounds.z + bounds.w) * 0.5
	var dir := Vector3(cos(lon) * cos(lat), sin(lat), sin(lon) * cos(lat))
	return dir * float(_planet.call(&"get_land_radius", dir))


func _basis_from_up(up: Vector3) -> Basis:
	var y := up.normalized()
	var reference := Vector3.FORWARD if absf(y.dot(Vector3.UP)) > 0.99 else Vector3.UP
	var x := reference.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _make_blade() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sections := 4
	for i in sections:
		var t0 := float(i) / float(sections)
		var t1 := float(i + 1) / float(sections)
		var l0 := _blade_vertex(t0, -1)
		var m0 := _blade_vertex(t0, 0)
		var r0 := _blade_vertex(t0, 1)
		var l1 := _blade_vertex(t1, -1)
		var m1 := _blade_vertex(t1, 0)
		var r1 := _blade_vertex(t1, 1)
		_add_tri(tool, l0, m0, l1, t0, t0, t1)
		_add_tri(tool, m0, m1, l1, t0, t1, t1)
		_add_tri(tool, m0, r0, m1, t0, t0, t1)
		_add_tri(tool, r0, r1, m1, t0, t1, t1)
	return tool.commit()


func _blade_vertex(t: float, side: int) -> Vector3:
	var width := lerpf(0.04, 0.008, t)
	var fold := lerpf(0.026, 0.005, t)
	var lean := t * t * 0.05
	if side == 0:
		return Vector3(0.0, t, lean + fold)
	return Vector3(width * float(side), t, lean)


func _make_cards(half_width: float, height: float, cards: int) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in cards:
		_add_card(tool, half_width, height, TAU * float(i) / float(cards))
	return tool.commit()


func _with_white(mesh: Mesh) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors := PackedColorArray()
	colors.resize(vertices.size())
	colors.fill(Color.WHITE)
	arrays[Mesh.ARRAY_COLOR] = colors
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


func _make_mushroom() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_card(tool, 0.045, 0.32, 0.0)
	_add_card(tool, 0.045, 0.32, PI * 0.5)
	var center := Vector3(0.0, 0.36, 0.0)
	for i in 5:
		var a := TAU * float(i) / 5.0
		var b := TAU * float(i + 1) / 5.0
		var pa := center + Vector3(cos(a) * 0.16, 0.06, sin(a) * 0.16)
		var pb := center + Vector3(cos(b) * 0.16, 0.06, sin(b) * 0.16)
		_add_tri(tool, center + Vector3(0.0, 0.1, 0.0), pa, pb, 0.3, 0.3, 0.3)
	return tool.commit()


func _make_flower() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_card(tool, 0.018, 0.62, 0.0)
	_add_card(tool, 0.018, 0.62, PI * 0.5)
	var center := Vector3(0.0, 0.62, 0.0)
	for i in 4:
		var yaw := float(i) * PI * 0.5
		var out := Vector3(cos(yaw), 0.0, sin(yaw))
		var side := Vector3(-out.z, 0.0, out.x)
		_add_tri(tool, center + side * 0.045, center - side * 0.045, center + out * 0.16 + Vector3(0.0, 0.28, 0.0), 0.55, 0.55, 1.0)
	return tool.commit()


func _add_card(tool: SurfaceTool, half_width: float, height: float, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var bl: Vector3 = basis * Vector3(-half_width, 0.0, 0.0)
	var br: Vector3 = basis * Vector3(half_width, 0.0, 0.0)
	var tr: Vector3 = basis * Vector3(half_width * 0.2, height, 0.0)
	var tl: Vector3 = basis * Vector3(-half_width * 0.2, height, 0.0)
	_add_tri(tool, bl, br, tl, 0.0, 0.0, 1.0)
	_add_tri(tool, br, tr, tl, 0.0, 1.0, 1.0)


func _add_tri(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ha: float, hb: float, hc: float) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 0.0000001:
		return
	normal = normal.normalized()
	var points: Array[Vector3] = [a, b, c]
	var heights: Array[float] = [ha, hb, hc]
	for i in 3:
		tool.set_normal(normal)
		tool.set_color(Color.WHITE)
		tool.set_uv(Vector2(0.0, heights[i]))
		tool.add_vertex(points[i])
