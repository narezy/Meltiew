class_name PlacePage
extends ScrollContainer
## A place's page: cover, author, rating (likes/dislikes), stats, Play, and servers at the bottom.

const LOCAL_COVERS := {"playground": "res://assets/playground_cover.png"}
const LOCAL_SQUARES := {"playground": "res://assets/playground_square.png"}

static var _cover_cache := {}

var place_id := "playground"
var _place: Dictionary = {}
var _root: VBoxContainer
var _vote_box: HBoxContainer
var _servers_box: VBoxContainer
var _comments_box: VBoxContainer
var _comments: Array = []
var _comments_more := false
var _stats_box: HFlowContainer
var _cover: RoundedImage
var _timer: Timer


static func cover_for(p: Dictionary) -> Texture2D:
	var id := str(p.get("id", ""))
	if LOCAL_COVERS.has(id):
		return load(LOCAL_COVERS[id])
	return _cover_cache.get(id)


static func rating_text(p: Dictionary) -> String:
	var likes := int(p.get("likes", 0))
	var total := likes + int(p.get("dislikes", 0))
	if total == 0:
		return "—"
	return "%d%%" % roundi(100.0 * likes / total)


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root = UI.vbox(20)
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_root)
	_root.add_child(Loading.block(L.t("loading")))
	_timer = Timer.new()
	_timer.wait_time = 8.0
	_timer.autostart = true
	_timer.timeout.connect(_load)
	add_child(_timer)
	_load()


func _menu() -> Node:
	return get_meta("menu")


func refresh() -> void:
	_load()


func _load() -> void:
	var r := await Api.request("GET", "/api/places/" + place_id.uri_encode())
	if not is_inside_tree():
		return
	if not r.ok:
		if _place.is_empty():
			for c in _root.get_children():
				c.queue_free()
			_root.add_child(Loading.error_block(r.message, func():
				for c in _root.get_children():
					c.queue_free()
				_root.add_child(Loading.block(L.t("loading")))
				_load()))
		else:
			UI.toast(r.message, "error")
		return
	var first := _place.is_empty()
	_place = r.data.place
	if first:
		_build()
	_render_stats()
	_render_votes()
	_render_servers(r.data.servers)


