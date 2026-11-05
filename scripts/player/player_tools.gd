extends RefCounted
class_name PlayerTools

const ITEMS := preload("res://scripts/resources/recipe_catalog.gd")
const TOOLS := preload("res://scripts/items/tool_scenes.gd")
const FARM := preload("res://scripts/farming/farming_config.gd")
const ARROW_PROJECTILE := preload("res://scenes/projectiles/wooden_arrow.tscn")

const ARROW_ID := "wooden_arrow"
const BOW_DRAW_TIME := 0.85
const BOW_MIN_RELEASE := 0.28
const BOW_SPEED_MIN := 14.0
const BOW_SPEED_MAX := 32.0
const BOW_DAMAGE_MIN := 0.45
const BOW_DAMAGE_MAX := 1.15
const BOW_AIM_DISTANCE := 48.0
## Offset pitch tir (degrés, positif = plus haut) pour coller au réticule.
const BOW_AIM_PITCH_DEG := 5.0

enum BowState { IDLE, AIMING, DRAWING }

var punch_weight := 0.0
var punch_phase := 0.0
var tool_held := false
var punching := false

var _host: CharacterBody3D
var _cooldown := 0.0
var _punch_time := 0.0
var _punch_impact_sent := false
var _equipped_tool_id := ""
var _rake_box: MeshInstance3D
var _rake_label: Label3D
var _rake_mat: StandardMaterial3D
var _bow_state: int = BowState.IDLE
var _bow_charge := 0.0
var _bow_node: Node3D
var _bow_shot_pending := false


func setup(host: CharacterBody3D) -> void:
	_host = host


