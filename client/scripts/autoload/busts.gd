extends Node
## Renders head-and-shoulders portraits of avatars off-screen and caches them.
## Used for every avatar picture in the UI, and uploaded so the website can show it.

signal ready_for(hash: String, tex: Texture2D)

const SIZE := 256

var _vp: SubViewport
var _avatar: MellyAvatar
var _cache := {}  # look hash -> Texture2D
var _queue: Array = []  # [hash, user]
var _busy := false


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
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, 25, 0)
	key.light_energy = 1.1
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, -140, 0)
	fill.light_energy = 0.35
	fill.light_color = Color("#b89cff")
	_vp.add_child(fill)
	var cam := Camera3D.new()
	cam.fov = 24
	var pos := Vector3(0.25, 1.66, 2.1)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, 1.48, 0) - pos), pos)
	_vp.add_child(cam)
	_avatar = MellyAvatar.new()
	_avatar.rotation.y = PI + 0.25
	_vp.add_child(_avatar)


## Returns the cached portrait for this user's look, or null and schedules a render.
func get_bust(u: Dictionary) -> Texture2D:
	var h := Session.look_hash(u)
	if _cache.has(h):
		return _cache[h]
	for item in _queue:
		if item[0] == h:
			return null
	_queue.append([h, u.duplicate()])
	if not _busy:
		_process_queue()
	return null


## Renders synchronously-ish (awaitable) and returns the portrait image.
func render_image(u: Dictionary) -> Image:
	var h := Session.look_hash(u)
	if not _cache.has(h):
		_queue.append([h, u.duplicate()])
		if not _busy:
			_process_queue()
		while not _cache.has(h):
			await ready_for
	return (_cache[h] as Texture2D).get_image()


func _process_queue() -> void:
	_busy = true
	while _queue.size() > 0:
		var item: Array = _queue.pop_front()
		var h: String = item[0]
		if _cache.has(h):
			continue
		_avatar.apply_user(item[1])
		_avatar.play("idle")
		_avatar.anim_player.seek(0.0, true)
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		# Hats are swapped with queue_free, so give the tree two frames to settle.
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := _vp.get_texture().get_image()
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var tex := ImageTexture.create_from_image(img)
		_cache[h] = tex
		ready_for.emit(h, tex)
	_busy = false


## Uploads a fresh portrait when the signed-in user's look changed.
func sync_my_render() -> void:
	var u := Session.user
	if u.is_empty():
		return
	var h := Session.look_hash(u)
	if str(u.get("render", "")) == h:
		return
	var img: Image = await render_image(u)
	var png := img.save_png_to_buffer()
	var r := await Api.request("POST", "/api/me/render", {"hash": h, "png": Marshalls.raw_to_base64(png)})
	if r.ok:
		Session.user["render"] = h
