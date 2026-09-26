class_name HomePage
extends ScrollContainer
## Home: friends who are online, and the grid of places to play.

var _places_box: HFlowContainer
var _people_section: Control
var _people_box: HBoxContainer
var _friends_box: HBoxContainer
var _friends_section: Control
var _friends_count: Label
var _recent_section: Control
var _recent_box: HBoxContainer
var _search: LineEdit
var _search_timer: Timer
var _timer: Timer
var _loading := false
var _loaded_once := false
var _search_spinner: Control


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var root := UI.vbox(22)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(root)

	var head_row := UI.hbox(12)
	var head := UI.vbox(2)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(UI.label(L.t("hello_name", [Session.user.get("display_name", "")]), 34, UI.TEXT, "black"))
	head.add_child(UI.label(L.t("home_sub"), 19, UI.MUTED))
	head_row.add_child(head)
	# Pieces and orbs: tap to buy pieces or see today's quests.
	var chips := Economy.chips(self)
	chips.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head_row.add_child(chips)
	root.add_child(head_row)

	_friends_section = UI.vbox(10)
	var fh := UI.hbox(8)
	fh.add_child(UI.label(L.t("nav_friends"), 24, UI.TEXT, "black"))
	_friends_count = UI.label("", 18, UI.MUTED, "bold")
	fh.add_child(_friends_count)
	_friends_section.add_child(fh)
	var fscroll := ScrollContainer.new()
	fscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	fscroll.custom_minimum_size.y = 128
	_friends_box = UI.hbox(14)
	fscroll.add_child(_friends_box)
	_friends_section.add_child(fscroll)
	root.add_child(_friends_section)
	# Until the first answer: round placeholders where friends will be.
	for i in 5:
		var sk := UI.vbox(6)
		sk.add_child(Loading.skeleton(Vector2(74, 74), 37))
		sk.add_child(Loading.skeleton(Vector2(74, 14), 7))
		_friends_box.add_child(sk)

	# Recently played: small square icons, lighter than the big place cards.
	_recent_section = UI.vbox(10)
	_recent_section.add_child(UI.label(L.t("recently_played"), 24, UI.TEXT, "black"))
	var rscroll := ScrollContainer.new()
	rscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rscroll.custom_minimum_size.y = 150
	_recent_box = UI.hbox(14)
	rscroll.add_child(_recent_box)
	_recent_section.add_child(rscroll)
	_recent_section.visible = false
	root.add_child(_recent_section)

	var ph := UI.hbox(12)
	var pt := UI.label(L.t("places"), 24, UI.TEXT, "black")
	pt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ph.add_child(pt)
	_search_spinner = Loading.spinner(28)
	_search_spinner.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_search_spinner.visible = false
	ph.add_child(_search_spinner)
	_search = UI.input(L.t("search_everything"))
	_search.custom_minimum_size = Vector2(260 if UI.is_compact() else 320, 48)
	_search.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_search.text_changed.connect(func(_t): _search_timer.start())
	ph.add_child(_search)
	root.add_child(ph)
	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.wait_time = 0.3
	_search_timer.timeout.connect(refresh_data)
	add_child(_search_timer)
	# Players matching the search, shown above the places.
	_people_section = UI.vbox(10)
	_people_section.add_child(UI.label(L.t("players"), 20, UI.MUTED, "bold"))
	var pscroll := ScrollContainer.new()
	pscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pscroll.custom_minimum_size.y = 128
	_people_box = UI.hbox(14)
	pscroll.add_child(_people_box)
	_people_section.add_child(pscroll)
	_people_section.visible = false
	root.add_child(_people_section)
	_places_box = HFlowContainer.new()
	_places_box.add_theme_constant_override("h_separation", 18)
	_places_box.add_theme_constant_override("v_separation", 18)
	root.add_child(_places_box)
	for i in 3:
		_places_box.add_child(Loading.place_card_skeleton())

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
	var q := _search.text.strip_edges() if _search else ""
	_search_spinner.visible = _loaded_once
	var pr := await Api.request("GET", "/api/places" + ("?q=" + q.uri_encode() if q != "" else ""))
	var fr := await Api.request("GET", "/api/friends")
	var rr := await Api.request("GET", "/api/me/recent") if q == "" else {}
	var ur: Dictionary = {}
	if q.length() >= 2:
		ur = await Api.request("GET", "/api/users/search?q=" + q.uri_encode())
	_loading = false
	if not is_inside_tree():
		return
	_search_spinner.visible = false
	_render_people(ur.data.users if ur.get("ok", false) else [])
	if pr.ok:
		_loaded_once = true
		_render_places(pr.data.places)
	elif not _loaded_once:
		# First load failed: say so instead of leaving placeholders forever.
		for c in _places_box.get_children():
			c.queue_free()
		_places_box.add_child(Loading.error_block(pr.message, refresh_data))
		_friends_section.visible = false
	if rr.get("ok", false):
		_render_recent(rr.data.places)
	if fr.ok:
		_render_friends(fr.data.friends)
		_menu().set_request_badge(fr.data.incoming.size())


func _render_places(places: Array) -> void:
	for c in _places_box.get_children():
		c.queue_free()
	if places.is_empty():
		_places_box.add_child(UI.label(L.t("no_places_found"), 18, UI.MUTED))
	for p in places:
		_places_box.add_child(place_card(p, func(): _menu().open_place(str(p.id))))


