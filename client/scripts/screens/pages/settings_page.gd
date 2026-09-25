class_name SettingsPage
extends ScrollContainer
## Settings: controls, sound, graphics, language, blocked players, account, about.

var _old_pw: LineEdit
var _new_pw: LineEdit
var _server_status: Label
var _blocked_box: VBoxContainer


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var root := UI.vbox(18)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(root)
	root.add_child(UI.label(L.t("nav_settings"), 34, UI.TEXT, "black"))

	var cols := UI.hbox(18)
	root.add_child(cols)
	var left := UI.vbox(18)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var right := UI.vbox(18)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)

	var game := _section(left, L.t("game"))
	SettingsWidgets.game_block(game)

	var look := _section(left, L.t("interface"))
	var scale_row := UI.hbox(8)
	scale_row.add_child(UI.label(L.t("ui_size"), 19, UI.TEXT))
	scale_row.add_child(UI.spacer())
	var scale_val := UI.label("", 17, UI.MUTED, "bold")
	scale_row.add_child(scale_val)
	look.add_child(scale_row)
	var slider := HSlider.new()
	slider.min_value = 0.8
	slider.max_value = 1.7
	slider.step = 0.05
	var cur := float(Session.settings.get("ui_scale", 0.0))
	slider.value = cur if cur > 0.0 else UI.default_ui_scale()
	slider.custom_minimum_size.y = 36
	slider.focus_mode = Control.FOCUS_NONE
	scale_val.text = "%d%%" % roundi(slider.value * 100.0)
	slider.value_changed.connect(func(x): scale_val.text = "%d%%" % roundi(x * 100.0))
	# Applied on release, otherwise the slider jumps under your finger while it rescales.
	slider.drag_ended.connect(func(_c):
		Session.settings.ui_scale = slider.value
		Session.save_settings())
	look.add_child(slider)
	var auto := UI.button(L.t("ui_size_auto"), "ghost", 44)
	auto.add_theme_font_size_override("font_size", 16)
	auto.pressed.connect(func():
		Session.settings.ui_scale = 0.0
		Session.save_settings()
		slider.value = UI.default_ui_scale())
	look.add_child(auto)

	var lang := _section(left, L.t("language"))
	var picker := OptionButton.new()
	picker.custom_minimum_size.y = 52
	picker.add_theme_font_size_override("font_size", 18)
	picker.focus_mode = Control.FOCUS_NONE
	for i in Languages.LIST.size():
		picker.add_item(Languages.LIST[i][1], i)
		if Languages.LIST[i][0] == L.lang:
			picker.select(i)
	picker.get_popup().add_theme_font_size_override("font_size", 18)
	picker.item_selected.connect(func(i): L.set_lang(Languages.LIST[i][0]))
	lang.add_child(picker)
	if L.lang != "en" and L.lang != "ru":
		var note := UI.label(L.t("lang_fallback_note"), 15, UI.MUTED)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lang.add_child(note)

	var about := _section(left, L.t("about"))
	var tg := UI.button("  " + L.t("telegram"), "mint", 50)
	tg.pressed.connect(func(): OS.shell_open(UI.TELEGRAM))
	about.add_child(tg)
	about.add_child(UI.label("Meltiew %s" % ProjectSettings.get_setting("application/config/version", "1.0.0"), 19, UI.TEXT, "bold"))
	about.add_child(UI.label(L.t("server_is", [Api.BASE_URL.replace("https://", "")]), 17, UI.MUTED))
	_server_status = UI.label(L.t("checking_server"), 17, UI.MUTED)
	about.add_child(_server_status)
	_check_server()

	var acc := _section(right, L.t("account"))
	acc.add_child(UI.label(L.t("signed_in_as", [Session.user.get("username", "")]), 19, UI.TEXT, "bold"))
	acc.add_child(UI.label(L.t("change_password"), 17, UI.MUTED, "bold"))
	_old_pw = UI.input(L.t("current_password"), true)
	acc.add_child(_old_pw)
	_new_pw = UI.input(L.t("new_password"), true)
	acc.add_child(_new_pw)
	var change := UI.button(L.t("change_password"), "ghost", 52)
	change.pressed.connect(_change_password)
	acc.add_child(change)
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 12)
	acc.add_child(sep)
	var logout := UI.button(L.t("log_out"), "danger", 54)
	logout.pressed.connect(_logout)
	acc.add_child(logout)

	var privacy := _section(right, L.t("privacy"))
	var hide := CheckButton.new()
	hide.text = L.t("hide_friends")
	hide.button_pressed = bool(Session.user.get("hide_friends", false))
	hide.add_theme_font_size_override("font_size", 19)
	hide.focus_mode = Control.FOCUS_NONE
	hide.toggled.connect(func(on):
		var r := await Api.request("PATCH", "/api/me", {"hide_friends": on})
		if r.ok:
			Session.set_user(r.data.user)
		else:
			UI.toast(r.message, "error"))
	privacy.add_child(hide)
	var bd := str(Session.user.get("birthdate", ""))
	if bd != "":
		privacy.add_child(UI.label(L.t("bd_is", [bd]), 16, UI.MUTED))
	else:
		var set_bd := UI.button(L.t("bd_title"), "primary", 48)
		set_bd.pressed.connect(func():
			if await BirthdayInput.ask(self):
				UI.toast(L.t("saved"), "ok"))
		privacy.add_child(set_bd)
	var rules: Dictionary = Session.user.get("rules", {})
	if rules.get("age") != null:
		var note := UI.label(L.t("rules_" + _rules_key(rules)), 15, UI.MUTED)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		privacy.add_child(note)

	var blocked := _section(right, L.t("blocked_players"))
	_blocked_box = UI.vbox(8)
	blocked.add_child(_blocked_box)
	_load_blocked()


