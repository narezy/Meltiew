class_name AccessoryThumbs
extends Node
## Little pictures of accessories for the avatar editor, rendered on the device
## from the catalog (so new server-side accessories get one too) and cached.

const SIZE := 160

static var _instance: AccessoryThumbs
static var _cache := {}  # "id@version" -> Texture2D

var _vp: SubViewport
var _cam: Camera3D
var _holder: Node3D
var _rim: DirectionalLight3D
var _queue: Array = []  # [id, Callable]
var _busy := false


## Calls `done(texture)` once the picture is ready (right away if cached).
static func fetch(id: String, done: Callable) -> void:
	var key := "%s@%d" % [id, Accessories.version]
	if _cache.has(key):
		done.call(_cache[key])
		return
	if _instance == null or not is_instance_valid(_instance):
		_instance = AccessoryThumbs.new()
		(Engine.get_main_loop() as SceneTree).root.add_child(_instance)
	_instance._queue.append([id, done])
	if not _instance._busy:
		_instance._run()


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#e6e0ff")
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_energy = 1.2
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, -140, 0)
	fill.light_energy = 0.4
	fill.light_color = Color("#b89cff")
	_vp.add_child(fill)
	# Rim light from behind the object: dark things (a black tail) would vanish on the
	# app's dark cards without a bright edge.
	_rim = DirectionalLight3D.new()
	_rim.light_energy = 6.0
	_rim.light_color = Color("#e9e2ff")
	_vp.add_child(_rim)
	_cam = Camera3D.new()
	_cam.fov = 30
	_vp.add_child(_cam)
	_holder = Node3D.new()
	_vp.add_child(_holder)


func _run() -> void:
	_busy = true
	while not _queue.is_empty():
		var item: Array = _queue.pop_front()
		var id: String = item[0]
		var key := "%s@%d" % [id, Accessories.version]
		if not _cache.has(key):
			_cache[key] = await _render(id)
		(item[1] as Callable).call(_cache[key])
	_busy = false


func _render(id: String) -> Texture2D:
	for c in _holder.get_children():
		c.queue_free()
	var node := Accessories.build(id)
	if node == null:
		return null
	# Frozen: animations would move it while we frame it.
	node.process_mode = Node.PROCESS_MODE_DISABLED
	_holder.add_child(node)
	await get_tree().process_frame
	var box := AABB()
	var first := true
	for n in node.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	# Three-quarter view from the front, far enough to fit the whole thing.
	var center := box.get_center()
	var radius := maxf(box.size.length() * 0.5, 0.1)
	var dir := Vector3(0.55, 0.35, -1.0 if Accessories.slot_of(id) == "back" else 1.0).normalized()
	var dist := radius / tan(deg_to_rad(_cam.fov * 0.5)) * 1.08
	_cam.global_transform = Transform3D(Basis.looking_at(-dir), center + dir * dist)
	# Shine from behind and above, towards the camera.
	_rim.global_transform = Transform3D(Basis.looking_at(dir + Vector3(0, -0.6, 0)), center)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	node.queue_free()
	return ImageTexture.create_from_image(img)
