extends RefCounted
class_name PendingCrafts

const CursorStack := preload("res://scripts/inventory/cursor_stack.gd")

var lots: Array[Dictionary] = []


func is_empty() -> bool:
	return lots.is_empty()


func is_active_for(cursor: CursorStack) -> bool:
	if cursor == null or cursor.is_empty() or lots.is_empty():
		return false
	return total_for(cursor.resource_id) > 0


func clear() -> void:
	lots.clear()


func push(result_id: String, amount: int, ingredients: Dictionary) -> void:
	if result_id.is_empty() or amount <= 0:
		return
	lots.append({
		"result_id": result_id,
		"amount": amount,
		"ingredients": ingredients.duplicate(),
	})


func total_for(result_id: String) -> int:
	var total := 0
	for lot in lots:
		if str(lot["result_id"]) == result_id:
			total += int(lot["amount"])
	return total


func validate_deposited(result_id: String, qty: int) -> void:
	if result_id.is_empty() or qty <= 0 or lots.is_empty():
		return
	var left := qty
	var i := 0
	while left > 0 and i < lots.size():
		var lot: Dictionary = lots[i]
		if str(lot["result_id"]) != result_id:
			i += 1
			continue
		var amount := int(lot["amount"])
		var take := mini(left, amount)
		if take >= amount:
			lots.remove_at(i)
			left -= take
			continue
		var new_amount := amount - take
		var ings: Dictionary = lot["ingredients"]
		var adjusted: Dictionary = {}
		for key in ings:
			adjusted[key] = int(ings[key]) * new_amount / amount
		lot["amount"] = new_amount
		lot["ingredients"] = adjusted
		left -= take
		break


func cancel_one(cursor: CursorStack, inventory: Node) -> bool:
	if lots.is_empty():
		return false
	var lot: Dictionary = lots.pop_back()
	var result_id := str(lot["result_id"])
	var amount := int(lot["amount"])
	if cursor != null and cursor.resource_id == result_id and amount > 0:
		cursor.take(amount)
	_refund(inventory, lot["ingredients"])
	return true


func cancel_all(cursor: CursorStack, inventory: Node) -> void:
	while cancel_one(cursor, inventory):
		pass


func _refund(inventory: Node, ingredients: Dictionary) -> void:
	if inventory == null or ingredients.is_empty():
		return
	for key in ingredients:
		var qty := int(ingredients[key])
		if qty > 0:
			inventory.call(&"add_resource", str(key), qty)
