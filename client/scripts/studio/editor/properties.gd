class_name StudioProperties
extends VBoxContainer
## Properties of the selected object with an editor for each type. Edits apply to
## every selected object that has the property, as one undo step.

signal open_script(id: String)
signal pick_asset(done: Callable)
## Like pick_asset, for the uploaded sounds.
signal pick_sound(done: Callable)
## The animation picker's "make one" button.
signal open_animator

var doc: EditDoc
var _box: VBoxContainer
var _updaters := {}  # prop -> Callable(value)
var _shown := ""
var _dirty := true


func setup(d: EditDoc) -> void:
	doc = d
	add_theme_constant_override("separation", 6)
	add_child(UI.label(L.t("st_properties"), 17, UI.TEXT, "black"))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	_box = UI.vbox(6)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_box)
	doc.selection_changed.connect(func(): _dirty = true)
	rebind()


func rebind() -> void:
	if not doc.tree.changed.is_connected(_on_changed):
		doc.tree.changed.connect(_on_changed)
	_dirty = true


func _on_changed(id: String, key: String) -> void:
	if id != _shown:
		return
	if _updaters.has(key):
		_updaters[key].call(doc.tree.prop(id, key) if key != "Name" else doc.tree.name_of(id))
	elif key == "":
		_dirty = true


func _process(_d: float) -> void:
	if _dirty:
		_dirty = false
		_rebuild()


func _rebuild() -> void:
	for c in _box.get_children():
		c.queue_free()
	_updaters.clear()
	var id := doc.primary()
	_shown = id
	if id == "" or not doc.tree.has(id):
		var l := UI.label(L.t("st_nothing_selected"), 15, UI.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_box.add_child(l)
		return
	var c := doc.tree.cls(id)
	var head := UI.hbox(8)
	head.add_child(TextureRect.new())
	(head.get_child(0) as TextureRect).texture = StudioExplorer.icon_for(c)
	(head.get_child(0) as TextureRect).stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	head.add_child(UI.label(c + (" ×%d" % doc.selection.size() if doc.selection.size() > 1 else ""), 16, UI.MUTED, "bold"))
	_box.add_child(head)
	var help := str(StudioSchema.raw(c).get("doc", ""))
	if help != "":
		var hl := UI.label(help, 13, UI.MUTED)
		hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_box.add_child(hl)
	_row("Name", "string", {}, doc.tree.name_of(id))
	var props: Dictionary = StudioSchema.info(c).props
	for k in props:
		if k == "Name":
			continue
		var p: Dictionary = props[k]
		if p.get("readonly", false) and c != "Players":
			continue
		_row(k, str(p.type), p, doc.tree.prop(id, k))


func _apply(key: String, value: Variant) -> void:
	var ids: Array = doc.selection.filter(func(i): return i == doc.primary() or key == "Name" or StudioSchema.info(doc.tree.cls(i)).props.has(key))
	if ids.size() == 1:
		doc.set_prop(ids[0], key, value)
		return
	doc.begin_batch()
	for i in ids:
		doc.set_prop(i, key, value)
	doc.end_batch("Change " + key)


func _row(key: String, type: String, p: Dictionary, value: Variant) -> void:
	var row := UI.hbox(8)
	var name := UI.label(key, 14, UI.TEXT)
	name.custom_minimum_size.x = 104
	name.clip_text = true
	name.tooltip_text = key
	row.add_child(name)
	var ed := _editor(key, type, p, value)
	ed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ed)
	_box.add_child(row)


func _field(text: String, commit: Callable) -> LineEdit:
	var le := LineEdit.new()
	le.text = text
	le.custom_minimum_size.y = 32
	le.add_theme_font_size_override("font_size", 14)
	le.select_all_on_focus = true
	le.text_submitted.connect(func(t):
		commit.call(t)
		le.release_focus())
	le.focus_exited.connect(func(): commit.call(le.text))
	return le


func _num(v: Variant) -> String:
	return SValue.describe(float(v))


