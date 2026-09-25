class_name GameHud
extends CanvasLayer
## In-game overlay: touch controls, chat, player list, server info, overlays.

signal leave_requested
signal chat_submitted(text: String)
signal wave_pressed
signal heart_pressed
signal player_tapped(user: Dictionary)

var player: LocalPlayer
var joystick: Joystick
var jump_btn: TouchButton
var wave_btn: TouchButton
var heart_btn: TouchButton

var _root: Control
var _server_label: Label
var _count_label: Label
var _chat_log: VBoxContainer
var _chat_input_row: HBoxContainer
var _chat_input: LineEdit
var _players_panel: PanelContainer
var _players_list: VBoxContainer
var _stats_label: Label
var _overlay: Control
var _overlay_text: Label
var _overlay_buttons: HBoxContainer
var _blockers: Array[Control] = []
var _cam_finger := -1
var _pinch := {}
var _mouse_look := false


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	joystick = Joystick.new()
	_root.add_child(joystick)

	# Top-left: leave + server info + chat log.
	var tl := UI.vbox(10)
	tl.position = Vector2(20, 16)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(tl)
	var info_row := UI.hbox(10)
	info_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.add_child(info_row)
	var leave := _icon_button("exit")
	leave.pressed.connect(func(): leave_requested.emit())
	info_row.add_child(leave)
	var info := _pill()
	var info_v := UI.vbox(0)
	info.add_child(info_v)
	_server_label = UI.label("Подключаемся...", 17, UI.TEXT, "bold")
	info_v.add_child(_server_label)
	_count_label = UI.label("", 14, UI.MUTED)
	info_v.add_child(_count_label)
	info_row.add_child(info)
	_blockers.append(info_row)

	_chat_log = UI.vbox(4)
	_chat_log.custom_minimum_size.x = 420
	_chat_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.add_child(_chat_log)

	_chat_input_row = UI.hbox(8)
	_chat_input_row.visible = false
	tl.add_child(_chat_input_row)
	_chat_input = UI.input("Написать в чат...")
	_chat_input.custom_minimum_size = Vector2(360, 50)
	_chat_input.max_length = 200
	_chat_input.text_submitted.connect(func(_t): _send_chat())
	_chat_input_row.add_child(_chat_input)
	var send := _icon_button("send")
	send.pressed.connect(_send_chat)
	_chat_input_row.add_child(send)
	_blockers.append(_chat_input_row)

	# Top-right: chat toggle + players.
	var tr := UI.hbox(10)
	tr.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tr.position = Vector2(-20, 16)
	tr.offset_left = -300
	tr.offset_right = -20
	tr.alignment = BoxContainer.ALIGNMENT_END
	_root.add_child(tr)
	var chat_btn := _icon_button("chat")
	chat_btn.pressed.connect(toggle_chat)
	tr.add_child(chat_btn)
	var players_btn := _icon_button("users")
	players_btn.pressed.connect(func(): _players_panel.visible = not _players_panel.visible)
	tr.add_child(players_btn)
	_blockers.append(tr)

	_players_panel = UI.card(16, Color(UI.BG_2, 0.92), 20)
	_players_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_players_panel.offset_left = -340
	_players_panel.offset_right = -20
	_players_panel.offset_top = 84
	_players_panel.visible = false
	_root.add_child(_players_panel)
	var pv := UI.vbox(10)
	_players_panel.add_child(pv)
	pv.add_child(UI.label("Игроки на сервере", 20, UI.TEXT, "black"))
	_players_list = UI.vbox(8)
	pv.add_child(_players_list)
	_blockers.append(_players_panel)

	_stats_label = UI.label("", 14, UI.MUTED)
	_stats_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_stats_label.position = Vector2(20, -30)
	_stats_label.offset_top = -30
	_stats_label.offset_left = 20
	_root.add_child(_stats_label)

	# Bottom-right: action buttons.
	jump_btn = TouchButton.make("jump", 118)
	wave_btn = TouchButton.make("hand", 76)
	heart_btn = TouchButton.make("heart", 76)
	for b in [jump_btn, wave_btn, heart_btn]:
		b.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		_root.add_child(b)
	_place(jump_btn, Vector2(-160, -170))
	_place(wave_btn, Vector2(-270, -110))
	_place(heart_btn, Vector2(-128, -270))
	jump_btn.pressed_down.connect(func():
		if player:
			player.request_jump())
	wave_btn.pressed_down.connect(func(): wave_pressed.emit())
	heart_btn.pressed_down.connect(func(): heart_pressed.emit())
	if not DisplayServer.is_touchscreen_available():
		# Keyboard players get hints instead of thumb buttons.
		jump_btn.visible = false
		var hint := UI.label("WASD — ходить, Space — прыжок, ПКМ — камера, колесо — зум, Enter — чат, 1 — помахать, 2 — сердечко", 15, Color(1, 1, 1, 0.7))
		hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
		hint.offset_top = -34
		hint.offset_bottom = -12
		hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
		hint.add_theme_constant_override("outline_size", 6)
		_root.add_child(hint)

	_overlay = ColorRect.new()
	(_overlay as ColorRect).color = Color(UI.BG, 0.88)
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


