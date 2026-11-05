extends RefCounted
class_name PlanetHeight

## Noise + landmark features → terrain height / crater / rocky.

var biome := FastNoiseLite.new()
var shape := FastNoiseLite.new()
var hills := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var feature_dirs := PackedVector3Array()
var feature_radius := PackedFloat32Array()
var feature_amount := PackedFloat32Array()
var feature_kind := PackedInt32Array()


func configure(host: Node) -> void:
	var scale := maxf(float(host.get(&"biome_scale")), 8.0)
	var world_seed := int(host.get(&"world_seed"))
	_setup_noise(biome, world_seed + 11, 1.0 / scale, 1)
	_setup_noise(shape, world_seed + 29, 0.82 / scale, 1)
	_setup_noise(hills, world_seed + 47, 1.7 / scale, 2)
	_setup_noise(detail, world_seed + 71, 3.1 / scale, 1)


func build_features(host: Node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(host.get(&"world_seed")) + 91
	feature_dirs = PackedVector3Array()
	feature_radius = PackedFloat32Array()
	feature_amount = PackedFloat32Array()
	feature_kind = PackedInt32Array()
	var count := maxi(int(host.get(&"landmark_count")), 1)
	var water_level := float(host.get(&"_water_level"))
	var terrain_relief := float(host.get(&"terrain_relief"))
	for i in count:
		var dir := Vector3.UP
		for _attempt in 8:
			var y := rng.randf_range(-0.85, 0.85)
			var ring := sqrt(maxf(0.0, 1.0 - y * y))
			var theta := rng.randf() * TAU
			dir = Vector3(cos(theta) * ring, y, sin(theta) * ring).normalized()
			if height(host, dir) > water_level + 0.35:
				break
		feature_dirs.append(dir)
		if i == 0:
			feature_kind.append(0)
			feature_radius.append(0.2)
			feature_amount.append(2.6 * terrain_relief)
		elif i == 1:
			feature_kind.append(1)
			feature_radius.append(0.11)
			feature_amount.append(2.4 * terrain_relief)
		else:
			feature_kind.append(0)
			feature_radius.append(rng.randf_range(0.09, 0.14))
			feature_amount.append(rng.randf_range(1.3, 1.9) * terrain_relief)


func height(host: Node, direction: Vector3) -> float:
	var dir := direction.normalized()
	var base_radius := float(host.get(&"base_radius"))
	var point := dir * base_radius
	var region := unit_noise(biome, point)
	var relief := float(host.get(&"terrain_relief"))
	var hill_amplitude := float(host.get(&"hill_amplitude"))
	var plateau_frequency := float(host.get(&"plateau_frequency"))
	var hill_mask := smoothstep(0.3, 0.5, region) * (1.0 - smoothstep(0.74, 0.9, region))
	var plains := detail.get_noise_3d(point.x, point.y, point.z) * 0.32 * relief
	var hills_v := hills.get_noise_3d(point.x, point.y, point.z) * hill_amplitude * 0.62 * relief * hill_mask
	var terrace_n := unit_noise(hills, point * 0.82)
	var terraces := smoothstep(0.4, 0.48, terrace_n) * 0.9
	terraces += smoothstep(0.64, 0.72, terrace_n) * 1.05
	terraces *= hill_mask * relief
	var edge := lerpf(0.86, 0.58, clampf(plateau_frequency, 0.0, 1.0))
	var shelf := smoothstep(edge, edge + 0.07, unit_noise(shape, point))
	plains *= 1.0 - shelf * 0.55
	hills_v *= 1.0 - shelf * 0.85
	terraces *= 1.0 - shelf
	var plateau := shelf * 4.3 * relief
	return base_radius + plains + hills_v + terraces + plateau + landmark_height(dir)


func landmark_height(dir: Vector3) -> float:
	var delta := 0.0
	for i in feature_dirs.size():
		var angle := acos(clampf(dir.dot(feature_dirs[i]), -1.0, 1.0))
		var radius: float = feature_radius[i]
		var u := angle / maxf(radius, 0.02)
		if u >= 1.15:
			continue
		var amount: float = feature_amount[i]
		if feature_kind[i] == 0:
			var bowl := smoothstep(1.0, 0.18, u)
			var rim := smoothstep(0.72, 0.94, u) * (1.0 - smoothstep(0.94, 1.12, u))
			delta += -bowl * amount + rim * amount * 0.28
		else:
			delta += exp(-u * u * 2.6) * amount
	return delta


func crater_mask(dir: Vector3) -> float:
	var mask := 0.0
	for i in feature_dirs.size():
		if feature_kind[i] != 0:
			continue
		var angle := acos(clampf(dir.dot(feature_dirs[i]), -1.0, 1.0))
		var u := angle / maxf(feature_radius[i], 0.02)
		mask = maxf(mask, smoothstep(0.95, 0.35, u))
	return mask


func rocky_amount(host: Node, dir: Vector3) -> float:
	var base_radius := float(host.get(&"base_radius"))
	var plateau_frequency := float(host.get(&"plateau_frequency"))
	var region := unit_noise(biome, dir * base_radius)
	var edge := lerpf(0.86, 0.58, clampf(plateau_frequency, 0.0, 1.0))
	var rocky := smoothstep(edge - 0.04, edge + 0.12, unit_noise(shape, dir * base_radius))
	return maxf(rocky, smoothstep(0.7, 0.88, region) * 0.65)


func ground_color(weights: PackedFloat32Array, rock_mix: float) -> Color:
	var color := Color(0.46, 0.62, 0.3) * weights[0]
	color += Color(0.22, 0.36, 0.16) * weights[1]
	color += Color(0.55, 0.52, 0.46) * weights[2]
	color += Color(0.3, 0.44, 0.32) * weights[3]
	color += Color(0.28, 0.26, 0.24) * weights[4]
	return color.lerp(Color(0.5, 0.47, 0.42), rock_mix)


func unit_noise(noise: FastNoiseLite, point: Vector3) -> float:
	return noise.get_noise_3d(point.x, point.y, point.z) * 0.5 + 0.5


func _setup_noise(noise: FastNoiseLite, noise_seed: int, frequency: float, octaves: int) -> void:
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	noise.frequency = frequency
