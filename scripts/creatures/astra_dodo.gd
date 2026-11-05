extends CharacterBody3D

## Dodo bipède — IA calquée sur astra_grazer (indépendante), anim dédiée.
## Groupe `creature` + `receive_hit` (PlayerTools).

const DROPS := preload("res://scripts/farming/drops.gd")

enum State { IDLE, WANDER, SEEK_FOOD, FOLLOW_WHEAT, FLEE, DEAD }

@export var max_health: float = 4.0
@export var walk_speed: float = 2.8
@export var flee_speed: float = 5.8
@export var follow_speed: float = 3.1
@export var roam_radius: float = 12.0
@export var food_eat_range: float = 1.3
@export var follow_stop_range: float = 2.0
@export var flee_duration: float = 10.0
@export var flinch_duration: float = 0.18
@export var idle_time_min: float = 1.2
@export var idle_time_max: float = 3.2
@export var wander_time_min: float = 1.6
@export var wander_time_max: float = 4.2
@export var meat_id: String = "raw_meat"
@export var meat_qty: int = 1
@export var hide_id: String = "hide"
@export var hide_qty: int = 1

var health: float = 4.0
var _state: State = State.IDLE
var _state_left: float = 0.0
var _flee_left: float = 0.0
var _flinch_left: float = 0.0
var _home: Vector3 = Vector3.ZERO
var _move_dir: Vector3 = Vector3.ZERO
var _food_target: Node3D
var _planet: Node3D
var _visual: Node3D
var _anim: AstraDodoAnim
var _alive := true

const FOOD_IDS := ["wheat", "wheat_seeds", "bread"]
const HELD_ATTRACT_ID := "wheat"
const GRAVITY := 18.0
const FLOOR_SNAP := 0.08
const SURFACE_BAND := 0.06


func _ready() -> void:
	add_to_group(&"creature")
	add_to_group(&"dodo")
	collision_layer = 8
	collision_mask = 1 | 8
	floor_snap_length = FLOOR_SNAP
	health = max_health
	_visual = get_node_or_null(^"Visual") as Node3D
	_anim = get_node_or_null(^"Visual/DodoAnim") as AstraDodoAnim
	var model := get_node_or_null(^"Visual/ModelMount/dodo") as Node3D
	if _anim != null:
		_anim.setup(model)
	_planet = get_tree().get_first_node_in_group(&"planet") as Node3D
	call_deferred(&"_boot_pose")


func _boot_pose() -> void:
	_snap_to_surface()
	_home = global_position
	_enter(State.IDLE)


func _physics_process(delta: float) -> void:
	if not _alive or _planet == null:
		return
	var up := _surface_up()
	up_direction = up
	_align_to_up(up)
	_update_ai(delta, up)
	_apply_motion(delta, up)
	_update_anim(delta)


func aim_point() -> Vector3:
	return global_position + _surface_up() * 0.85


func is_exposed() -> bool:
	return true


func receive_hit(tool_id: String = "", damage_mult: float = 1.0) -> bool:
	if not _alive:
		return false
	var dmg := _damage_for(tool_id) * maxf(damage_mult, 0.0)
	health = maxf(health - dmg, 0.0)
	if health < 0.001:
		health = 0.0
	_flee_left = flee_duration
	_state = State.FLEE
	_food_target = null
	_face_away_from_player()
	_start_flinch()
	if health <= 0.0:
		_die()
	return true


func _damage_for(tool_id: String) -> float:
	match tool_id:
		"wooden_sword":
			return _damage_for_hits(4)
		"wooden_axe":
			return _damage_for_hits(5)
		"wooden_pickaxe":
			return _damage_for_hits(5)
		"wooden_shovel":
			return _damage_for_hits(8)
		"wooden_arrow":
			return _damage_for_hits(3)
	if tool_id.ends_with("sword"):
		return _damage_for_hits(3)
	if tool_id.ends_with("axe") or tool_id.ends_with("pickaxe"):
		return _damage_for_hits(3)
	if tool_id.ends_with("shovel") or tool_id.ends_with("hoe"):
		return _damage_for_hits(4)
	return _damage_for_hits(4)


func _damage_for_hits(hits: int) -> float:
	return max_health / float(maxi(hits, 1)) + 0.0001


func _die() -> void:
	_alive = false
	_state = State.DEAD
	_flinch_left = 0.0
	velocity = Vector3.ZERO
	var up := _surface_up()
	DROPS.spawn_list(
		global_position + up * 0.35,
		up,
		[
			{"id": meat_id, "qty": meat_qty},
			{"id": hide_id, "qty": hide_qty},
		],
		self
	)
	queue_free()