## Card used on Home: cover, name, author, rating and players online.
static func place_card(p: Dictionary, on_open: Callable) -> Control:
	var c := UI.card(12, UI.CARD, 22)
	c.custom_minimum_size.x = 330
	var v := UI.vbox(8)
	c.add_child(v)
	var cover := RoundedImage.new(PlacePage.cover_for(p), 16)
	if cover.texture == null:
		# Studio places: covers come from the server.
		AssetCache.fetch(str(p.get("cover", "")), func(tex: Texture2D):
			if tex and is_instance_valid(cover):
				PlacePage._cover_cache[str(p.id)] = tex
				cover.texture = tex)
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
	# Long names wrap to two lines and end with "…" instead of widening the card.
	var title := UI.label(L.field(p, "name"), 22, UI.TEXT, "black")
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.max_lines_visible = 2
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.custom_minimum_size.x = 294
	info.add_child(title)
	var author: Dictionary = p.get("author", {})
	var by := UI.hbox(6)
	by.mouse_filter = Control.MOUSE_FILTER_IGNORE
	by.clip_contents = true
	by.custom_minimum_size.x = 294
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


func _render_people(users: Array) -> void:
	for c in _people_box.get_children():
		c.queue_free()
	_people_section.visible = not users.is_empty()
	for u in users:
		# Strangers open their profile; only friends are joined with one tap.
		_people_box.add_child(_friend_chip(u, str(u.get("relation", "")) == "friends"))


## Carousel of all friends: playing first, then online, then offline.
## Tapping someone who is playing joins them; anyone else opens their profile.
func _render_friends(friends: Array) -> void:
	for c in _friends_box.get_children():
		c.queue_free()
	_friends_section.visible = friends.size() > 0
	var online := friends.filter(func(f): return f.online).size()
	_friends_count.text = L.t("friends_online_n", [online, friends.size()])
	var ordered := friends.duplicate()
	ordered.sort_custom(func(a, b):
		var ra := 2 if a.get("playing") is Dictionary else (1 if a.online else 0)
		var rb := 2 if b.get("playing") is Dictionary else (1 if b.online else 0)
		if ra != rb:
			return ra > rb
		return str(a.display_name) < str(b.display_name))
	for f in ordered:
		_friends_box.add_child(_friend_chip(f))


func _friend_chip(f: Dictionary, can_join := true) -> Control:
	var playing: Variant = f.get("playing") if can_join else null
	var v := UI.vbox(4)
	v.custom_minimum_size.x = 92
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	var ring := PanelContainer.new()
	ring.mouse_filter = Control.MOUSE_FILTER_PASS
	ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_corner_radius_all(40)
	sb.set_border_width_all(4)
	sb.border_color = UI.MINT if playing is Dictionary else (UI.ONLINE if f.online else Color(0, 0, 0, 0))
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	ring.add_theme_stylebox_override("panel", sb)
	var bust := UI.avatar_badge(f, 66)
	if not f.online:
		bust.modulate = Color(1, 1, 1, 0.5)
	ring.add_child(bust)
	v.add_child(ring)
	var name := UI.label(str(f.display_name), 14, UI.TEXT if f.online else UI.MUTED, "bold")
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.clip_text = true
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.custom_minimum_size.x = 92
	v.add_child(name)
	if playing is Dictionary:
		var join := UI.label(L.t("join"), 13, UI.MINT, "black")
		join.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(join)
		UI.on_tap(v, func(): _menu().play(str(playing.server_id), str(playing.get("game", "playground"))))
	else:
		UI.on_tap(v, func(): _menu().show_profile(str(f.username)))
	return v


func _render_recent(places: Array) -> void:
	_recent_section.visible = not places.is_empty()
	var ids := places.map(func(p): return str(p.id))
	# Same list as before: keep the tiles (and their images) as they are.
	if ids == _recent_box.get_meta("ids", []):
		return
	_recent_box.set_meta("ids", ids)
	for c in _recent_box.get_children():
		c.queue_free()
	for p in places:
		_recent_box.add_child(_recent_tile(p))


func _recent_tile(p: Dictionary) -> Control:
	var tile := UI.vbox(6)
	tile.custom_minimum_size.x = 112
	var img := RoundedImage.new(null, 20)
	img.custom_minimum_size = Vector2(112, 112)
	tile.add_child(img)
	var id := str(p.id)
	var local: String = PlacePage.LOCAL_SQUARES.get(id, "")
	if local != "":
		img.texture = load(local)
	elif str(p.get("cover_square", "")) != "":
		AssetCache.fetch(str(p.cover_square), func(t):
			if is_instance_valid(img):
				img.texture = t)
	else:
		# No 1:1 icon: the middle of the wide cover.
		AssetCache.fetch(str(p.get("cover", "")), func(t: Texture2D):
			if t and is_instance_valid(img):
				img.texture = _square_crop(t))
	var name := UI.label(L.field(p, "name"), 15, UI.TEXT, "bold")
	name.custom_minimum_size.x = 112
	name.clip_text = true
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tile.add_child(name)
	UI.on_tap(tile, func(): _menu().open_place(id))
	return tile


static func _square_crop(t: Texture2D) -> Texture2D:
	var im := t.get_image()
	if im == null:
		return t
	var side := mini(im.get_width(), im.get_height())
	var rect := Rect2i((im.get_width() - side) / 2, (im.get_height() - side) / 2, side, side)
	return ImageTexture.create_from_image(im.get_region(rect))
