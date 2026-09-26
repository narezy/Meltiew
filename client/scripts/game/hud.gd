class_name GameHud
extends CanvasLayer
## In-game overlay: touch controls, chat, health, server info, emote wheel, overlays.

signal menu_requested
signal chat_submitted(text: String)
signal emote_picked(emote: String)
## A tool picked in the hotbar or inventory (the one in hand again = put it away).
signal tool_picked(id: String)

var player: LocalPlayer
var joystick: Joystick
var jump_btn: TouchButton
var emote_btn: TouchButton
var sprint_btn: TouchButton
var _stamina_bg: Panel
var _stamina_fill: Panel
var wheel: EmoteWheel

var _root: Control
const HP_W := 200.0
const CHAT_W := 360.0
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
var _hp_row: HBoxContainer

# Tools: 3 hotbar slots at the bottom and the whole inventory on demand.
const HOTBAR_SLOTS := 3
const SLOT := 62.0
var _hotbar: HBoxContainer
var _slots: Array[Button] = []
var _bag_btn: Button
var _inventory: PanelContainer
var _inv_grid: HFlowContainer
var _tools: Array = []  # [{id, name, icon, tip}] in pickup order
var _bar: Array = []  # tool ids shown in the hotbar slots
var _used := {}  # tool id -> last time it was picked (the oldest makes room)
var _seen: Array = []  # tool ids in the order they first showed up
var _equipped := ""
var _core := {"Backpack": true, "Health": true, "Chat": true, "Emotes": true}
var _crosshair: TextureRect


func _ready() -> void:
	_make_badges()
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
	_hp_row = hp_row
	# Stamina: a thin bar right under health, lined up with it.
	_stamina_bg = Panel.new()
	_stamina_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stamina_bg.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_stamina_bg.custom_minimum_size = Vector2(HP_W, 6)
	var stb := StyleBoxFlat.new()
	stb.bg_color = Color(0, 0, 0, 0.35)
	stb.set_corner_radius_all(3)
	_stamina_bg.add_theme_stylebox_override("panel", stb)
	_stamina_fill = Panel.new()
	_stamina_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stamina_fill.size = Vector2(HP_W, 6)
	var stf := StyleBoxFlat.new()
	stf.bg_color = Color("#6ec8ff")
	stf.set_corner_radius_all(3)
	_stamina_fill.add_theme_stylebox_override("panel", stf)
	_stamina_bg.add_child(_stamina_fill)
	_root.add_child(_stamina_bg)
	_build_tools()

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
	_chat_scroll.custom_minimum_size = Vector2(CHAT_W, 170)
	_chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cv.add_child(_chat_scroll)
	_chat_full = UI.vbox(3)
	_chat_full.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_scroll.add_child(_chat_full)
	_blockers.append(_chat_panel)

	_chat_input_row = UI.hbox(8)
	cv.add_child(_chat_input_row)
	_chat_input = UI.input(L.t("chat_placeholder"))
	_chat_input.custom_minimum_size = Vector2(CHAT_W - 60, 44)
	_chat_input.max_length = 200
	_chat_input.text_submitted.connect(func(_t): _send_chat())
	_chat_input_row.add_child(_chat_input)
	var send := _icon_button("send")
	send.custom_minimum_size = Vector2(44, 44)
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
	sprint_btn = TouchButton.make("run", 78)
	for b in [jump_btn, emote_btn, sprint_btn]:
		b.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		_root.add_child(b)
	_place(jump_btn, Vector2(-165, -175))
	_place(emote_btn, Vector2(-265, -110))
	_place(sprint_btn, Vector2(-144, -272))
	# Tap to run, tap again to walk (holding a button while steering is awkward on a phone).
	sprint_btn.pressed_down.connect(func():
		if player:
			player.sprint_toggle = not player.sprint_toggle
			sprint_btn.latched = player.sprint_toggle)
	jump_btn.pressed_down.connect(func():
		if player:
			player.request_jump())
	emote_btn.pressed_down.connect(func():
		release_touches()
		wheel.open())
	if not DisplayServer.is_touchscreen_available():
		jump_btn.visible = false
		sprint_btn.visible = false

	wheel = EmoteWheel.new()
	wheel.theme = UI.theme
	add_child(wheel)
	wheel.picked.connect(func(e): emote_picked.emit(e))

	_crosshair = TextureRect.new()
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_crosshair.visible = false
	_root.add_child(_crosshair)

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