func _start_flinch() -> void:
	_flinch_left = flinch_duration
	_move_dir = Vector3.ZERO
	velocity = Vector3.ZERO
	if _anim != null:
		_anim.trigger_flinch(flinch_duration)


func _update_anim(delta: float) -> void:
	if _anim == null:
		return
	var fleeing := _state == State.FLEE and _flee_left > 0.0
	var moving := _flinch_left <= 0.0 and _move_dir.length_squared() > 0.001
	var ref_speed := flee_speed if fleeing else walk_speed
	var speed_ratio := 0.0
	if moving and ref_speed > 0.001:
		var planar := velocity - up_direction * velocity.dot(up_direction)
		speed_ratio = planar.length() / ref_speed
		if fleeing:
			speed_ratio = maxf(speed_ratio, 1.0)
	_anim.tick(delta, moving, fleeing, speed_ratio)


func _update_ai(delta: float, up: Vector3) -> void:
	if _flinch_left > 0.0:
		_flinch_left = maxf(_flinch_left - delta, 0.0)
		_flee_left = maxf(_flee_left - delta, 0.0)
		_move_dir = Vector3.ZERO
		if _flinch_left > 0.0:
			return
		if _flee_left > 0.0:
			_state = State.FLEE
			_face_away_from_player()
		elif _state == State.FLEE:
			_enter(State.IDLE)
		return

	if _flee_left > 0.0:
		_flee_left = maxf(_flee_left - delta, 0.0)
		_state = State.FLEE
		var player := _player()
		if player != null:
			_move_dir = _tangent_away(player.global_position, up)
		if _flee_left <= 0.0:
			_enter(State.IDLE)
		elif _move_dir.length_squared() > 0.001:
			_orient_visual(delta, _move_dir, up)
		return

	if _player_holds_wheat():
		_food_target = null
		_state = State.FOLLOW_WHEAT
		var holder := _player()
		var dist := global_position.distance_to(holder.global_position)
		if dist <= follow_stop_range:
			_move_dir = Vector3.ZERO
		else:
			_move_dir = _tangent_toward(holder.global_position, up)
			_orient_visual(delta, _move_dir, up)
		return

	_state_left -= delta
	match _state:
		State.FOLLOW_WHEAT:
			_enter(State.IDLE)
		State.IDLE:
			_move_dir = Vector3.ZERO
			if _state_left <= 0.0:
				if _try_seek_food():
					pass
				else:
					_pick_wander(up)
		State.WANDER:
			if _state_left <= 0.0 or _away_from_home() > roam_radius:
				_enter(State.IDLE)
			elif _try_seek_food():
				pass
		State.SEEK_FOOD:
			if not _food_valid():
				_enter(State.IDLE)
			elif global_position.distance_to(_food_target.global_position) <= food_eat_range:
				_graze_food()
				_enter(State.IDLE)
			else:
				_move_dir = _tangent_toward(_food_target.global_position, up)
		_:
			_move_dir = Vector3.ZERO

	if _move_dir.length_squared() > 0.001:
		_orient_visual(delta, _move_dir, up)


func _apply_motion(delta: float, up: Vector3) -> void:
	var wish := Vector3.ZERO
	if _flinch_left <= 0.0 and _move_dir.length_squared() > 0.001:
		var speed := walk_speed
		if _state == State.FLEE:
			speed = flee_speed
		elif _state == State.FOLLOW_WHEAT:
			speed = follow_speed
		wish = _move_dir * speed
	var vertical := velocity.dot(up)
	if _flinch_left > 0.0:
		wish = Vector3.ZERO
	var offset := global_position - _planet.global_position
	var on_surface := false
	if offset.length_squared() > 0.001 and _planet.has_method(&"get_walk_radius"):
		var radius: float = float(_planet.call(&"get_walk_radius", offset))
		var target_len := radius + 0.05
		var dist := offset.length()
		var err := dist - target_len
		if absf(err) <= SURFACE_BAND or err < -SURFACE_BAND:
			on_surface = true
			vertical = 0.0
			global_position = _planet.global_position + offset.normalized() * target_len
		else:
			vertical -= GRAVITY * delta
	else:
		vertical -= GRAVITY * delta
	velocity = wish + up * vertical
	move_and_slide()
	if on_surface:
		velocity -= up * velocity.dot(up)


