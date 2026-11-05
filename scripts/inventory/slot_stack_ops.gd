extends RefCounted
class_name SlotStackOps

const CursorStack := preload("res://scripts/inventory/cursor_stack.gd")
const Capacities := preload("res://scripts/inventory/capacities.gd")


static func click(adapter: SlotInventoryAdapter, index: int, cursor: CursorStack, left_button: bool) -> void:
	if index < 0 or index >= adapter.slot_count:
		return
	var slot := adapter.stack_at(index)
	if left_button:
		_click_left(adapter, index, slot, cursor)
	else:
		_click_right(adapter, index, slot, cursor)


static func room_for(slot: Dictionary, id: String) -> int:
	return _room_for(slot, id)


static func deposit_one(adapter: SlotInventoryAdapter, index: int, cursor: CursorStack) -> void:
	if cursor.is_empty() or index < 0 or index >= adapter.slot_count:
		return
	var slot := adapter.stack_at(index)
	var id := str(cursor.resource_id)
	if not slot["id"].is_empty() and str(slot["id"]) != id:
		return
	var room := room_for(slot, id)
	if room <= 0:
		return
	var dur := int(cursor.durability)
	var moved := cursor.take(1)
	if moved <= 0:
		return
	var slot_id := id if slot["id"].is_empty() else str(slot["id"])
	var write_dur := dur if slot["id"].is_empty() else int(slot.get("durability", -1))
	adapter.write_stack(index, slot_id, int(slot["count"]) + moved, write_dur)


static func spread_evenly(adapter: SlotInventoryAdapter, indices: Array, cursor: CursorStack) -> void:
	if cursor.is_empty() or indices.is_empty():
		return
	var id := cursor.resource_id
	var dur := int(cursor.durability)
	var targets: Array[int] = []
	for raw in indices:
		var index := int(raw)
		if index < 0 or index >= adapter.slot_count:
			continue
		var slot := adapter.stack_at(index)
		if _room_for(slot, id) > 0:
			targets.append(index)
	if targets.is_empty():
		return
	var remaining := cursor.count
	var slots_left := targets.size()
	for index in targets:
		if remaining <= 0:
			break
		var slot := adapter.stack_at(index)
		var room := _room_for(slot, id)
		if room <= 0:
			slots_left = maxi(slots_left - 1, 1)
			continue
		var share := int(ceil(float(remaining) / float(slots_left)))
		var add := mini(mini(share, room), remaining)
		if add <= 0:
			continue
		var slot_id := id if slot["id"].is_empty() else str(slot["id"])
		var write_dur := dur if slot["id"].is_empty() else int(slot.get("durability", -1))
		adapter.write_stack(index, slot_id, int(slot["count"]) + add, write_dur)
		remaining -= add
		slots_left -= 1
	if remaining <= 0:
		cursor.clear()
	else:
		cursor.count = remaining


static func collect_matching_pairs(pairs: Array, cursor: CursorStack) -> void:
	if cursor.is_empty():
		return
	var id := cursor.resource_id
	var sources: Array = []
	for entry in pairs:
		var adapter: SlotInventoryAdapter = entry["adapter"]
		var index := int(entry["index"])
		if index < 0 or index >= adapter.slot_count:
			continue
		var slot := adapter.stack_at(index)
		if str(slot["id"]) != id:
			continue
		var amount := int(slot["count"])
		if amount <= 0:
			continue
		sources.append({"adapter": adapter, "index": index, "count": amount, "durability": int(slot.get("durability", -1))})
	sources.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["count"]) < int(b["count"])
	)
	for entry in sources:
		if cursor.space_left() <= 0:
			break
		var adapter: SlotInventoryAdapter = entry["adapter"]
		var index := int(entry["index"])
		var slot := adapter.stack_at(index)
		if str(slot["id"]) != id:
			continue
		var amount := int(slot["count"])
		if amount <= 0:
			continue
		var overflow := cursor.add(id, amount, int(slot.get("durability", -1)))
		var placed := amount - overflow
		if placed <= 0:
			break
		var remain := amount - placed
		if remain <= 0:
			adapter.write_stack(index, "", 0)
		else:
			adapter.write_stack(index, id, remain, int(slot.get("durability", -1)))


static func collect_matching(adapter: SlotInventoryAdapter, cursor: CursorStack, indices: Array) -> void:
	var pairs: Array = []
	for raw in indices:
		pairs.append({"adapter": adapter, "index": int(raw)})
	collect_matching_pairs(pairs, cursor)


static func transfer_stack(from_adapter: SlotInventoryAdapter, from_index: int, to_adapter: SlotInventoryAdapter) -> bool:
	if from_adapter == null or to_adapter == null:
		return false
	if from_index < 0 or from_index >= from_adapter.slot_count:
		return false
	var source := from_adapter.stack_at(from_index)
	var id := str(source["id"])
	var remaining := int(source["count"])
	var dur := int(source.get("durability", -1))
	if id.is_empty() or remaining <= 0:
		return false
	var start := remaining
	remaining = _deposit_into(to_adapter, id, remaining, true, dur)
	if remaining > 0:
		remaining = _deposit_into(to_adapter, id, remaining, false, dur)
	if remaining >= start:
		return false
	if remaining <= 0:
		from_adapter.write_stack(from_index, "", 0)
	else:
		from_adapter.write_stack(from_index, id, remaining, dur)
	return true


