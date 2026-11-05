extends CharacterBody3D
class_name Player

const INVENTORY_SCRIPT := preload("res://scripts/player/inventory.gd")
const TOTEM := preload("res://scripts/machines/camp_totem.gd")
const BUILD_CATALOG := preload("res://scripts/building/build_catalog.gd")
const FARM := preload("res://scripts/farming/farming_config.gd")
const PlayerVitals := preload("res://scripts/player/player_vitals.gd")
const PlayerBuildMode := preload("res://scripts/player/player_build_mode.gd")
const PlayerTools := preload("res://scripts/player/player_tools.gd")
const PlayerLocomotion := preload("res://scripts/player/player_locomotion.gd")
const PlayerInteract := preload("res://scripts/player/player_interact.gd")

@export var walk_speed: float = 5.0
@export var run_speed: float = 8.5
@export var acceleration: float = 18.0
@export var deceleration: float = 22.0
@export var jump_velocity: float = 4.8
@export var rotation_speed: float = 12.0
@export var hit_range: float = 3.2
@export var aim_radius: float = 1.25
@export var hit_cooldown: float = 0.54
@export var punch_duration: float = 0.34
@export var impact_ratio: float = 0.4
@export var pickup_radius: float = 2.2
@export var pickup_collect_distance: float = 0.45
@export var place_distance: float = 2.4
@export var place_clearance: float = 1.75
@export var max_health: float = 100.0

signal health_changed(current: float, maximum: float)
signal hunger_changed(current: float, maximum: float)
signal build_mode_changed

var _vitals: PlayerVitals = PlayerVitals.new()
var _build: PlayerBuildMode = PlayerBuildMode.new()
var _tools: PlayerTools = PlayerTools.new()
var _loco: PlayerLocomotion = PlayerLocomotion.new()
var _interact: PlayerInteract = PlayerInteract.new()

var health: float:
	get:
		return _vitals.health
	set(value):
		_vitals.health = value

var max_hunger: float:
	get:
		return _vitals.max_hunger
	set(value):
		_vitals.max_hunger = value

var hunger: float:
	get:
		return _vitals.hunger
	set(value):
		_vitals.hunger = value

var build_piece: String:
	get:
		return _build.build_piece
	set(value):
		_build.build_piece = value

var demolish_mode: bool:
	get:
		return _build.demolish_mode
	set(value):
		_build.demolish_mode = value

var punch_weight: float:
	get:
		return _tools.punch_weight
	set(value):
		_tools.punch_weight = value

var punch_phase: float:
	get:
		return _tools.punch_phase
	set(value):
		_tools.punch_phase = value

var tool_held: bool:
	get:
		return _tools.tool_held
	set(value):
		_tools.tool_held = value

var airborne: bool:
	get:
		return _loco.airborne
	set(value):
		_loco.airborne = value

var jumping: bool:
	get:
		return _loco.jumping
	set(value):
		_loco.jumping = value

var swimming: bool:
	get:
		return _loco.swimming
	set(value):
		_loco.swimming = value

var swim_moving: bool:
	get:
		return _loco.swim_moving
	set(value):
		_loco.swim_moving = value

var underwater: bool:
	get:
		return _loco.underwater
	set(value):
		_loco.underwater = value

var planar_speed: float:
	get:
		return _loco.planar_speed
	set(value):
		_loco.planar_speed = value

var radial_speed: float:
	get:
		return _loco.radial_speed
	set(value):
		_loco.radial_speed = value

var inventory: Node
var _controls_locked := false
var _dead := false
var _totem_respawn_queued := false
var _death_position := Vector3.ZERO
var _planet: Node3D
var _ignore_punch := false

var controls_locked: bool:
	get:
		return _controls_locked or _dead
	set(value):
		_controls_locked = value

var is_dead: bool:
	get:
		return _dead

var _eating: bool:
	get:
		return _vitals.eating


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	collision_mask = 1 | 8
	_planet = get_tree().get_first_node_in_group(&"planet")
	inventory = INVENTORY_SCRIPT.new()
	inventory.name = "Inventory"
	add_child(inventory)
	if not SaveManager.has_player_state():
		inventory.call(&"add_resource", "stone_shovel", 1)
		inventory.call(&"add_resource", "wooden_pickaxe", 1)
		inventory.call(&"add_resource", "wooden_axe", 1)
		inventory.call(&"add_resource", "wooden_hoe", 1)
		var chest_cost: Dictionary = BUILD_CATALOG.ingredients_of("wood_chest")
		for resource_id in chest_cost:
			inventory.call(&"add_resource", str(resource_id), int(chest_cost[resource_id]) * 2)
	_vitals.health_changed.connect(func(current: float, maximum: float) -> void:
		health_changed.emit(current, maximum)
	)
	_vitals.hunger_changed.connect(func(current: float, maximum: float) -> void:
		hunger_changed.emit(current, maximum)
	)
	_vitals.setup(max_health, FARM.MAX_HUNGER)
	_build.setup(self)
	_build.mode_changed.connect(func() -> void:
		build_mode_changed.emit()
	)
	_tools.setup(self)
	_loco.setup(self)
	_interact.setup(self)


func _input(event: InputEvent) -> void:
	if _build.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if _handle_hotbar_wheel(event):
		get_viewport().set_input_as_handled()


