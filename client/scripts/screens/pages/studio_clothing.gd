class_name StudioClothing
extends VBoxContainer
## Studio → Accessories: the shirts you (or your communities) have made, and making new
## ones: save the template, paint it in any program, load the PNG back, see it on a 3D
## Melly, name it, set a price (free or pieces) and publish. Making one costs 10 pieces
## or 100 orbs.

const TEMPLATE := preload("res://assets/clothing_template.png")

var communities: Array = []  # [{id, name}] you may make things for
var _list: VBoxContainer


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	var head := UI.hbox(12)
	var info := UI.label(L.t("cl_sub"), 16, UI.MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(info)
	var make := UI.button("+ " + L.t("cl_new"), "primary", 48)
	make.pressed.connect(func(): _editor({}))
	head.add_child(make)
	add_child(head)
	_list = UI.vbox(10)
	add_child(_list)
	refresh()


func refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	_list.add_child(Loading.row_skeleton(80))
	var r := await Api.request("GET", "/api/studio/clothing")
	if not is_inside_tree():
		return
	for c in _list.get_children():
		c.queue_free()
	if not r.ok:
		_list.add_child(Loading.error_block(r.message, refresh))
		return
	if r.data.items.is_empty():
		var empty := UI.card(26, Color(UI.CARD, 0.6), 20)
		var l := UI.label(L.t("cl_none"), 18, UI.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_child(l)
		_list.add_child(empty)
	for it in r.data.items:
		_list.add_child(_row(it))


func _row(it: Dictionary) -> Control:
	var c := UI.card(12, UI.CARD, 20)
	var h := UI.hbox(14)
	c.add_child(h)
	h.add_child(_thumb(str(it.image), 72))
	var v := UI.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(UI.label(str(it.name), 20, UI.TEXT, "black"))
	var price := int(it.get("price", 0))
	var meta := "%s · %s" % [L.t("cl_free") if price == 0 else "%d %s" % [price, L.t("eco_pieces")], L.t("cl_sales", [int(it.get("sales", 0))])]
	if it.get("community") is Dictionary:
		meta += " · " + str(it.community.name)
	v.add_child(UI.label(meta, 15, UI.MUTED))
	var edit := UI.button(L.t("edit"), "ghost", 44)
	edit.pressed.connect(func(): _editor(it))
	h.add_child(edit)
	var del := UI.button("🗑", "ghost", 44)
	del.custom_minimum_size.x = 48
	del.pressed.connect(func():
		if not await UI.confirm(self, L.t("cl_delete_q", [it.name]), L.t("cl_delete_text"), L.t("delete"), true):
			return
		var r := await Api.request("DELETE", "/api/studio/clothing/%d" % int(it.id))
		if r.ok:
			refresh()
		else:
			UI.toast(r.message, "error"))
	h.add_child(del)
	return c


static func _thumb(url: String, h: float, tex: Texture2D = null) -> Control:
	var tile := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(str(Session.colors_of(Session.user).get("torso", "#8a7cf0")))
	sb.set_corner_radius_all(8)
	tile.add_theme_stylebox_override("panel", sb)
	var front := ClothingLayout.torso_front()
	tile.custom_minimum_size = Vector2(h * front.size.x / front.size.y, h)
	var pic := TextureRect.new()
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_SCALE
	pic.set_anchors_preset(Control.PRESET_FULL_RECT)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(pic)
	var put := func(t: Texture2D):
		if t and is_instance_valid(pic):
			var at := AtlasTexture.new()
			at.atlas = t
			at.region = front
			pic.texture = at
	if tex:
		put.call(tex)
	elif url != "":
		AssetCache.fetch(url, put)
	return tile


## Making (it empty) or changing a shirt, in a window over the studio.
func _editor(it: Dictionary) -> void:
	var editing := not it.is_empty()
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var margin := MarginContainer.new()
	margin.theme = UI.theme
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12 if UI.is_compact() else 40)
	layer.add_child(margin)
	var card := UI.card(20, UI.CARD, 24)
	margin.add_child(card)
	var row := UI.hbox(18)
	card.add_child(row)
	var close := func(): layer.queue_free()

	# Left: the Melly wearing it.
	var stage_card := UI.card(0, Color(UI.BG_2, 0.8), 20)
	stage_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_card.size_flags_stretch_ratio = 0.8
	row.add_child(stage_card)
	var stage := AvatarStage.new()
	stage.zoom = 1.1
	stage_card.add_child(stage)
	stage.avatar.apply_user(Session.user)
	stage.avatar.set_clothes([])

	# Right: the steps.
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sc)
	var v := UI.vbox(12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	v.add_child(UI.label(L.t("cl_edit") if editing else L.t("cl_new"), 28, UI.TEXT, "black"))
	var state := {"image": PackedByteArray(), "tex": null}
	if editing:
		AssetCache.fetch(str(it.image), func(t: Texture2D):
			if t and is_instance_valid(stage):
				stage.avatar.set_extra_clothes([t]))

	var step1 := UI.label(L.t("cl_step1"), 16, UI.MUTED)
	step1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(step1)
	var tpl := UI.button(L.t("cl_template"), "ghost", 44)
	tpl.pressed.connect(func():
		StudioFiles.save_file("meltiew_shirt_template.png", ["*.png"], TEMPLATE.get_image().save_png_to_buffer(), func(path: String):
			UI.toast(L.t("cl_template_saved", [path]), "ok")))
	v.add_child(tpl)
	var pick_row := UI.hbox(10)
	var pick := UI.button(L.t("cl_pick"), "primary", 44)
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick_row.add_child(pick)
	var thumb_box := UI.hbox(0)  # the picked picture's front, once there is one
	pick_row.add_child(thumb_box)
	v.add_child(pick_row)
	pick.pressed.connect(func():
		StudioFiles.open_file(["*.png"], func(_path: String, bytes: PackedByteArray):
			var img := Image.new()
			if bytes.is_empty() or img.load_png_from_buffer(bytes) != OK:
				UI.toast(L.t("cl_bad_png"), "error")
				return
			if img.get_width() != ClothingLayout.W or img.get_height() != ClothingLayout.H:
				UI.toast(L.t("cl_bad_size", [img.get_width(), img.get_height()]), "error")
				return
			img.generate_mipmaps()
			var tex := ImageTexture.create_from_image(img)
			state.image = bytes
			state.tex = tex
			stage.avatar.set_extra_clothes([tex])
			stage.avatar.play("wave")
			for ch in thumb_box.get_children():
				ch.queue_free()
			thumb_box.add_child(_thumb("", 44, tex))))

	v.add_child(UI.label(L.t("cl_name"), 16, UI.MUTED, "bold"))
	var name := UI.input(L.t("cl_name_hint"))
	name.max_length = 40
	name.text = str(it.get("name", ""))
	v.add_child(name)
	var desc := UI.input(L.t("cl_desc_hint"))
	desc.max_length = 300
	desc.text = str(it.get("description", ""))
	v.add_child(desc)
	v.add_child(UI.label(L.t("cl_price"), 16, UI.MUTED, "bold"))
	var price := SpinBox.new()
	price.min_value = 0
	price.max_value = 100000
	price.step = 1
	price.value = int(it.get("price", 0))
	price.suffix = L.t("eco_pieces")
	var price_hint := UI.label(L.t("cl_price_hint"), 14, UI.MUTED)
	price_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(price)
	v.add_child(price_hint)

	var owner := OptionButton.new()
	var pay := {"currency": "pieces"}
	if not editing:
		v.add_child(UI.label(L.t("cl_owner"), 16, UI.MUTED, "bold"))
		owner.add_item(L.t("cl_owner_me"), 0)
		owner.set_item_metadata(0, null)
		for cm in communities:
			owner.add_item(str(cm.get("name", "")), owner.item_count)
			owner.set_item_metadata(owner.item_count - 1, int(cm.id))
		v.add_child(owner)
		v.add_child(UI.label(L.t("cl_pay"), 16, UI.MUTED, "bold"))
		var chips := UI.hbox(8)
		var b1 := UI.button("10 " + L.t("eco_pieces"), "flat", 42)
		var b2 := UI.button("100 " + L.t("eco_orbs"), "flat", 42)
		for b in [b1, b2]:
			b.theme_type_variation = "ChipButton"
			b.toggle_mode = true
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			chips.add_child(b)
		b1.button_pressed = true
		b1.pressed.connect(func():
			pay.currency = "pieces"
			b1.button_pressed = true
			b2.button_pressed = false)
		b2.pressed.connect(func():
			pay.currency = "orbs"
			b2.button_pressed = true
			b1.button_pressed = false)
		v.add_child(chips)

	var buttons := UI.hbox(10)
	var cancel := UI.button(L.t("cancel"), "ghost", 50)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(close)
	buttons.add_child(cancel)
	var go := UI.button(L.t("save") if editing else L.t("cl_publish"), "primary", 50)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(go)
	v.add_child(buttons)
	go.pressed.connect(func():
		if not editing and state.image.is_empty():
			UI.toast(L.t("cl_need_image"), "error")
			return
		if name.text.strip_edges().length() < 2:
			UI.toast(L.t("cl_need_name"), "error")
			return
		var body := {"name": name.text.strip_edges(), "description": desc.text.strip_edges(), "price": int(price.value)}
		if not state.image.is_empty():
			body.image = Marshalls.raw_to_base64(state.image)
		go.disabled = true
		var r: Dictionary
		if editing:
			r = await Api.request("PATCH", "/api/studio/clothing/%d" % int(it.id), body)
		else:
			body.currency = pay.currency
			var cm: Variant = owner.get_item_metadata(owner.selected) if owner.item_count > 0 else null
			if cm != null:
				body.community_id = cm
			r = await Api.request("POST", "/api/studio/clothing", body)
		if not is_inside_tree():
			return
		go.disabled = false
		if not r.ok:
			UI.toast(r.message, "error")
			return
		if r.data.get("wallet") is Dictionary:
			Economy.set_wallet(r.data.wallet)
		UI.toast(L.t("cl_saved") if editing else L.t("cl_published"), "ok")
		close.call()
		refresh())
