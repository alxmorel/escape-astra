extends StaticBody3D

const VOLUME := preload("res://scripts/terrain/terrain_volume.gd")
const FARMING := preload("res://scripts/farming/farming.gd")
const BUFFALO_POP := preload("res://scripts/creatures/buffalo_population.gd")
const PlanetForest := preload("res://scripts/world/planet_forest.gd")
const PlanetHeight := preload("res://scripts/world/planet_height.gd")
const PlanetHydroNetwork := preload("res://scripts/world/planet_hydro_network.gd")
const PlanetRocks := preload("res://scripts/world/planet_rocks.gd")
const OBSTACLE_LAYER := 8

signal terrain_edited(local_position: Vector3, radius: float)

@export var base_radius := 47.746
@export var hill_amplitude := 3.2
@export var water_offset := -1.15
@export var tree_target := 70
@export var rock_target := 36
@export var rock_spacing := 2.2
@export var rock_tree_clearance := 2.4
@export var iron_target := 22
@export var iron_spacing := 4.8
@export_range(0.0, 2.0, 0.05) var iron_density: float = 1.15
@export_range(0.05, 1.0, 0.01) var iron_rarity: float = 0.48
@export_range(0.6, 4.0, 0.05) var iron_burial_min: float = 1.2
@export_range(0.8, 5.0, 0.05) var iron_burial_max: float = 3.0
@export_range(0.0, 0.4, 0.01) var iron_shallow_chance: float = 0.18
@export var coal_target := 44
@export var coal_spacing := 3.2
@export_range(0.0, 2.0, 0.05) var coal_density: float = 1.35
@export_range(0.05, 1.0, 0.01) var coal_rarity: float = 0.72
@export_range(0.4, 4.0, 0.05) var coal_burial_min: float = 0.9
@export_range(0.8, 5.0, 0.05) var coal_burial_max: float = 2.8
@export_range(0.0, 0.8, 0.01) var coal_shallow_chance: float = 0.42
@export var world_seed := 0
@export_range(0.4, 2.2, 0.05) var terrain_relief: float = 1.0
@export_range(0.0, 1.0, 0.05) var plateau_frequency: float = 0.4
@export_range(12.0, 48.0, 1.0) var biome_scale: float = 26.0
@export_range(0.05, 0.8, 0.01) var target_water_coverage: float = 0.45
@export_range(0.0, 3.0, 0.05) var tree_density: float = 1.0
@export_range(0.0, 3.0, 0.05) var forest_tree_density: float = 1.0
@export_range(0.3, 2.0, 0.05) var forest_density: float = 1.0
@export_range(0.0, 1.0, 0.05) var forest_chance: float = 0.4
@export_range(0.0, 2.0, 0.05) var decoration_density: float = 1.0
@export_range(0.0, 3.0, 0.05) var bush_density: float = 1.0
@export_range(0.0, 1.0, 0.01) var bush_frequency: float = 0.55
@export_range(1, 8, 1) var landmark_count: int = 5

var _spring_dirs := PackedVector3Array()
var _spring_yield := PackedInt32Array()
var _spring_noise := FastNoiseLite.new()
var _spring_lookup: Dictionary = {}
var _spring_voxel := -1.0
var _water_level := 0.0
var _volume
var _xray := false

var _height := PlanetHeight.new()
var _forest := PlanetForest.new()
var _rocks := PlanetRocks.new()
var _hydro_net := PlanetHydroNetwork.new()
var _hydro_debug := false
var _hydro_debug_view: MeshInstance3D


func _enter_tree() -> void:
	var forced := int(SaveManager.active_seed())
	if forced != 0:
		world_seed = forced
	elif world_seed == 0:
		world_seed = randi()


