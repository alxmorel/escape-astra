extends RefCounted
class_name PlanetHydroNetwork

## Drainage sphérique seed-déterministe : raw → fill/breach → flow → accum → Strahler.

const SAMPLE_COUNT := 4096
const NEIGHBOR_COUNT := 8
const HEIGHT_EPS := 0.0004
const LIFT := 0.22
## Micro-dépressions franchies (monde).
const BREACH_DEPTH := 0.55
## Cuvettes gardées comme lacs (profondeur + catchment).
const LAKE_MIN_DEPTH := 0.55
const LAKE_MIN_CATCH := 48.0
## Classification canaux (relative à N + Strahler).
const STREAM_FRACTION := 0.004
const RIVER_FRACTION := 0.018
const STREAM_STRAHLER := 2
const RIVER_STRAHLER := 3

var sample_count := 0
var dirs := PackedVector3Array()
var heights := PackedFloat32Array() ## relief de travail (hydraulique après fill)
var base_heights := PackedFloat32Array() ## H0 brut
var hydraulic := PackedFloat32Array()
var neighbors: Array[PackedInt32Array] = []
var flow_to := PackedInt32Array()
var accum := PackedFloat32Array()
var basin_of := PackedInt32Array()
var strahler := PackedInt32Array()
var sink_ids: PackedInt32Array = PackedInt32Array()
var lake_ids: PackedInt32Array = PackedInt32Array()
var lake_surface := PackedFloat32Array() ## par sample ; 0 = non lac
var is_channel := PackedByteArray() ## 0 none, 1 stream, 2 river

var stream_count := 0
var river_count := 0
var confluence_count := 0
var breach_count := 0
var built_seed := 0
var build_ms := 0
var phase_ms: Dictionary = {}
var metrics_before: Dictionary = {}
var metrics_after: Dictionary = {}
## Bins spatiaux réutilisables (érosion / lookups).
var bins_t := 64
var bins_p := 128
var bins: Array = []

## Voisins Fibonacci = indépendants de la seed → cache process-wide.
static var _static_n := 0
static var _static_neighbors: Array[PackedInt32Array] = []
static var _static_bins: Array = []
static var _static_bins_t := 64
static var _static_bins_p := 128


func build(planet: Node) -> void:
	var t0 := Time.get_ticks_msec()
	phase_ms.clear()
	built_seed = int(planet.get(&"world_seed"))
	var t := Time.get_ticks_msec()
	_sample_base(planet)
	phase_ms["sample"] = Time.get_ticks_msec() - t
	t = Time.get_ticks_msec()
	_build_neighbors()
	phase_ms["neighbors"] = Time.get_ticks_msec() - t
	t = Time.get_ticks_msec()
	# --- raw ---
	heights = base_heights.duplicate()
	hydraulic = base_heights.duplicate()
	_compute_flow()
	_compute_accum()
	_compute_basins()
	_compute_strahler()
	_classify_channels()
	metrics_before = _snapshot("raw")
	phase_ms["raw_flow"] = Time.get_ticks_msec() - t
	t = Time.get_ticks_msec()
	# --- fill / breach ---
	_fill_breach()
	heights = base_heights.duplicate()
	hydraulic = base_heights.duplicate()
	_compute_accum()
	_compute_basins()
	_compute_strahler()
	_classify_channels()
	_assign_lake_surfaces()
	metrics_after = _snapshot("filled")
	phase_ms["breach"] = Time.get_ticks_msec() - t
	build_ms = Time.get_ticks_msec() - t0
	phase_ms["total"] = build_ms


