extends RefCounted
class_name SlotBag

const Capacities := preload("res://scripts/inventory/capacities.gd")
const ToolDurability := preload("res://scripts/items/tool_durability.gd")

var amounts: Dictionary = {}
var slots := PackedStringArray()
var slot_counts := PackedInt32Array()
## -1 = non-outil ; sinon durabilité actuelle.
var slot_durability := PackedInt32Array()


func setup(count: int) -> void:
	slots.resize(maxi(count, 0))
	slot_counts.resize(slots.size())
	slot_durability.resize(slots.size())
	for i in slot_durability.size():
		slot_durability[i] = -1


func size() -> int:
	return slots.size()


func get_slot_stack(index: int) -> Dictionary:
	if index < 0 or index >= slots.size():
		return {"id": "", "count": 0, "durability": -1, "max_durability": 0}
	var id := str(slots[index])
	if id.is_empty():
		return {"id": "", "count": 0, "durability": -1, "max_durability": 0}
	var max_d := ToolDurability.max_of(id)
	var dur := int(slot_durability[index]) if index < slot_durability.size() else -1
	if max_d > 0 and dur < 0:
		dur = max_d
	return {
		"id": id,
		"count": int(slot_counts[index]),
		"durability": dur,
		"max_durability": max_d,
	}


func set_slot_stack(index: int, resource_id: String, qty: int, durability: int = -1) -> void:
	if index < 0 or index >= slots.size():
		return
	_ensure_durability_size()
	if qty <= 0 or resource_id.is_empty():
		slots[index] = ""
		slot_counts[index] = 0
		slot_durability[index] = -1
	else:
		var prev_id := str(slots[index])
		slots[index] = resource_id
		slot_counts[index] = mini(qty, Capacities.stack_limit(resource_id))
		slot_durability[index] = _resolve_durability(resource_id, durability, prev_id, index)
	rebuild_amounts()


func _resolve_durability(resource_id: String, durability: int, prev_id: String, index: int) -> int:
	var max_d := ToolDurability.max_of(resource_id)
	if max_d <= 0:
		return -1
	if durability >= 0:
		return mini(durability, max_d)
	if prev_id == resource_id and int(slot_durability[index]) >= 0:
		return mini(int(slot_durability[index]), max_d)
	return max_d


func _ensure_durability_size() -> void:
	if slot_durability.size() == slots.size():
		return
	var old := slot_durability.size()
	slot_durability.resize(slots.size())
	for i in range(old, slot_durability.size()):
		slot_durability[i] = -1


func amount_of(resource_id: String) -> int:
	return int(amounts.get(resource_id, 0))


func fits(resource_id: String) -> bool:
	if resource_id.is_empty():
		return false
	var limit := Capacities.stack_limit(resource_id)
	for i in slots.size():
		var id := str(slots[i])
		if id.is_empty():
			return true
		if id == resource_id and int(slot_counts[i]) < limit:
			return true
	return false


func free_space_for(resource_id: String) -> int:
	var limit := Capacities.stack_limit(resource_id)
	var room := 0
	for i in slots.size():
		var id := str(slots[i])
		if id.is_empty():
			room += limit
		elif id == resource_id:
			room += maxi(0, limit - int(slot_counts[i]))
	return room


func add_items(resource_id: String, qty: int, durability: int = -1) -> int:
	if resource_id.is_empty() or qty <= 0:
		return qty
	var left := fill_existing_in_range(resource_id, qty, 0, slots.size(), durability)
	return fill_empty_in_range(resource_id, left, 0, slots.size(), durability)


func add_items_prefer_ranges(resource_id: String, qty: int, ranges: Array, durability: int = -1) -> int:
	if resource_id.is_empty() or qty <= 0:
		return qty
	var left := qty
	for raw in ranges:
		left = fill_existing_in_range(resource_id, left, int(raw[0]), int(raw[1]), durability)
		if left <= 0:
			return 0
	for raw in ranges:
		left = fill_empty_in_range(resource_id, left, int(raw[0]), int(raw[1]), durability)
		if left <= 0:
			return 0
	return left


func fill_existing_in_range(resource_id: String, qty: int, start: int, end: int, durability: int = -1) -> int:
	var left := qty
	for i in range(start, end):
		if str(slots[i]) != resource_id:
			continue
		left = add_to_slot_index(i, resource_id, left, durability)
		if left <= 0:
			break
	return left


