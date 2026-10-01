class_name CommunitiesPage
extends VBoxContainer
## Communities: yours and popular ones, search, and making one (10 pieces or 100
## orbs). Opening one shows its channels (a chat that refreshes itself), members
## with their roles, its places, and for its managers the settings.

const COLORS := ["#b79cff", "#7ee0c3", "#4cc9f0", "#ffb86b", "#ff8fb1", "#ffd166", "#9d7bff", "#6bd6a5"]
const PERMS := ["manage", "moderate", "places", "post", "bank"]
const POLL_SEC := 3.0

var _price := {"pieces": 10, "orbs": 100}
var _c: Dictionary = {}  # the open community
var _tab := "channels"
var _channel := 0
var _last_msg := 0
var _msgs: VBoxContainer
var _msg_scroll: ScrollContainer
var _poll: Timer
var _search: LineEdit
var _list: VBoxContainer
var _search_timer: Timer
var _content: VBoxContainer
var _tab_buttons := {}


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 16)
	_poll = Timer.new()
	_poll.wait_time = POLL_SEC
	_poll.timeout.connect(_poll_messages)
	add_child(_poll)
	_show_list()


func _menu() -> Node:
	return get_meta("menu")


func refresh() -> void:
	if _c.is_empty():
		_show_list()
	else:
		open_community(int(_c.id))


func _clear() -> void:
	_poll.stop()
	for ch in get_children():
		if ch != _poll:
			ch.queue_free()


# --- the list ------------------------------------------------------------------------

