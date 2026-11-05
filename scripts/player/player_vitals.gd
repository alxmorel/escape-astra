extends RefCounted
class_name PlayerVitals

const FARM := preload("res://scripts/farming/farming_config.gd")

signal health_changed(current: float, maximum: float)
signal hunger_changed(current: float, maximum: float)

var health: float = 100.0
var max_health: float = 100.0
var hunger: float = 100.0
var max_hunger: float = 100.0
var eating := false

var _eat_id := ""
var _eat_left := 0.0


func setup(hp_max: float, hunger_max: float) -> void:
	max_health = hp_max
	health = hp_max
	max_hunger = hunger_max
	hunger = hunger_max
	health_changed.emit(health, max_health)
	hunger_changed.emit(hunger, max_hunger)


func spend_hunger(amount: float) -> void:
	if amount <= 0.0 or hunger <= 0.0:
		return
	hunger = maxf(hunger - amount, 0.0)
	hunger_changed.emit(hunger, max_hunger)


func add_hunger(amount: float) -> void:
	if amount <= 0.0:
		return
	hunger = minf(hunger + amount, max_hunger)
	hunger_changed.emit(hunger, max_hunger)


func apply_starvation(dps: float, delta: float) -> void:
	if hunger > 0.0 or health <= 0.0 or dps <= 0.0:
		return
	var next := maxf(health - dps * delta, 0.0)
	if next == health:
		return
	health = next
	health_changed.emit(health, max_health)


func begin_eat(item_id: String, inventory) -> bool:
	if item_id.is_empty() or not FARM.is_food(item_id) or inventory == null:
		return false
	if int(inventory.call(&"get_amount", item_id)) <= 0:
		return false
	eating = true
	_eat_id = item_id
	_eat_left = FARM.eat_time(item_id)
	return true


func update_eat(delta: float, controls_locked: bool, selected_id: String, inventory) -> void:
	if not eating:
		return
	if controls_locked or selected_id != _eat_id:
		eating = false
		return
	_eat_left -= delta
	if _eat_left > 0.0:
		return
	eating = false
	if inventory == null or int(inventory.call(&"get_amount", _eat_id)) <= 0:
		return
	inventory.call(&"add_resource", _eat_id, -1)
	add_hunger(FARM.food_hunger(_eat_id))


func hunger_rate(swimming: bool, planar_speed: float) -> float:
	if swimming:
		return FARM.HUNGER_SWIM
	var moving := planar_speed > FARM.MOVE_THRESHOLD
	if moving and Input.is_action_pressed(&"sprint"):
		return FARM.HUNGER_RUN
	if moving:
		return FARM.HUNGER_WALK
	return FARM.HUNGER_IDLE


func tick_hunger(delta: float, swimming: bool, planar_speed: float) -> void:
	spend_hunger(hunger_rate(swimming, planar_speed) * delta)
	apply_starvation(FARM.STARVATION_DPS, delta)


func export_state() -> Dictionary:
	return {
		"health": health,
		"max_health": max_health,
		"hunger": hunger,
		"max_hunger": max_hunger,
	}


func import_state(data: Dictionary) -> void:
	max_health = float(data.get("max_health", max_health))
	health = float(data.get("health", health))
	max_hunger = float(data.get("max_hunger", max_hunger))
	hunger = float(data.get("hunger", hunger))
	health_changed.emit(health, max_health)
	hunger_changed.emit(hunger, max_hunger)
