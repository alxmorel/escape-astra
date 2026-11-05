extends RefCounted
class_name CursorStack

const Capacities := preload("res://scripts/inventory/capacities.gd")
const ToolDurability := preload("res://scripts/items/tool_durability.gd")

var resource_id := ""
var count := 0
var durability := -1


func is_empty() -> bool:
	return resource_id.is_empty() or count <= 0


func clear() -> void:
	resource_id = ""
	count = 0
	durability = -1


func space_left() -> int:
	if is_empty():
		return Capacities.MAX_STACK
	return maxi(0, Capacities.stack_limit(resource_id) - count)


func can_hold(id: String, qty: int = 1) -> bool:
	if id.is_empty() or qty <= 0:
		return false
	if is_empty():
		return qty <= Capacities.stack_limit(id)
	if resource_id != id:
		return false
	return count + qty <= Capacities.stack_limit(resource_id)


func add(id: String, qty: int, item_durability: int = -1) -> int:
	if id.is_empty() or qty <= 0:
		return qty
	if not is_empty() and resource_id != id:
		return qty
	if is_empty():
		resource_id = id
		if ToolDurability.has_durability(id):
			durability = item_durability if item_durability >= 0 else ToolDurability.max_of(id)
		else:
			durability = -1
	var room := space_left()
	var moved := mini(qty, room)
	count += moved
	if count <= 0:
		clear()
	return qty - moved


func take(qty: int) -> int:
	if is_empty() or qty <= 0:
		return 0
	var moved := mini(count, qty)
	count -= moved
	if count <= 0:
		clear()
	return moved


func peek() -> Dictionary:
	if is_empty():
		return {"id": "", "count": 0, "durability": -1}
	return {"id": resource_id, "count": count, "durability": durability}


func set_stack(id: String, qty: int, item_durability: int = -1) -> void:
	if id.is_empty() or qty <= 0:
		clear()
		return
	resource_id = id
	count = mini(qty, Capacities.stack_limit(id))
	if ToolDurability.has_durability(id):
		durability = item_durability if item_durability >= 0 else ToolDurability.max_of(id)
	else:
		durability = -1
