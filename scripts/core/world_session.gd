extends Node3D

const ITEMS := preload("res://scripts/resources/recipe_catalog.gd")
const GROUND_ITEM := preload("res://scenes/resources/ground_item.tscn")
const AUTOSAVE := 60.0

var paused := false
var _autosave := 0.0
var _left := false


func _ready() -> void:
	add_to_group(&"world_session")
	_restore()


func _process(delta: float) -> void:
	if _left or paused or not SaveManager.has_active():
		return
	SaveManager.play_time += delta
	_autosave += delta
	if _autosave < AUTOSAVE:
		return
	_autosave = 0.0
	save_now()


func save_now() -> void:
	if _left:
		return
	_write()


func save_and_quit() -> void:
	if _left:
		return
	paused = true
	_write()
	_left = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(SaveManager.MENU_SCENE)


func _write() -> void:
	if not SaveManager.has_active():
		return
	SaveManager.write_state(_capture())
	var volume := get_node_or_null(^"Planet/TerrainVolume")
	if volume != null and bool(volume.call(&"is_edit_dirty")):
		SaveManager.write_terrain(volume.call(&"export_edits"))
		volume.call(&"mark_edits_saved")


func _capture() -> Dictionary:
	return {
		"player": _capture_player(),
		"inventory": get_node(^"Player/Inventory").call(&"export_state"),
		"buildings": _capture_buildings(),
		"machines": _capture_machines(),
		"day_time": _capture_time(),
		"weather": _capture_weather(),
		"progression": SaveManager.progression(),
		"crops": _capture_crops(),
		"wild_wheat": _capture_wild(),
		"cut_grass": _capture_grass(),
		"cut_trees": _capture_trees(),
		"cut_rocks": _capture_rocks(),
		"buffalos": _capture_buffalos(),
	}


func _capture_player() -> Dictionary:
	var player := get_node(^"Player") as Node3D
	return {
		"origin": [player.global_position.x, player.global_position.y, player.global_position.z],
		"basis": _basis_array(player.global_basis),
		"health": float(player.get(&"health")),
		"hunger": float(player.get(&"hunger")),
	}


func _capture_buildings() -> Array:
	var nodes: Array = []
	for node in get_tree().get_nodes_in_group(&"construction"):
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			nodes.append(node)
	var index_of := {}
	for i in nodes.size():
		index_of[(nodes[i] as Node).get_instance_id()] = i
	var out: Array = []
	for node in nodes:
		var piece := node as Node3D
		var hosts: Array = []
		for link in piece.call(&"export_links"):
			var data: Dictionary = link
			var host_id := int(data.get("host_id", 0))
			if not index_of.has(host_id):
				continue
			hosts.append({
				"host": int(index_of[host_id]),
				"host_index": int(data.get("host_index", 0)),
				"plug_index": int(data.get("plug_index", 0)),
			})
		out.append({
			"id": str(piece.get("piece_id")),
			"origin": [piece.global_position.x, piece.global_position.y, piece.global_position.z],
			"basis": _basis_array(piece.global_basis),
			"storage": piece.call(&"export_storage"),
			"hosts": hosts,
		})
	return out


func _capture_machines() -> Array:
	var out: Array = []
	for node in get_tree().get_nodes_in_group(&"machine"):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		var machine := node as Node3D
		var item_id := _machine_id(machine)
		if item_id.is_empty():
			continue
		var state: Dictionary = {}
		if machine.has_method(&"export_state"):
			state = machine.call(&"export_state")
		out.append({
			"id": item_id,
			"origin": [machine.global_position.x, machine.global_position.y, machine.global_position.z],
			"basis": _basis_array(machine.global_basis),
			"state": state,
		})
	return out


func _capture_time() -> float:
	var sky := get_node_or_null(^"SkySystem")
	if sky != null and sky.has_method(&"export_time"):
		return float(sky.call(&"export_time"))
	return 0.0


func _capture_weather() -> Dictionary:
	var weather := get_node_or_null(^"WeatherManager")
	if weather != null and weather.has_method(&"export_state"):
		return weather.call(&"export_state")
	return {}


