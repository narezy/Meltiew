extends Node
## Monkey Tag's hands (examples/monkeytag, a place script) without a headset (--vr-sim):
## a hand slapped on the ground and pushed down lifts you, letting go flies you up, the
## stick doesn't walk. Script errors and prints are shown.
##   godot --path . res://tools/monkey_test.tscn -- --vr-sim --melt=../examples/monkeytag.melt

var driver := false


func _ready() -> void:
	if driver:
		_drive.call_deferred()
		return
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--melt="):
			path = a.trim_prefix("--melt=")
	Session.user = {"id": 1, "username": "tester", "display_name": "Tester", "birthdate": "2000-01-01", "colors": Session.DEFAULT_COLORS, "face": ":D", "accessories": []}
	Session.test_melt = JSON.parse_string(FileAccess.get_file_as_string(path))
	Session.pending_game = "test"
	Session.pending_server = "auto"
	var s: Node = load("res://tools/monkey_test.gd").new()
	s.driver = true
	get_tree().root.add_child.call_deferred(s)
	get_tree().change_scene_to_file.call_deferred("res://scenes/game.tscn")


func _hand_to(local: Vector3, secs: float) -> void:
	var h: Node3D = VR.hands.right
	var from := h.position
	var steps := maxi(1, int(secs * 60.0))
	for i in steps:
		h.position = from.lerp(local, float(i + 1) / steps)
		await get_tree().physics_frame


func _drive() -> void:
	while get_tree().current_scene == null or get_tree().current_scene.get("place_host") == null:
		await get_tree().process_frame
	var game: Node = get_tree().current_scene
	game.place_host.output.connect(func(op): print("  [script] ", op.get("level", ""), " ", op.get("msg", "")))
	await get_tree().create_timer(5.0).timeout
	var p: CharacterBody3D = game.player
	VR.show_panel(false)
	var t: PlaceTree = game.place_host.tree
	for id in t.descendants(game.place_host.player_gui()):
		if t.cls(id) == "TextLabel" and t.name_of(id) == "Label":
			print("status: ", game.place_host.scene.localize(str(t.prop(id, "Text"))))
	print("walk speed %.1f, legs hidden: %s" % [p.walk_speed, game.place_host.scene.part_shapes_of(game.place_host.local_humanoid())])
	var floor_y: float = -VR._lift + 0.02
	await _hand_to(Vector3(0.3, floor_y + 0.3, -0.3), 0.3)
	var y0 := p.global_position.y
	await _hand_to(Vector3(0.3, floor_y - 0.08, -0.3), 0.12)
	await _hand_to(Vector3(0.3, floor_y - 0.7, -0.3), 0.18)
	var y1 := p.global_position.y
	print("pushed down 0.6: feet %.2f -> %.2f" % [y0, y1])
	await _hand_to(Vector3(0.3, floor_y + 0.3, -0.3), 0.05)
	var top := p.global_position.y
	for i in 40:
		await get_tree().physics_frame
		top = maxf(top, p.global_position.y)
	print("let go: flew up to %.2f" % top)
	await get_tree().create_timer(1.5).timeout
	var x0 := p.global_position
	VR.hands.left.stick("primary", Vector2(0, 1))
	await get_tree().create_timer(0.6).timeout
	VR.hands.left.stick("primary", Vector2.ZERO)
	print("stick walk moved %.2f studs (want ~0)" % Vector2(p.global_position.x - x0.x, p.global_position.z - x0.z).length())
	get_tree().quit()
