class_name StudioAssets
extends PanelContainer
## Your uploaded images (textures for parts, UI images, skyboxes).
## Opened with a callback it works as a picker.

signal picked(ref: String)

var _grid: HFlowContainer
var _usage: Label
var _on_pick: Callable


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UI.BG_2
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(16)
	sb.border_color = UI.LINE
	sb.set_border_width_all(1)
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(560, 440)
	var v := UI.vbox(10)
	add_child(v)
	var head := UI.hbox(10)
	var title := UI.label(L.t("st_images"), 22, UI.TEXT, "black")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var up := UI.button(L.t("st_upload"), "primary", 40)
	up.add_theme_font_size_override("font_size", 15)
	up.pressed.connect(_upload)
	head.add_child(up)
	var close := UI.button("✕", "ghost", 40)
	close.custom_minimum_size.x = 44
	close.pressed.connect(func(): visible = false)
	head.add_child(close)
	v.add_child(head)
	_usage = UI.label("", 14, UI.MUTED)
	v.add_child(_usage)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	_grid = HFlowContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	sc.add_child(_grid)


func open(on_pick: Callable = Callable()) -> void:
	_on_pick = on_pick
	visible = true
	_load()


func _load() -> void:
	for c in _grid.get_children():
		c.queue_free()
	_grid.add_child(Loading.spinner(34))
	var r := await Api.request("GET", "/api/assets")
	for c in _grid.get_children():
		c.queue_free()
	if not r.ok:
		_grid.add_child(UI.label(r.message, 15, UI.DANGER))
		return
	var u: Dictionary = r.data.usage
	_usage.text = L.t("st_asset_usage", [int(u.count), int(u.max_count), snappedf(float(u.bytes) / 1048576.0, 0.1), int(float(u.max_bytes) / 1048576.0)])
	if r.data.assets.is_empty():
		var l := UI.label(L.t("st_no_images"), 15, UI.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 400
		_grid.add_child(l)
	for a in r.data.assets:
		_grid.add_child(_tile(a))


func _tile(a: Dictionary) -> Control:
	var c := UI.card(8, UI.CARD, 14)
	var v := UI.vbox(4)
	c.add_child(v)
	var img := TextureRect.new()
	img.custom_minimum_size = Vector2(112, 112)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	v.add_child(img)
	AssetCache.fetch(str(a.ref), func(t):
		if is_instance_valid(img):
			img.texture = t)
	var name := UI.label(str(a.name), 13, UI.TEXT, "bold")
	name.clip_text = true
	name.custom_minimum_size.x = 112
	v.add_child(name)
	var row := UI.hbox(4)
	var use := UI.button(L.t("st_use") if _on_pick.is_valid() else L.t("st_copy_ref"), "ghost", 30)
	use.add_theme_font_size_override("font_size", 13)
	use.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	use.pressed.connect(func():
		if _on_pick.is_valid():
			_on_pick.call(str(a.ref))
			visible = false
		else:
			DisplayServer.clipboard_set(str(a.ref))
			UI.toast(L.t("st_copied"), "ok"))
	row.add_child(use)
	var del := UI.button("✕", "ghost", 30)
	del.custom_minimum_size.x = 30
	del.pressed.connect(func():
		if await UI.confirm(self, L.t("st_delete_image_q"), str(a.name), L.t("st_delete"), true):
			var r := await Api.request("DELETE", "/api/assets/" + str(a.id))
			if r.ok:
				_load()
			else:
				UI.toast(r.message, "error"))
	row.add_child(del)
	v.add_child(row)
	return c


func _upload() -> void:
	StudioFiles.open_file(["*.png ; PNG", "*.jpg, *.jpeg ; JPEG"], func(path: String, bytes: PackedByteArray):
		if bytes.is_empty():
			return
		var r := await Api.request("POST", "/api/assets", {"name": path.get_file().get_basename(), "image": Marshalls.raw_to_base64(bytes)})
		if r.ok:
			UI.toast(L.t("st_uploaded"), "ok")
			_load()
		else:
			UI.toast(r.message, "error"))
