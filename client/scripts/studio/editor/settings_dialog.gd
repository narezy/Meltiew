class_name StudioSettings
extends PanelContainer
## Place settings and publishing: name and description (with translations), who can
## play it, max players, comments, the 16:9 cover and the 1:1 icon, and stats.

signal save_requested
var doc: EditDoc
var place_id := ""
var place: Dictionary = {}
var capture: Callable  # returns Image of the current 3D view
var _v: VBoxContainer


func setup(d: EditDoc) -> void:
	doc = d
	var sb := StyleBoxFlat.new()
	sb.bg_color = UI.BG_2
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(18)
	sb.border_color = UI.LINE
	sb.set_border_width_all(1)
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(720, 560)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	_v = UI.vbox(12)
	_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_v)


func open() -> void:
	visible = true
	for c in _v.get_children():
		c.queue_free()
	_v.add_child(Loading.block())
	var r := await Api.request("GET", "/api/studio/places/" + place_id)
	if r.ok:
		place = r.data.place
	_render()


func _section(title: String) -> VBoxContainer:
	var box := UI.vbox(8)
	box.add_child(UI.label(title, 18, UI.TEXT, "black"))
	_v.add_child(box)
	return box


func _render() -> void:
	for c in _v.get_children():
		c.queue_free()
	var head := UI.hbox(10)
	var title := UI.label(L.t("st_settings"), 24, UI.TEXT, "black")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := UI.button("✕", "ghost", 40)
	close.custom_minimum_size.x = 44
	close.pressed.connect(func(): visible = false)
	head.add_child(close)
	_v.add_child(head)

	var basics := _section(L.t("st_basics"))
	var name := UI.input(L.t("st_place_name"))
	name.text = str(doc.meta.get("name", ""))
	name.max_length = 60
	name.text_changed.connect(func(t):
		doc.meta.name = t
		doc._set_dirty(true))
	basics.add_child(name)
	var desc := TextEdit.new()
	desc.text = str(doc.meta.get("description", ""))
	desc.custom_minimum_size.y = 90
	desc.placeholder_text = L.t("st_place_description")
	desc.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	desc.text_changed.connect(func():
		doc.meta.description = desc.text
		doc._set_dirty(true))
	basics.add_child(desc)

	# Translations of the name and description.
	var tr := _section(L.t("st_translations"))
	var i18n: Dictionary = doc.meta.get("i18n", {"name": {}, "description": {}})
	doc.meta["i18n"] = i18n
	for key in ["name", "description"]:
		if not i18n.has(key):
			i18n[key] = {}
	var langs: Array = []
	for key in ["name", "description"]:
		for lang in i18n[key]:
			if not lang in langs:
				langs.append(lang)
	if langs.is_empty():
		langs = ["ru"]
	for lang in langs:
		var row := UI.hbox(8)
		var ll := UI.label(Languages.name_of(lang), 14, UI.MUTED, "bold")
		ll.custom_minimum_size.x = 120
		row.add_child(ll)
		for key in ["name", "description"]:
			var le := LineEdit.new()
			le.placeholder_text = L.t("st_place_name") if key == "name" else L.t("st_place_description")
			le.text = str(i18n[key].get(lang, ""))
			le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			le.text_changed.connect(func(t):
				if t == "":
					i18n[key].erase(lang)
				else:
					i18n[key][lang] = t
				doc._set_dirty(true))
			row.add_child(le)
		tr.add_child(row)
	var add_lang := Picker.new(L.t("st_add_language"), L.t("st_add_language"))
	for i in Languages.LIST.size():
		add_lang.add_item(Languages.LIST[i][1], Languages.LIST[i][0])
	add_lang.picked.connect(func(code):
		if not i18n.name.has(code):
			i18n.name[code] = ""
		_render())
	tr.add_child(add_lang)

	var access := _section(L.t("st_access"))
	var vis := OptionButton.new()
	vis.add_theme_font_size_override("font_size", 15)
	var options := [["private", L.t("st_vis_private")], ["friends", L.t("st_vis_friends")], ["public", L.t("st_vis_public")]]
	for i in options.size():
		vis.add_item(options[i][1], i)
		if options[i][0] == str(place.get("visibility", "private")):
			vis.select(i)
	vis.item_selected.connect(func(i): _patch({"visibility": options[i][0]}))
	access.add_child(vis)
	var maxp := HSlider.new()
	maxp.min_value = 1
	maxp.max_value = 30
	maxp.step = 1
	maxp.value = int(place.get("max_players", 10))
	var maxl := UI.label(L.t("st_max_players", [int(maxp.value)]), 15, UI.TEXT)
	maxp.value_changed.connect(func(v): maxl.text = L.t("st_max_players", [int(v)]))
	maxp.drag_ended.connect(func(_c): _patch({"max_players": int(maxp.value)}))
	access.add_child(maxl)
	access.add_child(maxp)
	var com := CheckBox.new()
	com.text = L.t("st_comments")
	com.button_pressed = bool(place.get("comments_enabled", true))
	com.toggled.connect(func(on): _patch({"comments_enabled": on}))
	access.add_child(com)

	var covers := _section(L.t("st_covers"))
	for kind in ["wide", "square"]:
		var row := UI.hbox(10)
		var img := TextureRect.new()
		img.custom_minimum_size = Vector2(160, 90) if kind == "wide" else Vector2(90, 90)
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		row.add_child(img)
		var url := str(place.get("cover" if kind == "wide" else "cover_square", ""))
		if url != "" and not url.begins_with("/img/"):
			AssetCache.fetch(url, func(t):
				if is_instance_valid(img):
					img.texture = t)
		var col := UI.vbox(6)
		col.add_child(UI.label(L.t("st_cover_wide") if kind == "wide" else L.t("st_cover_square"), 15, UI.TEXT, "bold"))
		var b1 := UI.button(L.t("st_take_from_view"), "ghost", 36)
		b1.add_theme_font_size_override("font_size", 14)
		b1.pressed.connect(func(): _upload_cover(kind, _crop(capture.call(), kind)))
		col.add_child(b1)
		var b2 := UI.button(L.t("st_upload"), "ghost", 36)
		b2.add_theme_font_size_override("font_size", 14)
		b2.pressed.connect(func():
			StudioFiles.open_file(["*.png ; PNG", "*.jpg, *.jpeg ; JPEG"], func(_p, bytes):
				var im := Image.new()
				if im.load_png_from_buffer(bytes) != OK and im.load_jpg_from_buffer(bytes) != OK:
					UI.toast(L.t("bad_image"), "error")
					return
				_upload_cover(kind, _crop(im, kind))))
		col.add_child(b2)
		row.add_child(col)
		covers.add_child(row)

	var passes := _section(L.t("eco_passes"))
	var ph := UI.label(L.t("eco_pass_hint"), 14, UI.MUTED)
	ph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	passes.add_child(ph)
	_load_passes(passes)

	var stats := _section(L.t("st_stats"))
	stats.add_child(Loading.spinner(28))
	_load_stats(stats)

	var save := UI.button(L.t("st_save_publish"), "primary", 50)
	save.pressed.connect(func(): save_requested.emit())
	_v.add_child(save)