func tick(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_sync_held_item()
	if selected_use() == "bow":
		_tick_bow(delta)
		punching = false
		punch_weight = 0.0
		punch_phase = 0.0
		_update_rake_preview()
		return
	if _bow_state != BowState.IDLE:
		_exit_bow()
	_update_punch(delta)
	_update_rake_preview()


func try_punch() -> void:
	if bool(_host.get(&"_eating")) or punching or _cooldown > 0.0 or selected_use() == "place":
		return
	if selected_use() == "bow":
		return
	if selected_use() == "consume":
		_host.call(&"_begin_eat")
		return
	if selected_use() == "tool" and not _tool_usable():
		return
	_cooldown = float(_host.get(&"hit_cooldown"))
	punching = true
	_punch_time = 0.0
	_punch_impact_sent = false
	punch_weight = 1.0
	punch_phase = 0.0
	_face_aim()


func is_bow_aiming() -> bool:
	return _bow_state == BowState.AIMING or _bow_state == BowState.DRAWING


func begin_bow_aim() -> bool:
	if selected_use() != "bow" or bool(_host.get(&"_eating")) or bool(_host.get(&"controls_locked")):
		return false
	if _bow_state != BowState.IDLE:
		return true
	_bow_state = BowState.AIMING
	_bow_charge = 0.0
	_bow_shot_pending = false
	_face_aim()
	_refresh_bow_node()
	_set_camera_aim(true)
	_sync_nocked_arrow()
	return true


func begin_bow_draw() -> bool:
	if _bow_state != BowState.AIMING and _bow_state != BowState.DRAWING:
		return false
	if bool(_host.get(&"_eating")) or bool(_host.get(&"controls_locked")):
		return false
	if not _tool_usable() or not _has_arrows():
		return false
	if _bow_state == BowState.DRAWING:
		return true
	_bow_state = BowState.DRAWING
	_bow_charge = 0.0
	_bow_shot_pending = false
	_face_aim()
	_refresh_bow_node()
	_sync_nocked_arrow()
	return true


func release_bow_draw() -> void:
	if _bow_state != BowState.DRAWING:
		return
	var charge := _bow_charge
	_bow_state = BowState.AIMING
	_bow_charge = 0.0
	_apply_bow_draw(0.0)
	if not _bow_shot_pending and charge >= BOW_MIN_RELEASE and _has_arrows() and _fire_arrow(charge):
		_bow_shot_pending = true
		_spend_arrow()
		_wear_selected_tool()
		_host.call(&"_spend_hunger", FARM.HUNGER_CHOP * 0.35)
	_bow_shot_pending = false
	_sync_nocked_arrow()


func cancel_bow_aim() -> void:
	_exit_bow()


func sync_bow_aim_visual() -> void:
	## Appelé après la pose bras (animation) pour coller l’arc / flèche au tir.
	if _bow_state == BowState.IDLE:
		return
	_refresh_bow_node()
	_orient_nocked_to_aim()


func cancel_bow_draw() -> void:
	if _bow_state == BowState.DRAWING:
		_bow_state = BowState.AIMING
		_bow_charge = 0.0
		_apply_bow_draw(0.0)
		_sync_nocked_arrow()
	else:
		_exit_bow()


func try_plant_plot() -> bool:
	if selected_use() != "plant":
		return false
	var plot := _find_plot_aim()
	if plot == null:
		return false
	return _try_plant_on(plot)


func selected_id() -> String:
	var inventory = _host.get(&"inventory")
	if inventory == null:
		return ""
	return str(inventory.call(&"get_selected_id"))


func selected_use() -> String:
	return ITEMS.use_of(selected_id())


func _update_punch(delta: float) -> void:
	var punch_duration := float(_host.get(&"punch_duration"))
	var impact_ratio := float(_host.get(&"impact_ratio"))
	if punching:
		_punch_time += delta
		var ratio := 0.84 if tool_held else clampf(impact_ratio, 0.05, 0.95)
		var impact_time := punch_duration * ratio
		if not _punch_impact_sent and _punch_time >= impact_time:
			_punch_impact_sent = true
			_on_punch_impact()
		if _punch_time >= punch_duration:
			punching = false
	if punching:
		punch_weight = 1.0
		punch_phase = clampf(_punch_time / maxf(punch_duration, 0.01), 0.0, 1.0)
	elif punch_weight > 0.0:
		punch_weight = maxf(punch_weight - delta / 0.16, 0.0)
		punch_phase = 1.0
	else:
		punch_phase = 0.0


func _on_punch_impact() -> void:
	var tool := selected_id()
	if selected_use() == "torch":
		_use_torch()
		return
	if tool.ends_with("rake") or tool.ends_with("hoe"):
		_use_rake()
		return
	if tool.ends_with("shovel"):
		_use_shovel()
		return
	var plot := _plot_from_ray()
	if plot != null:
		_use_plot(plot)
		return
	var struck := _harvestable_from_ray()
	if struck != null:
		_strike_harvestable(struck, tool)
		return
	var creature := _creature_from_ray()
	if creature != null:
		_strike_harvestable(creature, tool)
		return
	var target := _find_harvest_target()
	if target != null and target.has_method(&"receive_hit"):
		_strike_harvestable(target, tool)
		return
	var creature_aim := _find_creature_target()
	if creature_aim != null and creature_aim.has_method(&"receive_hit"):
		_strike_harvestable(creature_aim, tool)
		return
	_cut_grass()


func _use_torch() -> void:
	var struck := _harvestable_from_ray()
	if struck != null and _is_placed_torch(struck):
		_strike_harvestable(struck, selected_id())
		return
	_try_place_torch()


func _try_place_torch() -> bool:
	var inventory = _host.get(&"inventory")
	if inventory == null or int(inventory.call(&"get_amount", "torch")) <= 0:
		return false
	var hit := ground_aim()
	if hit.is_empty():
		return false
	if not _can_attach_torch(hit.get("collider") as Node):
		return false
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	if normal.length_squared() < 0.001:
		return false
	normal = normal.normalized()
	var origin: Vector3 = hit["position"] + normal * 0.03
	if origin.distance_to(_host.global_position) < 0.85:
		return false
	if _torch_blocked(origin):
		return false
	var script: Script = ITEMS.placeable_script("torch")
	if script == null:
		return false
	var torch := script.new() as Node3D
	if torch == null:
		return false
	_host.get_tree().current_scene.add_child(torch)
	torch.global_transform = Transform3D(_basis_from_normal(normal), origin)
	inventory.call(&"add_resource", "torch", -1)
	return true


func _can_attach_torch(collider: Node) -> bool:
	if collider == null:
		return false
	var planet: Node3D = _host.get(&"_planet")
	if planet != null and (collider == planet or planet.is_ancestor_of(collider)):
		return true
	var current := collider
	while current != null:
		if current.is_in_group(&"construction"):
			return true
		current = current.get_parent()
	return false


func _torch_blocked(origin: Vector3) -> bool:
	for node in _host.get_tree().get_nodes_in_group(&"machine"):
		if not _is_placed_torch(node):
			continue
		var torch := node as Node3D
		if torch != null and torch.global_position.distance_to(origin) < 0.35:
			return true
	return false


func _is_placed_torch(node: Node) -> bool:
	if node == null:
		return false
	var script: Script = node.get_script()
	if script == null:
		return false
	return str(script.resource_path).ends_with("torch.gd")


func _basis_from_normal(normal: Vector3) -> Basis:
	var y := normal.normalized()
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 0.001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _cut_grass() -> void:
	var planet: Node3D = _host.get(&"_planet")
	if planet == null:
		return
	var flora := planet.get_node_or_null(^"Flora")
	if flora == null or not flora.has_method(&"cut_at"):
		return
	var hit := ground_aim()
	if hit.is_empty():
		return
	flora.call(&"cut_at", planet.to_local(hit["position"]))


func _strike_harvestable(node: Node, tool: String) -> void:
	var hit := _tool_ray_hit()
	var hit_point: Variant = hit.get("position", null) if not hit.is_empty() else null
	if not bool(node.call(&"receive_hit", tool, hit_point)):
		return
	_spend_tool_hunger(tool)
	AudioManager.tool_impact(tool)
	if node.is_queued_for_deletion():
		AudioManager.break_harvest(str(node.get(&"required_tool")))
	elif node.has_method(&"is_chop_falling") and bool(node.call(&"is_chop_falling")):
		AudioManager.break_harvest("axe")


func _use_shovel() -> void:
	var planet: Node3D = _host.get(&"_planet")
	if planet == null:
		return
	var camera := _host.get_viewport().get_camera_3d()
	if camera == null:
		return
	var origin := camera.global_position
	var forward := -camera.global_basis.z
	var hit := _tool_ray_hit()
	if not hit.is_empty():
		var harvestable := _harvestable_from(hit.collider as Node)
		if harvestable != null:
			if str(harvestable.get(&"required_tool")) == "shovel" and bool(harvestable.call(&"receive_hit", selected_id())):
				_spend_tool_hunger(selected_id())
				AudioManager.tool_impact(selected_id())
			return
		if not planet.is_ancestor_of(hit.collider):
			return
		if _dig_terrain(hit.position, hit.normal):
			_spend_tool_hunger(selected_id())
			AudioManager.tool_impact(selected_id())
		return
	var marched: Dictionary = planet.call(&"march_terrain", origin, forward, _tool_ray_length(origin))
	if marched.is_empty():
		return
	var point: Vector3 = marched["point"]
	if point.distance_to(_host.global_position) > _tool_reach():
		return
	if _dig_terrain(point, marched["normal"]):
		_spend_tool_hunger(selected_id())
		AudioManager.tool_impact(selected_id())


func _dig_terrain(point: Vector3, normal: Vector3) -> bool:
	var planet: Node3D = _host.get(&"_planet")
	var underfoot := _is_dig_underfoot(point)
	var result: Variant = planet.call(
		&"dig_at", point, normal, selected_id(), underfoot, _host.global_position
	)
	var drop := ""
	var removed := 0
	if result is Dictionary:
		drop = str(result.get("drop", ""))
		removed = int(result.get("removed", 0))
	else:
		drop = str(result)
		removed = 0 if drop.is_empty() else 1
	if removed <= 0 or drop.is_empty():
		return false
	var inventory = _host.get(&"inventory")
	if inventory != null:
		inventory.call(&"add_resource", drop, 1)
	return true


func _is_dig_underfoot(point: Vector3) -> bool:
	var planet: Node3D = _host.get(&"_planet")
	if planet == null:
		return false
	var feet := planet.to_local(_host.global_position)
	if feet.length_squared() < 0.001:
		return false
	var up := feet.normalized()
	var hit := planet.to_local(point)
	var delta := hit - feet
	var along := delta.dot(up)
	var lateral := (delta - up * along).length()
	# Sous les pieds / au sol proche : latéral < largeur joueur, hit sous les hanches.
	return lateral <= 0.7 and along < 0.35


func _harvestable_from(node: Node) -> Node:
	var current := node
	while current != null:
		if current.is_in_group(&"harvestable"):
			return current
		current = current.get_parent()
	return null


func _creature_from(node: Node) -> Node:
	var current := node
	while current != null:
		if current.is_in_group(&"creature"):
			return current
		current = current.get_parent()
	return null


func _creature_from_ray() -> Node:
	var hit := _tool_ray_hit()
	if hit.is_empty():
		return null
	return _creature_from(hit.collider as Node)


func _find_creature_target() -> Node3D:
	var camera := _host.get_viewport().get_camera_3d()
	if camera == null:
		return null
	var origin := camera.global_position
	var direction := -camera.global_basis.z
	var aim_radius := float(_host.get(&"aim_radius"))
	var best: Node3D = null
	var best_along := INF
	for node in _host.get_tree().get_nodes_in_group(&"creature"):
		var creature := node as Node3D
		if creature == null:
			continue
		if creature.has_method(&"is_exposed") and not bool(creature.call(&"is_exposed")):
			continue
		var point: Vector3 = creature.call(&"aim_point") if creature.has_method(&"aim_point") else creature.global_position
		if point.distance_to(_host.global_position) > _tool_reach():
			continue
		var to_point := point - origin
		var along := to_point.dot(direction)
		if along < 0.2:
			continue
		var lateral := (to_point - direction * along).length()
		if lateral > aim_radius or along >= best_along:
			continue
		best = creature
		best_along = along
	return best


func _tool_reach() -> float:
	var body_shape: CollisionShape3D = _host.get_node_or_null(^"CollisionShape3D")
	var shape := body_shape.shape if body_shape != null else null
	if shape is CapsuleShape3D:
		var cap := shape as CapsuleShape3D
		var size := cap.height + cap.radius * 2.0
		return size * 2.0
	return 3.4


func _tool_ray_length(origin: Vector3) -> float:
	return _tool_reach() + origin.distance_to(_host.global_position)


func _tool_ray_hit() -> Dictionary:
	var camera := _host.get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var origin := camera.global_position
	var forward := -camera.global_basis.z
	var space := _host.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin + forward * _tool_ray_length(origin),
		1 | 8,
		[_host.get_rid()]
	)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return {}
	if hit.position.distance_to(_host.global_position) > _tool_reach():
		return {}
	return hit


