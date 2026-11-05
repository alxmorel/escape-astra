extends Node3D

## Population faune (buffles par défaut) : groupes 1–5, plafond, spawn échelonné, save/load.
## Réutilisable pour dodos : même script + `creature_scene` = astra_dodo.tscn + groupe dédié.

const DEFAULT_CREATURE := preload("res://scenes/creatures/astra_grazer.tscn")

@export var creature_scene: PackedScene = DEFAULT_CREATURE
@export var population_group: StringName = &"buffalo_population"
@export var managed_meta: StringName = &"buffalo_managed"
@export var target_population: int = 24
@export_range(1, 5, 1) var min_group_size: int = 1
@export_range(1, 5, 1) var max_group_size: int = 5
@export var min_player_distance: float = 36.0
@export var member_spacing: float = 3.6
@export var group_spacing: float = 26.0
@export var build_clearance: float = 8.0
@export var spawn_interval: float = 0.85
@export var restore_interval: float = 0.05
@export var anchor_attempts: int = 48
@export var member_attempts: int = 16

var _planet: Node3D
var _cooldown := 0.0
var _group_left := 0
var _group_anchor_dir := Vector3.UP
var _group_positions: Array[Vector3] = []
var _restore_queue: Array = []
var _restoring := false
var _rng := RandomNumberGenerator.new()
var _dir_pool: Array[Vector3] = []
var _dir_index := 0
var _member_fails := 0


func _ready() -> void:
	add_to_group(population_group)
	if creature_scene == null:
		creature_scene = DEFAULT_CREATURE
	_planet = get_parent() as Node3D
	var seed_value := 1
	if _planet != null and _planet.get(&"world_seed") != null:
		seed_value = int(_planet.get(&"world_seed"))
	_rng.seed = int(hash(seed_value) ^ hash(str(population_group)))
	if _planet != null and _planet.has_method(&"_fibonacci_directions"):
		_dir_pool = _planet.call(&"_fibonacci_directions", 320)
		_dir_pool.shuffle()


func _process(delta: float) -> void:
	if _planet == null or not is_instance_valid(_planet):
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	_prune_dead()
	if _restoring:
		_tick_restore()
		return
	if _cooldown > 0.0:
		return
	if _group_left > 0:
		_tick_group_member()
		return
	_try_start_group()


func living_count() -> int:
	var n := 0
	for child in get_children():
		if is_instance_valid(child) and not child.is_queued_for_deletion():
			n += 1
	return n


func export_state() -> Array:
	var rows: Array = []
	for child in get_children():
		var body := child as Node3D
		if body == null or not is_instance_valid(body) or body.is_queued_for_deletion():
			continue
		rows.append({
			"origin": [body.global_position.x, body.global_position.y, body.global_position.z],
			"basis": _basis_array(body.global_basis),
			"health": float(body.get(&"health")) if body.get(&"health") != null else 4.0,
		})
	return rows


func import_state(raw: Variant) -> void:
	for child in get_children():
		child.queue_free()
	_group_left = 0
	_group_positions.clear()
	_restore_queue.clear()
	_restoring = false
	if not raw is Array:
		return
	for row in raw:
		if row is Dictionary:
			_restore_queue.append((row as Dictionary).duplicate(true))
	_restoring = not _restore_queue.is_empty()
	_cooldown = 0.0


func _tick_restore() -> void:
	if _cooldown > 0.0:
		return
	if _restore_queue.is_empty():
		_restoring = false
		_cooldown = spawn_interval
		return
	var row: Dictionary = _restore_queue.pop_front()
	_spawn_at_transform(_vector_from(row.get("origin", [])), _basis_from(row.get("basis", [])), float(row.get("health", 4.0)))
	_cooldown = restore_interval


func _try_start_group() -> void:
	var need := target_population - living_count()
	if need <= 0:
		_cooldown = spawn_interval
		return
	var size := clampi(_rng.randi_range(min_group_size, max_group_size), 1, max_group_size)
	size = mini(size, need)
	var anchor := _pick_group_anchor()
	if anchor.length_squared() < 0.001:
		_cooldown = spawn_interval * 2.0
		return
	_group_anchor_dir = anchor
	_group_left = size
	_group_positions.clear()
	_member_fails = 0
	_tick_group_member()


func _tick_group_member() -> void:
	if living_count() >= target_population:
		_group_left = 0
		_group_positions.clear()
		_cooldown = spawn_interval
		return
	if _group_left <= 0:
		_cooldown = spawn_interval
		return
	if _spawn_group_member():
		_group_left -= 1
		_member_fails = 0
		_cooldown = spawn_interval
	else:
		# Reessaie sans brûler le quota ; abandonne le groupe si l’ancre est saturée.
		_member_fails += 1
		_cooldown = 0.35
		if _member_fails >= member_attempts:
			_group_left = 0
			_group_positions.clear()
			_member_fails = 0
			_cooldown = spawn_interval


func _spawn_group_member() -> bool:
	var dir := _group_anchor_dir
	if not _group_positions.is_empty():
		dir = _offset_dir(_group_anchor_dir, member_spacing * (0.65 + _rng.randf() * 0.7))
	for _i in member_attempts:
		if _try_spawn_direction(dir):
			return true
		dir = _offset_dir(_group_anchor_dir, member_spacing * (0.8 + _rng.randf() * 1.4))
	return false


func _pick_group_anchor() -> Vector3:
	for _i in anchor_attempts:
		var dir := _next_direction()
		if not _is_spawn_dir_ok(dir):
			continue
		var world := _world_on_surface(dir)
		if not _is_spawn_world_ok(world, true):
			continue
		return dir
	return Vector3.ZERO


