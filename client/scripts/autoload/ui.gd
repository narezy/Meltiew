extends Node
## Theme, palette, scene transitions, toasts and small widget factories.

const BG := Color("#16141d")
const BG_2 := Color("#1d1a26")
const CARD := Color("#242030")
const CARD_2 := Color("#2e2940")
const LINE := Color("#3a3450")
const TEXT := Color("#f4f1ec")
const MUTED := Color("#9d96b0")
const ACCENT := Color("#b89cff")
const ACCENT_DARK := Color("#8f6ff0")
const MINT := Color("#7ee0c3")
const PINK := Color("#ff8fb1")
const DANGER := Color("#ff6b7a")
const ONLINE := Color("#5fe08e")
const INK := Color("#17141f")
const TELEGRAM := "https://t.me/meltiew"

const SWATCHES := [
	"#f5f1ec", "#ffd9c2", "#e8b48f", "#b07852", "#6b4431", "#302d38",
	"#baa4e2", "#8f6ff0", "#6c8cff", "#4cc9f0", "#7ee0c3", "#5fe08e",
	"#c7f464", "#ffd166", "#ffa552", "#ff6b6b", "#ff8fb1", "#e056fd",
	"#ffffff", "#c9c5d3", "#8a8499", "#4a4458", "#1f1c27", "#000000",
]

var theme: Theme
var font_regular: FontVariation
var font_bold: FontVariation
var font_black: FontVariation

var _fade_layer: CanvasLayer
var _fade: ColorRect
var _toast_box: VBoxContainer
var _busy := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_fonts()
	theme = _build_theme()
	get_tree().root.theme = theme
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100
	add_child(_fade_layer)
	_fade = ColorRect.new()
	_fade.color = BG
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	_fade_layer.add_child(_fade)
	_toast_box = VBoxContainer.new()
	_toast_box.theme = theme
	# Bottom center, like Android snackbars: never covers page tabs or titles.
	_toast_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast_box.offset_bottom = -28
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.add_theme_constant_override("separation", 8)
	_fade_layer.add_child(_toast_box)
	Api.unauthorized.connect(_on_unauthorized)
	Api.update_required.connect(show_update_required)
	apply_ui_scale()
	Session.settings_changed.connect(apply_ui_scale)


func _on_unauthorized() -> void:
	if Session.token == "":
		return
	Net.close()
	Session.clear()
	toast(L.t("session_expired"), "error")
	goto("res://scenes/auth.tscn")


var _update_layer: CanvasLayer


## Full-screen "please update" screen for outdated app versions ("Later" closes it).
func show_update_required(message: String, url: String) -> void:
	if _update_layer:
		return
	_update_layer = CanvasLayer.new()
	_update_layer.layer = 120
	add_child(_update_layer)
	var bg := ColorRect.new()
	bg.theme = theme
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_update_layer.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(center)
	var v := vbox(18)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(v)
	var mark := TextureRect.new()
	mark.texture = load("res://assets/logo_mark.png")
	mark.custom_minimum_size = Vector2(110, 110)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(mark)
	var title := label(L.t("update_title"), 34, TEXT, "black")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var body := label(message if message != "" else L.t("update_body"), 20, MUTED)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = 560
	v.add_child(body)
	var b := button(L.t("update_button"), "primary", 60)
	b.custom_minimum_size.x = 300
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func(): OS.shell_open(url))
	v.add_child(b)
	var later := button(L.t("update_later"), "ghost", 48)
	later.custom_minimum_size.x = 300
	later.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	later.pressed.connect(func():
		_update_layer.queue_free()
		_update_layer = null)
	v.add_child(later)
	var ver := label(L.t("your_version", [Api.version()]), 15, MUTED)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ver)


# --- scene flow -------------------------------------------------------------

func goto(path: String) -> void:
	if _busy:
		return
	_busy = true
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var t := create_tween()
	t.tween_property(_fade, "modulate:a", 1.0, 0.18)
	await t.finished
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	var t2 := create_tween()
	t2.tween_property(_fade, "modulate:a", 0.0, 0.25)
	await t2.finished
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false


func toast(text: String, kind := "info") -> void:
	var panel := PanelContainer.new()
	var sb := _box(CARD_2, 14, 18, 12)
	sb.border_width_left = 4
	sb.border_color = {"error": DANGER, "ok": MINT}.get(kind, ACCENT)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 10
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := label(text, 19)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 280
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(l)
	_toast_box.add_child(panel)
	panel.modulate.a = 0.0
	var t := panel.create_tween()
	t.tween_property(panel, "modulate:a", 1.0, 0.2)
	t.tween_interval(2.6 if kind != "error" else 3.6)
	t.tween_property(panel, "modulate:a", 0.0, 0.3)
	t.tween_callback(panel.queue_free)