func _handle_hotbar_wheel(event: InputEvent) -> bool:
	if controls_locked or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	if _weather_console_open():
		return false
	if inventory == null or not event is InputEventMouseButton:
		return false
	var button := event as InputEventMouseButton
	if not button.pressed:
		return false
	if _build.blocks_hotbar_wheel(event):
		return false
	if button.button_index == MOUSE_BUTTON_WHEEL_UP:
		inventory.call(&"cycle_slot", -1)
		return true
	if button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		inventory.call(&"cycle_slot", 1)
		return true
	return false


func _weather_console_open() -> bool:
	var weather := get_tree().get_first_node_in_group(&"weather")
	return weather != null and bool(weather.get(&"console_open"))


func _unhandled_input(event: InputEvent) -> void:
	if controls_locked:
		return

	if event.is_action_pressed(&"interact"):
		_interact.try_interact()
		return

	if event is InputEventMouseButton:
		var plant_button := event as InputEventMouseButton
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and plant_button.button_index == MOUSE_BUTTON_RIGHT:
			if str(_tools.selected_use()) == "bow":
				if plant_button.pressed:
					if _tools.begin_bow_aim():
						get_viewport().set_input_as_handled()
				else:
					_tools.cancel_bow_aim()
					get_viewport().set_input_as_handled()
				return
			if plant_button.pressed:
				if _interact.try_open_aimed_furnace():
					get_viewport().set_input_as_handled()
					return
				if _tools.try_plant_plot():
					get_viewport().set_input_as_handled()
					return

	if event.is_action_pressed(&"ui_cancel"):
		if _tools.is_bow_aiming():
			_tools.cancel_bow_aim()
		_toggle_mouse_capture()
		return

	if event.is_action_released(&"punch"):
		_ignore_punch = false
		if str(_tools.selected_use()) == "bow" and _tools.is_bow_aiming():
			_tools.release_bow_draw()
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(&"punch") and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_ignore_punch = true
		return

	if (
		event.is_action_pressed(&"punch")
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		and str(_tools.selected_use()) == "bow"
		and _tools.is_bow_aiming()
	):
		if _tools.begin_bow_draw():
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_ignore_punch = true
			return


func _physics_process(delta: float) -> void:
	if _dead:
		_loco.tick(delta)
		return
	_tools.tick(delta)
	_vitals.update_eat(delta, controls_locked, _tools.selected_id(), inventory)
	_regenerate(delta)
	_interact.collect_nearby()
	if not _build.tick():
		if (
			not controls_locked
			and not _ignore_punch
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			and Input.is_action_pressed(&"punch")
		):
			_tools.try_punch()
	_loco.tick(delta)


func _get_surface_up() -> Vector3:
	return _loco.surface_up()


func _walk_radius(world_offset: Vector3) -> float:
	return _loco.walk_radius(world_offset)


func begin_build(piece_id: String) -> void:
	_build.begin(piece_id)


func cancel_build() -> void:
	_build.cancel()


func exit_build_mode() -> bool:
	return _build.exit()


func _begin_eat() -> void:
	_vitals.begin_eat(_tools.selected_id(), inventory)


func _update_hunger(delta: float) -> void:
	if _dead:
		return
	_vitals.tick_hunger(delta, swimming, planar_speed)
	_try_begin_death()


func _spend_hunger(amount: float) -> void:
	if _dead:
		return
	_vitals.spend_hunger(amount)


func apply_damage(amount: float) -> bool:
	if _dead or amount <= 0.0 or TOTEM.is_player_in_safe_zone():
		return false
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health)
	_try_begin_death()
	return true


func _regenerate(delta: float) -> void:
	if _dead or hunger <= 0.0 or health >= max_health:
		return
	var rate := TOTEM.current_regen_per_second()
	if rate <= 0.0:
		return
	health = minf(health + rate * delta, max_health)
	health_changed.emit(health, max_health)


func resolve_death_after_load() -> void:
	if _dead:
		_death_position = global_position
		if not _totem_respawn_queued:
			_totem_respawn_queued = true
			call_deferred(&"_attempt_totem_respawn")
		return
	_try_begin_death()


func _try_begin_death() -> bool:
	if _dead or health > 0.0:
		return false
	_dead = true
	_controls_locked = true
	_death_position = global_position
	if not _totem_respawn_queued:
		_totem_respawn_queued = true
		call_deferred(&"_attempt_totem_respawn")
	return true


func _attempt_totem_respawn() -> void:
	_totem_respawn_queued = false
	if not _dead:
		return
	if _planet == null:
		push_warning("EscapeAstra: respawn skipped (planet missing)")
		return
	var totem := TOTEM.pick_closest(_death_position)
	if totem != null:
		if _planet.has_method(&"place_player_near_world") and bool(
			_planet.call(&"place_player_near_world", self, totem.global_position)
		):
			_finish_respawn()
			return
		push_warning("EscapeAstra: totem respawn failed (no safe surface near totem)")
		return
	if not _planet.has_method(&"place_player_random") or not bool(_planet.call(&"place_player_random", self)):
		push_warning("EscapeAstra: random respawn failed (no safe land)")
		return
	_finish_respawn()


func _finish_respawn() -> void:
	health = max_health
	health_changed.emit(health, max_health)
	hunger = max_hunger
	hunger_changed.emit(hunger, max_hunger)
	_dead = false
	_controls_locked = false


func _toggle_mouse_capture() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
