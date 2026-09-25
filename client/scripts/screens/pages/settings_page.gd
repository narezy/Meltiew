class_name SettingsPage
extends ScrollContainer
## Settings: controls, sound, graphics, account security, about.

var _old_pw: LineEdit
var _new_pw: LineEdit
var _server_status: Label


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var root := UI.vbox(18)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(root)
	root.add_child(UI.label("Настройки", 34, UI.TEXT, "black"))

	var cols := UI.hbox(18)
	root.add_child(cols)
	var left := UI.vbox(18)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var right := UI.vbox(18)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)

	var game := _section(left, "Игра")
	_slider(game, "Чувствительность камеры", "camera_sensitivity", 0.3, 2.5, 0.05)
	_slider(game, "Громкость", "volume", 0.0, 1.0, 0.05)
	var q := UI.hbox(8)
	q.add_child(UI.label("Графика", 19, UI.TEXT))
	q.add_child(UI.spacer())
	for opt in [["low", "Быстрая"], ["high", "Красивая"]]:
		var b := UI.button(opt[1], "flat", 44)
		b.theme_type_variation = "ChipButton"
		b.toggle_mode = true
		b.button_pressed = Session.settings.quality == opt[0]
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(func():
			Session.settings.quality = opt[0]
			Session.save_settings()
			for c in q.get_children():
				if c is Button:
					c.button_pressed = c == b)
		q.add_child(b)
	game.add_child(q)
	var fps := CheckButton.new()
	fps.text = "Показывать FPS и пинг"
	fps.button_pressed = bool(Session.settings.show_fps)
	fps.add_theme_font_size_override("font_size", 19)
	fps.toggled.connect(func(on):
		Session.settings.show_fps = on
		Session.save_settings())
	game.add_child(fps)

	var about := _section(left, "О приложении")
	about.add_child(UI.label("Meltiew %s" % ProjectSettings.get_setting("application/config/version", "1.0.0"), 19, UI.TEXT, "bold"))
	about.add_child(UI.label("Сервер: meltiew.narez.xyz", 17, UI.MUTED))
	_server_status = UI.label("Проверяем связь...", 17, UI.MUTED)
	about.add_child(_server_status)
	_check_server()

	var acc := _section(right, "Аккаунт")
	acc.add_child(UI.label("Вошли как @%s" % Session.user.get("username", ""), 19, UI.TEXT, "bold"))
	acc.add_child(UI.label("Смена пароля", 17, UI.MUTED, "bold"))
	_old_pw = UI.input("Текущий пароль", true)
	acc.add_child(_old_pw)
	_new_pw = UI.input("Новый пароль (от 6 символов)", true)
	acc.add_child(_new_pw)
	var change := UI.button("Сменить пароль", "ghost", 52)
	change.pressed.connect(_change_password)
	acc.add_child(change)
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 12)
	acc.add_child(sep)
	var logout := UI.button("Выйти из аккаунта", "danger", 54)
	logout.pressed.connect(_logout)
	acc.add_child(logout)


func _section(parent: Control, title: String) -> VBoxContainer:
	var c := UI.card(22, UI.CARD, 24)
	parent.add_child(c)
	var v := UI.vbox(14)
	c.add_child(v)
	v.add_child(UI.label(title, 24, UI.TEXT, "black"))
	return v


func _slider(parent: Control, title: String, key: String, lo: float, hi: float, step: float) -> void:
	var row := UI.hbox(8)
	row.add_child(UI.label(title, 19, UI.TEXT))
	row.add_child(UI.spacer())
	var val := UI.label("", 17, UI.MUTED, "bold")
	row.add_child(val)
	parent.add_child(row)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Session.settings[key])
	s.custom_minimum_size.y = 36
	s.focus_mode = Control.FOCUS_NONE
	var fmt := func(x: float) -> String:
		return "%d%%" % roundi(x * 100.0) if key == "volume" else "%.2fx" % x
	val.text = fmt.call(s.value)
	s.value_changed.connect(func(x):
		val.text = fmt.call(x)
		Session.settings[key] = x)
	s.drag_ended.connect(func(_c): Session.save_settings())
	parent.add_child(s)


func _check_server() -> void:
	var t0 := Time.get_ticks_msec()
	var r := await Api.request("GET", "/api/health")
	if not is_inside_tree():
		return
	if r.ok:
		_server_status.text = "Сервер в порядке, отклик %d мс, аккаунтов: %d" % [Time.get_ticks_msec() - t0, int(r.data.users)]
		_server_status.add_theme_color_override("font_color", UI.ONLINE)
	else:
		_server_status.text = "Сервер недоступен: " + r.message
		_server_status.add_theme_color_override("font_color", UI.DANGER)


func _change_password() -> void:
	if _new_pw.text.length() < 6:
		UI.toast("Новый пароль должен быть от 6 символов", "error")
		return
	var r := await Api.request("POST", "/api/me/password", {"old_password": _old_pw.text, "new_password": _new_pw.text})
	if not is_inside_tree():
		return
	if r.ok:
		_old_pw.text = ""
		_new_pw.text = ""
		UI.toast("Пароль изменён. Другие устройства разлогинены", "ok")
	else:
		UI.toast(r.message, "error")


func _logout() -> void:
	var yes: bool = await UI.confirm(self, "Выйти?", "Чтобы вернуться, понадобятся логин и пароль.", "Выйти", true)
	if not yes:
		return
	await Api.request("POST", "/api/logout")
	Session.clear()
	UI.goto("res://scenes/auth.tscn")
