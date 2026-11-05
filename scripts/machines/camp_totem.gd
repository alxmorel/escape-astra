extends Node3D

const STYLIZED := preload("res://scripts/resources/stylized_material.gd")

@export var safe_radius: float = 16.0
@export var regen_per_second: float = 10.0

var _zone_mesh: SphereMesh


func _ready() -> void:
	add_to_group(&"machine")
	add_to_group(&"safe_zone")
	add_visual(self, 1.0)
	_build_zone()


func export_state() -> Dictionary:
	return {"safe_radius": safe_radius, "regen_per_second": regen_per_second}


func import_state(data: Dictionary) -> void:
	safe_radius = float(data.get("safe_radius", safe_radius))
	regen_per_second = float(data.get("regen_per_second", regen_per_second))


func _process(_delta: float) -> void:
	if _zone_mesh == null or is_equal_approx(_zone_mesh.radius, safe_radius):
		return
	_zone_mesh.radius = safe_radius
	_zone_mesh.height = safe_radius * 2.0


static func is_player_in_safe_zone() -> bool:
	var player := _player()
	if player == null:
		return false
	return is_in_safe_zone(player.global_position)


static func is_in_safe_zone(world_position: Vector3) -> bool:
	for node in _zones():
		var zone := node as Node3D
		if zone == null:
			continue
		if zone.global_position.distance_to(world_position) <= float(zone.get(&"safe_radius")):
			return true
	return false


static func can_target_player() -> bool:
	return not is_player_in_safe_zone()


static func should_abandon_pursuit(mob_position: Vector3) -> bool:
	return is_in_safe_zone(mob_position) or is_player_in_safe_zone()


static func current_regen_per_second() -> float:
	var player := _player()
	if player == null:
		return 0.0
	var best := 0.0
	for node in _zones():
		var zone := node as Node3D
		if zone == null:
			continue
		if zone.global_position.distance_to(player.global_position) > float(zone.get(&"safe_radius")):
			continue
		best = maxf(best, float(zone.get(&"regen_per_second")))
	return best


static func is_valid_totem(node: Node) -> bool:
	if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
		return false
	if not node is Node3D:
		return false
	var script: Script = node.get_script()
	if script == null:
		return false
	return str(script.resource_path).ends_with("camp_totem.gd")


static func list_valid() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for node in _zones():
		if is_valid_totem(node):
			out.append(node as Node3D)
	return out


static func pick_closest(from: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for totem in list_valid():
		var d := totem.global_position.distance_squared_to(from)
		if d < best_d:
			best_d = d
			best = totem
	return best


static func _player() -> Node3D:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.get_first_node_in_group(&"player") as Node3D


static func _zones() -> Array[Node]:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		var empty: Array[Node] = []
		return empty
	return tree.get_nodes_in_group(&"safe_zone")


static func add_visual(parent: Node3D, alpha: float, _item_id: String = "") -> Array:
	var materials: Array = []
	_add_box(parent, Vector3(0, 0.16, 0), Vector3(0.7, 0.32, 0.7), Color(0.42, 0.42, 0.44), alpha, materials)
	_add_box(parent, Vector3(0, 0.72, 0), Vector3(0.28, 0.9, 0.28), Color(0.45, 0.28, 0.14), alpha, materials)
	_add_box(parent, Vector3(0, 1.28, 0), Vector3(0.42, 0.22, 0.42), Color(0.55, 0.56, 0.52), alpha, materials)
	return materials


static func _add_box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, alpha: float, materials: Array) -> void:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.position = pos
	var material := STYLIZED.create(color, alpha)
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)
	materials.append(material)


func _build_zone() -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "SafeZone"
	_zone_mesh = SphereMesh.new()
	_zone_mesh.radius = safe_radius
	_zone_mesh.height = safe_radius * 2.0
	_zone_mesh.radial_segments = 28
	_zone_mesh.rings = 14
	mesh_instance.mesh = _zone_mesh
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(0.45, 0.82, 0.95, 0.1)
	material.emission_enabled = true
	material.emission = Color(0.35, 0.7, 0.85)
	material.emission_energy_multiplier = 0.35
	mesh_instance.material_override = material
	add_child(mesh_instance)
