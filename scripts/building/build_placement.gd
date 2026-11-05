extends RefCounted

const CATALOG := preload("res://scripts/building/build_catalog.gd")
const PIECE := preload("res://scripts/building/build_piece.gd")

const SNAP_RADIUS := 2.75


static func solve(tree: SceneTree, planet: Node3D, item_id: String, aim: Transform3D, rotation: int, player_pos: Vector3, height: float) -> Dictionary:
	var kind := CATALOG.kind_of(item_id)
	if kind == "chest":
		var deck := _deck_pose(tree, planet, aim, rotation, player_pos)
		if not deck.is_empty():
			return deck
	var plugs := CATALOG.sockets_of(kind)
	var forward := -aim.basis.z
	var pool: Array = []
	for node in tree.get_nodes_in_group(&"construction"):
		var host := node as Node3D
		if host == null or not host.has_method(&"is_socket_free"):
			continue
		var host_sockets: Array = host.get("sockets")
		var options: Array = []
		var closest_front := INF
		for host_index in host_sockets.size():
			var host_socket: Dictionary = host_sockets[host_index]
			if not _is_host(host_socket):
				continue
			for plug_index in plugs.size():
				var plug: Dictionary = plugs[plug_index]
				if not _is_plug(plug):
					continue
				if str(plug["link"]) != str(host_socket["link"]) or str(plug["join"]) != str(host_socket["join"]):
					continue
				if str(plug["join"]) == "meet" and (plug["direction"] as Vector3).dot(host_socket["direction"]) > -0.9:
					continue
				var xform := _align(host, host_socket, plug)
				if xform.basis.y.dot(host.global_basis.y) < 0.9:
					continue
				if aim.origin.distance_to(xform.origin) > 8.0:
					continue
				var score := _planar(aim.origin, xform.origin, aim.basis.y)
				if _in_front(xform.origin, player_pos, forward, aim.basis.y) and score < closest_front:
					closest_front = score
				options.append({
					"transform": xform,
					"host": host,
					"host_index": host_index,
					"plug_index": plug_index,
					"link": str(host_socket["link"]),
					"angle": _angle_around(host, xform.origin, aim.origin),
				})
		if options.is_empty() or closest_front > SNAP_RADIUS:
			continue
		pool.append_array(options)
	if pool.is_empty():
		var free := _spin(aim, rotation)
		var lift := CATALOG.preview_lift(kind)
		if CATALOG.elevates(kind):
			lift += height
		free.origin += free.basis.y * lift
		return {"transform": free, "valid": _valid(tree, planet, kind, free, false, player_pos), "links": []}
	var unique := _unique_poses(pool)
	var usable: Array = []
	for option in unique:
		if _option_valid(tree, planet, kind, option, player_pos):
			usable.append(option)
	var choices: Array = usable if not usable.is_empty() else unique
	var tops: Array = []
	var rest: Array = []
	for option in choices:
		if str(option["link"]) == "stairs_top":
			tops.append(option)
		else:
			rest.append(option)
	var sequence: Array = []
	if not tops.is_empty():
		sequence.append_array(_cycle_from(_ordered(tops), aim))
		if not rest.is_empty():
			sequence.append_array(_cycle_from(_ordered(rest), aim))
	else:
		sequence = _cycle_from(_ordered(rest), aim)
	var picked: Dictionary = sequence[posmod(rotation, sequence.size())]
	var pose: Transform3D = picked["transform"]
	var picked_host: Node = picked["host"]
	var host_index := int(picked["host_index"])
	var links: Array = [{
		"host": picked_host,
		"host_index": host_index,
		"plug_index": int(picked["plug_index"]),
	}]
	var valid := _option_valid(tree, planet, kind, picked, player_pos)
	return {"transform": pose, "valid": valid, "links": links}


static func commit(piece: Node, links: Array) -> void:
	for link in links:
		var data: Dictionary = link
		piece.call(&"attach_to", data["host"], int(data["host_index"]), int(data["plug_index"]))


static func _valid(tree: SceneTree, planet: Node3D, kind: String, xform: Transform3D, linked: bool, player_pos: Vector3) -> bool:
	if CATALOG.requires_snap(kind) and not linked:
		return false
	if player_pos.distance_to(xform.origin) < 0.7:
		return false
	if _overlaps(tree, xform.origin, kind):
		return false
	if kind == "foundation":
		if planet == null or not bool(planet.call(&"is_land", xform.origin - planet.global_position)):
			return false
		return bool(PIECE.inspect_foundation(xform, planet, tree)["ok"])
	if kind == "chest":
		if _on_deck(tree, xform):
			return true
		return planet != null and bool(planet.call(&"is_land", xform.origin - planet.global_position))
	if kind == "stairs":
		if planet == null:
			return false
		return bool(PIECE.inspect_stairs(xform, planet, tree)["ok"])
	return true


