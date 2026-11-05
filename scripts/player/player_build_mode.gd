extends RefCounted
class_name PlayerBuildMode

signal mode_changed

const ITEMS := preload("res://scripts/resources/recipe_catalog.gd")
const BUILD_PLACEMENT := preload("res://scripts/building/build_placement.gd")
const BUILD_PIECE := preload("res://scripts/building/build_piece.gd")
const BUILD_CATALOG := preload("res://scripts/building/build_catalog.gd")

var build_piece := ""
var demolish_mode := false

var _host: CharacterBody3D
var _preview: Node3D
var _preview_id := ""
var _preview_materials: Array = []
var _place_rotation := 0
var _place_height := 0.0
var _place_suppressed := false
var _place_queued := false
var _place_item := ""
var _aimed: Node3D
var _demolish_queued := false


func setup(host: CharacterBody3D) -> void:
	_host = host


func handle_input(event: InputEvent) -> bool:
	if bool(_host.get(&"controls_locked")) or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	if _is_shift_wheel(event):
		if demolish_mode or build_piece.is_empty() or not can_elevate():
			return false
		var wheel := event as InputEventMouseButton
		var step := 0.25 if wheel.button_index == MOUSE_BUTTON_WHEEL_UP else -0.25
		_place_height = clampf(_place_height + step, 0.0, BUILD_CATALOG.max_foundation_lift())
		_place_suppressed = false
		return true
	if _is_mode_key(event):
		set_demolish_mode(not demolish_mode)
		return true
	if demolish_mode:
		if event.is_action_pressed(&"punch") and not event.is_echo():
			_demolish_queued = true
			return true
		if event.is_action_pressed(&"rotate_build") and not event.is_echo():
			return true
		if event is InputEventMouseButton:
			var demolish_button := event as InputEventMouseButton
			if demolish_button.pressed and demolish_button.button_index == MOUSE_BUTTON_RIGHT:
				return true
		return false
	if build_piece.is_empty():
		return false
	if event.is_action_pressed(&"rotate_build") and not event.is_echo():
		_place_rotation += 1
		_place_suppressed = false
		return true
	if event.is_action_pressed(&"punch") and not event.is_echo():
		_place_queued = true
		return true
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_RIGHT:
			cancel()
			return true
	return false


func blocks_hotbar_wheel(event: InputEvent) -> bool:
	var button := event as InputEventMouseButton
	return button != null and button.shift_pressed and can_elevate() and not demolish_mode


func begin(piece_id: String) -> void:
	if not ITEMS.is_construction(piece_id) or ITEMS.ingredients_of(piece_id).is_empty():
		return
	build_piece = piece_id
	_place_item = ""
	_place_rotation = 0
	_place_height = 0.0
	_place_suppressed = false
	_place_queued = false
	if demolish_mode:
		set_demolish_mode(false)
	else:
		mode_changed.emit()


func cancel() -> void:
	if build_piece.is_empty():
		return
	build_piece = ""
	_place_item = ""
	_place_queued = false
	_place_suppressed = false
	if _preview != null:
		_preview.visible = false
	mode_changed.emit()


func exit() -> bool:
	if build_piece.is_empty() and not demolish_mode:
		return false
	build_piece = ""
	_place_item = ""
	_place_queued = false
	_place_suppressed = false
	_demolish_queued = false
	if _preview != null:
		_preview.visible = false
	if demolish_mode:
		set_demolish_mode(false)
	else:
		mode_changed.emit()
	return true


func set_demolish_mode(enabled: bool) -> void:
	if demolish_mode == enabled:
		return
	demolish_mode = enabled
	_place_queued = false
	_demolish_queued = false
	_set_aimed(null)
	if _preview != null:
		_preview.visible = false
	mode_changed.emit()


func can_elevate() -> bool:
	return not build_piece.is_empty() and BUILD_CATALOG.elevates(ITEMS.kind_of(build_piece))


## Returns true when build/demolish/place consumed the frame (no punch).
func tick() -> bool:
	if demolish_mode:
		_update_demolition()
		return true
	if not build_piece.is_empty():
		_update_build_placement()
		return true
	var selected_use := ITEMS.use_of(_selected_id())
	if selected_use == "place":
		_update_placement()
		return true
	_set_aimed(null)
	if _preview != null:
		_preview.visible = false
	return false


