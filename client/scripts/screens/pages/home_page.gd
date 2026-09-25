class_name HomePage
extends ScrollContainer
## Home: friends who are online, and the grid of places to play.

var _places_box: HFlowContainer
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
	head.add_child(UI.label(L.t("hello_name", [Session.user.get("display_name", "")]), 34, UI.TEXT, "black"))
	head.add_child(UI.label(L.t("home_sub"), 19, UI.MUTED))
	root.add_child(head)

	_friends_section = UI.vbox(12)
	_friends_section.add_child(UI.label(L.t("friends_online"), 24, UI.TEXT, "black"))
	var fscroll := ScrollContainer.new()
	fscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	fscroll.custom_minimum_size.y = 124
	_friends_box = UI.hbox(12)
	fscroll.add_child(_friends_box)
	_friends_section.add_child(fscroll)
	_friends_section.visible = false
	root.add_child(_friends_section)

	root.add_child(UI.label(L.t("places"), 24, UI.TEXT, "black"))
	_places_box = HFlowContainer.new()
	_places_box.add_theme_constant_override("h_separation", 18)
	_places_box.add_theme_constant_override("v_separation", 18)
	root.add_child(_places_box)

	_timer = Timer.new()
	_timer.wait_time = 10.0
	_timer.autostart = true
	_timer.timeout.connect(refresh_data)
	add_child(_timer)
	refresh_data()


func _menu() -> Node:
	return get_meta("menu")


func refresh() -> void:
	refresh_data()


func refresh_data() -> void:
	if _loading:
		return
	_loading = true
	var pr := await Api.request("GET", "/api/places")
	var fr := await Api.request("GET", "/api/friends")
	_loading = false
	if not is_inside_tree():
		return
	if pr.ok:
		_render_places(pr.data.places)
	if fr.ok:
		_render_friends(fr.data.friends)
		_menu().set_request_badge(fr.data.incoming.size())


func _render_places(places: Array) -> void:
	for c in _places_box.get_children():
		c.queue_free()
	for p in places:
		_places_box.add_child(place_card(p, func(): _menu().open_place(str(p.id))))


## Card used on Home: cover, name, author, rating and players online.
static func place_card(p: Dictionary, on_open: Callable) -> Control:
	var c := UI.card(12, UI.CARD, 22)
	c.custom_minimum_size.x = 330
	var v := UI.vbox(8)
	c.add_child(v)
	var cover := RoundedImage.new(PlacePage.cover_for(p), 16)
	cover.custom_minimum_size = Vector2(306, 172)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(cover)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 6)
	pad.add_theme_constant_override("margin_right", 6)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pad)
	var info := UI.vbox(4)
	pad.add_child(info)
	info.add_child(UI.label(L.field(p, "name"), 22, UI.TEXT, "black"))
	var author: Dictionary = p.get("author", {})
	var by := UI.hbox(6)
	by.mouse_filter = Control.MOUSE_FILTER_IGNORE
	by.add_child(UI.label(L.t("by"), 15, UI.MUTED))
	by.add_child(UI.name_row(author, 15, UI.MUTED, "bold"))
	info.add_child(by)
	var stats := UI.hbox(14)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_child(_stat_chip("heart", PlacePage.rating_text(p)))
	stats.add_child(_stat_chip("users", L.t("n_playing", [int(p.playing)])))
	info.add_child(stats)
	UI.on_tap(c, on_open)
	return c


static func _stat_chip(icon: String, text: String) -> Control:
	var h := UI.hbox(6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(Icon.make(icon, 16, UI.MUTED))
	h.add_child(UI.label(text, 15, UI.MUTED, "bold"))
	return h


func _render_friends(friends: Array) -> void:
	for c in _friends_box.get_children():
		c.queue_free()
	var online := friends.filter(func(f): return f.online)
	_friends_section.visible = online.size() > 0
	for f in online:
		var c := UI.card(14, UI.CARD, 20)
		c.custom_minimum_size.x = 260
		var row := UI.hbox(12)
		c.add_child(row)
		row.add_child(UI.avatar_badge(f, 50))
		var col := UI.vbox(2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(UI.name_row(f, 18))
		var playing: Variant = f.get("playing")
		if playing is Dictionary:
			col.add_child(UI.label(L.t("playing_on", [L.field(playing, "server_name")]), 14, UI.MINT))
			var join := UI.button(L.t("join"), "mint", 36)
			join.add_theme_font_size_override("font_size", 16)
			join.pressed.connect(func(): _menu().play(str(playing.server_id)))
			col.add_child(join)
		else:
			col.add_child(UI.label(L.t("in_menu"), 15, UI.ONLINE))
		row.add_child(col)
		UI.on_tap(c, func(): _menu().show_profile(str(f.username)))
		_friends_box.add_child(c)
