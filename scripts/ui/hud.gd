extends CanvasLayer

const PREVIEW := preload("res://scripts/ui/build_preview.gd")
const STORAGE_PANEL := preload("res://scripts/ui/storage_panel.gd")
const FURNACE_PANEL_SCENE := preload("res://scenes/ui/furnace_panel.tscn")
const PAUSE := preload("res://scripts/ui/pause_menu.gd")
const CursorStack := preload("res://scripts/inventory/cursor_stack.gd")
const SlotInventoryAdapter := preload("res://scripts/inventory/slot_inventory_adapter.gd")
const SlotPointerSession := preload("res://scripts/inventory/slot_pointer_session.gd")
const BuildMenuView := preload("res://scripts/ui/build_menu_view.gd")
const CraftCatalogView := preload("res://scripts/ui/craft_catalog_view.gd")
const HudVitalsView := preload("res://scripts/ui/hud_vitals_view.gd")
const BuildHelpView := preload("res://scripts/ui/build_help_view.gd")
const HotbarView := preload("res://scripts/ui/hotbar_view.gd")
const InventoryPanelView := preload("res://scripts/ui/inventory_panel_view.gd")
const HudSlotSession := preload("res://scripts/ui/hud_slot_session.gd")

@onready var _crosshair: Control = $Crosshair

var _player: Node
var _inventory
var _inventory_open := false
var _build_open := false
var _build_menu := BuildMenuView.new()
var _craft_catalog := CraftCatalogView.new()
var _slots := HudSlotSession.new()
var _vitals := HudVitalsView.new()
var _build_help := BuildHelpView.new()
var _hotbar_view := HotbarView.new()
var _inv_panel := InventoryPanelView.new()
var _storage_panel: CanvasLayer
var _furnace_panel: CanvasLayer
var _pause


func _ready() -> void:
	add_to_group(&"hud")
	var player := get_tree().get_first_node_in_group(&"player")
	if player == null:
		return
	_player = player
	_inventory = player.get_node(^"Inventory")
	var adapter := SlotInventoryAdapter.from_inventory(_inventory)
	_slots.setup(self, _inventory, adapter)
	_slots.refreshed.connect(_refresh)
	_slots.drag_visuals_changed.connect(_on_drag_visuals_changed)
	if player.has_signal(&"build_mode_changed"):
		player.connect(&"build_mode_changed", _sync_build_help)
	PREVIEW.open(self)
	_inv_panel.ensure(self, _bind_slot)
	_inv_panel.dim_clicked.connect(_on_dim_clicked)
	_craft_catalog.bind(_inventory, _slots.cursor, _slots.pending)
	_craft_catalog.mount(_inv_panel.craft_col, self)
	_craft_catalog.changed.connect(_on_craft_changed)
	_hotbar_view.ensure(self, _bind_slot)
	_build_help.ensure(self)
	_build_menu.set_inventory(_inventory)
	_build_menu.ensure(self)
	_build_menu.piece_chosen.connect(_on_build_piece_chosen)
	_vitals.ensure(self, player)
	_inventory.changed.connect(_refresh)
	_refresh()
	get_viewport().size_changed.connect(_apply_panel_bounds)
	_apply_panel_bounds()
	_pause = PAUSE.new()
	add_child(_pause)
	Settings.language_changed.connect(_on_language)


func set_pause_overlay(active: bool) -> void:
	_crosshair.visible = not active
	_vitals.set_visible(not active)
	_hotbar_view.set_visible(not active)
	if active:
		_build_help.set_visible(false)
	else:
		_sync_build_help()


func open_container(piece: Node) -> void:
	if piece == null or piece.get("storage") == null:
		return
	if _inventory_open:
		_set_inventory_open(false, false)
	_close_furnace_if_open()
	if _storage_panel == null:
		_storage_panel = STORAGE_PANEL.new()
		add_child(_storage_panel)
		_slots.set_storage_panel(_storage_panel)
	_storage_panel.call(&"open", piece, _inventory, _player)


