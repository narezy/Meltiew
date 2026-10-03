extends Node
## A VehicleSeat car on a test track (offline): sits the player in, gas, steering, a wall,
## a ramp, getting out and rolling to a stop. Prints what happened; --out saves pictures.
##   godot --path . res://tools/vehicle_test.tscn -- [--out=/tmp/car]

var driver := false
var _out := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	if driver:
		_drive.call_deferred()
		return
	var v3 := func(x, y, z): return {"$v3": [x, y, z]}
	var part := func(n: String, size: Vector3, pos: Vector3, color: String, extra := {}) -> Dictionary:
		var p := {"Size": v3.call(size.x, size.y, size.z), "Position": v3.call(pos.x, pos.y, pos.z), "Color": {"$c3": color}}
		p.merge(extra)
		return {"c": "Part", "n": n, "p": p}
	var car := [
		{"c": "VehicleSeat", "n": "Drive", "p": {"Size": v3.call(2, 0.4, 2), "Position": v3.call(0, 1.4, 0), "MaxSpeed": 40, "Torque": 30}},
		part.call("Body", Vector3(4, 0.8, 7), Vector3(0, 0.8, 0), "#d83a3a"),
		part.call("Hood", Vector3(4, 0.8, 2), Vector3(0, 1.6, -2.4), "#d83a3a"),
	]
	for i in 4:
		var x := 2.3 if i % 2 == 0 else -2.3
		var z := -2.4 if i < 2 else 2.4
		car.append(part.call("Wheel%s%s" % ["F" if i < 2 else "B", "R" if x > 0 else "L"], Vector3(1.4, 0.6, 1.4), Vector3(x, 0.7, z), "#222228", {"Shape": "Cylinder", "Rotation": v3.call(0, 0, 90)}))
	var melt := {"format": "melt", "version": 1, "meta": {"name": "cars"}, "tree": {"c": "DataModel", "k": [
		{"c": "Workspace", "n": "Workspace", "k": [
			part.call("Ground", Vector3(400, 1, 400), Vector3(0, -0.5, 0), "#5a8a4a"),
			part.call("Wall", Vector3(40, 6, 1), Vector3(0, 3, -60), "#888890"),
			{"c": "Part", "n": "Ramp", "p": {"Shape": "Wedge", "Size": v3.call(12, 4, 20), "Position": v3.call(40, 2, -20), "Color": {"$c3": "#aa8855"}}},
			{"c": "SpawnLocation", "n": "Spawn", "p": {"Position": v3.call(8, 0.2, 6)}},
			{"c": "Model", "n": "Car", "k": car},
		]},
	]}}
	Session.user = {"id": 1, "username": "tester", "display_name": "Tester", "birthdate": "2000-01-01", "colors": Session.DEFAULT_COLORS, "face": ":D", "accessories": []}
	Session.test_melt = melt
	Session.pending_game = "test"
	Session.pending_server = "auto"
	var s: Node = load("res://tools/vehicle_test.gd").new()
	s.driver = true
	s._out = _out
	get_tree().root.add_child.call_deferred(s)
	get_tree().change_scene_to_file.call_deferred("res://scenes/game.tscn")


func _shot(name: String) -> void:
	if _out == "":
		return
	await RenderingServer.frame_post_draw
	get_tree().root.get_texture().get_image().save_png("%s_%s.png" % [_out, name])


func _hold(action: String, secs: float) -> void:
	Input.action_press(action)
	await get_tree().create_timer(secs).timeout
	Input.action_release(action)


func _drive() -> void:
	while get_tree().current_scene == null or get_tree().current_scene.get("place_host") == null:
		await get_tree().process_frame
	var game: Node = get_tree().current_scene
	await get_tree().create_timer(2.5).timeout
	var t: PlaceTree = game.place_host.tree
	var seat := ""
	for id in t.descendants(t.service("Workspace")):
		if t.cls(id) == "VehicleSeat":
			seat = id
	game._sit(seat)
	await get_tree().create_timer(0.3).timeout
	var d: VehicleDrive = game._drive
	print("driving: ", d != null, "  parts: ", d.parts.size(), "  wheels: ", d.wheels.size(), "  box: ", d.box)
	var p0: Vector3 = d.pose.origin
	await _hold("move_forward", 2.0)
	print("after 2 s of gas: speed %.1f (max 40), moved %.1f studs, height %.2f" % [d.speed, d.pose.origin.distance_to(p0), d.pose.origin.y])
	print("player rides along: %.2f studs from the seat" % game.player.global_position.distance_to(d.pose.origin))
	# Somewhere open (it was heading for the wall), then a right turn at speed.
	d.pose = Transform3D(Basis(), Vector3(-60, 1.4, 60))
	d._body.global_transform = d.pose
	d.speed = 30.0
	var yaw0 := d.pose.basis.get_euler().y
	Input.action_press("move_forward")
	Input.action_press("move_right")
	for i in 60:
		await get_tree().physics_frame
		if i % 20 == 0:
			pass
	Input.action_release("move_right")
	Input.action_release("move_forward")
	print("turned right in 1 s at speed: %.0f degrees (want about -60)" % rad_to_deg(angle_difference(yaw0, d.pose.basis.get_euler().y)))
	await _shot("1_driving")
	# Straight into the wall far ahead: it stops there, not through it.
	d.pose = Transform3D(Basis(), Vector3(0, 1.4, -30))
	d._body.global_transform = d.pose
	d.speed = 0.0
	await _hold("move_forward", 3.0)
	print("at the wall: z %.1f (the wall's face is at -59.5), speed %.1f" % [d.pose.origin.z, d.speed])
	# Up the ramp.
	d.pose = Transform3D(Basis(), Vector3(40, 1.4, 5))
	d._body.global_transform = d.pose
	d.speed = 0.0
	var top := 0.0
	Input.action_press("move_forward")
	for i in 120:
		await get_tree().physics_frame
		top = maxf(top, d.pose.origin.y)
	Input.action_release("move_forward")
	print("ramp: up to %.1f studs high, leaning %.0f degrees" % [top, rad_to_deg(acos(clampf(d.pose.basis.y.normalized().dot(Vector3.UP), -1, 1)))])
	await _shot("2_ramp")
	# Out: it rolls on, then stops by itself and the tree knows where.
	d.pose = Transform3D(Basis(), Vector3(-40, 1.4, 40))
	d._body.global_transform = d.pose
	await _hold("move_forward", 1.5)
	game.player.stand_up()
	await get_tree().create_timer(0.2).timeout
	var at := d.pose.origin
	await get_tree().create_timer(4.0).timeout
	print("got out: rolled %.1f studs more, drive gone: %s, seat in the tree at %s" % [d.pose.origin.distance_to(at) if is_instance_valid(d) else -1.0, not is_instance_valid(d), t.prop(seat, "Position")])
	get_tree().quit()
