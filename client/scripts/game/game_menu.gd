class_name GameMenu
extends CanvasLayer
## In-game Meltiew menu: players (add friend / block), settings, controls,
## plus reset character, leave and resume.

signal resumed
signal reset_requested
signal leave_requested
signal settings_changed
signal blocks_changed(blocked_ids: Array)

var game: Node
var _card: Control
var _body: Control
var _tabs := {}
var _tab := "players"


func _ready() -> void:
	layer = 30
	visible = false
	var dim := ColorRect.new()
	dim.theme = UI.theme
	dim.color = Color(0.05, 0.04, 0.08, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.theme = UI.theme
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)
	var center := CenterContainer.new()
	margin.add_child(center)
	_card = UI.card(24, UI.BG_2, 28)
	_card.custom_minimum_size = Vector2(980, 560)
	center.add_child(_card)
	var row := UI.hbox(22)
	_card.add_child(row)

	# Left column: brand, tabs, actions.
	var side := UI.vbox(10)
	side.custom_minimum_size.x = 230
	row.add_child(side)
	var brand := UI.hbox(10)
	var mark := TextureRect.new()
	mark.texture = load("res://assets/logo_mark.png")
	mark.custom_minimum_size = Vector2(40, 40)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	brand.add_child(mark)
	brand.add_child(UI.label("meltiew", 26, UI.TEXT, "black"))
	side.add_child(brand)
	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	side.add_child(gap)
	for t in [["players", "users", L.t("players")], ["settings", "settings", L.t("nav_settings")], ["help", "menu", L.t("controls")]]:
		var b := _tab_button(t[0], t[1], t[2])
		side.add_child(b)
	side.add_child(UI.spacer(false))
	var reset := UI.button(L.t("reset_character"), "ghost", 52)
	reset.pressed.connect(func():
		close()
		reset_requested.emit())
	side.add_child(reset)
	var leave := UI.button(L.t("leave_game"), "danger", 52)
	leave.pressed.connect(func(): leave_requested.emit())
	side.add_child(leave)
	var resume := UI.button(L.t("resume"), "primary", 56)
	resume.pressed.connect(close)
	side.add_child(resume)

	var content := UI.card(20, UI.CARD, 22)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(content)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	_body = UI.vbox(12)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)


func _tab_button(id: String, icon: String, text: String) -> Button:
	var b := Button.new()
	b.theme_type_variation = "TabButton"
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 52
	var inner := UI.hbox(12)
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 16
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(Icon.make(icon, 22, UI.TEXT))
	var l := UI.label(text, 19, UI.TEXT, "bold")
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_FILL
	inner.add_child(l)
	b.add_child(inner)
	b.pressed.connect(func():
		Sfx.click()
		show_tab(id))
	_tabs[id] = b
	return b


func open() -> void:
	visible = true
	show_tab(_tab)
	_card.modulate.a = 0.0
	_card.scale = Vector2(0.96, 0.96)
	_card.pivot_offset = _card.size / 2.0
	var t := _card.create_tween().set_parallel()
	t.tween_property(_card, "modulate:a", 1.0, 0.15)
	t.tween_property(_card, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close() -> void:
	if visible:
		visible = false
		resumed.emit()


func show_tab(id: String) -> void:
	_tab = id
	for k in _tabs:
		_tabs[k].button_pressed = k == id
	for c in _body.get_children():
		c.queue_free()
	match id:
		"settings":
			_body.add_child(UI.label(L.t("nav_settings"), 26, UI.TEXT, "black"))
			SettingsWidgets.game_block(_body)
			var note := UI.label(L.t("graphics_note"), 15, UI.MUTED)
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_body.add_child(note)
		"help":
			_body.add_child(UI.label(L.t("controls"), 26, UI.TEXT, "black"))
			for line in ["help_move", "help_camera", "help_zoom", "help_jump", "help_emotes", "help_chat", "help_reset"]:
				var l := UI.label(L.t(line), 18, UI.TEXT)
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_body.add_child(l)
		_:
			_render_players()


func _render_players() -> void:
	_body.add_child(UI.label(L.t("players_on_server", [game.users.size(), 10]), 26, UI.TEXT, "black"))
	_body.add_child(UI.label(L.field(game.server_info, "name"), 16, UI.MUTED, "bold"))
	var list: Array = game.users.values()
	list.sort_custom(func(a, b): return str(a.display_name) < str(b.display_name))
	for u in list:
		_body.add_child(_player_row(u))


func _player_row(u: Dictionary) -> Control:
	var c := UI.card(12, UI.CARD_2, 18)
	var row := UI.hbox(12)
	c.add_child(row)
	row.add_child(UI.avatar_badge(u, 50))
	var col := UI.vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UI.name_row(u, 19))
	col.add_child(UI.label("@" + str(u.username), 15, UI.MUTED))
	row.add_child(col)
	if int(u.id) == int(Session.user.get("id", -1)):
		row.add_child(UI.label(L.t("its_you"), 16, UI.ACCENT, "bold"))
		return c
	var actions := UI.hbox(8)
	row.add_child(actions)
	actions.add_child(UI.label("...", 16, UI.MUTED))
	_fill_actions(actions, u)
	return c


func _fill_actions(actions: HBoxContainer, u: Dictionary) -> void:
	var r := await Api.request("GET", "/api/users/" + str(u.username).uri_encode())
	if not is_instance_valid(actions):
		return
	for ch in actions.get_children():
		ch.queue_free()
	var rel := str(r.data.get("user", {}).get("relation", "none")) if r.ok else "none"
	if rel != "blocked":
		var fr_text: String = {"friends": L.t("friends_badge"), "outgoing": L.t("request_sent_short"), "incoming": L.t("accept")}.get(rel, L.t("add_friend"))
		var fr := UI.button(fr_text, "mint" if rel in ["none", "incoming"] else "ghost", 44)
		fr.add_theme_font_size_override("font_size", 16)
		fr.disabled = rel in ["friends", "outgoing"]
		fr.pressed.connect(func():
			var path := "/api/friends/accept" if rel == "incoming" else "/api/friends/request"
			var res := await Api.request("POST", path, {"user_id": u.id})
			if res.ok:
				UI.toast(L.t("now_friends") if res.data.relation == "friends" else L.t("request_sent"), "ok")
				Sfx.play("pop")
			else:
				UI.toast(res.message, "error")
			if is_instance_valid(actions):
				_fill_actions(actions, u))
		actions.add_child(fr)
	var rep := UI.button(L.t("report"), "ghost", 44)
	rep.add_theme_font_size_override("font_size", 16)
	rep.pressed.connect(func(): UI.report(self, u))
	actions.add_child(rep)
	var blocked := rel == "blocked"
	var bl := UI.button(L.t("unblock") if blocked else L.t("block"), "ghost" if blocked else "danger", 44)
	bl.add_theme_font_size_override("font_size", 16)
	bl.pressed.connect(func():
		var res := await Api.request("POST", "/api/blocks/remove" if blocked else "/api/blocks/add", {"user_id": u.id})
		if res.ok:
			UI.toast(L.t("unblocked") if blocked else L.t("blocked_done"), "ok")
			_emit_blocks()
		if is_instance_valid(actions):
			_fill_actions(actions, u))
	actions.add_child(bl)


func _emit_blocks() -> void:
	var r := await Api.request("GET", "/api/blocks")
	if r.ok:
		var ids := []
		for u in r.data.users:
			ids.append(int(u.id))
		blocks_changed.emit(ids)
