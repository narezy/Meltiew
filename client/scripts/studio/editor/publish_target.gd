class_name PublishTarget
extends RefCounted
## "Publish where?": this place, a new place page, or one of your other places
## (its content gets replaced, its page stays).


## Returns {"kind": "current" | "new" | "place", "id", "name"} or {} if closed.
static func choose(parent: Node, current_id: String) -> Dictionary:
	var layer := CanvasLayer.new()
	layer.layer = 60
	parent.add_child(layer)
	var dim := ColorRect.new()
	dim.theme = UI.theme
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var card := UI.card(22, UI.CARD, 22)
	var vp := parent.get_viewport().get_visible_rect().size
	card.custom_minimum_size = Vector2(minf(560.0, vp.x - 40.0), 0)
	center.add_child(card)
	var v := UI.vbox(10)
	card.add_child(v)
	var head := UI.hbox(8)
	var title := UI.label(L.t("st_pub_title"), 24, UI.TEXT, "black")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := UI.button("✕", "ghost", 40)
	close.custom_minimum_size.x = 44
	head.add_child(close)
	v.add_child(head)

	var result := [null]
	close.pressed.connect(func(): result[0] = {})
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			result[0] = {})

	var current_name := ""
	var others: Array = []
	var r := await Api.request("GET", "/api/studio/places")
	for p in (r.data.get("places", []) if r.ok else []):
		if str(p.id) == current_id:
			current_name = str(p.get("name", ""))
		else:
			others.append(p)

	v.add_child(_option(L.t("st_pub_this") + (" · " + current_name if current_name != "" else ""), L.t("st_pub_this_hint"), "primary",
		func(): result[0] = {"kind": "current", "id": current_id}))
	v.add_child(_option(L.t("st_pub_new"), L.t("st_pub_new_hint"), "ghost",
		func(): result[0] = {"kind": "new"}))
	if not others.is_empty():
		v.add_child(UI.label(L.t("st_pub_other"), 16, UI.MUTED, "bold"))
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size.y = minf(others.size() * 52.0, maxf(vp.y * 0.6 - 260.0, 104.0))
		v.add_child(scroll)
		var list := UI.vbox(4)
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(list)
		for p in others:
			var b := UI.button(str(p.get("name", "?")), "flat", 48)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.mouse_filter = Control.MOUSE_FILTER_PASS
			b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			var pick := {"kind": "place", "id": str(p.id), "name": str(p.get("name", ""))}
			b.pressed.connect(func(): result[0] = pick)
			list.add_child(b)

	while result[0] == null:
		await parent.get_tree().process_frame
	layer.queue_free()
	return result[0]


static func _option(text: String, hint: String, variant: String, on_press: Callable) -> Control:
	var b := UI.button(text, variant, 64)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.tooltip_text = hint
	b.pressed.connect(on_press)
	var box := UI.vbox(2)
	box.add_child(b)
	var h := UI.label(hint, 14, UI.MUTED)
	h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(h)
	return box