func _ready() -> void:
	seed(world_seed)
	_water_level = base_radius + water_offset
	_height.configure(self)
	_height.build_features(self)
	_hydro_net.build(self)
	_build_springs()
	_forest.build_forests(self)
	_forest.import_cut_trees(SaveManager.state().get("cut_trees", {}))
	_rocks.import_cut_rocks(SaveManager.state().get("cut_rocks", {}))
	_volume = VOLUME.new()
	_volume.name = "TerrainVolume"
	add_child(_volume)
	_volume.setup(self)
	var spawn_direction := _nearest_land_direction(Vector3.UP)
	var spawn_position := _surface_position(spawn_direction)
	_place_player(spawn_direction, spawn_position)
	_volume.begin_boot()
	_volume.warm_start()
	_spawn_props(spawn_position)
	_rocks.spawn_landmarks(self)
	var farming := FARMING.new()
	farming.name = "Farming"
	add_child(farming)
	var buffalo_pop := BUFFALO_POP.new()
	buffalo_pop.name = "BuffaloPopulation"
	add_child(buffalo_pop)
	if _volume.has_edits():
		_conform_surface(Vector3.ZERO, 10000.0)


func _terrain_height(direction: Vector3) -> float:
	return _height.height(self, direction)


func _zone_weights_from(dir: Vector3, height: float) -> PackedFloat32Array:
	var wet := _spring_shore(dir, height)
	var crater := _height.crater_mask(dir)
	var rocky := _height.rocky_amount(self, dir)
	rocky *= 1.0 - crater * 0.35
	rocky *= 1.0 - wet
	var forest := _forest.forest_cover(dir)
	forest *= (1.0 - rocky) * (1.0 - crater) * (1.0 - wet * 0.8)
	var prairie := (1.0 - forest) * (1.0 - rocky) * (1.0 - crater) * (1.0 - wet * 0.65)
	wet *= 1.0 - crater * 0.5
	var sum := prairie + forest + rocky + wet + crater
	if sum < 0.001:
		return PackedFloat32Array([1.0, 0.0, 0.0, 0.0, 0.0])
	return PackedFloat32Array([prairie / sum, forest / sum, rocky / sum, wet / sum, crater / sum])


func get_zone_weights(world_offset: Vector3) -> PackedFloat32Array:
	var direction := (global_transform.basis.inverse() * world_offset).normalized()
	if direction.length_squared() < 0.001:
		direction = Vector3.UP
	return _zone_weights_from(direction, _terrain_height(direction))


func ground_surface(world_position: Vector3) -> String:
	if point_in_water(world_position):
		return "water"
	var local := to_local(world_position)
	if local.length_squared() < 0.001:
		return "grass"
	if _volume != null and _volume.has_method(&"material_id_at"):
		var mat := int(_volume.call(&"material_id_at", local))
		if mat >= 2:
			return "stone"
		if _volume.has_method(&"near_edit") and bool(_volume.call(&"near_edit", local, 0.9)):
			return "dirt"
	var weights := _zone_weights_from(local.normalized(), local.length())
	var grass := weights[0] + weights[1]
	var stone := weights[2] + weights[4]
	var sand := weights[3]
	if stone >= grass and stone >= sand and stone > 0.42:
		return "stone"
	if sand >= grass and sand >= stone and sand > 0.45:
		return "sand"
	return "grass"


func _build_springs() -> void:
	_height._setup_noise(_spring_noise, world_seed + 131, 1.6 / maxf(biome_scale, 8.0), 2)
	for dir in _fibonacci_directions(260):
		if dir.dot(Vector3.UP) > 0.94:
			continue
		var height := _terrain_height(dir)
		if not _is_hollow(dir, height):
			continue
		var wet := _height.unit_noise(_spring_noise, dir * base_radius)
		if wet < 0.57:
			continue
		var crowded := false
		for other in _spring_dirs:
			if acos(clampf(dir.dot(other), -1.0, 1.0)) < 0.16:
				crowded = true
				break
		if crowded:
			continue
		_spring_dirs.append(dir)
		_spring_yield.append(70 + int(pow(wet, 2.0) * 2400.0))


