extends RefCounted
class_name TerrainMeshJob

const TerrainSurfaceBuild := preload("res://scripts/terrain/terrain_surface_build.gd")

var active := false
var discard := false
var coord := Vector3i.ZERO

var _phase := 0
var _origin := Vector3i.ZERO
var _count := 0
var _index := 0
var _task := -1
var _t0 := 0
var _values := PackedFloat32Array()
var _materials := PackedByteArray()
var _packet: Dictionary = {}
var _voxel := 0.7
var _iso := 0.0
var _chunk_size := 8


func configure(voxel: float, iso: float, chunk_size: int) -> void:
	_voxel = voxel
	_iso = iso
	_chunk_size = chunk_size


func request_discard() -> void:
	if active:
		discard = true


func request_discard_at(target: Vector3i) -> void:
	if active and coord == target:
		discard = true


func pump(host: Node, boot: bool) -> void:
	var start := Time.get_ticks_usec()
	var budget := 14000 if boot else 6000
	while Time.get_ticks_usec() - start < budget:
		if not active:
			var pending: Array = host.get(&"_pending")
			if pending.is_empty():
				return
			start_job(host.call(&"_take_pending") as Vector3i, host)
		advance(host, boot)
		if active:
			return


func start_job(job_coord: Vector3i, host: Node) -> void:
	active = true
	discard = false
	_phase = 0
	coord = job_coord
	_t0 = Time.get_ticks_usec()
	_count = _chunk_size + 3
	_origin = job_coord * _chunk_size - Vector3i.ONE
	var total := _count * _count * _count
	_values = PackedFloat32Array()
	_values.resize(total)
	_materials = PackedByteArray()
	_materials.resize(total)
	_index = 0
	_task = -1
	_packet = {}
	var density_cache: Dictionary = host.get(&"_density_cache")
	if density_cache.size() > 120000:
		density_cache.clear()
		var height_cache: Dictionary = host.get(&"_height_cache")
		height_cache.clear()


func advance(host: Node, boot: bool) -> void:
	if not active:
		return
	if _phase == 0:
		if discard:
			clear()
			return
		_fill(host, boot)
		return
	if _task < 0 or not WorkerThreadPool.is_task_completed(_task):
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	var job_coord := coord
	var was_discard := discard
	var t0 := _t0
	var built: Dictionary = _packet.get("out", {})
	clear()
	if was_discard or built.is_empty():
		return
	var verts: PackedVector3Array = built["verts"]
	if verts.is_empty():
		host.call(&"_free_chunk", job_coord, false)
		var empty: Dictionary = host.get(&"_empty")
		empty[job_coord] = true
		return
	host.call(&"_apply_mesh", job_coord, built, t0)


func clear() -> void:
	active = false
	discard = false
	_phase = 0
	_task = -1
	_packet = {}
	_values = PackedFloat32Array()
	_materials = PackedByteArray()


func _fill(host: Node, boot: bool) -> void:
	var start := Time.get_ticks_usec()
	var n := _count
	var total := n * n * n
	var origin := _origin
	var slice := 8000 if boot else 5000
	while _index < total and Time.get_ticks_usec() - start < slice:
		var i := _index
		var x := i % n
		var y := int(i / n) % n
		var z := int(i / (n * n))
		var voxel := origin + Vector3i(x, y, z)
		_values[i] = float(host.call(&"_corner_density", voxel))
		_materials[i] = int(host.call(&"_material_at_voxel", voxel))
		_index += 1
	if _index < total:
		return
	_packet = {
		"values": _values,
		"materials": _materials,
		"origin": _origin,
		"count": _count,
	}
	_phase = 1
	_task = WorkerThreadPool.add_task(_assemble.bind(_packet))


func _assemble(packet: Dictionary) -> void:
	packet["out"] = TerrainSurfaceBuild.assemble(
		packet["values"],
		packet["materials"],
		packet["origin"],
		int(packet["count"]),
		_voxel,
		_iso,
		_chunk_size
	)
