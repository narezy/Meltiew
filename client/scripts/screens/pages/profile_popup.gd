class_name ProfilePopup
extends CanvasLayer
## Modal card with another player's profile, live avatar and friend actions.

var username := ""
var menu: Node
var _box: VBoxContainer
var _stage: AvatarStage
var _card: Control


func _ready() -> void:
	layer = 40
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_close())
	add_child(dim)
	var center := CenterContainer.new()
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
	_box.add_child(UI.label("Загружаем профиль...", 20, UI.MUTED))
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
		_box.add_child(UI.label(r.message, 20, UI.DANGER))
		_add_close()
		return
	_render(r.data.user)


func _render(u: Dictionary) -> void:
	_stage.avatar.apply_user(u)
	var top := UI.hbox(10)
	var names := UI.vbox(0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_child(UI.label(str(u.display_name), 32, UI.TEXT, "black"))
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
	var bl := UI.label(bio if bio != "" else "Пока ничего о себе не рассказал(а)", 19, UI.TEXT if bio != "" else UI.MUTED)
	bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(bl)

	var stats := UI.hbox(12)
	stats.add_child(_stat(str(int(u.get("friends", 0))), "друзей"))
	var joined := Time.get_date_dict_from_unix_time(int(float(u.get("created_at", 0)) / 1000.0))
	stats.add_child(_stat("%02d.%02d.%d" % [joined.day, joined.month, joined.year], "с нами с"))
	_box.add_child(stats)
	_box.add_child(UI.spacer(false))

	var actions := UI.hbox(10)
	_box.add_child(actions)
	var is_me := int(u.id) == int(Session.user.get("id", -1))
	var playing: Variant = u.get("playing")
	if playing is Dictionary and not is_me:
		var join := UI.button("Присоединиться", "mint", 56)
		join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		join.pressed.connect(func():
			_close()
			if menu and menu.has_method("play"):
				menu.play(str(playing.server_id)))
		actions.add_child(join)
	if is_me:
		return
	var rel := str(u.get("relation", "none"))
	var label := {"friends": "Удалить из друзей", "outgoing": "Отменить заявку", "incoming": "Принять заявку"}.get(rel, "Добавить в друзья")
	var variant := {"friends": "ghost", "outgoing": "ghost", "incoming": "primary"}.get(rel, "primary")
	var path := {"friends": "/api/friends/remove", "outgoing": "/api/friends/remove", "incoming": "/api/friends/accept"}.get(rel, "/api/friends/request")
	var b := UI.button(label, variant, 56)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func():
		b.disabled = true
		var r := await Api.request("POST", path, {"user_id": u.id})
		if not is_inside_tree():
			return
		if r.ok:
			Sfx.play("pop")
			UI.toast({"friends": "Вы теперь друзья!", "outgoing": "Заявка отправлена", "none": "Готово"}.get(str(r.data.relation), "Готово"), "ok")
			for c in _box.get_children():
				c.queue_free()
			_load()
		else:
			b.disabled = false
			UI.toast(r.message, "error"))
	actions.add_child(b)


func _stat(value: String, caption: String) -> Control:
	var c := UI.card(14, UI.BG_2, 16)
	var v := UI.vbox(0)
	c.add_child(v)
	v.add_child(UI.label(value, 22, UI.TEXT, "black"))
	v.add_child(UI.label(caption, 15, UI.MUTED))
	return c


func _add_close() -> void:
	var b := UI.button("Закрыть", "ghost")
	b.pressed.connect(_close)
	_box.add_child(b)