func build_with_heights(sample_dirs: PackedVector3Array, sample_heights: PackedFloat32Array, world_seed: int = 0) -> void:
	var t0 := Time.get_ticks_msec()
	phase_ms.clear()
	built_seed = world_seed
	dirs = sample_dirs.duplicate()
	base_heights = sample_heights.duplicate()
	sample_count = dirs.size()
	neighbors.clear()
	var t := Time.get_ticks_msec()
	_build_neighbors()
	phase_ms["neighbors"] = Time.get_ticks_msec() - t
	t = Time.get_ticks_msec()
	heights = base_heights.duplicate()
	hydraulic = base_heights.duplicate()
	_compute_flow()
	_compute_accum()
	_compute_basins()
	_compute_strahler()
	_classify_channels()
	metrics_before = _snapshot("raw")
	phase_ms["raw_flow"] = Time.get_ticks_msec() - t
	t = Time.get_ticks_msec()
	_fill_breach()
	heights = base_heights.duplicate()
	hydraulic = base_heights.duplicate()
	_compute_accum()
	_compute_basins()
	_compute_strahler()
	_classify_channels()
	_assign_lake_surfaces()
	metrics_after = _snapshot("filled")
	phase_ms["breach"] = Time.get_ticks_msec() - t
	build_ms = Time.get_ticks_msec() - t0
	phase_ms["total"] = build_ms
	phase_ms["sample"] = 0


func stream_threshold() -> float:
	return maxf(8.0, float(sample_count) * STREAM_FRACTION)


func river_threshold() -> float:
	return maxf(24.0, float(sample_count) * RIVER_FRACTION)


func is_stream(index: int) -> bool:
	return index >= 0 and index < is_channel.size() and int(is_channel[index]) >= 1


func is_river(index: int) -> bool:
	return index >= 0 and index < is_channel.size() and int(is_channel[index]) >= 2


func is_sink(index: int) -> bool:
	return index >= 0 and index < flow_to.size() and flow_to[index] < 0


func is_lake(index: int) -> bool:
	return index >= 0 and index < lake_surface.size() and lake_surface[index] > 0.0


func surface_point(index: int, lift: float = LIFT) -> Vector3:
	return dirs[index] * (heights[index] + lift)


func surface_point_base(index: int, lift: float = LIFT) -> Vector3:
	return dirs[index] * (base_heights[index] + lift)


func validate() -> Dictionary:
	var loops := 0
	var uphill := 0
	var orphan := 0
	var dead_end := 0
	var lake_set: Dictionary = {}
	for lake in lake_ids:
		lake_set[lake] = true
	for i in sample_count:
		var dest := int(flow_to[i])
		if dest < 0:
			if not lake_set.has(i):
				dead_end += 1
			continue
		if dest >= sample_count:
			orphan += 1
			continue
		# Uphill possible sur tronçons de breach (grimpe vers spill) — informatif seulement.
		if base_heights[dest] > base_heights[i] + HEIGHT_EPS:
			uphill += 1
		var guard := 0
		var seen: Dictionary = {}
		var cur := i
		while cur >= 0 and guard < sample_count + 2:
			if seen.has(cur):
				loops += 1
				break
			seen[cur] = true
			cur = int(flow_to[cur])
			guard += 1
	var bed_breaks := _count_bed_breaks(lake_set)
	return {
		"ok": loops == 0 and orphan == 0 and dead_end == 0 and bed_breaks == 0,
		"loops": loops,
		"uphill": uphill,
		"orphan_flow": orphan,
		"dead_ends": dead_end,
		"bed_breaks": bed_breaks,
		"sinks": sink_ids.size(),
		"lakes": lake_ids.size(),
		"streams": stream_count,
		"rivers": river_count,
		"confluences": confluence_count,
		"breaches": breach_count,
		"samples": sample_count,
		"build_ms": build_ms,
		"before": metrics_before,
		"after": metrics_after,
	}


func fingerprint() -> String:
	var h := 2166136261
	h = _mix(h, sample_count)
	h = _mix(h, built_seed)
	for i in sample_count:
		h = _mix(h, int(flow_to[i]) + 3)
		h = _mix(h, int(accum[i] * 100.0))
		h = _mix(h, int(strahler[i]))
		h = _mix(h, int(basin_of[i]) + 1)
		h = _mix(h, int(lake_surface[i] * 1000.0))
	return "%08x" % (h & 0xffffffff)


