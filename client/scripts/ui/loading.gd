class_name Loading
extends RefCounted
## Loading states for pages that wait on the network: a spinner, pulsing skeleton
## placeholders shaped like the content, and an error block with a retry button.
## Slow internet should never look like an empty page.


## Spinning arc.
class Spinner extends Control:
	var color := UI.ACCENT
	var _angle := 0.0

	func _init(px := 40.0, tint := UI.ACCENT) -> void:
		custom_minimum_size = Vector2(px, px)
		color = tint
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_angle = fmod(_angle + delta * TAU * 1.1, TAU)
		queue_redraw()

	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		var w := maxf(3.0, r * 0.22)
		draw_arc(size * 0.5, r - w, 0.0, TAU, 48, Color(color, 0.18), w, true)
		draw_arc(size * 0.5, r - w, _angle, _angle + TAU * 0.3, 24, color, w, true)


static func spinner(px := 40.0, tint := UI.ACCENT) -> Control:
	return Spinner.new(px, tint)


## Centered spinner with an optional caption, filling the space it's given.
static func block(text := "", px := 44.0) -> Control:
	var c := CenterContainer.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size.y = px * 3.0
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := UI.vbox(12)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sp := spinner(px)
	sp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(sp)
	if text != "":
		var l := UI.label(text, 17, UI.MUTED)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
	c.add_child(v)
	return c


## Gray rounded placeholder that gently pulses.
static func skeleton(px: Vector2, radius := 16) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = px
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = UI.CARD_2
	sb.set_corner_radius_all(radius)
	p.add_theme_stylebox_override("panel", sb)
	var t := p.create_tween().set_loops()
	t.tween_property(p, "modulate:a", 0.45, 0.7).set_trans(Tween.TRANS_SINE)
	t.tween_property(p, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)
	return p


## Place card placeholder (same size as HomePage.place_card).
static func place_card_skeleton() -> Control:
	var c := UI.card(12, UI.CARD, 22)
	c.custom_minimum_size.x = 330
	var v := UI.vbox(10)
	c.add_child(v)
	v.add_child(skeleton(Vector2(306, 172)))
	v.add_child(skeleton(Vector2(180, 22), 8))
	v.add_child(skeleton(Vector2(120, 16), 8))
	v.add_child(skeleton(Vector2(210, 16), 8))
	return c


## List row placeholder: avatar circle and two text lines.
static func row_skeleton(avatar := 52.0) -> Control:
	var c := UI.card(14, UI.CARD, 20)
	var h := UI.hbox(14)
	c.add_child(h)
	h.add_child(skeleton(Vector2(avatar, avatar), int(avatar / 2)))
	var v := UI.vbox(8)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_child(skeleton(Vector2(170, 18), 8))
	v.add_child(skeleton(Vector2(110, 14), 7))
	h.add_child(v)
	return c


## "Couldn't load" with the reason and a retry button.
static func error_block(message: String, retry: Callable) -> Control:
	var c := CenterContainer.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size.y = 180
	var v := UI.vbox(12)
	v.add_child(Icon.make("refresh", 40, UI.MUTED))
	(v.get_child(0) as Control).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var l := UI.label(message if message != "" else L.t("load_failed"), 17, UI.MUTED)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 320
	v.add_child(l)
	var b := UI.button(L.t("retry"), "ghost", 48)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(retry)
	v.add_child(b)
	c.add_child(v)
	return c
