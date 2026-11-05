extends RefCounted

const DRILL_SCRIPT := preload("res://scripts/machines/primitive_drill.gd")
const TOTEM_SCRIPT := preload("res://scripts/machines/camp_totem.gd")
const FURNACE_SCRIPT := preload("res://scripts/machines/furnace.gd")
const FLOUR_GRINDER_SCRIPT := preload("res://scripts/machines/flour_grinder.gd")
const FERMENTATION_TANK_SCRIPT := preload("res://scripts/machines/fermentation_tank.gd")
const DISTILLERY_SCRIPT := preload("res://scripts/machines/distillery.gd")
const TORCH_SCRIPT := preload("res://scripts/machines/torch.gd")
const BUILD := preload("res://scripts/building/build_catalog.gd")
const BUILD_PIECE := preload("res://scripts/building/build_piece.gd")
const FARM := preload("res://scripts/farming/farming_config.gd")

const NAMES := {
	"wood": "Wood",
	"sticks": "Sticks",
	"wood_planks": "Wood Planks",
	"stone": "Stone",
	"iron_ore": "Iron Ore",
	"dirt": "Dirt",
	"charcoal": "Charcoal",
	"coal": "Coal",
	"torch": "Torch",
	"wooden_shovel": "Wooden Shovel",
	"stone_shovel": "Stone Shovel",
	"iron_shovel": "Iron Shovel",
	"wooden_pickaxe": "Wooden Pickaxe",
	"stone_pickaxe": "Stone Pickaxe",
	"iron_pickaxe": "Iron Pickaxe",
	"wooden_axe": "Wooden Axe",
	"stone_axe": "Stone Axe",
	"iron_axe": "Iron Axe",
	"wooden_sword": "Wooden Sword",
	"stone_sword": "Stone Sword",
	"iron_sword": "Iron Sword",
	"wooden_bow": "Wooden Bow",
	"wooden_arrow": "Wooden Arrow",
	"primitive_drill": "Primitive Drill",
	"camp_totem": "Camp Totem",
	"furnace": "Furnace",
	"flour_grinder": "Flour Grinder",
	"fermentation_tank": "Fermentation Tank",
	"distillery": "Distillery",
	"wooden_hoe": "Wooden Hoe",
	"stone_hoe": "Stone Hoe",
	"iron_hoe": "Iron Hoe",
	"wooden_rake": "Wooden Rake",
	"wheat": "Wheat",
	"wheat_seeds": "Wheat Seeds",
	"bread": "Bread",
	"raw_meat": "Raw Meat",
	"hide": "Hide",
}

const USES := {
	"wooden_shovel": "tool",
	"stone_shovel": "tool",
	"iron_shovel": "tool",
	"wooden_pickaxe": "tool",
	"stone_pickaxe": "tool",
	"iron_pickaxe": "tool",
	"wooden_axe": "tool",
	"stone_axe": "tool",
	"iron_axe": "tool",
	"wooden_sword": "tool",
	"stone_sword": "tool",
	"iron_sword": "tool",
	"wooden_bow": "bow",
	"primitive_drill": "place",
	"camp_totem": "place",
	"furnace": "place",
	"flour_grinder": "place",
	"fermentation_tank": "place",
	"distillery": "place",
	"wooden_hoe": "tool",
	"stone_hoe": "tool",
	"iron_hoe": "tool",
	"wooden_rake": "tool",
	"wheat_seeds": "plant",
	"bread": "consume",
	"raw_meat": "consume",
	"torch": "torch",
}

