extends Node
## Studio's .obj export on a small made-up place (a few parts, a decal, a posed rig, one
## with a part swapped for a block that keeps the shirt, both wearing the clothing
## template): writes the zip and unpacks it, for a look in Blender.
##   godot --path . res://tools/obj_test.tscn -- --out=/tmp/obj

var _out := "/tmp/obj"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	_run.call_deferred()


func _run() -> void:
	var tree := PlaceTree.new()
	tree.create("ws", "Workspace", "Workspace", PlaceTree.ROOT)
	tree.create("p1", "Part", "Red", "ws")
	tree.set_prop("p1", "Color", Color.RED)
	tree.set_prop("p1", "Position", Vector3(4, 1, 0))
	tree.set_prop("p1", "Size", Vector3(2, 2, 2))
	tree.create("d1", "Decal", "Decal", "p1")
	tree.create("p2", "Part", "Ball", "ws")
	tree.set_prop("p2", "Shape", "Ball")
	tree.set_prop("p2", "Material", "Wood")
	tree.set_prop("p2", "Position", Vector3(-4, 1, 0))
	tree.create("r1", "Rig", "Pose", "ws")
	tree.set_prop("r1", "LeftArmAngle", Vector3(0, 0, 80))
	tree.set_prop("r1", "RightLegAngle", Vector3(40, 0, 0))
	tree.create("r2", "Rig", "Swapped", "ws")
	tree.set_prop("r2", "Position", Vector3(0, 0, 5))
	tree.create("blk", "Part", "Block", "ws")
	tree.set_prop("blk", "Position", Vector3(0, 20, 0))
	tree.set_prop("blk", "Size", Vector3(3, 2, 3))
	tree.set_prop("blk", "Color", Color.YELLOW)
	tree.set_prop("r2", "TorsoPart", {"$i": "blk"})
	tree.set_prop("r2", "TorsoPartKeepsClothing", true)
	var scene := PlaceScene.new()
	scene.editing = true
	add_child(scene)
	scene.bind(tree)
	for i in 10:
		await get_tree().process_frame
	# The clothing template as a shirt: its FRONT / BACK labels show where each side went.
	var shirt: Texture2D = load("res://assets/clothing_template.png")
	for r in ["r1", "r2"]:
		scene.avatar_for(r).set_extra_clothes([shirt])
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	var data: PackedByteArray = await ObjExport.selection(scene, ["p1", "p2", "r1", "r2"], "test")
	print("zip: %d bytes in %d ms" % [data.size(), Time.get_ticks_msec() - t0])
	DirAccess.make_dir_recursive_absolute(_out)
	var zp := _out.path_join("test.zip")
	var f := FileAccess.open(zp, FileAccess.WRITE)
	f.store_buffer(data)
	f.close()
	var zip := ZIPReader.new()
	zip.open(zp)
	for name in zip.get_files():
		var bytes := zip.read_file(name)
		print("  ", name, " ", bytes.size())
		var o := FileAccess.open(_out.path_join(name), FileAccess.WRITE)
		o.store_buffer(bytes)
		o.close()
	get_tree().quit()
