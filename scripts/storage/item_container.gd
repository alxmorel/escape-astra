extends RefCounted

const Capacities := preload("res://scripts/inventory/capacities.gd")
const SlotBag := preload("res://scripts/inventory/slot_bag.gd")

const SIMPLE_SLOTS := Capacities.CHEST
const DOUBLE_SLOTS := Capacities.DOUBLE_CHEST

signal changed

var _bag: SlotBag = SlotBag.new()

var slots: PackedStringArray:
	get:
		return _bag.slots

var slot_counts: PackedInt32Array:
	get:
		return _bag.slot_counts

var amounts: Dictionary:
	get:
		return _bag.amounts


static func capacity_for(wide: bool) -> int:
	return DOUBLE_SLOTS if wide else SIMPLE_SLOTS


func setup(count: int = SIMPLE_SLOTS) -> void:
	_bag.setup(maxi(count, 0))


func get_slot_stack(index: int) -> Dictionary:
	return _bag.get_slot_stack(index)


func set_slot_stack(index: int, resource_id: String, qty: int, durability: int = -1) -> void:
	_bag.set_slot_stack(index, resource_id, qty, durability)
	changed.emit()


func slot_id(index: int) -> String:
	if index < 0 or index >= _bag.size():
		return ""
	return str(_bag.slots[index])


func amount(resource_id: String) -> int:
	return _bag.amount_of(resource_id)


func stacks() -> Array:
	var out: Array = []
	for id in _bag.amounts.keys():
		out.append({"id": str(id), "qty": int(_bag.amounts[id])})
	return out


func put(resource_id: String, qty: int) -> int:
	if qty <= 0 or resource_id.is_empty():
		return qty
	var left := _bag.add_items(resource_id, qty)
	if left != qty:
		_bag.rebuild_amounts()
		changed.emit()
	return left


func take(resource_id: String, qty: int) -> int:
	var before := qty
	var left := _bag.remove_from_slots(resource_id, qty, -1)
	var taken := before - left
	if taken > 0:
		_bag.rebuild_amounts()
		changed.emit()
	return taken


func clear() -> void:
	_bag.clear()
	changed.emit()


func absorb(other) -> Array:
	var leftovers: Array = []
	if other == null:
		return leftovers
	for stack in other.stacks():
		var left := put(str(stack["id"]), int(stack["qty"]))
		if left > 0:
			leftovers.append({"id": str(stack["id"]), "qty": left})
	other.clear()
	return leftovers


func move_slot(from_index: int, to_index: int) -> void:
	_bag.move_slot(from_index, to_index)
	changed.emit()


func export_state() -> Dictionary:
	return _bag.export_slots()


func import_state(data: Dictionary) -> Array:
	var leftovers := _bag.import_slots(data, true)
	changed.emit()
	return leftovers
