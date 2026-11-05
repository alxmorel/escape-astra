extends "res://scripts/resources/harvestable.gd"

const MODEL := preload("res://assets/models/torch.glb")
const TorchLight := preload("res://scripts/items/torch_light.gd")
const TorchFire := preload("res://scripts/items/torch_fire.gd")


func _ready() -> void:
	resource_id = "torch"
	required_tool = ""
	max_hits = 1
	hits_per_drop = 1
	drop_quantity = 1
	aim_height = 0.22
	chip_color = Color(0.85, 0.55, 0.2)
	super._ready()
	add_to_group(&"machine")
	if get_node_or_null(^"Model") == null:
		_add_model()
	_ensure_light()
	TorchFire.apply(self)
	_ensure_collision()


func export_state() -> Dictionary:
	return {}


func import_state(_data: Dictionary) -> void:
	pass


static func add_visual(parent: Node3D, _alpha: float = 1.0, _item_id: String = "") -> Array:
	var visual := MODEL.instantiate() as Node3D
	if visual == null:
		return []
	visual.name = "Model"
	parent.add_child(visual)
	return []


func _add_model() -> void:
	add_visual(self)


func _ensure_light() -> void:
	var light := get_node_or_null(^"Light") as OmniLight3D
	if light == null:
		light = OmniLight3D.new()
		light.name = "Light"
		light.position = Vector3(0.0, 0.64, 0.0)
		add_child(light)
	TorchLight.apply(light)


func _ensure_collision() -> void:
	if get_node_or_null(^"Body") != null:
		return
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 8
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.14, 0.42, 0.14)
	shape.shape = box
	shape.position = Vector3(0.0, 0.21, 0.0)
	body.add_child(shape)
	add_child(body)
