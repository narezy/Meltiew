extends Node
## Midnight Hotel's hotel place (examples/hotel_rooms.melt), offline: walks the player from
## door to door, prints the place's script output and what happens; --test=howl brings the
## Howl at door 2 (stand in the open, then in a wardrobe), --test=chase the Watcher at 3.
##   godot --path . res://tools/hotel_test.tscn -- --melt=../examples/hotel_rooms.melt [--test=howl] [--out=/tmp/h]

var driver := false
var _out := ""
var _test := ""


func _ready() -> void:
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--melt="):
			path = a.trim_prefix("--melt=")
		elif a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a.begins_with("--test="):
			_test = a.trim_prefix("--test=")
	if driver:
		_drive.call_deferred()
		return
	var melt: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	if _test != "":
		for n in melt.tree.k:
			if n.c == "ReplicatedStorage":
				for f in n.k:
					if f.n == "Config":
						f.k.append({"c": "StringValue", "n": "Test", "p": {"Value": _test}})
	Session.user = {"id": 1, "username": "tester", "display_name": "Tester", "birthdate": "2000-01-01", "colors": Session.DEFAULT_COLORS, "face": ":D", "accessories": []}
	Session.test_melt = melt
	Session.pending_game = "test"
	Session.pending_server = "auto"
	var s: Node = load("res://tools/hotel_test.gd").new()
	s.driver = true
	s._out = _out
	s._test = _test
	get_tree().root.add_child.call_deferred(s)
	get_tree().change_scene_to_file.call_deferred("res://scenes/game.tscn")


func _shot(name: String) -> void:
	if _out == "":
		return
	await RenderingServer.frame_post_draw
	get_tree().root.get_texture().get_image().save_png("%s_%s.png" % [_out, name])


func _door_pos(t: PlaceTree, n: int) -> Variant:
	for id in t.descendants(t.service("Workspace")):
		if t.name_of(id) == "Room%d" % n:
			for k in t.kids(id):
				if t.name_of(k) == "Door":
					return t.prop(k, "Position")
	return null


func _drive() -> void:
	while get_tree().current_scene == null or get_tree().current_scene.get("place_host") == null:
		await get_tree().process_frame
	var game: Node = get_tree().current_scene
	game.place_host.output.connect(func(op): if str(op.get("level", "")) != "info" or _test != "": print("  [script ", op.get("level", ""), "] ", op.get("msg", "")))
	await get_tree().create_timer(3.0).timeout
	var t: PlaceTree = game.place_host.tree
	var p: LocalPlayer = game.player
	var state := func() -> int:
		var rs := t.service("ReplicatedStorage")
		for f in t.kids(rs):
			if t.name_of(f) == "State":
				return int(t.prop(t.kids(f)[0], "Value"))
		return -1
	print("start: rooms %d, player at %s" % [t.kids(t.descendants(t.service("Workspace")).filter(func(i): return t.name_of(i) == "Rooms")[0]).size(), p.global_position.round()])
	await _shot("0_start")
	for n in 4:
		var d: Variant = _door_pos(t, n)
		if d == null:
			print("no door in room %d" % n)
			break
		p.global_position = (d as Vector3) + Vector3(0, -2.5, 3)
		p.reset_physics_interpolation()
		p.cam_yaw = 0.0  # looking down the hotel (-Z)
		p.cam_pitch = -0.12
		await get_tree().create_timer(1.2).timeout
		print("at door %d: State.Door=%d, alive %s" % [n + 1, state.call(), not p.dead])
		if n == 0:
			await _shot("1_door")
		if _test == "howl" and n == 1:
			print("  waiting in the open for the Howl...")
			# Looking back the way it comes.
			p.cam_yaw = PI
			for i in 18:
				await get_tree().create_timer(0.5).timeout
				var howl := t.descendants(t.service("Workspace")).filter(func(x): return t.name_of(x) == "Howl")
				if not howl.is_empty():
					print("  the Howl is out at %s" % t.prop(howl[0], "Position"))
					await _shot("2_howl_coming")
					break
			await get_tree().create_timer(4.0).timeout
			print("  after the Howl: dead %s" % p.dead)
			await _shot("2_howl")
			break
		if _test == "chase" and n == 2:
			# Into the chase: walk (too slow), looking back at what's coming.
			p.cam_yaw = PI
			for i in 50:
				p.global_position += Vector3(0, 0, -0.3)
				await get_tree().create_timer(0.1).timeout
				var w := t.descendants(t.service("Workspace")).filter(func(x): return t.name_of(x) == "Watcher")
				if not w.is_empty() and i % 10 == 0:
					print("  the Watcher at %s, me at %s" % [t.prop(w[0], "Position"), p.global_position.round()])
				if i == 38:
					await _shot("2_chase")
				if p.dead:
					break
			print("  walking at 3 studs a second in the chase: dead %s" % p.dead)
			break
	get_tree().quit()
