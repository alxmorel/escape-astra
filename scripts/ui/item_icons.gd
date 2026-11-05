extends RefCounted

const BUILD := preload("res://scripts/building/build_catalog.gd")

static var _cache: Dictionary = {}


static func get_texture(resource_id: String) -> Texture2D:
	if _cache.has(resource_id):
		return _cache[resource_id]
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	if BUILD.has_piece(resource_id):
		_draw_build(image, BUILD.kind_of(resource_id), BUILD.material_of(resource_id))
	else:
		match resource_id:
			"wood":
				_draw_wood(image)
			"sticks":
				_draw_sticks(image)
			"wood_planks":
				_draw_planks(image)
			"stone":
				_draw_stone(image)
			"iron_ore":
				_draw_iron_ore(image)
			"dirt":
				_draw_dirt(image)
			"charcoal":
				_draw_charcoal(image)
			"coal":
				_draw_coal(image)
			"torch":
				_draw_torch(image)
			"wooden_shovel":
				_draw_shovel(image, Color(0.55, 0.4, 0.22), Color(0.32, 0.22, 0.12), Color(0.44, 0.3, 0.16))
			"stone_shovel":
				_draw_shovel(image, Color(0.62, 0.62, 0.64), Color(0.32, 0.32, 0.34), Color(0.48, 0.48, 0.5))
			"iron_shovel":
				_draw_shovel(image, Color(0.78, 0.8, 0.84), Color(0.42, 0.46, 0.52), Color(0.62, 0.66, 0.72))
			"wooden_pickaxe":
				_draw_pickaxe(image, Color(0.72, 0.74, 0.76), Color(0.4, 0.42, 0.44), Color(0.56, 0.58, 0.6))
			"stone_pickaxe":
				_draw_pickaxe(image, Color(0.62, 0.62, 0.64), Color(0.32, 0.32, 0.34), Color(0.48, 0.48, 0.5))
			"iron_pickaxe":
				_draw_pickaxe(image, Color(0.78, 0.8, 0.84), Color(0.42, 0.46, 0.52), Color(0.62, 0.66, 0.72))
			"wooden_axe":
				_draw_axe(image, Color(0.72, 0.74, 0.76), Color(0.4, 0.42, 0.44), Color(0.56, 0.58, 0.6))
			"stone_axe":
				_draw_axe(image, Color(0.62, 0.62, 0.64), Color(0.32, 0.32, 0.34), Color(0.48, 0.48, 0.5))
			"iron_axe":
				_draw_axe(image, Color(0.78, 0.8, 0.84), Color(0.42, 0.46, 0.52), Color(0.62, 0.66, 0.72))
			"wooden_sword":
				_draw_sword(image, Color(0.72, 0.5, 0.26), Color(0.38, 0.24, 0.11), Color(0.52, 0.33, 0.16))
			"stone_sword":
				_draw_sword(image, Color(0.62, 0.62, 0.64), Color(0.32, 0.32, 0.34), Color(0.48, 0.48, 0.5))
			"iron_sword":
				_draw_sword(image, Color(0.78, 0.8, 0.84), Color(0.42, 0.46, 0.52), Color(0.62, 0.66, 0.72))
			"primitive_drill":
				_draw_drill(image)
			"camp_totem":
				_draw_totem(image)
			"furnace":
				_draw_furnace(image)
			"flour_grinder":
				_draw_flour_grinder(image)
			"fermentation_tank":
				_draw_fermentation_tank(image)
			"distillery":
				_draw_distillery(image)
			"wooden_hoe":
				_draw_shovel(image, Color(0.55, 0.38, 0.18), Color(0.32, 0.22, 0.12), Color(0.44, 0.3, 0.16))
			"stone_hoe":
				_draw_shovel(image, Color(0.62, 0.62, 0.64), Color(0.32, 0.32, 0.34), Color(0.48, 0.48, 0.5))
			"iron_hoe":
				_draw_shovel(image, Color(0.78, 0.8, 0.84), Color(0.42, 0.46, 0.52), Color(0.62, 0.66, 0.72))
			"wooden_rake":
				_cube(image, 16, 6, Color(0.55, 0.48, 0.28), Color(0.32, 0.28, 0.14), Color(0.44, 0.38, 0.18), 8)
			"wheat":
				_cube(image, 16, 8, Color(0.92, 0.76, 0.26), Color(0.62, 0.46, 0.14), Color(0.78, 0.6, 0.18), 7)
			"wheat_seeds":
				_cube(image, 16, 12, Color(0.8, 0.64, 0.3), Color(0.5, 0.36, 0.14), Color(0.66, 0.48, 0.2), 5)
			"bread":
				_cube(image, 16, 8, Color(0.84, 0.56, 0.26), Color(0.52, 0.32, 0.14), Color(0.7, 0.42, 0.18), 7)
			"raw_meat":
				_cube(image, 16, 10, Color(0.78, 0.28, 0.28), Color(0.48, 0.14, 0.14), Color(0.62, 0.2, 0.2), 6)
			"hide":
				_cube(image, 16, 9, Color(0.72, 0.52, 0.3), Color(0.42, 0.28, 0.14), Color(0.56, 0.38, 0.2), 7)
			"wooden_bow":
				_cube(image, 16, 7, Color(0.62, 0.42, 0.2), Color(0.38, 0.24, 0.1), Color(0.5, 0.32, 0.14), 8)
			"wooden_arrow":
				_cube(image, 16, 10, Color(0.7, 0.55, 0.28), Color(0.4, 0.28, 0.12), Color(0.55, 0.4, 0.18), 5)
			_:
				_cube(image, 16, 6, Color(0.55, 0.55, 0.55), Color(0.32, 0.32, 0.32), Color(0.42, 0.42, 0.42), 8)
	var texture := ImageTexture.create_from_image(image)
	_cache[resource_id] = texture
	return texture


