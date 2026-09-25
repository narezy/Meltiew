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
const HP_W := 200.0
const CHAT_W := 430.0
## Messages shown while the chat is closed, and how many are kept to scroll back through.
const CHAT_PEEK := 3
const CHAT_HISTORY := 100

var _hp_fill: Panel
var _hp_label: Label
var _hp_shown := 100.0
var _chat_log: VBoxContainer
var _chat_panel: PanelContainer
var _chat_scroll: ScrollContainer
var _chat_full: VBoxContainer
var _chat_expanded := false
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
	_blockers.append(info_row)

	# Bottom-center: health bar, no backdrop.
	var hp_row := UI.hbox(8)
	hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hp_row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hp_row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hp_row.offset_bottom = -18
	hp_row.add_child(Icon.make("heart", 20, UI.PINK))
	var hp_bg := Panel.new()
	hp_bg.custom_minimum_size = Vector2(HP_W, 12)
	hp_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb := StyleBoxFlat.new()
	hb.bg_color = Color(0, 0, 0, 0.35)
	hb.set_corner_radius_all(6)
	hp_bg.add_theme_stylebox_override("panel", hb)
	_hp_fill = Panel.new()
	_hp_fill.size = Vector2(HP_W, 12)
	_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hf := StyleBoxFlat.new()
	hf.bg_color = UI.ONLINE
	hf.set_corner_radius_all(6)
	_hp_fill.add_theme_stylebox_override("panel", hf)
	hp_bg.add_child(_hp_fill)
	hp_row.add_child(hp_bg)
	_hp_label = UI.label("100", 15, Color.WHITE, "black")
	_hp_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	_hp_label.add_theme_constant_override("outline_size", 6)
	hp_row.add_child(_hp_label)
	_root.add_child(hp_row)

	# Closed chat: the last few messages float over the game and fade out.
	_chat_log = UI.vbox(3)
	_chat_log.custom_minimum_size.x = CHAT_W
	_chat_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.add_child(_chat_log)

	# Open chat: the whole history on a dark backdrop you can scroll, plus the input.
	_chat_panel = PanelContainer.new()
	var cp := StyleBoxFlat.new()
	cp.bg_color = Color(0, 0, 0, 0.45)
	cp.set_corner_radius_all(18)
	cp.content_margin_left = 12
	cp.content_margin_right = 12
	cp.content_margin_top = 10
	cp.content_margin_bottom = 10
	_chat_panel.add_theme_stylebox_override("panel", cp)
	_chat_panel.visible = false
	tl.add_child(_chat_panel)
	var cv := UI.vbox(8)
	_chat_panel.add_child(cv)
	_chat_scroll = ScrollContainer.new()
	_chat_scroll.custom_minimum_size = Vector2(CHAT_W, 230)
	_chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cv.add_child(_chat_scroll)
	_chat_full = UI.vbox(3)
	_chat_full.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_scroll.add_child(_chat_full)
	_blockers.append(_chat_panel)

	_chat_input_row = UI.hbox(8)
	cv.add_child(_chat_input_row)
	_chat_input = UI.input(L.t("chat_placeholder"))
	_chat_input.custom_minimum_size = Vector2(CHAT_W - 64, 50)
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
	_chat_btn = chat_btn
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

func set_server(_name: String, _players: int, _max_players: int) -> void:
	# The server name lives in the in-game menu now; the HUD stays clean.
	pass


var chat_enabled := true
var _chat_btn: Button


## Under-13 accounts have no chat: hide the log, the input and the button.
func set_chat_enabled(on: bool) -> void:
	chat_enabled = on
	_chat_log.visible = on and not _chat_expanded
	_chat_btn.visible = on
	if not on:
		_set_chat_expanded(false)


## Studio places can raise MaxHealth above 100.
var max_health := 100.0


func set_health(hp: float) -> void:
	if player:
		max_health = player.max_hp
	var t := create_tween()
	t.tween_method(func(v: float):
		var frac := clampf(v / maxf(max_health, 1.0), 0.0, 1.0)
		_hp_fill.size.x = HP_W * frac
		var sb := _hp_fill.get_theme_stylebox("panel") as StyleBoxFlat
		sb.bg_color = UI.ONLINE if frac > 0.5 else (Color("#ffd166") if frac > 0.25 else UI.DANGER), _hp_shown, hp, 0.2)
	_hp_shown = hp
	_hp_label.text = str(int(ceil(hp)))


func big_message(text: String, seconds := 2.5) -> void:
	_toast_big.text = text
	var t := _toast_big.create_tween()
	t.tween_property(_toast_big, "modulate:a", 1.0, 0.2)
	t.tween_interval(seconds)
	t.tween_property(_toast_big, "modulate:a", 0.0, 0.4)


func add_chat(author: String, text: String, color := UI.TEXT) -> void:
	var safe := text.replace("[", "[lb]")
	var bb := ""
	if author != "":
		bb = "[b][color=#%s]%s:[/color][/b] %s" % [color.to_html(false), author.replace("[", "[lb]"), safe]
	else:
		bb = "[color=#%s][i]%s[/i][/color]" % [UI.MUTED.lightened(0.25).to_html(false), safe]

	# Closed view: keep only the last few, fading after a while.
	var peek := _chat_line(bb)
	_chat_log.add_child(peek)
	while _chat_log.get_child_count() > CHAT_PEEK:
		var old := _chat_log.get_child(0)
		_chat_log.remove_child(old)
		old.queue_free()
	var t := peek.create_tween()
	t.tween_interval(14.0)
	t.tween_property(peek, "modulate:a", 0.0, 1.5)

	# Open view: full history; stays at the bottom unless you scrolled up to read.
	var bar := _chat_scroll.get_v_scroll_bar()
	var at_bottom := _chat_scroll.scroll_vertical >= bar.max_value - bar.page - 8.0
	_chat_full.add_child(_chat_line(bb))
	while _chat_full.get_child_count() > CHAT_HISTORY:
		var old := _chat_full.get_child(0)
		_chat_full.remove_child(old)
		old.queue_free()
	if at_bottom:
		_scroll_chat_down()


func _chat_line(bb: String) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	# PASS lets a finger drag through a line to scroll the open chat.
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.custom_minimum_size.x = CHAT_W - 24
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", 6)
	l.text = bb
	return l


func _scroll_chat_down() -> void:
	await get_tree().process_frame
	_chat_scroll.scroll_vertical = int(_chat_scroll.get_v_scroll_bar().max_value)


func _set_chat_expanded(on: bool) -> void:
	_chat_expanded = on
	_chat_panel.visible = on
	_chat_log.visible = chat_enabled and not on
	if on:
		_scroll_chat_down()
		_chat_input.grab_focus()
	else:
		_chat_input.release_focus()
		# Reopening the closed view shouldn't bring back long-faded messages.
		for c in _chat_log.get_children():
			c.modulate.a = 0.0


func toggle_chat() -> void:
	if not chat_enabled:
		return
	_set_chat_expanded(not _chat_expanded)


func chat_open() -> bool:
	return _chat_expanded and _chat_input.has_focus()


func _send_chat() -> void:
	var text := _chat_input.text.strip_edges()
	_chat_input.text = ""
	if text != "":
		chat_submitted.emit(text)
	# Phones: hide the keyboard but keep the chat open to read replies.
	if DisplayServer.is_touchscreen_available():
		_chat_input.release_focus()


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
				# Open chat that lost focus: jump back into typing instead of closing it.
				if _chat_expanded:
					_chat_input.grab_focus()
				else:
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
