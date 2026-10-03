class_name LoadingScreen
extends CanvasLayer
## Joining a place: its 16:9 cover blurred across the screen, the square icon in the
## middle breathing slowly (so it's plain the game hasn't frozen), the name and the
## author under it, and what's happening in small letters. Fades out once the world is in.

const ICON_SIZE := 168.0

var _back: TextureRect
var _icon: RoundedImage
var _name: Label
var _author: Label
var _status: Label
var _box: Control
var _dots := 0.0
var _status_text := ""
var _done := false


func _init() -> void:
	layer = 45


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_back = TextureRect.new()
	_back.set_anchors_preset(Control.PRESET_FULL_RECT)
	_back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_back.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/shaders/loading_backdrop.gdshader")
	_back.material = m
	_back.modulate.a = 0.0
	add_child(_back)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.theme = UI.theme
	add_child(center)
	var v := UI.vbox(10)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(v)
	_box = v
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(holder)
	_icon = RoundedImage.new(preload("res://assets/logo_mark.png"), 36.0)
	_icon.size = Vector2(ICON_SIZE, ICON_SIZE)
	_icon.pivot_offset = _icon.size / 2.0
	holder.add_child(_icon)
	v.add_child(_gap(8))
	_name = UI.label("", 34, UI.TEXT, "black")
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.custom_minimum_size.x = 520
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_name)
	_author = UI.label("", 18, Color(UI.TEXT, 0.7), "bold")
	_author.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_author)
	v.add_child(_gap(14))
	_status = UI.label("", 15, Color(UI.TEXT, 0.55))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_status)


## What place this is for: shows what's known right away (the place page passes it on) and
## fetches the rest (covers, author).
func show_place(place_id: String, status: String, known := {}) -> void:
	_status_text = status
	_apply(known)
	if place_id == "" or place_id == "test" or place_id == "playground":
		if place_id == "playground":
			_icon.texture = load("res://assets/playground_square.png")
			_set_back(load("res://assets/playground_cover.png"))
		return
	var r := await Api.request("GET", "/api/places/" + place_id)
	if r.ok and is_instance_valid(self) and not _done:
		_apply(r.data.get("place", {}))
		var p: Dictionary = r.data.place
		var wide := str(p.get("cover", ""))
		var square := str(p.get("cover_square", ""))
		if square != "":
			_fetch(square, func(t: Texture2D): _icon.texture = t)
		_fetch(wide, func(t: Texture2D):
			_set_back(t)
			# No icon of its own: the middle of the cover stands in.
			if square == "":
				_icon.texture = _square_of(t))


func set_status(text: String) -> void:
	_status_text = text


func _apply(p: Dictionary) -> void:
	if p.is_empty():
		return
	_name.text = L.field(p, "name") if p.has("name") else _name.text
	var author: Variant = p.get("author")
	var who := str(author.get("display_name", author.get("username", ""))) if author is Dictionary else str(p.get("author_username", ""))
	if who != "":
		_author.text = L.t("loading_by", [who])


func _set_back(t: Texture2D) -> void:
	if t == null:
		return
	_back.texture = t
	create_tween().tween_property(_back, "modulate:a", 1.0, 0.5)


func _fetch(url: String, done: Callable) -> void:
	if url == "":
		return
	if url.begins_with("/"):
		url = Api.BASE_URL + url
	var http := HTTPRequest.new()
	add_child(http)
	http.request(url)
	var res: Array = await http.request_completed
	http.queue_free()
	if res[1] != 200 or not is_instance_valid(self):
		return
	var img := Image.new()
	var buf: PackedByteArray = res[3]
	if img.load_png_from_buffer(buf) != OK and img.load_jpg_from_buffer(buf) != OK and img.load_webp_from_buffer(buf) != OK:
		return
	img.generate_mipmaps()
	done.call(ImageTexture.create_from_image(img))


static func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	return c


static func _square_of(t: Texture2D) -> Texture2D:
	var img := t.get_image()
	if img == null:
		return t
	var side := mini(img.get_width(), img.get_height())
	var sq := img.get_region(Rect2i((img.get_width() - side) / 2, (img.get_height() - side) / 2, side, side))
	return ImageTexture.create_from_image(sq)


func _process(delta: float) -> void:
	# Breathing slowly: alive, not frozen.
	var t := Time.get_ticks_msec() / 1000.0
	var k := 0.5 + 0.5 * sin(t * 2.6)
	_icon.scale = Vector2.ONE * (1.0 + 0.045 * k)
	_icon.modulate = Color(1, 1, 1, 0.82 + 0.18 * k)
	_dots += delta * 2.5
	_status.text = _status_text + ".".repeat(int(_dots) % 4) if _status_text != "" else ""


## The world is in: fade away.
func finish() -> void:
	if _done:
		return
	_done = true
	var tw := create_tween().set_parallel()
	for c in get_children():
		if c is CanvasItem:
			tw.tween_property(c, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(queue_free)