const RECIPES: Array[Dictionary] = [
	{
		"result_id": "sticks",
		"result_amount": 10,
		"category": "Resources",
		"ingredients": {"wood_planks": 1},
	},
	{
		"result_id": "wood_planks",
		"result_amount": 10,
		"category": "Resources",
		"ingredients": {"wood": 1},
	},
	{
		"result_id": "wooden_pickaxe",
		"result_amount": 1,
		"category": "Tools",
		"ingredients": {"sticks": 5, "wood": 5},
	},
	{
		"result_id": "stone_pickaxe",
		"result_amount": 1,
		"category": "Tools",
		"ingredients": {"sticks": 5, "stone": 5},
	},
	{
		"result_id": "iron_pickaxe",
		"result_amount": 1,
		"category": "Tools",
		"ingredients": {"sticks": 5, "iron_ore": 3},
	},
	{
		"result_id": "wooden_axe",
		"result_amount": 1,
		"category": "Tools",
		"ingredients": {"sticks": 5, "wood": 5},
	},
	{
		"result_id": "stone_axe",
		"result_amount": 1,
		"category": "Tools",
		"ingredients": {"sticks": 5, "stone": 5},
	},
	{
		"result_id": "iron_axe",
		"result_amount": 1,
		"category": "Tools",
		"ingredients": {"sticks": 5, "iron_ore": 3},
	},
	{
		"result_id": "wooden_sword",
		"result_amount": 1,
		"category": "Tools",
		"ingredients": {"sticks": 5, "wood": 5},
	},
	{
		"result_id": "stone_sword",
		"result_amount": 1,
		"category": "Tools",
		"ingredients": {"sticks": 5, "stone": 5},
	},
	{
		"result_id": "iron_sword",
		"result_amount": 1,
		"category": "Tools",
		"ingredients": {"sticks": 5, "iron_ore": 3},
	},
	{
		"result_id": "wooden_shovel",
		"result_amount": 1,
		"category": "Tools",
		"ingredients": {"sticks": 5, "wood": 5},
	},
	{
		"result_id": "stone_shovel",
		"result_amount": 1,
		"category": "Tools",
		"ingredients": {"sticks": 5, "stone": 5},
	},
	{
		"result_id": "iron_shovel",
		"result_amount": 1,
		"category": "Tools",
		"ingredients": {"sticks": 5, "iron_ore": 3},
	},
	{
		"result_id": "primitive_drill",
		"result_amount": 1,
		"category": "Machines",
		"ingredients": {"sticks": 200, "stone": 100, "wood_planks": 20},
	},
	{
		"result_id": "camp_totem",
		"result_amount": 1,
		"category": "Machines",
		"ingredients": {"wood_planks": 100, "stone": 100},
	},
	{
		"result_id": "furnace",
		"result_amount": 1,
		"category": "Machines",
		"ingredients": {"stone": 10, "dirt": 10},
	},
	{
		"result_id": "flour_grinder",
		"result_amount": 1,
		"category": "Machines",
		"ingredients": {"wood": 30},
	},
	{
		"result_id": "fermentation_tank",
		"result_amount": 1,
		"category": "Machines",
		"ingredients": {"wood": 50, "iron_ore": 10},
	},
	{
		"result_id": "distillery",
		"result_amount": 1,
		"category": "Machines",
		"ingredients": {"wood": 100, "iron_ore": 50},
	},
	{
		"result_id": "wooden_hoe",
		"result_amount": 1,
		"category": "Tools",
		"ingredients": {"sticks": 5, "wood": 5},
	},
	{
		"result_id": "stone_hoe",
		"result_amount": 1,
		"category": "Tools",
		"ingredients": {"sticks": 5, "stone": 5},
	},
	{
		"result_id": "iron_hoe",
		"result_amount": 1,
		"category": "Tools",
		"ingredients": {"sticks": 5, "iron_ore": 3},
	},
	{
		"result_id": "bread",
		"result_amount": 1,
		"category": "Resources",
		"ingredients": {"wheat": 3},
	},
	{
		"result_id": "torch",
		"result_amount": 10,
		"category": "Resources",
		"ingredients": {"sticks": 10, "charcoal": 2},
	},
	{
		"result_id": "wooden_bow",
		"result_amount": 1,
		"category": "Tools",
		"ingredients": {"sticks": 8, "wood": 6},
	},
	{
		"result_id": "wooden_arrow",
		"result_amount": 8,
		"category": "Tools",
		"ingredients": {"sticks": 4},
	},
]

static var _all_recipes: Array[Dictionary] = []


static func all_recipes() -> Array[Dictionary]:
	if not _all_recipes.is_empty():
		return _all_recipes
	for recipe in RECIPES:
		_all_recipes.append(recipe)
	return _all_recipes


static func build_recipes() -> Array[Dictionary]:
	return BUILD.recipes()


static func ingredients_of(piece_id: String) -> Dictionary:
	return BUILD.ingredients_of(piece_id)


static func refund_of(piece_id: String) -> Dictionary:
	return BUILD.refund_of(piece_id)


static func use_of(resource_id: String) -> String:
	if USES.has(resource_id):
		return str(USES[resource_id])
	return ""


static func kind_of(resource_id: String) -> String:
	return BUILD.kind_of(resource_id)


static func is_construction(resource_id: String) -> bool:
	return BUILD.has_piece(resource_id)


static func build_actions(resource_id: String, demolish: bool = false) -> PackedStringArray:
	if demolish:
		return BUILD.build_actions("", true)
	if not is_construction(resource_id):
		return PackedStringArray()
	return BUILD.build_actions(kind_of(resource_id), false)


static func build_action_text(action: String) -> String:
	return BUILD.action_text(action)


static func placeable_script(resource_id: String) -> Script:
	if BUILD.has_piece(resource_id):
		return BUILD_PIECE
	if resource_id == "primitive_drill":
		return DRILL_SCRIPT
	if resource_id == "camp_totem":
		return TOTEM_SCRIPT
	if resource_id == "furnace":
		return FURNACE_SCRIPT
	if resource_id == "flour_grinder":
		return FLOUR_GRINDER_SCRIPT
	if resource_id == "fermentation_tank":
		return FERMENTATION_TANK_SCRIPT
	if resource_id == "distillery":
		return DISTILLERY_SCRIPT
	if resource_id == "torch":
		return TORCH_SCRIPT
	return null


static func display_name(resource_id: String) -> String:
	var key := "ITEM_" + resource_id.to_upper()
	var translated := TranslationServer.translate(key)
	if translated != key:
		return translated
	if NAMES.has(resource_id):
		return str(NAMES[resource_id])
	var built := BUILD.display_name(resource_id)
	return built if not built.is_empty() else resource_id


static func tooltip_text(resource_id: String) -> String:
	var label := display_name(resource_id)
	var restored := FARM.food_hunger(resource_id)
	if restored <= 0.0:
		return label
	return "%s\n%s" % [label, TranslationServer.translate("TOOLTIP_HUNGER") % int(round(restored))]