func _show_list() -> void:
	_clear()
	_c = {}
	var head := UI.hbox(16)
	var title := UI.vbox(2)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(UI.label(L.t("nav_communities"), 34, UI.TEXT, "black"))
	var sub := UI.label(L.t("cm_sub"), 19, UI.MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_child(sub)
	head.add_child(title)
	var make := UI.button(L.t("cm_create"), "primary", 52)
	make.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	make.pressed.connect(_create_sheet)
	head.add_child(make)
	add_child(head)

	_search = UI.input(L.t("cm_search"))
	add_child(_search)
	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.wait_time = 0.35
	_search_timer.timeout.connect(_load_list)
	add_child(_search_timer)
	_search.text_changed.connect(func(_t): _search_timer.start())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = UI.vbox(10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	add_child(scroll)
	_load_list()


func _load_list() -> void:
	if not is_instance_valid(_list):
		return
	for ch in _list.get_children():
		ch.queue_free()
	_list.add_child(Loading.spinner(30))
	var text := _search.text.strip_edges()
	var mine: Array = []
	if text == "":
		var rm := await Api.request("GET", "/api/communities/mine")
		if rm.ok:
			mine = rm.data.get("communities", [])
			_price = rm.data.get("price", _price)
	var r := await Api.request("GET", "/api/communities?q=" + text.uri_encode())
	if not is_instance_valid(_list) or text != _search.text.strip_edges():
		return
	for ch in _list.get_children():
		ch.queue_free()
	if not mine.is_empty():
		_list.add_child(UI.label(L.t("cm_mine"), 18, UI.MUTED, "bold"))
		for c in mine:
			_list.add_child(_card(c))
	var found: Array = r.data.get("communities", []) if r.ok else []
	var mine_ids := mine.map(func(c): return int(c.id))
	found = found.filter(func(c): return not (int(c.id) in mine_ids))
	_list.add_child(UI.label(L.t("cm_found") if text != "" else L.t("cm_popular"), 18, UI.MUTED, "bold"))
	if found.is_empty():
		var e := UI.label(L.t("cm_none"), 17, UI.MUTED)
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(e)
	for c in found:
		_list.add_child(_card(c))


## The four roles every community starts with are shown in the app's language.
static func role_name(n: Variant) -> String:
	var key := "cm_role_" + str(n).to_lower()
	return L.t(key) if str(n) in ["Owner", "Admin", "Builder", "Member"] else str(n)


static func emblem(c: Dictionary, px := 56) -> Control:
	var p := UI.card(0, Color(str(c.get("color", "#b79cff"))), int(px * 0.3))
	p.custom_minimum_size = Vector2(px, px)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.label(str(c.get("name", "?")).substr(0, 1).to_upper(), int(px * 0.5), Color("#1d1a26"), "black")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p


func _card(c: Dictionary) -> Control:
	var card := UI.card(14, UI.CARD, 20)
	var row := UI.hbox(14)
	card.add_child(row)
	row.add_child(emblem(c))
	var col := UI.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var n := UI.label(str(c.name), 21, UI.TEXT, "bold")
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(n)
	var line := L.t("cm_members", [int(c.get("members", 0))])
	if c.has("role_name"):
		line += " · " + role_name(c.role_name)
	col.add_child(UI.label(line, 16, UI.MUTED))
	row.add_child(col)
	UI.on_tap(card, func(): open_community(int(c.id)))
	return card


func _create_sheet() -> void:
	var s := Economy._sheet(self, L.t("cm_create"))
	var layer: CanvasLayer = s[0]
	var v: VBoxContainer = s[1]
	var name := UI.input(L.t("cm_name"))
	name.max_length = 40
	v.add_child(name)
	var desc := TextEdit.new()
	desc.placeholder_text = L.t("cm_desc")
	desc.custom_minimum_size.y = 90
	desc.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	v.add_child(desc)
	var color := [COLORS[randi() % COLORS.size()]]
	v.add_child(_swatches(color))
	var hint := UI.label(L.t("cm_price_hint"), 15, UI.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)
	var row := UI.hbox(8)
	for cur in ["pieces", "orbs"]:
		var b := UI.button("", "primary" if cur == "pieces" else "ghost", 52)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var inner := UI.hbox(6)
		inner.set_anchors_preset(Control.PRESET_CENTER)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ink: Color = UI.TEXT if cur == "orbs" else Color("#1d1a26")
		inner.add_child(UI.label(L.t("cm_create_for"), 17, ink, "bold"))
		inner.add_child(Economy.price_tag({cur: int(_price.get(cur, 0))}, 17, cur, ink))
		b.custom_minimum_size.x = 200
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(inner)
		b.add_child(center)
		b.pressed.connect(func():
			var r := await Api.request("POST", "/api/communities", {"name": name.text.strip_edges(), "description": desc.text.strip_edges(), "color": color[0], "currency": cur})
			if not r.ok:
				UI.toast(r.message, "error")
				return
			if r.data.has("wallet"):
				Economy.set_wallet(r.data.wallet)
			layer.queue_free()
			UI.toast(L.t("cm_created"), "ok")
			open_community(int(r.data.community.id)))
		row.add_child(b)
	v.add_child(row)


func _swatches(picked: Array) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	var buttons: Array = []
	for col in COLORS:
		var b := Button.new()
		b.toggle_mode = true
		b.set_meta("pad_focus", true)
		b.focus_mode = Controls.focus_mode()
		b.custom_minimum_size = Vector2(40, 40)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(col)
		sb.set_corner_radius_all(20)
		var on := sb.duplicate() as StyleBoxFlat
		on.set_border_width_all(4)
		on.border_color = UI.TEXT
		for st in ["normal", "hover"]:
			b.add_theme_stylebox_override(st, sb)
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_stylebox_override("hover_pressed", on)
		b.button_pressed = col == picked[0]
		b.pressed.connect(func():
			picked[0] = col
			for o in buttons:
				o.button_pressed = o == b)
		buttons.append(b)
		flow.add_child(b)
	return flow


# --- one community ---------------------------------------------------------------------

func open_community(id: int) -> void:
	var r := await Api.request("GET", "/api/communities/%d" % id)
	if not is_inside_tree():
		return
	if not r.ok:
		UI.toast(r.message, "error")
		_show_list()
		return
	var switching := _c.is_empty() or int(_c.id) != id
	_c = r.data.community
	if switching:
		_tab = "channels"
		_channel = 0
	_render_community()


func _me() -> Dictionary:
	return _c.get("me", {}) if _c.get("me") is Dictionary else {}


func _can(perm: String) -> bool:
	return perm in _me().get("perms", [])


func _render_community() -> void:
	_clear()
	var head := UI.hbox(14)
	var back := UI.button("", "ghost", 52)
	back.custom_minimum_size.x = 52
	var bi := Icon.make("back", 24, UI.TEXT)
	bi.set_anchors_preset(Control.PRESET_CENTER)
	bi.position -= Vector2(12, 12)
	back.add_child(bi)
	back.pressed.connect(_show_list)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(back)
	head.add_child(emblem(_c, 64))
	var col := UI.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var n := UI.label(str(_c.name), 28, UI.TEXT, "black")
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(n)
	var line := L.t("cm_members", [int(_c.members)])
	if _c.get("owner") is Dictionary:
		line += " · " + L.t("cm_by", [str(_c.owner.display_name)])
	col.add_child(UI.label(line, 16, UI.MUTED))
	head.add_child(col)
	var me := _me()
	if me.is_empty():
		if bool(_c.get("banned", false)):
			head.add_child(UI.label(L.t("cm_banned"), 16, UI.PINK, "bold"))
		else:
			var join := UI.button(L.t("cm_join"), "mint", 50)
			join.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			join.pressed.connect(func(): _act("POST", "/api/communities/%d/join" % int(_c.id)))
			head.add_child(join)
	elif int(me.rank) < 255:
		var leave := UI.button(L.t("cm_leave"), "ghost", 50)
		leave.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		leave.pressed.connect(func():
			if await UI.confirm(self, L.t("cm_leave_q"), str(_c.name), L.t("cm_leave")):
				_act("POST", "/api/communities/%d/leave" % int(_c.id)))
		head.add_child(leave)
	add_child(head)
	if str(_c.get("description", "")) != "":
		var d := UI.label(str(_c.description), 17, UI.MUTED)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.max_lines_visible = 3
		add_child(d)

	var tabs := UI.hbox(8)
	_tab_buttons = {}
	var list := [["channels", L.t("cm_channels")], ["members", L.t("cm_people")], ["places", L.t("cm_places")]]
	# Members see the bank (the balance comes with the community only for them).
	if _c.has("bank") and _c.bank != null:
		list.append(["bank", L.t("cm_bank")])
	if _can("manage"):
		list.append(["settings", L.t("cm_settings")])
	for t in list:
		var b := UI.button(t[1], "flat", 44)
		b.theme_type_variation = "ChipButton"
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(func(): _set_tab(t[0]))
		tabs.add_child(b)
		_tab_buttons[t[0]] = b
	add_child(tabs)
	_content = UI.vbox(10)
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_content)
	if not _tab_buttons.has(_tab):
		_tab = "channels"
	_set_tab(_tab)


func _act(method: String, path: String, body: Variant = null) -> bool:
	var r := await Api.request(method, path, body)
	if not r.ok:
		UI.toast(r.message, "error")
		return false
	if r.data.get("community") is Dictionary:
		_c = r.data.community
		_render_community()
	elif not _c.is_empty():
		open_community(int(_c.id))
	return true


func _set_tab(t: String) -> void:
	_tab = t
	_poll.stop()
	for k in _tab_buttons:
		_tab_buttons[k].button_pressed = k == t
	for ch in _content.get_children():
		ch.queue_free()
	match t:
		"channels":
			_channels_tab()
		"members":
			_members_tab()
		"places":
			_places_tab()
		"bank":
			_bank_tab()
		"settings":
			_settings_tab()


# --- channels ---------------------------------------------------------------------------

func _channels_tab() -> void:
	var channels: Array = _c.get("channels", [])
	if channels.is_empty():
		return
	if not channels.any(func(ch): return int(ch.id) == _channel):
		_channel = int(channels[0].id)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	for ch in channels:
		var b := UI.button("# " + str(ch.name), "flat", 38)
		b.theme_type_variation = "ChipButton"
		b.toggle_mode = true
		b.button_pressed = int(ch.id) == _channel
		b.add_theme_font_size_override("font_size", 16)
		var cid := int(ch.id)
		b.pressed.connect(func():
			_channel = cid
			_set_tab("channels"))
		chips.add_child(b)
	_content.add_child(chips)

	var box := UI.card(12, UI.BG_2, 18)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(box)
	_msg_scroll = ScrollContainer.new()
	_msg_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_msg_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_msg_scroll)
	_msgs = UI.vbox(10)
	_msgs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_msg_scroll.add_child(_msgs)
	_last_msg = 0

	var ch_now: Dictionary = channels.filter(func(ch): return int(ch.id) == _channel)[0]
	var me := _me()
	if me.is_empty():
		_content.add_child(UI.label(L.t("cm_join_to_write"), 16, UI.MUTED))
	elif not _can("post") or int(me.rank) < int(ch_now.post_rank):
		_content.add_child(UI.label(L.t("cm_cant_write"), 16, UI.MUTED))
	else:
		var row := UI.hbox(8)
		var input := UI.input(L.t("cm_write", [str(ch_now.name)]))
		input.max_length = 1000
		input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(input)
		var send := UI.button(L.t("send"), "primary", 56)
		row.add_child(send)
		var go := func():
			var text := input.text.strip_edges()
			if text == "":
				return
			input.text = ""
			var r := await Api.request("POST", "/api/communities/%d/channels/%d/messages" % [int(_c.id), _channel], {"text": text})
			if not r.ok:
				UI.toast(r.message, "error")
				input.text = text
				return
			_poll_messages()
		send.pressed.connect(go)
		input.text_submitted.connect(func(_t): go.call())
		_content.add_child(row)
	_load_messages()


