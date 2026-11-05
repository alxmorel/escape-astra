extends RefCounted

const DIR := "res://scenes/ui/item_previews/"
const PIECE := preload("res://scripts/building/build_piece.gd")
const FARM := preload("res://scripts/farming/farming_config.gd")

const SHARED := {
	"wooden_pickaxe": "pickaxe",
	"stone_pickaxe": "pickaxe",
	"iron_pickaxe": "pickaxe",
	"wooden_axe": "axe",
	"stone_axe": "axe",
	"iron_axe": "axe",
	"wooden_sword": "sword",
	"stone_sword": "sword",
	"iron_sword": "sword",
	"wooden_shovel": "shovel",
	"wooden_hoe": "hoe",
	"stone_hoe": "hoe",
	"iron_hoe": "hoe",
	"wooden_rake": "hoe",
	"stone_shovel": "shovel",
	"iron_shovel": "shovel",
	"wood_foundation": "foundation",
	"stone_foundation": "foundation",
	"wood_wall": "wall",
	"stone_wall": "wall",
	"wood_window_wall": "window_wall",
	"stone_window_wall": "window_wall",
	"wood_door_wall": "door_wall",
	"stone_door_wall": "door_wall",
	"wood_stairs": "stairs",
	"stone_stairs": "stairs",
	"wood_floor": "floor",
	"stone_floor": "floor",
	"wood_ceiling": "ceiling",
	"stone_ceiling": "ceiling",
}

const MODELS := {
	"wooden_pickaxe": preload("res://assets/models/WoodenPickaxe.glb"),
	"stone_pickaxe": preload("res://assets/models/StonePickaxe.glb"),
	"iron_pickaxe": preload("res://assets/models/IronPickaxe.glb"),
	"wooden_axe": preload("res://assets/models/WoodenAxe.glb"),
	"stone_axe": preload("res://assets/models/StoneAxe.glb"),
	"iron_axe": preload("res://assets/models/IronAxe.glb"),
	"wooden_sword": preload("res://assets/models/wooden_sword.glb"),
	"stone_sword": preload("res://assets/models/stone_sword.glb"),
	"iron_sword": preload("res://assets/models/iron_sword.glb"),
	"wooden_shovel": preload("res://assets/models/WoodenShovel.glb"),
	"stone_shovel": preload("res://assets/models/StoneShovel.glb"),
	"iron_shovel": preload("res://assets/models/IronShovel.glb"),
	"wooden_hoe": preload("res://scenes/items/wooden_hoe.tscn"),
	"stone_hoe": preload("res://scenes/items/stone_hoe.tscn"),
	"iron_hoe": preload("res://scenes/items/iron_hoe.tscn"),
	"furnace": preload("res://assets/models/Four.glb"),
	"flour_grinder": preload("res://assets/models/FlourGrinder.glb"),
	"fermentation_tank": preload("res://assets/models/FermentationTank.glb"),
	"distillery": preload("res://assets/models/Distillery.glb"),
	"torch": preload("res://assets/models/torch.glb"),
	"charcoal": preload("res://assets/models/Charcoal.glb"),
	"iron_ore": preload("res://assets/models/iron_rock_01.glb"),
	"coal": preload("res://assets/models/Coal.glb"),
	"wooden_bow": preload("res://assets/models/wooden_bow.glb"),
	"wooden_arrow": preload("res://assets/models/wooden_arrow.glb"),
}


static func path_for(item_id: String) -> String:
	return DIR + str(SHARED.get(item_id, item_id)) + ".tscn"


static func load_scene(item_id: String) -> PackedScene:
	var path := path_for(item_id)
	if not ResourceLoader.exists(path):
		push_error("Missing item preview scene: %s" % path)
		return null
	return load(path) as PackedScene


static func apply_model(root: Node, item_id: String) -> void:
	var model := root.get_node_or_null(^"World/Model") as Node3D
	if model == null:
		return
	var scene: PackedScene = FARM.scene_for(item_id)
	if scene == null and MODELS.has(item_id):
		scene = MODELS[item_id]
	if scene == null:
		if SHARED.has(item_id):
			for child in model.get_children():
				child.free()
			PIECE.add_preview_visual(model, item_id)
		return
	var placed := Transform3D.IDENTITY
	var has_pose := false
	for child in model.get_children():
		var node := child as Node3D
		if node != null and not has_pose:
			placed = node.transform
			has_pose = true
		child.free()
	var visual := scene.instantiate() as Node3D
	if visual == null:
		return
	if has_pose:
		visual.transform = placed
	model.add_child(visual)
