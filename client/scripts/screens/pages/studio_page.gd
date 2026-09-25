class_name StudioPage
extends ScrollContainer
## Studio home: your places with their status and numbers. Create a new one,
## import a .marp file, open, play, see stats or delete.

var _list: VBoxContainer


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var root := UI.vbox(16)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(root)
	var head := UI.hbox(12)
	var titles := UI.vbox(2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(UI.label(L.t("nav_studio"), 34, UI.TEXT, "black"))
	var sub := UI.label(L.t("studio_sub"), 17, UI.MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(sub)
	head.add_child(titles)
	var imp := UI.button(L.t("st_import"), "ghost", 48)
	imp.pressed.connect(_import)
	head.add_child(imp)
	var create := UI.button("+ " + L.t("st_new_place"), "primary", 48)
	create.pressed.connect(_create)
	head.add_child(create)
	root.add_child(head)
	if OS.has_feature("mobile"):
		var warn := UI.card(14, Color(UI.CARD_2, 0.8), 16)
		var wl := UI.label(L.t("st_mobile_text"), 15, UI.MUTED)
		wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.add_child(wl)
		root.add_child(warn)
	_list = UI.vbox(12)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_list)
	refresh()


func _menu() -> Node:
	return get_meta("menu")


func refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	for i in 2:
		_list.add_child(Loading.row_skeleton(90))
	var r := await Api.request("GET", "/api/studio/places")
	if not is_inside_tree():
		return
	for c in _list.get_children():
		c.queue_free()
	if not r.ok:
		_list.add_child(Loading.error_block(r.message, refresh))
		return
	if r.data.places.is_empty():
		var empty := UI.card(26, Color(UI.CARD, 0.6), 20)
		var l := UI.label(L.t("st_no_places"), 18, UI.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_child(l)
		_list.add_child(empty)
	for p in r.data.places:
		_list.add_child(_row(p))


func _row(p: Dictionary) -> Control:
	var c := UI.card(12, UI.CARD, 20)
	var h := UI.hbox(14)
	c.add_child(h)
	var cover := RoundedImage.new(null, 14)
	cover.custom_minimum_size = Vector2(160, 90)
	h.add_child(cover)
	AssetCache.fetch(str(p.get("cover", "")), func(t):
		if is_instance_valid(cover):
			cover.texture = t)
	var info := UI.vbox(4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_row := UI.hbox(8)
	name_row.add_child(UI.label(L.field(p, "name"), 21, UI.TEXT, "black"))
	var vis := str(p.get("visibility", "private"))
	var badge := UI.label(L.t("st_vis_" + vis), 12, UI.INK, "black")
	var sb := StyleBoxFlat.new()
	sb.bg_color = {"public": UI.MINT, "friends": UI.ACCENT}.get(vis, UI.MUTED)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	badge.add_theme_stylebox_override("normal", sb)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(badge)
	info.add_child(name_row)
	info.add_child(UI.label(L.t("st_place_line", [int(p.visits), int(p.playing), UI.relative_time(float(p.get("updated_at", 0)))]), 14, UI.MUTED))
	h.add_child(info)
	var edit := UI.button(L.t("st_open"), "primary", 44)
	edit.pressed.connect(func():
		Session.studio_place_id = str(p.id)
		Session.studio_marp = {}
		UI.goto("res://scenes/studio.tscn"))
	edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(edit)
	var play := UI.button(L.t("play"), "mint", 44)
	play.pressed.connect(func(): _menu().play("auto", str(p.id)))
	play.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(play)
	var more := MenuButton.new()
	more.text = "•••"
	more.flat = true
	more.custom_minimum_size = Vector2(52, 44)
	more.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	more.add_theme_font_size_override("font_size", 16)
	more.add_theme_color_override("font_color", UI.TEXT)
	more.add_theme_color_override("font_hover_color", UI.ACCENT)
	var pm := more.get_popup()
	pm.add_theme_font_size_override("font_size", 16)
	pm.add_item(L.t("st_stats"), 0)
	pm.add_item(L.t("st_delete"), 1)
	pm.id_pressed.connect(func(i):
		if i == 0:
			_stats(p)
		else:
			_delete(p))
	h.add_child(more)
	return c


func _create() -> void:
	var name := await _ask_name()
	if name == "":
		return
	var r := await Api.request("POST", "/api/studio/places", {"name": name})
	if not r.ok:
		UI.toast(r.message, "error")
		return
	Session.studio_place_id = str(r.data.place.id)
	Session.studio_marp = {}
	UI.goto("res://scenes/studio.tscn")


func _ask_name() -> String:
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	var dim := ColorRect.new()
	dim.theme = UI.theme
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var card := UI.card(24, UI.CARD, 24)
	card.custom_minimum_size.x = 440
	center.add_child(card)
	var v := UI.vbox(12)
	card.add_child(v)
	v.add_child(UI.label(L.t("st_new_place"), 24, UI.TEXT, "black"))
	var input := UI.input(L.t("st_place_name"))
	input.max_length = 60
	v.add_child(input)
	var row := UI.hbox(10)
	var cancel := UI.button(L.t("cancel"), "ghost", 48)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ok := UI.button(L.t("st_create"), "primary", 48)
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cancel)
	row.add_child(ok)
	v.add_child(row)
	input.grab_focus()
	var result := [null]
	cancel.pressed.connect(func(): result[0] = "")
	ok.pressed.connect(func(): result[0] = input.text.strip_edges())
	input.text_submitted.connect(func(t): result[0] = t.strip_edges())
	while result[0] == null:
		await get_tree().process_frame
	layer.queue_free()
	return result[0]


func _import() -> void:
	StudioFiles.open_file(["*.marp ; Meltiew place"], func(path: String, bytes: PackedByteArray):
		var marp: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		if not (marp is Dictionary and marp.get("format") == "marp"):
			UI.toast(L.t("st_bad_file"), "error")
			return
		var r := await Api.request("POST", "/api/studio/places", {"name": str(marp.get("meta", {}).get("name", path.get_file().get_basename())), "marp": marp})
		if r.ok:
			refresh()
		else:
			UI.toast(r.message, "error"))


func _stats(p: Dictionary) -> void:
	var r := await Api.request("GET", "/api/studio/places/%s/stats" % p.id)
	if not r.ok:
		UI.toast(r.message, "error")
		return
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	var dim := ColorRect.new()
	dim.theme = UI.theme
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var card := UI.card(22, UI.CARD, 24)
	card.custom_minimum_size.x = 620
	center.add_child(card)
	var v := UI.vbox(12)
	card.add_child(v)
	v.add_child(UI.label(L.field(p, "name"), 24, UI.TEXT, "black"))
	v.add_child(StudioSettings.stats_view(r.data.stats))
	var close := UI.button(L.t("close"), "ghost", 46)
	close.pressed.connect(layer.queue_free)
	v.add_child(close)


func _delete(p: Dictionary) -> void:
	if not await UI.confirm(self, L.t("st_delete_place_q"), L.field(p, "name"), L.t("st_delete"), true):
		return
	var r := await Api.request("DELETE", "/api/studio/places/" + str(p.id))
	if r.ok:
		refresh()
	else:
		UI.toast(r.message, "error")