func _is_hollow(dir: Vector3, height: float) -> bool:
	var basis := _basis_from_up(dir)
	var higher := 0
	for step in 8:
		var angle := TAU * float(step) / 8.0
		var neighbor := (dir + (basis.x * cos(angle) + basis.z * sin(angle)) * 0.05).normalized()
		if _terrain_height(neighbor) > height + 0.08:
			higher += 1
	return higher >= 5


func _spring_shore(dir: Vector3, height: float) -> float:
	var wet := 0.0
	for axis in _spring_dirs:
		var gap := acos(clampf(dir.dot(axis), -1.0, 1.0))
		if gap > 0.22:
			continue
		var band := 1.0 - smoothstep(0.04, 0.2, gap)
		var close := 1.0 - smoothstep(0.2, 2.2, absf(height - _terrain_height(axis)))
		wet = maxf(wet, band * close)
	return wet


func _is_water(direction: Vector3) -> bool:
	var dir := direction.normalized()
	var height := _terrain_height(dir)
	if _volume != null:
		var water = _volume.get_node_or_null(^"Water")
		if water != null and water.has_method(&"sea_level_radius"):
			var sea := float(water.call(&"sea_level_radius"))
			if sea > 1.0 and height < sea:
				return true
	for axis in _spring_dirs:
		var gap := acos(clampf(dir.dot(axis), -1.0, 1.0))
		if gap > 0.1:
			continue
		if height < _terrain_height(axis) + 0.45:
			return true
	return false


func _surface_position(direction: Vector3) -> Vector3:
	var dir := direction.normalized()
	return dir * _terrain_height(dir)


func _ground_color(point: Vector3, rock_mix: float) -> Color:
	return _height.ground_color(_zone_weights_from(point.normalized(), point.length()), rock_mix)


func _spawn_props(spawn_position: Vector3) -> void:
	_rocks.ensure_resources()
	var features := Node3D.new()
	features.name = "Features"
	add_child(features)
	var tree_positions: Array[Vector3] = []
	var tree_reaches := PackedFloat32Array()
	_forest.spawn_forest_trees(self, features, spawn_position, tree_positions, tree_reaches)
	var rock_positions: Array[Vector3] = []
	var rock_cap := clampi(int(round(float(rock_target) * lerpf(0.75, 1.45, plateau_frequency))), 16, 56)
	for direction in _shuffled_directions(700):
		if rock_positions.size() >= rock_cap:
			break
		if not _is_plantable(direction):
			continue
		var weights := _zone_weights_from(direction.normalized(), _terrain_height(direction))
		if randf() > weights[2] * 0.95 + weights[4] * 0.7 + weights[0] * 0.08:
			continue
		var position := _surface_position(direction)
		if position.distance_to(spawn_position) < 4.0:
			continue
		if _forest.tree_blocked(position, tree_positions, tree_reaches, maxf(rock_tree_clearance, 0.8), 0.0):
			continue
		if _is_near(position, rock_positions, rock_spacing):
			continue
		var key: String = _rocks.rock_key(direction)
		if not _rocks.is_rock_cut(key):
			_rocks.spawn_harvestable(self, features, direction, position, key)
		else:
			_rocks.burn_harvestable_rng()
		rock_positions.append(position)
	var iron_positions := _spawn_iron_deposits(features, spawn_position, rock_positions)
	_spawn_coal_deposits(features, spawn_position, rock_positions, iron_positions)
	_forest.spawn_more_trees(self, features, spawn_position, tree_positions, tree_reaches)
	_forest.spawn_wild_wheat(self, features, spawn_position, tree_positions)