func _editor(key: String, type: String, p: Dictionary, value: Variant) -> Control:
	match type:
		"bool":
			var cb := CheckBox.new()
			cb.button_pressed = bool(value)
			cb.toggled.connect(func(on): _apply(key, on))
			_updaters[key] = func(v): cb.set_pressed_no_signal(bool(v))
			return cb
		"number":
			var le := _field(_num(value), func(t):
				if t.is_valid_float():
					var n := float(t)
					if p.has("min"):
						n = maxf(n, float(p.min))
					if p.has("max"):
						n = minf(n, float(p.max))
					_apply(key, n))
			_updaters[key] = func(v):
				if not le.has_focus():
					le.text = _num(v)
			return le
		"Vector3", "Vector2", "UDim2":
			return _multi(key, type, value)
		"Color3":
			var h := UI.hbox(6)
			var picker := ColorPickerButton.new()
			picker.color = value
			picker.edit_alpha = false
			picker.custom_minimum_size = Vector2(44, 32)
			picker.popup_closed.connect(func(): _apply(key, picker.color))
			h.add_child(picker)
			var hex := _field("#" + (value as Color).to_html(false), func(t):
				if Color.html_is_valid(t):
					_apply(key, Color(t)))
			hex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(hex)
			_updaters[key] = func(v):
				picker.color = v
				if not hex.has_focus():
					hex.text = "#" + (v as Color).to_html(false)
			return h
		"source":
			var b := UI.button(L.t("st_edit_script"), "ghost", 34)
			b.add_theme_font_size_override("font_size", 14)
			b.pressed.connect(func(): open_script.emit(doc.primary()))
			return b
		"asset":
			var h := UI.hbox(6)
			var le := _field(str(value), func(t): _apply(key, t.strip_edges()))
			le.placeholder_text = "asset://..."
			le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(le)
			var b := UI.button("…", "ghost", 32)
			b.custom_minimum_size.x = 36
			b.pressed.connect(func(): pick_asset.emit(func(ref: String): _apply(key, ref)))
			h.add_child(b)
			_updaters[key] = func(v):
				if not le.has_focus():
					le.text = str(v)
			return h
		"sound":
			# A built-in sound from the list, or one of yours (asset://...) from the "…" picker.
			var h := UI.hbox(6)
			var ob := OptionButton.new()
			ob.add_theme_font_size_override("font_size", 14)
			ob.fit_to_longest_item = false
			ob.clip_text = true
			ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var builtins := StudioSchema.enum_values("BuiltinSound")
			var fill := func(v: String):
				ob.clear()
				for i in builtins.size():
					ob.add_item(str(builtins[i]), i)
				if v.begins_with("asset://"):
					ob.add_item(L.t("st_my_sound"), builtins.size())
					ob.select(builtins.size())
				else:
					ob.select(maxi(builtins.find(v), 0))
			fill.call(str(value))
			ob.item_selected.connect(func(i):
				if i < builtins.size():
					_apply(key, str(builtins[i])))
			h.add_child(ob)
			var b := UI.button("…", "ghost", 32)
			b.custom_minimum_size.x = 36
			b.tooltip_text = L.t("st_sounds")
			b.pressed.connect(func(): pick_sound.emit(func(ref: String): _apply(key, ref)))
			h.add_child(b)
			_updaters[key] = func(v): fill.call(str(v))
			return h
		"accessories":
			# A Rig's accessories: how many, and a sheet with all of them to tap on and off.
			var list := func(v) -> Array:
				var out: Array = []
				for a in str(v).split(",", false):
					out.append(a.strip_edges())
				return out
			var b := UI.button("", "ghost", 32)
			b.add_theme_font_size_override("font_size", 14)
			var show := func(v): b.text = L.t("st_acc_count", [list.call(v).size()])
			show.call(value)
			b.pressed.connect(func():
				StudioPickers.accessories(self, list.call(doc.tree.prop(doc.primary(), key)), func(worn: Array):
					_apply(key, ",".join(worn))))
			_updaters[key] = show
			return b
		"animation":
			var b := UI.button("", "ghost", 32)
			b.add_theme_font_size_override("font_size", 14)
			b.clip_text = true
			var show := func(v):
				var ref := str(v)
				b.text = "—" if ref == "" else (ref if ref.begins_with("anim://") else L.t("anim_" + ref))
			show.call(value)
			var allow_none: bool = StudioSchema.default_of(doc.tree.cls(doc.primary()), key) == ""
			b.pressed.connect(func():
				StudioPickers.animation(self, allow_none, func(ref: String): _apply(key, ref), func(): open_animator.emit()))
			_updaters[key] = show
			return b
		"Instance":
			var shown := "—"
			if value is Dictionary and value.has("$i"):
				shown = doc.tree.name_of(str(value["$i"]))
			return UI.label(shown, 14, UI.MUTED)
	if type.begins_with("enum:"):
		var ob := OptionButton.new()
		ob.add_theme_font_size_override("font_size", 14)
		ob.fit_to_longest_item = false
		ob.clip_text = true
		var values := StudioSchema.enum_values(type.substr(5))
		for i in values.size():
			ob.add_item(str(values[i]), i)
			if str(values[i]) == str(value):
				ob.select(i)
		ob.item_selected.connect(func(i): _apply(key, str(values[i])))
		_updaters[key] = func(v): ob.select(values.find(str(v)))
		return ob
	var le := _field(str(value), func(t): _apply(key, t))
	_updaters[key] = func(v):
		if not le.has_focus():
			le.text = str(v)
	return le


## X/Y/Z (or scale/offset pairs for UDim2) as separate little fields.
func _multi(key: String, type: String, value: Variant) -> Control:
	var labels: Array = {"Vector3": ["X", "Y", "Z"], "Vector2": ["X", "Y"], "UDim2": ["Xs", "Xo", "Ys", "Yo"]}[type]
	var colors := [Color("#ff6b7a"), Color("#7ee0c3"), Color("#4cc9f0"), Color("#ffd166")]
	var grid := GridContainer.new()
	grid.columns = 2 if type == "UDim2" else labels.size()
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	var fields: Array = []
	var read := func(v: Variant, i: int) -> float:
		if v is Vector3 or v is Vector2:
			return v[i]
		if v is PackedFloat32Array:
			return v[i]
		return 0.0
	for i in labels.size():
		var le := _field(_num(read.call(value, i)), func(t):
			if not t.is_valid_float():
				return
			var cur: Variant = doc.tree.prop(doc.primary(), key)
			var n := float(t)
			if cur is Vector3:
				cur[i] = n
			elif cur is Vector2:
				cur[i] = n
			elif cur is PackedFloat32Array:
				cur = cur.duplicate()
				cur[i] = n
			_apply(key, cur))
		le.custom_minimum_size.x = 48
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.tooltip_text = labels[i]
		var sb := StyleBoxFlat.new()
		sb.bg_color = UI.BG_2
		sb.border_width_left = 3
		sb.border_color = colors[i]
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 6
		sb.content_margin_right = 4
		le.add_theme_stylebox_override("normal", sb)
		var fsb := sb.duplicate() as StyleBoxFlat
		fsb.bg_color = UI.CARD_2
		le.add_theme_stylebox_override("focus", fsb)
		le.add_theme_constant_override("minimum_character_width", 3)
		grid.add_child(le)
		fields.append(le)
	_updaters[key] = func(v):
		for i in fields.size():
			if not fields[i].has_focus():
				fields[i].text = _num(read.call(v, i))
	return grid
