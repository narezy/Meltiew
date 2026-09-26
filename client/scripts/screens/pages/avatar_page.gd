class_name AvatarPage
extends HBoxContainer
## Avatar editor: color each of the six body parts, and put on the faces and
## accessories you own (new ones come from the shop page), profile.

var _stage: AvatarStage
var _colors := {}
var _worn: Array = []
var _face := ":D"
var _face_buttons := {}
var _selected_parts := ["torso"]
var _part_buttons := {}
var _swatch_buttons: Array[Button] = []
var _acc_buttons := {}
var _save: Button
var _name_edit: LineEdit
var _bio_edit: TextEdit
var _tab_pages := {}
var _tab_buttons := {}
var _dirty := false
var _custom_picker: ColorPickerButton


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 24)
	_colors = Session.colors_of(Session.user)
	_worn = Session.worn_of(Session.user)
	_face = str(Session.user.get("face", ":D"))

	var compact := UI.is_compact()
	if compact:
		add_theme_constant_override("separation", 16)
	var left := UI.vbox(12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.62 if compact else 0.8
	add_child(left)
	var title_row := UI.hbox(10)
	var title := UI.label(L.t("nav_avatar"), 34, UI.TEXT, "black")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	title_row.add_child(Economy.chips(self))
	left.add_child(title_row)
	var stage_card := UI.card(0, Color(UI.CARD, 0.55), 26)
	stage_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(stage_card)
	_stage = AvatarStage.new()
	_stage.zoom = 1.15
	stage_card.add_child(_stage)
	_stage.clicked.connect(func(): _stage.avatar.play("wave"))
	var tools := UI.hbox(10)
	var wave := UI.button(L.t("wave"), "ghost", 48)
	wave.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wave.pressed.connect(func(): _stage.avatar.play("wave"))
	tools.add_child(wave)
	var rnd := UI.button(L.t("random"), "ghost", 48)
	rnd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rnd.pressed.connect(_randomize)
	tools.add_child(rnd)
	var reset := UI.button(L.t("like_melly"), "ghost", 48)
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.pressed.connect(func():
		_colors = Session.DEFAULT_COLORS.duplicate()
		_worn = []
		_face = ":D"
		_apply_preview())
	tools.add_child(reset)
	if compact:
		for b in tools.get_children():
			b.add_theme_font_size_override("font_size", 15)
			b.custom_minimum_size.y = 44
	left.add_child(tools)

	var right := UI.vbox(14)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right)
	# Wraps into two rows when the column is narrow (phones, long translations).
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 8)
	tabs.add_theme_constant_override("v_separation", 8)
	for t in [["colors", L.t("colors")], ["faces", L.t("faces")], ["hats", L.t("accessories")], ["profile", L.t("profile")]]:
		var b := UI.button(t[1], "flat", 46)
		b.theme_type_variation = "ChipButton"
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if compact:
			b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(func(): _show_tab(t[0]))
		tabs.add_child(b)
		_tab_buttons[t[0]] = b
	right.add_child(tabs)

	var body := UI.card(20, UI.CARD, 24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(body)
	var stack := Control.new()
	body.add_child(stack)
	_tab_pages.colors = _build_colors_tab()
	_tab_pages.hats = _build_hats_tab()
	_tab_pages.faces = _build_faces_tab()
	_tab_pages.profile = _build_profile_tab()
	for k in _tab_pages:
		var sc := ScrollContainer.new()
		sc.set_anchors_preset(Control.PRESET_FULL_RECT)
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_tab_pages[k].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(_tab_pages[k])
		stack.add_child(sc)
		_tab_pages[k] = sc

	_save = UI.button(L.t("save"), "primary", 58)
	_save.pressed.connect(_on_save)
	right.add_child(_save)

	_show_tab("colors")
	_apply_preview()
	_set_dirty(false)


func _show_tab(id: String) -> void:
	for k in _tab_pages:
		_tab_pages[k].visible = k == id
		_tab_buttons[k].button_pressed = k == id


func _build_colors_tab() -> Control:
	var v := UI.vbox(14)
	v.add_child(UI.label(L.t("what_to_paint"), 18, UI.MUTED, "bold"))
	var parts := HFlowContainer.new()
	parts.add_theme_constant_override("h_separation", 8)
	parts.add_theme_constant_override("v_separation", 8)
	var all := _chip(L.t("whole_body"))
	all.pressed.connect(func(): _select_parts(Session.BODY_PARTS.duplicate()))
	parts.add_child(all)
	_part_buttons["_all"] = all
	for part in Session.BODY_PARTS:
		var b := _chip(L.t("part_" + part))
		b.pressed.connect(func(): _select_parts([part]))
		parts.add_child(b)
		_part_buttons[part] = b
	var arms := _chip(L.t("both_arms"))
	arms.pressed.connect(func(): _select_parts(["arm_l", "arm_r"]))
	parts.add_child(arms)
	_part_buttons["_arms"] = arms
	var legs := _chip(L.t("both_legs"))
	legs.pressed.connect(func(): _select_parts(["leg_l", "leg_r"]))
	parts.add_child(legs)
	_part_buttons["_legs"] = legs
	v.add_child(parts)

	v.add_child(UI.label(L.t("color"), 18, UI.MUTED, "bold"))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for hex in UI.SWATCHES:
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(48, 48)
		sw.focus_mode = Control.FOCUS_NONE
		sw.set_meta("hex", hex)
		_style_swatch(sw, Color(hex), false)
		sw.pressed.connect(func():
			Sfx.click()
			_paint(hex))
		grid.add_child(sw)
		_swatch_buttons.append(sw)
	v.add_child(grid)

	var custom_row := UI.hbox(12)
	custom_row.add_child(UI.label(L.t("custom_color"), 18, UI.TEXT, "bold"))
	_custom_picker = ColorPickerButton.new()
	_custom_picker.custom_minimum_size = Vector2(120, 48)
	_custom_picker.edit_alpha = false
	_custom_picker.color = Color(_colors.torso)
	_custom_picker.color_changed.connect(func(c: Color): _paint("#" + c.to_html(false)))
	_custom_picker.focus_mode = Control.FOCUS_NONE
	custom_row.add_child(_custom_picker)
	v.add_child(custom_row)
	_select_parts(["torso"])
	return v


func _chip(text: String) -> Button:
	var b := UI.button(text, "flat", 42)
	b.theme_type_variation = "ChipButton"
	b.toggle_mode = true
	b.add_theme_font_size_override("font_size", 16)
	return b


func _style_swatch(b: Button, c: Color, selected: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(24)
	sb.set_border_width_all(4 if selected else 2)
	sb.border_color = UI.TEXT if selected else Color(1, 1, 1, 0.12)
	for s in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		b.add_theme_stylebox_override(s, sb)


func _select_parts(parts: Array) -> void:
	_selected_parts = parts
	var key: String = parts[0] if parts.size() == 1 else ""
	if parts.size() == 6:
		key = "_all"
	elif parts == ["arm_l", "arm_r"]:
		key = "_arms"
	elif parts == ["leg_l", "leg_r"]:
		key = "_legs"
	for k in _part_buttons:
		_part_buttons[k].button_pressed = k == key
	_refresh_swatches()


func _refresh_swatches() -> void:
	var current := str(_colors.get(_selected_parts[0], "")).to_lower()
	for sw in _swatch_buttons:
		_style_swatch(sw, Color(sw.get_meta("hex")), str(sw.get_meta("hex")).to_lower() == current)
	if _custom_picker and current != "":
		_custom_picker.color = Color(current)


func _paint(hex: String) -> void:
	for part in _selected_parts:
		_colors[part] = hex
	_apply_preview()
	_refresh_swatches()


func _build_faces_tab() -> Control:
	var grid := GridContainer.new()
	grid.columns = 3 if UI.is_compact() else 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var mine := Economy.owned("face")
	for f in Faces.LIST:
		var id: String = f[0]
		if not mine.has(id) and id != _face:
			continue
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(84, 84)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.theme_type_variation = "ChipButton"
		# Face on a little skin-colored tile, like it sits on Melly's head.
		var tile := Panel.new()
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(str(_colors.get("head", "#f5f1ec")))
		sb.set_corner_radius_all(14)
		tile.add_theme_stylebox_override("panel", sb)
		tile.set_anchors_preset(Control.PRESET_FULL_RECT)
		tile.offset_left = 10
		tile.offset_top = 10
		tile.offset_right = -10
		tile.offset_bottom = -10
		b.add_child(tile)
		var img := TextureRect.new()
		img.texture = Faces.texture(id)
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.set_anchors_preset(Control.PRESET_FULL_RECT)
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(img)
		b.pressed.connect(func():
			Sfx.click()
			_face = id
			_apply_preview())
		grid.add_child(b)
		_face_buttons[id] = b
	var v := UI.vbox(12)
	v.add_child(grid)
	v.add_child(_shop_button())
	return v


## Accessories from the server's catalog, with a picture each. Tap to put on or
## take off; one per slot (a new hat replaces the old one).
func _build_hats_tab() -> Control:
	var v := UI.vbox(12)
	var head := UI.hbox(10)
	var hint := UI.label(L.t("acc_hint", [Accessories.max_worn]), 15, UI.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hint)
	var off := UI.button(L.t("acc_take_off"), "ghost", 40)
	off.add_theme_font_size_override("font_size", 15)
	off.pressed.connect(func():
		_worn = []
		_apply_preview())
	head.add_child(off)
	v.add_child(head)
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	var mine := Economy.owned("accessory")
	for it in Accessories.items():
		var id := str(it.id)
		if not mine.has(id) and not id in _worn:
			continue
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.theme_type_variation = "ChipButton"
		b.custom_minimum_size = Vector2(118, 146)
		var col := UI.vbox(2)
		col.set_anchors_preset(Control.PRESET_FULL_RECT)
		col.offset_left = 6
		col.offset_right = -6
		col.offset_top = 6
		col.offset_bottom = -6
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(col)
		var pic := TextureRect.new()
		pic.custom_minimum_size = Vector2(96, 96)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(pic)
		AccessoryThumbs.fetch(id, func(t: Texture2D):
			if is_instance_valid(pic):
				pic.texture = t)
		var name := UI.label(Accessories.name_of(id), 14, UI.TEXT, "bold")
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name.max_lines_visible = 2
		name.custom_minimum_size.x = 100
		name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(name)
		b.pressed.connect(func():
			Sfx.click()
			if id in _worn:
				_worn.erase(id)
			else:
				_worn = Accessories.wear(_worn, id)
			_apply_preview())
		grid.add_child(b)
		_acc_buttons[id] = b
	v.add_child(_shop_button())
	return v


## Things you don't have yet are in the shop.
func _shop_button() -> Button:
	var b := UI.button(L.t("shop_more"), "ghost", 48)
	var ic := Icon.make("shop", 22, UI.ACCENT)
	ic.position = Vector2(14, 13)
	b.add_child(ic)
	b.pressed.connect(func():
		var menu: Variant = get_meta("menu", null)
		if menu:
			menu.open_page("shop"))
	return b


func _build_profile_tab() -> Control:
	var v := UI.vbox(12)
	v.add_child(UI.label(L.t("nick_label"), 18, UI.MUTED, "bold"))
	_name_edit = UI.input(L.t("nick"))
	_name_edit.max_length = 24
	_name_edit.text = str(Session.user.get("display_name", ""))
	_name_edit.text_changed.connect(func(_t): _set_dirty(true))
	v.add_child(_name_edit)
	v.add_child(UI.label(L.t("about_me"), 18, UI.MUTED, "bold"))
	_bio_edit = TextEdit.new()
	_bio_edit.custom_minimum_size.y = 120
	_bio_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_bio_edit.placeholder_text = L.t("bio_hint")
	_bio_edit.text = str(Session.user.get("bio", ""))
	_bio_edit.text_changed.connect(func():
		if _bio_edit.text.length() > 160:
			_bio_edit.text = _bio_edit.text.substr(0, 160)
			_bio_edit.set_caret_column(160)
		_set_dirty(true))
	v.add_child(_bio_edit)
	var info := UI.label(L.t("login_is", [Session.user.get("username", "")]), 16, UI.MUTED)
	v.add_child(info)
	return v


func _apply_preview() -> void:
	_stage.avatar.set_colors(_colors)
	_stage.avatar.set_accessories(_worn)
	_stage.avatar.set_face(_face)
	for id in _face_buttons:
		_face_buttons[id].button_pressed = id == _face
	for id in _acc_buttons:
		_acc_buttons[id].button_pressed = id in _worn
	_refresh_swatches()
	_set_dirty(true)


func _set_dirty(v: bool) -> void:
	_dirty = v
	if _save:
		_save.disabled = not v
		_save.text = L.t("save") if v else L.t("saved")


func _randomize() -> void:
	for part in Session.BODY_PARTS:
		_colors[part] = UI.SWATCHES.pick_random()
	if randf() < 0.6:
		var skin: String = ["#f5f1ec", "#ffd9c2", "#e8b48f", "#b07852", "#6b4431"].pick_random()
		for part in ["head", "arm_l", "arm_r"]:
			_colors[part] = skin
	# Only things you own, so "random" never asks you to pay.
	var mine := Economy.owned("accessory")
	_worn = Accessories.random_look().filter(func(id): return mine.has(id))
	_face = Economy.owned("face").pick_random()
	_apply_preview()
	_stage.avatar.play("wave")


func _on_save() -> void:
	var name := _name_edit.text.strip_edges()
	if name.length() < 2:
		UI.toast(L.t("nick_short"), "error")
		_show_tab("profile")
		return
	_save.disabled = true
	_save.text = L.t("saving")
	var r := await Api.request("PATCH", "/api/me", {
		"colors": _colors,
		"accessories": _worn,
		"face": _face,
		"display_name": name,
		"bio": _bio_edit.text.strip_edges(),
	})
	if not is_inside_tree():
		return
	if not r.ok:
		UI.toast(r.message, "error")
		_set_dirty(true)
		return
	Session.set_user(r.data.user)
	Sfx.play("coin")
	UI.toast(L.t("look_saved"), "ok")
	Busts.sync_my_render()
	_stage.avatar.play("wave")
	_set_dirty(false)
