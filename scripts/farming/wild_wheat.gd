extends Node3D

const FARM := preload("res://scripts/farming/farming_config.gd")
const DROPS := preload("res://scripts/farming/drops.gd")

const AIM_HEIGHT := 0.45
const BODY_RADIUS := 0.2
const BODY_HEIGHT := 0.72

var wheat_key := ""


func _ready() -> void:
	add_to_group(&"harvestable")
	var scene := FARM.scene_for("wheat_wild")
	if scene != null:
		var visual := scene.instantiate()
		visual.name = "Visual"
		add_child(visual)
	var body := StaticBody3D.new()
	body.collision_layer = 8
	body.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = BODY_RADIUS
	shape.height = BODY_HEIGHT
	shape_node.shape = shape
	shape_node.position = Vector3(0, BODY_HEIGHT * 0.5, 0)
	body.add_child(shape_node)
	add_child(body)


func aim_point() -> Vector3:
	return global_position + global_basis.y * AIM_HEIGHT


func receive_hit(_tool_id: String = "") -> bool:
	DROPS.spawn_list(global_position, global_basis.y, FARM.wild_drops(), self)
	var farming := get_tree().get_first_node_in_group(&"farming")
	if farming != null and farming.has_method(&"note_wild"):
		farming.call(&"note_wild", wheat_key)
	queue_free()
	return true
