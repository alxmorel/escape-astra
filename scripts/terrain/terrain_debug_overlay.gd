extends Node
class_name TerrainDebugOverlay

var enabled := false

var _root: CanvasLayer
var _label: Label
var _wait := 0.0


func ensure(host: Node) -> void:
	if _root != null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 30
	layer.visible = enabled
	host.add_child(layer)
	_root = layer
	_label = Label.new()
	_label.position = Vector2(12, 12)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override(&"font_size", 16)
	_label.add_theme_color_override(&"font_color", Color(0.93, 0.96, 0.9))
	_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override(&"outline_size", 6)
	layer.add_child(_label)


func toggle() -> void:
	enabled = not enabled
	if _root != null:
		_root.visible = enabled


func tick(delta: float, stats: Dictionary) -> void:
	if not enabled:
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = 0.25
	refresh(stats)


func refresh(stats: Dictionary) -> void:
	if _label == null:
		return
	var weather_line := str(stats.get("weather_line", ""))
	_label.text = "FPS %d\nChunks chargés %d\nChunks rendus %d\nChunks collision %d\nChunks dirty %d\nTriangles %d\nSamples/chunk %d\nRebuild moyen %.1f ms\nRebuilds/s %d\nWater ready %d\nWater triangles %d\nOcean patches %d\nOcean tris %d%s" % [
		int(stats.get("fps", 0)),
		int(stats.get("chunks", 0)),
		int(stats.get("rendered", 0)),
		int(stats.get("collision", 0)),
		int(stats.get("dirty", 0)),
		int(stats.get("tris", 0)),
		int(stats.get("samples", 0)),
		float(stats.get("rebuild_ms", 0.0)),
		int(stats.get("rebuilds_s", 0)),
		int(stats.get("water_ready", 0)),
		int(stats.get("water_tris", 0)),
		int(stats.get("ocean_patches", 0)),
		int(stats.get("ocean_tris", 0)),
		weather_line,
	]
