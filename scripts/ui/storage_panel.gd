extends CanvasLayer

const ITEM_SLOT := preload("res://scripts/ui/item_slot.gd")
const RECIPES := preload("res://scripts/resources/recipe_catalog.gd")
const SlotInventoryAdapter := preload("res://scripts/inventory/slot_inventory_adapter.gd")
const SlotStackOps := preload("res://scripts/inventory/slot_stack_ops.gd")
const Capacities := preload("res://scripts/inventory/capacities.gd")

const SLOT_SIZE := 48.0
const SLOT_GAP := 4.0

var _piece: Node
var _inventory: Node
var _player: Node
var _store
var _root: Control
var _panel: PanelContainer
var _chest_grid: GridContainer
var _player_grid: GridContainer
var _title: Label
var _chest_slots: Array = []
var _player_slots: Array = []
var _player_adapter: SlotInventoryAdapter
var _chest_adapter: SlotInventoryAdapter
var _hud: Node
var _cursor
var _session


func is_open() -> bool:
	return _root != null and _root.visible


func open(piece: Node, inventory: Node, player: Node) -> void:
	_piece = piece
	_inventory = inventory
	_player = player
	_store = piece.get("storage")
	if _store == null:
		return
	_hud = get_tree().get_first_node_in_group(&"hud")
	if _hud != null:
		_cursor = _hud.call(&"get_cursor_stack")
		_session = _hud.call(&"get_pointer_session")
		if _hud.has_method(&"get_player_slot_adapter"):
			_player_adapter = _hud.call(&"get_player_slot_adapter")
	if _player_adapter == null:
		_player_adapter = SlotInventoryAdapter.from_inventory(_inventory)
	_chest_adapter = SlotInventoryAdapter.from_container(_store)
	_ensure_ui()
	_rebuild_slots()
	_root.visible = true
	_fit_panel()
	_set_hotbar_interactive(true)
	_player.set(&"controls_locked", true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not _store.changed.is_connected(_refresh):
		_store.changed.connect(_refresh)
	if not _inventory.changed.is_connected(_refresh):
		_inventory.changed.connect(_refresh)
	_refresh()
	if _hud != null:
		_hud.call(&"refresh_cursor_ghost")
		if _hud.has_method(&"_refresh"):
			_hud.call(&"_refresh")
	AudioManager.ui("open")


func close() -> void:
	if _root == null or not _root.visible:
		return
	_root.visible = false
	AudioManager.ui("close")
	if _session != null:
		_session.cancel_drag()
	if _hud != null and _hud.has_method(&"cancel_pending_crafts"):
		_hud.call(&"cancel_pending_crafts")
	if _hud != null and _cursor != null and not _cursor.is_empty():
		var track: Dictionary = _hud.call(&"begin_cursor_track") if _hud.has_method(&"begin_cursor_track") else {}
		var left := int(_inventory.call(&"stash_cursor_stack", _cursor.resource_id, _cursor.count, _cursor.durability))
		if left <= 0:
			_cursor.clear()
		else:
			_cursor.count = left
		if _hud.has_method(&"end_cursor_track") and not track.is_empty():
			_hud.call(&"end_cursor_track", track)
		_hud.call(&"refresh_cursor_ghost")
	if _session != null:
		_session.reset()
	_piece = null
	_store = null
	_set_hotbar_interactive(false)
	if _player != null and is_instance_valid(_player):
		_player.set(&"controls_locked", false)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if not is_open() or _session == null or not _session.shift_transfer:
		return
	if event is InputEventKey and not event.pressed and not event.is_echo():
		if not (Input.is_key_pressed(KEY_SHIFT) or Input.is_physical_key_pressed(KEY_SHIFT)):
			_stop_shift_transfer()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event is InputEventMouseMotion and _session != null and _session.active():
		var before := _stack_key()
		if _session.track_motion(event.global_position, _cursor, _is_ghost_mode()):
			if _stack_key() != before:
				AudioManager.ui("drop")
			_after_slot_action()
	if event is InputEventMouseButton and not event.pressed:
		_on_global_mouse_released((event as InputEventMouseButton).button_index)


func _ensure_ui() -> void:
	if _root != null:
		return
	layer = 25
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_input)
	_root.add_child(dim)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.clip_contents = true
	_panel.add_theme_stylebox_override(&"panel", _style(Color(0.07, 0.08, 0.09, 0.97)))
	_root.add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", 10)
	margin.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override(&"font_size", 18)
	box.add_child(_title)
	var columns := HBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override(&"separation", 24)
	box.add_child(columns)
	var player_col := VBoxContainer.new()
	player_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	player_col.add_theme_constant_override(&"separation", 6)
	columns.add_child(player_col)
	player_col.add_child(_heading("INVENTORY"))
	if not Settings.language_changed.is_connected(_on_language):
		Settings.language_changed.connect(_on_language)
	_player_grid = GridContainer.new()
	_player_grid.columns = Capacities.GRID_COLUMNS
	_player_grid.add_theme_constant_override(&"h_separation", int(SLOT_GAP))
	_player_grid.add_theme_constant_override(&"v_separation", int(SLOT_GAP))
	player_col.add_child(_slot_scroll(_player_grid))
	var chest_col := VBoxContainer.new()
	chest_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chest_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chest_col.add_theme_constant_override(&"separation", 6)
	columns.add_child(chest_col)
	chest_col.add_child(_heading("CHEST"))
	_chest_grid = GridContainer.new()
	_chest_grid.columns = Capacities.GRID_COLUMNS
	_chest_grid.add_theme_constant_override(&"h_separation", int(SLOT_GAP))
	_chest_grid.add_theme_constant_override(&"v_separation", int(SLOT_GAP))
	chest_col.add_child(_slot_scroll(_chest_grid))
	if not get_viewport().size_changed.is_connected(_fit_panel):
		get_viewport().size_changed.connect(_fit_panel)


