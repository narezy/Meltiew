class_name GameHud
extends CanvasLayer
## In-game overlay: touch controls, chat, health, server info, emote wheel, overlays.

signal menu_requested
signal chat_submitted(text: String)
signal emote_picked(emote: String)

var player: LocalPlayer
var joystick: Joystick
var jump_btn: TouchButton
var emote_btn: TouchButton
var wheel: EmoteWheel

var _root: Control
var _server_label: Label
var _count_label: Label
var _hp_fill: Panel
var _hp_label: Label
var _hp_shown := 100.0
var _chat_log: VBoxContainer
var _chat_input_row: HBoxContainer
var _chat_input: LineEdit
var _stats_label: Label
var _toast_big: Label
var _overlay: Control
var _overlay_text: Label
var _overlay_buttons: HBoxContainer
var _blockers: Array[Control] = []
var _cam_finger := -1
var _pinch := {}
var _mouse_look := false
var _cam_btn: Button


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.theme = UI.theme
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	joystick = Joystick.new()
	_root.add_child(joystick)

	# Top-left: menu, server info, health, chat log.
	var tl := UI.vbox(8)
	tl.position = Vector2(20, 16)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(tl)
	var info_row := UI.hbox(10)
	info_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.add_child(info_row)
	var menu := _icon_button("menu")
	menu.pressed.connect(func(): menu_requested.emit())
	info_row.add_child(menu)
	var info := _pill()
	var info_v := UI.vbox(2)
	info.add_child(info_v)
	_server_label = UI.label(L.t("connecting"), 16, UI.TEXT, "bold")
	info_v.add_child(_server_label)
	var hp_row := UI.hbox(8)
	var hp_bg := Panel.new()
	hp_bg.custom_minimum_size = Vector2(150, 10)
	hp_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var hb := StyleBoxFlat.new()
	hb.bg_color = Color(0, 0, 0, 0.45)
	hb.set_corner_radius_all(5)
	hp_bg.add_theme_stylebox_override("panel", hb)
	_hp_fill = Panel.new()
	_hp_fill.size = Vector2(150, 10)
	var hf := StyleBoxFlat.new()
	hf.bg_color = UI.ONLINE
	hf.set_corner_radius_all(5)
	_hp_fill.add_theme_stylebox_override("panel", hf)
	hp_bg.add_child(_hp_fill)
	hp_row.add_child(hp_bg)
	_hp_label = UI.label("100", 13, UI.MUTED, "bold")
	hp_row.add_child(_hp_label)
	_count_label = UI.label("", 13, UI.MUTED)
	hp_row.add_child(_count_label)
	info_v.add_child(hp_row)
	info_row.add_child(info)
	_blockers.append(info_row)

	_chat_log = UI.vbox(3)
	_chat_log.custom_minimum_size.x = 430
	_chat_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.add_child(_chat_log)

	_chat_input_row = UI.hbox(8)
	_chat_input_row.visible = false
	tl.add_child(_chat_input_row)
	_chat_input = UI.input(L.t("chat_placeholder"))
	_chat_input.custom_minimum_size = Vector2(360, 50)
	_chat_input.max_length = 200
	_chat_input.text_submitted.connect(func(_t): _send_chat())
	_chat_input_row.add_child(_chat_input)
	var send := _icon_button("send")
	send.pressed.connect(_send_chat)
	_chat_input_row.add_child(send)
	_blockers.append(_chat_input_row)

	# Top-right: camera mode + chat.
	var tr := UI.hbox(10)
	tr.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr.offset_left = -200
	tr.offset_right = -20
	tr.offset_top = 16
	tr.alignment = BoxContainer.ALIGNMENT_END
	_root.add_child(tr)
	_cam_btn = _icon_button("camera")
	_cam_btn.pressed.connect(func():
		if player:
			player.toggle_first_person())
	tr.add_child(_cam_btn)
	var chat_btn := _icon_button("chat")
	chat_btn.pressed.connect(toggle_chat)
	tr.add_child(chat_btn)
	_blockers.append(tr)

	# FPS/ping readout, top center where no control ever covers it.
	_stats_label = UI.label("", 15, UI.TEXT, "bold")
	_stats_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_stats_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_stats_label.offset_top = 12
	_stats_label.offset_bottom = 36
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_stats_label.add_theme_constant_override("outline_size", 6)
	_stats_label.visible = bool(Session.settings.show_fps)
	_root.add_child(_stats_label)

	_toast_big = UI.label("", 34, UI.TEXT, "black")
	_toast_big.set_anchors_preset(Control.PRESET_CENTER)
	_toast_big.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_big.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_toast_big.add_theme_constant_override("outline_size", 12)
	_toast_big.offset_top = -120
	_toast_big.modulate.a = 0.0
	_root.add_child(_toast_big)

	# Bottom-right: jump + emotes.
	jump_btn = TouchButton.make("jump", 120)
	emote_btn = TouchButton.make("smile", 78)
	for b in [jump_btn, emote_btn]:
		b.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		_root.add_child(b)
	_place(jump_btn, Vector2(-165, -175))
	_place(emote_btn, Vector2(-265, -110))
	jump_btn.pressed_down.connect(func():
		if player:
			player.request_jump())
	emote_btn.pressed_down.connect(func():
		release_touches()
		wheel.open())
	if not DisplayServer.is_touchscreen_available():
		jump_btn.visible = false
		var hint := UI.label(L.t("desktop_hint"), 14, Color(1, 1, 1, 0.75))
		hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
		hint.offset_top = -30
		hint.offset_bottom = -10
		hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
		hint.add_theme_constant_override("outline_size", 6)
		_root.add_child(hint)

	wheel = EmoteWheel.new()
	wheel.theme = UI.theme
	add_child(wheel)
	wheel.picked.connect(func(e): emote_picked.emit(e))

	_overlay = ColorRect.new()
	_overlay.theme = UI.theme
	(_overlay as ColorRect).color = Color(UI.BG, 0.9)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	add_child(_overlay)
	var oc := CenterContainer.new()
	oc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(oc)
	var ov := UI.vbox(18)
	ov.alignment = BoxContainer.ALIGNMENT_CENTER
	oc.add_child(ov)
	var mark := TextureRect.new()
	mark.texture = load("res://assets/logo_mark.png")
	mark.custom_minimum_size = Vector2(90, 90)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ov.add_child(mark)
	_overlay_text = UI.label("", 24, UI.TEXT, "bold")
	_overlay_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay_text.custom_minimum_size.x = 520
	ov.add_child(_overlay_text)
	_overlay_buttons = UI.hbox(12)
	_overlay_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	ov.add_child(_overlay_buttons)


