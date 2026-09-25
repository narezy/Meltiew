class_name MessagesPage
extends HBoxContainer
## Direct messages outside the game: conversation list (chats / requests) and a chat pane.

## Set before adding to open a conversation with this user right away.
var open_user: Dictionary = {}

var _tab := "chats"
var _tabs := {}
var _list: VBoxContainer
var _pane: VBoxContainer
var _conversations: Array = []
var _current: Dictionary = {}
var _messages_box: VBoxContainer
var _scroll: ScrollContainer
var _last_id := 0
var _input: LineEdit
var _poll: Timer


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 18)

	var left := UI.vbox(12)
	left.custom_minimum_size.x = 280 if get_viewport_rect().size.x < 1120.0 else 330
	add_child(left)
	left.add_child(UI.label(L.t("messages"), 34, UI.TEXT, "black"))
	var tabs := UI.hbox(8)
	for t in [["chats", L.t("chats")], ["requests", L.t("dm_requests")]]:
		var b := UI.button(t[1], "flat", 44)
		b.theme_type_variation = "ChipButton"
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(func():
			_tab = t[0]
			_render_list())
		tabs.add_child(b)
		_tabs[t[0]] = b
	left.add_child(tabs)
	var ls := ScrollContainer.new()
	ls.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ls.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = UI.vbox(8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ls.add_child(_list)
	left.add_child(ls)

	var right := UI.card(18, UI.CARD, 24)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(right)
	_pane = UI.vbox(12)
	right.add_child(_pane)
	_empty_pane()

	_poll = Timer.new()
	_poll.wait_time = 3.0
	_poll.autostart = true
	_poll.timeout.connect(_tick)
	add_child(_poll)
	await _load_list()
	if not open_user.is_empty():
		_open(open_user)


func _menu() -> Node:
	return get_meta("menu")


func refresh() -> void:
	_load_list()


func _tick() -> void:
	_load_list()
	if not _current.is_empty():
		_load_messages(false)


func _load_list() -> void:
	var r := await Api.request("GET", "/api/dm")
	if not is_inside_tree() or not r.ok:
		return
	_conversations = r.data.conversations
	var reqs := _conversations.filter(func(c): return c.state == "incoming").size()
	_tabs.requests.text = L.t("dm_requests") + (" (%d)" % reqs if reqs > 0 else "")
	_render_list()


func _render_list() -> void:
	for k in _tabs:
		_tabs[k].button_pressed = k == _tab
	for c in _list.get_children():
		c.queue_free()
	var items := _conversations.filter(func(c): return (c.state == "incoming") == (_tab == "requests"))
	if items.is_empty():
		var l := UI.label(L.t("no_requests_dm") if _tab == "requests" else L.t("no_chats"), 16, UI.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(l)
		return
	for conv in items:
		var u: Dictionary = conv.user
		var on: bool = not _current.is_empty() and int(_current.get("id", -1)) == int(u.id)
		var c := UI.card(12, UI.CARD_2 if on else UI.CARD, 18)
		var row := UI.hbox(10)
		c.add_child(row)
		row.add_child(UI.avatar_badge(u, 46))
		var col := UI.vbox(2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(UI.name_row(u, 17))
		var last: Dictionary = conv.last
		var prev := UI.label((L.t("you_prefix") if last.from_me else "") + str(last.body), 14, UI.MUTED)
		prev.clip_text = true
		prev.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		prev.custom_minimum_size.x = 150
		col.add_child(prev)
		row.add_child(col)
		if int(conv.unread) > 0:
			var badge := UI.label(str(conv.unread), 14, UI.INK, "black")
			var sb := StyleBoxFlat.new()
			sb.bg_color = UI.PINK
			sb.set_corner_radius_all(11)
			sb.content_margin_left = 8
			sb.content_margin_right = 8
			badge.add_theme_stylebox_override("normal", sb)
			badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(badge)
		UI.on_tap(c, func(): _open(u))
		_list.add_child(c)


func _empty_pane() -> void:
	for c in _pane.get_children():
		c.queue_free()
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(10)
	v.add_child(Icon.make("chat", 56, UI.LINE))
	var l := UI.label(L.t("pick_chat"), 18, UI.MUTED)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	center.add_child(v)
	_pane.add_child(center)


func _open(u: Dictionary) -> void:
	_current = u
	_last_id = 0
	_render_list()
	await _load_messages(true)


func _load_messages(full: bool) -> void:
	var uid := int(_current.get("id", 0))
	var r := await Api.request("GET", "/api/dm/%d?after=%d" % [uid, 0 if full else _last_id])
	if not is_inside_tree() or not r.ok or int(_current.get("id", -1)) != uid:
		return
	if full:
		_build_pane(r.data)
	for m in r.data.messages:
		if int(m.id) > _last_id:
			_add_bubble(m)
			_last_id = int(m.id)
	if full or r.data.messages.size() > 0:
		await get_tree().process_frame
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _build_pane(data: Dictionary) -> void:
	for c in _pane.get_children():
		c.queue_free()
	var u: Dictionary = data.user
	var head := UI.hbox(12)
	head.add_child(UI.avatar_badge(u, 48))
	var col := UI.vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UI.name_row(u, 20))
	var st := FriendsPage.status_text(u)
	col.add_child(UI.label(st[0], 14, st[1]))
	head.add_child(col)
	var prof := UI.button(L.t("profile"), "ghost", 42)
	prof.add_theme_font_size_override("font_size", 16)
	prof.pressed.connect(func(): _menu().show_profile(str(u.username)))
	head.add_child(prof)
	_pane.add_child(head)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_messages_box = UI.vbox(8)
	_messages_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_messages_box)
	_pane.add_child(_scroll)

	var state := str(data.state)
	if not data.get("can_message", true):
		_pane.add_child(_note(L.t("dm_unavailable_note")))
	elif state == "incoming":
		var box := UI.vbox(8)
		box.add_child(_note(L.t("dm_request_from", [u.display_name])))
		var row := UI.hbox(10)
		var no := UI.button(L.t("decline"), "ghost", 50)
		no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		no.pressed.connect(func():
			await Api.request("POST", "/api/dm/%d/decline" % int(u.id))
			_current = {}
			_empty_pane()
			_load_list())
		var yes := UI.button(L.t("accept"), "mint", 50)
		yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		yes.pressed.connect(func():
			await Api.request("POST", "/api/dm/%d/accept" % int(u.id))
			Sfx.play("pop")
			_open(u)
			_load_list())
		row.add_child(no)
		row.add_child(yes)
		box.add_child(row)
		_pane.add_child(box)
	elif state == "outgoing":
		_pane.add_child(_note(L.t("dm_waiting", [u.display_name])))
	else:
		if state == "none":
			_pane.add_child(_note(L.t("dm_first_message")))
		var row := UI.hbox(10)
		_input = UI.input(L.t("type_message"))
		_input.max_length = 500
		_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_input.text_submitted.connect(func(_t): _send())
		row.add_child(_input)
		var send := UI.button("", "primary", 56)
		send.custom_minimum_size.x = 64
		var ic := Icon.make("send", 24, UI.INK)
		ic.position = Vector2(20, 16)
		send.add_child(ic)
		send.pressed.connect(_send)
		row.add_child(send)
		_pane.add_child(row)


func _note(text: String) -> Control:
	var l := UI.label(text, 16, UI.MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _add_bubble(m: Dictionary) -> void:
	var row := UI.hbox(0)
	var bubble := PanelContainer.new()
	bubble.mouse_filter = Control.MOUSE_FILTER_PASS
	var sb := StyleBoxFlat.new()
	sb.bg_color = UI.ACCENT if m.from_me else UI.CARD_2
	sb.set_corner_radius_all(16)
	sb.corner_radius_bottom_right = 4 if m.from_me else 16
	sb.corner_radius_bottom_left = 16 if m.from_me else 4
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	bubble.add_theme_stylebox_override("panel", sb)
	var l := UI.label(str(m.body), 17, UI.INK if m.from_me else UI.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = mini(420, 20 + str(m.body).length() * 10)
	bubble.add_child(l)
	if m.from_me:
		row.add_child(UI.spacer())
	row.add_child(bubble)
	_messages_box.add_child(row)


func _send() -> void:
	if _input == null:
		return
	var text := _input.text.strip_edges()
	if text == "":
		return
	_input.text = ""
	var uid := int(_current.get("id", 0))
	var r := await Api.request("POST", "/api/dm/%d" % uid, {"text": text})
	if not is_inside_tree():
		return
	if not r.ok:
		UI.toast(r.message, "error")
		return
	Sfx.play("pop", 1.3)
	if str(r.data.state) != "open":
		# First message to a stranger: the composer turns into "waiting".
		_open(_current)
	else:
		_load_messages(false)
	_load_list()
