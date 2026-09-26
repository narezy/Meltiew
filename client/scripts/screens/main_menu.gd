extends Control
## Main hub: sidebar navigation + pages (home, friends, avatar, settings).

const PAGES := [
	{"id": "home", "title": "nav_home", "icon": "home"},
	{"id": "friends", "title": "nav_friends", "icon": "friends"},
	{"id": "messages", "title": "messages", "icon": "chat"},
	{"id": "communities", "title": "nav_communities", "icon": "group"},
	{"id": "avatar", "title": "nav_avatar", "icon": "avatar"},
	{"id": "shop", "title": "nav_shop", "icon": "shop"},
	{"id": "studio", "title": "nav_studio", "icon": "code"},
	{"id": "settings", "title": "nav_settings", "icon": "settings"},
]

static var last_page := "home"

static var _asked_birthday := false

var _nav_buttons := {}
var _nav_icons := {}
var _content: MarginContainer
var _page: Control
var _page_id := ""
var _badges := {}
var _side: PanelContainer
var _brand_label: Label
var _nav_labels: Array[Label] = []
var _tg: Button
var _me_col: Control
var _compact := false
var _dm_user: Dictionary = {}
var _me_box: HBoxContainer
var _poll: Timer
var _side_box: VBoxContainer
var _side_gap: Control


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
	_apply_compact()
	get_viewport().size_changed.connect(_apply_compact)
	open_page(last_page)

	_poll = Timer.new()
	_poll.wait_time = 8.0
	_poll.autostart = true
	_poll.timeout.connect(_poll_requests)
	add_child(_poll)
	_poll_requests()
	_check_launch()
	# First visit of the day: a few orbs.
	var bonus := int(Session.get_meta("daily_bonus", 0))
	if bonus > 0:
		Session.set_meta("daily_bonus", 0)
		UI.toast(L.t("eco_daily_bonus", [bonus]), "ok")
	L.changed.connect(func(): get_tree().reload_current_scene())
	if str(Session.user.get("birthdate", "")) == "" and not _asked_birthday:
		_asked_birthday = true
		BirthdayInput.ask(self)


func _notification(what: int) -> void:
	# Coming back from the browser after pressing "Play" on the website.
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		var launch := Launcher.take()
		if not launch.is_empty():
			_joining_overlay()
			Api.request("GET", "/api/launch")
			play(launch.server, launch.game)
			return
		_check_launch()
		# Back from paying in the browser.
		Economy.check_pending_payment()


## Full-screen "Joining..." while the game scene loads after "Play" on the website.
func _joining_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	var dim := ColorRect.new()
	dim.theme = UI.theme
	dim.color = Color(UI.BG, 0.94)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var v := UI.vbox(16)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(v)
	var spin := Loading.spinner(44)
	spin.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(spin)
	var l := UI.label(L.t("joining_from_site"), 24, UI.TEXT, "black")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)


var _checking_launch := false


func _check_launch() -> void:
	if _checking_launch or not is_inside_tree():
		return
	_checking_launch = true
	var r := await Api.request("GET", "/api/launch")
	_checking_launch = false
	if r.ok and r.data.get("launch") is Dictionary and is_inside_tree():
		_joining_overlay()
		play(str(r.data.launch.server), str(r.data.launch.get("game", "playground")))


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
	side.custom_minimum_size.x = 232
	_side = side
	# Scrolls instead of stretching the window when the screen is short (20:9 phones).
	var side_scroll := ScrollContainer.new()
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	side.add_child(side_scroll)
	var v := UI.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_scroll.add_child(v)
	_side_box = v

	var brand := UI.hbox(12)
	var mark := TextureRect.new()
	mark.texture = load("res://assets/logo_mark.png")
	mark.custom_minimum_size = Vector2(44, 44)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	brand.add_child(mark)
	_brand_label = UI.label("meltiew", 30, UI.TEXT, "black")
	brand.add_child(_brand_label)
	v.add_child(brand)
	var gap := Control.new()
	gap.custom_minimum_size.y = 18
	v.add_child(gap)
	_side_gap = gap

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
		_nav_labels.append(l)
		if p.id == "friends" or p.id == "messages":
			# Floats over the button so it can sit beside the label or on the icon's corner.
			var nav_badge := UI.label("", 15, UI.INK, "black")
			_badges[p.id] = nav_badge
			var badge_bg := StyleBoxFlat.new()
			badge_bg.bg_color = UI.PINK
			badge_bg.set_corner_radius_all(12)
			badge_bg.content_margin_left = 8
			badge_bg.content_margin_right = 8
			nav_badge.add_theme_stylebox_override("normal", badge_bg)
			nav_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			nav_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			nav_badge.visible = false
			b.add_child(nav_badge)
		b.add_child(inner)
		b.pressed.connect(func():
			Sfx.click()
			open_page(p.id))
		v.add_child(b)
		_nav_buttons[p.id] = b
		_nav_icons[p.id] = [ic, l]

	v.add_child(UI.spacer(false))
	var tg := UI.button("", "flat", 40)
	_tg = tg
	tg.alignment = HORIZONTAL_ALIGNMENT_LEFT
	tg.add_theme_font_size_override("font_size", 15)
	tg.tooltip_text = L.t("telegram")
	var tg_icon := Icon.make("send", 20, UI.ACCENT)
	tg_icon.name = "Icon"
	tg.add_child(tg_icon)
	tg.pressed.connect(func(): OS.shell_open(UI.TELEGRAM))
	v.add_child(tg)
	var me_card := UI.card(12, UI.CARD, 18)
	_me_box = UI.hbox(12)
	me_card.add_child(_me_box)
	# Your own card opens your profile.
	me_card.tooltip_text = L.t("my_profile")
	UI.on_tap(me_card, func(): show_profile(str(Session.user.get("username", ""))))
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
	_me_col = col
	_me_col.visible = not _compact