func _harvestable_from_ray() -> Node:
	var hit := _tool_ray_hit()
	if hit.is_empty():
		return null
	return _harvestable_from(hit.collider as Node)


func _face_aim() -> void:
	var camera := _host.get_viewport().get_camera_3d()
	if camera == null:
		return
	var up: Vector3 = _host.call(&"_get_surface_up")
	var forward := -camera.global_basis.z
	forward = (forward - up * forward.dot(up)).normalized()
	if forward.length_squared() < 0.001:
		return
	var local_direction := _host.global_transform.basis.inverse() * forward
	var visual: Node3D = _host.get_node(^"Visual")
	visual.rotation.y = atan2(-local_direction.x, -local_direction.z)


func _find_harvest_target() -> Node3D:
	var camera := _host.get_viewport().get_camera_3d()
	if camera == null:
		return null
	var origin := camera.global_position
	var direction := -camera.global_basis.z
	var aim_radius := float(_host.get(&"aim_radius"))
	var best: Node3D = null
	var best_along := INF
	for node in _host.get_tree().get_nodes_in_group(&"harvestable"):
		var harvestable := node as Node3D
		if harvestable == null:
			continue
		if harvestable.has_method(&"is_exposed") and not bool(harvestable.call(&"is_exposed")):
			continue
		var point: Vector3 = harvestable.call(&"aim_point") if harvestable.has_method(&"aim_point") else harvestable.global_position
		if point.distance_to(_host.global_position) > _tool_reach():
			continue
		var to_point := point - origin
		var along := to_point.dot(direction)
		if along < 0.2:
			continue
		var lateral := (to_point - direction * along).length()
		if lateral > aim_radius or along >= best_along:
			continue
		best = harvestable
		best_along = along
	return best


