extends CanvasLayer

## UI four — layout entièrement dans `scenes/ui/furnace_panel.tscn`.
## Cuisson / recettes : brancher via `set_cook_progress`, `cook_tick` (machine) et filtres `can_accept_*`.

const ITEM_SLOT := preload("res://scripts/ui/item_slot.gd")
const RECIPES := preload("res://scripts/resources/recipe_catalog.gd")
const SlotInventoryAdapter := preload("res://scripts/inventory/slot_inventory_adapter.gd")
const SlotStackOps := preload("res://scripts/inventory/slot_stack_ops.gd")
const Capacities := preload("res://scripts/inventory/capacities.gd")

const SLOT_INPUT := 0
const SLOT_FUEL := 1
const SLOT_RESULT := 2
const FURNACE_SLOTS := 3
const SLOT_SIZE := 48.0

@onready var _root: Control = $Root
@onready var _dim: ColorRect = $Root/Dim
@onready var _panel: PanelContainer = $Root/Panel
@onready var _title: Label = $Root/Panel/Margin/VBox/Title
@onready var _input_slot: Panel = $Root/Panel/Margin/VBox/FurnaceRow/InputColumn/InputSlot
@onready var _fuel_slot: Panel = $Root/Panel/Margin/VBox/FurnaceRow/CenterColumn/FuelSlot
@onready var _result_slot: Panel = $Root/Panel/Margin/VBox/FurnaceRow/ResultColumn/ResultSlot
@onready var _progress: ProgressBar = $Root/Panel/Margin/VBox/FurnaceRow/CenterColumn/CookProgress
@onready var _player_grid: GridContainer = $Root/Panel/Margin/VBox/PlayerGrid

var _machine: Node
var _inventory: Node
var _player: Node
var _store
var _hud: Node
var _cursor
var _session
var _player_adapter: SlotInventoryAdapter
var _furnace_adapter: SlotInventoryAdapter
var _furnace_slots: Array = []
var _player_slots: Array = []


func _ready() -> void:
	layer = 25
	_root.visible = false
	_dim.gui_input.connect(_on_dim_input)
	_bind_furnace_slot(_input_slot, SLOT_INPUT)
	_bind_furnace_slot(_fuel_slot, SLOT_FUEL)
	_bind_furnace_slot(_result_slot, SLOT_RESULT)
	_progress.min_value = 0.0
	_progress.max_value = 1.0
	_progress.value = 0.0
	_progress.show_percentage = false
	if not Settings.language_changed.is_connected(_on_language):
		Settings.language_changed.connect(_on_language)
	_apply_tr(_root)


func is_open() -> bool:
	return _root != null and _root.visible


