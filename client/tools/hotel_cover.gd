extends Node
## Midnight Hotel's cover picture: a corridor of the hotel (examples/hotel_rooms.melt), in
## first person, no HUD. examples/hotel/make_cover.py puts the skull and the title on it.
##   godot --path . --resolution 1920x1080 res://tools/hotel_cover.tscn -- --melt=../examples/hotel_rooms.melt --out=/tmp/corridor.png

var driver := false
var _out := ""


func _ready() -> void:
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--melt="):
			path = a.trim_prefix("--melt=")
		elif a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	if driver:
		_drive.call_deferred()
		return
	Session.user = {"id": 1, "username": "tester", "display_name": "Tester", "birthdate": "2000-01-01", "colors": Session.DEFAULT_COLORS, "face": ":D", "accessories": []}
	Session.test_melt = JSON.parse_string(FileAccess.get_file_as_string(path))
	Session.pending_game = "test"
	Session.pending_server = "auto"
	var s: Node = load("res://tools/hotel_cover.gd").new()
	s.driver = true
	s._out = _out
	get_tree().root.add_child.call_deferred(s)
	get_tree().change_scene_to_file.call_deferred("res://scenes/game.tscn")


func _drive() -> void:
	while get_tree().current_scene == null or get_tree().current_scene.get("place_host") == null:
		await get_tree().process_frame
	var game: Node = get_tree().current_scene
	await get_tree().create_timer(3.0).timeout
	var p: LocalPlayer = game.player
	var t: PlaceTree = game.place_host.tree
	# Open a few doors so the corridor goes on.
	for n in 3:
		for id in t.descendants(t.service("Workspace")):
			if t.name_of(id) == "Room%d" % n:
				for k in t.kids(id):
					if t.name_of(k) == "Door":
						p.global_position = (t.prop(k, "Position") as Vector3) + Vector3(0, -2.5, 3)
		await get_tree().create_timer(1.0).timeout
	# Back in the first room, looking down the hotel.
	p.global_position = Vector3(0, 0, -3)
	p.reset_physics_interpolation()
	p.first_person = true
	p.cam_yaw = 0.0
	p.cam_pitch = 0.05
	game.hud.visible = false
	for c in game.place_host.find_children("*", "CanvasLayer", true, false):
		c.visible = false
	await get_tree().create_timer(1.5).timeout
	# Drawn at full size whatever the window is (tiling window managers squeeze it).
	var vp := SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	vp.world_3d = get_tree().root.find_world_3d()
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cam := Camera3D.new()
	cam.fov = p.camera.fov
	cam.far = 300.0
	vp.add_child(cam)
	cam.global_transform = p.camera.global_transform
	cam.current = true
	for i in 6:
		await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(_out)
	get_tree().quit()