func find_target() -> Node3D:
	var camera := _host.get_viewport().get_camera_3d()
	if camera == null:
		return null
	var origin := camera.global_position
	var direction := -camera.global_basis.z
	var best: Node3D = null
	var best_along := 12.0
	var hit_range := float(_host.get(&"hit_range"))
	for group in [&"construction", &"farm_plot"]:
		for node in _host.get_tree().get_nodes_in_group(group):
			var piece := node as Node3D
			if piece == null or not piece.has_method(&"aim_distance"):
				continue
			var along: float = piece.call(&"aim_distance", origin, direction, best_along)
			if along >= best_along:
				continue
			var hit_point := origin + direction * along
			if hit_point.distance_to(_host.global_position) > hit_range:
				continue
			best = piece
			best_along = along
	return best


func _is_shift_wheel(event: InputEvent) -> bool:
	var wheel := event as InputEventMouseButton
	if wheel == null or not wheel.pressed or not wheel.shift_pressed:
		return false
	return wheel.button_index == MOUSE_BUTTON_WHEEL_UP or wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN


func _is_mode_key(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return false
	return key.physical_keycode == KEY_C and not key.ctrl_pressed and not key.alt_pressed and not key.meta_pressed


func _selected_id() -> String:
	var inventory = _host.get(&"inventory")
	if inventory == null:
		return ""
	return str(inventory.call(&"get_selected_id"))


func _update_build_placement() -> void:
	var item_id := build_piece
	if item_id != _place_item:
		_place_item = item_id
		_place_rotation = 0
		_place_height = 0.0
		_place_suppressed = false
	var planet: Node3D = _host.get(&"_planet")
	if planet == null or bool(_host.get(&"controls_locked")) or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or _place_suppressed:
		_place_queued = false
		if _preview != null:
			_preview.visible = false
		return
	_ensure_preview(item_id)
	var solved: Dictionary = BUILD_PLACEMENT.solve(
		_host.get_tree(),
		planet,
		item_id,
		_placement_transform(),
		_place_rotation,
		_host.global_position,
		_place_height
	)
	var build_pose: Transform3D = solved["transform"]
	_preview.global_transform = build_pose
	_preview.visible = true
	var build_valid := bool(solved["valid"])
	var affordable := _can_pay(item_id)
	var site: Array = BUILD_PIECE.sync_site(_preview, item_id, planet, 0.45, false)
	_tint_preview(build_valid and affordable, site)
	if _place_queued:
		_place_queued = false
		if build_valid and affordable:
			_place_construction(item_id, build_pose, solved["links"])


func _can_pay(piece_id: String) -> bool:
	var cost := ITEMS.ingredients_of(piece_id)
	var inventory = _host.get(&"inventory")
	if cost.is_empty() or inventory == null:
		return false
	return bool(inventory.call(&"can_craft", {"ingredients": cost}))


func _update_placement() -> void:
	var item_id := _selected_id()
	if item_id != _place_item:
		_place_item = item_id
		_place_rotation = 0
		_place_height = 0.0
		_place_suppressed = false
	var planet: Node3D = _host.get(&"_planet")
	if planet == null or bool(_host.get(&"controls_locked")) or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or _place_suppressed:
		_place_queued = false
		if _preview != null:
			_preview.visible = false
		return
	_ensure_preview(item_id)
	var pose := _placement_transform()
	_preview.global_transform = pose
	_preview.visible = true
	var valid := _placement_valid(pose.origin)
	_tint_preview(valid)
	if valid and not bool(_host.get(&"_ignore_punch")) and Input.is_action_just_pressed(&"punch"):
		_place_selected(pose)


func _ensure_preview(item_id: String) -> void:
	if _preview != null and _preview_id == item_id:
		return
	if _preview != null:
		_preview.queue_free()
		_preview = null
	_preview = Node3D.new()
	_preview.name = "PlacementPreview"
	_preview_id = item_id
	_host.get_tree().current_scene.add_child(_preview)
	var script := ITEMS.placeable_script(item_id)
	_preview_materials = []
	if script != null:
		_preview_materials = script.call(&"add_visual", _preview, 0.45, item_id)


func _placement_transform() -> Transform3D:
	var planet: Node3D = _host.get(&"_planet")
	var up: Vector3 = _host.call(&"_get_surface_up")
	var camera_yaw: Node3D = _host.get_node(^"CameraYaw")
	var forward := -camera_yaw.global_transform.basis.z
	forward = (forward - up * forward.dot(up)).normalized()
	if forward.length_squared() < 0.001:
		forward = -_host.global_transform.basis.z
	var place_distance := float(_host.get(&"place_distance"))
	var offset := _host.global_position + forward * place_distance - planet.global_position
	if offset.length_squared() < 0.001:
		offset = up
	var outward := offset.normalized()
	var walk_radius: float = _host.call(&"_walk_radius", offset)
	return Transform3D(_aligned_basis(outward, forward), planet.global_position + outward * walk_radius)


func _aligned_basis(up: Vector3, forward: Vector3) -> Basis:
	var y := up.normalized()
	var z := forward - y * forward.dot(y)
	if z.length_squared() < 0.001:
		z = y.cross(Vector3.RIGHT)
	z = -z.normalized()
	var x := y.cross(z).normalized()
	z = x.cross(y).normalized()
	return Basis(x, y, z)


func _placement_valid(origin: Vector3) -> bool:
	var planet: Node3D = _host.get(&"_planet")
	var place_clearance := float(_host.get(&"place_clearance"))
	if planet == null or origin.distance_to(_host.global_position) < 1.15:
		return false
	if not bool(planet.call(&"is_land", origin - planet.global_position)):
		return false
	for node in _host.get_tree().get_nodes_in_group(&"harvestable"):
		var harvestable := node as Node3D
		if harvestable != null and harvestable.global_position.distance_to(origin) < place_clearance:
			return false
	for node in _host.get_tree().get_nodes_in_group(&"machine"):
		var machine := node as Node3D
		if machine != null and machine.global_position.distance_to(origin) < place_clearance:
			return false
	for node in _host.get_tree().get_nodes_in_group(&"construction"):
		var block := node as Node3D
		if block != null and block.global_position.distance_to(origin) < place_clearance:
			return false
	return true


func _tint_preview(valid: bool, extra: Array = []) -> void:
	var tint := Color(0.55, 1.0, 0.62) if valid else Color(1.0, 0.45, 0.4)
	var entries := _preview_materials
	if not extra.is_empty():
		entries = _preview_materials.duplicate()
		entries.append_array(extra)
	for entry in entries:
		var material := entry as ShaderMaterial
		if material == null:
			continue
		var base: Color = material.get_meta(&"base_color")
		material.set_shader_parameter(&"albedo", Color(base.r * tint.r, base.g * tint.g, base.b * tint.b, 0.45))


func _update_demolition() -> void:
	if _preview != null:
		_preview.visible = false
	if bool(_host.get(&"controls_locked")) or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_demolish_queued = false
		_set_aimed(null)
		return
	_set_aimed(find_target())
	if not _demolish_queued:
		return
	_demolish_queued = false
	if _aimed != null and is_instance_valid(_aimed) and _aimed.has_method(&"demolish"):
		var piece := _aimed
		_aimed = null
		piece.call(&"demolish")


func _set_aimed(piece: Node3D) -> void:
	if _aimed == piece:
		return
	if is_instance_valid(_aimed) and _aimed.has_method(&"set_highlighted"):
		_aimed.call(&"set_highlighted", false)
	_aimed = piece
	if is_instance_valid(_aimed) and _aimed.has_method(&"set_highlighted"):
		_aimed.call(&"set_highlighted", true)


func _place_construction(item_id: String, pose: Transform3D, links: Array) -> void:
	var script: Script = ITEMS.placeable_script(item_id)
	var cost := ITEMS.ingredients_of(item_id)
	var inventory = _host.get(&"inventory")
	var planet: Node3D = _host.get(&"_planet")
	if script == null or cost.is_empty() or inventory == null:
		return
	if not bool(inventory.call(&"try_consume", cost)):
		return
	var piece := script.new() as Node3D
	if piece == null:
		for resource_id in cost:
			inventory.call(&"add_resource", str(resource_id), int(cost[resource_id]))
		return
	_host.get_tree().current_scene.add_child(piece)
	piece.global_transform = pose
	piece.call(&"setup", item_id)
	BUILD_PLACEMENT.commit(piece, links)
	piece.call(&"apply_site", planet)
	AudioManager.build_place(str(piece.get(&"material_id")))


func _place_selected(pose: Transform3D) -> void:
	var item_id := _selected_id()
	var script: Script = ITEMS.placeable_script(item_id)
	var inventory = _host.get(&"inventory")
	if script == null or inventory == null:
		return
	var machine := script.new() as Node3D
	if machine == null:
		return
	_host.get_tree().current_scene.add_child(machine)
	machine.global_transform = pose
	inventory.call(&"add_resource", item_id, -1)