func _spawn_iron_deposits(features: Node3D, spawn_position: Vector3, rock_positions: Array[Vector3]) -> Array[Vector3]:
	var iron_positions: Array[Vector3] = []
	var cap := clampi(int(round(float(iron_target) * iron_density)), 0, 48)
	if cap <= 0:
		return iron_positions
	var burial_lo := minf(iron_burial_min, iron_burial_max)
	var burial_hi := maxf(iron_burial_min, iron_burial_max)
	var rng := RandomNumberGenerator.new()
	rng.seed = _iron_spawn_seed()
	var directions := _fibonacci_directions(900)
	for i in range(directions.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := directions[i]
		directions[i] = directions[j]
		directions[j] = swap
	for direction in directions:
		if iron_positions.size() >= cap:
			break
		if not _is_plantable(direction):
			continue
		var weights := _zone_weights_from(direction.normalized(), _terrain_height(direction))
		var chance := weights[2] * iron_rarity + weights[4] * iron_rarity * 0.55 + weights[0] * iron_rarity * 0.04
		if rng.randf() > chance:
			continue
		var surface := _surface_position(direction)
		if surface.distance_to(spawn_position) < 6.0:
			continue
		if _is_near(surface, rock_positions, maxf(rock_spacing, 1.6)):
			continue
		if _is_near(surface, iron_positions, iron_spacing):
			continue
		var burial := rng.randf_range(burial_lo, burial_hi)
		var shallow_roll := rng.randf()
		var shallow_burial := rng.randf_range(0.35, minf(1.0, burial_lo))
		if shallow_roll < iron_shallow_chance:
			burial = shallow_burial
		var key: String = _rocks.iron_key(direction)
		if _rocks.is_rock_cut(key):
			_rocks.burn_iron_rng(rng)
			iron_positions.append(surface)
			continue
		_rocks.spawn_iron_deposit(self, features, direction, surface, burial, rng, key)
		iron_positions.append(surface)
	return iron_positions


func _spawn_coal_deposits(
	features: Node3D,
	spawn_position: Vector3,
	rock_positions: Array[Vector3],
	iron_positions: Array[Vector3]
) -> void:
	var cap := clampi(int(round(float(coal_target) * coal_density)), 0, 72)
	if cap <= 0:
		return
	var burial_lo := minf(coal_burial_min, coal_burial_max)
	var burial_hi := maxf(coal_burial_min, coal_burial_max)
	var rng := RandomNumberGenerator.new()
	rng.seed = _coal_spawn_seed()
	var directions := _fibonacci_directions(900)
	for i in range(directions.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := directions[i]
		directions[i] = directions[j]
		directions[j] = swap
	var coal_positions: Array[Vector3] = []
	for direction in directions:
		if coal_positions.size() >= cap:
			break
		if not _is_plantable(direction):
			continue
		var weights := _zone_weights_from(direction.normalized(), _terrain_height(direction))
		var chance := weights[2] * coal_rarity + weights[4] * coal_rarity * 0.65 + weights[0] * coal_rarity * 0.08
		if rng.randf() > chance:
			continue
		var surface := _surface_position(direction)
		if surface.distance_to(spawn_position) < 5.0:
			continue
		if _is_near(surface, rock_positions, maxf(rock_spacing * 0.85, 1.4)):
			continue
		if _is_near(surface, iron_positions, maxf(iron_spacing * 0.75, 3.0)):
			continue
		if _is_near(surface, coal_positions, coal_spacing):
			continue
		var burial := rng.randf_range(burial_lo, burial_hi)
		var shallow_roll := rng.randf()
		var shallow_burial := rng.randf_range(0.2, minf(0.85, burial_lo))
		if shallow_roll < coal_shallow_chance:
			burial = shallow_burial
		var key: String = _rocks.coal_key(direction)
		if _rocks.is_rock_cut(key):
			_rocks.burn_coal_rng(rng)
			coal_positions.append(surface)
			continue
		_rocks.spawn_coal_deposit(self, features, direction, surface, burial, rng, key)
		coal_positions.append(surface)


func _iron_spawn_seed() -> int:
	return int(hash(world_seed) ^ 0x1F07E0DE)


func _coal_spawn_seed() -> int:
	return int(hash(world_seed) ^ 0xC0A17EED)


func _is_plantable(direction: Vector3) -> bool:
	return not _is_water(direction)


func _slope_up(direction: Vector3) -> Vector3:
	var dir := direction.normalized()
	if dir.length_squared() < 0.001:
		return Vector3.UP
	var height := _terrain_height(dir)
	var basis := _basis_from_up(dir)
	var step := 1.35
	var east := _surface_position((dir * height + basis.x * step).normalized())
	var west := _surface_position((dir * height - basis.x * step).normalized())
	var north := _surface_position((dir * height + basis.z * step).normalized())
	var south := _surface_position((dir * height - basis.z * step).normalized())
	var normal := (east - west).cross(north - south)
	if normal.length_squared() < 0.0001 or normal.dot(dir) <= 0.0:
		return dir
	return normal.normalized()


func _crater_mask(dir: Vector3) -> float:
	return _height.crater_mask(dir)


func _rocky_amount(dir: Vector3) -> float:
	return _height.rocky_amount(self, dir)


func note_cut_tree(key: String) -> void:
	_forest.note_cut_tree(key)


func note_cut_rock(key: String) -> void:
	_rocks.note_cut_rock(key)


func export_cut_trees() -> Dictionary:
	return _forest.export_cut_trees()


func export_cut_rocks() -> Dictionary:
	return _rocks.export_cut_rocks()


func is_land(world_offset: Vector3) -> bool:
	var local := _local_offset(world_offset)
	if local.length_squared() < 0.001:
		return false
	return not _is_water(local.normalized())


func get_walk_radius(world_offset: Vector3) -> float:
	return _support_radius(_local_offset(world_offset))


func point_in_water(world_position: Vector3) -> bool:
	if _volume == null:
		return false
	return bool(_volume.call(&"point_in_water", to_local(world_position)))


func spring_id_at(local_pos: Vector3, voxel: float) -> int:
	_cache_springs(voxel)
	var cell := _pos_cell(local_pos, voxel)
	if not _spring_lookup.has(cell):
		return -1
	return int(_spring_lookup[cell])


func _cache_springs(voxel: float) -> void:
	if is_equal_approx(_spring_voxel, voxel):
		return
	_spring_voxel = voxel
	_spring_lookup.clear()
	for i in _spring_dirs.size():
		_spring_lookup[_mouth_cell(i, voxel)] = i


func _mouth_cell(index: int, voxel: float) -> Vector3i:
	var axis := _spring_dirs[index]
	var radius := _terrain_height(axis)
	var fallback := _pos_cell(axis * (radius + voxel), voxel)
	for _step in 6:
		radius += voxel * 0.5
		var cell := _pos_cell(axis * radius, voxel)
		if _volume != null and not bool(_volume.call(&"cell_is_solid", cell)):
			return cell
		var center := (Vector3(cell) + Vector3(0.5, 0.5, 0.5)) * voxel
		if center.length() > _terrain_height(center.normalized()) + voxel * 0.15:
			return cell
	return fallback


func _pos_cell(pos: Vector3, voxel: float) -> Vector3i:
	return Vector3i(floori(pos.x / voxel), floori(pos.y / voxel), floori(pos.z / voxel))


func spring_axes() -> PackedVector3Array:
	return _spring_dirs


func spring_budget(spring_id: int) -> int:
	if spring_id < 0 or spring_id >= _spring_yield.size():
		return 0
	return int(_spring_yield[spring_id])


func get_land_radius(world_offset: Vector3) -> float:
	return get_walk_radius(world_offset)


func sample_terrain_height(direction: Vector3) -> float:
	if direction.length_squared() < 0.001:
		return _terrain_height(Vector3.UP)
	return _terrain_height(direction.normalized())


func sample_ground_color(point: Vector3) -> Color:
	return _ground_color(point, 0.0)


func terrain_edited_near(local_point: Vector3, radius: float) -> bool:
	return _volume != null and bool(_volume.call(&"near_edit", local_point, radius))


func set_xray(enabled: bool) -> bool:
	_xray = enabled
	if _volume != null and _volume.has_method(&"set_xray"):
		_volume.call(&"set_xray", enabled)
	_apply_iron_xray(enabled)
	return _xray


func toggle_xray() -> bool:
	return set_xray(not _xray)


func is_xray() -> bool:
	return _xray


func hydro_network():
	return _hydro_net


func set_hydro_debug(enabled: bool) -> bool:
	_hydro_debug = enabled
	_refresh_hydro_debug()
	return _hydro_debug


func toggle_hydro_debug() -> bool:
	return set_hydro_debug(not _hydro_debug)


func is_hydro_debug() -> bool:
	return _hydro_debug


func _refresh_hydro_debug() -> void:
	if not _hydro_debug:
		if _hydro_debug_view != null and is_instance_valid(_hydro_debug_view):
			_hydro_debug_view.visible = false
		return
	if _hydro_debug_view == null or not is_instance_valid(_hydro_debug_view):
		_hydro_debug_view = MeshInstance3D.new()
		_hydro_debug_view.name = "HydroDebug"
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.no_depth_test = true
		mat.render_priority = 8
		_hydro_debug_view.material_override = mat
		_hydro_debug_view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_hydro_debug_view.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(_hydro_debug_view)
	_hydro_debug_view.mesh = _hydro_net.make_debug_mesh()
	_hydro_debug_view.visible = true


func _apply_iron_xray(enabled: bool) -> void:
	for node in get_tree().get_nodes_in_group(&"harvestable"):
		if str(node.get(&"resource_id")) != "iron_ore":
			continue
		if enabled:
			_ensure_iron_xray_marker(node as Node3D)
		else:
			_clear_iron_xray_marker(node as Node3D)


func _ensure_iron_xray_marker(rock: Node3D) -> void:
	if rock == null:
		return
	if rock.get_node_or_null(^"XrayMarker") != null:
		return
	var marker := MeshInstance3D.new()
	marker.name = "XrayMarker"
	var sphere := SphereMesh.new()
	sphere.radius = 0.55
	sphere.height = 1.1
	marker.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.45, 0.12, 0.95)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.15)
	mat.emission_energy_multiplier = 2.4
	mat.no_depth_test = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker.material_override = mat
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var aim_h := float(rock.get(&"aim_height")) if rock.get(&"aim_height") != null else 0.5
	marker.position = Vector3(0.0, aim_h, 0.0)
	rock.add_child(marker)