func make_debug_mesh(eroded_heights: PackedFloat32Array = PackedFloat32Array()) -> ArrayMesh:
	var use_h := eroded_heights if eroded_heights.size() == sample_count else heights
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	for i in sample_count:
		var dest := int(flow_to[i])
		if dest < 0 or int(is_channel[i]) < 1:
			continue
		var a: Vector3 = dirs[i] * (use_h[i] + LIFT)
		var b: Vector3 = dirs[dest] * (use_h[dest] + LIFT)
		var color := _channel_color(i)
		st.set_color(color)
		st.add_vertex(a)
		st.set_color(color)
		st.add_vertex(b)
	for lake in lake_ids:
		var c: Vector3 = dirs[lake] * (use_h[lake] + LIFT)
		var s := 0.4 + clampf(accum[lake] / 800.0, 0.0, 1.2)
		_cross(st, c, s, Color(0.95, 0.3, 0.85))
	return st.commit()


func metrics_report() -> String:
	var b: Dictionary = metrics_before
	var a: Dictionary = metrics_after
	return "hydro %dms N=%d | before sinks=%s pathMax=%s rivers=%s | after sinks=%s lakes=%s pathMax=%s streams=%s rivers=%s conf=%s breach=%s" % [
		build_ms,
		sample_count,
		str(b.get("sinks", "?")),
		str(b.get("path_max", "?")),
		str(b.get("rivers", "?")),
		str(a.get("sinks", "?")),
		str(a.get("lakes", lake_ids.size())),
		str(a.get("path_max", "?")),
		str(a.get("streams", stream_count)),
		str(a.get("rivers", river_count)),
		str(a.get("confluences", confluence_count)),
		str(breach_count),
	]


func _sample_base(planet: Node) -> void:
	dirs = PackedVector3Array()
	base_heights = PackedFloat32Array()
	dirs.resize(SAMPLE_COUNT)
	base_heights.resize(SAMPLE_COUNT)
	sample_count = SAMPLE_COUNT
	var golden := PI * (3.0 - sqrt(5.0))
	var use_base := planet.has_method(&"sample_base_height")
	for i in SAMPLE_COUNT:
		var y := 1.0 - (float(i) / float(SAMPLE_COUNT - 1)) * 2.0
		var ring := sqrt(maxf(0.0, 1.0 - y * y))
		var theta := golden * float(i)
		var dir := Vector3(cos(theta) * ring, y, sin(theta) * ring).normalized()
		dirs[i] = dir
		if use_base:
			base_heights[i] = float(planet.call(&"sample_base_height", dir))
		else:
			base_heights[i] = float(planet.call(&"sample_terrain_height", dir))


func _build_neighbors() -> void:
	if _static_n == sample_count and _static_neighbors.size() == sample_count:
		neighbors = _static_neighbors.duplicate()
		bins = _static_bins
		bins_t = _static_bins_t
		bins_p = _static_bins_p
		return
	neighbors.clear()
	neighbors.resize(sample_count)
	bins_t = 64
	bins_p = 128
	bins = []
	bins.resize(bins_t * bins_p)
	for i in bins.size():
		bins[i] = PackedInt32Array()
	for i in sample_count:
		var key := _theta_bin(dirs[i], bins_t) * bins_p + _phi_bin(dirs[i], bins_p)
		(bins[key] as PackedInt32Array).append(i)
	var max_gap := clampf(2.8 * sqrt(TAU * 2.0 / float(maxi(sample_count, 2))), 0.05, 0.22)
	var max_dot := cos(max_gap)
	var best_d := PackedFloat32Array()
	var best_i := PackedInt32Array()
	best_d.resize(NEIGHBOR_COUNT)
	best_i.resize(NEIGHBOR_COUNT)
	for i in sample_count:
		var di := dirs[i]
		var ti := _theta_bin(di, bins_t)
		var pi := _phi_bin(di, bins_p)
		for k in NEIGHBOR_COUNT:
			best_d[k] = -2.0
			best_i[k] = -1
		for dt in range(-2, 3):
			var tt := ti + dt
			if tt < 0 or tt >= bins_t:
				continue
			for dp in range(-2, 3):
				var pp := posmod(pi + dp, bins_p)
				var cell: PackedInt32Array = bins[tt * bins_p + pp]
				for j in cell:
					if j == i:
						continue
					var d := di.dot(dirs[j])
					if d < max_dot:
						continue
					_insert_topk(best_d, best_i, d, j, NEIGHBOR_COUNT)
		var packed := PackedInt32Array()
		for k in NEIGHBOR_COUNT:
			if best_i[k] >= 0:
				packed.append(best_i[k])
		if packed.is_empty():
			packed = _brute_neighbors(i, max_dot)
		neighbors[i] = packed
	_static_n = sample_count
	_static_neighbors = neighbors.duplicate()
	_static_bins = bins
	_static_bins_t = bins_t
	_static_bins_p = bins_p