func _place(c: Control, offset: Vector2) -> void:
	c.offset_left = offset.x
	c.offset_top = offset.y
	c.offset_right = offset.x + c.custom_minimum_size.x
	c.offset_bottom = offset.y + c.custom_minimum_size.y


func _pill() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UI.BG_2, 0.78)
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", sb)
	return p


func _icon_button(kind: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(54, 54)
	b.focus_mode = Control.FOCUS_NONE
	b.theme_type_variation = "GhostButton"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UI.BG_2, 0.78)
	sb.set_corner_radius_all(16)
	var sb2 := sb.duplicate()
	sb2.bg_color = Color(UI.ACCENT_DARK, 0.9)
	for s in ["normal", "hover", "focus"]:
		b.add_theme_stylebox_override(s, sb)
	b.add_theme_stylebox_override("pressed", sb2)
	b.add_theme_stylebox_override("hover_pressed", sb2)
	var ic := Icon.make(kind, 24)
	ic.position = Vector2(15, 15)
	b.add_child(ic)
	b.pressed.connect(func(): Sfx.click())
	return b


# --- public API -------------------------------------------------------------

func set_server(name: String, players: int, max_players: int) -> void:
	_server_label.text = name
	_count_label.text = "%d / %d игроков" % [players, max_players]


func set_players(users: Array) -> void:
	for c in _players_list.get_children():
		c.queue_free()
	for u in users:
		var row := UI.hbox(10)
		row.add_child(UI.avatar_badge(u, 38))
		var name := UI.label(str(u.display_name), 18, UI.TEXT, "bold")
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.clip_text = true
		row.add_child(name)
		if int(u.id) == int(Session.user.get("id", -1)):
			row.add_child(UI.label("это ты", 14, UI.ACCENT))
		else:
			var user: Dictionary = u
			UI.on_tap(row, func(): player_tapped.emit(user))
		_players_list.add_child(row)


func add_chat(author: String, text: String, color := UI.TEXT) -> void:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.custom_minimum_size.x = 420
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", 6)
	var safe := text.replace("[", "[lb]")
	if author != "":
		l.text = "[b][color=#%s]%s:[/color][/b] %s" % [color.to_html(false), author.replace("[", "[lb]"), safe]
	else:
		l.text = "[color=#%s][i]%s[/i][/color]" % [UI.MUTED.lightened(0.2).to_html(false), safe]
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
	_stats_label.text = "%d FPS · пинг %s" % [fps, ("%d мс" % ping) if ping >= 0 else "—"]


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


# --- input routing ----------------------------------------------------------

func _blocked(pos: Vector2) -> bool:
	for b in _blockers:
		if b.is_visible_in_tree() and b.get_global_rect().has_point(pos):
			return true
	return false


func _input(event: InputEvent) -> void:
	if player == null or _overlay.visible:
		return
	if event is InputEventScreenTouch:
		_touch(event)
	elif event is InputEventScreenDrag:
		_drag(event)
	elif not DisplayServer.is_touchscreen_available():
		_desktop(event)


func _touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		for b in [jump_btn, wave_btn, heart_btn]:
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
		for b in [jump_btn, wave_btn, heart_btn]:
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
			player.zoom_camera(-0.8)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			player.zoom_camera(0.8)
	elif event is InputEventMouseMotion and _mouse_look:
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
			KEY_1:
				wave_pressed.emit()
			KEY_2:
				heart_pressed.emit()
			KEY_SPACE:
				player.request_jump()
			KEY_ESCAPE:
				leave_requested.emit()


func _process(_delta: float) -> void:
	if player:
		player.move_input = joystick.value
		player.keyboard_blocked = chat_open()
		player.run = Input.is_key_pressed(KEY_SHIFT) and not player.keyboard_blocked
