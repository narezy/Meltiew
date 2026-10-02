extends Node
## VR without a headset (--vr-sim): plays a .melt offline, points the pretend right hand at
## the panel, clicks, walks with the left stick, and saves what the headset would show
## after each step. For checking the VR panel, the laser and the controls by eye.
##   godot --path . res://tools/vr_test.tscn -- --vr-sim --melt=/path/place.melt --out=/tmp/vr

var driver := false
var _out := "/tmp/vr"


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
	if not melt is Dictionary or not VR.active:
		printerr("vr_test: needs --vr-sim and a place")
		get_tree().quit(1)
		return
	Session.user = {"id": 1, "username": "tester", "display_name": "Tester", "birthdate": "2000-01-01", "colors": Session.DEFAULT_COLORS, "face": ":D", "accessories": []}
	Session.test_melt = melt
	Session.pending_game = "test"
	Session.pending_server = "auto"
	var s: Node = load("res://tools/vr_test.gd").new()
	s.driver = true
	get_tree().root.add_child.call_deferred(s)
	get_tree().change_scene_to_file.call_deferred("res://scenes/game.tscn")


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	VR.vp.get_texture().get_image().save_png("%s_%s.png" % [_out, name])
	print("shot ", name, "  pointing=", VR._pointing, " px=", VR._px.round(), " panel=", VR.panel_shown, " screen=", get_tree().root.get_visible_rect().size, " window=", DisplayServer.window_get_size(), " scale=", get_tree().root.content_scale_factor)


## Turns the pretend hand to aim at a spot of the panel (uv 0..1 from the top left).
func _aim(side: String, uv: Vector2) -> void:
	var size := (VR.panel.mesh as QuadMesh).size
	var spot := VR.panel.global_transform * Vector3((uv.x - 0.5) * size.x, (0.5 - uv.y) * size.y, 0)
	var hand: Node3D = VR.hands[side]
	hand.look_at(spot, Vector3.UP)
	await get_tree().create_timer(0.2).timeout


func _drive() -> void:
	await get_tree().create_timer(5.0).timeout
	var game: Node = get_tree().current_scene
	await _shot("1_start")
	await _aim("right", Vector2(0.5, 0.5))
	await _shot("2_pointing")
	# The menu button opens the game menu on the panel; click its "Continue" button.
	VR.hands.left.press("menu_button", true)
	VR.hands.left.press("menu_button", false)
	await get_tree().create_timer(0.5).timeout
	await _aim("right", Vector2(0.5, 0.5))
	await _shot("3_menu")
	print("menu open: ", game.menu.visible)
	# Point at the menu's "Continue" button and pull the trigger.
	var cont: Control = null
	for b in game.menu.find_children("*", "Button", true, false):
		if (b as Button).text == L.t("continue_game") or (b as Button).text == L.t("resume"):
			cont = b
	if cont:
		var c := cont.get_global_rect().get_center() / get_tree().root.get_visible_rect().size
		await _aim("right", c)
		VR.hands.right.press("trigger_click", true)
		await get_tree().create_timer(0.1).timeout
		VR.hands.right.press("trigger_click", false)
		await get_tree().create_timer(0.3).timeout
		print("menu open after clicking Continue with the laser: ", game.menu.visible)
	else:
		print("no Continue button found")
		VR.hands.left.press("menu_button", true)
		VR.hands.left.press("menu_button", false)
	await get_tree().create_timer(0.3).timeout
	# Walk forward with the left stick.
	var p0: Vector3 = game.player.global_position
	VR.hands.left.stick("primary", Vector2(0, 1))
	await get_tree().create_timer(1.0).timeout
	VR.hands.left.stick("primary", Vector2.ZERO)
	print("eyes %.2f above the feet (want %.2f)" % [VR.camera.global_position.y - game.player.global_position.y, LocalPlayer.EYE_HEIGHT])
	print("walked %.1f studs; head over the feet: %.2f" % [game.player.global_position.distance_to(p0),
		Vector2(VR.camera.global_position.x - game.player.global_position.x, VR.camera.global_position.z - game.player.global_position.z).length()])
	# Turn with the right stick.
	var yaw0: float = game.player.cam_yaw
	VR.hands.right.stick("primary", Vector2(1, 0))
	await get_tree().create_timer(0.2).timeout
	VR.hands.right.stick("primary", Vector2.ZERO)
	await get_tree().create_timer(0.2).timeout
	print("turned %.0f degrees" % rad_to_deg(angle_difference(yaw0, game.player.cam_yaw)))
	# Hide the panel (Y) and reach out with both hands.
	VR.hands.left.press("by_button", true)
	VR.hands.left.press("by_button", false)
	VR.hands.left.position = VR.camera.position + Vector3(-0.3, -0.35, -0.45)
	VR.hands.right.position = VR.camera.position + Vector3(0.35, -0.5, -0.2)
	await get_tree().create_timer(0.5).timeout
	await _shot("4_hands")
	# Look down at your own body: arms and legs, no torso or head.
	VR.camera.rotation.x = deg_to_rad(-55.0)
	await get_tree().create_timer(0.3).timeout
	await _shot("4b_down")
	VR.camera.rotation.x = 0.0
	# The chat opens: the keyboard comes up; type a letter with the laser.
	VR.show_panel(true)
	game.hud.toggle_chat(true)
	await get_tree().create_timer(0.4).timeout
	print("keyboard shown: ", VR._kb.visible)
	var key: Button = null
	for b in VR._keys.find_children("*", "Button", true, false):
		if (b as Button).text in ["q", "й"]:
			key = b
	if key and VR._kb.visible:
		var uv := key.get_global_rect().get_center() / VR._kb_vp.get_visible_rect().size
		var spot := VR._kb.global_transform * VR._local_on(VR._kb, uv)
		(VR.hands.right as Node3D).look_at(spot, Vector3.UP)
		await get_tree().create_timer(0.2).timeout
		VR.hands.right.press("trigger_click", true)
		await get_tree().create_timer(0.1).timeout
		VR.hands.right.press("trigger_click", false)
		await get_tree().create_timer(0.3).timeout
		print("typed into the chat: '", game.hud._chat_input.text, "'")
	await _shot("5_keyboard")
	get_tree().quit()
