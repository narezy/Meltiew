extends Node
## Climbing with VR hands (VRHands) without a headset (--vr-sim): a floor, a Climbable
## wall. The grip on the wall holds, pulling down climbs, letting go drops you.
##   godot --path . res://tools/vr_hands_test.tscn -- --vr-sim

var driver := false


func _ready() -> void:
	if driver:
		_drive.call_deferred()
		return
	var melt := {"format": "melt", "version": 1, "meta": {"name": "hands"}, "tree": {"c": "DataModel", "k": [
		{"c": "Workspace", "n": "Workspace", "k": [
			{"c": "Part", "n": "Floor", "p": {"Size": {"$v3": [60, 1, 60]}, "Position": {"$v3": [0, -0.5, 0]}}},
			{"c": "Part", "n": "Wall", "p": {"Size": {"$v3": [8, 12, 1]}, "Position": {"$v3": [0, 6, -1.2]}, "Climbable": true}},
			{"c": "SpawnLocation", "n": "Spawn", "p": {"Position": {"$v3": [0, 0.1, 0]}}},
		]},
	]}}
	Session.user = {"id": 1, "username": "tester", "display_name": "Tester", "birthdate": "2000-01-01", "colors": Session.DEFAULT_COLORS, "face": ":D", "accessories": []}
	Session.test_melt = melt
	Session.pending_game = "test"
	Session.pending_server = "auto"
	var s: Node = load("res://tools/vr_hands_test.gd").new()
	s.driver = true
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
	var head: Vector3 = VR.camera.position
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
	# Without the grip a hand on the wall doesn't hold.
	VR.hands.right.position = Vector3(0.0, head.y - 0.3, -0.75)
	await get_tree().create_timer(0.3).timeout
	print("no grip: held=", p._vr_hands.held.keys())
	get_tree().quit()