func _clear_iron_xray_marker(rock: Node3D) -> void:
	if rock == null:
		return
	var marker := rock.get_node_or_null(^"XrayMarker")
	if marker != null:
		marker.queue_free()


func dig_at(
	global_point: Vector3,
	global_normal: Vector3,
	tool_id: String,
	underfoot: bool = false,
	player_world: Vector3 = Vector3.ZERO
) -> Dictionary:
	if _volume == null:
		return {"drop": "", "removed": 0, "status": "blocked"}
	var player_local := Vector3.ZERO if player_world == Vector3.ZERO else to_local(player_world)
	var result: Variant = _volume.call(
		&"dig_global", global_point, global_normal, tool_id, underfoot, player_local
	)
	if result is Dictionary:
		return result
	return {"drop": str(result), "removed": 0 if str(result).is_empty() else 1, "status": "ok"}


func is_point_air(world_point: Vector3) -> bool:
	if _volume == null:
		return true
	return float(_volume.call(&"density_at", to_local(world_point))) <= 0.05


func march_terrain(origin: Vector3, direction: Vector3, reach: float) -> Dictionary:
	if _volume == null:
		return {}
	var hit: Variant = _volume.call(&"march_global", origin, direction, reach)
	return hit if hit is Dictionary else {}


func notify_terrain_edit(local_center: Vector3, radius: float) -> void:
	_conform_surface(local_center, radius)
	terrain_edited.emit(local_center, radius)


