extends Node3D

const MODEL := preload("res://assets/models/Four.glb")
const STYLIZED := preload("res://scripts/resources/stylized_material.gd")
const ItemContainer := preload("res://scripts/storage/item_container.gd")
const Capacities := preload("res://scripts/inventory/capacities.gd")

## Indices storage : 0 input, 1 fuel, 2 result (voir furnace_panel.SLOT_*).
const SLOT_INPUT := 0
const SLOT_FUEL := 1
const SLOT_RESULT := 2
const SLOT_COUNT := 3

const SMELT_RECIPES := {
	"wood": {"result_id": "charcoal", "result_amount": 1},
}

## Énergie d’un item fuel (unité = 1 bûche).
## Charbon de bois = 4× bûche ; charbon miné = 8× bûche (= 2× charbon de bois).
const FUEL_ENERGY := {
	"wood": 1.0,
	"charcoal": 4.0,
	"coal": 8.0,
}
## Coût d’une cuisson charbon = 50 % d’une bûche.
const COOK_FUEL_COST := 0.5

@export var interact_radius: float = 2.8
## Durée d’une cuisson (s) — recette charbon = 10 s.
@export var cook_seconds: float = 10.0

var storage = null
var cook_progress: float = 0.0
## Reliquat de la bûche / fuel en cours (pas de demi-stack dans SlotBag).
var fuel_partial: float = 0.0


func _ready() -> void:
	add_to_group(&"machine")
	if storage == null:
		storage = ItemContainer.new()
		storage.setup(SLOT_COUNT)
	if get_node_or_null(^"Model") == null:
		add_visual(self, 1.0)
	_ensure_collision()


func _process(delta: float) -> void:
	cook_tick(delta)


func open_ui() -> void:
	var hud := get_tree().get_first_node_in_group(&"hud")
	if hud != null and hud.has_method(&"open_furnace"):
		hud.call(&"open_furnace", self)


func get_cook_progress() -> float:
	return cook_progress


func can_accept_input(resource_id: String) -> bool:
	return SMELT_RECIPES.has(resource_id)


func can_accept_fuel(resource_id: String) -> bool:
	return FUEL_ENERGY.has(resource_id)


func can_accept_result(resource_id: String) -> bool:
	var stack: Dictionary = storage.get_slot_stack(SLOT_RESULT) if storage != null else {"id": "", "count": 0}
	var current := str(stack.get("id", ""))
	return current.is_empty() or current == resource_id


func cook_tick(delta: float) -> void:
	if storage == null or delta <= 0.0:
		return
	_sync_fuel_partial()
	if not _can_cook():
		cook_progress = 0.0
		return
	var need := maxf(cook_seconds, 0.05)
	cook_progress = minf(cook_progress + delta / need, 1.0)
	if cook_progress < 1.0:
		return
	if not _try_complete_cook():
		cook_progress = 0.0
		return
	cook_progress = 0.0


func export_state() -> Dictionary:
	var slots: Dictionary = {}
	if storage != null:
		slots = storage.export_state()
	return {
		"slots": slots,
		"cook_progress": cook_progress,
		"fuel_partial": fuel_partial,
	}


func import_state(data: Dictionary) -> void:
	if storage == null:
		storage = ItemContainer.new()
		storage.setup(SLOT_COUNT)
	var slots: Variant = data.get("slots", {})
	if slots is Dictionary and not (slots as Dictionary).is_empty():
		storage.import_state(slots)
	cook_progress = float(data.get("cook_progress", 0.0))
	fuel_partial = float(data.get("fuel_partial", data.get("fuel_left", 0.0)))
	# Ancien save : fuel_left était en secondes ; on ignore la conversion (reset soft).
	if data.has("fuel_left") and not data.has("fuel_partial"):
		fuel_partial = 0.0
	_sync_fuel_partial()


func _can_cook() -> bool:
	var recipe := _active_recipe()
	if recipe.is_empty():
		return false
	if not _can_output(recipe):
		return false
	return _has_fuel_for_cook()


func _active_recipe() -> Dictionary:
	var input: Dictionary = storage.get_slot_stack(SLOT_INPUT)
	var id := str(input.get("id", ""))
	if id.is_empty() or int(input.get("count", 0)) <= 0:
		return {}
	if not SMELT_RECIPES.has(id):
		return {}
	var recipe: Dictionary = SMELT_RECIPES[id]
	return {
		"input_id": id,
		"result_id": str(recipe["result_id"]),
		"result_amount": int(recipe.get("result_amount", 1)),
	}


func _can_output(recipe: Dictionary) -> bool:
	var result_id := str(recipe["result_id"])
	var amount := int(recipe["result_amount"])
	var slot: Dictionary = storage.get_slot_stack(SLOT_RESULT)
	var current_id := str(slot.get("id", ""))
	var current_count := int(slot.get("count", 0))
	if current_id.is_empty():
		return amount <= Capacities.stack_limit(result_id)
	if current_id != result_id:
		return false
	return current_count + amount <= Capacities.stack_limit(result_id)


