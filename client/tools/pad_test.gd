extends Node
## Plays a .melt offline and drives it with a pretend gamepad: presses buttons and moves
## sticks in a script and saves a screenshot after each step. For checking gamepad (and
## TV remote) controls without one.
##   godot --path . res://tools/pad_test.tscn -- --melt=/path/place.melt --out=/tmp/pad
## Steps: walk with the left stick, turn with the right one, Start (menu), down / A in it,
## B (back), Y (emote wheel), d-pad, A, B.

var driver := false
var _out := "/tmp/pad"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	if driver:
		_drive.call_deferred()
		return
	var melt_path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--melt="):
			melt_path = a.trim_prefix("--melt=")
	var melt: Variant = JSON.parse_string(FileAccess.get_file_as_string(melt_path))
	if not melt is Dictionary:
		printerr("pad_test: no place at ", melt_path)
		get_tree().quit(1)
		return
	Session.user = {"id": 1, "username": "tester", "display_name": "Tester", "birthdate": "2000-01-01", "colors": Session.DEFAULT_COLORS, "face": ":D", "accessories": []}
	Session.test_melt = melt
	Session.pending_game = "test"
	Session.pending_server = "auto"
	var s: Node = load("res://tools/pad_test.gd").new()
	s.driver = true
	s.name = "PadTestDriver"
	get_tree().root.add_child.call_deferred(s)
	get_tree().change_scene_to_file.call_deferred("res://scenes/game.tscn")


func _button(b: JoyButton, hold := 0.08) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().create_timer(hold).timeout
	var u := InputEventJoypadButton.new()
	u.button_index = b
	u.pressed = false
	Input.parse_input_event(u)
	await get_tree().create_timer(0.25).timeout


func _axis(axis: JoyAxis, value: float, secs: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)
	await get_tree().create_timer(secs).timeout
	var z := InputEventJoypadMotion.new()
	z.axis = axis
	z.axis_value = 0.0
	Input.parse_input_event(z)
	await get_tree().create_timer(0.2).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s_%s.png" % [_out, name]
	get_viewport().get_texture().get_image().save_png(path)
	var f := get_viewport().gui_get_focus_owner()
	print("shot %s  device=%s  focus=%s" % [path, Controls.device, f.get_path() if f else "none"])


func _drive() -> void:
	await get_tree().create_timer(5.0).timeout
	var game: Node = get_tree().current_scene
	var p0: Vector3 = game.player.global_position
	await _axis(JOY_AXIS_LEFT_Y, -1.0, 1.0)
	print("walked %.1f studs" % game.player.global_position.distance_to(p0))
	var yaw0: float = game.player.cam_yaw
	await _axis(JOY_AXIS_RIGHT_X, 1.0, 0.5)
	print("camera turned %.2f rad" % (game.player.cam_yaw - yaw0))
	await _shot("1_walked")
	await _button(JOY_BUTTON_START)
	await _shot("2_menu")
	await _button(JOY_BUTTON_DPAD_DOWN)
	await _button(JOY_BUTTON_DPAD_DOWN)
	await _shot("3_menu_down")
	await _button(JOY_BUTTON_B)
	print("menu open after B: ", game.menu.visible)
	await _button(JOY_BUTTON_Y)
	await _shot("4_wheel")
	await _button(JOY_BUTTON_DPAD_RIGHT)
	await _shot("5_wheel_right")
	await _button(JOY_BUTTON_B)
	print("wheel open after B: ", game.hud.wheel.visible)
	var y0: float = game.player.global_position.y
	await _button(JOY_BUTTON_A, 0.05)
	await get_tree().create_timer(0.1).timeout
	print("jump rose %.2f" % (game.player.global_position.y - y0))
	get_tree().quit()