func _local_offset(world_offset: Vector3) -> Vector3:
	return global_transform.basis.inverse() * world_offset


func _support_radius(local_offset: Vector3) -> float:
	if local_offset.length_squared() < 0.001:
		local_offset = Vector3.UP
	if _volume == null:
		return _terrain_height(local_offset.normalized())
	return float(_volume.call(&"support_radius", local_offset))


func _conform_surface(local_center: Vector3, radius: float) -> void:
	for node in get_tree().get_nodes_in_group(&"harvestable"):
		_snap_prop(node as Node3D, local_center, radius + 1.6)
	var landmarks := get_node_or_null(^"Landmarks")
	if landmarks != null:
		for child in landmarks.get_children():
			_snap_prop(child as Node3D, local_center, radius + 1.6)
	var seen: Dictionary = {}
	for node in get_tree().get_nodes_in_group(&"construction"):
		_snap_build(node as Node3D, local_center, radius + 0.8, seen)


func _snap_prop(node: Node3D, center: Vector3, reach: float) -> void:
	if node == null:
		return
	if bool(node.get_meta(&"skip_terrain_snap", false)):
		return
	var local := to_local(node.global_position)
	if local.distance_to(center) > reach:
		return
	var dir := local.normalized()
	if dir.length_squared() < 0.001:
		return
	var procedural := _terrain_height(dir)
	var actual := get_land_radius(dir)
	if absf(actual - procedural) < 0.08:
		return
	node.global_position = to_global(dir * actual)


