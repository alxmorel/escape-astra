extends RefCounted
class_name WeatherProfiles

## Weather id profiles + wind sampling (stateless helpers).


static func profile(id: int) -> Dictionary:
	match id:
		1: # CLOUDY
			return pack(0.5, 0.55, 1.15, 0.0, 0.92, 0.85, 0.9, 0.0)
		2: # OVERCAST
			return pack(0.84, 0.78, 1.35, 0.0, 0.78, 0.65, 0.7, 0.0)
		3: # FOG
			return pack(0.42, 0.5, 3.4, 0.0, 0.82, 0.72, 0.78, 0.0)
		4: # RAIN
			return pack(0.9, 0.84, 1.75, 0.68, 0.64, 0.5, 0.55, 0.0)
		5: # STORM
			return pack(1.0, 1.0, 2.15, 1.0, 0.46, 0.3, 0.32, 1.0)
		_:
			return pack(0.18, 0.35, 1.0, 0.0, 1.0, 1.0, 1.0, 0.0)


static func pack(
	coverage: float,
	density: float,
	weather_fog_multiplier: float,
	rain: float,
	ambient: float,
	sun: float,
	sky: float,
	storm: float
) -> Dictionary:
	return {
		"cloud_coverage": coverage,
		"cloud_density": density,
		"weather_fog_multiplier": weather_fog_multiplier,
		"rain_intensity": rain,
		"ambient_light_multiplier": ambient,
		"sun_light_multiplier": sun,
		"sky_brightness": sky,
		"storm_intensity": storm,
	}


static func sanitize(raw: Dictionary, keys: PackedStringArray) -> Dictionary:
	var out := profile(0)
	for key in keys:
		if raw.has(key):
			out[key] = float(raw[key])
	return out


static func wind_sample(rng: RandomNumberGenerator, id: int) -> Dictionary:
	var intensity := 0.0
	var gust := 0.0
	var turn := rng.randf_range(-0.65, 0.65)
	var hold := rng.randf_range(90.0, 190.0)
	match id:
		0: # CLEAR
			if rng.randf() < 0.42:
				intensity = rng.randf_range(0.4, 0.88)
				gust = rng.randf_range(0.1, 0.4)
			else:
				intensity = rng.randf_range(0.0, 0.16)
				gust = rng.randf_range(0.0, 0.08)
		4: # RAIN
			if rng.randf() < 0.38:
				intensity = rng.randf_range(0.22, 0.5)
				gust = rng.randf_range(0.08, 0.28)
			else:
				intensity = rng.randf_range(0.0, 0.18)
				gust = rng.randf_range(0.0, 0.1)
			hold = rng.randf_range(70.0, 160.0)
		5: # STORM
			if rng.randf() < 0.78:
				intensity = rng.randf_range(0.66, 1.0)
				gust = rng.randf_range(0.42, 0.95)
				turn = rng.randf_range(-1.25, 1.25)
			else:
				intensity = rng.randf_range(0.3, 0.58)
				gust = rng.randf_range(0.16, 0.42)
				turn = rng.randf_range(-0.8, 0.8)
			hold = rng.randf_range(48.0, 110.0)
		2: # OVERCAST
			if rng.randf() < 0.22:
				intensity = rng.randf_range(0.14, 0.38)
				gust = rng.randf_range(0.02, 0.14)
			else:
				intensity = rng.randf_range(0.0, 0.12)
				gust = rng.randf_range(0.0, 0.05)
		_:
			if rng.randf() < 0.16:
				intensity = rng.randf_range(0.1, 0.3)
				gust = rng.randf_range(0.0, 0.1)
			else:
				intensity = rng.randf_range(0.0, 0.08)
				gust = rng.randf_range(0.0, 0.04)
	return {
		"intensity": intensity,
		"gust": gust,
		"turn": turn,
		"hold": hold,
	}


static func cloud_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(st, Vector3(0.0, 0.16, 0.0), Vector3(2.2, 0.42, 1.35))
	_box(st, Vector3(0.85, 0.28, 0.2), Vector3(1.35, 0.5, 0.95))
	_box(st, Vector3(-0.8, 0.22, 0.15), Vector3(1.25, 0.46, 0.9))
	_box(st, Vector3(0.1, 0.32, -0.5), Vector3(1.1, 0.38, 0.8))
	_box(st, Vector3(-0.2, 0.12, 0.62), Vector3(0.95, 0.34, 0.7))
	return st.commit()


static func _box(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var h := size * 0.5
	var p: Array[Vector3] = [
		center + Vector3(-h.x, -h.y, -h.z),
		center + Vector3(h.x, -h.y, -h.z),
		center + Vector3(h.x, -h.y, h.z),
		center + Vector3(-h.x, -h.y, h.z),
		center + Vector3(-h.x, h.y, -h.z),
		center + Vector3(h.x, h.y, -h.z),
		center + Vector3(h.x, h.y, h.z),
		center + Vector3(-h.x, h.y, h.z),
	]
	_face(st, p[4], p[5], p[6], p[7])
	_face(st, p[0], p[3], p[2], p[1])
	_face(st, p[0], p[1], p[5], p[4])
	_face(st, p[2], p[3], p[7], p[6])
	_face(st, p[1], p[2], p[6], p[5])
	_face(st, p[3], p[0], p[4], p[7])


static func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var n := (b - a).cross(d - a).normalized()
	for point in [a, b, c, a, c, d]:
		st.set_normal(n)
		st.add_vertex(point)