func _load_messages() -> void:
	var cid := _channel
	var r := await Api.request("GET", "/api/communities/%d/channels/%d/messages" % [int(_c.id), cid])
	if not is_instance_valid(_msgs) or cid != _channel or _tab != "channels":
		return
	var list: Array = r.data.get("messages", []) if r.ok else []
	if list.is_empty():
		var e := UI.label(L.t("cm_no_messages"), 16, UI.MUTED)
		e.name = "Empty"
		_msgs.add_child(e)
	_add_messages(list)
	_poll.start()


func _poll_messages() -> void:
	if _tab != "channels" or not is_instance_valid(_msgs) or _c.is_empty():
		return
	var cid := _channel
	var r := await Api.request("GET", "/api/communities/%d/channels/%d/messages?after=%d" % [int(_c.id), cid, _last_msg])
	if r.ok and is_instance_valid(_msgs) and cid == _channel:
		var list: Array = r.data.get("messages", [])
		if not list.is_empty() and _msgs.has_node("Empty"):
			_msgs.get_node("Empty").queue_free()
		_add_messages(list)


func _add_messages(list: Array) -> void:
	var first := _last_msg == 0
	var at_bottom := _msg_scroll.scroll_vertical >= _msg_scroll.get_v_scroll_bar().max_value - _msg_scroll.size.y - 40
	for m in list:
		if int(m.id) <= _last_msg:
			continue
		_last_msg = int(m.id)
		_msgs.add_child(_message_row(m))
	if not list.is_empty() and (first or at_bottom):
		await get_tree().process_frame
		if is_instance_valid(_msg_scroll):
			_msg_scroll.scroll_vertical = int(_msg_scroll.get_v_scroll_bar().max_value)