static func _draw_wood(image: Image) -> void:
	_cube(image, 16, 4, Color(0.72, 0.5, 0.26), Color(0.38, 0.24, 0.11), Color(0.52, 0.33, 0.16), 9)
	var ring := Color(0.86, 0.68, 0.4)
	_px(image, 16, 8, ring)
	_px(image, 14, 10, ring)
	_px(image, 18, 10, ring)
	_px(image, 16, 11, ring)


static func _draw_sticks(image: Image) -> void:
	var top := Color(0.62, 0.42, 0.2)
	var left := Color(0.34, 0.22, 0.1)
	var right := Color(0.48, 0.32, 0.15)
	_cube(image, 11, 14, top, left, right, 4)
	_cube(image, 17, 8, top, left, right, 4)
	_cube(image, 22, 15, top, left, right, 4)


static func _draw_planks(image: Image) -> void:
	_cube(image, 16, 5, Color(0.84, 0.68, 0.4), Color(0.52, 0.38, 0.2), Color(0.68, 0.5, 0.28), 9)
	var seam := Color(0.38, 0.26, 0.14)
	_px(image, 18, 16, seam)
	_px(image, 20, 16, seam)
	_px(image, 22, 16, seam)
	_px(image, 18, 19, seam)
	_px(image, 20, 19, seam)


static func _draw_dirt(image: Image) -> void:
	_cube(image, 16, 6, Color(0.48, 0.34, 0.18), Color(0.28, 0.18, 0.1), Color(0.38, 0.26, 0.14), 8)


static func _draw_charcoal(image: Image) -> void:
	_cube(image, 16, 8, Color(0.22, 0.2, 0.18), Color(0.1, 0.09, 0.08), Color(0.16, 0.14, 0.12), 7)
	_cube(image, 16, 10, Color(0.32, 0.28, 0.24), Color(0.16, 0.14, 0.12), Color(0.24, 0.2, 0.16), 4)


static func _draw_coal(image: Image) -> void:
	_cube(image, 16, 7, Color(0.14, 0.14, 0.16), Color(0.06, 0.06, 0.08), Color(0.1, 0.1, 0.12), 8)
	_cube(image, 16, 10, Color(0.22, 0.22, 0.26), Color(0.1, 0.1, 0.12), Color(0.16, 0.16, 0.18), 4)