func _insert_topk(best_d: PackedFloat32Array, best_i: PackedInt32Array, d: float, j: int, count: int) -> void:
	var slot := -1
	for k in count:
		if d > best_d[k] + 1e-12 or (absf(d - best_d[k]) <= 1e-12 and (best_i[k] < 0 or j < best_i[k])):
			slot = k
			break
	if slot < 0:
		return
	for k in range(count - 1, slot, -1):
		best_d[k] = best_d[k - 1]
		best_i[k] = best_i[k - 1]
	best_d[slot] = d
	best_i[slot] = j


func _brute_neighbors(i: int, max_dot: float) -> PackedInt32Array:
	var best_d := PackedFloat32Array()
	var best_i := PackedInt32Array()
	best_d.resize(NEIGHBOR_COUNT)
	best_i.resize(NEIGHBOR_COUNT)
	for k in NEIGHBOR_COUNT:
		best_d[k] = -2.0
		best_i[k] = -1
	var di := dirs[i]
	for j in sample_count:
		if i == j:
			continue
		var d := di.dot(dirs[j])
		if d < max_dot:
			continue
		_insert_topk(best_d, best_i, d, j, NEIGHBOR_COUNT)
	var packed := PackedInt32Array()
	for k in NEIGHBOR_COUNT:
		if best_i[k] >= 0:
			packed.append(best_i[k])
	return packed


func _theta_bin(dir: Vector3, bt: int = -1) -> int:
	var n := bins_t if bt < 0 else bt
	var t := acos(clampf(dir.y, -1.0, 1.0)) / PI
	return clampi(int(t * float(n)), 0, n - 1)


func _phi_bin(dir: Vector3, bp: int = -1) -> int:
	var n := bins_p if bp < 0 else bp
	var p := (atan2(dir.z, dir.x) + PI) / TAU
	return clampi(int(p * float(n)), 0, n - 1)


func _compute_flow() -> void:
	flow_to = PackedInt32Array()
	flow_to.resize(sample_count)
	for i in sample_count:
		var best := -1
		var best_h := heights[i]
		var best_idx := 0x7fffffff
		for j in neighbors[i]:
			var hj := heights[j]
			if hj >= heights[i] - HEIGHT_EPS:
				continue
			if hj < best_h - HEIGHT_EPS or (absf(hj - best_h) <= HEIGHT_EPS and j < best_idx):
				best = j
				best_h = hj
				best_idx = j
		flow_to[i] = best


func _compute_accum() -> void:
	accum = PackedFloat32Array()
	accum.resize(sample_count)
	for i in sample_count:
		accum[i] = 1.0
	var order := _topo_order()
	for i in order:
		var dest := int(flow_to[i])
		if dest >= 0:
			accum[dest] += accum[i]


func _topo_order() -> Array[int]:
	## Sources → exutoires (valide même si breach grimpe en altitude).
	var indeg := PackedInt32Array()
	indeg.resize(sample_count)
	for i in sample_count:
		indeg[i] = 0
	for i in sample_count:
		var dest := int(flow_to[i])
		if dest >= 0:
			indeg[dest] = int(indeg[dest]) + 1
	var queue: Array[int] = []
	for i in sample_count:
		if int(indeg[i]) == 0:
			queue.append(i)
	var order: Array[int] = []
	var head := 0
	while head < queue.size():
		var u: int = queue[head]
		head += 1
		order.append(u)
		var dest := int(flow_to[u])
		if dest < 0:
			continue
		indeg[dest] = int(indeg[dest]) - 1
		if int(indeg[dest]) == 0:
			queue.append(dest)
	if order.size() < sample_count:
		# Cycle résiduel : complète de façon déterministe.
		var seen: Dictionary = {}
		for i in order:
			seen[i] = true
		for i in sample_count:
			if not seen.has(i):
				order.append(i)
	return order