func _sync_held_item() -> void:
	var held_id := selected_id()
	tool_held = TOOLS.has_tool(held_id)
	var tool_mount: Node3D = _host.get_node_or_null(^"Visual/Torso/RightArmPivot/RightArm/ToolMount")
	if tool_mount == null:
		return
	if held_id == _equipped_tool_id:
		_refresh_bow_node()
		return
	if _bow_state != BowState.IDLE:
		_exit_bow()
	for child in tool_mount.get_children():
		child.queue_free()
	_equipped_tool_id = held_id if tool_held else ""
	_bow_node = null
	if not tool_held:
		return
	var visual := TOOLS.instantiate(held_id)
	if visual != null:
		tool_mount.add_child(visual)
		_refresh_bow_node()


func _tick_bow(delta: float) -> void:
	_refresh_bow_node()
	if _bow_state == BowState.IDLE:
		_apply_bow_draw(0.0)
		return
	if (
		bool(_host.get(&"controls_locked"))
		or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
		or selected_use() != "bow"
	):
		_exit_bow()
		return
	_face_aim()
	_set_camera_aim(true)
	_orient_nocked_to_aim()
	# Resync LMB si press/release a été mangé par l’UI.
	var punch_held := Input.is_action_pressed(&"punch") and not bool(_host.get(&"_ignore_punch"))
	if _bow_state == BowState.AIMING and punch_held:
		begin_bow_draw()
	elif _bow_state == BowState.DRAWING and not punch_held:
		release_bow_draw()
		return
	if _bow_state == BowState.DRAWING:
		if not _has_arrows() or not _tool_usable():
			_bow_state = BowState.AIMING
			_bow_charge = 0.0
			_apply_bow_draw(0.0)
			_sync_nocked_arrow()
			return
		_bow_charge = minf(_bow_charge + delta / BOW_DRAW_TIME, 1.0)
		_apply_bow_draw(_bow_charge)
	else:
		_apply_bow_draw(0.0)
		_sync_nocked_arrow()