static func _draw_torch(image: Image) -> void:
	var wood := Color(0.58, 0.4, 0.2)
	var wood_l := Color(0.32, 0.22, 0.1)
	var wood_r := Color(0.46, 0.3, 0.14)
	_cube(image, 16, 12, wood, wood_l, wood_r, 3)
	_cube(image, 16, 8, wood, wood_l, wood_r, 2)
	_cube(image, 16, 4, Color(0.95, 0.7, 0.2), Color(0.85, 0.35, 0.08), Color(0.9, 0.5, 0.12), 3)
	_px(image, 16, 3, Color(1.0, 0.92, 0.45))


static func _draw_shovel(image: Image, top: Color, left: Color, right: Color) -> void:
	var wood := Color(0.62, 0.42, 0.2)
	var dark := Color(0.34, 0.22, 0.1)
	for i in 10:
		_px(image, 12 + i, 22 - i, wood)
		_px(image, 13 + i, 22 - i, dark)
	_cube(image, 22, 3, top, left, right, 4)


static func _draw_stone(image: Image) -> void:
	_cube(image, 16, 6, Color(0.68, 0.68, 0.7), Color(0.4, 0.4, 0.42), Color(0.52, 0.52, 0.55), 8)


static func _draw_iron_ore(image: Image) -> void:
	_cube(image, 16, 6, Color(0.58, 0.46, 0.4), Color(0.34, 0.26, 0.22), Color(0.46, 0.34, 0.3), 8)
	var fleck := Color(0.78, 0.82, 0.86)
	_px(image, 14, 12, fleck)
	_px(image, 18, 14, fleck)
	_px(image, 16, 17, fleck)


static func _draw_pickaxe(image: Image, top: Color, left: Color, right: Color) -> void:
	var wood := Color(0.62, 0.42, 0.2)
	var dark := Color(0.34, 0.22, 0.1)
	for i in 10:
		_px(image, 10 + i, 22 - i, wood)
		_px(image, 11 + i, 22 - i, dark)
	_cube(image, 22, 4, top, left, right, 4)


static func _draw_axe(image: Image, top: Color, left: Color, right: Color) -> void:
	var wood := Color(0.62, 0.42, 0.2)
	var dark := Color(0.34, 0.22, 0.1)
	for i in 10:
		_px(image, 12 + i, 22 - i, wood)
		_px(image, 13 + i, 22 - i, dark)
	_cube(image, 22, 3, top, left, right, 3)
	_cube(image, 18, 6, top, left, right, 3)


static func _draw_sword(image: Image, top: Color, left: Color, right: Color) -> void:
	var wood := Color(0.55, 0.38, 0.18)
	var dark := Color(0.32, 0.22, 0.1)
	for i in 8:
		_px(image, 15, 22 - i, wood)
		_px(image, 16, 22 - i, dark)
	_cube(image, 16, 4, top, left, right, 3)
	_cube(image, 16, 8, top, left, right, 5)
	_px(image, 16, 3, top)


static func _draw_drill(image: Image) -> void:
	_cube(image, 16, 8, Color(0.42, 0.44, 0.48), Color(0.2, 0.22, 0.24), Color(0.32, 0.34, 0.36), 7)
	_cube(image, 16, 18, Color(0.22, 0.22, 0.24), Color(0.1, 0.1, 0.12), Color(0.16, 0.16, 0.18), 3)


static func _draw_build(image: Image, kind: String, material: String) -> void:
	var top := Color(0.72, 0.5, 0.26)
	var left := Color(0.38, 0.24, 0.11)
	var right := Color(0.52, 0.33, 0.16)
	if material == "stone":
		top = Color(0.7, 0.7, 0.72)
		left = Color(0.4, 0.4, 0.42)
		right = Color(0.54, 0.54, 0.56)
	match kind:
		"wall", "window_wall", "door_wall":
			_cube(image, 16, 3, top, left, right, 6)
		"ceiling":
			_cube(image, 16, 8, top, left, right, 8)
		"floor":
			_cube(image, 16, 11, top, left, right, 8)
		"stairs":
			_cube(image, 10, 16, top, left, right, 3)
			_cube(image, 16, 11, top, left, right, 3)
			_cube(image, 22, 6, top, left, right, 3)
		"chest":
			_cube(image, 16, 10, top, left, right, 7)
			_px(image, 16, 14, Color(0.86, 0.72, 0.28))
		"double_chest":
			_cube(image, 11, 10, top, left, right, 5)
			_cube(image, 21, 10, top, left, right, 5)
		_:
			_cube(image, 16, 13, top, left, right, 8)
	if kind == "window_wall":
		for y in range(8, 12):
			for x in range(14, 19):
				_px(image, x, y, Color(0, 0, 0, 0))
	elif kind == "door_wall":
		for y in range(10, 18):
			for x in range(13, 20):
				_px(image, x, y, Color(0, 0, 0, 0))