func _try_spawn_direction(direction: Vector3) -> bool:
	var dir := direction.normalized()
	if not _is_spawn_dir_ok(dir):
		return false
	var world := _world_on_surface(dir)
	if not _is_spawn_world_ok(world, false):
		return false
	var up := dir
	if _planet.has_method(&"_slope_up"):
		up = (_planet.call(&"_slope_up", dir) as Vector3).normalized()
	var basis: Basis = Basis.IDENTITY
	if _planet.has_method(&"_basis_from_up"):
		basis = _planet.call(&"_basis_from_up", up)
	var buffalo := _spawn_at_transform(world + up * 0.05, basis, -1.0)
	if buffalo == null:
		return false
	_group_positions.append(world)
	return true


func _spawn_at_transform(origin: Vector3, basis: Basis, health: float) -> Node3D:
	if living_count() >= target_population and health < 0.0:
		return null
	if creature_scene == null:
		return null
	var animal := creature_scene.instantiate() as Node3D
	if animal == null:
		return null
	animal.set_meta(managed_meta, true)
	add_child(animal)
	animal.global_transform = Transform3D(basis.orthonormalized(), origin)
	if health >= 0.0:
		animal.set(&"health", health)
		animal.set(&"max_health", maxf(float(animal.get(&"max_health")), health))
	return animal


func _is_spawn_dir_ok(direction: Vector3) -> bool:
	if _planet == null:
		return false
	var dir := direction.normalized()
	if dir.length_squared() < 0.001:
		return false
	if _planet.has_method(&"_is_plantable") and not bool(_planet.call(&"_is_plantable", dir)):
		return false
	if _planet.has_method(&"get_zone_weights"):
		var world := _world_on_surface(dir)
		var weights: PackedFloat32Array = _planet.call(&"get_zone_weights", world - _planet.global_position)
		if weights.size() >= 5:
			if weights[4] > 0.42:
				return false
			if weights[2] > 0.55:
				return false
			if weights[3] > 0.62:
				return false
			if weights[1] > 0.78:
				return false
	return true


func _is_spawn_world_ok(world: Vector3, as_group_anchor: bool) -> bool:
	if _planet == null:
		return false
	if _planet.has_method(&"point_in_water") and bool(_planet.call(&"point_in_water", world)):
		return false
	if _planet.has_method(&"ground_surface"):
		var surface := str(_planet.call(&"ground_surface", world))
		if surface == "water" or surface == "stone":
			return false
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if player != null and world.distance_to(player.global_position) < min_player_distance:
		return false
	var min_peer := group_spacing if as_group_anchor else member_spacing
	for child in get_children():
		var other := child as Node3D
		if other == null or not is_instance_valid(other):
			continue
		if world.distance_to(other.global_position) < min_peer:
			return false
	for pos in _group_positions:
		if world.distance_to(pos) < member_spacing * 0.85:
			return false
	for node in get_tree().get_nodes_in_group(&"construction"):
		var build := node as Node3D
		if build != null and world.distance_to(build.global_position) < build_clearance:
			return false
	for node in get_tree().get_nodes_in_group(&"safe_zone"):
		var zone := node as Node3D
		if zone != null and world.distance_to(zone.global_position) < maxf(build_clearance, 12.0):
			return false
	return true


func _world_on_surface(direction: Vector3) -> Vector3:
	var dir := direction.normalized()
	var local := dir
	if _planet.has_method(&"_surface_position"):
		local = _planet.call(&"_surface_position", dir)
	elif _planet.has_method(&"get_walk_radius"):
		local = dir * float(_planet.call(&"get_walk_radius", dir))
	return _planet.to_global(local)


func _offset_dir(anchor: Vector3, arc_meters: float) -> Vector3:
	var up := anchor.normalized()
	var basis: Basis
	if _planet != null and _planet.has_method(&"_basis_from_up"):
		basis = _planet.call(&"_basis_from_up", up)
	else:
		basis = Basis.looking_at(Vector3.FORWARD, up)
	var ang := _rng.randf() * TAU
	var height := 1.0
	if _planet != null and _planet.has_method(&"_terrain_height"):
		height = float(_planet.call(&"_terrain_height", up))
	var offset: Vector3 = (basis.x * cos(ang) + basis.z * sin(ang)) * arc_meters
	return (up * height + offset).normalized()


func _next_direction() -> Vector3:
	if _dir_pool.is_empty():
		return Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)).normalized()
	_dir_index = (_dir_index + 1) % _dir_pool.size()
	if _dir_index == 0:
		_dir_pool.shuffle()
	return _dir_pool[_dir_index]


func _prune_dead() -> void:
	for child in get_children():
		if not is_instance_valid(child) or child.is_queued_for_deletion():
			continue


func _basis_array(basis: Basis) -> Array:
	return [
		basis.x.x, basis.x.y, basis.x.z,
		basis.y.x, basis.y.y, basis.y.z,
		basis.z.x, basis.z.y, basis.z.z,
	]


func _basis_from(raw: Variant) -> Basis:
	if not raw is Array or (raw as Array).size() < 9:
		return Basis.IDENTITY
	var a: Array = raw
	return Basis(
		Vector3(float(a[0]), float(a[1]), float(a[2])),
		Vector3(float(a[3]), float(a[4]), float(a[5])),
		Vector3(float(a[6]), float(a[7]), float(a[8]))
	)


func _vector_from(raw: Variant) -> Vector3:
	if not raw is Array or (raw as Array).size() < 3:
		return Vector3.ZERO
	var a: Array = raw
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
