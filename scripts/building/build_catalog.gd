extends RefCounted

# Une pièce = une entrée de PIECES + un profil dans _make_defs (forme, sockets, occupancy).

const TILE := 3.0
const FLOOR_H := 0.42
const WALL_H := 2.6
const THICK := 0.22
const CEIL_H := 0.26

const MATERIALS := {
	"wood": {
		"color": Color(0.62, 0.42, 0.2),
		"seam": Color(0.44, 0.28, 0.13),
	},
	"stone": {
		"color": Color(0.58, 0.59, 0.62),
		"seam": Color(0.4, 0.41, 0.44),
	},
}

const PIECES: Array[Dictionary] = [
	{"id": "wood_foundation", "name": "Wood Foundation", "kind": "foundation", "material": "wood", "cost_id": "wood_planks", "cost": 20},
	{"id": "wood_wall", "name": "Wood Wall", "kind": "wall", "material": "wood", "cost_id": "wood_planks", "cost": 10},
	{"id": "wood_window_wall", "name": "Wood Window Wall", "kind": "window_wall", "material": "wood", "cost_id": "wood_planks", "cost": 8},
	{"id": "wood_door_wall", "name": "Wood Door Wall", "kind": "door_wall", "material": "wood", "cost_id": "wood_planks", "cost": 8},
	{"id": "wood_stairs", "name": "Wood Stairs", "kind": "stairs", "material": "wood", "cost_id": "wood_planks", "cost": 12},
	{"id": "wood_floor", "name": "Wood Floor", "kind": "floor", "material": "wood", "cost_id": "wood_planks", "cost": 16},
	{"id": "wood_ceiling", "name": "Wood Ceiling", "kind": "ceiling", "material": "wood", "cost_id": "wood_planks", "cost": 10},
	{"id": "stone_foundation", "name": "Stone Foundation", "kind": "foundation", "material": "stone", "cost_id": "stone", "cost": 20},
	{"id": "stone_wall", "name": "Stone Wall", "kind": "wall", "material": "stone", "cost_id": "stone", "cost": 15},
	{"id": "stone_window_wall", "name": "Stone Window Wall", "kind": "window_wall", "material": "stone", "cost_id": "stone", "cost": 12},
	{"id": "stone_door_wall", "name": "Stone Door Wall", "kind": "door_wall", "material": "stone", "cost_id": "stone", "cost": 12},
	{"id": "stone_stairs", "name": "Stone Stairs", "kind": "stairs", "material": "stone", "cost_id": "stone", "cost": 16},
	{"id": "stone_floor", "name": "Stone Floor", "kind": "floor", "material": "stone", "cost_id": "stone", "cost": 16},
	{"id": "stone_ceiling", "name": "Stone Ceiling", "kind": "ceiling", "material": "stone", "cost_id": "stone", "cost": 15},
	{"id": "wood_chest", "name": "Wood Chest", "kind": "chest", "material": "wood", "cost_id": "wood_planks", "cost": 20, "category": "Storage", "subcategory": "Storage"},
	{"id": "wood_double_chest", "name": "Double Chest", "kind": "double_chest", "material": "wood", "craft": false},
]

static var _by_id: Dictionary = {}
static var _defs: Dictionary = {}


static func has_piece(piece_id: String) -> bool:
	return _index().has(piece_id)


static func display_name(piece_id: String) -> String:
	return str(_index().get(piece_id, {}).get("name", ""))


static func kind_of(piece_id: String) -> String:
	return str(_index().get(piece_id, {}).get("kind", ""))


static func material_of(piece_id: String) -> String:
	return str(_index().get(piece_id, {}).get("material", ""))


static func material_style(material_id: String) -> Dictionary:
	return MATERIALS.get(material_id, MATERIALS["wood"])


static func requires_snap(kind: String) -> bool:
	return bool(_def(kind).get("requires_snap", true))


static func preview_lift(kind: String) -> float:
	return float(_def(kind).get("preview_lift", 0.0))


static func occupancy_of(kind: String) -> String:
	return str(_def(kind).get("occupancy", kind))


static func occupancy_radius(kind: String) -> float:
	return float(_def(kind).get("radius", 1.0))


static func sockets_of(kind: String) -> Array:
	return (_def(kind).get("sockets", []) as Array).duplicate(true)