# --- widget factories -------------------------------------------------------

## True when the logical window is narrow (phones, small windows): pages use tighter layouts.
func is_compact() -> bool:
	return get_viewport().get_visible_rect().size.x < 1120.0


func label(text: String, size := 20, color := TEXT, weight := "regular") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if weight == "bold":
		l.add_theme_font_override("font", font_bold)
	elif weight == "black":
		l.add_theme_font_override("font", font_black)
	return l


func button(text: String, variant := "primary", min_h := 56) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = min_h
	b.focus_mode = Control.FOCUS_NONE
	match variant:
		"ghost":
			b.theme_type_variation = "GhostButton"
		"danger":
			b.theme_type_variation = "DangerButton"
		"mint":
			b.theme_type_variation = "MintButton"
		"flat":
			b.theme_type_variation = "FlatButton"
	b.pressed.connect(func(): Sfx.click())
	return b


func input(placeholder: String, secret := false) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.secret = secret
	e.custom_minimum_size.y = 56
	e.clear_button_enabled = not secret
	e.caret_blink = true
	return e


func card(pad := 20, color := CARD, radius := 22) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.add_theme_stylebox_override("panel", _box(color, radius, pad, pad))
	return p


func vbox(sep := 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


func hbox(sep := 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


func spacer(h := true) -> Control:
	var c := Control.new()
	if h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


func dot(color: Color, size := 12) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(size, size)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_theme_stylebox_override("panel", _box(color, size, 0, 0))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## Round 3D bust portrait of the user (rendered by Busts, cached per look).
func avatar_badge(u: Dictionary, size := 52) -> Control:
	var colors := Session.colors_of(u)
	var p := Panel.new()
	p.custom_minimum_size = Vector2(size, size)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := Color(colors.torso).lerp(CARD_2, 0.55)
	var sb := _box(bg, size, 0, 0)
	p.add_theme_stylebox_override("panel", sb)
	var img := BustImage.new(u, size * 0.5)
	img.set_anchors_preset(Control.PRESET_FULL_RECT)
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(img)
	return p


## Closes a popup only on a tap that starts and ends on the dim around `card`:
## pressing inside the card, or dragging to scroll, never closes it.
func close_outside(dim: Control, card: Control, on_close: Callable) -> void:
	var st := {"down": false, "at": Vector2.ZERO}
	dim.gui_input.connect(func(e: InputEvent):
		if not (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT):
			return
		var p: Vector2 = dim.get_global_transform() * e.position
		var outside := not card.get_global_rect().has_point(p)
		if e.pressed:
			st.down = outside
			st.at = p
			return
		var close: bool = st.down and outside and p.distance_to(st.at) < 16.0
		st.down = false
		if close:
			on_close.call())


func confirm(parent: Node, title: String, text: String, ok_text := "", danger := false) -> bool:
	if ok_text == "":
		ok_text = L.t("yes")
	var layer := CanvasLayer.new()
	layer.layer = 50
	parent.add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.theme = theme
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var c := card(28, CARD, 26)
	c.custom_minimum_size.x = 440
	center.add_child(c)
	var v := vbox(16)
	c.add_child(v)
	v.add_child(label(title, 26, TEXT, "black"))
	var body := label(text, 19, MUTED)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(body)
	var row := hbox(12)
	v.add_child(row)
	var no := button(L.t("cancel"), "ghost")
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var yes := button(ok_text, "danger" if danger else "primary")
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(no)
	row.add_child(yes)
	var result := [false]
	var done := [false]
	no.pressed.connect(func(): done[0] = true)
	yes.pressed.connect(func():
		result[0] = true
		done[0] = true)
	while not done[0]:
		await get_tree().process_frame
	layer.queue_free()
	return result[0]


func relative_time(ms: float) -> String:
	var sec := int((Time.get_unix_time_from_system() * 1000.0 - ms) / 1000.0)
	if sec < 60:
		return L.t("time_now")
	if sec < 3600:
		return L.t("time_min", [sec / 60])
	if sec < 86400:
		return L.t("time_hour", [sec / 3600])
	return L.t("time_day", [sec / 86400])


# --- theme ------------------------------------------------------------------

func _build_fonts() -> void:
	var base: FontFile = load("res://assets/fonts/Nunito.ttf")
	# Nunito covers Latin and Cyrillic; CJK, Arabic, Indic, Thai... come from the system fonts.
	var system := SystemFont.new()
	system.font_names = PackedStringArray(["sans-serif", "Noto Sans", "Noto Sans CJK SC", "Noto Sans Arabic", "Noto Sans Devanagari", "Roboto"])
	base.fallbacks = [system]
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
	font_regular = FontVariation.new()
	font_regular.base_font = base
	font_regular.variation_opentype = {wght: 600}
	font_bold = FontVariation.new()
	font_bold.base_font = base
	font_bold.variation_opentype = {wght: 800}
	font_black = FontVariation.new()
	font_black.base_font = base
	font_black.variation_opentype = {wght: 900}


func _box(color: Color, radius := 16, px := 16, py := 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = px
	sb.content_margin_right = px
	sb.content_margin_top = py
	sb.content_margin_bottom = py
	sb.anti_aliasing = true
	sb.corner_detail = 10
	return sb


func _button_styles(t: Theme, type: String, base: Color, fg: Color, border := Color.TRANSPARENT) -> void:
	var normal := _box(base, 16, 22, 12)
	if border.a > 0:
		normal.set_border_width_all(2)
		normal.border_color = border
	var hover := normal.duplicate()
	hover.bg_color = base.lightened(0.08)
	var pressed := normal.duplicate()
	pressed.bg_color = base.darkened(0.12)
	pressed.content_margin_top = 14
	pressed.content_margin_bottom = 10
	var disabled := normal.duplicate()
	disabled.bg_color = base.darkened(0.45)
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("hover_pressed", type, pressed)
	t.set_stylebox("disabled", type, disabled)
	t.set_stylebox("focus", type, StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, type, fg)
	t.set_color("font_disabled_color", type, fg.darkened(0.4))
	t.set_font("font", type, font_bold)


func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font_regular
	t.default_font_size = 20

	t.set_color("font_color", "Label", TEXT)
	_button_styles(t, "Button", ACCENT, INK)
	t.set_font_size("font_size", "Button", 21)
	for v in ["GhostButton", "DangerButton", "MintButton", "FlatButton", "TabButton", "ChipButton"]:
		t.set_type_variation(v, "Button")
	_button_styles(t, "GhostButton", CARD_2, TEXT)
	_button_styles(t, "DangerButton", DANGER, INK)
	_button_styles(t, "MintButton", MINT, INK)
	_button_styles(t, "FlatButton", Color(1, 1, 1, 0.0), MUTED)

	# Bottom navigation tab: transparent until selected.
	_button_styles(t, "TabButton", Color(0, 0, 0, 0), MUTED)
	var tab_on := _box(CARD_2, 16, 18, 10)
	t.set_stylebox("pressed", "TabButton", tab_on)
	t.set_stylebox("hover_pressed", "TabButton", tab_on)
	t.set_color("font_pressed_color", "TabButton", TEXT)
	t.set_color("font_hover_pressed_color", "TabButton", TEXT)
	t.set_font_size("font_size", "TabButton", 18)

	_button_styles(t, "ChipButton", CARD_2, TEXT)
	var chip_on := _box(ACCENT, 16, 22, 12)
	t.set_stylebox("pressed", "ChipButton", chip_on)
	t.set_stylebox("hover_pressed", "ChipButton", chip_on)
	t.set_color("font_pressed_color", "ChipButton", INK)
	t.set_color("font_hover_pressed_color", "ChipButton", INK)

	var le := _box(BG_2, 14, 18, 12)
	le.set_border_width_all(2)
	le.border_color = LINE
	var le_focus := le.duplicate()
	le_focus.border_color = ACCENT
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", le_focus)
	t.set_stylebox("read_only", "LineEdit", le)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", MUTED.darkened(0.15))
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", ACCENT_DARK)
	t.set_font_size("font_size", "LineEdit", 20)
	t.set_stylebox("normal", "TextEdit", le)
	t.set_stylebox("focus", "TextEdit", le_focus)
	t.set_color("font_color", "TextEdit", TEXT)
	t.set_color("font_placeholder_color", "TextEdit", MUTED.darkened(0.15))
	t.set_color("caret_color", "TextEdit", ACCENT)
	t.set_color("background_color", "TextEdit", Color(0, 0, 0, 0))

	t.set_stylebox("panel", "PanelContainer", _box(CARD, 22, 20, 20))
	t.set_stylebox("panel", "Panel", _box(CARD, 22, 0, 0))

	var grabber := _box(LINE, 6, 0, 0)
	var grabber_hi := _box(ACCENT, 6, 0, 0)
	var track := _box(Color(0, 0, 0, 0), 6, 3, 3)
	for sb_type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sb_type, track)
		t.set_stylebox("grabber", sb_type, grabber)
		t.set_stylebox("grabber_highlight", sb_type, grabber_hi)
		t.set_stylebox("grabber_pressed", sb_type, grabber_hi)

	var slider := _box(CARD_2, 8, 0, 4)
	var slider_fill := _box(ACCENT, 8, 0, 4)
	t.set_stylebox("slider", "HSlider", slider)
	t.set_stylebox("grabber_area", "HSlider", slider_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)
	var knob := Image.create(28, 28, false, Image.FORMAT_RGBA8)
	knob.fill(Color(0, 0, 0, 0))
	for x in 28:
		for y in 28:
			var d := Vector2(x - 13.5, y - 13.5).length()
			if d <= 13.0:
				knob.set_pixel(x, y, TEXT if d < 11.0 else ACCENT)
	var knob_tex := ImageTexture.create_from_image(knob)
	t.set_icon("grabber", "HSlider", knob_tex)
	t.set_icon("grabber_highlight", "HSlider", knob_tex)

	var check_on := Image.create(44, 26, false, Image.FORMAT_RGBA8)
	var check_off := Image.create(44, 26, false, Image.FORMAT_RGBA8)
	for img_data in [[check_on, ACCENT, 31.0], [check_off, LINE, 13.0]]:
		var img: Image = img_data[0]
		img.fill(Color(0, 0, 0, 0))
		for x in 44:
			for y in 26:
				var cx := clampf(x, 13.0, 31.0)
				if Vector2(x - cx, y - 12.5).length() <= 12.5:
					img.set_pixel(x, y, img_data[1])
				if Vector2(x - img_data[2], y - 12.5).length() <= 9.5:
					img.set_pixel(x, y, TEXT)
	t.set_icon("checked", "CheckButton", ImageTexture.create_from_image(check_on))
	t.set_icon("unchecked", "CheckButton", ImageTexture.create_from_image(check_off))
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_color("font_hover_color", "CheckButton", TEXT)
	t.set_color("font_pressed_color", "CheckButton", TEXT)
	t.set_color("font_hover_pressed_color", "CheckButton", TEXT)
	t.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())
	for s in ["normal", "hover", "pressed", "hover_pressed"]:
		t.set_stylebox(s, "CheckButton", StyleBoxEmpty.new())

	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("bold_font", "RichTextLabel", font_bold)
	t.set_font_size("normal_font_size", "RichTextLabel", 19)
	t.set_font_size("bold_font_size", "RichTextLabel", 19)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_stylebox("focus", "RichTextLabel", StyleBoxEmpty.new())
	return t


## A wrapped label for the little bit of Markdown our docs use: **bold**, *italic*,
## `code` and [links](url) (shown as their text).
func md_label(text: String, size := 15, color := MUTED) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_font_size_override("italics_font_size", size)
	r.add_theme_color_override("default_color", color)
	r.text = md_to_bbcode(text)
	return r


static func md_to_bbcode(md: String) -> String:
	# Brackets are BBCode, so real ones are escaped (links become their text first).
	var out := md.replace("[", "\u0001").replace("]", "\u0002")
	var re := RegEx.create_from_string("\u0001(.+?)\u0002\\([^)\\s]*\\)")
	out = re.sub(out, "$1", true)
	out = out.replace("\u0001", "[lb]").replace("\u0002", "[rb]")
	re = RegEx.create_from_string("`([^`]+)`")
	out = re.sub(out, "[color=#c9b8ff]$1[/color]", true)
	re = RegEx.create_from_string("\\*\\*(.+?)\\*\\*")
	out = re.sub(out, "[b]$1[/b]", true)
	re = RegEx.create_from_string("(^|[^*\\w])\\*([^*\\s][^*]*?)\\*(?!\\w)")
	out = re.sub(out, "$1[i]$2[/i]", true)
	return out


## Calls `cb` on a tap (press + release without dragging), so rows inside
## scroll containers don't fire while the user is scrolling.
func on_tap(c: Control, cb: Callable) -> void:
	var start := [Vector2.ZERO]
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	c.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				start[0] = e.global_position
			elif e.global_position.distance_to(start[0]) < 14.0:
				cb.call())