func _restore() -> void:
	if not SaveManager.has_player_state():
		return
	var data := SaveManager.state()
	_restore_player(data.get("player", {}))
	var inventory: Variant = data.get("inventory", {})
	if inventory is Dictionary and not (inventory as Dictionary).is_empty():
		get_node(^"Player/Inventory").call(&"import_state", inventory)
		_refund_carried_builds()
	_restore_buildings(data.get("buildings", []))
	_restore_machines(data.get("machines", []))
	var crops: Variant = data.get("crops", [])
	if crops is Array:
		_restore_crops(crops)
	var sky := get_node_or_null(^"SkySystem")
	if sky != null and sky.has_method(&"import_time") and data.has("day_time"):
		sky.call(&"import_time", float(data.get("day_time", 0.0)))
	var weather_state: Variant = data.get("weather", {})
	var weather := get_node_or_null(^"WeatherManager")
	if weather != null and weather.has_method(&"import_state") and weather_state is Dictionary and not (weather_state as Dictionary).is_empty():
		weather.call(&"import_state", weather_state)
	_restore_buffalos(data.get("buffalos", []))
	_resolve_player_death_after_load()


func _resolve_player_death_after_load() -> void:
	var player := get_node_or_null(^"Player")
	if player != null and player.has_method(&"resolve_death_after_load"):
		player.call(&"resolve_death_after_load")


func _restore_player(raw: Variant) -> void:
	if not raw is Dictionary or (raw as Dictionary).is_empty():
		return
	var data: Dictionary = raw
	var player := get_node(^"Player") as CharacterBody3D
	player.velocity = Vector3.ZERO
	player.global_transform = Transform3D(_basis_from(data.get("basis", [])), _vector_from(data.get("origin", [])))
	player.set(&"health", float(data.get("health", player.get(&"health"))))
	player.emit_signal(&"health_changed", float(player.get(&"health")), float(player.get(&"max_health")))
	var max_hunger := float(player.get(&"max_hunger"))
	player.set(&"hunger", float(data.get("hunger", max_hunger)))
	player.emit_signal(&"hunger_changed", float(player.get(&"hunger")), max_hunger)


func _refund_carried_builds() -> void:
	var inventory := get_node(^"Player/Inventory")
	var slots: Variant = inventory.get(&"slots")
	if not slots is PackedStringArray:
		return
	var packed: PackedStringArray = slots
	var payout: Dictionary = {}
	var clear: Array[int] = []
	for i in packed.size():
		var stack: Dictionary = inventory.call(&"get_slot_stack", i)
		var id := str(stack["id"])
		var count := int(stack["count"])
		if count <= 0 or not ITEMS.is_construction(id):
			continue
		clear.append(i)
		var cost: Dictionary = ITEMS.refund_of(id)
		for mat in cost:
			var key := str(mat)
			payout[key] = int(payout.get(key, 0)) + int(cost[mat]) * count
	for i in clear:
		inventory.call(&"set_slot_stack", i, "", 0)
	var player := get_node(^"Player") as Node3D
	for mat in payout:
		var left := int(inventory.call(&"add_resource", str(mat), int(payout[mat])))
		if left <= 0 or player == null:
			continue
		var drop := GROUND_ITEM.instantiate() as Node3D
		drop.set(&"resource_id", str(mat))
		drop.set(&"quantity", left)
		add_child(drop)
		drop.global_position = player.global_position + player.global_transform.basis.y * 1.2


func _restore_buildings(rows: Variant) -> void:
	if not rows is Array:
		return
	var planet := get_node(^"Planet")
	var spawned: Array = []
	for row in rows:
		var info: Dictionary = row
		var script: Script = ITEMS.placeable_script(str(info.get("id", "")))
		if script == null:
			spawned.append(null)
			continue
		var piece := script.new() as Node3D
		if piece == null:
			spawned.append(null)
			continue
		add_child(piece)
		piece.global_transform = Transform3D(_basis_from(info.get("basis", [])), _vector_from(info.get("origin", [])))
		piece.call(&"setup", str(info.get("id", "")))
		piece.call(&"import_storage", info.get("storage", {}))
		spawned.append(piece)
	for i in (rows as Array).size():
		var piece: Node = spawned[i]
		if piece == null or not is_instance_valid(piece):
			continue
		var info: Dictionary = (rows as Array)[i]
		for link in info.get("hosts", []):
			var data: Dictionary = link
			var host_i := int(data.get("host", -1))
			if host_i < 0 or host_i >= spawned.size():
				continue
			var host: Node = spawned[host_i]
			if host == null or not is_instance_valid(host):
				continue
			piece.call(&"attach_to", host, int(data.get("host_index", 0)), int(data.get("plug_index", 0)))
	for piece in spawned:
		if piece == null or not is_instance_valid(piece) or piece.is_queued_for_deletion():
			continue
		piece.call(&"apply_site", planet)