func _rebuild_slots() -> void:
	_clear_grid(_player_grid, _player_slots)
	_clear_grid(_chest_grid, _chest_slots)
	var backpack_start := int(_inventory.SLOT_COUNT)
	_player_grid.columns = Capacities.GRID_COLUMNS
	for i in Capacities.BACKPACK:
		_player_grid.add_child(_make_slot("player", backpack_start + i, _player_slots))
	var chest_count := mini(int(_store.slots.size()), Capacities.DOUBLE_CHEST)
	_chest_grid.columns = Capacities.GRID_COLUMNS
	for i in chest_count:
		_chest_grid.add_child(_make_slot("chest", i, _chest_slots))
	_title.text = RECIPES.display_name(str(_piece.get("piece_id")))
	_fit_panel()


func _slot_scroll(grid: GridContainer) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.add_child(grid)
	return scroll


func _fit_panel() -> void:
	if _panel == null or _player_grid == null or _chest_grid == null:
		return
	var cols := Capacities.GRID_COLUMNS
	var backpack_rows := ceili(float(Capacities.BACKPACK) / float(cols))
	var chest_rows := ceili(float(_chest_slots.size()) / float(cols))
	var visible_rows := mini(maxi(backpack_rows, chest_rows), 8)
	var content_w := 32.0 + _grid_span(cols) + 24.0 + _grid_span(cols)
	var content_h := 32.0 + 28.0 + 10.0 + 22.0 + 6.0 + _grid_span(visible_rows)
	var view := get_viewport().get_visible_rect().size
	var width := minf(content_w, maxf(view.x - 32.0, 320.0))
	var height := minf(content_h, maxf(view.y - 32.0, 240.0))
	_panel.offset_left = -width * 0.5
	_panel.offset_right = width * 0.5
	_panel.offset_top = -height * 0.5
	_panel.offset_bottom = height * 0.5


func _set_hotbar_interactive(active: bool) -> void:
	if _hud != null and _hud.has_method(&"set_hotbar_interactive"):
		_hud.call(&"set_hotbar_interactive", active)


func get_chest_adapter() -> SlotInventoryAdapter:
	return _chest_adapter


func transfer_from_player(index: int) -> bool:
	if _player_adapter == null or _chest_adapter == null:
		return false
	return SlotStackOps.transfer_stack(_player_adapter, index, _chest_adapter)


func _grid_span(count: int) -> float:
	if count <= 0:
		return 0.0
	return float(count) * SLOT_SIZE + float(count - 1) * SLOT_GAP


