extends RefCounted

const MAX_HUNGER := 100.0
const HUNGER_IDLE := 0.035
const HUNGER_WALK := 0.06
const HUNGER_RUN := 0.11
const HUNGER_SWIM := 0.13
const HUNGER_JUMP := 0.15
const HUNGER_CHOP := 0.35
const HUNGER_MINE := 0.35
const HUNGER_DIG := 0.35
const STARVATION_DPS := 2.0
const MOVE_THRESHOLD := 0.45

const MAT_DIRT := 1
const CELL := 1.0
const PLOT_MAX_SLOPE_DEG := 30.0

const WILD_NEAR_COUNT := 0
const WILD_NEAR_MIN := 8.0
const WILD_NEAR_MAX := 40.0
const WILD_CLEARANCE := 3.0
const WILD_SPACING := 2.6
const WILD_TREE_GAP := 1.6
const WILD_PRAIRIE := 0.5
const WILD_PRAIRIE_SOFT := 0.28
const WILD_TARGET := 0
const WILD_RESPAWN := 900.0
const WILD_WHEAT_QTY := 1
const WILD_SEEDS_MIN := 1
const WILD_SEEDS_MAX := 2
const WILD_FLAT := 1.05

const FOODS := {
	"bread": {"hunger": 40.0, "eat_time": 1.1},
	"raw_meat": {"hunger": 18.0, "eat_time": 1.0},
}

const CROPS := {
	"wheat": {
		"stage_seconds": [150.0, 150.0, 150.0, 150.0, 150.0, 150.0],
		"yield_id": "wheat",
		"yield_qty": 1,
		"seed_id": "wheat_seeds",
		"seeds_min": 2,
		"seeds_max": 3,
	},
}

const WHEAT_STAGE_SCENES: Array = [
	preload("res://scenes/visuals/wheat_stage_0.tscn"),
	preload("res://scenes/visuals/wheat_stage_1.tscn"),
	preload("res://scenes/visuals/wheat_stage_2.tscn"),
	preload("res://scenes/visuals/wheat_stage_3.tscn"),
	preload("res://scenes/visuals/wheat_stage_4.tscn"),
	preload("res://scenes/visuals/wheat_stage_5.tscn"),
]

const VISUALS := {
	"wheat_wild": WHEAT_STAGE_SCENES[5],
	"wheat_stage_0": WHEAT_STAGE_SCENES[0],
	"wheat_stage_1": WHEAT_STAGE_SCENES[1],
	"wheat_stage_2": WHEAT_STAGE_SCENES[2],
	"wheat_stage_3": WHEAT_STAGE_SCENES[3],
	"wheat_stage_4": WHEAT_STAGE_SCENES[4],
	"wheat_stage_5": WHEAT_STAGE_SCENES[5],
	"wheat_seeds": WHEAT_STAGE_SCENES[0],
	"wheat": preload("res://scenes/visuals/wheat.tscn"),
	"bread": preload("res://scenes/visuals/bread.tscn"),
}


static func cell_at(local: Vector3) -> Vector3i:
	return Vector3i(floori(local.x / CELL), floori(local.y / CELL), floori(local.z / CELL))


static func dominant_axis(direction: Vector3) -> int:
	var dom := 0
	if absf(direction.y) > absf(direction.x):
		dom = 1
	if absf(direction.z) > absf(direction[dom]):
		dom = 2
	return dom


static func surface_cell(local: Vector3, radius: float) -> Vector3i:
	var dir := local
	if dir.length_squared() < 0.001:
		dir = Vector3.UP
	dir = dir.normalized()
	var dom := dominant_axis(dir)
	var u := (dom + 1) % 3
	var v := (dom + 2) % 3
	var cell := Vector3i.ZERO
	cell[u] = floori(local[u] / CELL)
	cell[v] = floori(local[v] / CELL)
	var cu := (float(cell[u]) + 0.5) * CELL
	var cv := (float(cell[v]) + 0.5) * CELL
	var nd := dir[dom]
	if absf(nd) < 0.25:
		nd = 0.25 if nd >= 0.0 else -0.25
	var cd := (radius - dir[u] * cu - dir[v] * cv) / nd
	cell[dom] = floori(cd / CELL)
	return cell


