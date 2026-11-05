extends RefCounted
class_name HotbarView

const ITEM_SLOT := preload("res://scripts/ui/item_slot.gd")
const Capacities := preload("res://scripts/inventory/capacities.gd")

var bar: HBoxContainer
var slots: Array = []


func ensure(host: Node, bind_slot: Callable) -> void:
	if bar != null:
		return
	var layer := CanvasLayer.new()
	layer.name = "HotbarLayer"
	layer.layer = 26
	host.add_child(layer)
	bar = HBoxContainer.new()
	bar.name = "Hotbar"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override(&"separation", 4)
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = -250.0
	bar.offset_right = 250.0
	bar.offset_top = -72.0
	bar.offset_bottom = -14.0
	layer.add_child(bar)
	for i in Capacities.HOTBAR:
		var slot = ITEM_SLOT.new()
		slot.slot_index = i
		slot.hotbar = true
		bar.add_child(bind_slot.call(slot, slots))


func set_visible(visible: bool) -> void:
	if bar != null:
		bar.visible = visible


func set_interactive(active: bool) -> void:
	if bar == null:
		return
	bar.visible = true
	bar.mouse_filter = Control.MOUSE_FILTER_PASS if active else Control.MOUSE_FILTER_IGNORE