static func _is_deck_kind(kind: String) -> bool:
	return kind == "foundation" or kind == "floor" or kind == "ceiling"


static func _deck_pose(tree: SceneTree, planet: Node3D, aim: Transform3D, rotation: int, player_pos: Vector3) -> Dictionary:
	var best_score := INF
	var best_pose := Transform3D.IDENTITY
	var half := CATALOG.TILE * 0.5
	var inset := 0.55
	for node in tree.get_nodes_in_group(&"construction"):
		var host := node as Node3D
		if host == null:
			continue
		var host_kind := str(host.get("kind"))
		if not _is_deck_kind(host_kind):
			continue
		var up := host.global_basis.y.normalized()
		var top := host.global_position + up * CATALOG.top_of(host_kind)
		var reach := absf((player_pos - top).dot(up))
		if reach > 4.0:
			continue
		var right := host.global_basis.x.normalized()
		var back := host.global_basis.z.normalized()
		var player_delta := player_pos - top
		var player_planar := player_delta - up * player_delta.dot(up)
		var player_on := (
			absf(player_delta.dot(up)) < 1.25
			and absf(player_planar.dot(right)) <= half
			and absf(player_planar.dot(back)) <= half
		)
		var delta := aim.origin - top
		var planar := delta - up * delta.dot(up)
		var lx := planar.dot(right)
		var lz := planar.dot(back)
		var over_tile := absf(lx) <= half + 0.25 and absf(lz) <= half + 0.25
		if not over_tile and not player_on:
			continue
		lx = clampf(lx, -(half - inset), half - inset)
		lz = clampf(lz, -(half - inset), half - inset)
		var origin := top + right * lx + back * lz
		var score := Vector2(lx, lz).length() + reach * 0.15
		if not player_on:
			score += planar.length() * 0.05
		if score >= best_score:
			continue
		best_score = score
		best_pose = _spin(Transform3D(host.global_basis, origin), rotation)
	if best_score == INF:
		return {}
	return {
		"transform": best_pose,
		"valid": _valid(tree, planet, "chest", best_pose, true, player_pos),
		"links": [],
	}


static func _on_deck(tree: SceneTree, xform: Transform3D) -> bool:
	var half := CATALOG.TILE * 0.5
	var inset := 0.5
	for node in tree.get_nodes_in_group(&"construction"):
		var host := node as Node3D
		if host == null:
			continue
		var host_kind := str(host.get("kind"))
		if not _is_deck_kind(host_kind):
			continue
		if host.global_basis.y.dot(xform.basis.y) < 0.9:
			continue
		var up := host.global_basis.y.normalized()
		var top := host.global_position + up * CATALOG.top_of(host_kind)
		var delta := xform.origin - top
		if absf(delta.dot(up)) > 0.12:
			continue
		var planar := delta - up * delta.dot(up)
		var right := host.global_basis.x.normalized()
		var back := host.global_basis.z.normalized()
		if absf(planar.dot(right)) > half - inset:
			continue
		if absf(planar.dot(back)) > half - inset:
			continue
		return true
	return false


static func _edge_taken(host: Node, host_index: int, kind: String) -> bool:
	if host == null:
		return false
	var host_kind := str(host.get("kind"))
	if host_kind != "foundation" and host_kind != "floor":
		return false
	var used: Dictionary = host.get("used_sockets")
	if kind == "stairs":
		if _socket_used(used, host_index - 8):
			return true
		var wall_index := host_index - 4
		return _socket_used(used, wall_index) and _guest_kind(host, wall_index) != "door_wall"
	if kind == "wall" or kind == "window_wall":
		return _socket_used(used, host_index + 4)
	if kind == "foundation" or kind == "floor":
		return _socket_used(used, host_index + 8)
	return false


static func _socket_used(used: Dictionary, index: int) -> bool:
	return index >= 0 and used.has(index)


static func _guest_kind(host: Node, host_index: int) -> String:
	for link in host.get("_guests"):
		var data: Dictionary = link
		if int(data["host_index"]) != host_index:
			continue
		var guest: Node = data["guest"]
		if is_instance_valid(guest):
			return str(guest.get("kind"))
	return ""


static func _overlaps(tree: SceneTree, origin: Vector3, kind: String) -> bool:
	var occupancy := CATALOG.occupancy_of(kind)
	var radius := CATALOG.occupancy_radius(kind)
	for node in tree.get_nodes_in_group(&"construction"):
		var piece := node as Node3D
		if piece == null or str(piece.get("occupancy")) != occupancy:
			continue
		var block := radius
		if occupancy == "chest":
			block = maxf(radius, CATALOG.occupancy_radius(str(piece.get("kind"))))
		if piece.global_position.distance_to(origin) < block:
			return true
	return false


