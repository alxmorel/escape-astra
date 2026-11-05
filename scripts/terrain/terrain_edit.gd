extends RefCounted
class_name TerrainEdit

## Dig / flatten ops used by the terrain façade. Host must expose density, edits, enqueue.

const FACE_OFFSETS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]


static func dig(
	host: Node,
	point: Vector3,
	_normal: Vector3,
	tool: String,
	voxel: float,
	iso: float,
	_brush_radius: float,
	brush_strength: float,
	tools: Dictionary,
	drops: Dictionary,
	_target_voxels: int = 48,
	_legacy_depth: float = 0.7,
	underfoot: bool = false,
	dig_width: float = 0.95,
	dig_height: float = 2.1,
	dig_depth: float = 1.4,
	under_depth: float = 1.05,
	min_shell: float = 0.35,
	player_local: Vector3 = Vector3.ZERO,
	air_density: float = -0.65
) -> Dictionary:
	var tool_key := tool
	if not tools.has(tool_key):
		tool_key = "shovel" if tool.ends_with("shovel") else tool
	var allowed: Array = tools.get(tool_key, [])
	var planet: Node3D = host.get(&"_planet")
	if allowed.is_empty() or planet == null:
		return dig_result("", 0, "blocked")
	var local_point := planet.to_local(point)
	if local_point.length_squared() < 0.001:
		return dig_result("", 0, "blocked")
	var radial := local_point.normalized()
	var inward := -radial
	var probe := local_point
	for _step in 8:
		if float(host.call(&"density_at", probe)) > 0.05:
			break
		probe += inward * (voxel * 0.35)
	if float(host.call(&"density_at", probe)) <= 0.05:
		return dig_result("", 0, "empty")
	var focus := probe
	var box := _make_dig_box(
		focus, radial, player_local, underfoot,
		dig_width, dig_height, dig_depth, under_depth, voxel
	)
	var span := maxf(dig_width, maxf(dig_height, maxf(dig_depth, under_depth)))
	var extent := int(ceil(span / voxel)) + 3
	var center_v: Vector3i = host.call(&"_voxel_at", focus)
	var candidates: Array = []
	var saw_stone := false
	var primary: Dictionary = {}
	for x in range(center_v.x - extent, center_v.x + extent + 1):
		for y in range(center_v.y - extent, center_v.y + extent + 1):
			for z in range(center_v.z - extent, center_v.z + extent + 1):
				var vox := Vector3i(x, y, z)
				var pos := Vector3(vox) * voxel
				if pos.length() < 8.0:
					continue
				if not _inside_dig_box(pos, box):
					continue
				var mat: int = host.call(&"_material_at_voxel", vox)
				if not allowed.has(mat):
					saw_stone = true
					continue
				var current: float = host.call(&"_corner_density", vox)
				if current <= iso:
					continue
				var item := {
					"vox": vox,
					"score": pos.distance_squared_to(focus),
					"current": current,
					"mat": mat,
				}
				candidates.append(item)
				primary[vox] = true
	_append_thin_shells(
		host, candidates, primary, box, center_v, extent, voxel, iso, min_shell, allowed
	)
	if candidates.is_empty():
		if saw_stone:
			return dig_result("", 0, "stone")
		return dig_result("", 0, "empty")
	candidates.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) < float(b["score"])
	)
	var changes: Array = []
	var removed: Dictionary = {}
	var seen: Dictionary = {}
	for item in candidates:
		var vox_key: Vector3i = item["vox"]
		if seen.has(vox_key):
			continue
		seen[vox_key] = true
		var current := float(item["current"])
		# Évacuation complète : un coup ouvre le volume (évite les multi-hits sur le même coin).
		var next := air_density
		if current - next < 0.05:
			continue
		var mat := int(item["mat"])
		changes.append([vox_key, next])
		removed[mat] = int(removed.get(mat, 0)) + 1
	if changes.is_empty() or bool(host.call(&"_protected", changes)):
		return dig_result("", 0, "blocked")
	var edits: Dictionary = host.get(&"_edits")
	var touched: Array[Vector3i] = []
	for change in changes:
		var vox2: Vector3i = change[0]
		var next2 := float(change[1])
		if absf(next2 - float(host.call(&"_procedural_density", vox2))) < 0.03:
			edits.erase(vox2)
		else:
			edits[vox2] = next2
		touched.append(vox2)
	host.call(&"_refresh_edit_chunks")
	host.set(&"_support_cache_ok", false)
	host.set(&"_edit_dirty", true)
	var notify_radius := span + voxel
	planet.call(&"notify_terrain_edit", focus, notify_radius)
	var chunk_list: Array = host.call(&"_chunks_for", touched)
	host.call(&"_enqueue", chunk_list)
	if host.has_method(&"clear_collision_for"):
		host.call(&"clear_collision_for", chunk_list)
	var water = host.get(&"_water")
	if water != null:
		water.call(&"disturb", focus, notify_radius + voxel)
	var removed_n := _removed_count(removed)
	var status := "ok" if removed_n > 0 else "empty"
	return dig_result(_best_drop(removed, drops), removed_n, status)


