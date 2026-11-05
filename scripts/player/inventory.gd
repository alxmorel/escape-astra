extends Node

signal changed
signal slot_selected(index: int)

const Capacities := preload("res://scripts/inventory/capacities.gd")
const SlotBag := preload("res://scripts/inventory/slot_bag.gd")
const ToolDurability := preload("res://scripts/items/tool_durability.gd")
const SLOT_COUNT := Capacities.HOTBAR
const BACKPACK_SIZE := Capacities.BACKPACK

var _bag: SlotBag = SlotBag.new()
var selected_index: int = 0

var slots: PackedStringArray:
	get:
		return _bag.slots

var slot_counts: PackedInt32Array:
	get:
		return _bag.slot_counts

var amounts: Dictionary:
	get:
		return _bag.amounts


func _ready() -> void:
	_bag.setup(SLOT_COUNT + BACKPACK_SIZE)


func get_slot_stack(index: int) -> Dictionary:
	return _bag.get_slot_stack(index)


func set_slot_stack(index: int, resource_id: String, qty: int, durability: int = -1) -> void:
	_bag.set_slot_stack(index, resource_id, qty, durability)
	changed.emit()


func add_resource(resource_id: String, qty: int, durability: int = -1) -> int:
	if qty == 0 or resource_id.is_empty():
		return 0
	if qty < 0:
		_remove_resource(resource_id, -qty)
		return 0
	var left := _add_items(resource_id, qty, durability)
	if left != qty:
		_bag.rebuild_amounts()
		changed.emit()
	return left


func get_amount(resource_id: String) -> int:
	return _bag.amount_of(resource_id)


func fits(resource_id: String) -> bool:
	return _bag.fits(resource_id)


func get_selected_id() -> String:
	return str(_bag.slots[selected_index])


func get_selected_durability() -> int:
	var stack := get_slot_stack(selected_index)
	return int(stack.get("durability", -1))


func can_use_selected_tool() -> bool:
	var id := get_selected_id()
	if not ToolDurability.has_durability(id):
		return true
	return get_selected_durability() > 0


func wear_selected_tool(amount: int = ToolDurability.WEAR_PER_USE) -> bool:
	## true si l'outil vient de casser.
	if not ToolDurability.has_durability(get_selected_id()):
		return false
	var broke := _bag.wear_at(selected_index, amount)
	_bag.rebuild_amounts()
	changed.emit()
	return broke


func select_slot(index: int) -> void:
	selected_index = clampi(index, 0, SLOT_COUNT - 1)
	slot_selected.emit(selected_index)
	changed.emit()


func cycle_slot(direction: int) -> void:
	var next := (selected_index + direction) % SLOT_COUNT
	if next < 0:
		next += SLOT_COUNT
	select_slot(next)


func can_craft(recipe: Dictionary) -> bool:
	var ingredients: Dictionary = recipe["ingredients"]
	for resource_id in ingredients:
		if get_amount(str(resource_id)) < int(ingredients[resource_id]):
			return false
	return true


func try_consume(ingredients: Dictionary) -> bool:
	if ingredients.is_empty():
		return false
	var recipe := {"ingredients": ingredients}
	if not can_craft(recipe):
		return false
	_consume_ingredients(recipe)
	return true


func try_craft(recipe: Dictionary) -> bool:
	if not can_craft(recipe):
		return false
	_consume_ingredients(recipe)
	add_resource(str(recipe["result_id"]), int(recipe["result_amount"]))
	return true


func try_craft_once(recipe: Dictionary) -> Dictionary:
	if not can_craft(recipe):
		return {"id": "", "count": 0, "durability": -1}
	_consume_ingredients(recipe)
	var result_id := str(recipe["result_id"])
	var dur := ToolDurability.max_of(result_id) if ToolDurability.has_durability(result_id) else -1
	return {"id": result_id, "count": int(recipe["result_amount"]), "durability": dur}


func max_craft_times(recipe: Dictionary) -> int:
	var ingredients: Dictionary = recipe["ingredients"]
	var limit := 999999
	for resource_id in ingredients:
		var need := int(ingredients[resource_id])
		if need <= 0:
			continue
		limit = mini(limit, get_amount(str(resource_id)) / need)
	return maxi(limit, 0)


func craft_max_into_slots(recipe: Dictionary) -> int:
	var result_id := str(recipe["result_id"])
	var per := maxi(int(recipe.get("result_amount", 1)), 1)
	var crafted := 0
	while can_craft(recipe):
		if _bag.free_space_for(result_id) < per:
			break
		_consume_ingredients(recipe)
		var left := _add_items(result_id, per)
		if left > 0:
			var placed := per - left
			if placed > 0:
				_bag.remove_from_slots(result_id, placed, -1)
			_refund_ingredients(recipe)
			break
		crafted += 1
	if crafted > 0:
		_bag.rebuild_amounts()
		changed.emit()
	return crafted


func can_hold_new_result(result_id: String) -> bool:
	return fits(result_id)