static func solids_of(kind: String) -> Array:
	return (_def(kind).get("solids", []) as Array).duplicate(true)


static func walkable_of(kind: String) -> bool:
	return bool(_def(kind).get("walkable", false))


static func aim_height(kind: String) -> float:
	match kind:
		"wall", "window_wall", "door_wall":
			return 1.3
		"stairs":
			return 0.9
		"ceiling", "floor":
			return 0.15
		"chest", "double_chest":
			return 0.4
		_:
			return 0.3


const KIND_SUBCATEGORY := {
	"foundation": "Foundations",
	"wall": "Walls",
	"window_wall": "Openings",
	"door_wall": "Openings",
	"floor": "Floors",
	"ceiling": "Floors",
	"stairs": "Stairs",
	"chest": "Storage",
	"double_chest": "Storage",
}

static func ingredients_of(piece_id: String) -> Dictionary:
	var piece: Dictionary = _index().get(piece_id, {})
	if piece.is_empty() or not piece.has("cost_id"):
		return {}
	return {str(piece["cost_id"]): int(piece.get("cost", 0))}


static func refund_of(piece_id: String) -> Dictionary:
	if piece_id == "wood_double_chest":
		var single := ingredients_of("wood_chest")
		var doubled := {}
		for resource_id in single:
			doubled[resource_id] = int(single[resource_id]) * 2
		return doubled
	return ingredients_of(piece_id)


static func recipes() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for piece in PIECES:
		if not bool(piece.get("craft", true)):
			continue
		var ingredients := ingredients_of(str(piece["id"]))
		if ingredients.is_empty():
			continue
		var kind := str(piece["kind"])
		var subcategory := str(piece.get("subcategory", KIND_SUBCATEGORY.get(kind, "")))
		var category := str(piece.get("category", "Storage" if subcategory == "Storage" else "Construction"))
		list.append({
			"result_id": str(piece["id"]),
			"result_amount": 1,
			"category": category,
			"subcategory": subcategory,
			"ingredients": ingredients,
		})
	return list


static func _index() -> Dictionary:
	if _by_id.is_empty():
		for piece in PIECES:
			_by_id[str(piece["id"])] = piece
	return _by_id


static func _def(kind: String) -> Dictionary:
	return defs().get(kind, {})


static func defs() -> Dictionary:
	if _defs.is_empty():
		_defs = _make_defs()
	return _defs


static func _make_defs() -> Dictionary:
	var wall_sockets := _wall_sockets()
	return {
		"foundation": {
			"occupancy": "foundation",
			"walkable": true,
			"radius": 2.05,
			"requires_snap": false,
			"preview_lift": 0.0,
			"elevate": true,
			"sockets": _foundation_sockets(),
			"solids": [_slab_solid(FLOOR_H)],
		},
		"wall": {
			"occupancy": "wall",
			"radius": 1.05,
			"requires_snap": true,
			"preview_lift": 0.0,
			"sockets": wall_sockets,
			"solids": [_wall_box()],
		},
		"window_wall": {
			"occupancy": "wall",
			"radius": 1.05,
			"requires_snap": true,
			"preview_lift": 0.0,
			"sockets": wall_sockets.duplicate(true),
			"solids": _window_solids(),
		},
		"door_wall": {
			"occupancy": "wall",
			"radius": 1.05,
			"requires_snap": true,
			"preview_lift": 0.0,
			"sockets": _door_sockets(),
			"solids": _door_solids(),
		},
		"stairs": {
			"occupancy": "stair",
			"walkable": true,
			"radius": 1.15,
			"requires_snap": true,
			"preview_lift": 0.0,
			"sockets": [
				_socket("stair", "mount", "plug", Vector3.ZERO, Vector3(0, 0, 1)),
				_socket("stairs_top", "mount", "plug", Vector3.ZERO, Vector3(0, 0, 1)),
				_socket("floor_top", "mount", "host", Vector3.ZERO, Vector3(0, 0, 1)),
				_socket("foundation", "meet", "host", Vector3(0, -stair_rise() - _slab_top(), stair_run()), Vector3(0, 0, 1)),
				_socket("floor", "meet", "host", Vector3(0, -stair_rise() - _slab_top(), stair_run()), Vector3(0, 0, 1)),
			],
			"solids": [],
		},
		"floor": {
			"occupancy": "floor",
			"walkable": true,
			"radius": 2.05,
			"requires_snap": true,
			"preview_lift": FLOOR_H + WALL_H,
			"sockets": _floor_sockets(),
			"solids": [_slab_solid(FLOOR_H)],
		},
		"ceiling": {
			"occupancy": "ceiling",
			"walkable": true,
			"radius": 2.05,
			"requires_snap": true,
			"preview_lift": FLOOR_H + WALL_H,
			"sockets": _edge_sockets("ceiling", "mount", "plug", 0.0),
			"solids": [_solid(Vector3(0, CEIL_H * 0.5 - 0.05, 0), Vector3(TILE + THICK, CEIL_H, TILE + THICK))],
		},
		"chest": {
			"occupancy": "chest",
			"radius": 0.62,
			"requires_snap": false,
			"preview_lift": 0.0,
			"sockets": _chest_sockets(0.54),
			"solids": [_solid(Vector3(0, 0.39, 0), Vector3(1.08, 0.78, 0.66))],
		},
		"double_chest": {
			"occupancy": "chest",
			"radius": 1.08,
			"requires_snap": false,
			"preview_lift": 0.0,
			"sockets": [],
			"solids": [_solid(Vector3(0, 0.39, 0), Vector3(2.16, 0.78, 0.66))],
		},
	}