func _compute_basins() -> void:
	basin_of = PackedInt32Array()
	basin_of.resize(sample_count)
	sink_ids = PackedInt32Array()
	for i in sample_count:
		basin_of[i] = -1
		if flow_to[i] < 0:
			sink_ids.append(i)
			basin_of[i] = i
	for i in sample_count:
		if basin_of[i] >= 0:
			continue
		var path: Array[int] = []
		var cur := i
		var guard := 0
		while cur >= 0 and basin_of[cur] < 0 and guard < sample_count:
			path.append(cur)
			cur = int(flow_to[cur])
			guard += 1
		var sink := i
		if cur >= 0:
			sink = basin_of[cur] if basin_of[cur] >= 0 else cur
		for node in path:
			basin_of[node] = sink


func _compute_strahler() -> void:
	strahler = PackedInt32Array()
	strahler.resize(sample_count)
	var kids: Array[PackedInt32Array] = []
	kids.resize(sample_count)
	for i in sample_count:
		strahler[i] = 0
		kids[i] = PackedInt32Array()
	for i in sample_count:
		var dest := int(flow_to[i])
		if dest >= 0:
			kids[dest].append(i)
	var order := _topo_order()
	for i in order:
		var childs: PackedInt32Array = kids[i]
		if childs.is_empty():
			strahler[i] = 1
			continue
		var max_o := 0
		var max_n := 0
		for c in childs:
			var o := int(strahler[c])
			if o > max_o:
				max_o = o
				max_n = 1
			elif o == max_o:
				max_n += 1
		strahler[i] = max_o + 1 if max_n >= 2 else maxi(max_o, 1)


func _classify_channels() -> void:
	stream_count = 0
	river_count = 0
	confluence_count = 0
	is_channel = PackedByteArray()
	is_channel.resize(sample_count)
	var st := stream_threshold()
	var rt := river_threshold()
	var incoming := PackedInt32Array()
	incoming.resize(sample_count)
	for i in sample_count:
		incoming[i] = 0
		is_channel[i] = 0
	for i in sample_count:
		var stream := accum[i] >= st or int(strahler[i]) >= STREAM_STRAHLER
		var river := accum[i] >= rt and int(strahler[i]) >= RIVER_STRAHLER
		if river:
			is_channel[i] = 2
			river_count += 1
			stream_count += 1
		elif stream:
			is_channel[i] = 1
			stream_count += 1
		var dest := int(flow_to[i])
		if dest >= 0 and int(is_channel[i]) >= 1:
			incoming[dest] += 1
	for i in sample_count:
		if incoming[i] >= 2 and int(is_channel[i]) >= 1:
			confluence_count += 1


func _fill_breach() -> void:
	breach_count = 0
	lake_ids = PackedInt32Array()
	lake_surface = PackedFloat32Array()
	lake_surface.resize(sample_count)
	for i in sample_count:
		lake_surface[i] = 0.0
	# Traiter petits catchments d'abord pour fusionner vers les grands lacs.
	var ordered: Array[int] = []
	for sink in sink_ids:
		ordered.append(sink)
	ordered.sort_custom(func(a: int, b: int) -> bool:
		if not is_equal_approx(accum[a], accum[b]):
			return accum[a] < accum[b]
		return a < b
	)
	for sink in ordered:
		var info := _find_spill(sink)
		var depth := float(info.get("depth", 0.0))
		var pour_in := int(info.get("pour_in", -1))
		var pour_out := int(info.get("pour_out", -1))
		var catch := accum[sink]
		var keep_lake := depth >= LAKE_MIN_DEPTH and catch >= LAKE_MIN_CATCH
		if pour_out < 0 or pour_in < 0:
			lake_ids.append(sink)
			continue
		if keep_lake:
			lake_ids.append(sink)
			continue
		# Ne pas drainer vers un nœud qui rejoint déjà ce sink (cycle).
		if _flow_reaches(pour_out, sink):
			lake_ids.append(sink)
			continue
		if not _wire_breach_path(sink, pour_in, pour_out):
			lake_ids.append(sink)
			continue
		breach_count += 1
	_break_cycles()


