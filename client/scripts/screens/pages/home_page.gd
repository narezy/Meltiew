class_name HomePage
extends ScrollContainer
## Home: featured playground, live server browser, friends who are online.

var _online_label: Label
var _servers_box: VBoxContainer
var _friends_box: HBoxContainer
var _friends_section: Control
var _timer: Timer
var _loading := false


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var root := UI.vbox(22)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(root)

	var head := UI.vbox(2)
	head.add_child(UI.label("Привет, %s!" % Session.user.get("display_name", ""), 34, UI.TEXT, "black"))
	head.add_child(UI.label("Во что сегодня играем? Пока выбор простой, но очень весёлый.", 19, UI.MUTED))
	root.add_child(head)

	root.add_child(_build_hero())

	_friends_section = UI.vbox(12)
	_friends_section.add_child(UI.label("Друзья онлайн", 24, UI.TEXT, "black"))
	var fscroll := ScrollContainer.new()
	fscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	fscroll.custom_minimum_size.y = 124
	_friends_box = UI.hbox(12)
	fscroll.add_child(_friends_box)
	_friends_section.add_child(fscroll)
	_friends_section.visible = false
	root.add_child(_friends_section)

	var sh := UI.hbox(12)
	sh.add_child(UI.label("Серверы площадки", 24, UI.TEXT, "black"))
	sh.add_child(UI.spacer())
	var refresh := UI.button("", "ghost", 48)
	refresh.custom_minimum_size.x = 48
	var ric := Icon.make("refresh", 22)
	ric.set_anchors_preset(Control.PRESET_CENTER)
	ric.position = Vector2(-11, -11)
	refresh.add_child(ric)
	refresh.pressed.connect(refresh_data)
	sh.add_child(refresh)
	var create := UI.button("  Новый сервер", "ghost", 48)
	create.icon = null
	create.pressed.connect(func(): _menu().play("new"))
	sh.add_child(create)
	root.add_child(sh)
	_servers_box = UI.vbox(10)
	root.add_child(_servers_box)
	_servers_box.add_child(_empty_row("Загружаем серверы..."))

	_timer = Timer.new()
	_timer.wait_time = 8.0
	_timer.autostart = true
	_timer.timeout.connect(refresh_data)
	add_child(_timer)
	refresh_data()


func _menu() -> Node:
	return get_meta("menu")


func refresh() -> void:
	refresh_data()