func _crop(img: Image, kind: String) -> Image:
	if img == null:
		return null
	var w := img.get_width()
	var h := img.get_height()
	var target := Vector2i(800, 450) if kind == "wide" else Vector2i(512, 512)
	var aspect := float(target.x) / target.y
	var cw := mini(w, int(h * aspect))
	var ch := int(cw / aspect)
	var out := img.get_region(Rect2i((w - cw) / 2, (h - ch) / 2, cw, ch))
	out.resize(target.x, target.y, Image.INTERPOLATE_LANCZOS)
	return out


func _upload_cover(kind: String, img: Image) -> void:
	if img == null:
		return
	var png := img.save_png_to_buffer()
	var r := await Api.request("POST", "/api/studio/places/%s/cover" % place_id, {"kind": kind, "image": Marshalls.raw_to_base64(png)})
	if r.ok:
		place = r.data.place
		UI.toast(L.t("saved"), "ok")
		_render()
	else:
		UI.toast(r.message, "error")


func _patch(body: Dictionary) -> void:
	var r := await Api.request("PATCH", "/api/studio/places/" + place_id, body)
	if r.ok:
		place = r.data.place
		UI.toast(L.t("saved"), "ok")
	else:
		UI.toast(r.message, "error")


func _load_stats(box: VBoxContainer) -> void:
	var r := await Api.request("GET", "/api/studio/places/%s/stats" % place_id)
	if not is_instance_valid(box):
		return
	for c in box.get_children():
		if c is Loading.Spinner:
			c.queue_free()
	if not r.ok:
		box.add_child(UI.label(r.message, 14, UI.MUTED))
		return
	box.add_child(StudioSettings.stats_view(r.data.stats))


