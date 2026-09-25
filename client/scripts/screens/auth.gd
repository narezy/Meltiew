extends Control
## Sign in / sign up screen.

var _mode := "login"
var _tab_login: Button
var _tab_register: Button
var _username: LineEdit
var _display: LineEdit
var _password: LineEdit
var _password2: LineEdit
var _display_row: Control
var _password2_row: Control
var _birthday: BirthdayInput
var _birthday_row: Control
var _submit: Button
var _error: Label
var _hint: Label
var _stage: AvatarStage


func _ready() -> void:
	add_child(Backdrop.new())
	var content := Control.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(content)
	add_child(KeyboardAvoider.new(content))

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	content.add_child(margin)
	var fit := func():
		var short := get_viewport_rect().size.y < 760.0
		for side in ["top", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 14 if short else 36)
	get_viewport().size_changed.connect(fit)
	fit.call()
	var row := UI.hbox(32)
	margin.add_child(row)

	# Left: brand + live Melly.
	var left := UI.vbox(0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.1
	row.add_child(left)
	var brand := UI.hbox(14)
	left.add_child(brand)
	var mark := TextureRect.new()
	mark.texture = load("res://assets/logo_mark.png")
	mark.custom_minimum_size = Vector2(56, 56)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	brand.add_child(mark)
	brand.add_child(UI.label("meltiew", 40, UI.TEXT, "black"))
	var tagline := UI.label(L.t("tagline"), 22, UI.MUTED)
	left.add_child(tagline)
	_stage = AvatarStage.new()
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.auto_spin = 0.25
	left.add_child(_stage)
	_stage.clicked.connect(func(): _stage.avatar.play("wave"))
	_randomize_look()
	var look_timer := Timer.new()
	look_timer.wait_time = 3.5
	look_timer.autostart = true
	look_timer.timeout.connect(_randomize_look)
	add_child(look_timer)

	# Right: form card.
	# Scrolls when the sign-up form is taller than the screen (short phones, keyboard up).
	var right := ScrollContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(right)
	var center := VBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(center)
	var card := UI.card(28, UI.CARD, 28)
	card.custom_minimum_size.x = 470
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(card)
	var form := UI.vbox(14)
	card.add_child(form)

	var tabs := UI.hbox(6)
	var tabs_bg := UI.card(6, UI.BG_2, 18)
	tabs_bg.add_child(tabs)
	form.add_child(tabs_bg)
	_tab_login = _make_tab(L.t("sign_in"), "login")
	_tab_register = _make_tab(L.t("sign_up"), "register")
	tabs.add_child(_tab_login)
	tabs.add_child(_tab_register)

	_username = UI.input(L.t("username"))
	_username.max_length = 20
	form.add_child(_username)
	_display = UI.input(L.t("display_name_hint"))
	_display.max_length = 24
	_display_row = _display
	form.add_child(_display)
	_password = UI.input(L.t("password"), true)
	_password.max_length = 128
	form.add_child(_password)
	_password2 = UI.input(L.t("password_repeat"), true)
	_password2.max_length = 128
	_password2_row = _password2
	form.add_child(_password2)
	var bd := UI.vbox(6)
	bd.add_child(UI.label(L.t("bd_label"), 15, UI.MUTED, "bold"))
	_birthday = BirthdayInput.new()
	bd.add_child(_birthday)
	_birthday_row = bd
	form.add_child(bd)

	_error = UI.label("", 18, UI.DANGER)
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.visible = false
	form.add_child(_error)
	_submit = UI.button(L.t("sign_in"))
	_submit.custom_minimum_size.y = 60
	form.add_child(_submit)
	_hint = UI.label("", 16, UI.MUTED)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	form.add_child(_hint)

	_submit.pressed.connect(_on_submit)
	for e in [_username, _display, _password, _password2]:
		e.text_submitted.connect(func(_t): _next_field(e))
	_set_mode("login")


func _make_tab(text: String, mode: String) -> Button:
	var b := UI.button(text, "flat", 48)
	b.theme_type_variation = "TabButton"
	b.toggle_mode = true
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func(): _set_mode(mode))
	return b


func _set_mode(mode: String) -> void:
	_mode = mode
	var reg := mode == "register"
	_tab_login.button_pressed = not reg
	_tab_register.button_pressed = reg
	_display_row.visible = reg
	_password2_row.visible = reg
	_birthday_row.visible = reg
	_submit.text = L.t("create_account") if reg else L.t("sign_in")
	_hint.text = L.t("register_hint") if reg else L.t("login_hint")
	_error.visible = false


func _next_field(from: LineEdit) -> void:
	var order: Array = [_username, _password] if _mode == "login" else [_username, _display, _password, _password2]
	var i := order.find(from)
	if i >= 0 and i < order.size() - 1:
		order[i + 1].grab_focus()
	else:
		_on_submit()


func _show_error(text: String) -> void:
	_error.text = text
	_error.visible = true
	Sfx.play("error")
	var t := create_tween()
	var x := _error.position.x
	for k in 4:
		t.tween_property(_error, "position:x", x + (8 if k % 2 == 0 else -8), 0.04)
	t.tween_property(_error, "position:x", x, 0.04)


func _on_submit() -> void:
	var username := _username.text.strip_edges()
	var password := _password.text
	var regex := RegEx.create_from_string("^[A-Za-z0-9_]{3,20}$")
	if regex.search(username) == null:
		_show_error(L.t("bad_username"))
		return
	if password.length() < 6:
		_show_error(L.t("bad_password"))
		return
	var body := {"username": username, "password": password}
	var path := "/api/login"
	if _mode == "register":
		if _password2.text != password:
			_show_error(L.t("passwords_mismatch"))
			return
		var display := _display.text.strip_edges()
		body.display_name = display if display.length() >= 2 else username
		body.birthdate = _birthday.value()
		if body.birthdate == "":
			_show_error(L.t("bd_incomplete"))
			return
		path = "/api/register"
	_submit.disabled = true
	_submit.text = L.t("one_sec")
	_error.visible = false
	var r := await Api.request("POST", path, body)
	_submit.disabled = false
	_set_mode(_mode)
	if not r.ok:
		_show_error(r.message)
		return
	Session.set_auth(r.data.token, r.data.user)
	Sfx.play("join")
	UI.toast(L.t("welcome_name", [r.data.user.display_name]), "ok")
	Busts.sync_my_render()
	UI.goto("res://scenes/main_menu.tscn")


func _randomize_look() -> void:
	var colors := {}
	var pal: Array = UI.SWATCHES
	var skin: String = ["#f5f1ec", "#ffd9c2", "#e8b48f", "#b07852"].pick_random()
	colors.head = skin
	colors.arm_l = skin
	colors.arm_r = skin
	colors.torso = pal.pick_random()
	var pants: String = pal.pick_random()
	colors.leg_l = pants
	colors.leg_r = pants
	_stage.avatar.set_colors(colors)
	_stage.avatar.set_hat(UI.HATS.pick_random().id)