static func dig_result(drop: String, removed: int, status: String) -> Dictionary:
	return {"drop": drop, "removed": removed, "status": status}


static func flatten_plot(
	host: Node,
	cell: Vector3i,
	radius: float,
	normal: Vector3,
	voxel: float
) -> void:
	var planet: Node3D = host.get(&"_planet")
	if planet == null:
		return
	var center := Vector3(cell) + Vector3.ONE * 0.5
	var plane_normal := normal.normalized()
	if plane_normal.length_squared() < 0.01:
		plane_normal = center.normalized()
	if radius <= 0.0:
		radius = float(host.call(&"_surface_radius", plane_normal, center.length()))
	var origin := plane_normal * radius
	var lo: Vector3i = host.call(&"_voxel_at", Vector3(cell) - Vector3.ONE * 0.25)
	var hi: Vector3i = host.call(&"_voxel_at", Vector3(cell) + Vector3.ONE * 1.25)
	var edits: Dictionary = host.get(&"_edits")
	var touched: Array[Vector3i] = []
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				var vox := Vector3i(x, y, z)
				var pos := Vector3(vox) * voxel
				if pos.length() < 8.0:
					continue
				var signed := (pos - origin).dot(plane_normal)
				if absf(signed) > 1.6:
					continue
				var target := clampf(-signed, -1.4, 1.4)
				if absf(float(host.call(&"_corner_density", vox)) - target) < 0.02:
					continue
				if absf(target - float(host.call(&"_procedural_density", vox))) < 0.03:
					edits.erase(vox)
				else:
					edits[vox] = target
				touched.append(vox)
	if touched.is_empty():
		return
	host.call(&"_refresh_edit_chunks")
	host.set(&"_support_cache_ok", false)
	host.set(&"_edit_dirty", true)
	planet.call(&"notify_terrain_edit", origin, 2.2)
	host.call(&"_enqueue", host.call(&"_chunks_for", touched))


static func plot_plane(cell: Vector3i, radius: float, surface_radius: Callable) -> Dictionary:
	var center := Vector3(cell) + Vector3.ONE * 0.5
	var n := center.normalized()
	if n.length_squared() < 0.01:
		n = Vector3.UP
	if radius <= 0.0:
		radius = float(surface_radius.call(n, center.length()))
	var dom := 0
	if absf(n.y) > absf(n.x):
		dom = 1
	if absf(n.z) > absf(n[dom]):
		dom = 2
	var axis_u := Vector3.ZERO
	var axis_v := Vector3.ZERO
	axis_u[(dom + 1) % 3] = 1.0
	axis_v[(dom + 2) % 3] = 1.0
	return {
		"normal": n,
		"origin": n * radius,
		"half_u": (axis_u - n * axis_u.dot(n)) * 0.5,
		"half_v": (axis_v - n * axis_v.dot(n)) * 0.5,
	}


static func _make_dig_box(
	focus: Vector3,
	radial: Vector3,
	player_local: Vector3,
	underfoot: bool,
	dig_width: float,
	dig_height: float,
	dig_depth: float,
	under_depth: float,
	voxel: float
) -> Dictionary:
	var up := radial
	var shaft := underfoot
	var into := -up
	if not underfoot and player_local.length_squared() > 0.001:
		var tangent := focus - player_local
		tangent -= up * tangent.dot(up)
		if tangent.length_squared() > 0.04:
			# Mélange tangentiel + entrant pour mordre la croûte, indépendamment de la pente du mesh.
			into = (tangent.normalized() * 0.7 + (-up) * 0.3).normalized()
		if absf(into.dot(up)) > 0.82:
			into = -up
			shaft = true
	elif underfoot:
		into = -up
		shaft = true
	var hint := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var right: Vector3
	var forward: Vector3
	if shaft:
		right = up.cross(hint).normalized()
		forward = right.cross(up).normalized()
	else:
		# Forward = direction de creusage (peut avoir une composante radiale).
		forward = into.normalized()
		right = up.cross(forward)
		if right.length_squared() < 0.001:
			right = up.cross(hint)
		right = right.normalized()
		# Recalcule un forward orthogonal à right dans le plan into/up.
		var ortho := right.cross(up).normalized()
		if forward.dot(ortho) < 0.0:
			ortho = -ortho
		# Conserve la composante radiale de into pour la profondeur.
		forward = (ortho * maxf(ortho.dot(into), 0.05) + (-up) * maxf((-up).dot(into), 0.0)).normalized()
		if forward.length_squared() < 0.001:
			forward = into
	var pad := voxel * 0.35
	var half_w := dig_width * 0.5 + pad
	if shaft:
		# Puits sous les pieds : ~1.3 cube de large, ~1.5 cube de profondeur radiale.
		return {
			"origin": focus,
			"right": right,
			"up": up,
			"forward": forward,
			"half_w": half_w,
			"half_f": half_w,
			"u_lo": -(under_depth + pad),
			"u_hi": pad,
			"shaft": true,
		}
	# Couloir : largeur ~1.3 voxel, hauteur ~3 voxels, profondeur 2 voxels / coup.
	var u_lo := -dig_height * 0.35 - pad
	var u_hi := dig_height * 0.65 + pad
	return {
		"origin": focus,
		"right": right,
		"up": up,
		"forward": forward,
		"half_w": half_w,
		"half_f": 0.0,
		"u_lo": u_lo,
		"u_hi": u_hi,
		"d_lo": -pad,
		"d_hi": dig_depth + pad,
		"shaft": false,
	}


