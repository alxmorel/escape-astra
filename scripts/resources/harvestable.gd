extends Node3D

const GROUND_ITEM_SCENE := preload("res://scenes/resources/ground_item.tscn")
const STYLIZED := preload("res://scripts/resources/stylized_material.gd")

@export var resource_id: String = "wood"
@export var required_tool: String = ""
@export var max_hits: int = 10
@export var hits_per_drop: int = 2
@export var drop_quantity: int = 1
@export var aim_height: float = 1.1
@export var chip_color: Color = Color(0.62, 0.4, 0.18)

var hits: int = 0
var cut_key := ""


func _ready() -> void:
	add_to_group(&"harvestable")


func _accepts_tool(tool_id: String) -> bool:
	if required_tool.is_empty():
		return true
	if required_tool == "pickaxe":
		return tool_id.ends_with("pickaxe")
	if required_tool == "axe":
		return tool_id.ends_with("_axe")
	if required_tool == "shovel":
		return tool_id.ends_with("shovel")
	return tool_id == required_tool


func aim_point() -> Vector3:
	return global_position + global_transform.basis.y.normalized() * aim_height


func receive_hit(tool_id: String = "", _hit_point: Variant = null) -> bool:
	if not _accepts_tool(tool_id):
		return false
	if not is_exposed():
		return false
	hits += 1
	_spawn_chips()
	if hits_per_drop > 0 and hits % hits_per_drop == 0:
		_spawn_drop()
	if hits >= max_hits:
		_register_cut()
		queue_free()
		return true
	var base_scale := scale
	var tween := create_tween()
	tween.tween_property(self, "scale", base_scale * Vector3(1.08, 0.88, 1.08), 0.05)
	tween.tween_property(self, "scale", base_scale, 0.09)
	return true


func is_exposed() -> bool:
	if not has_meta(&"skip_terrain_snap") or not bool(get_meta(&"skip_terrain_snap")):
		return true
	var planet := get_tree().get_first_node_in_group(&"planet")
	if planet == null or not planet.has_method(&"is_point_air"):
		return true
	return bool(planet.call(&"is_point_air", aim_point()))


func _register_cut() -> void:
	if cut_key.is_empty():
		return
	var planet := get_tree().get_first_node_in_group(&"planet")
	if planet == null:
		return
	if required_tool == "pickaxe" and planet.has_method(&"note_cut_rock"):
		planet.call(&"note_cut_rock", cut_key)
		return
	if planet.has_method(&"note_cut_tree"):
		planet.call(&"note_cut_tree", cut_key)


func _spawn_drop() -> void:
	var item := GROUND_ITEM_SCENE.instantiate()
	item.resource_id = resource_id
	item.quantity = drop_quantity
	get_tree().current_scene.add_child(item)
	var up := global_transform.basis.y.normalized()
	var side := global_transform.basis.x.normalized()
	if side.length_squared() < 0.001:
		side = up.cross(Vector3.FORWARD).normalized()
	item.global_position = global_position + up * 1.3 + side * randf_range(-0.35, 0.35)
	item.linear_velocity = side * randf_range(0.8, 1.6) + up * 1.4


func _spawn_chips() -> void:
	var origin := aim_point()
	var up := global_transform.basis.y.normalized()
	for _i in 4:
		var chip := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3.ONE * 0.08
		chip.mesh = box
		chip.material_override = STYLIZED.create(chip_color)
		get_tree().current_scene.add_child(chip)
		chip.global_position = origin
		var spray := (up * 0.4 + Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))).normalized()
		var tween := chip.create_tween()
		tween.tween_property(chip, "global_position", origin + spray * 0.55, 0.18)
		tween.parallel().tween_property(chip, "scale", Vector3.ZERO, 0.18)
		tween.tween_callback(chip.queue_free)