func _exit_bow() -> void:
	_bow_state = BowState.IDLE
	_bow_charge = 0.0
	_bow_shot_pending = false
	_apply_bow_draw(0.0)
	if _bow_node != null and _bow_node.has_method(&"clear_nocked_arrow"):
		_bow_node.call(&"clear_nocked_arrow")
	if _bow_node != null and _bow_node.has_method(&"clear_aim_align"):
		_bow_node.call(&"clear_aim_align")
	_set_camera_aim(false)


func _apply_bow_draw(amount: float) -> void:
	if _bow_node != null and _bow_node.has_method(&"set_draw"):
		_bow_node.call(&"set_draw", amount)


func _refresh_bow_node() -> void:
	var tool_mount: Node3D = _host.get_node_or_null(^"Visual/Torso/RightArmPivot/RightArm/ToolMount")
	if tool_mount == null or tool_mount.get_child_count() == 0:
		_bow_node = null
		return
	var child := tool_mount.get_child(0) as Node3D
	_bow_node = child if child != null and child.has_method(&"set_draw") else null


func _sync_nocked_arrow() -> void:
	if _bow_node == null or not _bow_node.has_method(&"show_nocked_arrow"):
		return
	var show := _bow_state != BowState.IDLE and _has_arrows()
	_bow_node.call(&"show_nocked_arrow", show)
	if show:
		_orient_nocked_to_aim()