## The first/third person button only shows where the place lets you switch.
func set_view_toggle(on: bool) -> void:
	_cam_btn.visible = on


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


# --- tools ------------------------------------------------------------------

func _build_tools() -> void:
	_hotbar = UI.hbox(8)
	_hotbar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hotbar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hotbar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hotbar.offset_bottom = -46
	_hotbar.alignment = BoxContainer.ALIGNMENT_CENTER
	_hotbar.visible = false
	_root.add_child(_hotbar)
	_blockers.append(_hotbar)
	for i in HOTBAR_SLOTS:
		var b := _slot_button(i + 1)
		b.pressed.connect(func(): _pick_slot(i))
		_hotbar.add_child(b)
		_slots.append(b)
	_bag_btn = _icon_button("backpack")
	_bag_btn.custom_minimum_size = Vector2(48, 48)
	(_bag_btn.get_child(0) as Control).position = Vector2(11, 11)
	_bag_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bag_btn.pressed.connect(toggle_inventory)
	_hotbar.add_child(_bag_btn)

	_inventory = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UI.BG, 0.92)
	sb.set_corner_radius_all(22)
	sb.set_content_margin_all(16)
	_inventory.add_theme_stylebox_override("panel", sb)
	_inventory.set_anchors_preset(Control.PRESET_CENTER)
	_inventory.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_inventory.grow_vertical = Control.GROW_DIRECTION_BOTH
	_inventory.visible = false
	_root.add_child(_inventory)
	_blockers.append(_inventory)
	var v := UI.vbox(12)
	_inventory.add_child(v)
	var head := UI.hbox(8)
	v.add_child(head)
	var title := UI.label(L.t("inventory"), 22, UI.TEXT, "black")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := _icon_button("close")
	close.custom_minimum_size = Vector2(44, 44)
	(close.get_child(0) as Control).position = Vector2(9, 9)
	close.pressed.connect(toggle_inventory)
	head.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(4 * (SLOT + 10), 2 * (SLOT + 10) + 20)
	v.add_child(scroll)
	_inv_grid = HFlowContainer.new()
	_inv_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inv_grid.add_theme_constant_override("h_separation", 10)
	_inv_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_inv_grid)


