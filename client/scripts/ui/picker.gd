class_name Picker
extends Button
## A dropdown that opens its choices in a scrollable sheet. Godot's OptionButton
## popup can't be scrolled with a finger and grows as wide as its longest item.

signal picked(id: Variant)

var title := ""
var placeholder := ""
var _items: Array = []  # [id, label]
var _selected: Variant = null


func _init(p_title := "", p_placeholder := "") -> void:
	title = p_title
	placeholder = p_placeholder
	focus_mode = Control.FOCUS_NONE
	clip_text = true
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	custom_minimum_size.y = 52
	add_theme_font_size_override("font_size", 18)
	var sb := StyleBoxFlat.new()
	sb.bg_color = UI.BG_2
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(2)
	sb.border_color = UI.LINE
	sb.content_margin_left = 14
	sb.content_margin_right = 34
	for st in ["normal", "hover", "pressed", "focus"]:
		add_theme_stylebox_override(st, sb)
	add_theme_color_override("font_color", UI.TEXT)
	add_theme_color_override("font_hover_color", UI.TEXT)
	add_theme_color_override("font_pressed_color", UI.TEXT)
	var arrow := Icon.make("down", 18, UI.MUTED)
	arrow.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	arrow.position = Vector2(-28, -9)
	add_child(arrow)
	pressed.connect(_open)
	_refresh()


func add_item(label: String, id: Variant) -> void:
	_items.append([id, label])
	_refresh()


func clear_items() -> void:
	_items.clear()
	_refresh()


func select_id(id: Variant) -> void:
	_selected = id
	_refresh()


func get_selected_id() -> Variant:
	return _selected


func _label_of(id: Variant) -> String:
	for it in _items:
		if it[0] == id:
			return it[1]
	return ""


func _refresh() -> void:
	var l := _label_of(_selected) if _selected != null else ""
	text = l if l != "" else placeholder
	add_theme_color_override("font_color", UI.TEXT if l != "" else UI.MUTED)


func _open() -> void:
	Sfx.click()
	var layer := CanvasLayer.new()
	layer.layer = 80
	get_tree().root.add_child(layer)
	var dim := ColorRect.new()
	dim.theme = UI.theme
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			layer.queue_free())
	var vp := get_viewport().get_visible_rect().size
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)
	var card := UI.card(22, UI.CARD, 18)
	card.custom_minimum_size = Vector2(minf(460.0, vp.x - 32.0), 0)
	center.add_child(card)
	var v := UI.vbox(10)
	card.add_child(v)
	var head := UI.hbox(8)
	var tl := UI.label(title if title != "" else placeholder, 22, UI.TEXT, "black")
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.clip_text = true
	head.add_child(tl)
	var close := UI.button("✕", "ghost", 44)
	close.custom_minimum_size.x = 48
	close.pressed.connect(layer.queue_free)
	head.add_child(close)
	v.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var row_h := 48.0
	scroll.custom_minimum_size.y = minf(_items.size() * (row_h + 4.0), vp.y * 0.72 - 90.0)
	v.add_child(scroll)
	var list := UI.vbox(4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var current: Button = null
	for it in _items:
		var b := UI.button(str(it[1]), "flat", int(row_h))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 18)
		# Buttons pass drags through so a finger can scroll the list.
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		if it[0] == _selected:
			b.theme_type_variation = "ChipButton"
			b.toggle_mode = true
			b.button_pressed = true
			current = b
		var id: Variant = it[0]
		b.pressed.connect(func():
			layer.queue_free()
			if id != _selected:
				_selected = id
				_refresh()
				picked.emit(id))
		list.add_child(b)
	if current:
		# Open with the current choice in view.
		await get_tree().process_frame
		if is_instance_valid(scroll):
			scroll.ensure_control_visible(current)
