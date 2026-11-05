extends RefCounted
class_name HudSlotSession

signal refreshed
signal drag_visuals_changed

const CursorStack := preload("res://scripts/inventory/cursor_stack.gd")
const PendingCrafts := preload("res://scripts/inventory/pending_crafts.gd")
const SlotInventoryAdapter := preload("res://scripts/inventory/slot_inventory_adapter.gd")
const SlotStackOps := preload("res://scripts/inventory/slot_stack_ops.gd")
const SlotPointerSession := preload("res://scripts/inventory/slot_pointer_session.gd")
const CursorGhostView := preload("res://scripts/ui/cursor_ghost_view.gd")

var cursor := CursorStack.new()
var pending := PendingCrafts.new()
var pointer := SlotPointerSession.new()
var ghost := CursorGhostView.new()
var adapter: SlotInventoryAdapter

var _host: Node
var _inventory
var _storage_panel: CanvasLayer
var _furnace_panel: CanvasLayer
var _inventory_open := false


func setup(host: Node, inventory, player_adapter: SlotInventoryAdapter) -> void:
	_host = host
	_inventory = inventory
	adapter = player_adapter
	ghost.ensure(host)


func set_inventory_open(open: bool) -> void:
	_inventory_open = open


func set_storage_panel(panel: CanvasLayer) -> void:
	_storage_panel = panel


func set_furnace_panel(panel: CanvasLayer) -> void:
	_furnace_panel = panel


func is_storage_open() -> bool:
	return _storage_panel != null and bool(_storage_panel.call(&"is_open"))


func is_furnace_open() -> bool:
	return _furnace_panel != null and bool(_furnace_panel.call(&"is_open"))


func is_cursor_ui_open() -> bool:
	return _inventory_open or is_storage_open() or is_furnace_open()


func is_ghost_mode() -> bool:
	return pending.is_active_for(cursor)


func begin_cursor_track() -> Dictionary:
	return {"id": cursor.resource_id, "count": cursor.count}


func end_cursor_track(before: Dictionary) -> void:
	var id := str(before.get("id", ""))
	if id.is_empty():
		return
	var before_count := int(before.get("count", 0))
	var deposited := before_count - cursor.count if cursor.resource_id == id else before_count
	if deposited > 0:
		pending.validate_deposited(id, deposited)


func cancel_one_pending_craft() -> bool:
	if not is_ghost_mode():
		return false
	var ok := pending.cancel_one(cursor, _inventory)
	if ok:
		refresh_ghost()
		refreshed.emit()
	return ok


func cancel_pending_crafts() -> void:
	if pending.is_empty():
		return
	pending.cancel_all(cursor, _inventory)
	refresh_ghost()
	refreshed.emit()


func handle_ghost_right_click(event: InputEvent) -> bool:
	if not is_cursor_ui_open() or not is_ghost_mode():
		return false
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_RIGHT:
		return false
	pointer.reset()
	if not cancel_one_pending_craft():
		return false
	AudioManager.ui("click")
	return true


func track_motion(pos: Vector2) -> bool:
	if not pointer.active():
		return false
	if pointer.track_motion(pos, cursor, is_ghost_mode()):
		refresh_drag_visuals()
		return true
	return false


func on_global_mouse_released(button: int) -> void:
	if not is_cursor_ui_open():
		return
	if not pointer.active() or button != pointer.drag_button:
		return
	if pointer.shift_transfer:
		pointer.reset()
		refresh_drag_visuals()
		return
	if not pointer.drag_moved:
		return
	var before := _stack_key()
	var track := begin_cursor_track()
	pointer.finish_drag(cursor)
	end_cursor_track(track)
	if _stack_key() != before:
		AudioManager.ui("drop")
	refresh_drag_visuals()


func fill_slot(slot, hotbar_size: int) -> void:
	var index := int(slot.slot_index)
	var stack: Dictionary = _inventory.call(&"get_slot_stack", index)
	var resource_id := str(stack["id"])
	var amount := int(stack["count"])
	var durability := int(stack.get("durability", -1))
	var max_durability := int(stack.get("max_durability", 0))
	var preview: Dictionary = pointer.preview_at(index)
	if not preview.is_empty():
		resource_id = str(preview["id"])
		amount = int(preview["count"])
		if preview.has("durability"):
			durability = int(preview["durability"])
		if preview.has("max_durability"):
			max_durability = int(preview["max_durability"])
	var selected := index < hotbar_size and index == int(_inventory.selected_index)
	slot.set_item(resource_id, amount, selected, false, durability, max_durability)


func on_shift_clicked(index: int) -> void:
	if pointer.shift_transfer and pointer.drag_moved:
		pointer.reset()
		refresh_drag_visuals()
		return
	pointer.reset()
	if not cursor.is_empty() or is_ghost_mode():
		return
	var ok := false
	if is_storage_open() and _storage_panel.has_method(&"transfer_from_player"):
		ok = bool(_storage_panel.call(&"transfer_from_player", index))
	elif is_furnace_open() and _furnace_panel.has_method(&"transfer_from_player"):
		ok = bool(_furnace_panel.call(&"transfer_from_player", index))
	else:
		var hotbar_size := int(_inventory.SLOT_COUNT)
		if index < hotbar_size:
			ok = _inventory.call(&"quick_move_to_backpack", index)
		else:
			ok = _inventory.call(&"quick_move_to_hotbar", index)
	if ok:
		AudioManager.ui("drop")
		refresh_drag_visuals()


func on_clicked(index: int) -> void:
	if pointer.drag_moved:
		return
	_select_hotbar_if_needed(index)


func slots_interactive() -> bool:
	return _inventory_open or is_storage_open() or is_furnace_open()


