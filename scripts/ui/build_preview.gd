extends RefCounted

const SCENES := preload("res://scripts/ui/item_preview_scenes.gd")

static var _host: Node = null
static var _views: Dictionary = {}


static func open(parent: Node) -> void:
	if is_instance_valid(_host):
		return
	_views.clear()
	_host = Node.new()
	_host.name = "BuildPreviews"
	_host.tree_exiting.connect(_release.bind(_host))
	parent.add_child(_host)


static func close() -> void:
	if is_instance_valid(_host):
		var host := _host
		host.queue_free()
		_release(host)
		return
	_views.clear()
	_host = null


static func _release(host: Node) -> void:
	if _host != host:
		return
	_views.clear()
	_host = null


static func texture_for(resource_id: String) -> Texture2D:
	if not is_instance_valid(_host) or resource_id.is_empty():
		return null
	if _views.has(resource_id):
		var cached: Variant = _views[resource_id]
		if is_instance_valid(cached):
			return (cached as SubViewport).get_texture()
		_views.erase(resource_id)
	var viewport := _make_viewport(resource_id)
	if viewport == null:
		return null
	_host.add_child(viewport)
	_views[resource_id] = viewport
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	return viewport.get_texture()


static func _make_viewport(resource_id: String) -> SubViewport:
	var packed := SCENES.load_scene(resource_id)
	if packed == null:
		return null
	var root := packed.instantiate()
	SCENES.apply_model(root, resource_id)
	if not root is Node3D:
		push_error("Item preview scene root must be Node3D: %s" % SCENES.path_for(resource_id))
		root.queue_free()
		return null
	var viewport := SubViewport.new()
	viewport.size = Vector2i(128, 128)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.add_child(root)
	for cam in root.find_children("*", "Camera3D", true, false):
		(cam as Camera3D).current = true
		break
	return viewport
