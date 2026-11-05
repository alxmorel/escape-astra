extends Node3D

const STYLIZED := preload("res://scripts/resources/stylized_material.gd")

@export var machine_name: String = "Primitive Drill"
@export var output_id: String = "stone"
@export var output_label: String = "Stone"
@export var capacity: int = 20
@export var seconds_per_item: float = 2.0
@export var interact_radius: float = 2.6

var stored: int = 0

var _elapsed: float = 0.0
var _label: Label3D


func _ready() -> void:
	add_to_group(&"machine")
	add_visual(self, 1.0)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, 1.65, 0)
	_label.font_size = 56
	_label.pixel_size = 0.004
	_label.outline_size = 8
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.modulate = Color(0.95, 0.95, 0.95)
	add_child(_label)
	_refresh_label()


func _process(delta: float) -> void:
	if stored >= capacity:
		return
	_elapsed += delta
	if _elapsed < seconds_per_item:
		return
	_elapsed -= seconds_per_item
	stored = mini(stored + 1, capacity)
	_refresh_label()


func export_state() -> Dictionary:
	return {"stored": stored, "elapsed": _elapsed}


func import_state(data: Dictionary) -> void:
	stored = int(data.get("stored", 0))
	_elapsed = float(data.get("elapsed", 0.0))
	if _label != null:
		_refresh_label()


func take_contents() -> int:
	var amount := stored
	stored = 0
	_elapsed = 0.0
	_refresh_label()
	return amount


func _refresh_label() -> void:
	_label.text = "%s\n%d / %d %s" % [machine_name, stored, capacity, output_label]


static func add_visual(parent: Node3D, alpha: float, _item_id: String = "") -> Array:
	var materials: Array = []
	_add_box(parent, Vector3(0, 0.18, 0), Vector3(0.9, 0.36, 0.9), Color(0.22, 0.24, 0.26), alpha, materials)
	_add_box(parent, Vector3(0, 0.62, 0), Vector3(0.42, 0.55, 0.42), Color(0.36, 0.38, 0.42), alpha, materials)
	_add_box(parent, Vector3(0, 0.98, 0), Vector3(0.22, 0.18, 0.22), Color(0.55, 0.58, 0.62), alpha, materials)
	_add_box(parent, Vector3(0, 0.1, 0.16), Vector3(0.12, 0.32, 0.12), Color(0.14, 0.14, 0.15), alpha, materials)
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