func place_in_slot(resource_id: String, index: int) -> void:
	if resource_id.is_empty():
		return
	var qty := get_amount(resource_id)
	if qty <= 0:
		return
	if index < 0 or index >= _bag.size():
		return
	var occupant := str(_bag.slots[index])
	if not occupant.is_empty() and occupant != resource_id:
		return
	var slot_qty := int(_bag.slot_counts[index]) if occupant == resource_id else 0
	var moved := mini(qty, Capacities.stack_limit(resource_id) - slot_qty)
	if moved <= 0:
		return
	_bag.remove_from_slots(resource_id, moved, index)
	set_slot_stack(index, resource_id, slot_qty + moved)


func quick_move_to_backpack(from_index: int) -> bool:
	if from_index < 0 or from_index >= SLOT_COUNT:
		return false
	var stack := get_slot_stack(from_index)
	if stack["id"].is_empty():
		return false
	var target := _bag.first_stack_slot(str(stack["id"]), SLOT_COUNT, _bag.size(), false)
	if target < 0:
		return false
	_bag.move_stack_amount(from_index, target, int(stack["count"]))
	changed.emit()
	return true


func quick_move_to_hotbar(from_index: int) -> bool:
	if from_index < SLOT_COUNT or from_index >= _bag.size():
		return false
	var stack := get_slot_stack(from_index)
	if stack["id"].is_empty():
		return false
	var target := _bag.first_stack_slot(str(stack["id"]), 0, SLOT_COUNT, false)
	if target < 0:
		return false
	_bag.move_stack_amount(from_index, target, int(stack["count"]))
	changed.emit()
	return true


func move_slot(from_index: int, to_index: int) -> void:
	_bag.move_slot(from_index, to_index)
	changed.emit()


func export_state() -> Dictionary:
	var data := _bag.export_slots()
	data["selected"] = selected_index
	return data


func import_state(data: Dictionary) -> void:
	var incoming_counts: Array = data.get("slot_counts", [])
	if incoming_counts.is_empty() and not data.has("slot_durability"):
		var incoming: Array = data.get("slots", [])
		var incoming_amounts: Dictionary = data.get("amounts", {})
		_bag.amounts.clear()
		for key in incoming_amounts:
			_bag.amounts[str(key)] = int(incoming_amounts[key])
		for i in _bag.size():
			_bag.slots[i] = str(incoming[i]) if i < incoming.size() else ""
			_bag.slot_counts[i] = 0
			if i < _bag.slot_durability.size():
				_bag.slot_durability[i] = -1
		_migrate_legacy_single_slot_amounts(data)
	else:
		_bag.import_slots(data, false)
	selected_index = clampi(int(data.get("selected", 0)), 0, SLOT_COUNT - 1)
	slot_selected.emit(selected_index)
	changed.emit()


func stash_cursor_stack(resource_id: String, qty: int, durability: int = -1) -> int:
	if resource_id.is_empty() or qty <= 0:
		return qty
	var left := _add_items(resource_id, qty, durability)
	if left != qty:
		_bag.rebuild_amounts()
		changed.emit()
	return left


func _consume_ingredients(recipe: Dictionary) -> void:
	var ingredients: Dictionary = recipe["ingredients"]
	for resource_id in ingredients:
		_remove_resource(str(resource_id), int(ingredients[resource_id]))


func _refund_ingredients(recipe: Dictionary) -> void:
	var ingredients: Dictionary = recipe["ingredients"]
	for resource_id in ingredients:
		_add_items(str(resource_id), int(ingredients[resource_id]))


func _remove_resource(resource_id: String, qty: int) -> void:
	var left := _bag.remove_from_slots(resource_id, qty, selected_index)
	if left != qty:
		_bag.rebuild_amounts()
		changed.emit()


func _add_items(resource_id: String, qty: int, durability: int = -1) -> int:
	return _bag.add_items_prefer_ranges(
		resource_id,
		qty,
		[[0, SLOT_COUNT], [SLOT_COUNT, _bag.size()]],
		durability
	)


func _migrate_legacy_single_slot_amounts(data: Dictionary) -> void:
	var incoming_amounts: Dictionary = data.get("amounts", {})
	var used: Dictionary = {}
	_bag._ensure_durability_size()
	for i in _bag.size():
		var id := str(_bag.slots[i])
		if id.is_empty():
			_bag.slot_counts[i] = 0
			_bag.slot_durability[i] = -1
			continue
		if used.has(id):
			_bag.slots[i] = ""
			_bag.slot_counts[i] = 0
			_bag.slot_durability[i] = -1
			continue
		_bag.slot_counts[i] = int(incoming_amounts.get(id, int(_bag.slot_counts[i])))
		_bag.slot_durability[i] = ToolDurability.max_of(id) if ToolDurability.has_durability(id) else -1
		used[id] = true
	_bag.normalize_oversized_stacks()
	_bag.rebuild_amounts()
