class_name AudioCache
extends RefCounted
## Sounds uploaded to Meltiew ("asset://<id>": OGG, MP3 or WAV) downloaded once and shared.

static var _streams := {}  # ref -> AudioStream
static var _waiting := {}  # ref -> Array[Callable]


## Calls `done(stream)` now if cached, or when the download finishes (null on failure).
static func fetch(ref: String, done: Callable) -> void:
	if not ref.begins_with("asset://"):
		done.call(null)
		return
	if _streams.has(ref):
		done.call(_streams[ref])
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
		var stream: AudioStream = decode(body) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else null
		if stream:
			_streams[ref] = stream
		var list: Array = _waiting.get(ref, [])
		_waiting.erase(ref)
		for cb in list:
			if cb.is_valid():
				cb.call(stream))
	if http.request(AssetCache.url_of(ref)) != OK:
		http.queue_free()
		_waiting.erase(ref)
		done.call(null)


## Bytes of an OGG, MP3 or WAV file as a stream Godot can play (null if it isn't one).
static func decode(bytes: PackedByteArray) -> AudioStream:
	if bytes.size() < 12:
		return null
	# Compare raw bytes: headers carry binary sizes (zeros) that would cut a string short.
	var magic := func(at: int, tag: String) -> bool:
		return bytes.slice(at, at + tag.length()) == tag.to_ascii_buffer()
	if magic.call(0, "OggS"):
		return AudioStreamOggVorbis.load_from_buffer(bytes)
	if magic.call(0, "RIFF") and magic.call(8, "WAVE"):
		return AudioStreamWAV.load_from_buffer(bytes)
	if magic.call(0, "ID3") or (bytes[0] == 0xFF and (bytes[1] & 0xE0) == 0xE0):
		var mp3 := AudioStreamMP3.new()
		mp3.data = bytes
		return mp3
	return null


## Studio: a freshly uploaded sound is known without downloading it again.
static func put(ref: String, stream: AudioStream) -> void:
	_streams[ref] = stream
