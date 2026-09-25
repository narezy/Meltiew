class_name FriendsPage
extends VBoxContainer
## Friends: search players, handle requests, see who is online or playing.

var _search: LineEdit
var _list: VBoxContainer
var _search_timer: Timer
var _mode := "friends"
var _data := {"friends": [], "incoming": [], "outgoing": []}
var _tab_buttons := {}


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 18)

	var head := UI.hbox(16)
	var title := UI.vbox(2)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(UI.label("Друзья", 34, UI.TEXT, "black"))
	title.add_child(UI.label("Найди друзей по нику и играйте на одном сервере", 19, UI.MUTED))
	head.add_child(title)
	add_child(head)

	var search_row := UI.hbox(12)
	_search = UI.input("Поиск игроков по нику или логину")
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.right_icon = null
	search_row.add_child(_search)
	add_child(search_row)
	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.wait_time = 0.35
	_search_timer.timeout.connect(_do_search)
	add_child(_search_timer)
	_search.text_changed.connect(func(_t): _search_timer.start())
	_search.text_submitted.connect(func(_t): _do_search())

	var tabs := UI.hbox(8)
	for t in [["friends", "Мои друзья"], ["incoming", "Заявки"], ["outgoing", "Отправленные"]]:
		var b := UI.button(t[1], "flat", 44)
		b.theme_type_variation = "ChipButton"
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(func(): _set_mode(t[0]))
		tabs.add_child(b)
		_tab_buttons[t[0]] = b
	add_child(tabs)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = UI.vbox(10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	add_child(scroll)

	var t := Timer.new()
	t.wait_time = 10.0
	t.autostart = true
	t.timeout.connect(func():
		if _search.text.strip_edges() == "":
			refresh())
	add_child(t)
	_set_mode("friends")
	refresh()


func _menu() -> Node:
	return get_meta("menu")


func _set_mode(mode: String) -> void:
	_mode = mode
	for k in _tab_buttons:
		_tab_buttons[k].button_pressed = k == mode
	if _search.text.strip_edges() != "":
		_search.text = ""
	_render()


func refresh() -> void:
	var r := await Api.request("GET", "/api/friends")
	if not is_inside_tree():
		return
	if not r.ok:
		UI.toast(r.message, "error")
		return
	_data = r.data
	var n: int = _data.incoming.size()
	_tab_buttons.incoming.text = "Заявки" + (" (%d)" % n if n > 0 else "")
	_menu().set_request_badge(n)
	if _search.text.strip_edges() == "":
		_render()


func _clear() -> void:
	for c in _list.get_children():
		c.queue_free()


func _empty(text: String) -> void:
	var c := UI.card(26, Color(UI.CARD, 0.6), 20)
	var l := UI.label(text, 18, UI.MUTED)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.add_child(l)
	_list.add_child(c)


func _render() -> void:
	_clear()
	var items: Array = _data.get(_mode, [])
	if items.is_empty():
		match _mode:
			"friends":
				_empty("Пока друзей нет. Найди кого-нибудь через поиск сверху!")
			"incoming":
				_empty("Новых заявок нет")
			_:
				_empty("Ты никому не отправлял(а) заявок")
		return
	for u in items:
		_list.add_child(_row(u, {"friends": "friends", "incoming": "incoming", "outgoing": "outgoing"}[_mode]))


func _do_search() -> void:
	var q := _search.text.strip_edges()
	if q.length() < 2:
		_render()
		return
	var r := await Api.request("GET", "/api/users/search?q=" + q.uri_encode())
	if not is_inside_tree() or _search.text.strip_edges() != q:
		return
	_clear()
	if not r.ok:
		_empty(r.message)
		return
	if r.data.users.is_empty():
		_empty("Никого не нашли по запросу «%s»" % q)
		return
	for u in r.data.users:
		_list.add_child(_row(u, str(u.get("relation", "none"))))


static func status_text(u: Dictionary) -> Array:
	var playing: Variant = u.get("playing")
	if playing is Dictionary:
		return ["Играет: " + str(playing.get("server_name", "площадка")), UI.MINT]
	if u.get("online", false):
		return ["В сети", UI.ONLINE]
	return ["Не в сети", UI.MUTED]


func _row(u: Dictionary, relation: String) -> Control:
	var c := UI.card(14, UI.CARD, 20)
	var row := UI.hbox(14)
	c.add_child(row)
	var badge := UI.avatar_badge(u, 54)
	row.add_child(badge)
	var col := UI.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_row := UI.hbox(8)
	name_row.add_child(UI.label(str(u.display_name), 20, UI.TEXT, "bold"))
	name_row.add_child(UI.label("@" + str(u.username), 16, UI.MUTED))
	col.add_child(name_row)
	var st := status_text(u)
	var srow := UI.hbox(8)
	srow.add_child(UI.dot(st[1], 9))
	srow.add_child(UI.label(st[0], 16, st[1]))
	col.add_child(srow)
	row.add_child(col)

	UI.on_tap(c, func(): _menu().show_profile(str(u.username)))

	match relation:
		"friends":
			var playing: Variant = u.get("playing")
			if playing is Dictionary:
				var join := UI.button("Присоединиться", "mint", 50)
				join.pressed.connect(func(): _menu().play(str(playing.server_id)))
				row.add_child(join)
			var rm := UI.button("Удалить", "ghost", 50)
			rm.pressed.connect(func(): _remove(u))
			row.add_child(rm)
		"incoming":
			var ok := UI.button("Принять", "mint", 50)
			ok.pressed.connect(func(): _act("/api/friends/accept", u, "Теперь вы друзья с %s" % u.display_name))
			row.add_child(ok)
			var no := UI.button("Отклонить", "ghost", 50)
			no.pressed.connect(func(): _act("/api/friends/remove", u, ""))
			row.add_child(no)
		"outgoing":
			var cancel := UI.button("Отменить", "ghost", 50)
			cancel.pressed.connect(func(): _act("/api/friends/remove", u, "Заявка отменена"))
			row.add_child(cancel)
		_:
			var add := UI.button("Добавить", "primary", 50)
			add.pressed.connect(func(): _act("/api/friends/request", u, "Заявка отправлена"))
			row.add_child(add)
	return c


func _remove(u: Dictionary) -> void:
	var yes: bool = await UI.confirm(self, "Удалить из друзей?", "%s пропадёт из списка друзей." % u.display_name, "Удалить", true)
	if yes:
		_act("/api/friends/remove", u, "Удалено")


func _act(path: String, u: Dictionary, ok_text: String) -> void:
	var r := await Api.request("POST", path, {"user_id": u.id})
	if not is_inside_tree():
		return
	if not r.ok:
		UI.toast(r.message, "error")
		return
	if r.data.get("relation") == "friends" and path == "/api/friends/request":
		ok_text = "У вас была встречная заявка, теперь вы друзья!"
	if ok_text != "":
		UI.toast(ok_text, "ok")
		Sfx.play("pop")
	await refresh()
	if _search.text.strip_edges() != "":
		_do_search()