func _message_row(m: Dictionary) -> Control:
	var u: Dictionary = m.author
	var row := UI.hbox(10)
	var badge := UI.avatar_badge(u, 40)
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(badge)
	var col := UI.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var top := UI.hbox(8)
	var nr := UI.name_row(u, 16)
	top.add_child(nr)
	top.add_child(UI.label(UI.relative_time(float(m.created_at)), 13, UI.MUTED))
	col.add_child(top)
	UI.on_tap(nr, func(): _menu().show_profile(str(u.username)))
	var body := UI.label(str(m.body), 17, UI.TEXT)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(body)
	row.add_child(col)
	var mine := int(u.id) == int(Session.user.get("id", -1))
	if mine or _can("moderate"):
		var del := UI.button("✕", "flat", 28)
		del.custom_minimum_size.x = 30
		del.add_theme_font_size_override("font_size", 13)
		del.add_theme_color_override("font_color", UI.MUTED)
		del.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		del.tooltip_text = L.t("delete")
		del.pressed.connect(func():
			var r := await Api.request("DELETE", "/api/communities/%d/messages/%d" % [int(_c.id), int(m.id)])
			if r.ok:
				row.queue_free()
			else:
				UI.toast(r.message, "error"))
		row.add_child(del)
	return row


# --- members ----------------------------------------------------------------------------