func _make_slot(tag: String, index: int, bucket: Array) -> Panel:
	var slot = ITEM_SLOT.new()
	slot.slot_index = index
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	slot.primary_pressed.connect(_on_primary_pressed.bind(tag))
	slot.primary_released.connect(_on_primary_released.bind(tag))
	slot.secondary_pressed.connect(_on_secondary_pressed.bind(tag))
	slot.secondary_released.connect(_on_secondary_released.bind(tag))
	slot.shift_clicked.connect(_on_shift_clicked.bind(tag))
	slot.pointer_entered.connect(_on_pointer_entered.bind(tag, slot))
	slot.mouse_exited.connect(AudioManager.ui_hover_exit.bind(slot))
	bucket.append(slot)
	return slot


func _adapter_for(tag: String) -> SlotInventoryAdapter:
	return _player_adapter if tag == "player" else _chest_adapter


func _on_primary_pressed(index: int, tag: String) -> void:
	if _session == null:
		return
	var shift := Input.is_key_pressed(KEY_SHIFT) or Input.is_physical_key_pressed(KEY_SHIFT)
	if shift:
		if _cursor != null and not _cursor.is_empty():
			return
		if _is_ghost_mode():
			return
		var from_adapter := _adapter_for(tag)
		var to_adapter := _chest_adapter if tag == "player" else _player_adapter
		_session.on_press(
			MOUSE_BUTTON_LEFT,
			index,
			get_viewport().get_mouse_position(),
			from_adapter,
			true,
			to_adapter
		)
		return
	_session.on_press(MOUSE_BUTTON_LEFT, index, get_viewport().get_mouse_position(), _adapter_for(tag))


func _on_shift_clicked(index: int, tag: String) -> void:
	if _session != null and _session.shift_transfer and _session.drag_moved:
		_stop_shift_transfer()
		return
	if _session != null:
		_session.reset()
	if _cursor != null and not _cursor.is_empty():
		return
	if _is_ghost_mode():
		return
	var from_adapter := _adapter_for(tag)
	var to_adapter := _chest_adapter if tag == "player" else _player_adapter
	if not SlotStackOps.transfer_stack(from_adapter, index, to_adapter):
		return
	AudioManager.ui("drop")
	_after_slot_action()


func _stop_shift_transfer() -> void:
	if _session == null or not _session.shift_transfer:
		return
	_session.reset()
	_after_slot_action()


func _on_primary_released(index: int, double_click: bool, tag: String) -> void:
	if _session == null or _cursor == null:
		return
	var before := _stack_key()
	var track := _track_begin()
	var result: String = _session.handle_release(
		MOUSE_BUTTON_LEFT,
		index,
		true,
		double_click,
		_adapter_for(tag),
		_cursor,
		_collect_pairs(tag)
	)
	if result == "none":
		return
	_track_end(track)
	_select_hotbar_if_needed(index, tag)
	if _stack_key() != before:
		AudioManager.ui("drop")
	_after_slot_action()


func _select_hotbar_if_needed(index: int, tag: String) -> void:
	if tag != "player" or _inventory == null:
		return
	if index < 0 or index >= int(_inventory.SLOT_COUNT):
		return
	_inventory.call(&"select_slot", index)


func _is_ghost_mode() -> bool:
	return _hud != null and _hud.has_method(&"is_ghost_mode") and bool(_hud.call(&"is_ghost_mode"))


func _on_secondary_pressed(index: int, tag: String) -> void:
	if _session == null or _is_ghost_mode():
		return
	_session.on_press(MOUSE_BUTTON_RIGHT, index, get_viewport().get_mouse_position(), _adapter_for(tag))


func _on_secondary_released(index: int, tag: String) -> void:
	if _session == null or _cursor == null or _is_ghost_mode():
		return
	var before := _stack_key()
	var track := _track_begin()
	var result: String = _session.handle_release(
		MOUSE_BUTTON_RIGHT,
		index,
		false,
		false,
		_adapter_for(tag),
		_cursor,
		_collect_pairs()
	)
	if result == "none":
		return
	_track_end(track)
	if _stack_key() != before:
		AudioManager.ui("drop")
	_after_slot_action()


func _on_pointer_entered(index: int, tag: String, slot: Control) -> void:
	if not is_open() or _session == null or _cursor == null:
		return
	if _is_ghost_mode() and _session.drag_button == MOUSE_BUTTON_RIGHT:
		return
	var before := _stack_key()
	var track := _track_begin()
	_session.on_pointer_enter(index, _adapter_for(tag), _cursor, _is_ghost_mode())
	_track_end(track)
	if _stack_key() != before:
		AudioManager.ui("drop")
	elif _session.is_left_preview():
		pass
	else:
		AudioManager.ui_hover(slot)
	_after_slot_action()


