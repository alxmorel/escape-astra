extends SceneTree

## Charge test_planet headless et mesure le temps jusqu’au terrain jouable.


func _initialize() -> void:
	var sid := 42
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		sid = int(args[0])
	call_deferred(&"_boot", sid)


func _boot(sid: int) -> void:
	var sm := root.get_node_or_null(^"/root/SaveManager")
	if sm != null:
		sm.set(&"active", {
			"save_version": 1,
			"id": "bench_%d" % sid,
			"name": "bench",
			"seed": sid,
			"created_at": 0,
			"saved_at": 0,
			"play_time": 0.0,
			"progression": {},
		})
	var t0 := Time.get_ticks_msec()
	var err := change_scene_to_file("res://scenes/world/test_planet.tscn")
	if err != OK:
		push_error("failed to load test_planet %s" % err)
		quit(1)
		return
	await process_frame
	var deadline := t0 + 60000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var planet := root.find_child("Planet", true, false)
		if planet == null:
			continue
		var volume = planet.get_node_or_null(^"TerrainVolume")
		if volume == null:
			continue
		if bool(volume.get(&"_boot")):
			continue
		var water_ms := 0
		var phases: Dictionary = {}
		if planet.has_method(&"hydro_metrics"):
			var m: Dictionary = planet.call(&"hydro_metrics")
			water_ms = int(m.get("build_ms", 0))
			phases = m.get("phase_ms", {})
		var playable_ms := Time.get_ticks_msec() - t0
		print(
			"playable_boot seed=%d playable_ms=%d water_gen_ms=%d phases=%s"
			% [sid, playable_ms, water_ms, phases]
		)
		quit(0)
		return
	push_error("playable boot timeout")
	quit(1)