func _slot_button(number: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(SLOT, SLOT)
	b.focus_mode = Control.FOCUS_NONE
	b.clip_contents = true
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 8
	icon.offset_top = 8
	icon.offset_right = -8
	icon.offset_bottom = -8
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(icon)
	var name_label := UI.label("", 12, UI.TEXT, "bold")
	name_label.name = "Name"
	name_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_label.offset_left = 4
	name_label.offset_right = -4
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.max_lines_visible = 3
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(name_label)
	if number > 0:
		var num := UI.label(str(number), 11, UI.MUTED, "black")
		num.position = Vector2(6, 2)
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(num)
	_style_slot(b, false, false)
	return b


func _style_slot(b: Button, filled: bool, on: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UI.BG_2, 0.82 if filled else 0.45)
	sb.set_corner_radius_all(16)
	if on:
		sb.set_border_width_all(3)
		sb.border_color = UI.ACCENT
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		b.add_theme_stylebox_override(st, sb)


func _fill_slot(b: Button, t: Dictionary) -> void:
	var icon: TextureRect = b.get_node("Icon")
	var name_label: Label = b.get_node("Name")
	icon.texture = null
	name_label.text = str(t.get("name", ""))
	b.tooltip_text = str(t.get("tip", ""))
	var ref := str(t.get("icon", ""))
	if ref != "":
		AssetCache.fetch(ref, func(tex: Texture2D):
			if tex and is_instance_valid(icon):
				icon.texture = tex
				name_label.text = "")
	_style_slot(b, not t.is_empty(), t.get("id", "") == _equipped and _equipped != "")


## The player's tools changed (picked up, lost, equipped...).
func set_tools(list: Array, equipped: String) -> void:
	# Keep the order tools were first seen in, wherever they move (hand, backpack).
	for t in list:
		if not _seen.has(t.id):
			_seen.append(t.id)
	var live := list.map(func(t): return t.id)
	_seen = _seen.filter(func(id): return live.has(id))
	list = list.duplicate()
	list.sort_custom(func(a, b): return _seen.find(a.id) < _seen.find(b.id))
	_tools = list
	_equipped = equipped
	var ids := list.map(func(t): return t.id)
	_bar = _bar.filter(func(id): return ids.has(id))
	# New tools fill empty slots in the order they were picked up.
	for id in ids:
		if _bar.size() >= HOTBAR_SLOTS:
			break
		if not _bar.has(id):
			_bar.append(id)
	# What's in hand is always in the hotbar.
	if equipped != "" and not _bar.has(equipped):
		_make_room(equipped)
	_refresh_tools()


func _make_room(id: String) -> void:
	if _bar.size() < HOTBAR_SLOTS:
		_bar.append(id)
		return
	var oldest := 0
	for i in _bar.size():
		if _bar[i] != _equipped and float(_used.get(_bar[i], 0)) < float(_used.get(_bar[oldest], 0)):
			oldest = i
	if _bar[oldest] == _equipped:
		oldest = (oldest + 1) % _bar.size()
	_bar[oldest] = id


func _tool(id: String) -> Dictionary:
	for t in _tools:
		if t.id == id:
			return t
	return {}


func _refresh_tools() -> void:
	_hotbar.visible = _core.Backpack and not _tools.is_empty()
	_bag_btn.visible = _tools.size() > HOTBAR_SLOTS
	for i in HOTBAR_SLOTS:
		var t := _tool(_bar[i]) if i < _bar.size() else {}
		_slots[i].visible = i < maxi(_tools.size(), 1)
		_fill_slot(_slots[i], t)
	if not _core.Backpack:
		_inventory.visible = false
	if _inventory.visible:
		_fill_inventory()


func _fill_inventory() -> void:
	for c in _inv_grid.get_children():
		c.queue_free()
	if _tools.is_empty():
		_inv_grid.add_child(UI.label(L.t("inventory_empty"), 16, UI.MUTED))
		return
	for t in _tools:
		var b := _slot_button(_bar.find(t.id) + 1)
		_fill_slot(b, t)
		var id: String = t.id
		b.pressed.connect(func():
			_used[id] = Time.get_ticks_msec()
			if not _bar.has(id):
				_make_room(id)
			tool_picked.emit(id)
			_inventory.visible = false)
		_inv_grid.add_child(b)


func _pick_slot(i: int) -> void:
	if not _core.Backpack or i >= _bar.size():
		return
	_used[_bar[i]] = Time.get_ticks_msec()
	tool_picked.emit(_bar[i])


func toggle_inventory() -> void:
	if not _core.Backpack:
		return
	_inventory.visible = not _inventory.visible
	if _inventory.visible:
		release_touches()
		_fill_inventory()


func inventory_open() -> bool:
	return _inventory.visible


## StarterGui:SetCoreGuiEnabled from the place's scripts.
func set_core_gui(kind: String, on: bool) -> void:
	_core[kind] = on
	match kind:
		"Backpack":
			_refresh_tools()
		"Health":
			_hp_row.visible = on
		"Chat":
			set_chat_enabled(chat_enabled)
		"Emotes":
			emote_btn.visible = on
			if not on:
				wheel.close()


## A dot (or the place's cursor image) in the middle while the mouse is locked.
func set_crosshair(tex: Texture2D, on: bool) -> void:
	_crosshair.visible = on
	if tex:
		_crosshair.texture = tex
	elif _crosshair.texture == null or not _crosshair.has_meta("dot"):
		var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		for y in 12:
			for x in 12:
				var d := Vector2(x - 5.5, y - 5.5).length()
				if d < 5.5:
					img.set_pixel(x, y, Color(0, 0, 0, 0.55) if d > 3.2 else Color.WHITE)
		_crosshair.texture = ImageTexture.create_from_image(img)
		_crosshair.set_meta("dot", true)
	if tex:
		_crosshair.remove_meta("dot")
	_crosshair.size = _crosshair.texture.get_size()
	_crosshair.position = (_root.size - _crosshair.size) / 2.0


# --- public API -------------------------------------------------------------

func set_server(_name: String, _players: int, _max_players: int) -> void:
	# The server name lives in the in-game menu now; the HUD stays clean.
	pass


var chat_enabled := true
var _chat_btn: Button


## Under-13 accounts have no chat: hide the log, the input and the button.
func set_chat_enabled(on: bool) -> void:
	chat_enabled = on
	on = on and _core.Chat
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


## The stamina bar under health: hidden when stamina is endless or sprinting is
## off, faded while full, amber while winded.
func _update_stamina() -> void:
	var on: bool = _hp_row.visible and player.can_sprint and player.max_stamina > 0.0
	_stamina_bg.visible = on
	if DisplayServer.is_touchscreen_available():
		sprint_btn.visible = player.can_sprint and not player.dead
		if not player.can_sprint and player.sprint_toggle:
			player.sprint_toggle = false
			sprint_btn.latched = false
	if not on:
		return
	var r := _hp_row.get_global_rect()
	var bar_x := r.position.x + (r.size.x - HP_W) * 0.5
	for c in _hp_row.get_children():
		if c is Panel:
			bar_x = (c as Control).global_position.x
	_stamina_bg.global_position = Vector2(bar_x, r.end.y + 4.0)
	var frac := clampf(player.stamina / player.max_stamina, 0.0, 1.0)
	_stamina_fill.size.x = HP_W * frac
	var sb := _stamina_fill.get_theme_stylebox("panel") as StyleBoxFlat
	sb.bg_color = Color("#ffb86b") if player.winded else Color("#6ec8ff")
	_stamina_bg.modulate.a = move_toward(_stamina_bg.modulate.a, 0.45 if frac >= 0.999 else 1.0, get_process_delta_time() * 3.0)


## A place gave you a badge: a card slides down from the top for a few seconds.
func badge_popup(b: Dictionary) -> void:
	var card := UI.card(12, Color(UI.CARD, 0.96), 20)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var row := UI.hbox(12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var pic := TextureRect.new()
	pic.custom_minimum_size = Vector2(64, 64)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(pic)
	if str(b.get("image", "")) != "":
		var wr: WeakRef = weakref(pic)
		AssetCache.fetch(str(b.image), func(t: Texture2D):
			var p: TextureRect = wr.get_ref()
			if p and t:
				p.texture = t)
	else:
		pic.add_child(Icon.make("star", 64, UI.ACCENT))
	var col := UI.vbox(2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(UI.label(L.t("bg_got", [str(b.get("name", ""))]), 20, UI.TEXT, "black"))
	if str(b.get("description", "")) != "":
		col.add_child(UI.label(str(b.description), 15, UI.MUTED))
	row.add_child(col)
	_root.add_child(card)
	card.offset_top = -120
	Sfx.play("win")
	var t := card.create_tween()
	t.tween_property(card, "offset_top", 70.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(4.0)
	t.tween_property(card, "modulate:a", 0.0, 0.4)
	t.tween_callback(card.queue_free)


func big_message(text: String, seconds := 2.5) -> void:
	_toast_big.text = text
	var t := _toast_big.create_tween()
	t.tween_property(_toast_big, "modulate:a", 1.0, 0.2)
	t.tween_interval(seconds)
	t.tween_property(_toast_big, "modulate:a", 0.0, 0.4)


var _badges := {}  # role -> Texture2D of its badge


## Renders the owner/admin badges once into textures the chat can show inline.
func _make_badges() -> void:
	for role in ["owner", "admin"]:
		var vp := SubViewport.new()
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(vp)
		var b := UI.role_badge({"role": role}, 13)
		b.theme = UI.theme
		vp.add_child(b)
		await get_tree().process_frame
		vp.size = Vector2i(b.get_combined_minimum_size().ceil())
		b.size = vp.size
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var tex := ImageTexture.create_from_image(vp.get_texture().get_image())
		# RichTextLabel [img] takes a resource path, so give the texture one.
		tex.take_over_path("res://__chat_badge_%s.tex" % role)
		_badges[role] = tex
		vp.queue_free()


func add_chat(author: String, text: String, color := UI.TEXT, role := "") -> void:
	var safe := text.replace("[", "[lb]")
	var bb := ""
	if author != "":
		# Owner / admin badge after the name: the same pill as on profiles, as an image.
		var badge := ""
		if _badges.has(role):
			var tex: Texture2D = _badges[role]
			badge = " [img=%dx%d]%s[/img]" % [tex.get_width(), tex.get_height(), tex.resource_path]
		bb = "[b][color=#%s]%s[/color][/b]%s[b][color=#%s]:[/color][/b] %s" % [
			color.to_html(false), author.replace("[", "[lb]"), badge, color.to_html(false), safe]
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


## Opening shows the history; the input only takes focus when asked (a chat key
## on a keyboard), so tapping the chat button doesn't pop up the phone keyboard.
func _set_chat_expanded(on: bool, focus := false) -> void:
	_chat_expanded = on
	_chat_panel.visible = on
	_chat_log.visible = chat_enabled and not on
	if on:
		_scroll_chat_down()
		if focus:
			_chat_input.grab_focus()
	else:
		_chat_input.release_focus()
		# Reopening the closed view shouldn't bring back long-faded messages.
		for c in _chat_log.get_children():
			c.modulate.a = 0.0


func toggle_chat(focus := false) -> void:
	if not chat_enabled or not _core.Chat:
		return
	_set_chat_expanded(not _chat_expanded, focus)


func chat_open() -> bool:
	return _chat_expanded and _chat_input.has_focus()


func _send_chat() -> void:
	var text := _chat_input.text.strip_edges()
	_chat_input.text = ""
	if text != "":
		chat_submitted.emit(text)
	# Back to playing: the chat stays open to read replies, but WASD moves again
	# (and phones hide the keyboard). Enter, T or / jumps back into typing.
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


## The right mouse button is held to turn the camera.
func mouse_look() -> bool:
	return _mouse_look


func release_touches() -> void:
	for b in [jump_btn, emote_btn, sprint_btn]:
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


## Phones: may a tap here click the world (not the joystick, a button or a panel)?
func tap_allowed(pos: Vector2) -> bool:
	if _blocked(pos) or _overlay.visible or wheel.visible:
		return false
	for b in [jump_btn, emote_btn, sprint_btn]:
		if b.visible and b.get_global_rect().has_point(pos):
			return false
	return pos.x >= get_viewport().get_visible_rect().size.x * 0.42


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
	# Tapping or clicking anywhere outside the chat stops typing (and drops the keyboard).
	if _chat_input.has_focus() and ((event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed)):
		var at: Vector2 = event.position
		if not _chat_panel.get_global_rect().has_point(at) and not _chat_input_row.get_global_rect().has_point(at):
			_chat_input.release_focus()
			if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
				DisplayServer.virtual_keyboard_hide()
	if event is InputEventScreenTouch:
		_touch(event)
	elif event is InputEventScreenDrag:
		_drag(event)
	elif not DisplayServer.is_touchscreen_available():
		_desktop(event)


func _touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		for b in [jump_btn, emote_btn, sprint_btn]:
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
		for b in [jump_btn, emote_btn, sprint_btn]:
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
	elif event is InputEventMouseMotion and (_mouse_look or player.first_person or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED):
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
					toggle_chat(true)
				get_viewport().set_input_as_handled()
			KEY_B, KEY_G:
				if _core.Emotes and emote_btn.visible:
					release_touches()
					wheel.open()
			KEY_V:
				player.toggle_first_person()
			KEY_CTRL:
				# Shift lock (turned on in the menu's settings): Ctrl flips it.
				if Session.settings.get("shift_lock", false):
					player.shift_locked = not player.shift_locked
			KEY_1, KEY_2, KEY_3:
				_pick_slot(event.keycode - KEY_1)
			KEY_QUOTELEFT:
				toggle_inventory()
			KEY_R:
				player.die()
			KEY_SPACE:
				player.request_jump()
			KEY_ESCAPE, KEY_M:
				menu_requested.emit()


func _process(delta: float) -> void:
	if player:
		player.move_input = joystick.value
		player.keyboard_blocked = chat_open()
		player.sprint = Input.is_key_pressed(KEY_SHIFT) and not player.keyboard_blocked
		player.jump_held = (Input.is_key_pressed(KEY_SPACE) and not player.keyboard_blocked) or jump_btn.is_down()
		if player.shift_locked and not Session.settings.get("shift_lock", false):
			player.shift_locked = false
		# Arrow keys turn the camera (left/right) and tilt it (up/down).
		if not player.keyboard_blocked and not DisplayServer.is_touchscreen_available():
			var turn := float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT))
			var tilt := float(Input.is_physical_key_pressed(KEY_UP)) - float(Input.is_physical_key_pressed(KEY_DOWN))
			if turn != 0.0 or tilt != 0.0:
				player.rotate_camera(Vector2(turn, -tilt) * 380.0 * delta)
		_update_stamina()