func _snap_build(node: Node3D, center: Vector3, reach: float, seen: Dictionary) -> void:
	if node == null or not is_instance_valid(node) or seen.has(node):
		return
	var hosts: Variant = node.get(&"_hosts")
	if hosts is Array and not (hosts as Array).is_empty():
		return
	var local := to_local(node.global_position)
	if local.distance_to(center) > reach:
		return
	var dir := local.normalized()
	if dir.length_squared() < 0.001:
		return
	var procedural := _terrain_height(dir)
	var actual := get_land_radius(dir)
	if absf(actual - procedural) < 0.08:
		return
	var above := local.length() - procedural
	if above < -1.0 or above > 14.0:
		return
	var delta := dir * (actual + above - local.length())
	_shift_build(node, global_transform.basis * delta, seen)


func _shift_build(node: Node3D, delta: Vector3, seen: Dictionary) -> void:
	if node == null or not is_instance_valid(node) or seen.has(node):
		return
	seen[node] = true
	node.global_position += delta
	var guests: Variant = node.get(&"_guests")
	if guests is Array:
		for link in guests:
			if link is Dictionary:
				var guest := (link as Dictionary).get("guest") as Node3D
				_shift_build(guest, delta, seen)


func _place_player(direction: Vector3, _ground_position: Vector3) -> void:
	var player := get_tree().get_first_node_in_group(&"player") as CharacterBody3D
	if player == null:
		return
	place_player_on_direction(player, direction)


func place_player_on_direction(player: CharacterBody3D, direction: Vector3) -> void:
	if player == null:
		return
	var up := direction.normalized()
	if up.length_squared() < 0.001:
		up = Vector3.UP
	var feet := to_global(up * get_walk_radius(up))
	player.velocity = Vector3.ZERO
	player.global_transform = Transform3D(_basis_from_up(up), feet + up * 0.05)


func place_player_near_world(player: CharacterBody3D, world_position: Vector3) -> bool:
	if player == null:
		return false
	var local := to_local(world_position)
	if local.length_squared() < 0.001:
		return false
	var base_dir := local.normalized()
	var height := local.length()
	var basis := _basis_from_up(base_dir)
	var ring_meters: Array[float] = [0.0, 1.5, 2.5, 3.5]
	for dist in ring_meters:
		var steps := 1 if dist <= 0.01 else 8
		for i in steps:
			var ang := float(i) * TAU / float(steps)
			var offset: Vector3 = (basis.x * cos(ang) + basis.z * sin(ang)) * dist
			var dir: Vector3 = (base_dir * height + offset).normalized()
			if not _is_plantable(dir):
				continue
			place_player_on_direction(player, dir)
			return true
	return false


func place_player_random(player: CharacterBody3D) -> bool:
	if player == null:
		return false
	for direction in _shuffled_directions(180):
		if not _is_plantable(direction):
			continue
		place_player_on_direction(player, direction)
		return true
	var fallback := _nearest_land_direction(Vector3.UP)
	if not _is_plantable(fallback):
		return false
	place_player_on_direction(player, fallback)
	return true