func _build_hero() -> Control:
	var hero := UI.card(16, UI.CARD, 26)
	var row := UI.hbox(24)
	hero.add_child(row)
	var cover_tex: Texture2D = load("res://assets/playground_cover.png") if ResourceLoader.exists("res://assets/playground_cover.png") else null
	var cover := RoundedImage.new(cover_tex, 20)
	cover.custom_minimum_size = Vector2(420, 236)
	row.add_child(cover)
	var info := UI.vbox(10)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(info)
	var tag := UI.label("ЕДИНСТВЕННАЯ И ЛУЧШАЯ", 14, UI.ACCENT, "black")
	info.add_child(tag)
	info.add_child(UI.label("Детская площадка", 32, UI.TEXT, "black"))
	var desc := UI.label("Горки, качели, батуты, карусель и паркур над облаками. До 10 игроков на сервер.", 18, UI.MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(desc)
	var stat := UI.hbox(8)
	stat.add_child(UI.dot(UI.ONLINE, 10))
	_online_label = UI.label("...", 17, UI.TEXT, "bold")
	stat.add_child(_online_label)
	info.add_child(stat)
	var buttons := UI.hbox(12)
	var play := UI.button("Играть", "primary", 60)
	play.custom_minimum_size.x = 200
	var pic := Icon.make("play", 20, UI.INK)
	pic.position = Vector2(26, 20)
	play.add_child(pic)
	play.add_theme_constant_override("h_separation", 0)
	play.text = "    Играть"
	play.pressed.connect(func(): _menu().play("auto"))
	buttons.add_child(play)
	info.add_child(buttons)
	return hero


func _empty_row(text: String) -> Control:
	var c := UI.card(22, Color(UI.CARD, 0.6), 20)
	var l := UI.label(text, 18, UI.MUTED)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(l)
	return c


func refresh_data() -> void:
	if _loading:
		return
	_loading = true
	var sr := await Api.request("GET", "/api/servers?game=playground")
	var fr := await Api.request("GET", "/api/friends")
	_loading = false
	if not is_inside_tree():
		return
	if sr.ok:
		_render_servers(sr.data.servers)
	else:
		for c in _servers_box.get_children():
			c.queue_free()
		_servers_box.add_child(_empty_row(sr.message))
	if fr.ok:
		_render_friends(fr.data.friends)
		_menu().set_request_badge(fr.data.incoming.size())


func _render_servers(servers: Array) -> void:
	for c in _servers_box.get_children():
		c.queue_free()
	var total := 0
	for s in servers:
		total += int(s.players)
	_online_label.text = "%d %s сейчас на площадке" % [total, _plural(total, "игрок", "игрока", "игроков")]
	if servers.is_empty():
		_servers_box.add_child(_empty_row("Пока ни одного сервера. Жми «Играть», и первый будет твоим."))
		return
	for s in servers:
		_servers_box.add_child(_server_row(s))


func _server_row(s: Dictionary) -> Control:
	var c := UI.card(16, UI.CARD, 20)
	var row := UI.hbox(16)
	c.add_child(row)
	var col := UI.vbox(4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UI.label(str(s.name), 20, UI.TEXT, "bold"))
	var friends: Array = s.get("friends", [])
	var sub := "Здесь друзья: " + ", ".join(friends) if friends.size() > 0 else "Сервер #" + str(s.id)
	col.add_child(UI.label(sub, 16, UI.MINT if friends.size() > 0 else UI.MUTED))
	row.add_child(col)

	var players := int(s.players)
	var max_p := int(s.max_players)
	var meter := UI.vbox(6)
	meter.custom_minimum_size.x = 160
	meter.alignment = BoxContainer.ALIGNMENT_CENTER
	var ml := UI.label("%d / %d" % [players, max_p], 17, UI.TEXT, "bold")
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	meter.add_child(ml)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = max_p
	bar.value = players
	bar.custom_minimum_size.y = 10
	var bg := StyleBoxFlat.new()
	bg.bg_color = UI.BG_2
	bg.set_corner_radius_all(5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UI.DANGER if players >= max_p else UI.ACCENT
	fill.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	meter.add_child(bar)
	row.add_child(meter)

	var full := players >= max_p
	var join := UI.button("Полный" if full else "Войти", "ghost" if full else "mint", 52)
	join.custom_minimum_size.x = 130
	join.disabled = full
	join.pressed.connect(func(): _menu().play(str(s.id)))
	row.add_child(join)
	return c


func _render_friends(friends: Array) -> void:
	for c in _friends_box.get_children():
		c.queue_free()
	var online := friends.filter(func(f): return f.online)
	_friends_section.visible = online.size() > 0
	for f in online:
		var c := UI.card(14, UI.CARD, 20)
		c.custom_minimum_size.x = 250
		var row := UI.hbox(12)
		c.add_child(row)
		row.add_child(UI.avatar_badge(f, 50))
		var col := UI.vbox(2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nl := UI.label(str(f.display_name), 18, UI.TEXT, "bold")
		nl.clip_text = true
		col.add_child(nl)
		var playing: Variant = f.get("playing")
		if playing is Dictionary:
			col.add_child(UI.label("На площадке", 15, UI.MINT))
			var join := UI.button("Зайти", "mint", 36)
			join.add_theme_font_size_override("font_size", 16)
			join.pressed.connect(func(): _menu().play(str(playing.server_id)))
			col.add_child(join)
		else:
			col.add_child(UI.label("В меню", 15, UI.ONLINE))
		row.add_child(col)
		UI.on_tap(c, func(): _menu().show_profile(str(f.username)))
		_friends_box.add_child(c)


static func _plural(n: int, one: String, few: String, many: String) -> String:
	var m10 := n % 10
	var m100 := n % 100
	if m10 == 1 and m100 != 11:
		return one
	if m10 >= 2 and m10 <= 4 and (m100 < 10 or m100 >= 20):
		return few
	return many
