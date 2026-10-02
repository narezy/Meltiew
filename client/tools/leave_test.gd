extends Node
## Leaving a place from the game menu: opens it, presses Leave, confirms, and says whether
## the game scene went away. --vr-sim for the same in VR.
##   godot --path . res://tools/leave_test.tscn -- --melt=/path/place.melt

var driver := false


func _ready() -> void:
	if driver:
		_drive.call_deferred()
		return
	var melt_path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--melt="):
			melt_path = a.trim_prefix("--melt=")
	Session.user = {"id": 1, "username": "tester", "display_name": "Tester", "birthdate": "2000-01-01", "colors": Session.DEFAULT_COLORS, "face": ":D", "accessories": []}
	Session.test_melt = JSON.parse_string(FileAccess.get_file_as_string(melt_path))
	Session.pending_game = "test"
	Session.pending_server = "auto"
	var s: Node = load("res://tools/leave_test.gd").new()
	s.driver = true
	get_tree().root.add_child.call_deferred(s)
	get_tree().change_scene_to_file.call_deferred("res://scenes/game.tscn")


func _button(root: Node, text: String) -> Button:
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).text == text and (b as Button).is_visible_in_tree():
			return b
	return null


## Presses a button the way you would: the mouse, or in VR the laser and the trigger.
func _press(b: Button) -> void:
	var at := b.get_global_rect().get_center()
	if not VR.active:
		for down in [true, false]:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.pressed = down
			e.position = at
			e.global_position = at
			get_tree().root.push_input(e, true)
			await get_tree().process_frame
		return
	var uv := at / get_tree().root.get_visible_rect().size
	var size := (VR.panel.mesh as QuadMesh).size
	var spot := VR.panel.global_transform * Vector3((uv.x - 0.5) * size.x, (0.5 - uv.y) * size.y, 0)
	(VR.hands.right as Node3D).look_at(spot, Vector3.UP)
	await get_tree().create_timer(0.2).timeout
	VR.hands.right.press("trigger_click", true)
	await get_tree().create_timer(0.1).timeout
	VR.hands.right.press("trigger_click", false)


func _drive() -> void:
	await get_tree().create_timer(5.0).timeout
	var game: Node = get_tree().current_scene
	print("in game: ", game.name, " ui busy=", UI._busy)
	game._open_menu()
	await get_tree().create_timer(0.5).timeout
	var leave := _button(game.menu, L.t("leave_game"))
	print("leave button: ", leave)
	await _press(leave)
	await get_tree().create_timer(0.5).timeout
	var yes := _button(get_tree().root, L.t("leave_game"))
	print("confirm shown: ", yes != null and yes != leave)
	for b in get_tree().root.find_children("*", "Button", true, false):
		if (b as Button).text == L.t("leave_game") and b != leave:
			yes = b
	print("confirm button: ", yes)
	if yes:
		await _press(yes)
	await get_tree().create_timer(1.5).timeout
	print("after leave: scene=", get_tree().current_scene.name if get_tree().current_scene else "none", " ui busy=", UI._busy, " leaving=", game._leaving if is_instance_valid(game) else "freed")
	get_tree().quit()