func _nearest_land_direction(from: Vector3) -> Vector3:
	var origin := from.normalized()
	var best := origin
	var best_score := -4.0
	var found := false
	for direction in _fibonacci_directions(180):
		if not _is_plantable(direction):
			continue
		var weights := _zone_weights_from(direction, _terrain_height(direction))
		var score := direction.dot(origin) + weights[0] * 0.5 - weights[4] * 1.1 - weights[2] * 0.35
		if score > best_score:
			best_score = score
			best = direction
			found = true
	return best if found else origin


func _shuffled_directions(count: int) -> Array[Vector3]:
	var directions := _fibonacci_directions(count)
	directions.shuffle()
	return directions


func _fibonacci_directions(count: int) -> Array[Vector3]:
	var directions: Array[Vector3] = []
	var golden := PI * (3.0 - sqrt(5.0))
	for i in count:
		var y := 1.0 - (float(i) / float(count - 1)) * 2.0
		var ring := sqrt(maxf(0.0, 1.0 - y * y))
		var theta := golden * i
		directions.append(Vector3(cos(theta) * ring, y, sin(theta) * ring))
	return directions


func _is_near(position: Vector3, others: Array[Vector3], min_distance: float) -> bool:
	for other in others:
		if position.distance_squared_to(other) < min_distance * min_distance:
			return true
	return false


func _basis_from_up(up: Vector3) -> Basis:
	var y := up.normalized()
	var reference := Vector3.FORWARD if absf(y.dot(Vector3.UP)) > 0.99 else Vector3.UP
	var x := reference.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _horizontal_reach(root: Node3D) -> float:
	var reach := 0.2
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		var local_box := mesh_node.get_aabb()
		var xform := _mesh_transform(root, mesh_node)
		for i in 8:
			var corner: Vector3 = xform * local_box.get_endpoint(i)
			reach = maxf(reach, Vector2(corner.x, corner.z).length())
	return reach


func _mesh_transform(root: Node3D, mesh_node: MeshInstance3D) -> Transform3D:
	var xform := mesh_node.transform
	var parent := mesh_node.get_parent() as Node3D
	while parent != null and parent != root:
		xform = parent.transform * xform
		parent = parent.get_parent() as Node3D
	return xform


func _ground_fit(root: Node3D) -> AABB:
	var box := _mesh_bounds(root)
	if box.size.length_squared() < 0.001:
		return AABB(Vector3(-0.4, 0, -0.4), Vector3(0.8, 2.0, 0.8))
	root.position -= Vector3(box.get_center().x, box.position.y, box.get_center().z)
	return AABB(Vector3(-box.size.x * 0.5, 0.0, -box.size.z * 0.5), box.size)


func _mesh_bounds(root: Node3D) -> AABB:
	var merged := AABB()
	var started := false
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		var local_box := mesh_node.get_aabb()
		var xform := mesh_node.transform
		var parent := mesh_node.get_parent() as Node3D
		while parent != null and parent != root:
			xform = parent.transform * xform
			parent = parent.get_parent() as Node3D
		for i in 8:
			var corner: Vector3 = xform * local_box.get_endpoint(i)
			if not started:
				merged = AABB(corner, Vector3.ZERO)
				started = true
			else:
				merged = merged.expand(corner)
	return merged


func _add_obstacle(parent: Node3D, shape: Shape3D, shape_position: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = OBSTACLE_LAYER
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = shape_position
	body.add_child(collision)
	parent.add_child(body)

func _best_zone_direction(zone: int) -> Vector3:
	var best := Vector3.ZERO
	var best_score := 0.35
	for direction in _fibonacci_directions(160):
		if not _is_plantable(direction):
			continue
		var weights := _zone_weights_from(direction, _terrain_height(direction))
		if weights[zone] > best_score:
			best_score = weights[zone]
			best = direction
	return best