static func tangent_halves(normal: Vector3) -> Array:
	var n := normal.normalized()
	if n.length_squared() < 0.01:
		n = Vector3.UP
	var dom := dominant_axis(n)
	var u := (dom + 1) % 3
	var v := (dom + 2) % 3
	var step_u := Vector3.ZERO
	var step_v := Vector3.ZERO
	step_u[u] = CELL
	step_v[v] = CELL
	var nd := n[dom]
	if absf(nd) < 0.25:
		var axis_u := Vector3.ZERO
		var axis_v := Vector3.ZERO
		axis_u[u] = 1.0
		axis_v[v] = 1.0
		return [(axis_u - n * axis_u.dot(n)) * 0.5, (axis_v - n * axis_v.dot(n)) * 0.5]
	step_u[dom] = -n[u] * CELL / nd
	step_v[dom] = -n[v] * CELL / nd
	return [step_u * 0.5, step_v * 0.5]


static func cell_on_plane(cell: Vector3i, normal: Vector3, radius: float) -> Vector3:
	var n := normal.normalized()
	if n.length_squared() < 0.01:
		n = Vector3.UP
	var dom := dominant_axis(n)
	var u := (dom + 1) % 3
	var v := (dom + 2) % 3
	var center := Vector3.ZERO
	center[u] = (float(cell[u]) + 0.5) * CELL
	center[v] = (float(cell[v]) + 0.5) * CELL
	var nd := n[dom]
	if absf(nd) < 0.25:
		var raw := Vector3(cell) + Vector3.ONE * 0.5
		return raw - n * (raw.dot(n) - radius)
	center[dom] = (radius - n[u] * center[u] - n[v] * center[v]) / nd
	return center


static func scene_for(resource_id: String) -> PackedScene:
	if not VISUALS.has(resource_id):
		return null
	return VISUALS[resource_id] as PackedScene


static func food_hunger(resource_id: String) -> float:
	if not FOODS.has(resource_id):
		return 0.0
	return float((FOODS[resource_id] as Dictionary).get("hunger", 0.0))


static func eat_time(resource_id: String) -> float:
	if not FOODS.has(resource_id):
		return 0.0
	return float((FOODS[resource_id] as Dictionary).get("eat_time", 0.0))


static func is_food(resource_id: String) -> bool:
	return FOODS.has(resource_id)


static func crop_known(crop_id: String) -> bool:
	return CROPS.has(crop_id)


static func stage_index(crop_id: String, planted_at: float, now: float) -> int:
	if not CROPS.has(crop_id) or planted_at < 0.0:
		return -1
	var seconds: Array = (CROPS[crop_id] as Dictionary).get("stage_seconds", [])
	if seconds.is_empty():
		return -1
	var elapsed := maxf(now - planted_at, 0.0)
	var acc := 0.0
	for i in seconds.size():
		acc += float(seconds[i])
		if elapsed < acc:
			return i
	return seconds.size() - 1


static func is_mature(crop_id: String, planted_at: float, now: float) -> bool:
	var seconds: Array = []
	if CROPS.has(crop_id):
		seconds = (CROPS[crop_id] as Dictionary).get("stage_seconds", [])
	if seconds.is_empty():
		return false
	return stage_index(crop_id, planted_at, now) == seconds.size() - 1


static func stage_scene(crop_id: String, stage: int) -> PackedScene:
	if crop_id == "wheat" and stage >= 0 and stage < WHEAT_STAGE_SCENES.size():
		return WHEAT_STAGE_SCENES[stage] as PackedScene
	return scene_for("%s_stage_%d" % [crop_id, stage])


static func wild_key(direction: Vector3) -> String:
	var dir := direction.normalized()
	return "%d_%d_%d" % [int(round(dir.x * 1000.0)), int(round(dir.y * 1000.0)), int(round(dir.z * 1000.0))]


static func wild_drops() -> Array:
	return [
		{"id": "wheat", "qty": WILD_WHEAT_QTY},
		{"id": "wheat_seeds", "qty": randi_range(WILD_SEEDS_MIN, WILD_SEEDS_MAX)},
	]


static func crop_drops(crop_id: String) -> Array:
	if not CROPS.has(crop_id):
		return []
	var data: Dictionary = CROPS[crop_id]
	return [
		{"id": str(data.get("yield_id", "")), "qty": int(data.get("yield_qty", 1))},
		{"id": str(data.get("seed_id", "")), "qty": randi_range(int(data.get("seeds_min", 1)), int(data.get("seeds_max", 1)))},
	]