func bind_player(p: LocalPlayer) -> void:
	player = p
	p.health_changed.connect(set_health)
	p.camera_mode_changed.connect(func(fp): _cam_btn.modulate = UI.ACCENT if fp else Color.WHITE)


func _place(c: Control, offset: Vector2) -> void:
	c.offset_left = offset.x
	c.offset_top = offset.y
	c.offset_right = offset.x + c.custom_minimum_size.x
	c.offset_bottom = offset.y + c.custom_minimum_size.y


func _pill() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UI.BG_2, 0.8)
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	p.add_theme_stylebox_override("panel", sb)
	return p


func _icon_button(kind: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(56, 56)
	b.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UI.BG_2, 0.8)
	sb.set_corner_radius_all(16)
	var sb2 := sb.duplicate()
	sb2.bg_color = Color(UI.ACCENT_DARK, 0.9)
	for s in ["normal", "hover", "focus"]:
		b.add_theme_stylebox_override(s, sb)
	b.add_theme_stylebox_override("pressed", sb2)
	b.add_theme_stylebox_override("hover_pressed", sb2)
	var ic := Icon.make(kind, 26)
	ic.position = Vector2(15, 15)
	b.add_child(ic)
	b.pressed.connect(func(): Sfx.click())
	return b


# --- public API -------------------------------------------------------------

func set_server(name: String, players: int, max_players: int) -> void:
	_server_label.text = name
	_count_label.text = "· %d/%d" % [players, max_players]


func set_health(hp: float) -> void:
	var t := create_tween()
	t.tween_method(func(v: float):
		_hp_fill.size.x = 150.0 * clampf(v / 100.0, 0.0, 1.0)
		var sb := _hp_fill.get_theme_stylebox("panel") as StyleBoxFlat
		sb.bg_color = UI.ONLINE if v > 50.0 else (Color("#ffd166") if v > 25.0 else UI.DANGER), _hp_shown, hp, 0.2)
	_hp_shown = hp
	_hp_label.text = str(int(ceil(hp)))


func big_message(text: String, seconds := 2.5) -> void:
	_toast_big.text = text
	var t := _toast_big.create_tween()
	t.tween_property(_toast_big, "modulate:a", 1.0, 0.2)
	t.tween_interval(seconds)
	t.tween_property(_toast_big, "modulate:a", 0.0, 0.4)


func add_chat(author: String, text: String, color := UI.TEXT) -> void:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.custom_minimum_size.x = 430
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", 6)
	var safe := text.replace("[", "[lb]")
	if author != "":
		l.text = "[b][color=#%s]%s:[/color][/b] %s" % [color.to_html(false), author.replace("[", "[lb]"), safe]
	else:
		l.text = "[color=#%s][i]%s[/i][/color]" % [UI.MUTED.lightened(0.25).to_html(false), safe]
	_chat_log.add_child(l)
	while _chat_log.get_child_count() > 7:
		var old := _chat_log.get_child(0)
		_chat_log.remove_child(old)
		old.queue_free()
	var t := l.create_tween()
	t.tween_interval(14.0)
	t.tween_property(l, "modulate:a", 0.0, 1.5)


