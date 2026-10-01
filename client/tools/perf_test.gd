extends Node
## Plays a .melt offline (like play_test) and prints the engine's numbers every second:
## the average frame, the GPU's and the renderer's CPU time per frame, the worst frame of
## the second, draw calls, triangles, nodes. For finding what costs a phone its frames.
##   godot --path . res://tools/perf_test.tscn -- --melt=/path/place.melt --secs=12
##     [--quality=low|medium|high] [--off=lights,shadows,sky,fog,players] [--scale=0.75]
##     [--mobile]   (as a phone: the place's phone quality and limits)
## --off turns things off after loading, to see what each one costs.

var sampler := false
var _secs := 12
var _off: PackedStringArray = []
var _scale := 1.0
var _frames: PackedFloat64Array = []
var _last_us := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			_secs = int(a.trim_prefix("--secs="))
		elif a.begins_with("--off="):
			_off = a.trim_prefix("--off=").split(",")
		elif a.begins_with("--scale="):
			_scale = float(a.trim_prefix("--scale="))
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
	if "--mobile" in OS.get_cmdline_user_args():
		Session.phone = true
	Session.settings.fps = "0"
	Session.user = {"id": 1, "username": "tester", "display_name": "Tester", "birthdate": "2000-01-01", "colors": Session.DEFAULT_COLORS, "face": ":D", "accessories": []}
	Session.test_melt = melt
	Session.pending_game = "test"
	Session.pending_server = "auto"
	var s: Node = load("res://tools/perf_test.gd").new()
	s.sampler = true
	s.name = "PerfSampler"
	get_tree().root.add_child.call_deferred(s)
	get_tree().change_scene_to_file.call_deferred("res://scenes/game.tscn")


func _process(_delta: float) -> void:
	if not sampler:
		return
	var now := Time.get_ticks_usec()
	if _last_us > 0:
		_frames.append((now - _last_us) / 1000.0)
	_last_us = now


func _turn_off() -> void:
	var root := get_tree().current_scene
	var vp := get_viewport()
	if _scale != 1.0:
		vp.scaling_3d_scale = _scale
	for what in _off:
		match what:
			"lights":
				for n in root.find_children("*", "OmniLight3D", true, false) + root.find_children("*", "SpotLight3D", true, false):
					(n as Light3D).visible = false
			"shadows":
				for n in root.find_children("*", "DirectionalLight3D", true, false):
					(n as Light3D).shadow_enabled = false
			"sky", "fog":
				for n in root.find_children("*", "WorldEnvironment", true, false):
					var env: Environment = (n as WorldEnvironment).environment
					if what == "sky":
						env.background_mode = Environment.BG_COLOR
					else:
						env.fog_enabled = false
			"balls":
				for n in root.find_children("*", "MeshInstance3D", true, false):
					if (n as MeshInstance3D).mesh is SphereMesh:
						(n as MeshInstance3D).visible = false


func _sample() -> void:
	await get_tree().create_timer(3.0).timeout
	_turn_off()
	await get_tree().create_timer(1.0).timeout
	var vp_rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	print("sec  fps  avg_ms  worst_ms  gpu_ms  rcpu_ms  draws    prims  nodes  lights")
	var lights := get_tree().current_scene.find_children("*", "Light3D", true, false).filter(func(l): return l.visible).size()
	var sums := [0.0, 0.0, 0.0]
	for i in _secs:
		_frames.clear()
		await get_tree().create_timer(1.0).timeout
		var avg := 0.0
		var worst := 0.0
		for f in _frames:
			avg += f
			worst = maxf(worst, f)
		avg /= maxf(1.0, _frames.size())
		var gpu := RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
		var rcpu := RenderingServer.viewport_get_measured_render_time_cpu(vp_rid) + RenderingServer.get_frame_setup_time_cpu()
		sums[0] += avg
		sums[1] += gpu
		sums[2] += rcpu
		print("%3d %5d %7.2f %9.2f %7.2f %8.2f %6d %8d %6d %6d" % [i, _frames.size(), avg, worst, gpu, rcpu,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT), lights])
	print("AVG frame %.2f ms, gpu %.2f ms, render cpu %.2f ms" % [sums[0] / _secs, sums[1] / _secs, sums[2] / _secs])
	get_tree().quit()