func _fuel_item_fraction(fuel_id: String) -> float:
	var energy := float(FUEL_ENERGY.get(fuel_id, 0.0))
	if energy <= 0.0:
		return 1.0
	# Portion d’un item retirée par cuisson (ex. bois 0.5/1 = 50 %).
	return COOK_FUEL_COST / energy


func _has_fuel_for_cook() -> bool:
	var fuel: Dictionary = storage.get_slot_stack(SLOT_FUEL)
	var id := str(fuel.get("id", ""))
	var count := int(fuel.get("count", 0))
	# L’item reste dans le slot tant que fuel_partial < 1 (pas de demi-stack).
	return count >= 1 and FUEL_ENERGY.has(id)


func _sync_fuel_partial() -> void:
	var fuel: Dictionary = storage.get_slot_stack(SLOT_FUEL)
	var id := str(fuel.get("id", ""))
	var count := int(fuel.get("count", 0))
	if count <= 0 or not FUEL_ENERGY.has(id):
		fuel_partial = 0.0


func _try_complete_cook() -> bool:
	var recipe := _active_recipe()
	if recipe.is_empty() or not _can_output(recipe) or not _has_fuel_for_cook():
		return false
	var fuel: Dictionary = storage.get_slot_stack(SLOT_FUEL)
	var fuel_id := str(fuel.get("id", ""))
	var fuel_count := int(fuel.get("count", 0))
	var fraction := _fuel_item_fraction(fuel_id)
	var input: Dictionary = storage.get_slot_stack(SLOT_INPUT)
	var input_id := str(input.get("id", ""))
	var input_count := int(input.get("count", 0))
	if input_id != str(recipe["input_id"]) or input_count <= 0:
		return false
	# Consommation uniquement à la réussite (après vérif résultat).
	storage.set_slot_stack(SLOT_INPUT, input_id, input_count - 1)
	fuel_partial += fraction
	while fuel_partial >= 1.0 - 0.0001 and fuel_count > 0:
		fuel_count -= 1
		fuel_partial = maxf(fuel_partial - 1.0, 0.0)
	if fuel_count <= 0:
		storage.set_slot_stack(SLOT_FUEL, "", 0)
		fuel_partial = 0.0
	else:
		storage.set_slot_stack(SLOT_FUEL, fuel_id, fuel_count)
	var result_id := str(recipe["result_id"])
	var add := int(recipe["result_amount"])
	var slot: Dictionary = storage.get_slot_stack(SLOT_RESULT)
	var current_id := str(slot.get("id", ""))
	var current_count := int(slot.get("count", 0))
	if current_id.is_empty():
		storage.set_slot_stack(SLOT_RESULT, result_id, add)
	else:
		storage.set_slot_stack(SLOT_RESULT, result_id, current_count + add)
	return true


static func add_visual(parent: Node3D, alpha: float, _item_id: String = "") -> Array:
	var materials: Array = []
	var visual := MODEL.instantiate() as Node3D
	if visual == null:
		return materials
	visual.name = "Model"
	parent.add_child(visual)
	if alpha < 0.99:
		_make_ghost(visual, alpha, materials)
	return materials


static func _make_ghost(root: Node, alpha: float, materials: Array) -> void:
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		var color := _mesh_color(mesh_instance)
		var material := STYLIZED.create(color, alpha)
		mesh_instance.material_override = material
		materials.append(material)
		var mesh := mesh_instance.mesh
		if mesh != null:
			for i in mesh.get_surface_count():
				mesh_instance.set_surface_override_material(i, null)
	for child in root.get_children():
		_make_ghost(child, alpha, materials)


static func _mesh_color(mesh_instance: MeshInstance3D) -> Color:
	var color := _albedo_from(mesh_instance.material_override)
	if color != Color(-1, -1, -1, -1):
		return color
	var mesh := mesh_instance.mesh
	if mesh == null:
		return Color(0.5, 0.48, 0.44)
	for i in mesh.get_surface_count():
		color = _albedo_from(mesh_instance.get_active_material(i))
		if color != Color(-1, -1, -1, -1):
			return color
	return Color(0.5, 0.48, 0.44)


static func _albedo_from(material: Material) -> Color:
	if material is StandardMaterial3D:
		return (material as StandardMaterial3D).albedo_color
	if material is ShaderMaterial:
		var value: Variant = (material as ShaderMaterial).get_shader_parameter(&"albedo")
		if value is Color:
			return value as Color
	return Color(-1, -1, -1, -1)


func _ensure_collision() -> void:
	if get_node_or_null(^"Body") != null:
		return
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 8
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.1, 1.2, 1.1)
	shape.shape = box
	shape.position = Vector3(0.0, 0.6, 0.0)
	body.add_child(shape)
	add_child(body)