func _flow_reaches(start: int, target: int) -> bool:
	var cur := start
	var guard := 0
	var seen: Dictionary = {}
	while cur >= 0 and guard < sample_count:
		if cur == target:
			return true
		if seen.has(cur):
			return true
		seen[cur] = true
		cur = int(flow_to[cur])
		guard += 1
	return false


func _wire_breach_path(sink: int, pour_in: int, pour_out: int) -> bool:
	if sink == pour_in:
		if _flow_reaches(pour_out, sink):
			return false
		flow_to[sink] = pour_out
		return true
	var parent: Dictionary = {}
	var queue: Array[int] = [sink]
	parent[sink] = -1
	var found := false
	var head := 0
	while head < queue.size():
		var u: int = queue[head]
		head += 1
		if u == pour_in:
			found = true
			break
		for v in neighbors[u]:
			if basin_of[v] != sink:
				continue
			if parent.has(v):
				continue
			parent[v] = u
			queue.append(v)
	if not found or not parent.has(pour_in):
		var adjacent := false
		for v in neighbors[sink]:
			if v == pour_in:
				adjacent = true
				break
		if not adjacent:
			return false
		if _flow_reaches(pour_out, sink):
			return false
		flow_to[sink] = pour_in
		flow_to[pour_in] = pour_out
		return true
	if _flow_reaches(pour_out, sink):
		return false
	var cur := pour_in
	while cur != sink:
		var prev: int = int(parent[cur])
		flow_to[prev] = cur
		cur = prev
	flow_to[pour_in] = pour_out
	# Vérifie absence de cycle après câblage.
	if _flow_reaches(pour_out, pour_in):
		# rollback minimal : couper la sortie
		flow_to[pour_in] = -1
		return false
	return true


func _break_cycles() -> void:
	var visiting: Dictionary = {}
	for i in sample_count:
		if visiting.has(i):
			continue
		var cur := i
		var stack: Array[int] = []
		var idx_of: Dictionary = {}
		while cur >= 0:
			if idx_of.has(cur):
				# Cycle stack[idx..] — couper au nœud de plus basse altitude.
				var start_i: int = int(idx_of[cur])
				var best := cur
				var best_h := base_heights[cur]
				for s in range(start_i, stack.size()):
					var node: int = stack[s]
					if base_heights[node] < best_h - HEIGHT_EPS or (absf(base_heights[node] - best_h) <= HEIGHT_EPS and node < best):
						best = node
						best_h = base_heights[node]
				flow_to[best] = -1
				if lake_ids.find(best) < 0:
					lake_ids.append(best)
				break
			if visiting.has(cur):
				break
			idx_of[cur] = stack.size()
			stack.append(cur)
			visiting[cur] = true
			cur = int(flow_to[cur])


func _find_spill(sink: int) -> Dictionary:
	var spill_h := INF
	var pour_in := -1
	var pour_out := -1
	for i in sample_count:
		if basin_of[i] != sink:
			continue
		for j in neighbors[i]:
			if basin_of[j] == sink:
				continue
			var level := maxf(base_heights[i], base_heights[j])
			if level < spill_h - HEIGHT_EPS or (absf(level - spill_h) <= HEIGHT_EPS and (j < pour_out or pour_out < 0)):
				spill_h = level
				pour_in = i
				pour_out = j
	if spill_h == INF:
		spill_h = base_heights[sink]
	var depth := spill_h - base_heights[sink]
	return {
		"spill": spill_h,
		"pour_in": pour_in,
		"pour_out": pour_out,
		"depth": depth,
	}