func _restore_machines(rows: Variant) -> void:
	if not rows is Array:
		return
	for row in rows:
		var info: Dictionary = row
		var script: Script = ITEMS.placeable_script(str(info.get("id", "")))
		if script == null:
			continue
		var machine := script.new() as Node3D
		if machine == null:
			continue
		add_child(machine)
		machine.global_transform = Transform3D(_basis_from(info.get("basis", [])), _vector_from(info.get("origin", [])))
		if machine.has_method(&"import_state"):
			machine.call(&"import_state", info.get("state", {}))


func _capture_crops() -> Array:
	var out: Array = []
	for node in get_tree().get_nodes_in_group(&"farm_plot"):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		var plot := node as Node3D
		if plot == null:
			continue
		var cell := plot.get(&"cell") as Vector3i
		out.append({
			"cell": [cell.x, cell.y, cell.z],
			"crop_id": str(plot.get(&"crop_id")),
			"planted_at": float(plot.get(&"planted_at")),
		})
	return out


func _capture_grass() -> Dictionary:
	var flora := get_node_or_null(^"Planet/Flora")
	if flora != null and flora.has_method(&"export_cuts"):
		return flora.call(&"export_cuts")
	var saved: Variant = SaveManager.state().get("cut_grass", {})
	if saved is Dictionary:
		return (saved as Dictionary).duplicate()
	return {}


func _capture_trees() -> Dictionary:
	var planet := get_node_or_null(^"Planet")
	if planet != null and planet.has_method(&"export_cut_trees"):
		return planet.call(&"export_cut_trees")
	var saved: Variant = SaveManager.state().get("cut_trees", {})
	if saved is Dictionary:
		return (saved as Dictionary).duplicate()
	return {}


func _capture_rocks() -> Dictionary:
	var planet := get_node_or_null(^"Planet")
	if planet != null and planet.has_method(&"export_cut_rocks"):
		return planet.call(&"export_cut_rocks")
	var saved: Variant = SaveManager.state().get("cut_rocks", {})
	if saved is Dictionary:
		return (saved as Dictionary).duplicate()
	return {}


func _capture_wild() -> Dictionary:
	var farming := get_tree().get_first_node_in_group(&"farming")
	if farming != null and farming.has_method(&"export_wild"):
		var state: Variant = farming.call(&"export_wild")
		if state is Dictionary:
			return state
	var saved: Variant = SaveManager.state().get("wild_wheat", {})
	if saved is Dictionary:
		return (saved as Dictionary).duplicate()
	return {}


func _capture_buffalos() -> Array:
	var pop := get_node_or_null(^"Planet/BuffaloPopulation")
	if pop != null and pop.has_method(&"export_state"):
		var rows: Variant = pop.call(&"export_state")
		if rows is Array:
			return rows
	return []


func _restore_buffalos(raw: Variant) -> void:
	var pop := get_node_or_null(^"Planet/BuffaloPopulation")
	if pop == null or not pop.has_method(&"import_state"):
		return
	pop.call(&"import_state", raw)


func _restore_crops(rows: Array) -> void:
	var farming := get_node_or_null(^"Planet/Farming")
	if farming == null or not farming.has_method(&"restore_plots"):
		return
	farming.call(&"restore_plots", rows)


func _machine_id(machine: Node) -> String:
	var script: Script = machine.get_script()
	if script == null:
		return ""
	var path := script.resource_path
	if path.ends_with("primitive_drill.gd"):
		return "primitive_drill"
	if path.ends_with("camp_totem.gd"):
		return "camp_totem"
	if path.ends_with("furnace.gd"):
		return "furnace"
	if path.ends_with("flour_grinder.gd"):
		return "flour_grinder"
	if path.ends_with("fermentation_tank.gd"):
		return "fermentation_tank"
	if path.ends_with("distillery.gd"):
		return "distillery"
	if path.ends_with("torch.gd"):
		return "torch"
	return ""


func _basis_array(basis: Basis) -> Array:
	return [
		basis.x.x, basis.x.y, basis.x.z,
		basis.y.x, basis.y.y, basis.y.z,
		basis.z.x, basis.z.y, basis.z.z,
	]


func _basis_from(raw: Variant) -> Basis:
	if not raw is Array or (raw as Array).size() < 9:
		return Basis.IDENTITY
	var values: Array = raw
	return Basis(
		Vector3(float(values[0]), float(values[1]), float(values[2])),
		Vector3(float(values[3]), float(values[4]), float(values[5])),
		Vector3(float(values[6]), float(values[7]), float(values[8]))
	)


func _vector_from(raw: Variant) -> Vector3:
	if not raw is Array or (raw as Array).size() < 3:
		return Vector3.ZERO
	var values: Array = raw
	return Vector3(float(values[0]), float(values[1]), float(values[2]))