func _orient_nocked_to_aim() -> void:
	var camera := _host.get_viewport().get_camera_3d()
	if camera == null or _bow_node == null:
		return
	var up: Vector3 = _host.call(&"_get_surface_up")
	var origin := _bow_muzzle_origin(camera)
	var dir := _bow_shot_direction(camera, origin)
	if _bow_node.has_method(&"align_to_shot"):
		_bow_node.call(&"align_to_shot", dir, up)
	if _bow_node.has_method(&"orient_nocked"):
		_bow_node.call(&"orient_nocked", dir, up)


func _set_camera_aim(active: bool) -> void:
	var yaw: Node = _host.get_node_or_null(^"CameraYaw")
	if yaw != null and yaw.has_method(&"set_bow_aim"):
		yaw.call(&"set_bow_aim", active)


func _has_arrows() -> bool:
	var inventory = _host.get(&"inventory")
	if inventory == null:
		return false
	return int(inventory.call(&"get_amount", ARROW_ID)) > 0


func _spend_arrow() -> void:
	var inventory = _host.get(&"inventory")
	if inventory == null:
		return
	inventory.call(&"add_resource", ARROW_ID, -1)


func _bow_aim_point(camera: Camera3D) -> Vector3:
	var forward := -camera.global_basis.z
	var from := camera.global_position
	var to := from + forward * BOW_AIM_DISTANCE
	var space := _host.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 8, [_host.get_rid()])
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		return hit["position"] as Vector3
	return to


func _bow_muzzle_origin(camera: Camera3D) -> Vector3:
	_refresh_bow_node()
	if _bow_node != null and _bow_node.has_method(&"muzzle_global"):
		return _bow_node.call(&"muzzle_global") as Vector3
	return camera.global_position - camera.global_basis.z * 0.55


func _bow_shot_direction(camera: Camera3D, origin: Vector3) -> Vector3:
	var dir := _bow_aim_point(camera) - origin
	if dir.length_squared() < 0.0001:
		dir = -camera.global_basis.z
	else:
		dir = dir.normalized()
	# Pitch manuel autour de l’axe droit caméra (positif = plus haut).
	var right := camera.global_basis.x
	if right.length_squared() > 0.0001 and not is_zero_approx(BOW_AIM_PITCH_DEG):
		dir = dir.rotated(right.normalized(), deg_to_rad(BOW_AIM_PITCH_DEG))
	return dir.normalized()


func _fire_arrow(charge: float) -> bool:
	var camera := _host.get_viewport().get_camera_3d()
	if camera == null:
		return false
	var t := clampf(charge, 0.0, 1.0)
	var speed := lerpf(BOW_SPEED_MIN, BOW_SPEED_MAX, t)
	var dmg := lerpf(BOW_DAMAGE_MIN, BOW_DAMAGE_MAX, t)
	var origin := _bow_muzzle_origin(camera)
	var direction := _bow_shot_direction(camera, origin)
	if _bow_node != null and _bow_node.has_method(&"clear_nocked_arrow"):
		_bow_node.call(&"clear_nocked_arrow")
	var arrow := ARROW_PROJECTILE.instantiate() as Node
	if arrow == null:
		return false
	arrow.set(&"power", t)
	arrow.set(&"damage_mult", dmg)
	arrow.set(&"shooter", _host)
	_host.get_tree().current_scene.add_child(arrow)
	if arrow.has_method(&"launch"):
		arrow.call(&"launch", origin, direction, speed)
	return true


