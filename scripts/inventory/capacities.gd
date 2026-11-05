extends RefCounted
class_name InventoryCapacities

const ToolDurability := preload("res://scripts/items/tool_durability.gd")

const HOTBAR := 9
const BACKPACK := 20
const CHEST := 20
const DOUBLE_CHEST := 40
const GRID_COLUMNS := 5
const MAX_STACK := 100


static func stack_limit(resource_id: String = "") -> int:
	if ToolDurability.has_durability(resource_id):
		return 1
	return MAX_STACK
