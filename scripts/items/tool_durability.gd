extends RefCounted

const RECIPES := preload("res://scripts/resources/recipe_catalog.gd")

## Durabilité max par outil (usure = 1 par usage réussi).
const MAX := {
	"wooden_pickaxe": 64,
	"stone_pickaxe": 128,
	"iron_pickaxe": 256,
	"wooden_axe": 64,
	"stone_axe": 128,
	"iron_axe": 256,
	"wooden_sword": 64,
	"stone_sword": 128,
	"iron_sword": 256,
	"wooden_shovel": 64,
	"stone_shovel": 128,
	"iron_shovel": 256,
	"wooden_hoe": 64,
	"stone_hoe": 128,
	"iron_hoe": 256,
	"wooden_rake": 64,
	"wooden_bow": 80,
}

const WEAR_PER_USE := 1


static func is_tool(resource_id: String) -> bool:
	var use := RECIPES.use_of(resource_id)
	return use == "tool" or use == "bow"


static func max_of(resource_id: String) -> int:
	if MAX.has(resource_id):
		return int(MAX[resource_id])
	if is_tool(resource_id):
		return 64
	return 0


static func has_durability(resource_id: String) -> bool:
	return max_of(resource_id) > 0