func _tool_usable() -> bool:
	var inventory = _host.get(&"inventory")
	if inventory == null or not inventory.has_method(&"can_use_selected_tool"):
		return true
	return bool(inventory.call(&"can_use_selected_tool"))


func _spend_tool_hunger(tool: String) -> void:
	if tool.ends_with("pickaxe"):
		_host.call(&"_spend_hunger", FARM.HUNGER_MINE)
	elif tool.ends_with("shovel"):
		_host.call(&"_spend_hunger", FARM.HUNGER_DIG)
	elif tool.ends_with("axe"):
		_host.call(&"_spend_hunger", FARM.HUNGER_CHOP)
	elif tool.ends_with("hoe") or tool.ends_with("rake"):
		_host.call(&"_spend_hunger", FARM.HUNGER_DIG)
	_wear_selected_tool()


func _wear_selected_tool() -> void:
	var inventory = _host.get(&"inventory")
	if inventory == null or not inventory.has_method(&"wear_selected_tool"):
		return
	inventory.call(&"wear_selected_tool")


func _use_rake() -> void:
	var hit := _rake_aim()
	if hit.is_empty():
		return
	var farming := _host.get_tree().get_first_node_in_group(&"farming")
	if farming == null:
		return
	if bool(farming.call(&"try_till", hit["position"])):
		_spend_tool_hunger(selected_id())
		AudioManager.tool_impact(selected_id())


func _update_rake_preview() -> void:
	var till_tool := selected_id()
	var planet: Node3D = _host.get(&"_planet")
	if bool(_host.get(&"controls_locked")) or planet == null or (not till_tool.ends_with("rake") and not till_tool.ends_with("hoe")):
		_hide_rake_preview()
		return
	var hit := _rake_aim()
	if hit.is_empty():
		_hide_rake_preview()
		return
	var farming := _host.get_tree().get_first_node_in_group(&"farming")
	if farming == null or not farming.has_method(&"inspect"):
		_hide_rake_preview()
		return
	var info: Dictionary = farming.call(&"inspect", hit["position"])
	var cell: Vector3i = info.get("cell", Vector3i.ZERO)
	_ensure_rake_preview()
	if not farming.has_method(&"patch_frame"):
		_hide_rake_preview()
		return
	var frame: Dictionary = farming.call(&"patch_frame", cell)
	var normal: Vector3 = frame["normal"]
	var radius := float(frame["radius"])
	if normal.length_squared() < 0.01 or radius < 1.0:
		_hide_rake_preview()
		return
	normal = normal.normalized()
	var halves: Array = FARM.tangent_halves(normal)
	var half_u: Vector3 = halves[0]
	var half_v: Vector3 = halves[1]
	var lift := FARM.cell_on_plane(cell, normal, radius) + normal * 0.04
	var p00 := lift - half_u - half_v
	var p10 := lift + half_u - half_v
	var p11 := lift + half_u + half_v
	var p01 := lift - half_u + half_v
	if (p10 - p00).cross(p01 - p00).dot(normal) < 0.0:
		var swap := p10
		p10 = p01
		p01 = swap
	var verts := PackedVector3Array([p00, p10, p11, p00, p11, p01])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_rake_box.mesh = mesh
	_rake_box.global_transform = planet.global_transform
	var ok := bool(info.get("ok", false))
	_rake_mat.albedo_color = Color(0.25, 0.9, 0.35, 0.35) if ok else Color(0.95, 0.22, 0.18, 0.4)
	_rake_box.visible = true
	_rake_label.global_position = planet.to_global(lift + normal * 0.7)
	_rake_label.visible = not ok
	if not ok:
		_rake_label.text = TranslationServer.translate("PLOT_" + str(info.get("reason", "empty")).to_upper())