func open(machine: Node, inventory: Node, player: Node) -> void:
	if machine == null or inventory == null or player == null:
		return
	_machine = machine
	_inventory = inventory
	_player = player
	_store = machine.get("storage")
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
	_furnace_adapter = SlotInventoryAdapter.from_container(_store)
	_ensure_player_slots()
	_title.text = RECIPES.display_name("furnace")
	_root.visible = true
	set_process(true)
	_set_hotbar_interactive(true)
	_player.set(&"controls_locked", true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not _store.changed.is_connected(_refresh):
		_store.changed.connect(_refresh)
	if not _inventory.changed.is_connected(_refresh):
		_inventory.changed.connect(_refresh)
	_sync_progress_from_machine()
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
	set_process(false)
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
	if _store != null and _store.changed.is_connected(_refresh):
		_store.changed.disconnect(_refresh)
	if _inventory != null and _inventory.changed.is_connected(_refresh):
		_inventory.changed.disconnect(_refresh)
	_machine = null
	_store = null
	_set_hotbar_interactive(false)
	if _player != null and is_instance_valid(_player):
		_player.set(&"controls_locked", false)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Point d’intégration cuisson : ratio 0..1 affiché sur la barre.
func set_cook_progress(ratio: float) -> void:
	if _progress == null:
		return
	_progress.value = clampf(ratio, 0.0, 1.0)


func get_furnace_adapter() -> SlotInventoryAdapter:
	return _furnace_adapter


func transfer_from_player(index: int) -> bool:
	if _player_adapter == null or _furnace_adapter == null:
		return false
	return _transfer_to_furnace_slots(index)


func _process(_delta: float) -> void:
	if not is_open():
		return
	_sync_progress_from_machine()


## Maj+clic : priorise fuel / input / result selon can_accept_*.
func _transfer_to_furnace_slots(from_index: int) -> bool:
	var source: Dictionary = _player_adapter.stack_at(from_index)
	var id := str(source.get("id", ""))
	if id.is_empty() or int(source.get("count", 0)) <= 0:
		return false
	var order: Array[int] = []
	if _machine != null:
		if _machine.has_method(&"can_accept_input") and bool(_machine.call(&"can_accept_input", id)):
			order.append(SLOT_INPUT)
		if _machine.has_method(&"can_accept_fuel") and bool(_machine.call(&"can_accept_fuel", id)):
			order.append(SLOT_FUEL)
		if _machine.has_method(&"can_accept_result") and bool(_machine.call(&"can_accept_result", id)):
			order.append(SLOT_RESULT)
	if order.is_empty():
		return SlotStackOps.transfer_stack(_player_adapter, from_index, _furnace_adapter)
	var remaining := int(source["count"])
	var dur := int(source.get("durability", -1))
	var start := remaining
	for slot_i in order:
		if remaining <= 0:
			break
		var slot: Dictionary = _furnace_adapter.stack_at(slot_i)
		var slot_id := str(slot.get("id", ""))
		if not slot_id.is_empty() and slot_id != id:
			continue
		var limit := Capacities.stack_limit(id)
		var have := 0 if slot_id.is_empty() else int(slot.get("count", 0))
		var room := limit - have
		if room <= 0:
			continue
		var moved := mini(remaining, room)
		var write_dur := dur if slot_id.is_empty() else int(slot.get("durability", -1))
		_furnace_adapter.write_stack(slot_i, id, have + moved, write_dur)
		remaining -= moved
	if remaining >= start:
		return false
	if remaining <= 0:
		_player_adapter.write_stack(from_index, "", 0)
	else:
		_player_adapter.write_stack(from_index, id, remaining, dur)
	return true


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


func _bind_furnace_slot(slot: Panel, index: int) -> void:
	if slot == null:
		return
	slot.slot_index = index
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	_connect_slot_signals(slot, "furnace")
	_furnace_slots.append(slot)


func _ensure_player_slots() -> void:
	if not _player_slots.is_empty():
		return
	_player_grid.columns = Capacities.GRID_COLUMNS
	var backpack_start := int(_inventory.SLOT_COUNT)
	for i in Capacities.BACKPACK:
		var slot = ITEM_SLOT.new()
		slot.slot_index = backpack_start + i
		slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		_connect_slot_signals(slot, "player")
		_player_grid.add_child(slot)
		_player_slots.append(slot)


func _connect_slot_signals(slot, tag: String) -> void:
	if not slot.primary_pressed.is_connected(_on_primary_pressed.bind(tag)):
		slot.primary_pressed.connect(_on_primary_pressed.bind(tag))
	if not slot.primary_released.is_connected(_on_primary_released.bind(tag)):
		slot.primary_released.connect(_on_primary_released.bind(tag))
	if not slot.secondary_pressed.is_connected(_on_secondary_pressed.bind(tag)):
		slot.secondary_pressed.connect(_on_secondary_pressed.bind(tag))
	if not slot.secondary_released.is_connected(_on_secondary_released.bind(tag)):
		slot.secondary_released.connect(_on_secondary_released.bind(tag))
	if not slot.shift_clicked.is_connected(_on_shift_clicked.bind(tag)):
		slot.shift_clicked.connect(_on_shift_clicked.bind(tag))
	if not slot.pointer_entered.is_connected(_on_pointer_entered.bind(tag, slot)):
		slot.pointer_entered.connect(_on_pointer_entered.bind(tag, slot))
	if not slot.mouse_exited.is_connected(AudioManager.ui_hover_exit.bind(slot)):
		slot.mouse_exited.connect(AudioManager.ui_hover_exit.bind(slot))


func _adapter_for(tag: String) -> SlotInventoryAdapter:
	return _player_adapter if tag == "player" else _furnace_adapter


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
		var to_adapter := _furnace_adapter if tag == "player" else _player_adapter
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
	var to_adapter := _furnace_adapter if tag == "player" else _player_adapter
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
	if _stack_key() != before:
		AudioManager.ui("drop")
	_after_slot_action()


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


func _collect_pairs(tag: String = "") -> Array:
	var pairs: Array = []
	if tag != "furnace":
		for i in int(_inventory.slots.size()):
			pairs.append({"adapter": _player_adapter, "index": i})
	if tag != "player":
		for i in FURNACE_SLOTS:
			pairs.append({"adapter": _furnace_adapter, "index": i})
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
		_fill_slot(slot, true)
	for slot in _furnace_slots:
		_fill_slot(slot, false)
	_sync_progress_from_machine()


func _fill_slot(slot, player_side: bool) -> void:
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
			or (not player_side and _session.drag_adapter == _furnace_adapter)
		)
		if adapter_match and not preview.is_empty():
			resource_id = str(preview["id"])
			amount = int(preview["count"])
			if preview.has("durability"):
				durability = int(preview["durability"])
			if preview.has("max_durability"):
				max_durability = int(preview["max_durability"])
	slot.set_item(resource_id, amount, false, false, durability, max_durability)


func _sync_progress_from_machine() -> void:
	if _machine != null and _machine.has_method(&"get_cook_progress"):
		set_cook_progress(float(_machine.call(&"get_cook_progress")))
	elif _progress != null:
		_progress.value = 0.0


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
			parts.append("f%s:%d" % [str(stack["id"]), int(stack["count"])])
	return "|".join(parts)


func _track_begin() -> Dictionary:
	if _hud != null and _hud.has_method(&"begin_cursor_track"):
		return _hud.call(&"begin_cursor_track")
	return {}


func _track_end(before: Dictionary) -> void:
	if before.is_empty():
		return
	if _hud != null and _hud.has_method(&"end_cursor_track"):
		_hud.call(&"end_cursor_track", before)


func _is_ghost_mode() -> bool:
	return _hud != null and _hud.has_method(&"is_ghost_mode") and bool(_hud.call(&"is_ghost_mode"))


func _set_hotbar_interactive(active: bool) -> void:
	if _hud != null and _hud.has_method(&"set_hotbar_interactive"):
		_hud.call(&"set_hotbar_interactive", active)


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_RIGHT and not _is_ghost_mode():
			close()


func _on_language() -> void:
	_apply_tr(_root)
	if is_open():
		_title.text = RECIPES.display_name("furnace")


func _apply_tr(node: Node) -> void:
	if node.has_meta(&"key") and node is Label:
		node.set(&"text", tr(str(node.get_meta(&"key"))))
	for child in node.get_children():
		_apply_tr(child)
