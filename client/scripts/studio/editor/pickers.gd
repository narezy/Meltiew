class_name StudioPickers
extends RefCounted
## Sheets Studio's properties open: accessories for a Rig, animations for a Rig or
## an EmoteOverride.

const BUILTIN_ANIMS := ["idle", "walk", "run", "wave", "dance", "cheer", "sit", "clap", "laugh", "punch", "throw"]


## A centered card over a dim layer; returns [layer, content vbox].
static func _sheet(parent: Node, title: String, width := 640.0) -> Array:
	var layer := CanvasLayer.new()
	layer.layer = 60
	parent.add_child(layer)
	var dim := ColorRect.new()
	dim.theme = UI.theme
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var vp := parent.get_viewport().get_visible_rect().size
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var card := UI.card(18, UI.BG_2, 20)
	card.custom_minimum_size = Vector2(minf(width, vp.x - 32.0), minf(520.0, vp.y - 40.0))
	center.add_child(card)
	var v := UI.vbox(10)
	card.add_child(v)
	var head := UI.hbox(8)
	var tl := UI.label(title, 22, UI.TEXT, "black")
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tl)
	var close := UI.button("✕", "ghost", 40)
	close.custom_minimum_size.x = 44
	close.pressed.connect(layer.queue_free)
	head.add_child(close)
	v.add_child(head)
	return [layer, v]


## Every accessory with its picture; tap to put on or take off (one per slot).
## `done(list)` gets the new list when the sheet closes with "Done".
static func accessories(parent: Node, current: Array, done: Callable) -> void:
	var s := _sheet(parent, L.t("accessories"), 720.0)
	var layer: CanvasLayer = s[0]
	var v: VBoxContainer = s[1]
	var worn := current.duplicate()
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var grid := HFlowContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	sc.add_child(grid)
	var buttons := {}
	var refresh := func():
		for k in buttons:
			buttons[k].button_pressed = k in worn
	for it in Accessories.items():
		var id := str(it.id)
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.theme_type_variation = "ChipButton"
		b.custom_minimum_size = Vector2(104, 124)
		var col := UI.vbox(2)
		col.set_anchors_preset(Control.PRESET_FULL_RECT)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(col)
		var pic := TextureRect.new()
		pic.custom_minimum_size = Vector2(84, 84)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(pic)
		var wr: WeakRef = weakref(pic)
		AccessoryThumbs.fetch(id, func(t: Texture2D):
			var p: TextureRect = wr.get_ref()
			if p:
				p.texture = t)
		var n := UI.label(Accessories.name_of(id), 13, UI.TEXT, "bold")
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n.clip_text = true
		n.custom_minimum_size.x = 96
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(n)
		b.pressed.connect(func():
			if id in worn:
				worn.erase(id)
			else:
				worn = Accessories.wear(worn, id)
			refresh.call())
		grid.add_child(b)
		buttons[id] = b
	refresh.call()
	var row := UI.hbox(8)
	var clear := UI.button(L.t("acc_take_off"), "ghost", 44)
	clear.pressed.connect(func():
		worn = []
		refresh.call())
	row.add_child(clear)
	var ok := UI.button(L.t("done"), "primary", 44)
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.pressed.connect(func():
		layer.queue_free()
		done.call(worn))
	row.add_child(ok)
	v.add_child(row)


## Melly's own moves and your animations from the animator. `done(ref)`.
static func animation(parent: Node, allow_none: bool, done: Callable, open_animator: Callable) -> void:
	var s := _sheet(parent, L.t("anim_pick"), 560.0)
	var layer: CanvasLayer = s[0]
	var v: VBoxContainer = s[1]
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var list := UI.vbox(6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	var pick := func(ref: String):
		layer.queue_free()
		done.call(ref)
	list.add_child(UI.label(L.t("anim_builtin"), 15, UI.MUTED, "bold"))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	list.add_child(flow)
	if allow_none:
		var nb := UI.button("—", "flat", 38)
		nb.theme_type_variation = "ChipButton"
		nb.pressed.connect(func(): pick.call(""))
		flow.add_child(nb)
	for a in BUILTIN_ANIMS:
		var b := UI.button(L.t("anim_" + a), "flat", 38)
		b.theme_type_variation = "ChipButton"
		b.pressed.connect(func(): pick.call(a))
		flow.add_child(b)
	list.add_child(UI.label(L.t("anim_mine"), 15, UI.MUTED, "bold"))
	var mine := UI.vbox(4)
	list.add_child(mine)
	mine.add_child(Loading.spinner(26))
	var make := UI.button(L.t("anim_open_animator"), "ghost", 44)
	make.pressed.connect(func():
		layer.queue_free()
		open_animator.call())
	v.add_child(make)
	var r := await Api.request("GET", "/api/animations")
	if not is_instance_valid(mine):
		return
	for c in mine.get_children():
		c.queue_free()
	var items: Array = r.data.get("animations", []) if r.ok else []
	if items.is_empty():
		var l := UI.label(L.t("anim_none_yet"), 14, UI.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mine.add_child(l)
	for a in items:
		# Each one with its id (what scripts play) and a button to copy it.
		var ref := str(a.ref)
		var row := UI.hbox(6)
		var b := UI.button("%s  · %.1f s" % [str(a.name), float(a.length)], "flat", 44)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): pick.call(ref))
		row.add_child(b)
		var cp := UI.button(ref, "ghost", 44)
		cp.add_theme_font_size_override("font_size", 14)
		cp.add_theme_color_override("font_color", UI.MINT)
		cp.tooltip_text = L.t("an_copy")
		cp.pressed.connect(func():
			DisplayServer.clipboard_set(ref)
			UI.toast(L.t("st_copied") + ": " + ref, "ok"))
		row.add_child(cp)
		mine.add_child(row)