## Narrow screens (phones, big interface scale): the sidebar shrinks to icons.
func _apply_compact() -> void:
	var vp_size := get_viewport_rect().size
	var compact := vp_size.x < 1120.0
	# Short screens (wide phones in landscape) get tighter rows, whatever the width.
	var short := vp_size.y < 760.0
	_compact = compact
	for id in _nav_buttons:
		_nav_buttons[id].custom_minimum_size.y = 46 if short else 56
	_side_box.add_theme_constant_override("separation", 4 if short else 8)
	_side_gap.custom_minimum_size.y = 4 if short else 18
	sb_top_bottom(short)
	_side.custom_minimum_size.x = 92 if compact else 232
	var sb := _side.get_theme_stylebox("panel") as StyleBoxFlat
	sb.content_margin_left = 12 if compact else 18
	sb.content_margin_right = 12 if compact else 18
	_brand_label.visible = not compact
	for l in _nav_labels:
		l.visible = not compact
	_tg.text = "" if compact else "        " + L.t("telegram")
	(_tg.get_node("Icon") as Control).position = Vector2(24 if compact else 16, 10)
	for id in _badges:
		var nb: Label = _badges[id]
		nb.add_theme_font_size_override("font_size", 13 if compact else 15)
		nb.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		if compact:
			nb.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			nb.offset_right = -4
			nb.offset_top = 4
			nb.offset_bottom = 4 + nb.get_minimum_size().y
		else:
			nb.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
			nb.offset_right = -14
			nb.offset_top = -nb.get_minimum_size().y / 2.0
			nb.offset_bottom = nb.get_minimum_size().y / 2.0
		nb.offset_left = nb.offset_right - nb.get_minimum_size().x
	if _me_col:
		_me_col.visible = not compact
	var m := 18 if compact else 32
	_content.add_theme_constant_override("margin_left", m)
	_content.add_theme_constant_override("margin_right", 16 if compact else 28)
	_content.add_theme_constant_override("margin_top", 18 if short else (16 if compact else 28))
	_content.add_theme_constant_override("margin_bottom", 12 if short else 28)


func sb_top_bottom(short: bool) -> void:
	var sb := _side.get_theme_stylebox("panel") as StyleBoxFlat
	sb.content_margin_top = 14 if short else 24
	sb.content_margin_bottom = 12 if short else 20


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


## Rebuilds the current page from scratch (after changes that alter its layout).
func reload_page() -> void:
	var id := _page_id
	_page_id = ""
	open_page(id)


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
		"shop":
			_page = ShopPage.new()
		"settings":
			_page = SettingsPage.new()
		"studio":
			_page = StudioPage.new()
		"communities":
			_page = CommunitiesPage.new()
		"messages":
			_page = MessagesPage.new()
			_page.open_user = _dm_user
			_dm_user = {}
		"place":
			_page = PlacePage.new()
			_page.place_id = _open_place_id
		_:
			_page = HomePage.new()
	_page.set_meta("menu", self)
	_content.add_child(_page)
	var page := _page
	page.modulate.a = 0.0
	# Slide in from where the container puts the page (its margins), once it's laid out.
	await get_tree().process_frame
	if not is_instance_valid(page):
		return
	var y := page.position.y
	page.position.y = y + 12
	var t := page.create_tween().set_parallel()
	t.tween_property(page, "modulate:a", 1.0, 0.2)
	t.tween_property(page, "position:y", y, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func set_request_badge(n: int) -> void:
	_set_badge("friends", n)


func _set_badge(id: String, n: int) -> void:
	if _badges.has(id):
		_badges[id].text = str(n)
		_badges[id].visible = n > 0
		_badges[id].offset_left = _badges[id].offset_right - _badges[id].get_minimum_size().x


func _poll_requests() -> void:
	var r := await Api.request("GET", "/api/notifications")
	if r.ok and is_instance_valid(self):
		_set_badge("friends", int(r.data.friend_requests))
		_set_badge("messages", int(r.data.dm_unread) + int(r.data.dm_requests))


## Opens Messages with a conversation to this user (from a profile).
func open_messages(u: Dictionary) -> void:
	_dm_user = u
	_page_id = ""
	open_page("messages")


## Starts the playground, optionally on a specific server ("auto", "new" or id).
func play(server := "auto", game := "playground") -> void:
	# No game without a date of birth (it decides the chat rules).
	if str(Session.user.get("birthdate", "")) == "":
		if not await BirthdayInput.ask(self):
			UI.toast(L.t("birthdate_needed"), "error")
			return
	Session.pending_server = server
	Session.pending_game = game
	UI.goto("res://scenes/game.tscn")


## Opens the communities page right on one community (from a profile).
func open_community(id: int) -> void:
	await open_page("communities")
	if _page is CommunitiesPage:
		_page.open_community(id)


func show_profile(username: String) -> void:
	var popup := ProfilePopup.new()
	popup.username = username
	popup.menu = self
	add_child(popup)