func _rules_key(rules: Dictionary) -> String:
	if not rules.get("chat", false):
		return "kid"
	if rules.get("filter_dm", true):
		return "teen"
	if rules.get("filter_chat", true):
		return "older_teen"
	return "adult"


func _section(parent: Control, title: String) -> VBoxContainer:
	var c := UI.card(22, UI.CARD, 24)
	parent.add_child(c)
	var v := UI.vbox(14)
	c.add_child(v)
	v.add_child(UI.label(title, 24, UI.TEXT, "black"))
	return v


func _load_blocked() -> void:
	_blocked_box.add_child(Loading.spinner(30))
	var r := await Api.request("GET", "/api/blocks")
	if not is_inside_tree():
		return
	for c in _blocked_box.get_children():
		c.queue_free()
	var list: Array = r.data.get("users", []) if r.ok else []
	if list.is_empty():
		_blocked_box.add_child(UI.label(L.t("nobody_blocked"), 17, UI.MUTED))
		return
	for u in list:
		var row := UI.hbox(10)
		row.add_child(UI.avatar_badge(u, 40))
		var n := UI.label(str(u.display_name), 18, UI.TEXT, "bold")
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(n)
		var b := UI.button(L.t("unblock"), "ghost", 42)
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(func():
			await Api.request("POST", "/api/blocks/remove", {"user_id": u.id})
			if is_inside_tree():
				UI.toast(L.t("unblocked"), "ok")
				_load_blocked())
		row.add_child(b)
		_blocked_box.add_child(row)


func _check_server() -> void:
	var t0 := Time.get_ticks_msec()
	var r := await Api.request("GET", "/api/health")
	if not is_inside_tree():
		return
	if r.ok:
		_server_status.text = L.t("server_ok", [Time.get_ticks_msec() - t0, int(r.data.users)])
		_server_status.add_theme_color_override("font_color", UI.ONLINE)
	else:
		_server_status.text = L.t("server_down", [r.message])
		_server_status.add_theme_color_override("font_color", UI.DANGER)


func _change_password() -> void:
	if _new_pw.text.length() < 6:
		UI.toast(L.t("bad_password"), "error")
		return
	var r := await Api.request("POST", "/api/me/password", {"old_password": _old_pw.text, "new_password": _new_pw.text})
	if not is_inside_tree():
		return
	if r.ok:
		_old_pw.text = ""
		_new_pw.text = ""
		UI.toast(L.t("password_changed"), "ok")
	else:
		UI.toast(r.message, "error")


func _logout() -> void:
	var yes: bool = await UI.confirm(self, L.t("log_out_q"), L.t("log_out_body"), L.t("log_out"), true)
	if not yes:
		return
	await Api.request("POST", "/api/logout")
	Session.clear()
	UI.goto("res://scenes/auth.tscn")
