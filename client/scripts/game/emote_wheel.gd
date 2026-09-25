class_name EmoteWheel
extends Control
## Radial emote picker: wave, hearts, dance, cheer, sit, clap, laugh.

signal picked(emote: String)

const ITEMS := [
	["wave", "hand"], ["heart", "heart"], ["dance", "music"], ["cheer", "star"],
	["sit", "chair"], ["clap", "clap"], ["laugh", "smile"],
]
const RADIUS := 150.0
const BTN := 92.0

var _items: Array[Control] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	for i in ITEMS.size():
		var it: Array = ITEMS[i]
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(BTN, BTN)
		b.size = Vector2(BTN, BTN)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(UI.BG_2, 0.92)
		sb.set_corner_radius_all(int(BTN / 2))
		sb.set_border_width_all(2)
		sb.border_color = Color(1, 1, 1, 0.14)
		var sb_hi := sb.duplicate()
		sb_hi.bg_color = UI.ACCENT_DARK
		for st in ["normal", "focus"]:
			b.add_theme_stylebox_override(st, sb)
		for st in ["hover", "pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(st, sb_hi)
		var ic := Icon.make(it[1], 34)
		ic.position = Vector2((BTN - 34) / 2.0, 16)
		b.add_child(ic)
		var l := UI.label(L.t("emote_" + it[0]), 14, UI.TEXT, "bold")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size = Vector2(BTN, 20)
		l.position = Vector2(0, 56)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(l)
		var emote: String = it[0]
		b.pressed.connect(func():
			Sfx.click()
			close()
			picked.emit(emote))
		add_child(b)
		_items.append(b)
	var center := Button.new()
	center.focus_mode = Control.FOCUS_NONE
	center.custom_minimum_size = Vector2(70, 70)
	center.size = Vector2(70, 70)
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(UI.CARD_2, 0.95)
	csb.set_corner_radius_all(35)
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		center.add_theme_stylebox_override(st, csb)
	var x := Icon.make("close", 24)
	x.position = Vector2(23, 23)
	center.add_child(x)
	center.pressed.connect(close)
	add_child(center)
	_items.append(center)
	resized.connect(_layout)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()


func open() -> void:
	visible = true
	_layout()
	for i in _items.size():
		var c := _items[i]
		c.scale = Vector2(0.4, 0.4)
		c.pivot_offset = c.size / 2.0
		c.modulate.a = 0.0
		var t := c.create_tween().set_parallel()
		t.tween_property(c, "scale", Vector2.ONE, 0.22).set_delay(i * 0.02).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(c, "modulate:a", 1.0, 0.12).set_delay(i * 0.02)


func close() -> void:
	visible = false


func _layout() -> void:
	var c := get_viewport_rect().size / 2.0
	for i in ITEMS.size():
		var a := -PI / 2.0 + TAU * i / ITEMS.size()
		_items[i].position = c + Vector2(cos(a), sin(a)) * RADIUS - Vector2(BTN, BTN) / 2.0
	_items[-1].position = c - Vector2(35, 35)
