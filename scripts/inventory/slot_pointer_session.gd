extends RefCounted
class_name SlotPointerSession

const SlotStackOps := preload("res://scripts/inventory/slot_stack_ops.gd")

const DRAG_THRESHOLD := 5.0

var drag_button := -1
var drag_origin := -1
var drag_moved := false
var drag_path: Array[int] = []
var drag_adapter: SlotInventoryAdapter
var shift_transfer := false
var transfer_target: SlotInventoryAdapter

var _press_pos := Vector2.ZERO
var _preview: Dictionary = {}
var _preview_remain := 0


func active() -> bool:
	return drag_button >= 0


func is_left_preview() -> bool:
	return (
		drag_button == MOUSE_BUTTON_LEFT
		and drag_moved
		and not shift_transfer
		and not _preview.is_empty()
	)


func preview_at(index: int) -> Dictionary:
	if not _preview.has(index):
		return {}
	return _preview[index]


func preview_cursor_count(real_count: int) -> int:
	if not is_left_preview():
		return real_count
	return _preview_remain


func reset() -> void:
	drag_button = -1
	drag_origin = -1
	drag_moved = false
	drag_path.clear()
	drag_adapter = null
	shift_transfer = false
	transfer_target = null
	_press_pos = Vector2.ZERO
	_preview.clear()
	_preview_remain = 0


func on_press(
	button: int,
	index: int,
	screen_pos: Vector2,
	adapter: SlotInventoryAdapter,
	shift_mode := false,
	target_adapter: SlotInventoryAdapter = null
) -> void:
	reset()
	drag_button = button
	drag_origin = index
	drag_moved = false
	drag_adapter = adapter
	shift_transfer = shift_mode
	transfer_target = target_adapter
	_press_pos = screen_pos


func track_motion(screen_pos: Vector2, cursor = null, ghost_mode := false) -> bool:
	if drag_button < 0:
		return false
	if shift_transfer and not _shift_held():
		reset()
		return false
	if drag_moved or _press_pos.distance_to(screen_pos) < DRAG_THRESHOLD:
		return false
	drag_moved = true
	if shift_transfer:
		_include_shift_slot(drag_origin)
		return true
	if cursor != null and drag_origin >= 0:
		_include_slot(drag_origin, cursor, ghost_mode)
	return true


func on_pointer_enter(index: int, adapter: SlotInventoryAdapter, cursor, ghost_mode := false) -> void:
	if drag_button < 0 or not drag_moved:
		return
	if shift_transfer:
		if not _shift_held():
			reset()
			return
		if adapter != drag_adapter:
			return
		_include_shift_slot(index)
		return
	if adapter != drag_adapter:
		return
	_include_slot(index, cursor, ghost_mode)


func handle_release(
	button: int,
	index: int,
	left: bool,
	double_click: bool,
	adapter: SlotInventoryAdapter,
	cursor,
	collect_pairs: Array
) -> String:
	if drag_button != button:
		return "none"
	if drag_moved:
		finish_drag(cursor)
		return "drag"
	if try_click(index, left, double_click, adapter, cursor, collect_pairs):
		return "click"
	reset()
	return "none"


func try_click(index: int, left: bool, double_click: bool, adapter: SlotInventoryAdapter, cursor, collect_pairs: Array) -> bool:
	if drag_button < 0 or drag_moved:
		return false
	if left:
		if double_click and not cursor.is_empty():
			SlotStackOps.collect_matching_pairs(collect_pairs, cursor)
		else:
			SlotStackOps.click(adapter, index, cursor, true)
	else:
		SlotStackOps.click(adapter, index, cursor, false)
	reset()
	return true


func finish_drag(cursor) -> void:
	if drag_button < 0:
		return
	if shift_transfer or not drag_moved or drag_adapter == null:
		reset()
		return
	var button := drag_button
	var path := drag_path.duplicate()
	var adapter := drag_adapter
	var origin := drag_origin
	_preview.clear()
	_preview_remain = 0
	if button == MOUSE_BUTTON_LEFT and cursor != null and not cursor.is_empty() and not path.is_empty():
		SlotStackOps.spread_evenly(adapter, path, cursor)
	elif button == MOUSE_BUTTON_RIGHT and cursor != null and cursor.is_empty() and origin >= 0 and not path.is_empty():
		SlotStackOps.right_drag_from_source(adapter, origin, path)
	reset()


func cancel_drag() -> void:
	reset()


func _shift_held() -> bool:
	return Input.is_key_pressed(KEY_SHIFT) or Input.is_physical_key_pressed(KEY_SHIFT)


func _include_shift_slot(index: int) -> void:
	if drag_adapter == null or transfer_target == null:
		return
	if index < 0 or index >= drag_adapter.slot_count:
		return
	if index in drag_path:
		return
	drag_path.append(index)
	SlotStackOps.transfer_stack(drag_adapter, index, transfer_target)


func _include_slot(index: int, cursor, ghost_mode: bool) -> void:
	if drag_adapter == null or index < 0 or index >= drag_adapter.slot_count:
		return
	if index in drag_path:
		return
	if drag_button == MOUSE_BUTTON_RIGHT:
		if ghost_mode or cursor == null or cursor.is_empty():
			drag_path.append(index)
			return
		SlotStackOps.deposit_one(drag_adapter, index, cursor)
		drag_path.append(index)
		return
	if drag_button == MOUSE_BUTTON_LEFT:
		if cursor == null or cursor.is_empty():
			return
		var slot: Dictionary = drag_adapter.stack_at(index)
		if SlotStackOps.room_for(slot, cursor.resource_id) <= 0:
			return
		drag_path.append(index)
		_recompute_left_preview(cursor)


func _recompute_left_preview(cursor) -> void:
	_preview.clear()
	_preview_remain = int(cursor.count) if cursor != null else 0
	if cursor == null or cursor.is_empty() or drag_adapter == null or drag_path.is_empty():
		return
	var id: String = cursor.resource_id
	var remaining: int = int(cursor.count)
	var targets: Array[int] = []
	var baselines: Dictionary = {}
	var rooms: Dictionary = {}
	for index in drag_path:
		var slot: Dictionary = drag_adapter.stack_at(index)
		var room: int = SlotStackOps.room_for(slot, id)
		if room <= 0:
			continue
		targets.append(index)
		baselines[index] = int(slot["count"]) if str(slot["id"]) == id else 0
		rooms[index] = room
	if targets.is_empty():
		return
	var slots_left: int = targets.size()
	for index in targets:
		if remaining <= 0:
			break
		var room: int = int(rooms[index])
		if room <= 0:
			slots_left = maxi(slots_left - 1, 1)
			continue
		var share: int = int(ceil(float(remaining) / float(slots_left)))
		var add: int = mini(mini(share, room), remaining)
		if add > 0:
			var entry := {
				"id": id,
				"count": int(baselines[index]) + add,
			}
			if int(cursor.durability) >= 0:
				entry["durability"] = int(cursor.durability)
			_preview[index] = entry
			remaining -= add
		slots_left -= 1
	_preview_remain = remaining