func _build() -> void:
	for c in _root.get_children():
		c.queue_free()
	var back := UI.button("", "flat", 44)
	back.text = "   " + L.t("back")
	back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var bi := Icon.make("back", 20, UI.MUTED)
	bi.position = Vector2(12, 12)
	back.add_child(bi)
	back.pressed.connect(func(): _menu().open_page("home"))
	_root.add_child(back)

	var top := UI.hbox(26)
	_root.add_child(top)
	_cover = RoundedImage.new(cover_for(_place), 22)
	_cover.custom_minimum_size = Vector2(320, 180) if UI.is_compact() else Vector2(440, 248)
	_cover.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(_cover)
	if _cover.texture == null:
		_fetch_cover()

	var info := UI.vbox(12)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	# Square icon (1:1) next to the title when the place has one.
	var title_row := UI.hbox(14)
	var sq_path: String = LOCAL_SQUARES.get(place_id, "")
	if sq_path != "" or str(_place.get("cover_square", "")) != "":
		var sq := RoundedImage.new(load(sq_path) if sq_path != "" else null, 18)
		sq.custom_minimum_size = Vector2(84, 84)
		title_row.add_child(sq)
		if sq.texture == null:
			_fetch_image(str(_place.cover_square), sq)
	var title := UI.label(L.field(_place, "name"), 36, UI.TEXT, "black")
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	info.add_child(title_row)
	var author: Dictionary = _place.get("author", {})
	var by := UI.hbox(10)
	by.add_child(UI.label(L.t("by"), 17, UI.MUTED))
	if int(author.get("id", 0)) > 0:
		by.add_child(UI.avatar_badge(author, 34))
	by.add_child(UI.name_row(author, 18))
	info.add_child(by)
	if int(author.get("id", 0)) > 0:
		UI.on_tap(by, func(): _menu().show_profile(str(author.username)))
	_stats_box = HFlowContainer.new()
	_stats_box.add_theme_constant_override("h_separation", 10)
	_stats_box.add_theme_constant_override("v_separation", 8)
	info.add_child(_stats_box)
	_vote_box = UI.hbox(10)
	info.add_child(_vote_box)
	var play := UI.button("    " + L.t("play"), "primary", 64)
	play.add_theme_font_size_override("font_size", 24)
	var pic := Icon.make("play", 22, UI.INK)
	pic.position = Vector2(30, 21)
	play.add_child(pic)
	play.pressed.connect(func(): _menu().play("auto", place_id))
	info.add_child(play)
	var hint := UI.label(L.t("play_hint"), 14, UI.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(hint)
	if str(_place.get("kind", "")) == "studio" and int(author.get("id", 0)) != int(Session.user.get("id", -1)):
		var rep := UI.button(L.t("report_place_title"), "flat", 36)
		rep.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		rep.add_theme_color_override("font_color", UI.DANGER)
		rep.add_theme_font_size_override("font_size", 15)
		rep.pressed.connect(func(): UI.report(self, author, {"place_id": place_id}))
		info.add_child(rep)

	var about := UI.card(20, UI.CARD, 22)
	var av := UI.vbox(8)
	about.add_child(av)
	av.add_child(UI.label(L.t("about_place"), 22, UI.TEXT, "black"))
	var desc := UI.label(L.field(_place, "description"), 18, UI.TEXT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	av.add_child(desc)
	var created := Time.get_date_dict_from_unix_time(int(float(_place.get("created_at", 0)) / 1000.0))
	av.add_child(UI.label(L.t("created_on", ["%02d.%02d.%d" % [created.day, created.month, created.year]]), 15, UI.MUTED))
	_root.add_child(about)

	var sh := UI.hbox(12)
	sh.add_child(UI.label(L.t("servers_title"), 24, UI.TEXT, "black"))
	sh.add_child(UI.spacer())
	var create := UI.button(L.t("new_server"), "ghost", 48)
	create.pressed.connect(func(): _menu().play("new", place_id))
	sh.add_child(create)
	_root.add_child(sh)
	_servers_box = UI.vbox(10)
	_root.add_child(_servers_box)
	_comments_box = UI.vbox(10)
	_root.add_child(_comments_box)
	_load_comments()


func _fetch_image(url: String, target: TextureRect) -> void:
	if url == "":
		return
	if url.begins_with("/"):
		url = Api.BASE_URL + url
	var http := HTTPRequest.new()
	add_child(http)
	http.request(url)
	var res: Array = await http.request_completed
	http.queue_free()
	var img := Image.new()
	if res[1] == 200 and img.load_png_from_buffer(res[3]) == OK and is_instance_valid(target):
		target.texture = ImageTexture.create_from_image(img)


func _fetch_cover() -> void:
	var url := str(_place.get("cover", ""))
	if url == "":
		return
	if url.begins_with("/"):
		url = Api.BASE_URL + url
	var http := HTTPRequest.new()
	add_child(http)
	http.request(url)
	var res: Array = await http.request_completed
	http.queue_free()
	var img := Image.new()
	if res[1] == 200 and img.load_png_from_buffer(res[3]) == OK and is_instance_valid(_cover):
		var tex := ImageTexture.create_from_image(img)
		_cover_cache[place_id] = tex
		_cover.texture = tex


func _chip(icon: String, text: String, color := UI.TEXT) -> Control:
	var c := UI.card(0, UI.CARD_2, 14)
	var sb := c.get_theme_stylebox("panel") as StyleBoxFlat
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	var h := UI.hbox(8)
	h.add_child(Icon.make(icon, 18, color))
	h.add_child(UI.label(text, 16, color, "bold"))
	c.add_child(h)
	return c


func _render_stats() -> void:
	for c in _stats_box.get_children():
		c.queue_free()
	_stats_box.add_child(_chip("users", L.t("n_playing", [int(_place.playing)]), UI.ONLINE))
	_stats_box.add_child(_chip("eye", L.t("n_visits", [int(_place.visits)])))
	_stats_box.add_child(_chip("heart", L.t("rating", [rating_text(_place)]), UI.PINK))


func _render_votes() -> void:
	for c in _vote_box.get_children():
		c.queue_free()
	var mine := int(_place.get("my_vote", 0))
	for spec in [[1, "like", int(_place.likes)], [-1, "dislike", int(_place.dislikes)]]:
		var on: bool = mine == spec[0]
		var b := UI.button("      " + str(spec[2]), "flat", 50)
		b.theme_type_variation = "ChipButton"
		b.toggle_mode = true
		b.button_pressed = on
		b.custom_minimum_size.x = 110
		var ic := Icon.make(spec[1], 22, UI.INK if on else UI.TEXT)
		ic.position = Vector2(18, 14)
		b.add_child(ic)
		var value: int = 0 if on else spec[0]
		b.pressed.connect(func(): _vote(value))
		_vote_box.add_child(b)
	# Like ratio bar.
	var likes := float(_place.likes)
	var total := likes + float(_place.dislikes)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.value = likes / total if total > 0 else 0.0
	bar.custom_minimum_size = Vector2(140, 8)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = UI.DANGER if total > 0 else UI.CARD_2
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UI.ONLINE
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	_vote_box.add_child(bar)


func _vote(value: int) -> void:
	var r := await Api.request("POST", "/api/places/%s/vote" % place_id.uri_encode(), {"value": value})
	if not is_inside_tree():
		return
	if r.ok:
		_place = r.data.place
		Sfx.play("pop")
		_render_votes()
		_render_stats()
	else:
		UI.toast(r.message, "error")


func _render_servers(servers: Array) -> void:
	for c in _servers_box.get_children():
		c.queue_free()
	if servers.is_empty():
		var e := UI.card(22, Color(UI.CARD, 0.6), 20)
		var l := UI.label(L.t("no_servers"), 18, UI.MUTED)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		e.add_child(l)
		_servers_box.add_child(e)
		return
	for s in servers:
		_servers_box.add_child(_server_row(s))


func _server_row(s: Dictionary) -> Control:
	var c := UI.card(16, UI.CARD, 20)
	var row := UI.hbox(16)
	c.add_child(row)
	var col := UI.vbox(4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UI.label(L.field(s, "name"), 20, UI.TEXT, "bold"))
	var friends: Array = s.get("friends", [])
	var sub := L.t("friends_here", [", ".join(friends)]) if friends.size() > 0 else L.t("server_id", [s.id])
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
	var join := UI.button(L.t("full") if full else L.t("join"), "ghost" if full else "mint", 52)
	join.custom_minimum_size.x = 130
	join.disabled = full
	join.pressed.connect(func(): _menu().play(str(s.id), place_id))
	row.add_child(join)
	return c


# --- comments ------------------------------------------------------------------------

func _load_comments(more := false) -> void:
	var path := "/api/places/%s/comments" % place_id.uri_encode()
	if more and not _comments.is_empty():
		path += "?before=%d" % int(_comments[-1].id)
	var r := await Api.request("GET", path)
	if not is_inside_tree() or not r.ok:
		return
	var list: Array = r.data.comments
	_comments = _comments + list if more else list
	_comments_more = list.size() >= 30
	_render_comments(bool(r.data.enabled), bool(r.data.can_post))


func _render_comments(enabled: bool, can_post: bool) -> void:
	for c in _comments_box.get_children():
		c.queue_free()
	_comments_box.add_child(UI.label(L.t("comments"), 24, UI.TEXT, "black"))
	if not enabled:
		_comments_box.add_child(UI.label(L.t("comments_off"), 17, UI.MUTED))
		return
	if can_post:
		var row := UI.hbox(10)
		var input := UI.input(L.t("comment_placeholder"))
		input.max_length = 500
		input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(input)
		var send := UI.button(L.t("send"), "primary", 52)
		row.add_child(send)
		var post := func(_t = ""):
			var text := input.text.strip_edges()
			if text == "":
				return
			send.disabled = true
			var r := await Api.request("POST", "/api/places/%s/comments" % place_id.uri_encode(), {"text": text})
			send.disabled = false
			if not r.ok:
				UI.toast(r.message, "error")
				return
			_comments.push_front(r.data.comment)
			_render_comments(enabled, can_post)
		send.pressed.connect(post)
		input.text_submitted.connect(post)
		_comments_box.add_child(row)
	else:
		_comments_box.add_child(UI.label(L.t("comments_too_young"), 16, UI.MUTED))
	if _comments.is_empty():
		_comments_box.add_child(UI.label(L.t("no_comments"), 17, UI.MUTED))
	for c in _comments:
		_comments_box.add_child(_comment_row(c, enabled, can_post))
	if _comments_more:
		var more := UI.button(L.t("load_more"), "ghost", 44)
		more.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		more.pressed.connect(func(): _load_comments(true))
		_comments_box.add_child(more)


func _comment_row(c: Dictionary, enabled: bool, can_post: bool) -> Control:
	var card := UI.card(16, UI.CARD, 16)
	var row := UI.hbox(12)
	card.add_child(row)
	var author: Dictionary = c.author
	var badge := UI.avatar_badge(author, 40)
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(badge)
	UI.on_tap(badge, func(): _menu().show_profile(str(author.username)))
	var col := UI.vbox(4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := UI.hbox(8)
	head.add_child(UI.name_row(author, 16))
	head.add_child(UI.label(UI.relative_time(float(c.created_at)), 13, UI.MUTED))
	col.add_child(head)
	var body := UI.label(str(c.body), 16, UI.TEXT)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(body)
	row.add_child(col)
	# Small actions in a row, top right, so the comment stays as tall as its text.
	var actions := UI.hbox(4)
	actions.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if c.get("can_delete", false):
		var del := UI.button(L.t("delete"), "flat", 28)
		del.add_theme_font_size_override("font_size", 13)
		del.pressed.connect(func():
			if not await UI.confirm(self, L.t("delete_comment_q"), str(c.body).left(80), L.t("delete"), true):
				return
			var r := await Api.request("DELETE", "/api/places/%s/comments/%d" % [place_id.uri_encode(), int(c.id)])
			if r.ok:
				_comments.erase(c)
				_render_comments(enabled, can_post)
			else:
				UI.toast(r.message, "error"))
		actions.add_child(del)
	if int(author.get("id", 0)) != int(Session.user.get("id", -1)):
		var rep := UI.button(L.t("report"), "flat", 28)
		rep.add_theme_font_size_override("font_size", 13)
		rep.add_theme_color_override("font_color", UI.DANGER)
		rep.pressed.connect(func(): UI.report(self, author, {"comment_id": int(c.id)}))
		actions.add_child(rep)
	row.add_child(actions)
	return card
