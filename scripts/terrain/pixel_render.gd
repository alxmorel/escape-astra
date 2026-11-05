extends Node3D

const PIXEL_SHADER := preload("res://shaders/pixel_lighting.gdshader")

@export_range(1, 8, 1) var pixel_size: int = 3:
	set(value):
		pixel_size = maxi(value, 1)
		_apply_size()

@export_range(2, 12, 1) var light_levels: int = 4:
	set(value):
		light_levels = maxi(value, 2)
		_apply_shader()

@export_range(0.0, 1.0, 0.05) var dither_strength: float = 0.55:
	set(value):
		dither_strength = clampf(value, 0.0, 1.0)
		_apply_shader()

@onready var _viewport: SubViewport = $World

var _display: TextureRect
var _material: ShaderMaterial


func _ready() -> void:
	_viewport.own_world_3d = true
	_viewport.handle_input_locally = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_viewport.use_taa = false
	_viewport.use_debanding = false
	_material = ShaderMaterial.new()
	_material.shader = PIXEL_SHADER
	_display = TextureRect.new()
	_display.name = "PixelDisplay"
	_display.set_anchors_preset(Control.PRESET_FULL_RECT)
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_display.stretch_mode = TextureRect.STRETCH_SCALE
	_display.texture = _viewport.get_texture()
	_display.material = _material
	add_child(_display)
	child_entered_tree.connect(_on_child_entered)
	get_viewport().size_changed.connect(_apply_size)
	_apply_shader()
	_apply_size()
	var camera := _viewport.find_child("Camera3D", true, false) as Camera3D
	if camera != null:
		camera.current = true


func _unhandled_input(event: InputEvent) -> void:
	_viewport.push_input(event)


func _on_child_entered(node: Node) -> void:
	if node is Node3D or node is WorldEnvironment:
		node.reparent.call_deferred(_viewport)


func _apply_size() -> void:
	if _viewport == null:
		return
	var screen := Vector2i(get_viewport().get_visible_rect().size)
	var divisor := maxi(pixel_size, 1)
	_viewport.size = Vector2i(maxi(screen.x / divisor, 1), maxi(screen.y / divisor, 1))


func _apply_shader() -> void:
	if _material == null:
		return
	_material.set_shader_parameter(&"light_levels", light_levels)
	_material.set_shader_parameter(&"dither_strength", dither_strength)