func _on_global_mouse_released(button: int) -> void:
	if _session == null or _cursor == null:
		return
	if not _session.active() or button != _session.drag_button:
		return
	if _session.shift_transfer:
		_stop_shift_transfer()
		return
	if not _session.drag_moved:
		return
	var before := _stack_key()
	var track := _track_begin()
	_session.finish_drag(_cursor)
	_track_end(track)
	if _stack_key() != before:
		AudioManager.ui("drop")
	_after_slot_action()


func _stack_key() -> String:
	var parts := PackedStringArray()
	if _cursor != null:
		parts.append("%s:%d" % [_cursor.resource_id, _cursor.count])
	if _inventory != null:
		for i in int(_inventory.slots.size()):
			var stack: Dictionary = _inventory.call(&"get_slot_stack", i)
			parts.append("p%s:%d" % [str(stack["id"]), int(stack["count"])])
	if _store != null:
		for i in int(_store.slots.size()):
			var stack: Dictionary = _store.call(&"get_slot_stack", i)
			parts.append("c%s:%d" % [str(stack["id"]), int(stack["count"])])
	return "|".join(parts)


func _collect_pairs(tag: String = "") -> Array:
	var pairs: Array = []
	if tag != "chest":
		for i in int(_inventory.slots.size()):
			pairs.append({"adapter": _player_adapter, "index": i})
	if tag != "player":
		for i in int(_store.slots.size()):
			pairs.append({"adapter": _chest_adapter, "index": i})
	return pairs


func _after_slot_action() -> void:
	if _hud != null:
		_hud.call(&"refresh_cursor_ghost")
		if _hud.has_method(&"_refresh"):
			_hud.call(&"_refresh")
	_refresh()


func _refresh() -> void:
	if not is_open() or _store == null:
		return
	for slot in _player_slots:
		_fill_storage_slot(slot, true)
	for slot in _chest_slots:
		_fill_storage_slot(slot, false)


func _fill_storage_slot(slot, player_side: bool) -> void:
	var index := int(slot.slot_index)
	var stack: Dictionary
	if player_side:
		stack = _inventory.call(&"get_slot_stack", index)
	else:
		stack = _store.call(&"get_slot_stack", index)
	var resource_id := str(stack["id"])
	var amount := int(stack["count"])
	var durability := int(stack.get("durability", -1))
	var max_durability := int(stack.get("max_durability", 0))
	if _session != null and _session.drag_adapter != null:
		var preview: Dictionary = _session.preview_at(index)
		var adapter_match: bool = (
			(player_side and _session.drag_adapter == _player_adapter)
			or (not player_side and _session.drag_adapter == _chest_adapter)
		)
		if adapter_match and not preview.is_empty():
			resource_id = str(preview["id"])
			amount = int(preview["count"])
			if preview.has("durability"):
				durability = int(preview["durability"])
			if preview.has("max_durability"):
				max_durability = int(preview["max_durability"])
	slot.set_item(resource_id, amount, false, false, durability, max_durability)


func _track_begin() -> Dictionary:
	if _hud != null and _hud.has_method(&"begin_cursor_track"):
		return _hud.call(&"begin_cursor_track")
	return {}


func _track_end(before: Dictionary) -> void:
	if before.is_empty():
		return
	if _hud != null and _hud.has_method(&"end_cursor_track"):
		_hud.call(&"end_cursor_track", before)


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_RIGHT and not _is_ghost_mode():
			close()


func _clear_grid(grid: Control, bucket: Array) -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.free()
	bucket.clear()


func _on_language() -> void:
	_apply_tr(self)
	if is_open() and _piece != null:
		_title.text = RECIPES.display_name(str(_piece.get("piece_id")))


func _apply_tr(node: Node) -> void:
	if node.has_meta(&"key") and node is Label:
		node.set(&"text", tr(str(node.get_meta(&"key"))))
	for child in node.get_children():
		_apply_tr(child)


func _heading(key: String) -> Label:
	var label := Label.new()
	label.set_meta(&"key", key)
	label.text = tr(key)
	label.add_theme_font_size_override(&"font_size", 14)
	return label


func _style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(6)
	style.set_border_width_all(1)
	style.border_color = Color(1, 1, 1, 0.08)
	return style
