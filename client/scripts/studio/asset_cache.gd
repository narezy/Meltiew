class_name AssetCache
extends RefCounted
## Images uploaded to Meltiew ("asset://<id>") loaded once and shared.
## Also accepts plain http(s) URLs to the Meltiew server.

static var _textures := {}  # ref -> Texture2D
static var _waiting := {}  # ref -> Array[Callable]


static func url_of(ref: String) -> String:
	if ref.begins_with("asset://"):
		return Api.BASE_URL + "/api/assets/" + ref.trim_prefix("asset://")
	if ref.begins_with("/"):
		return Api.BASE_URL + ref
	return ref


## Calls `done(texture)` now if cached, or when the download finishes (null on failure).
static func fetch(ref: String, done: Callable) -> void:
	if ref == "":
		done.call(null)
		return
	if _textures.has(ref):
		done.call(_textures[ref])
		return
	if _waiting.has(ref):
		_waiting[ref].append(done)
		return
	_waiting[ref] = [done]
	var root := (Engine.get_main_loop() as SceneTree).root
	var http := HTTPRequest.new()
	root.add_child(http)
	http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		var tex: Texture2D = null
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			var img := Image.new()
			var err := img.load_png_from_buffer(body)
			if err != OK:
				err = img.load_jpg_from_buffer(body)
			if err == OK:
				img.generate_mipmaps()
				tex = ImageTexture.create_from_image(img)
		if tex:
			_textures[ref] = tex
		var list: Array = _waiting.get(ref, [])
		_waiting.erase(ref)
		for cb in list:
			if cb.is_valid():
				cb.call(tex))
	if http.request(url_of(ref)) != OK:
		http.queue_free()
		_waiting.erase(ref)
		done.call(null)


## Studio: a freshly uploaded image is known without downloading it again.
static func put(ref: String, tex: Texture2D) -> void:
	_textures[ref] = tex