func _members_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := UI.vbox(8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	_content.add_child(scroll)
	list.add_child(Loading.spinner(30))
	var r := await Api.request("GET", "/api/communities/%d/members" % int(_c.id))
	if not is_instance_valid(list):
		return
	for ch in list.get_children():
		ch.queue_free()
	var roles := {}
	for role in _c.get("roles", []):
		roles[int(role.id)] = role
	var my_rank := int(_me().get("rank", 0))
	for m in (r.data.get("members", []) if r.ok else []):
		var role: Dictionary = roles.get(int(m.role_id), {"name": "?", "rank": 0})
		var card := UI.card(12, UI.CARD, 18)
		var row := UI.hbox(12)
		card.add_child(row)
		row.add_child(UI.avatar_badge(m, 46))
		var col := UI.vbox(2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(UI.name_row(m, 18))
		col.add_child(UI.label("@" + str(m.username), 14, UI.MUTED))
		row.add_child(col)
		var above := int(role.rank) < my_rank and int(m.id) != int(Session.user.get("id", -1))
		if _can("manage") and above:
			var pick := Picker.new(L.t("cm_role"))
			pick.custom_minimum_size.x = 170
			for rl in _c.get("roles", []):
				if int(rl.rank) < my_rank:
					pick.add_item(role_name(rl.name), int(rl.id))
			pick.select_id(int(m.role_id))
			var uid := int(m.id)
			pick.picked.connect(func(rid):
				var rr := await Api.request("PATCH", "/api/communities/%d/members/%d" % [int(_c.id), uid], {"role_id": int(rid)})
				UI.toast(L.t("saved") if rr.ok else rr.message, "ok" if rr.ok else "error"))
			row.add_child(pick)
		else:
			row.add_child(UI.label(role_name(role.name), 16, UI.ACCENT if int(role.rank) >= 200 else UI.MUTED, "bold"))
		if _can("moderate") and above:
			for ban in [false, true]:
				var b := UI.button(L.t("cm_ban") if ban else L.t("cm_remove"), "danger" if ban else "ghost", 44)
				var uid2 := int(m.id)
				var who := str(m.display_name)
				b.pressed.connect(func():
					var q := L.t("cm_ban_q", [who]) if ban else L.t("cm_remove_q", [who])
					if not await UI.confirm(self, q, L.t("cm_ban_text") if ban else "", L.t("cm_ban") if ban else L.t("cm_remove"), true):
						return
					var rr := await Api.request("DELETE", "/api/communities/%d/members/%d%s" % [int(_c.id), uid2, "?ban=1" if ban else ""])
					if rr.ok:
						card.queue_free()
					else:
						UI.toast(rr.message, "error"))
				row.add_child(b)
		UI.on_tap(col, func(): _menu().show_profile(str(m.username)))
		list.add_child(card)


# --- places -----------------------------------------------------------------------------

func _places_tab() -> void:
	if _can("places"):
		var make := UI.button(L.t("cm_new_place"), "primary", 48)
		make.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		make.pressed.connect(func():
			var r := await Api.request("POST", "/api/studio/places", {"name": str(_c.name), "community_id": int(_c.id)})
			if not r.ok:
				UI.toast(r.message, "error")
				return
			Session.studio_place_id = str(r.data.place.id)
			Session.studio_melt = {}
			UI.goto("res://scenes/studio.tscn"))
		_content.add_child(make)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 14)
	flow.add_theme_constant_override("v_separation", 14)
	scroll.add_child(flow)
	_content.add_child(scroll)
	var r := await Api.request("GET", "/api/communities/%d/places" % int(_c.id))
	if not is_instance_valid(flow):
		return
	var places: Array = r.data.get("places", []) if r.ok else []
	if places.is_empty():
		flow.add_child(UI.label(L.t("cm_no_places"), 17, UI.MUTED))
	for p in places:
		var pid := str(p.id)
		flow.add_child(HomePage.place_card(p, func(): _menu().open_place(pid)))


# --- bank -------------------------------------------------------------------------------

## The balance, what came in and went out, and (for the owner or a role with "bank")
## paying members: an amount next to each, one or several at once.
func _bank_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	_content.add_child(scroll)
	v.add_child(Loading.spinner(30))
	var cid := int(_c.id)
	var r := await Api.request("GET", "/api/communities/%d/bank" % cid)
	if not is_instance_valid(v):
		return
	for ch in v.get_children():
		ch.queue_free()
	if not r.ok:
		v.add_child(UI.label(r.message, 16, UI.MUTED))
		return
	var bank := int(r.data.get("bank", 0))
	var head := UI.card(16, UI.CARD, 18)
	var hv := UI.vbox(4)
	head.add_child(hv)
	var bal := UI.hbox(10)
	bal.add_child(Icon.make("piece", 34, Economy.PIECE_COLOR))
	bal.add_child(UI.label(str(bank), 34, UI.TEXT, "black"))
	hv.add_child(bal)
	var about := UI.label(L.t("cm_bank_about"), 15, UI.MUTED)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hv.add_child(about)
	v.add_child(head)

	if r.data.get("can_pay", false) and bank > 0:
		v.add_child(UI.label(L.t("cm_bank_pay"), 20, UI.TEXT, "bold"))
		var mr := await Api.request("GET", "/api/communities/%d/members" % cid)
		if not is_instance_valid(v):
			return
		var amounts := {}
		var pay := UI.button(L.t("cm_bank_pay"), "primary", 50)
		pay.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var update_total := func():
			var total := 0
			for uid in amounts:
				total += int(amounts[uid].value)
			pay.text = L.t("cm_bank_pay_total", [total])
			pay.disabled = total <= 0 or total > bank
		for m in (mr.data.get("members", []) if mr.ok else []):
			var row := UI.hbox(12)
			row.add_child(UI.avatar_badge(m, 40))
			var nm := UI.name_row(m, 17)
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(nm)
			var amount := SpinBox.new()
			amount.min_value = 0
			amount.max_value = bank
			amount.custom_minimum_size.x = 130
			amount.value_changed.connect(func(_x): update_total.call())
			amounts[int(m.id)] = amount
			row.add_child(amount)
			v.add_child(row)
		update_total.call()
		pay.pressed.connect(func():
			var payouts := []
			for uid in amounts:
				if int(amounts[uid].value) > 0:
					payouts.append({"user_id": uid, "amount": int(amounts[uid].value)})
			pay.disabled = true
			var pr := await Api.request("POST", "/api/communities/%d/bank/pay" % cid, {"payouts": payouts})
			if pr.ok:
				UI.toast(L.t("cm_bank_paid"), "ok")
				if pr.data.get("wallet") is Dictionary:
					Economy.set_wallet(pr.data.wallet)
				_set_tab("bank")
			else:
				UI.toast(pr.message, "error")
				pay.disabled = false)
		v.add_child(pay)

	v.add_child(UI.label(L.t("cm_bank_history"), 20, UI.TEXT, "bold"))
	var log: Array = r.data.get("log", [])
	if log.is_empty():
		v.add_child(UI.label(L.t("cm_bank_empty"), 16, UI.MUTED))
	for e in log:
		var row := UI.hbox(10)
		var delta := int(e.get("delta", 0))
		var who: Variant = e.get("user")
		var what := L.t("cm_bank_sale") if str(e.get("reason", "")) == "gamepass_sale" else L.t("cm_bank_payout", [str(who.display_name) if who is Dictionary else "?"])
		var l := UI.label(what, 16, UI.TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(UI.label(("+" if delta > 0 else "") + str(delta), 17, UI.MINT if delta > 0 else UI.PINK, "black"))
		v.add_child(row)


# --- settings (managers) ----------------------------------------------------------------

func _settings_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	_content.add_child(scroll)
	var my_rank := int(_me().get("rank", 0))
	var cid := int(_c.id)

	# Name, description, color.
	var info := UI.card(16, UI.CARD, 20)
	var iv := UI.vbox(10)
	info.add_child(iv)
	var name := UI.input(L.t("cm_name"))
	name.text = str(_c.name)
	name.max_length = 40
	iv.add_child(name)
	var desc := TextEdit.new()
	desc.text = str(_c.get("description", ""))
	desc.custom_minimum_size.y = 90
	desc.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	iv.add_child(desc)
	var color := [str(_c.get("color", COLORS[0]))]
	iv.add_child(_swatches(color))
	var save := UI.button(L.t("save"), "primary", 48)
	save.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	save.pressed.connect(func():
		if await _act("PATCH", "/api/communities/%d" % cid, {"name": name.text.strip_edges(), "description": desc.text, "color": color[0]}):
			UI.toast(L.t("saved"), "ok"))
	iv.add_child(save)
	v.add_child(info)

	# Roles.
	v.add_child(UI.label(L.t("cm_roles"), 20, UI.TEXT, "bold"))
	var rh := UI.label(L.t("cm_roles_hint"), 14, UI.MUTED)
	rh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(rh)
	for role in _c.get("roles", []):
		v.add_child(_role_row(role, my_rank))
	var add_row := UI.hbox(8)
	var rname := UI.input(L.t("cm_role_name"))
	rname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(rname)
	var rrank := SpinBox.new()
	rrank.min_value = 2
	rrank.max_value = mini(254, my_rank - 1)
	rrank.value = 50
	rrank.prefix = L.t("cm_rank")
	add_row.add_child(rrank)
	var radd := UI.button(L.t("cm_add"), "ghost", 52)
	radd.pressed.connect(func(): _act("POST", "/api/communities/%d/roles" % cid, {"name": rname.text.strip_edges(), "rank": int(rrank.value), "perms": ["post"]}))
	add_row.add_child(radd)
	v.add_child(add_row)

	# Channels.
	v.add_child(UI.label(L.t("cm_channels"), 20, UI.TEXT, "bold"))
	var chans: Array = _c.get("channels", [])
	for i in chans.size():
		var ch: Dictionary = chans[i]
		var row := UI.hbox(8)
		var cn := UI.label("# " + str(ch.name), 17, UI.TEXT, "bold")
		cn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(cn)
		# Order in the list: up and down one place.
		for step in [-1, 1]:
			var mv := UI.button("▲" if step < 0 else "▼", "ghost", 44)
			mv.custom_minimum_size.x = 44
			mv.tooltip_text = L.t("cm_move_up" if step < 0 else "cm_move_down")
			mv.disabled = i + step < 0 or i + step >= chans.size()
			var mid := int(ch.id)
			var to: int = i + step
			mv.pressed.connect(func(): _act("PATCH", "/api/communities/%d/channels/%d" % [cid, mid], {"position": to}))
			row.add_child(mv)
		var pr := SpinBox.new()
		pr.min_value = 1
		pr.max_value = 255
		pr.value = int(ch.post_rank)
		pr.prefix = L.t("cm_post_rank")
		var chid := int(ch.id)
		pr.value_changed.connect(func(val): Api.request("PATCH", "/api/communities/%d/channels/%d" % [cid, chid], {"post_rank": int(val)}))
		row.add_child(pr)
		var del := UI.button("✕", "ghost", 44)
		del.custom_minimum_size.x = 48
		del.pressed.connect(func():
			if await UI.confirm(self, L.t("cm_delete_channel_q", [str(ch.name)]), "", L.t("delete"), true):
				_act("DELETE", "/api/communities/%d/channels/%d" % [cid, chid]))
		row.add_child(del)
		v.add_child(row)
	var cadd_row := UI.hbox(8)
	var cname := UI.input(L.t("cm_channel_name"))
	cname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cadd_row.add_child(cname)
	var cadd := UI.button(L.t("cm_add"), "ghost", 52)
	cadd.pressed.connect(func(): _act("POST", "/api/communities/%d/channels" % cid, {"name": cname.text.strip_edges()}))
	cadd_row.add_child(cadd)
	v.add_child(cadd_row)

	if my_rank >= 255:
		var del := UI.button(L.t("cm_delete"), "danger", 48)
		del.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		del.pressed.connect(func():
			if await UI.confirm(self, L.t("cm_delete_q", [str(_c.name)]), L.t("cm_delete_text"), L.t("delete"), true):
				var r := await Api.request("DELETE", "/api/communities/%d" % cid)
				if r.ok:
					_show_list()
				else:
					UI.toast(r.message, "error"))
		v.add_child(del)


func _role_row(role: Dictionary, my_rank: int) -> Control:
	var card := UI.card(12, UI.BG_2, 16)
	var col := UI.vbox(8)
	card.add_child(col)
	var editable := int(role.rank) < my_rank
	var top := UI.hbox(8)
	var rn := UI.label("%s  ·  %s%d" % [role_name(role.name), L.t("cm_rank"), int(role.rank)], 17, UI.TEXT, "bold")
	rn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(rn)
	var rid := int(role.id)
	if editable and int(role.rank) > 1:
		var del := UI.button("✕", "ghost", 38)
		del.custom_minimum_size.x = 42
		del.pressed.connect(func():
			if await UI.confirm(self, L.t("cm_delete_role_q", [role_name(role.name)]), L.t("cm_delete_role_text"), L.t("delete"), true):
				_act("DELETE", "/api/communities/%d/roles/%d" % [int(_c.id), rid]))
		top.add_child(del)
	col.add_child(top)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	var have: Array = role.get("perms", []).duplicate()
	for p in PERMS:
		var b := UI.button(L.t("cm_perm_" + p), "flat", 36)
		b.theme_type_variation = "ChipButton"
		b.toggle_mode = true
		b.button_pressed = p in have
		b.disabled = not editable
		b.add_theme_font_size_override("font_size", 14)
		b.tooltip_text = L.t("cm_perm_" + p + "_hint")
		b.toggled.connect(func(on: bool):
			if on and not (p in have):
				have.append(p)
			elif not on:
				have.erase(p)
			var r := await Api.request("PATCH", "/api/communities/%d/roles/%d" % [int(_c.id), rid], {"perms": have})
			if not r.ok:
				UI.toast(r.message, "error"))
		chips.add_child(b)
	col.add_child(chips)
	return card