static func _foundation_sockets() -> Array:
	var sockets := _edge_sockets("foundation", "meet", "both", 0.0)
	sockets.append_array(_edge_sockets("wall_base", "mount", "host", FLOOR_H))
	sockets.append_array(_edge_sockets("stair", "mount", "host", FLOOR_H))
	return sockets


static func _floor_sockets() -> Array:
	var top := _slab_top()
	var sockets := _edge_sockets("floor", "meet", "both", 0.0)
	sockets.append_array(_edge_sockets("wall_base", "mount", "host", top))
	sockets.append_array(_edge_sockets("stair", "mount", "host", top))
	sockets.append_array(_edge_sockets("ceiling", "mount", "plug", 0.0))
	sockets.append_array(_edge_sockets("floor_top", "mount", "plug", top))
	return sockets


static func _wall_sockets() -> Array:
	var arrival := stair_rise()
	var inward := -stair_run() * 0.5
	return [
		_socket("wall_base", "mount", "plug", Vector3.ZERO, Vector3(0, 0, 1)),
		_socket("ceiling", "mount", "host", Vector3(0, stair_rise(), 0), Vector3(0, 0, 1)),
		_socket("stairs_top", "mount", "host", Vector3(-stair_run() * 0.5, arrival, inward), Vector3(1, 0, 0)),
		_socket("stairs_top", "mount", "host", Vector3(stair_run() * 0.5, arrival, inward), Vector3(-1, 0, 0)),
	]


static func _door_sockets() -> Array:
	var sockets: Array = _wall_sockets().duplicate(true)
	# Socket prêt pour une future porte ouvrable, sans pièce pour l'instant.
	sockets.append(_socket("door", "mount", "host", Vector3(0, 1.0, 0.06), Vector3(0, 0, -1)))
	return sockets


static func _door_solids() -> Array:
	var opening_w := 1.4
	var header_h := 0.52
	var side_w := (TILE - opening_w) * 0.5
	var side_x := opening_w * 0.5 + side_w * 0.5
	var post_top := WALL_H - header_h
	var post_bottom := -0.04
	var header_bottom := post_top - 0.02
	return [
		_solid(Vector3(-side_x, (post_bottom + post_top) * 0.5, 0), Vector3(side_w, post_top - post_bottom, THICK)),
		_solid(Vector3(side_x, (post_bottom + post_top) * 0.5, 0), Vector3(side_w, post_top - post_bottom, THICK)),
		_solid(Vector3(0, (header_bottom + WALL_H) * 0.5, 0), Vector3(TILE, WALL_H - header_bottom, THICK)),
	]