func open_furnace(machine: Node) -> void:
	if machine == null or machine.get("storage") == null:
		return
	if _inventory_open:
		_set_inventory_open(false, false)
	if _storage_panel != null and bool(_storage_panel.call(&"is_open")):
		_storage_panel.call(&"close")
	if _furnace_panel == null:
		_furnace_panel = FURNACE_PANEL_SCENE.instantiate()
		add_child(_furnace_panel)
		if _slots.has_method(&"set_furnace_panel"):
			_slots.set_furnace_panel(_furnace_panel)
	_furnace_panel.call(&"open", machine, _inventory, _player)


func _close_furnace_if_open() -> void:
	if _furnace_panel != null and bool(_furnace_panel.call(&"is_open")):
		_furnace_panel.call(&"close")


func set_hotbar_visible(visible: bool) -> void:
	_hotbar_view.set_visible(visible)


func set_hotbar_interactive(active: bool) -> void:
	_hotbar_view.set_interactive(active)


func is_storage_open() -> bool:
	return _slots.is_storage_open()


func get_player_slot_adapter() -> SlotInventoryAdapter:
	return _slots.adapter


func get_cursor_stack() -> CursorStack:
	return _slots.cursor


func get_pointer_session() -> SlotPointerSession:
	return _slots.pointer


func is_ghost_mode() -> bool:
	return _slots.is_ghost_mode()


func refresh_cursor_ghost() -> void:
	_slots.refresh_ghost()


func begin_cursor_track() -> Dictionary:
	return _slots.begin_cursor_track()


func end_cursor_track(before: Dictionary) -> void:
	_slots.end_cursor_track(before)


func cancel_one_pending_craft() -> bool:
	return _slots.cancel_one_pending_craft()


func cancel_pending_crafts() -> void:
	_slots.cancel_pending_crafts()


func is_cursor_ui_open() -> bool:
	return _slots.is_cursor_ui_open()


func _input(event: InputEvent) -> void:
	if _inventory == null or _console_open():
		return
	if _slots.handle_ghost_right_click(event):
		get_viewport().set_input_as_handled()
		return
	if (
		event is InputEventMouseButton
		and not event.pressed
		and _slots.pointer.active()
		and _slots.pointer.drag_moved
		and event.button_index == _slots.pointer.drag_button
	):
		_slots.on_global_mouse_released(event.button_index)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		_slots.track_motion(event.global_position)
	if _pause != null and _pause.visible:
		if event.is_action_pressed(&"ui_cancel") and not event.is_echo():
			_pause.back()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(&"toggle_inventory") and not event.is_echo():
			get_viewport().set_input_as_handled()
		return
	if _storage_panel != null and bool(_storage_panel.call(&"is_open")):
		if event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_cancel"):
			_storage_panel.call(&"close")
			get_viewport().set_input_as_handled()
		return
	if _furnace_panel != null and bool(_furnace_panel.call(&"is_open")):
		if event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_cancel"):
			_furnace_panel.call(&"close")
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"toggle_build") and not event.is_echo():
		_set_build_open(not _build_open)
		get_viewport().set_input_as_handled()
	elif _build_open and event.is_action_pressed(&"ui_cancel") and not event.is_echo():
		_set_build_open(false)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"toggle_inventory") and not event.is_echo():
		_set_inventory_open(not _inventory_open)
		get_viewport().set_input_as_handled()
	elif _inventory_open and event.is_action_pressed(&"ui_cancel") and not event.is_echo():
		_set_inventory_open(false)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_cancel") and not event.is_echo():
		if _player != null and bool(_player.call(&"exit_build_mode")):
			get_viewport().set_input_as_handled()
		elif _pause != null:
			_pause.open()
			get_viewport().set_input_as_handled()


func _console_open() -> bool:
	var weather := get_tree().get_first_node_in_group(&"weather")
	return weather != null and bool(weather.get(&"console_open"))


func _unhandled_input(event: InputEvent) -> void:
	if _inventory == null or _console_open():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		if key >= KEY_1 and key <= KEY_9:
			var index := key - KEY_1
			if is_cursor_ui_open() and index != int(_inventory.selected_index):
				AudioManager.ui("select")
			_inventory.call(&"select_slot", index)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion:
		_slots.track_motion(event.global_position)
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if not button.pressed:
			_slots.on_global_mouse_released(button.button_index)