func _enter(next: State) -> void:
	_state = next
	match next:
		State.IDLE:
			_state_left = randf_range(idle_time_min, idle_time_max)
			_move_dir = Vector3.ZERO
			_food_target = null
		State.WANDER:
			_state_left = randf_range(wander_time_min, wander_time_max)
		State.SEEK_FOOD:
			_state_left = 8.0
		State.FOLLOW_WHEAT:
			_state_left = 0.0
			_food_target = null
		State.FLEE:
			_food_target = null
		_:
			_state_left = 0.0


func _pick_wander(up: Vector3) -> void:
	var home_pull := _tangent_toward(_home, up)
	var random := _random_tangent(up)
	_move_dir = (random * 0.75 + home_pull * 0.25).normalized()
	if _move_dir.length_squared() < 0.001:
		_move_dir = random
	_enter(State.WANDER)


func _try_seek_food() -> bool:
	var food := _find_food()
	if food == null:
		return false
	_food_target = food
	_enter(State.SEEK_FOOD)
	return true


func _find_food() -> Node3D:
	var best: Node3D = null
	var best_d := roam_radius
	for node in get_tree().get_nodes_in_group(&"ground_item"):
		var item := node as Node3D
		if item == null:
			continue
		var id := str(item.get(&"resource_id"))
		if not FOOD_IDS.has(id):
			continue
		var d := global_position.distance_to(item.global_position)
		if d < best_d:
			best = item
			best_d = d
	return best


func _food_valid() -> bool:
	return _food_target != null and is_instance_valid(_food_target) and not _food_target.is_queued_for_deletion()


func _graze_food() -> void:
	if not _food_valid():
		return
	var qty := int(_food_target.get(&"quantity"))
	if qty <= 1:
		_food_target.queue_free()
	else:
		_food_target.set(&"quantity", qty - 1)
	_food_target = null


func _player_holds_wheat() -> bool:
	var player := _player()
	if player == null:
		return false
	var inventory = player.get(&"inventory")
	if inventory == null or not inventory.has_method(&"get_selected_id"):
		return false
	return str(inventory.call(&"get_selected_id")) == HELD_ATTRACT_ID


func _snap_to_surface() -> void:
	if _planet == null:
		_planet = get_tree().get_first_node_in_group(&"planet") as Node3D
	if _planet == null:
		return
	var offset := global_position - _planet.global_position
	if offset.length_squared() < 0.001:
		offset = Vector3.UP
	if not _planet.has_method(&"get_walk_radius"):
		return
	var radius: float = float(_planet.call(&"get_walk_radius", offset))
	var up := offset.normalized()
	global_position = _planet.global_position + up * (radius + 0.05)
	_align_to_up(up)


func _surface_up() -> Vector3:
	if _planet == null:
		return Vector3.UP
	var offset := global_position - _planet.global_position
	if offset.length_squared() < 0.001:
		return Vector3.UP
	return offset.normalized()


func _align_to_up(up: Vector3) -> void:
	var forward := -global_transform.basis.z
	forward = (forward - up * forward.dot(up)).normalized()
	if forward.length_squared() < 0.001:
		forward = up.cross(Vector3.RIGHT)
		if forward.length_squared() < 0.001:
			forward = up.cross(Vector3.FORWARD)
		forward = forward.normalized()
	look_at(global_position + forward, up)


func _orient_visual(delta: float, direction: Vector3, up: Vector3) -> void:
	if _visual == null or direction.length_squared() < 0.001 or _flinch_left > 0.0:
		return
	var flat := (direction - up * direction.dot(up)).normalized()
	if flat.length_squared() < 0.001:
		return
	var local := global_transform.basis.inverse() * flat
	var yaw := atan2(-local.x, -local.z)
	_visual.rotation.y = lerp_angle(_visual.rotation.y, yaw, 7.0 * delta)


func _tangent_toward(target: Vector3, up: Vector3) -> Vector3:
	var delta := target - global_position
	var flat := delta - up * delta.dot(up)
	if flat.length_squared() < 0.001:
		return Vector3.ZERO
	return flat.normalized()


func _tangent_away(target: Vector3, up: Vector3) -> Vector3:
	return -_tangent_toward(target, up)


func _random_tangent(up: Vector3) -> Vector3:
	var axis := up.cross(Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)))
	if axis.length_squared() < 0.001:
		axis = up.cross(Vector3.RIGHT)
	return axis.normalized()


func _away_from_home() -> float:
	return global_position.distance_to(_home)


func _player() -> Node3D:
	return get_tree().get_first_node_in_group(&"player") as Node3D


func _face_away_from_player() -> void:
	var player := _player()
	if player == null:
		return
	_move_dir = _tangent_away(player.global_position, _surface_up())