static func _deposit_into(adapter: SlotInventoryAdapter, id: String, qty: int, merge_only: bool, durability: int = -1) -> int:
	var left := qty
	if left <= 0:
		return 0
	for index in adapter.slot_count:
		if left <= 0:
			break
		var slot := adapter.stack_at(index)
		var slot_id := str(slot["id"])
		if merge_only:
			if slot_id != id:
				continue
		elif not slot_id.is_empty():
			continue
		var room := _room_for(slot, id)
		if room <= 0:
			continue
		var moved := mini(left, room)
		var new_count := moved if slot_id.is_empty() else int(slot["count"]) + moved
		var write_dur := durability if slot_id.is_empty() else int(slot.get("durability", -1))
		adapter.write_stack(index, id, new_count, write_dur)
		left -= moved
	return left


static func right_drag_from_source(adapter: SlotInventoryAdapter, origin: int, indices: Array) -> void:
	if origin < 0 or origin >= adapter.slot_count:
		return
	var source := adapter.stack_at(origin)
	var id := str(source["id"])
	var dur := int(source.get("durability", -1))
	if id.is_empty():
		return
	for raw in indices:
		var index := int(raw)
		if index == origin:
			continue
		source = adapter.stack_at(origin)
		if str(source["id"]).is_empty() or int(source["count"]) <= 0:
			break
		dur = int(source.get("durability", -1))
		var slot := adapter.stack_at(index)
		if not slot["id"].is_empty() and str(slot["id"]) != id:
			continue
		var room := _room_for(slot, id)
		if room <= 0:
			continue
		var origin_count := int(source["count"])
		if slot["id"].is_empty():
			adapter.write_stack(index, id, 1, dur)
		else:
			adapter.write_stack(index, id, int(slot["count"]) + 1, int(slot.get("durability", -1)))
		var remain := origin_count - 1
		if remain <= 0:
			adapter.write_stack(origin, "", 0)
		else:
			adapter.write_stack(origin, id, remain, dur)


static func _click_left(adapter: SlotInventoryAdapter, index: int, slot: Dictionary, cursor: CursorStack) -> void:
	var slot_id := str(slot["id"])
	var slot_count := int(slot["count"])
	var slot_dur := int(slot.get("durability", -1))
	if cursor.is_empty():
		if slot_id.is_empty() or slot_count <= 0:
			return
		cursor.set_stack(slot_id, slot_count, slot_dur)
		adapter.write_stack(index, "", 0)
		return
	var cursor_id := cursor.resource_id
	var cursor_dur := int(cursor.durability)
	if slot_id.is_empty():
		var moved := cursor.count
		cursor.clear()
		adapter.write_stack(index, cursor_id, moved, cursor_dur)
		return
	if slot_id == cursor_id:
		var room := _room_for(slot, cursor_id)
		if room <= 0:
			return
		var moved := cursor.take(mini(room, cursor.count))
		adapter.write_stack(index, cursor_id, slot_count + moved, slot_dur)
		return
	_swap_with_cursor(adapter, index, slot, cursor)


static func _click_right(adapter: SlotInventoryAdapter, index: int, slot: Dictionary, cursor: CursorStack) -> void:
	var slot_id := str(slot["id"])
	var slot_count := int(slot["count"])
	var slot_dur := int(slot.get("durability", -1))
	if cursor.is_empty():
		if slot_id.is_empty() or slot_count <= 0:
			return
		var take := ceili(slot_count / 2.0)
		take = mini(take, cursor.space_left())
		if take <= 0:
			return
		cursor.add(slot_id, take, slot_dur)
		var remain := slot_count - take
		if remain <= 0:
			adapter.write_stack(index, "", 0)
		else:
			adapter.write_stack(index, slot_id, remain, slot_dur)
		return
	var cursor_id := cursor.resource_id
	if slot_id.is_empty():
		deposit_one(adapter, index, cursor)
		return
	if slot_id == cursor_id:
		deposit_one(adapter, index, cursor)
		return


static func _swap_with_cursor(adapter: SlotInventoryAdapter, index: int, slot: Dictionary, cursor: CursorStack) -> void:
	var slot_id := str(slot["id"])
	var slot_count := int(slot["count"])
	var slot_dur := int(slot.get("durability", -1))
	var cursor_id := cursor.resource_id
	var cursor_count := cursor.count
	var cursor_dur := int(cursor.durability)
	cursor.set_stack(slot_id, slot_count, slot_dur)
	if cursor_id.is_empty() or cursor_count <= 0:
		adapter.write_stack(index, "", 0)
	else:
		adapter.write_stack(index, cursor_id, cursor_count, cursor_dur)


static func _room_for(slot: Dictionary, id: String) -> int:
	if not slot["id"].is_empty() and str(slot["id"]) != id:
		return 0
	var limit := Capacities.stack_limit(id)
	if slot["id"].is_empty():
		return limit
	return maxi(0, limit - int(slot["count"]))