func toggle_chat() -> void:
	_chat_input_row.visible = not _chat_input_row.visible
	if _chat_input_row.visible:
		_chat_input.grab_focus()
		for c in _chat_log.get_children():
			c.modulate.a = 1.0
	else:
		_chat_input.release_focus()


func chat_open() -> bool:
	return _chat_input_row.visible and _chat_input.has_focus()


func _send_chat() -> void:
	var text := _chat_input.text.strip_edges()
	_chat_input.text = ""
	if text != "":
		chat_submitted.emit(text)
	if DisplayServer.is_touchscreen_available():
		toggle_chat()


func set_stats(fps: int, ping: int) -> void:
	_stats_label.visible = bool(Session.settings.show_fps)
	_stats_label.text = L.t("stats", [fps, ("%d ms" % ping) if ping >= 0 else "—"])


func show_overlay(text: String, buttons: Array = []) -> void:
	_overlay.visible = true
	_overlay_text.text = text
	for c in _overlay_buttons.get_children():
		c.queue_free()
	for b in buttons:
		var btn := UI.button(b[0], b[2] if b.size() > 2 else "primary", 56)
		btn.custom_minimum_size.x = 220
		btn.pressed.connect(b[1])
		_overlay_buttons.add_child(btn)


func hide_overlay() -> void:
	_overlay.visible = false


func release_touches() -> void:
	for b in [jump_btn, emote_btn]:
		b.force_release()
	joystick.reset()
	_pinch.clear()
	_cam_finger = -1
	_mouse_look = false


# --- input routing ----------------------------------------------------------

func _blocked(pos: Vector2) -> bool:
	for b in _blockers:
		if b.is_visible_in_tree() and b.get_global_rect().has_point(pos):
			return true
	return false


func _input(event: InputEvent) -> void:
	if player == null:
		return
	# Finger releases must always reach the buttons and joystick, even while the
	# emote wheel or an overlay is open, or they'd stay "held" forever.
	if event is InputEventScreenTouch and not event.pressed:
		_touch(event)
		return
	if _overlay.visible or wheel.visible:
		return
	if event is InputEventScreenTouch:
		_touch(event)
	elif event is InputEventScreenDrag:
		_drag(event)
	elif not DisplayServer.is_touchscreen_available():
		_desktop(event)


func _touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		for b in [jump_btn, emote_btn]:
			if b.touch_press(e.index, e.position):
				return
		if _blocked(e.position):
			return
		var w := get_viewport().get_visible_rect().size.x
		if e.position.x < w * 0.42 and not joystick.active():
			joystick.begin(e.index, e.position)
		else:
			_pinch[e.index] = e.position
			if _cam_finger < 0:
				_cam_finger = e.index
	else:
		for b in [jump_btn, emote_btn]:
			b.touch_release(e.index)
		joystick.end(e.index)
		_pinch.erase(e.index)
		if e.index == _cam_finger:
			_cam_finger = _pinch.keys()[0] if _pinch.size() > 0 else -1


func _drag(e: InputEventScreenDrag) -> void:
	if joystick.owns_finger(e.index):
		joystick.drag(e.index, e.position)
		return
	if not _pinch.has(e.index):
		return
	if _pinch.size() >= 2:
		var keys := _pinch.keys()
		var before: float = (_pinch[keys[0]] as Vector2).distance_to(_pinch[keys[1]])
		_pinch[e.index] = e.position
		var after: float = (_pinch[keys[0]] as Vector2).distance_to(_pinch[keys[1]])
		player.zoom_camera((before - after) * 0.03)
		return
	_pinch[e.index] = e.position
	if e.index == _cam_finger:
		player.rotate_camera(e.relative)


func _desktop(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_mouse_look = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			player.zoom_camera(-0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			player.zoom_camera(0.9)
	elif event is InputEventMouseMotion and (_mouse_look or player.first_person):
		if _mouse_look or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			player.rotate_camera(event.relative)
	elif event is InputEventKey and event.pressed and not event.echo:
		if chat_open():
			if event.keycode == KEY_ESCAPE:
				toggle_chat()
			return
		match event.keycode:
			KEY_ENTER, KEY_KP_ENTER, KEY_T, KEY_SLASH:
				toggle_chat()
				get_viewport().set_input_as_handled()
			KEY_B, KEY_G:
				release_touches()
				wheel.open()
			KEY_V:
				player.toggle_first_person()
			KEY_R:
				player.die()
			KEY_SPACE:
				player.request_jump()
			KEY_ESCAPE, KEY_M:
				menu_requested.emit()


func _process(_delta: float) -> void:
	if player:
		player.move_input = joystick.value
		player.keyboard_blocked = chat_open()
		player.sprint = Input.is_key_pressed(KEY_SHIFT) and not player.keyboard_blocked
