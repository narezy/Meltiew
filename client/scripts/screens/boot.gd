extends Control
## Splash: shows the logo, restores the session and routes to auth or menu.

var _mark: TextureRect
var _status: Label


func _ready() -> void:
	add_child(Backdrop.new())
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var v := UI.vbox(18)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(v)
	_mark = TextureRect.new()
	_mark.texture = load("res://assets/logo_mark.png")
	_mark.custom_minimum_size = Vector2(150, 150)
	_mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_mark.pivot_offset = Vector2(75, 75)
	v.add_child(_mark)
	var title := UI.label("meltiew", 64, UI.TEXT, "black")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	_status = UI.label("", 18, UI.MUTED)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_status)

	_mark.scale = Vector2(0.6, 0.6)
	_mark.modulate.a = 0.0
	title.modulate.a = 0.0
	var t := create_tween().set_parallel()
	t.tween_property(_mark, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_mark, "modulate:a", 1.0, 0.35)
	t.tween_property(title, "modulate:a", 1.0, 0.5).set_delay(0.2)
	await get_tree().create_timer(0.7).timeout
	_route()


func _route() -> void:
	if Session.token == "":
		UI.goto("res://scenes/auth.tscn")
		return
	_status.text = L.t("connecting")
	var spin := Loading.spinner(34)
	spin.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_status.get_parent().add_child(spin)
	Accessories.refresh()  # newest accessory catalog, in the background
	var r := await Api.request("GET", "/api/me")
	spin.queue_free()
	if r.ok:
		Session.set_user(r.data.user)
		Session.set_meta("daily_bonus", int(r.data.get("daily_bonus", 0)))
		Busts.sync_my_render()
		# Opened from "Play" on the website: straight into the game, no menu detour.
		var launch := Launcher.take()
		if not launch.is_empty() and str(Session.user.get("birthdate", "")) != "":
			Session.pending_server = launch.server
			Session.pending_game = launch.game
			Api.request("GET", "/api/launch")  # consume the website's queue entry
			UI.goto("res://scenes/game.tscn")
			return
		UI.goto("res://scenes/main_menu.tscn")
	elif r.status == 401:
		Session.clear()
		UI.goto("res://scenes/auth.tscn")
	else:
		_status.text = r.message
		var retry := UI.button(L.t("retry"), "ghost")
		retry.custom_minimum_size.x = 260
		retry.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_status.get_parent().add_child(retry)
		retry.pressed.connect(func():
			retry.queue_free()
			_route())
