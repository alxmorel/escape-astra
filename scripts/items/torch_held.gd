extends Node3D

const TorchLight := preload("res://scripts/items/torch_light.gd")
const TorchFire := preload("res://scripts/items/torch_fire.gd")


func _ready() -> void:
	TorchLight.apply(get_node_or_null(^"Light") as OmniLight3D)
	TorchFire.apply(self)
	for node in find_children("*", "GeometryInstance3D", true, false):
		if node is GPUParticles3D:
			continue
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
