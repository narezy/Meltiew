class_name PlaceBillboards
extends Control
## BillboardGuis: GUI floating over the Part or Model it's in, always facing the camera.
## Each one is a PlaceGui rooted at the BillboardGui, moved every frame to where its
## object is on screen. Hidden behind the camera, past MaxDistance, or (unless
## AlwaysOnTop) behind a wall.

signal gui_event(id: String, ev: String, value: Variant)

var tree: PlaceTree
var scene: PlaceScene
var strings := {}
var lang := "en"
var _boards := {}  # BillboardGui id -> {box: Control, gui: PlaceGui}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func bind(t: PlaceTree, s: PlaceScene) -> void:
	tree = t
	scene = s
	tree.added.connect(_on_added)
	tree.removed.connect(func(id: String, _parent: String): _drop(id))
	tree.reparented.connect(func(id: String, _old: String):
		_drop(id)
		_on_added(id))
	var ws := tree.service("Workspace")
	if ws != "":
		for id in tree.descendants(ws):
			_on_added(id)


func _on_added(id: String) -> void:
	if tree.cls(id) != "BillboardGui" or _boards.has(id) or not scene.in_world(id):
		return
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var g := PlaceGui.new()
	g.theme = UI.theme
	g.strings = strings
	g.lang = lang
	g.root_is_frame = true
	box.add_child(g)
	g.bind(tree, id)
	g.gui_event.connect(func(gid, ev, value): gui_event.emit(gid, ev, value))
	_boards[id] = {"box": box, "gui": g}


func _drop(id: String) -> void:
	if _boards.has(id):
		_boards[id].box.queue_free()
		_boards.erase(id)


func _process(_delta: float) -> void:
	if _boards.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	for id in _boards.keys():
		var box: Control = _boards[id].box
		if not tree.has(id):
			_drop(id)
			continue
		var at: Variant = _anchor(id)
		box.visible = false
		if cam == null or at == null or not tree.prop(id, "Enabled"):
			continue
		var point: Vector3 = at + (tree.prop(id, "StudsOffset") as Vector3)
		var dist := cam.global_position.distance_to(point)
		if cam.is_position_behind(point) or dist > float(tree.prop(id, "MaxDistance")):
			continue
		if not tree.prop(id, "AlwaysOnTop") and _blocked(cam.global_position, point):
			continue
		var s: Variant = tree.prop(id, "Size")
		var px := Vector2(200, 50)
		if s is PackedFloat32Array and s.size() == 4:
			# Offset in pixels, scale in studs (it grows as you come closer, like a thing
			# in the world).
			var per_stud := get_viewport().get_visible_rect().size.y / (2.0 * maxf(dist, 0.1) * tan(deg_to_rad(cam.fov) / 2.0))
			px = Vector2(s[1] + s[0] * per_stud, s[3] + s[2] * per_stud)
		box.size = px
		box.position = cam.unproject_position(point) - px / 2.0
		box.visible = true


## Where the BillboardGui floats: the middle of its Part, the head of a character or
## Rig, or the first part of any other Model. null if there's nothing to hang it on.
func _anchor(id: String) -> Variant:
	var target := tree.parent_of(id)
	if target == "":
		return null
	var av: Node = scene.avatar_for(target)
	if av and av is MellyAvatar:
		return (av as MellyAvatar).head_center() if av.is_visible_in_tree() else null
	if StudioSchema.is_a(tree.cls(target), "BasePart"):
		# Where it's drawn (a moving part glides between updates).
		var body := scene.body_of(target)
		return body.global_position if body else tree.prop(target, "Position")
	for d in tree.descendants(target):
		if StudioSchema.is_a(tree.cls(d), "BasePart"):
			return tree.prop(d, "Position")
	return null


func _blocked(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, PlaceScene.LAYER_WORLD)
	var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and from.distance_to(hit.position) < from.distance_to(to) - 1.0