func _set_inventory_open(open: bool, announce: bool = true) -> void:
	if open == _inventory_open:
		return
	if open and _build_open:
		_set_build_open(false, false)
	_inventory_open = open
	_slots.set_inventory_open(open)
	_inv_panel.set_open(open)
	if open:
		PREVIEW.open(self)
		_slots.reset_pointer()
	else:
		_slots.cancel_drag()
		cancel_pending_crafts()
		_slots.stash_cursor_stack()
	set_hotbar_interactive(open or is_storage_open())
	_apply_menu_lock()
	if announce:
		AudioManager.ui("open" if open else "close")
	_slots.refresh_ghost()
	_refresh()


func _set_build_open(open: bool, announce: bool = true) -> void:
	if open == _build_open:
		return
	if open and _inventory_open:
		_set_inventory_open(false, false)
	_build_open = open
	if open:
		PREVIEW.open(self)
	_build_menu.set_open(open)
	_apply_menu_lock()
	if announce:
		AudioManager.ui("open" if open else "close")
	_sync_build_help()


func _on_build_piece_chosen(piece_id: String) -> void:
	_set_build_open(false, false)
	if _player != null:
		_player.call(&"begin_build", piece_id)
	get_viewport().set_input_as_handled()


func _apply_menu_lock() -> void:
	var open := _inventory_open or _build_open
	_crosshair.visible = not open
	if _player != null:
		_player.set(&"controls_locked", open)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED


func _refresh() -> void:
	var hotbar_size := int(_inventory.SLOT_COUNT)
	for slot in _hotbar_view.slots:
		_slots.fill_slot(slot, hotbar_size)
	for slot in _inv_panel.backpack_slots:
		_slots.fill_slot(slot, hotbar_size)
	_craft_catalog.refresh_cards()
	_build_menu.refresh_cards()
	_sync_build_help()


func _on_drag_visuals_changed() -> void:
	if _inventory_open or is_storage_open():
		_refresh()


func _bind_slot(slot, bucket: Array):
	slot.clicked.connect(_slots.on_clicked)
	slot.shift_clicked.connect(_slots.on_shift_clicked)
	slot.dropped_on.connect(_slots.on_dropped)
	slot.cancel_requested.connect(_on_slot_cancel)
	slot.primary_pressed.connect(_slots.on_primary_pressed)
	slot.primary_released.connect(_slots.on_primary_released)
	slot.secondary_pressed.connect(_slots.on_secondary_pressed)
	slot.secondary_released.connect(_slots.on_secondary_released)
	slot.pointer_entered.connect(_slots.on_pointer_entered.bind(slot))
	slot.mouse_exited.connect(AudioManager.ui_hover_exit.bind(slot))
	bucket.append(slot)
	return slot


func _apply_panel_bounds() -> void:
	var view := get_viewport().get_visible_rect().size
	_craft_catalog.set_columns(_inv_panel.apply_bounds(view))
	_build_menu.apply_bounds(view)


func _on_craft_changed() -> void:
	_slots.refresh_ghost()
	_refresh()


func _process(_delta: float) -> void:
	_slots.follow_mouse()


func _sync_build_help() -> void:
	_build_help.sync(_player, _inventory, _inventory_open, _build_open)


func _on_language() -> void:
	_apply_tr(self)
	_vitals.refresh_language()
	_sync_build_help()
	_craft_catalog.rebuild()
	_build_menu.rebuild_subs()
	_build_menu.rebuild_catalog()
	_refresh()


func _apply_tr(node: Node) -> void:
	if node.has_meta(&"key") and (node is Label or node is Button):
		node.set(&"text", tr(str(node.get_meta(&"key"))))
	for child in node.get_children():
		_apply_tr(child)


func _on_slot_cancel() -> void:
	pass


func _on_dim_clicked() -> void:
	_slots.stash_cursor_stack()
	_refresh()
	get_viewport().set_input_as_handled()