static func _inside_dig_box(pos: Vector3, box: Dictionary) -> bool:
	var origin: Vector3 = box["origin"]
	var rel := pos - origin
	var right: Vector3 = box["right"]
	var up: Vector3 = box["up"]
	var forward: Vector3 = box["forward"]
	if absf(rel.dot(right)) > float(box["half_w"]):
		return false
	var along_up := rel.dot(up)
	if along_up < float(box["u_lo"]) or along_up > float(box["u_hi"]):
		return false
	if bool(box["shaft"]):
		return absf(rel.dot(forward)) <= float(box["half_f"])
	var along_f := rel.dot(forward)
	return along_f >= float(box["d_lo"]) and along_f <= float(box["d_hi"])


static func _near_dig_box(pos: Vector3, box: Dictionary, margin: float) -> bool:
	var grown := box.duplicate()
	grown["half_w"] = float(box["half_w"]) + margin
	grown["u_lo"] = float(box["u_lo"]) - margin
	grown["u_hi"] = float(box["u_hi"]) + margin
	if bool(box["shaft"]):
		grown["half_f"] = float(box["half_f"]) + margin
	else:
		grown["d_lo"] = float(box["d_lo"]) - margin
		grown["d_hi"] = float(box["d_hi"]) + margin
	return _inside_dig_box(pos, grown)


static func _append_thin_shells(
	host: Node,
	candidates: Array,
	primary: Dictionary,
	box: Dictionary,
	center_v: Vector3i,
	extent: int,
	voxel: float,
	iso: float,
	min_shell: float,
	allowed: Array
) -> void:
	var margin := maxf(min_shell, voxel * 0.45)
	for x in range(center_v.x - extent, center_v.x + extent + 1):
		for y in range(center_v.y - extent, center_v.y + extent + 1):
			for z in range(center_v.z - extent, center_v.z + extent + 1):
				var vox := Vector3i(x, y, z)
				if primary.has(vox):
					continue
				var pos := Vector3(vox) * voxel
				if pos.length() < 8.0:
					continue
				if not _near_dig_box(pos, box, margin):
					continue
				var mat: int = host.call(&"_material_at_voxel", vox)
				if not allowed.has(mat):
					continue
				var current: float = host.call(&"_corner_density", vox)
				if current <= iso:
					continue
				if not _is_thin_shell(host, vox, current, iso, min_shell):
					continue
				candidates.append({
					"vox": vox,
					"score": pos.distance_squared_to(Vector3(box["origin"])) + 1000.0,
					"current": current,
					"mat": mat,
				})


static func _is_thin_shell(host: Node, vox: Vector3i, current: float, iso: float, min_shell: float) -> bool:
	var air := 0
	for offset in FACE_OFFSETS:
		if float(host.call(&"_corner_density", vox + offset)) <= iso:
			air += 1
	if air >= 4:
		return true
	if current < iso + min_shell and air >= 2:
		return true
	return false


static func _best_drop(removed: Dictionary, drops: Dictionary) -> String:
	var best := ""
	var best_n := 0
	for mat in removed:
		var n := int(removed[mat])
		if n > best_n and drops.has(mat):
			best = str(drops[mat])
			best_n = n
	return best


static func _removed_count(removed: Dictionary) -> int:
	var total := 0
	for mat in removed:
		total += int(removed[mat])
	return total
