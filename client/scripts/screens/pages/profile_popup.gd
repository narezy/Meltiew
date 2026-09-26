class_name ProfilePopup
extends CanvasLayer
## Modal card with another player's profile, live avatar and friend actions.

signal changed

var username := ""
var menu: Node
var _box: VBoxContainer
var _stage: AvatarStage
var _card: Control


func _ready() -> void:
	layer = 40
	var dim := ColorRect.new()
	dim.theme = UI.theme
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_close())
	add_child(dim)
	var center := CenterContainer.new()
	center.theme = UI.theme
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_card = UI.card(24, UI.CARD, 28)
	_card.custom_minimum_size = Vector2(760, 420)
	center.add_child(_card)
	var row := UI.hbox(24)
	_card.add_child(row)
	var stage_bg := UI.card(0, UI.BG_2, 22)
	stage_bg.custom_minimum_size = Vector2(280, 380)
	row.add_child(stage_bg)
	_stage = AvatarStage.new()
	stage_bg.add_child(_stage)
	_stage.clicked.connect(func(): _stage.avatar.play("wave"))
	_box = UI.vbox(12)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_box)
	_box.add_child(Loading.block(L.t("loading_profile")))
	_card.scale = Vector2(0.94, 0.94)
	_card.pivot_offset = _card.custom_minimum_size / 2.0
	_card.modulate.a = 0.0
	var t := create_tween().set_parallel()
	t.tween_property(_card, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_card, "modulate:a", 1.0, 0.15)
	_load()


func _close() -> void:
	queue_free()


func _load() -> void:
	var r := await Api.request("GET", "/api/users/" + username.uri_encode())
	if not is_inside_tree():
		return
	for c in _box.get_children():
		c.queue_free()
	if not r.ok:
		_box.add_child(Loading.error_block(r.message, func():
			for c in _box.get_children():
				c.queue_free()
			_box.add_child(Loading.block(L.t("loading_profile")))
			_load()))
		_add_close()
		return
	_render(r.data.user)


func _render(u: Dictionary) -> void:
	_stage.avatar.apply_user(u)
	var top := UI.hbox(10)
	var names := UI.vbox(0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_child(UI.name_row(u, 32, UI.TEXT, "black"))
	names.add_child(UI.label("@" + str(u.username), 18, UI.MUTED))
	top.add_child(names)
	var x := UI.button("", "ghost", 48)
	x.custom_minimum_size.x = 48
	var xi := Icon.make("close", 20)
	xi.position = Vector2(14, 14)
	x.add_child(xi)
	x.pressed.connect(_close)
	x.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(x)
	_box.add_child(top)

	var st := FriendsPage.status_text(u)
	var srow := UI.hbox(8)
	srow.add_child(UI.dot(st[1], 10))
	srow.add_child(UI.label(st[0], 18, st[1], "bold"))
	_box.add_child(srow)

	var bio := str(u.get("bio", ""))
	var bl := UI.label(bio if bio != "" else L.t("no_bio"), 19, UI.TEXT if bio != "" else UI.MUTED)
	bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(bl)

	var stats := UI.hbox(12)
	stats.add_child(_stat(str(int(u.get("friends", 0))), L.plural(int(u.get("friends", 0)), "friends_word")))
	var joined := Time.get_date_dict_from_unix_time(int(float(u.get("created_at", 0)) / 1000.0))
	stats.add_child(_stat("%02d.%02d.%d" % [joined.day, joined.month, joined.year], L.t("member_since")))
	_box.add_child(stats)
	var friends_row := UI.hbox(6)
	_box.add_child(friends_row)
	_load_friends(str(u.username), friends_row)
	var badges_row := UI.hbox(6)
	_box.add_child(badges_row)
	_load_badges(str(u.username), badges_row)
	_box.add_child(UI.spacer(false))

	var actions := UI.hbox(10)
	_box.add_child(actions)
	var is_me := int(u.id) == int(Session.user.get("id", -1))
	var playing: Variant = u.get("playing")
	if playing is Dictionary and not is_me:
		var join := UI.button(L.t("join_friend"), "mint", 56)
		join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		join.pressed.connect(func():
			_close()
			if menu and menu.has_method("play"):
				menu.play(str(playing.server_id)))
		actions.add_child(join)
	if is_me:
		return
	var rel := str(u.get("relation", "none"))
	if rel != "blocked" and menu and menu.has_method("open_messages"):
		var dm := UI.button(L.t("message"), "ghost", 56)
		dm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dm.pressed.connect(func():
			_close()
			menu.open_messages(u))
		actions.add_child(dm)
	var more := UI.hbox(10)
	_box.add_child(more)
	var report := UI.button(L.t("report"), "flat", 40)
	report.add_theme_font_size_override("font_size", 15)
	report.pressed.connect(func(): UI.report(self, u))
	more.add_child(report)
	if rel != "blocked":
		var label: String = {"friends": L.t("remove_friend"), "outgoing": L.t("cancel_request"), "incoming": L.t("accept_request")}.get(rel, L.t("add_friend"))
		var variant: String = {"friends": "ghost", "outgoing": "ghost", "incoming": "primary"}.get(rel, "primary")
		var path: String = {"friends": "/api/friends/remove", "outgoing": "/api/friends/remove", "incoming": "/api/friends/accept"}.get(rel, "/api/friends/request")
		actions.add_child(_action_button(label, variant, path, u))
	var block_path := "/api/blocks/remove" if rel == "blocked" else "/api/blocks/add"
	var block := _action_button(L.t("unblock") if rel == "blocked" else L.t("block"), "ghost", block_path, u)
	block.size_flags_horizontal = Control.SIZE_FILL
	block.custom_minimum_size.y = 40
	block.add_theme_font_size_override("font_size", 15)
	more.add_child(block)


func _action_button(text: String, variant: String, path: String, u: Dictionary) -> Button:
	var b := UI.button(text, variant, 56)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func():
		if path == "/api/blocks/add":
			var sure: bool = await UI.confirm(self, L.t("block_q", [u.display_name]), L.t("block_body"), L.t("block"), true)
			if not sure:
				return
		b.disabled = true
		var r := await Api.request("POST", path, {"user_id": u.id})
		if not is_inside_tree():
			return
		if r.ok:
			Sfx.play("pop")
			var toast_key: String = {"friends": "now_friends", "outgoing": "request_sent", "blocked": "blocked_done"}.get(str(r.data.relation), "done")
			UI.toast(L.t(toast_key), "ok")
			changed.emit()
			for c in _box.get_children():
				c.queue_free()
			_load()
		else:
			b.disabled = false
			UI.toast(r.message, "error"))
	return b