static func _window_solids() -> Array:
	var opening_w := TILE * 0.52
	var header_h := WALL_H * 0.2
	var sill_h := WALL_H * 0.3
	var side_w := (TILE - opening_w) * 0.5
	var side_x := opening_w * 0.5 + side_w * 0.5
	var post_top := WALL_H - header_h
	var post_bottom := -0.04
	var sill_bottom := -0.04
	var header_bottom := post_top - 0.02
	return [
		_solid(Vector3(-side_x, (post_bottom + post_top) * 0.5, 0), Vector3(side_w, post_top - post_bottom, THICK)),
		_solid(Vector3(side_x, (post_bottom + post_top) * 0.5, 0), Vector3(side_w, post_top - post_bottom, THICK)),
		_solid(Vector3(0, (sill_bottom + sill_h) * 0.5, 0), Vector3(opening_w, sill_h - sill_bottom, THICK)),
		_solid(Vector3(0, (header_bottom + WALL_H) * 0.5, 0), Vector3(TILE, WALL_H - header_bottom, THICK)),
	]


static func _edge_sockets(link: String, join: String, role: String, height: float) -> Array:
	var half := TILE * 0.5
	return [
		_socket(link, join, role, Vector3(half, height, 0), Vector3(1, 0, 0)),
		_socket(link, join, role, Vector3(-half, height, 0), Vector3(-1, 0, 0)),
		_socket(link, join, role, Vector3(0, height, half), Vector3(0, 0, 1)),
		_socket(link, join, role, Vector3(0, height, -half), Vector3(0, 0, -1)),
	]


static func _chest_sockets(half: float) -> Array:
	return [
		_socket("chest_side", "meet", "both", Vector3(-half, 0.39, 0), Vector3(-1, 0, 0)),
		_socket("chest_side", "meet", "both", Vector3(half, 0.39, 0), Vector3(1, 0, 0)),
	]


static func _socket(link: String, join: String, role: String, position: Vector3, direction: Vector3) -> Dictionary:
	return {
		"link": link,
		"join": join,
		"role": role,
		"position": position,
		"direction": direction,
	}


static func _solid(position: Vector3, size: Vector3) -> Dictionary:
	return {"position": position, "size": size}


static func _slab_solid(height: float) -> Dictionary:
	return _solid(Vector3(0, height * 0.5, 0), Vector3(TILE, height, TILE))


static func _wall_box() -> Dictionary:
	return _solid(Vector3(0, (WALL_H - 0.04) * 0.5, 0), Vector3(TILE, WALL_H + 0.04, THICK))


static func _top_y(solid: Dictionary) -> float:
	var pos: Vector3 = solid["position"]
	var size: Vector3 = solid["size"]
	return pos.y + size.y * 0.5


static func _slab_top() -> float:
	return _top_y(_slab_solid(FLOOR_H))


static func stair_rise() -> float:
	return _top_y(_wall_box())


static func stair_run() -> float:
	var size: Vector3 = _wall_box()["size"]
	return maxf(size.x, size.z)


static func stair_steps() -> int:
	return clampi(int(round(stair_rise() / _slab_top())), 2, 14)


static func max_foundation_lift() -> float:
	return maxf(top_of("wall") - top_of("foundation"), 0.0)


const ACTION_TEXT := {
	"mode_destroy": "[C] Destruction",
	"mode_build": "[C] Construction",
	"place": "[LMB] Placer",
	"rotate": "[R] Rotation",
	"elevate": "[Shift + Molette] Élévation",
	"cancel": "[Échap] Annuler",
	"dismantle": "[LMB] Démonter",
}


static func elevates(kind: String) -> bool:
	return bool(_def(kind).get("elevate", false))


static func build_actions(kind: String, demolish: bool = false) -> PackedStringArray:
	if demolish:
		return PackedStringArray(["mode_build", "dismantle", "cancel"])
	var actions := PackedStringArray(["mode_destroy", "place", "rotate"])
	if elevates(kind):
		actions.append("elevate")
	actions.append("cancel")
	return actions


static func action_text(action: String) -> String:
	var key := "BUILD_" + action.to_upper()
	var translated := TranslationServer.translate(key)
	if translated != key:
		return translated
	return str(ACTION_TEXT.get(action, ""))


static func top_of(kind: String) -> float:
	var best := 0.0
	for solid in solids_of(kind):
		best = maxf(best, _top_y(solid))
	return best
