extends Control
## Main hub: sidebar navigation + pages (home, friends, avatar, settings).

const PAGES := [
	{"id": "home", "title": "nav_home", "icon": "home"},
	{"id": "friends", "title": "nav_friends", "icon": "friends"},
	{"id": "avatar", "title": "nav_avatar", "icon": "avatar"},
	{"id": "settings", "title": "nav_settings", "icon": "settings"},
]

static var last_page := "home"

var _nav_buttons := {}
var _nav_icons := {}
var _content: MarginContainer
var _page: Control
var _page_id := ""
var _badge: Label
var _me_box: HBoxContainer
var _poll: Timer


func _ready() -> void:
	add_child(Backdrop.new())
	var shell := Control.new()
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shell)
	add_child(KeyboardAvoider.new(shell))
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 0)
	shell.add_child(row)

	row.add_child(_build_sidebar())
	_content = MarginContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		_content.add_theme_constant_override("margin_" + side, 28)
	_content.add_theme_constant_override("margin_left", 32)
	row.add_child(_content)

	Session.user_changed.connect(_refresh_me)
	_refresh_me()
	open_page(last_page)

	_poll = Timer.new()
	_poll.wait_time = 15.0
	_poll.autostart = true
	_poll.timeout.connect(_poll_requests)
	add_child(_poll)
	_poll_requests()
	_check_launch()
	L.changed.connect(func(): get_tree().reload_current_scene())


func _notification(what: int) -> void:
	# Coming back from the browser after pressing "Play" on the website.
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_check_launch()


var _checking_launch := false


func _check_launch() -> void:
	if _checking_launch or not is_inside_tree():
		return
	_checking_launch = true
	var r := await Api.request("GET", "/api/launch")
	_checking_launch = false
	if r.ok and r.data.get("launch") is Dictionary and is_inside_tree():
		play(str(r.data.launch.server))


func _build_sidebar() -> Control:
	var side := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UI.BG_2, 0.92)
	sb.border_width_right = 1
	sb.border_color = UI.LINE
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 24
	sb.content_margin_bottom = 20
	side.add_theme_stylebox_override("panel", sb)
	side.custom_minimum_size.x = 250
	var v := UI.vbox(8)
	side.add_child(v)

	var brand := UI.hbox(12)
	var mark := TextureRect.new()
	mark.texture = load("res://assets/logo_mark.png")
	mark.custom_minimum_size = Vector2(44, 44)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	brand.add_child(mark)
	brand.add_child(UI.label("meltiew", 30, UI.TEXT, "black"))
	v.add_child(brand)
	var gap := Control.new()
	gap.custom_minimum_size.y = 18
	v.add_child(gap)

	for p in PAGES:
		var b := Button.new()
		b.theme_type_variation = "TabButton"
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.y = 56
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var inner := UI.hbox(14)
		inner.set_anchors_preset(Control.PRESET_FULL_RECT)
		inner.offset_left = 18
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := Icon.make(p.icon, 24, UI.MUTED)
		inner.add_child(ic)
		var l := UI.label(L.t(p.title), 20, UI.MUTED, "bold")
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size_flags_vertical = Control.SIZE_FILL
		inner.add_child(l)
		if p.id == "friends":
			inner.add_child(UI.spacer())
			_badge = UI.label("", 15, UI.INK, "black")
			var badge_bg := StyleBoxFlat.new()
			badge_bg.bg_color = UI.PINK
			badge_bg.set_corner_radius_all(12)
			badge_bg.content_margin_left = 9
			badge_bg.content_margin_right = 9
			badge_bg.content_margin_top = 1
			badge_bg.content_margin_bottom = 1
			_badge.add_theme_stylebox_override("normal", badge_bg)
			_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_badge.visible = false
			inner.add_child(_badge)
			var pad := Control.new()
			pad.custom_minimum_size.x = 8
			inner.add_child(pad)
		b.add_child(inner)
		b.pressed.connect(func():
			Sfx.click()
			open_page(p.id))
		v.add_child(b)
		_nav_buttons[p.id] = b
		_nav_icons[p.id] = [ic, l]

	v.add_child(UI.spacer(false))
	var me_card := UI.card(12, UI.CARD, 18)
	_me_box = UI.hbox(12)
	me_card.add_child(_me_box)
	v.add_child(me_card)
	return side


func _refresh_me() -> void:
	if _me_box == null:
		return
	for c in _me_box.get_children():
		c.queue_free()
	var u := Session.user
	_me_box.add_child(UI.avatar_badge(u, 44))
	var col := UI.vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UI.name_row(u, 18))
	var handle := UI.label("@" + str(u.get("username", "")), 15, UI.MUTED)
	handle.clip_text = true
	col.add_child(handle)
	_me_box.add_child(col)


var _open_place_id := "playground"


func open_place(id: String) -> void:
	_open_place_id = id
	_page_id = ""
	open_page("place")
	# Places live under Home in the sidebar.
	_highlight("home")


func _highlight(id: String) -> void:
	for pid in _nav_buttons:
		var on: bool = pid == id
		_nav_buttons[pid].button_pressed = on
		_nav_icons[pid][0].color = UI.ACCENT if on else UI.MUTED
		_nav_icons[pid][1].add_theme_color_override("font_color", UI.TEXT if on else UI.MUTED)


func open_page(id: String) -> void:
	if id == _page_id and _page:
		if _page.has_method("refresh"):
			_page.refresh()
		return
	_page_id = id
	if id != "place":
		last_page = id
	_highlight(id)
	if _page:
		_page.queue_free()
	match id:
		"friends":
			_page = FriendsPage.new()
		"avatar":
			_page = AvatarPage.new()
		"settings":
			_page = SettingsPage.new()
		"place":
			_page = PlacePage.new()
			_page.place_id = _open_place_id
		_:
			_page = HomePage.new()
	_page.set_meta("menu", self)
	_content.add_child(_page)
	_page.modulate.a = 0.0
	_page.position.y = 12
	var t := _page.create_tween().set_parallel()
	t.tween_property(_page, "modulate:a", 1.0, 0.2)
	t.tween_property(_page, "position:y", 0.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func set_request_badge(n: int) -> void:
	if _badge:
		_badge.text = str(n)
		_badge.visible = n > 0


func _poll_requests() -> void:
	var r := await Api.request("GET", "/api/friends")
	if r.ok and is_instance_valid(self):
		set_request_badge(r.data.incoming.size())


## Starts the playground, optionally on a specific server ("auto", "new" or id).
func play(server := "auto") -> void:
	Session.pending_server = server
	UI.goto("res://scenes/game.tscn")


func show_profile(username: String) -> void:
	var popup := ProfilePopup.new()
	popup.username = username
	popup.menu = self
	add_child(popup)
