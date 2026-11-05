extends RefCounted

const SCENES := {
	"wooden_pickaxe": preload("res://scenes/items/wooden_pickaxe.tscn"),
	"stone_pickaxe": preload("res://scenes/items/stone_pickaxe.tscn"),
	"iron_pickaxe": preload("res://scenes/items/iron_pickaxe.tscn"),
	"wooden_axe": preload("res://scenes/items/wooden_axe.tscn"),
	"stone_axe": preload("res://scenes/items/stone_axe.tscn"),
	"iron_axe": preload("res://scenes/items/iron_axe.tscn"),
	"wooden_sword": preload("res://scenes/items/wooden_sword.tscn"),
	"stone_sword": preload("res://scenes/items/stone_sword.tscn"),
	"iron_sword": preload("res://scenes/items/iron_sword.tscn"),
	"wooden_shovel": preload("res://scenes/items/wooden_shovel.tscn"),
	"stone_shovel": preload("res://scenes/items/stone_shovel.tscn"),
	"iron_shovel": preload("res://scenes/items/iron_shovel.tscn"),
	"wooden_hoe": preload("res://scenes/items/wooden_hoe.tscn"),
	"stone_hoe": preload("res://scenes/items/stone_hoe.tscn"),
	"iron_hoe": preload("res://scenes/items/iron_hoe.tscn"),
	"wooden_rake": preload("res://scenes/items/wooden_rake.tscn"),
	"torch": preload("res://scenes/items/torch.tscn"),
	"wooden_bow": preload("res://scenes/items/wooden_bow.tscn"),
}


static func has_tool(item_id: String) -> bool:
	return SCENES.has(item_id)


static func instantiate(item_id: String) -> Node3D:
	var scene: PackedScene = SCENES.get(item_id)
	if scene == null:
		return null
	return scene.instantiate() as Node3D
