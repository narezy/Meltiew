extends Node
## Plays a .melt offline (like play_test) and prints the engine's numbers every second:
## frame time, script (process) and physics time, draw calls, objects, nodes. For finding
## what costs a phone its frames.
##   godot --path . res://tools/perf_test.tscn -- --melt=/path/place.melt --secs=12 [--quality=low]

var sampler := false
var _secs := 12


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			_secs = int(a.trim_prefix("--secs="))
	if sampler:
		_sample.call_deferred()
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var melt_path := ""
	var quality := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--melt="):
			melt_path = a.trim_prefix("--melt=")
		elif a.begins_with("--quality="):
			quality = a.trim_prefix("--quality=")
	var melt: Variant = JSON.parse_string(FileAccess.get_file_as_string(melt_path))
	if not melt is Dictionary:
		printerr("perf_test: no place at ", melt_path)
		get_tree().quit(1)
		return
	if quality != "":
		Session.settings.quality = quality
	Session.user = {"id": 1, "username": "tester", "display_name": "Tester", "birthdate": "2000-01-01", "colors": Session.DEFAULT_COLORS, "face": ":D", "accessories": []}
	Session.test_melt = melt
	Session.pending_game = "test"
	Session.pending_server = "auto"
	var s: Node = load("res://tools/perf_test.gd").new()
	s.sampler = true
	s.name = "PerfSampler"
	get_tree().root.add_child.call_deferred(s)
	get_tree().change_scene_to_file.call_deferred("res://scenes/game.tscn")


func _sample() -> void:
	await get_tree().create_timer(3.0).timeout
	print("sec  fps  frame_ms  process_ms  physics_ms  draws  objects  prims  nodes")
	for i in _secs:
		await get_tree().create_timer(1.0).timeout
		var fps := Engine.get_frames_per_second()
		print("%3d %5d %8.2f %10.2f %10.2f %6d %8d %6d %6d" % [i, fps, 1000.0 / maxf(fps, 1),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	get_tree().quit()