func fill_empty_in_range(resource_id: String, qty: int, start: int, end: int, durability: int = -1) -> int:
	var left := qty
	for i in range(start, end):
		if not str(slots[i]).is_empty():
			continue
		left = add_to_slot_index(i, resource_id, left, durability)
		if left <= 0:
			break
	return left


func add_to_slot_index(index: int, resource_id: String, qty: int, durability: int = -1) -> int:
	if qty <= 0:
		return 0
	_ensure_durability_size()
	var limit := Capacities.stack_limit(resource_id)
	var id := str(slots[index])
	if id.is_empty():
		var moved := mini(qty, limit)
		slots[index] = resource_id
		slot_counts[index] = moved
		slot_durability[index] = _resolve_durability(resource_id, durability, "", index)
		return qty - moved
	if id != resource_id:
		return qty
	var room := limit - int(slot_counts[index])
	if room <= 0:
		return qty
	var merged := mini(room, qty)
	slot_counts[index] += merged
	return qty - merged


func remove_from_slots(resource_id: String, qty: int, prefer_index: int = -1) -> int:
	var left := qty
	if prefer_index >= 0 and prefer_index < slots.size() and str(slots[prefer_index]) == resource_id:
		left = remove_from_slot_index(prefer_index, left)
	if left <= 0:
		return 0
	for i in slots.size():
		if i == prefer_index:
			continue
		if str(slots[i]) != resource_id:
			continue
		left = remove_from_slot_index(i, left)
		if left <= 0:
			break
	return left


func remove_from_slot_index(index: int, qty: int) -> int:
	_ensure_durability_size()
	var have := int(slot_counts[index])
	if have <= 0:
		return qty
	var moved := mini(have, qty)
	var remain := have - moved
	if remain <= 0:
		slots[index] = ""
		slot_counts[index] = 0
		slot_durability[index] = -1
	else:
		slot_counts[index] = remain
	return qty - moved


func move_slot(from_index: int, to_index: int) -> void:
	if from_index == to_index:
		return
	if from_index < 0 or to_index < 0 or from_index >= slots.size() or to_index >= slots.size():
		return
	_ensure_durability_size()
	var from := get_slot_stack(from_index)
	if from["id"].is_empty():
		return
	var to := get_slot_stack(to_index)
	var from_dur := int(from.get("durability", -1))
	var to_dur := int(to.get("durability", -1))
	if to["id"].is_empty():
		var id := str(from["id"])
		var moved := mini(int(from["count"]), Capacities.stack_limit(id))
		set_slot_stack(to_index, id, moved, from_dur)
		var remain := int(from["count"]) - moved
		if remain <= 0:
			set_slot_stack(from_index, "", 0)
		else:
			slots[from_index] = id
			slot_counts[from_index] = remain
			slot_durability[from_index] = from_dur
			rebuild_amounts()
		return
	if str(to["id"]) == str(from["id"]):
		var room := Capacities.stack_limit(str(to["id"])) - int(to["count"])
		var moved := mini(maxi(room, 0), int(from["count"]))
		if moved > 0:
			# Outils stack 1 : pas de merge de durabilités différentes.
			set_slot_stack(to_index, str(to["id"]), int(to["count"]) + moved, to_dur)
			var remain := int(from["count"]) - moved
			if remain <= 0:
				set_slot_stack(from_index, "", 0)
			else:
				set_slot_stack(from_index, str(from["id"]), remain, from_dur)
		return
	set_slot_stack(from_index, str(to["id"]), int(to["count"]), to_dur)
	set_slot_stack(to_index, str(from["id"]), int(from["count"]), from_dur)


func move_stack_amount(from_index: int, to_index: int, qty: int) -> void:
	var from := get_slot_stack(from_index)
	if from["id"].is_empty() or qty <= 0:
		return
	var to := get_slot_stack(to_index)
	var id := str(from["id"])
	var from_dur := int(from.get("durability", -1))
	var moved := qty
	if not to["id"].is_empty() and str(to["id"]) != id:
		return
	var limit := Capacities.stack_limit(id)
	if to["id"].is_empty():
		moved = mini(qty, limit)
		set_slot_stack(to_index, id, moved, from_dur)
	else:
		var room := limit - int(to["count"])
		moved = mini(mini(qty, maxi(room, 0)), int(from["count"]))
		if moved <= 0:
			return
		set_slot_stack(to_index, id, int(to["count"]) + moved, int(to.get("durability", -1)))
	var remain := int(from["count"]) - moved
	if remain <= 0:
		set_slot_stack(from_index, "", 0)
	else:
		set_slot_stack(from_index, id, remain, from_dur)


