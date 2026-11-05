extends RefCounted
class_name TerrainSurfaceBuild

const MC := preload("res://scripts/terrain/marching_cubes.gd")


static func assemble(
	values: PackedFloat32Array,
	materials: PackedByteArray,
	origin_v: Vector3i,
	n: int,
	voxel: float,
	iso: float,
	chunk_size: int
) -> Dictionary:
	var raw: Dictionary = MC.polygonize(values, materials, n, Vector3(origin_v) * voxel, voxel, iso, 1, chunk_size)
	var source: PackedVector3Array = raw["positions"]
	var source_mats: PackedByteArray = raw["materials"]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var mats := PackedByteArray()
	var faces := PackedVector3Array()
	var tri_count := int(source.size() / 3)
	for tri in tri_count:
		var a := source[tri * 3]
		var b := source[tri * 3 + 1]
		var c := source[tri * 3 + 2]
		var ma := int(source_mats[tri * 3])
		var mb := int(source_mats[tri * 3 + 1])
		var mc := int(source_mats[tri * 3 + 2])
		var rh := (b - a).cross(c - a)
		if rh.length_squared() < 0.000001:
			continue
		var na := _air_from_grid(values, origin_v, n, a, voxel)
		var nb := _air_from_grid(values, origin_v, n, b, voxel)
		var nc := _air_from_grid(values, origin_v, n, c, voxel)
		var outward := na + nb + nc
		if outward.length_squared() < 0.000001:
			outward = (a + b + c).normalized()
		if rh.dot(outward) < 0.0:
			var swap := b
			b = c
			c = swap
			var swap_m := mb
			mb = mc
			mc = swap_m
			var swap_n := nb
			nb = nc
			nc = swap_n
		verts.append(a)
		verts.append(c)
		verts.append(b)
		norms.append(na)
		norms.append(nc)
		norms.append(nb)
		mats.append(ma)
		mats.append(mc)
		mats.append(mb)
		faces.append(a)
		faces.append(b)
		faces.append(c)
	return {"verts": verts, "norms": norms, "mats": mats, "faces": faces}


static func _air_from_grid(
	values: PackedFloat32Array,
	origin_v: Vector3i,
	n: int,
	pos: Vector3,
	voxel: float
) -> Vector3:
	var step := voxel * 0.5
	var gradient := Vector3(
		_sample_grid(values, origin_v, n, pos + Vector3(step, 0.0, 0.0), voxel)
		- _sample_grid(values, origin_v, n, pos - Vector3(step, 0.0, 0.0), voxel),
		_sample_grid(values, origin_v, n, pos + Vector3(0.0, step, 0.0), voxel)
		- _sample_grid(values, origin_v, n, pos - Vector3(0.0, step, 0.0), voxel),
		_sample_grid(values, origin_v, n, pos + Vector3(0.0, 0.0, step), voxel)
		- _sample_grid(values, origin_v, n, pos - Vector3(0.0, 0.0, step), voxel)
	)
	if gradient.length_squared() < 0.000001:
		return pos.normalized()
	return -gradient.normalized()


static func _sample_grid(
	values: PackedFloat32Array,
	origin_v: Vector3i,
	n: int,
	pos: Vector3,
	voxel: float
) -> float:
	var g := pos / voxel - Vector3(origin_v)
	var x0 := floori(g.x)
	var y0 := floori(g.y)
	var z0 := floori(g.z)
	if x0 < 0 or y0 < 0 or z0 < 0 or x0 >= n - 1 or y0 >= n - 1 or z0 >= n - 1:
		return values[clampi(x0, 0, n - 1) + n * (clampi(y0, 0, n - 1) + n * clampi(z0, 0, n - 1))]
	var tx := g.x - float(x0)
	var ty := g.y - float(y0)
	var tz := g.z - float(z0)
	var x1 := x0 + 1
	var y1 := y0 + 1
	var z1 := z0 + 1
	var c00 := lerpf(values[x0 + n * (y0 + n * z0)], values[x1 + n * (y0 + n * z0)], tx)
	var c10 := lerpf(values[x0 + n * (y1 + n * z0)], values[x1 + n * (y1 + n * z0)], tx)
	var c01 := lerpf(values[x0 + n * (y0 + n * z1)], values[x1 + n * (y0 + n * z1)], tx)
	var c11 := lerpf(values[x0 + n * (y1 + n * z1)], values[x1 + n * (y1 + n * z1)], tx)
	return lerpf(lerpf(c00, c10, ty), lerpf(c01, c11, ty), tz)
