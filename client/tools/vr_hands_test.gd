extends Node
## VR hands moving you (VRHands) without a headset (--vr-sim): a floor, a Climbable wall.
## Arms mode: a hand pushed down into the floor lifts you, letting go throws you up.
## Walk mode: the grip on the wall holds, pulling down climbs, letting go drops you.
##   godot --path . res://tools/vr_hands_test.tscn -- --vr-sim [--walk]

var driver := false
var _walk := false


func _ready() -> void:
	_walk = "--walk" in OS.get_cmdline_user_args()
	if driver:
		_drive.call_deferred()
		return
	var melt := {"format": "melt", "version": 1, "meta": {"name": "hands"}, "tree": {"c": "DataModel", "k": [
		{"c": "Workspace", "n": "Workspace", "k": [
			{"c": "Part", "n": "Floor", "p": {"Size": {"$v3": [60, 1, 60]}, "Position": {"$v3": [0, -0.5, 0]}}},
			{"c": "Part", "n": "Wall", "p": {"Size": {"$v3": [8, 12, 1]}, "Position": {"$v3": [0, 6, -1.2]}, "Climbable": true}},
			{"c": "SpawnLocation", "n": "Spawn", "p": {"Position": {"$v3": [0, 0.1, 0]}}},
		]},
		{"c": "StarterPlayer", "n": "StarterPlayer", "p": {"VRLocomotion": "Walk" if _walk else "Arms"}},
	]}}
	Session.user = {"id": 1, "username": "tester", "display_name": "Tester", "birthdate": "2000-01-01", "colors": Session.DEFAULT_COLORS, "face": ":D", "accessories": []}
	Session.test_melt = melt
	Session.pending_game = "test"
	Session.pending_server = "auto"
	var s: Node = load("res://tools/vr_hands_test.gd").new()
	s.driver = true
	s._walk = _walk
	get_tree().root.add_child.call_deferred(s)
	get_tree().change_scene_to_file.call_deferred("res://scenes/game.tscn")


## Moves the pretend right hand to `local` (in the play area, like a real controller) over
## `secs`, a physics step at a time.
func _hand_to(local: Vector3, secs: float) -> void:
	var h: Node3D = VR.hands.right
	var from := h.position
	var steps := maxi(1, int(secs * 60.0))
	for i in steps:
		h.position = from.lerp(local, float(i + 1) / steps)
		await get_tree().physics_frame


func _drive() -> void:
	await get_tree().create_timer(4.0).timeout
	var game: Node = get_tree().current_scene
	var p: CharacterBody3D = game.player
	VR.show_panel(false)
	p.global_position = Vector3(0, 0.3, 0)  # right in front of the wall
	await get_tree().create_timer(0.3).timeout
	print("mode: ", "walk" if _walk else "arms", "  vr_arms=", p.vr_arms, "  feet y=%.2f" % p.global_position.y)
	var head: Vector3 = VR.camera.position
	if not _walk:
		# Down to the floor (feet level: the hand at -lift below the head's room height).
		var floor_y: float = -VR._lift + 0.02
		await _hand_to(Vector3(0.3, floor_y + 0.25, -0.3), 0.3)
		await _hand_to(Vector3(0.3, floor_y - 0.05, -0.3), 0.15)
		print("hand on the floor: held=", p._vr_hands.held.keys(), " feet y=%.2f" % p.global_position.y)
		# Push down hard: the body goes up.
		await _hand_to(Vector3(0.3, floor_y - 0.6, -0.3), 0.15)
		var y_pushed := p.global_position.y
		print("pushed: feet y=%.2f  velocity=%s" % [y_pushed, p.velocity.round()])
		# Pull the hand up off the floor: let go, keep flying up for a moment.
		await _hand_to(Vector3(0.3, 0.0, -0.3), 0.05)
		var top := p.global_position.y
		for i in 30:
			await get_tree().physics_frame
			top = maxf(top, p.global_position.y)
		print("let go: held=", p._vr_hands.held.keys(), " flew up to %.2f (from %.2f)" % [top, y_pushed])
		# Walking with the stick does nothing in Arms mode.
		var x0 := p.global_position
		await get_tree().create_timer(1.0).timeout
		VR.hands.left.stick("primary", Vector2(0, 1))
		await get_tree().create_timer(0.6).timeout
		VR.hands.left.stick("primary", Vector2.ZERO)
		print("stick walk moved %.2f studs (want 0)" % Vector2(p.global_position.x - x0.x, p.global_position.z - x0.z).length())
	else:
		# The wall is in front: reach to it at chest height and grip.
		await _hand_to(Vector3(0.0, head.y - 0.3, -0.75), 0.3)
		VR.hands.right.press("grip_click", true)
		await get_tree().physics_frame
		await get_tree().physics_frame
		print("grip on the wall: held=", p._vr_hands.held.keys(), " feet y=%.2f" % p.global_position.y)
		await _hand_to(Vector3(0.0, head.y - 1.0, -0.75), 0.4)
		print("pulled down: feet y=%.2f (want about +0.7)" % p.global_position.y)
		var y_held := p.global_position.y
		await get_tree().create_timer(0.5).timeout
		print("hanging still: feet y=%.2f (want %.2f)" % [p.global_position.y, y_held])
		VR.hands.right.press("grip_click", false)
		await get_tree().create_timer(1.0).timeout
		print("let go: held=", p._vr_hands.held.keys(), " feet y=%.2f (fell back)" % p.global_position.y)
	get_tree().quit()