static func _draw_totem(image: Image) -> void:
	_cube(image, 16, 16, Color(0.55, 0.55, 0.58), Color(0.32, 0.32, 0.34), Color(0.44, 0.44, 0.46), 5)
	_cube(image, 16, 8, Color(0.62, 0.4, 0.2), Color(0.34, 0.2, 0.1), Color(0.48, 0.3, 0.14), 3)
	_cube(image, 16, 3, Color(0.72, 0.84, 0.7), Color(0.4, 0.52, 0.38), Color(0.55, 0.66, 0.5), 2)


static func _draw_furnace(image: Image) -> void:
	_cube(image, 16, 10, Color(0.55, 0.5, 0.46), Color(0.32, 0.28, 0.24), Color(0.44, 0.4, 0.36), 8)
	_cube(image, 16, 6, Color(0.62, 0.58, 0.52), Color(0.36, 0.32, 0.28), Color(0.48, 0.44, 0.4), 5)
	var mouth := Color(0.12, 0.08, 0.06)
	_px(image, 14, 14, mouth)
	_px(image, 15, 14, mouth)
	_px(image, 16, 14, mouth)
	_px(image, 17, 14, mouth)
	_px(image, 15, 15, mouth)
	_px(image, 16, 15, mouth)


static func _draw_flour_grinder(image: Image) -> void:
	_cube(image, 16, 12, Color(0.62, 0.48, 0.28), Color(0.36, 0.26, 0.14), Color(0.5, 0.36, 0.18), 7)
	_cube(image, 16, 8, Color(0.72, 0.58, 0.34), Color(0.42, 0.3, 0.16), Color(0.56, 0.42, 0.22), 4)
	_cube(image, 16, 5, Color(0.5, 0.48, 0.46), Color(0.3, 0.28, 0.26), Color(0.4, 0.38, 0.36), 3)


static func _draw_fermentation_tank(image: Image) -> void:
	_cube(image, 16, 8, Color(0.52, 0.56, 0.6), Color(0.3, 0.34, 0.38), Color(0.42, 0.46, 0.5), 7)
	_cube(image, 16, 6, Color(0.6, 0.64, 0.68), Color(0.36, 0.4, 0.44), Color(0.48, 0.52, 0.56), 5)
	var band := Color(0.4, 0.32, 0.2)
	_px(image, 12, 14, band)
	_px(image, 13, 14, band)
	_px(image, 18, 14, band)
	_px(image, 19, 14, band)


static func _draw_distillery(image: Image) -> void:
	_cube(image, 13, 10, Color(0.58, 0.52, 0.42), Color(0.34, 0.3, 0.22), Color(0.46, 0.4, 0.3), 6)
	_cube(image, 20, 8, Color(0.66, 0.68, 0.72), Color(0.4, 0.42, 0.46), Color(0.52, 0.54, 0.58), 5)
	_cube(image, 20, 4, Color(0.72, 0.74, 0.78), Color(0.44, 0.46, 0.5), Color(0.56, 0.58, 0.62), 3)


static func _cube(image: Image, cx: int, top_y: int, top: Color, left: Color, right: Color, radius: int) -> void:
	for row in radius:
		for x in range(cx - row, cx + row + 1):
			_px(image, x, top_y + row, top)
	var hinge := top_y + radius - 1
	for row in radius:
		var y := hinge + row
		for x in range(cx - radius + 1 + row, cx + 1):
			_px(image, x, y, left)
		for x in range(cx + 1, cx + radius - row + 1):
			_px(image, x, y, right)


static func _px(image: Image, x: int, y: int, color: Color) -> void:
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return
	image.set_pixel(x, y, color)