func on_primary_pressed(index: int) -> void:
	if not slots_interactive():
		return
	var shift := Input.is_key_pressed(KEY_SHIFT) or Input.is_physical_key_pressed(KEY_SHIFT)
	if shift:
		if not cursor.is_empty() or is_ghost_mode():
			return
		if is_storage_open() and _storage_panel.has_method(&"get_chest_adapter"):
			var chest_adapter: SlotInventoryAdapter = _storage_panel.call(&"get_chest_adapter")
			pointer.on_press(
				MOUSE_BUTTON_LEFT,
				index,
				_host.get_viewport().get_mouse_position(),
				adapter,
				true,
				chest_adapter
			)
		elif is_furnace_open() and _furnace_panel.has_method(&"get_furnace_adapter"):
			var furnace_adapter: SlotInventoryAdapter = _furnace_panel.call(&"get_furnace_adapter")
			pointer.on_press(
				MOUSE_BUTTON_LEFT,
				index,
				_host.get_viewport().get_mouse_position(),
				adapter,
				true,
				furnace_adapter
			)
		return
	pointer.on_press(MOUSE_BUTTON_LEFT, index, _host.get_viewport().get_mouse_position(), adapter)


func on_primary_released(index: int, double_click: bool) -> void:
	if not slots_interactive():
		return
	var before_sel := int(_inventory.selected_index)
	var before := _stack_key()
	var track := begin_cursor_track()
	var result := pointer.handle_release(
		MOUSE_BUTTON_LEFT,
		index,
		true,
		double_click,
		adapter,
		cursor,
		_player_collect_pairs()
	)
	if result == "none":
		return
	end_cursor_track(track)
	var moved := _stack_key() != before
	if moved:
		AudioManager.ui("drop")
	_finish_slot_action(index)
	if result == "click" and not moved and index < int(_inventory.SLOT_COUNT) and int(_inventory.selected_index) != before_sel:
		AudioManager.ui("select")


func on_secondary_pressed(index: int) -> void:
	if not slots_interactive() or is_ghost_mode():
		return
	pointer.on_press(MOUSE_BUTTON_RIGHT, index, _host.get_viewport().get_mouse_position(), adapter)


func on_secondary_released(index: int) -> void:
	if not slots_interactive() or is_ghost_mode():
		return
	var before := _stack_key()
	var track := begin_cursor_track()
	var result := pointer.handle_release(
		MOUSE_BUTTON_RIGHT,
		index,
		false,
		false,
		adapter,
		cursor,
		_player_collect_pairs()
	)
	if result == "none":
		return
	end_cursor_track(track)
	if _stack_key() != before:
		AudioManager.ui("drop")
	_finish_slot_action(index)


func on_pointer_entered(index: int, slot: Control) -> void:
	if not slots_interactive():
		return
	if is_ghost_mode() and pointer.drag_button == MOUSE_BUTTON_RIGHT:
		return
	var before := _stack_key()
	var track := begin_cursor_track()
	pointer.on_pointer_enter(index, adapter, cursor, is_ghost_mode())
	end_cursor_track(track)
	if _stack_key() != before:
		AudioManager.ui("drop")
	elif not pointer.is_left_preview():
		AudioManager.ui_hover(slot)
	refresh_drag_visuals()


func on_dropped(from_index: int, to_index: int) -> void:
	var before := _stack_key()
	_inventory.call(&"move_slot", from_index, to_index)
	if _stack_key() != before:
		AudioManager.ui("drop")
	refreshed.emit()


func follow_mouse() -> void:
	if cursor.is_empty():
		return
	ghost.follow_mouse(_host.get_viewport())


func stash_cursor_stack() -> void:
	if cursor.is_empty():
		return
	var track := begin_cursor_track()
	var left: int = int(_inventory.call(&"stash_cursor_stack", cursor.resource_id, cursor.count, cursor.durability))
	if left <= 0:
		cursor.clear()
	else:
		cursor.count = left
	end_cursor_track(track)
	refresh_ghost()


func refresh_ghost() -> void:
	ghost.ensure(_host)
	if cursor.is_empty():
		ghost.refresh("", 0, false)
		return
	var shown := pointer.preview_cursor_count(cursor.count)
	ghost.refresh(cursor.resource_id, shown, is_cursor_ui_open())


func refresh_drag_visuals() -> void:
	refresh_ghost()
	drag_visuals_changed.emit()
	if is_storage_open():
		_storage_panel.call(&"_refresh")
	if is_furnace_open():
		_furnace_panel.call(&"_refresh")


func reset_pointer() -> void:
	pointer.reset()


func cancel_drag() -> void:
	pointer.cancel_drag()


func _finish_slot_action(index: int) -> void:
	_select_hotbar_if_needed(index)
	refresh_ghost()
	refreshed.emit()


func _select_hotbar_if_needed(index: int) -> void:
	if index < int(_inventory.SLOT_COUNT):
		_inventory.call(&"select_slot", index)


func _stack_key() -> String:
	var parts := PackedStringArray()
	parts.append("%s:%d" % [cursor.resource_id, cursor.count])
	for i in int(_inventory.slots.size()):
		var stack: Dictionary = _inventory.call(&"get_slot_stack", i)
		parts.append("%s:%d" % [str(stack["id"]), int(stack["count"])])
	return "|".join(parts)


func _player_collect_pairs() -> Array:
	var pairs: Array = []
	for i in int(_inventory.slots.size()):
		pairs.append({"adapter": adapter, "index": i})
	if is_furnace_open() and _furnace_panel.has_method(&"get_furnace_adapter"):
		var furnace_adapter: SlotInventoryAdapter = _furnace_panel.call(&"get_furnace_adapter")
		for i in furnace_adapter.slot_count:
			pairs.append({"adapter": furnace_adapter, "index": i})
	return pairs