## Friends preview: up to 7 busts, or a note when the list is hidden.
func _load_friends(username: String, row: HBoxContainer) -> void:
	var spin := Loading.spinner(26)
	row.add_child(spin)
	var r := await Api.request("GET", "/api/users/%s/friends" % username.uri_encode())
	if not is_instance_valid(row):
		return
	spin.queue_free()
	if not r.ok:
		return
	if r.data.hidden:
		row.add_child(UI.label(L.t("friends_hidden"), 15, UI.MUTED))
		return
	var list: Array = r.data.friends
	for i in mini(list.size(), 7):
		var f: Dictionary = list[i]
		var b := UI.avatar_badge(f, 40)
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		b.tooltip_text = str(f.display_name)
		b.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				username = str(f.username)
				self.username = username
				for c in _box.get_children():
					c.queue_free()
				_box.add_child(Loading.block(L.t("loading_profile")))
				_load())
		row.add_child(b)
	if list.size() > 7:
		row.add_child(UI.label("+%d" % (list.size() - 7), 16, UI.MUTED, "bold"))


## Badges from places: a strip of the newest ones; tap for all of them.
func _load_badges(username: String, row: HBoxContainer) -> void:
	var r := await Api.request("GET", "/api/users/%s/badges" % username.uri_encode())
	if not r.ok or not is_instance_valid(row) or r.data.badges.is_empty():
		return
	var all: Array = r.data.badges
	row.add_child(UI.label(L.t("bg_count", [all.size()]), 15, UI.MUTED, "bold"))
	for b in all.slice(0, 7):
		var pic := TextureRect.new()
		pic.custom_minimum_size = Vector2(38, 38)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.tooltip_text = str(b.name)
		row.add_child(pic)
		if str(b.get("image", "")) != "":
			var wr: WeakRef = weakref(pic)
			AssetCache.fetch(str(b.image), func(t: Texture2D):
				var p: TextureRect = wr.get_ref()
				if p and t:
					p.texture = t)
		else:
			pic.add_child(Icon.make("star", 38, UI.ACCENT))
	var more := UI.button(L.t("bg_all"), "ghost", 38)
	more.add_theme_font_size_override("font_size", 14)
	more.pressed.connect(func(): _all_badges(username, all))
	row.add_child(more)


func _all_badges(username: String, all: Array) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	var dim := ColorRect.new()
	dim.theme = UI.theme
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var vp := get_viewport().get_visible_rect().size
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var card := UI.card(20, UI.CARD, 22)
	card.custom_minimum_size = Vector2(minf(720.0, vp.x - 32.0), minf(560.0, vp.y - 40.0))
	center.add_child(card)
	var v := UI.vbox(12)
	card.add_child(v)
	var head := UI.hbox(8)
	var tl := UI.label(L.t("bg_of", [username]), 24, UI.TEXT, "black")
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tl)
	var close := UI.button("✕", "ghost", 44)
	close.custom_minimum_size.x = 48
	close.pressed.connect(layer.queue_free)
	head.add_child(close)
	v.add_child(head)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var grid := BadgeGrid.make(all, true)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(grid)


func _stat(value: String, caption: String) -> Control:
	var c := UI.card(14, UI.BG_2, 16)
	var v := UI.vbox(0)
	c.add_child(v)
	v.add_child(UI.label(value, 22, UI.TEXT, "black"))
	v.add_child(UI.label(caption, 15, UI.MUTED))
	return c


func _add_close() -> void:
	var b := UI.button(L.t("close"), "ghost")
	b.pressed.connect(_close)
	_box.add_child(b)