static func _option_valid(tree: SceneTree, planet: Node3D, kind: String, option: Dictionary, player_pos: Vector3) -> bool:
	var host: Node = option["host"]
	var host_index := int(option["host_index"])
	var pose: Transform3D = option["transform"]
	var socket_free := host != null and bool(host.call(&"is_socket_free", host_index))
	return socket_free and not _edge_taken(host, host_index, kind) and _valid(tree, planet, kind, pose, true, player_pos)


static func _unique_poses(options: Array) -> Array:
	var unique: Array = []
	for option in options:
		var pose: Transform3D = option["transform"]
		var same := false
		for kept in unique:
			var other: Transform3D = kept["transform"]
			if pose.origin.distance_to(other.origin) > 0.08:
				continue
			if pose.basis.z.dot(other.basis.z) < 0.99:
				continue
			if pose.basis.y.dot(other.basis.y) < 0.99:
				continue
			same = true
			break
		if not same:
			unique.append(option)
	return unique


static func _cycle_from(options: Array, aim: Transform3D) -> Array:
	if options.is_empty():
		return []
	var start := 0
	var best := INF
	for i in options.size():
		var pose: Transform3D = options[i]["transform"]
		var distance := _planar(aim.origin, pose.origin, aim.basis.y)
		if distance < best:
			best = distance
			start = i
	var sequence: Array = []
	for i in options.size():
		sequence.append(options[(start + i) % options.size()])
	return sequence


static func _ordered(options: Array) -> Array:
	options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var delta := float(a["angle"]) - float(b["angle"])
		if absf(delta) > 0.001:
			return delta < 0.0
		return int(a["plug_index"]) < int(b["plug_index"])
	)
	var start := 0
	var best := INF
	for i in options.size():
		var magnitude := absf(float(options[i]["angle"]))
		if magnitude < best:
			best = magnitude
			start = i
	var ordered: Array = []
	for i in options.size():
		ordered.append(options[(start + i) % options.size()])
	return ordered


static func _align(host: Node3D, host_socket: Dictionary, plug: Dictionary) -> Transform3D:
	var host_pos: Vector3 = host.global_transform * (host_socket["position"] as Vector3)
	var host_dir: Vector3 = (host.global_basis * (host_socket["direction"] as Vector3)).normalized()
	var world_dir := host_dir if str(plug["join"]) == "mount" else -host_dir
	var basis := _basis_from_axes(plug["direction"], Vector3.UP, world_dir, host.global_basis.y)
	return Transform3D(basis, host_pos - basis * (plug["position"] as Vector3))


static func _basis_from_axes(local_dir: Vector3, local_up: Vector3, world_dir: Vector3, world_up: Vector3) -> Basis:
	var lu := local_up.normalized()
	var ld := local_dir - lu * local_dir.dot(lu)
	if ld.length_squared() < 0.0001:
		ld = Vector3.FORWARD
	ld = ld.normalized()
	var local := Basis(lu.cross(ld).normalized(), lu, ld)
	var wu := world_up.normalized()
	var wd := world_dir - wu * world_dir.dot(wu)
	if wd.length_squared() < 0.0001:
		wd = Vector3.FORWARD
	wd = wd.normalized()
	var wx := wu.cross(wd).normalized()
	return Basis(wx, wu, wx.cross(wu).normalized()) * local.inverse()


static func _spin(xform: Transform3D, rotation: int) -> Transform3D:
	var steps := posmod(rotation, 4)
	if steps == 0:
		return xform
	return Transform3D(xform.basis.rotated(xform.basis.y.normalized(), float(steps) * PI * 0.5), xform.origin)


static func _planar(a: Vector3, b: Vector3, up: Vector3) -> float:
	var delta := a - b
	return (delta - up * delta.dot(up)).length()


static func _in_front(origin: Vector3, player_pos: Vector3, forward: Vector3, up: Vector3) -> bool:
	var to_piece := origin - player_pos
	to_piece -= up * to_piece.dot(up)
	var flat_forward := forward - up * forward.dot(up)
	if to_piece.length_squared() < 0.04 or flat_forward.length_squared() < 0.001:
		return false
	return flat_forward.normalized().dot(to_piece.normalized()) > 0.15


static func _angle_around(host: Node3D, piece_origin: Vector3, aim_origin: Vector3) -> float:
	var up := host.global_basis.y
	var from := aim_origin - host.global_position
	var to := piece_origin - host.global_position
	from -= up * from.dot(up)
	to -= up * to.dot(up)
	if from.length_squared() < 0.0001 or to.length_squared() < 0.0001:
		return 0.0
	return _signed_angle(from, to, up)


static func _signed_angle(from: Vector3, to: Vector3, up: Vector3) -> float:
	var a := from.normalized()
	var b := to.normalized()
	return atan2(up.dot(a.cross(b)), clampf(a.dot(b), -1.0, 1.0))


static func _is_plug(socket: Dictionary) -> bool:
	var role := str(socket["role"])
	return role == "plug" or role == "both"


static func _is_host(socket: Dictionary) -> bool:
	var role := str(socket["role"])
	return role == "host" or role == "both"