func _rake_aim() -> Dictionary:
	var hit := ground_aim()
	var planet: Node3D = _host.get(&"_planet")
	if hit.is_empty() or planet == null:
		return {}
	var collider := hit.get("collider") as Node
	if _harvestable_from(collider) != null:
		return {}
	if _plot_from(collider) != null:
		return hit
	if collider == planet or planet.is_ancestor_of(collider):
		return hit
	return {}


func _ensure_rake_preview() -> void:
	if _rake_box != null:
		return
	_rake_mat = StandardMaterial3D.new()
	_rake_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rake_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rake_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rake_mat.albedo_color = Color(0.25, 0.9, 0.35, 0.35)
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * FARM.CELL
	_rake_box = MeshInstance3D.new()
	_rake_box.mesh = mesh
	_rake_box.material_override = _rake_mat
	_rake_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rake_box.top_level = true
	_rake_box.visible = false
	_host.add_child(_rake_box)
	_rake_label = Label3D.new()
	_rake_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_rake_label.font_size = 48
	_rake_label.pixel_size = 0.002
	_rake_label.outline_size = 8
	_rake_label.modulate = Color(1, 0.9, 0.9)
	_rake_label.no_depth_test = true
	_rake_label.top_level = true
	_rake_label.visible = false
	_host.add_child(_rake_label)


func _hide_rake_preview() -> void:
	if _rake_box != null:
		_rake_box.visible = false
	if _rake_label != null:
		_rake_label.visible = false


func _use_plot(plot: Node) -> void:
	if _try_plant_on(plot):
		return
	if bool(plot.call(&"is_mature")):
		plot.call(&"harvest")


func _try_plant_on(plot: Node) -> bool:
	if plot == null or selected_use() != "plant" or not bool(plot.call(&"is_empty")):
		return false
	var inventory = _host.get(&"inventory")
	if inventory == null or int(inventory.call(&"get_amount", "wheat_seeds")) <= 0:
		return false
	if not bool(plot.call(&"plant", "wheat")):
		return false
	inventory.call(&"add_resource", "wheat_seeds", -1)
	return true


func _plot_from_ray() -> Node:
	return _find_plot_aim()


func _find_plot_aim() -> Node:
	var hit := _tool_ray_hit()
	if not hit.is_empty():
		var plot := _plot_from(hit.collider as Node)
		if plot != null:
			return plot
		plot = _plot_at_aim(hit["position"])
		if plot != null:
			return plot
	var ground := ground_aim()
	if ground.is_empty():
		return null
	return _plot_at_aim(ground["position"])


func _plot_at_aim(global_point: Vector3) -> Node:
	var farming := _host.get_tree().get_first_node_in_group(&"farming")
	if farming == null:
		return null
	var info: Dictionary = farming.call(&"inspect", global_point)
	if str(info.get("reason", "")) != "taken":
		return null
	var cell: Vector3i = info.get("cell", Vector3i.ZERO)
	for node in _host.get_tree().get_nodes_in_group(&"farm_plot"):
		if node.get(&"cell") == cell:
			return node
	return null


func _plot_from(node: Node) -> Node:
	var current := node
	while current != null:
		if current.is_in_group(&"farm_plot"):
			return current
		current = current.get_parent()
	return null


func ground_aim() -> Dictionary:
	var hit := _tool_ray_hit()
	if not hit.is_empty():
		return hit
	var planet: Node3D = _host.get(&"_planet")
	if planet == null:
		return {}
	var camera := _host.get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var origin := camera.global_position
	var forward := -camera.global_basis.z
	var marched: Dictionary = planet.call(&"march_terrain", origin, forward, _tool_ray_length(origin))
	if marched.is_empty():
		return {}
	var point: Vector3 = marched["point"]
	if point.distance_to(_host.global_position) > _tool_reach():
		return {}
	return {
		"position": point,
		"normal": marched["normal"],
		"collider": planet,
	}
