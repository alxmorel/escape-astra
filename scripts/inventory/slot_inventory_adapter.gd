extends RefCounted
class_name SlotInventoryAdapter

var slot_count: int = 0
var get_stack: Callable
var set_stack: Callable
var on_changed: Callable


func stack_at(index: int) -> Dictionary:
	if get_stack.is_valid():
		return get_stack.call(index)
	return {"id": "", "count": 0, "durability": -1, "max_durability": 0}


func write_stack(index: int, id: String, amount: int, durability: int = -1) -> void:
	if set_stack.is_valid():
		set_stack.call(index, id, amount, durability)
	if on_changed.is_valid():
		on_changed.call()


static func from_inventory(inventory: Node) -> SlotInventoryAdapter:
	var adapter := SlotInventoryAdapter.new()
	adapter.slot_count = int(inventory.slots.size())
	adapter.get_stack = func(index: int) -> Dictionary:
		return inventory.call(&"get_slot_stack", index)
	adapter.set_stack = func(index: int, id: String, amount: int, durability: int = -1) -> void:
		inventory.call(&"set_slot_stack", index, id, amount, durability)
	adapter.on_changed = Callable()
	return adapter


static func from_container(container) -> SlotInventoryAdapter:
	var adapter := SlotInventoryAdapter.new()
	adapter.slot_count = int(container.slots.size())
	adapter.get_stack = func(index: int) -> Dictionary:
		return container.call(&"get_slot_stack", index)
	adapter.set_stack = func(index: int, id: String, amount: int, durability: int = -1) -> void:
		container.call(&"set_slot_stack", index, id, amount, durability)
	adapter.on_changed = Callable()
	return adapter