## Visits, players, playtime and a 30-day chart of visits.
static func stats_view(s: Dictionary) -> Control:
	var v := UI.vbox(10)
	var tiles := HFlowContainer.new()
	tiles.add_theme_constant_override("h_separation", 8)
	tiles.add_theme_constant_override("v_separation", 8)
	var hours := float(s.get("playtime_ms", 0)) / 3600000.0
	for t in [
		[L.t("st_visits"), str(int(s.visits))],
		[L.t("st_players"), str(int(s.unique_players))],
		[L.t("st_returning"), str(int(s.returning_players))],
		[L.t("st_playtime"), (str(snappedf(hours, 0.1)) + " h") if hours >= 1.0 else (str(int(hours * 60.0)) + " min")],
		[L.t("st_session"), str(int(float(s.avg_session_ms) / 60000.0)) + " min"],
		[L.t("st_now"), str(int(s.playing))],
		["♥", "%d / %d" % [int(s.likes), int(s.dislikes)]],
		[L.t("st_comments_n"), str(int(s.comments))],
	]:
		var c := UI.card(10, UI.CARD, 14)
		var cv := UI.vbox(0)
		cv.add_child(UI.label(t[0], 12, UI.MUTED, "bold"))
		cv.add_child(UI.label(t[1], 20, UI.TEXT, "black"))
		c.add_child(cv)
		c.custom_minimum_size.x = 110
		tiles.add_child(c)
	v.add_child(tiles)
	var daily: Array = s.get("daily", [])
	if not daily.is_empty():
		var chart := HBoxContainer.new()
		chart.custom_minimum_size.y = 90
		chart.add_theme_constant_override("separation", 3)
		var top := 1
		for d in daily:
			top = maxi(top, int(d.visits))
		for d in daily:
			var col := VBoxContainer.new()
			col.alignment = BoxContainer.ALIGNMENT_END
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			col.tooltip_text = "%s: %d" % [d.day, int(d.visits)]
			var bar := ColorRect.new()
			bar.color = UI.ACCENT
			bar.custom_minimum_size = Vector2(6, maxf(3.0, 80.0 * int(d.visits) / top))
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.add_child(bar)
			chart.add_child(col)
		v.add_child(UI.label(L.t("st_last_30"), 13, UI.MUTED, "bold"))
		v.add_child(chart)
	return v


## This place's gamepasses: the list (with ids for scripts) and a form for a new one.
func _load_passes(box: VBoxContainer) -> void:
	var list := UI.vbox(6)
	box.add_child(list)
	var r := await Api.request("GET", "/api/places/%s/passes" % place_id)
	if not is_instance_valid(list):
		return
	for p in (r.data.get("passes", []) if r.ok else []):
		var row := UI.hbox(8)
		var n := UI.label(str(p.name), 16, UI.TEXT, "bold")
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.clip_text = true
		row.add_child(n)
		row.add_child(Economy.price_tag({"pieces": int(p.price)}, 15))
		row.add_child(UI.label(L.t("eco_pass_sold", [int(p.id), int(p.sales)]), 14, UI.MUTED))
		var del := UI.button("✕", "ghost", 36)
		del.custom_minimum_size.x = 40
		var pid := int(p.id)
		del.pressed.connect(func():
			var d := await Api.request("DELETE", "/api/studio/places/%s/passes/%d" % [place_id, pid])
			if d.ok:
				row.queue_free()
			else:
				UI.toast(d.message, "error"))
		row.add_child(del)
		list.add_child(row)
	var form := UI.hbox(8)
	var name := UI.input(L.t("eco_pass_name"))
	name.max_length = 50
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(name)
	var price := SpinBox.new()
	price.min_value = 1
	price.max_value = 100000
	price.value = 25
	price.custom_minimum_size.x = 110
	price.tooltip_text = L.t("eco_pass_price")
	form.add_child(price)
	var image := [""]
	var pick := UI.button(L.t("eco_pass_pick_image"), "ghost", 44)
	pick.pressed.connect(func():
		StudioFiles.open_file(["*.png ; PNG", "*.jpg, *.jpeg ; JPEG"], func(_path, bytes):
			var im := Image.new()
			if im.load_png_from_buffer(bytes) != OK and im.load_jpg_from_buffer(bytes) != OK:
				UI.toast(L.t("bad_image"), "error")
				return
			image[0] = Marshalls.raw_to_base64(_crop(im, "square").save_png_to_buffer())
			pick.text = "✓ " + L.t("eco_pass_pick_image")))
	form.add_child(pick)
	var add := UI.button(L.t("eco_pass_new"), "primary", 44)
	add.pressed.connect(func():
		var body := {"name": name.text.strip_edges(), "price": int(price.value)}
		if image[0] != "":
			body.image = image[0]
		var c := await Api.request("POST", "/api/studio/places/%s/passes" % place_id, body)
		if not c.ok:
			UI.toast(c.message, "error")
			return
		UI.toast(L.t("saved"), "ok")
		for ch in box.get_children():
			if ch != box.get_child(0) and ch != box.get_child(1):
				ch.queue_free()
		_load_passes(box))
	form.add_child(add)
	box.add_child(form)