func _assign_lake_surfaces() -> void:
	# Tout sink résiduel après fill = exutoire lacustre (pas de terminaison orpheline).
	lake_surface = PackedFloat32Array()
	lake_surface.resize(sample_count)
	for i in sample_count:
		lake_surface[i] = 0.0
	var kept: Dictionary = {}
	for sink in lake_ids:
		kept[sink] = true
	for i in sample_count:
		if flow_to[i] < 0:
			kept[i] = true
	var out_ids := PackedInt32Array()
	for sink in kept.keys():
		var s := int(sink)
		if flow_to[s] >= 0:
			continue
		out_ids.append(s)
		var info := _find_spill_for_current(s)
		var spill_h := float(info.get("spill", base_heights[s]))
		var surface := spill_h - 0.08
		for i in sample_count:
			if basin_of[i] != s:
				continue
			if base_heights[i] < surface:
				lake_surface[i] = maxf(lake_surface[i], surface)
	lake_ids = out_ids


func _find_spill_for_current(sink: int) -> Dictionary:
	var spill_h := INF
	var pour_in := -1
	var pour_out := -1
	for i in sample_count:
		if basin_of[i] != sink:
			continue
		for j in neighbors[i]:
			if basin_of[j] == sink:
				continue
			var level := maxf(base_heights[i], base_heights[j])
			if level < spill_h - HEIGHT_EPS or (absf(level - spill_h) <= HEIGHT_EPS and (j < pour_out or pour_out < 0)):
				spill_h = level
				pour_in = i
				pour_out = j
	if spill_h == INF:
		spill_h = base_heights[sink]
	return {"spill": spill_h, "pour_in": pour_in, "pour_out": pour_out, "depth": spill_h - base_heights[sink]}


func _snapshot(label: String) -> Dictionary:
	var path_max := 0
	var path_sum := 0
	var max_accum := 0.0
	for i in sample_count:
		max_accum = maxf(max_accum, accum[i])
		var lenp := 0
		var cur := i
		var guard := 0
		while cur >= 0 and guard < sample_count:
			var nxt := int(flow_to[cur])
			if nxt < 0:
				break
			lenp += 1
			cur = nxt
			guard += 1
		path_max = maxi(path_max, lenp)
		path_sum += lenp
	var max_strahler := 0
	for i in sample_count:
		max_strahler = maxi(max_strahler, int(strahler[i]))
	return {
		"label": label,
		"sinks": sink_ids.size(),
		"lakes": lake_ids.size(),
		"streams": stream_count,
		"rivers": river_count,
		"confluences": confluence_count,
		"breaches": breach_count,
		"path_max": path_max,
		"path_mean": float(path_sum) / float(maxi(sample_count, 1)),
		"max_accum": max_accum,
		"max_strahler": max_strahler,
	}


func _count_bed_breaks(lake_set: Dictionary) -> int:
	## Continuité : tout canal doit atteindre un lac / sink lacustre en suivant flow_to.
	var breaks := 0
	for i in sample_count:
		if int(is_channel[i]) < 1:
			continue
		if not _reaches_lake(i, lake_set):
			breaks += 1
	return breaks


func _reaches_lake(start: int, lake_set: Dictionary) -> bool:
	var cur := start
	var guard := 0
	var seen: Dictionary = {}
	while cur >= 0 and guard < sample_count:
		if seen.has(cur):
			return false
		seen[cur] = true
		if lake_set.has(cur) or lake_surface[cur] > 0.0:
			return true
		var nxt := int(flow_to[cur])
		if nxt < 0:
			return lake_set.has(cur)
		cur = nxt
		guard += 1
	return false


func _channel_color(index: int) -> Color:
	if int(is_channel[index]) >= 2:
		return Color(0.12, 0.4, 1.0)
	var t := clampf(float(strahler[index] - 1) / 4.0, 0.0, 1.0)
	return Color(0.4, 0.9, 0.95).lerp(Color(0.2, 0.6, 1.0), t)


func _cross(st: SurfaceTool, center: Vector3, size: float, color: Color) -> void:
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.FORWARD]:
		st.set_color(color)
		st.add_vertex(center - axis * size)
		st.set_color(color)
		st.add_vertex(center + axis * size)


func _mix(h: int, value: int) -> int:
	return int((h ^ value) * 16777619) & 0x7fffffff
