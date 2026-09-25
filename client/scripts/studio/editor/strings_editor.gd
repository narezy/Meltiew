class_name StudioStrings
extends PanelContainer
## Translations for the place. Each key has a text per language; in the place write
## "$key" in any Text property (UI or 3D text), or Strings.get("key") in scripts.
## Players see their own language, English (or the first filled) otherwise.

var doc: EditDoc
var _table: VBoxContainer
var _langs: Array = ["en", "ru"]
var _new_key: LineEdit
var _add_lang: OptionButton


func setup(d: EditDoc) -> void:
	doc = d
	var sb := StyleBoxFlat.new()
	sb.bg_color = UI.BG_2
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(16)
	sb.border_color = UI.LINE
	sb.set_border_width_all(1)
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(760, 480)
	var v := UI.vbox(10)
	add_child(v)
	var head := UI.hbox(10)
	var title := UI.label(L.t("st_strings"), 22, UI.TEXT, "black")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := UI.button("✕", "ghost", 40)
	close.custom_minimum_size.x = 44
	close.pressed.connect(func(): visible = false)
	head.add_child(close)
	v.add_child(head)
	var hint := UI.label(L.t("st_strings_hint"), 14, UI.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)
	var tools := UI.hbox(8)
	_new_key = UI.input(L.t("st_new_key"))
	_new_key.custom_minimum_size = Vector2(220, 40)
	tools.add_child(_new_key)
	var add := UI.button(L.t("st_add_key"), "primary", 40)
	add.add_theme_font_size_override("font_size", 15)
	add.pressed.connect(_add_key)
	tools.add_child(add)
	tools.add_child(UI.spacer())
	_add_lang = OptionButton.new()
	_add_lang.add_theme_font_size_override("font_size", 15)
	_add_lang.add_item(L.t("st_add_language"), 0)
	for i in Languages.LIST.size():
		_add_lang.add_item(Languages.LIST[i][1], i + 1)
	_add_lang.item_selected.connect(func(i):
		if i > 0:
			var code: String = Languages.LIST[i - 1][0]
			if not code in _langs:
				_langs.append(code)
				_render()
		_add_lang.select(0))
	tools.add_child(_add_lang)
	v.add_child(tools)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	_table = UI.vbox(6)
	_table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_table)


func open() -> void:
	visible = true
	for key in doc.strings:
		for lang in doc.strings[key]:
			if not lang in _langs:
				_langs.append(lang)
	_render()


func _add_key() -> void:
	var key := _new_key.text.strip_edges().replace(" ", "_")
	if key == "" or doc.strings.has(key):
		return
	doc.strings[key] = {}
	doc._set_dirty(true)
	_new_key.text = ""
	_render()


func _render() -> void:
	for c in _table.get_children():
		c.queue_free()
	var head := UI.hbox(6)
	var k := UI.label(L.t("st_key"), 14, UI.MUTED, "bold")
	k.custom_minimum_size.x = 160
	head.add_child(k)
	for lang in _langs:
		var l := UI.label(Languages.name_of(lang), 14, UI.MUTED, "bold")
		l.custom_minimum_size.x = 180
		head.add_child(l)
	_table.add_child(head)
	var keys: Array = doc.strings.keys()
	keys.sort()
	for key in keys:
		var row := UI.hbox(6)
		var kl := UI.label("$" + key, 14, UI.ACCENT, "bold")
		kl.custom_minimum_size.x = 160
		kl.clip_text = true
		row.add_child(kl)
		for lang in _langs:
			var le := LineEdit.new()
			le.custom_minimum_size = Vector2(180, 34)
			le.add_theme_font_size_override("font_size", 14)
			le.text = str(doc.strings[key].get(lang, ""))
			le.text_changed.connect(func(t):
				if t == "":
					doc.strings[key].erase(lang)
				else:
					doc.strings[key][lang] = t
				doc._set_dirty(true))
			row.add_child(le)
		var del := UI.button("✕", "ghost", 34)
		del.custom_minimum_size.x = 34
		del.pressed.connect(func():
			doc.strings.erase(key)
			doc._set_dirty(true)
			_render())
		row.add_child(del)
		_table.add_child(row)