## Small colored chip for staff roles ("OWNER", "ADMIN"); null for everyone else.
func role_badge(u: Dictionary, size := 13) -> Control:
	var role := str(u.get("role", "user"))
	if role != "owner" and role != "admin":
		return null
	var l := label(L.t("role_" + role), size, INK, "black")
	var sb := _box(Color("#ffd166") if role == "owner" else MINT, 8, 7, 1)
	l.add_theme_stylebox_override("normal", sb)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Display name with the role badge next to it.
func name_row(u: Dictionary, size := 20, color := TEXT, weight := "bold") -> HBoxContainer:
	var row := hbox(8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := label(str(u.get("display_name", "?")), size, color, weight)
	row.add_child(n)
	var badge := role_badge(u, maxi(11, size - 7))
	if badge:
		row.add_child(badge)
	return row


## Report dialog: pick a reason, optional details, sends to the admin queue.
## `about` = {"place_id": ...} or {"comment_id": ...} reports that instead of the player.
func report(parent: Node, u: Dictionary, about := {}) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 60
	parent.add_child(layer)
	var dim := ColorRect.new()
	dim.theme = theme
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var c := card(26, CARD, 26)
	c.custom_minimum_size.x = 480
	center.add_child(c)
	var v := vbox(12)
	c.add_child(v)
	var title := L.t("report_title", [u.get("display_name", "")])
	var reasons := ["chat", "name", "avatar", "cheating", "other"]
	if about.has("place_id"):
		title = L.t("report_place_title")
		reasons = ["place", "name", "other"]
	elif about.has("comment_id"):
		title = L.t("report_comment_title")
		reasons = ["comment", "chat", "other"]
	var t := label(title, 24, TEXT, "black")
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	var reason := [reasons[0]]
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 8)
	chips.add_theme_constant_override("v_separation", 8)
	v.add_child(chips)
	for r in reasons:
		var b := button(L.t("report_" + r), "flat", 42)
		b.theme_type_variation = "ChipButton"
		b.toggle_mode = true
		b.button_pressed = r == reason[0]
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(func():
			reason[0] = r
			for other in chips.get_children():
				other.button_pressed = other == b)
		chips.add_child(b)
	var details := input(L.t("report_details"))
	details.max_length = 300
	v.add_child(details)
	var row := hbox(10)
	v.add_child(row)
	var cancel_b := button(L.t("cancel"), "ghost")
	cancel_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_b.pressed.connect(layer.queue_free)
	row.add_child(cancel_b)
	var send := button(L.t("report_send"), "danger")
	send.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	send.pressed.connect(func():
		send.disabled = true
		var body := {"user_id": u.get("id"), "reason": reason[0], "details": details.text}
		body.merge(about)
		var r := await Api.request("POST", "/api/report", body)
		toast(str(r.data.get("message", L.t("done"))) if r.ok else r.message, "ok" if r.ok else "error")
		layer.queue_free())
	row.add_child(send)