func first_stack_slot(resource_id: String, start: int, end: int, merge_only: bool) -> int:
	var limit := Capacities.stack_limit(resource_id)
	for i in range(start, end):
		if str(slots[i]) == resource_id and int(slot_counts[i]) < limit:
			return i
	if merge_only:
		return -1
	for i in range(start, end):
		if str(slots[i]).is_empty():
			return i
	return -1


func clear() -> void:
	amounts.clear()
	_ensure_durability_size()
	for i in slots.size():
		slots[i] = ""
		slot_counts[i] = 0
		slot_durability[i] = -1


func rebuild_amounts() -> void:
	amounts.clear()
	for i in slots.size():
		var id := str(slots[i])
		if id.is_empty():
			continue
		amounts[id] = int(amounts.get(id, 0)) + int(slot_counts[i])


func normalize_oversized_stacks() -> void:
	_ensure_durability_size()
	var overflow: Array = []
	for i in slots.size():
		var id := str(slots[i])
		if id.is_empty():
			continue
		var limit := Capacities.stack_limit(id)
		var count := int(slot_counts[i])
		if count <= limit:
			continue
		overflow.append({"id": id, "qty": count - limit, "durability": int(slot_durability[i])})
		slot_counts[i] = limit
	for entry in overflow:
		var left := add_items(str(entry["id"]), int(entry["qty"]), int(entry.get("durability", -1)))
		if left <= 0:
			continue
		var placed := false
		for i in slots.size():
			if str(slots[i]) != str(entry["id"]):
				continue
			slot_counts[i] += left
			placed = true
			break
		if not placed:
			for i in slots.size():
				if not str(slots[i]).is_empty():
					continue
				slots[i] = str(entry["id"])
				slot_counts[i] = left
				slot_durability[i] = _resolve_durability(str(entry["id"]), int(entry.get("durability", -1)), "", i)
				break


func wear_at(index: int, amount: int = 1) -> bool:
	## Usure ; true si l'outil casse (slot vidé).
	if index < 0 or index >= slots.size() or amount <= 0:
		return false
	_ensure_durability_size()
	var id := str(slots[index])
	var max_d := ToolDurability.max_of(id)
	if max_d <= 0:
		return false
	var dur := int(slot_durability[index])
	if dur < 0:
		dur = max_d
	dur = maxi(dur - amount, 0)
	if dur <= 0:
		set_slot_stack(index, "", 0)
		return true
	slot_durability[index] = dur
	return false


func export_slots() -> Dictionary:
	_ensure_durability_size()
	var slot_list: Array = []
	var count_list: Array = []
	var dur_list: Array = []
	for i in slots.size():
		slot_list.append(str(slots[i]))
		count_list.append(int(slot_counts[i]))
		dur_list.append(int(slot_durability[i]))
	return {
		"amounts": amounts.duplicate(),
		"slots": slot_list,
		"slot_counts": count_list,
		"slot_durability": dur_list,
	}


func import_slots(data: Dictionary, allow_overflow_beyond: bool = false) -> Array:
	amounts.clear()
	_ensure_durability_size()
	var incoming_amounts: Dictionary = data.get("amounts", {})
	for key in incoming_amounts:
		amounts[str(key)] = int(incoming_amounts[key])
	var incoming: Array = data.get("slots", [])
	var incoming_counts: Array = data.get("slot_counts", [])
	var incoming_durs: Array = data.get("slot_durability", [])
	for i in slots.size():
		slots[i] = str(incoming[i]) if i < incoming.size() else ""
		if i < incoming_counts.size():
			slot_counts[i] = int(incoming_counts[i])
		elif not slots[i].is_empty():
			slot_counts[i] = int(amounts.get(slots[i], 0))
		else:
			slot_counts[i] = 0
		if i < incoming_durs.size():
			slot_durability[i] = int(incoming_durs[i])
		elif ToolDurability.max_of(str(slots[i])) > 0:
			slot_durability[i] = ToolDurability.max_of(str(slots[i]))
		else:
			slot_durability[i] = -1
	normalize_oversized_stacks()
	var leftovers: Array = []
	if allow_overflow_beyond:
		for i in range(slots.size(), incoming.size()):
			var id := str(incoming[i])
			if id.is_empty() or i >= incoming_counts.size():
				continue
			var qty := int(incoming_counts[i])
			if qty <= 0:
				continue
			var dur := int(incoming_durs[i]) if i < incoming_durs.size() else -1
			var left := add_items(id, qty, dur)
			if left > 0:
				leftovers.append({"id": id, "qty": left})
	rebuild_amounts()
	return leftovers