## Space taken by notches, rounded corners and system bars, in UI units:
## (left, top, right, bottom). Zero on desktops.
func safe_insets(vp: Viewport) -> Vector4:
	if not OS.has_feature("mobile"):
		return Vector4.ZERO
	var win := Vector2(DisplayServer.window_get_size())
	var safe := DisplayServer.get_display_safe_area()
	if win.x <= 0.0 or win.y <= 0.0 or safe.size.x <= 0:
		return Vector4.ZERO
	var k := vp.get_visible_rect().size / win
	return Vector4(
		maxf(0.0, safe.position.x) * k.x,
		maxf(0.0, safe.position.y) * k.y,
		maxf(0.0, win.x - safe.end.x) * k.x,
		maxf(0.0, win.y - safe.end.y) * k.y)


## Interface size. Phones get bigger UI by default; the Settings slider overrides it.
func apply_ui_scale() -> void:
	var s := float(Session.settings.get("ui_scale", 0.0))
	if s <= 0.0:
		s = default_ui_scale()
	get_tree().root.content_scale_factor = s


func default_ui_scale() -> float:
	if OS.has_feature("mobile"):
		# Base layout is 1280x720; on a phone that reads tiny, so zoom it up.
		var screen := DisplayServer.screen_get_size()
		var inches := Vector2(screen).length() / maxf(float(DisplayServer.screen_get_dpi()), 1.0)
		return 1.35 if inches < 7.5 else 1.15
	return 1.0
