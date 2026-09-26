class_name PlaceGui
extends Control
## Draws a place's UI (ScreenGui -> Frames, labels, buttons, images...) from a PlaceTree.
## In the game the root is the LocalPlayer's PlayerGui; in Studio it's StarterGui.
## Layout follows the scripting API: UDim2 Position/Size (scale of the parent + pixels),
## AnchorPoint, UIPadding, UIListLayout, UIGridLayout; style comes from UICorner/UIStroke.

signal gui_event(id: String, ev: String, value: Variant)

var tree: PlaceTree
var root_id := ""
var strings := {}
var lang := "en"
## Studio: clicking selects instead of pressing; everything stays visible.
var editing := false

var _controls := {}  # id -> Control (the node's own control)
var _content := {}  # id -> Control that holds its children (ScrollingFrame canvas)
var _dirty := true
var _last_screen := Vector2.ZERO

const DECOR := ["UICorner", "UIStroke", "UIPadding", "UIListLayout", "UIGridLayout"]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(func(): _dirty = true)


func bind(t: PlaceTree, root: String) -> void:
	tree = t
	tree.added.connect(_on_added)
	tree.removed.connect(_on_removed)
	tree.changed.connect(_on_changed)
	tree.reparented.connect(_on_reparented)
	set_root(root)


func set_root(root: String) -> void:
	for id in _controls.keys():
		if is_instance_valid(_controls[id]):
			_controls[id].queue_free()
	_controls.clear()
	_content.clear()
	root_id = root
	if root != "" and tree.has(root):
		for id in tree.descendants(root):
			_build(id)
	_dirty = true


func control_of(id: String) -> Control:
	return _controls.get(id)


func localize(text: String) -> String:
	if text.begins_with("$") and strings.has(text.substr(1)):
		var e: Dictionary = strings[text.substr(1)]
		return str(e.get(lang, e.get("en", text)))
	return text


func _in_root(id: String) -> bool:
	return root_id != "" and tree.is_descendant(id, root_id)


func _is_gui(id: String) -> bool:
	var c := tree.cls(id)
	return c == "ScreenGui" or StudioSchema.is_a(c, "GuiObject")


func _on_added(id: String) -> void:
	if _in_root(id):
		_build(id)
		_restyle_parent_if_decor(id)
	_dirty = true


func _on_removed(id: String, parent: String) -> void:
	if _controls.has(id):
		if is_instance_valid(_controls[id]):
			_controls[id].queue_free()
		_controls.erase(id)
		_content.erase(id)
	if _controls.has(parent):
		_style(parent)
	_dirty = true


func _on_reparented(id: String, old: String) -> void:
	var ids := [id] + tree.descendants(id)
	for x in ids:
		if _controls.has(x):
			_controls[x].queue_free()
			_controls.erase(x)
			_content.erase(x)
	if _controls.has(old):
		_style(old)
	if _in_root(id):
		for x in ids:
			_build(x)
		_restyle_parent_if_decor(id)
	_dirty = true


func _on_changed(id: String, key: String) -> void:
	if _controls.has(id):
		_style(id)
	else:
		_restyle_parent_if_decor(id)
	_dirty = true


func _restyle_parent_if_decor(id: String) -> void:
	if tree.cls(id) in DECOR:
		var p := tree.parent_of(id)
		if _controls.has(p):
			_style(p)


# --- building ----------------------------------------------------------------------

func _parent_holder(id: String) -> Control:
	var p := tree.parent_of(id)
	if p == root_id:
		return self
	return _content.get(p, _controls.get(p))


func _build(id: String) -> void:
	if _controls.has(id) or not _is_gui(id):
		return
	var holder := _parent_holder(id)
	if holder == null:
		return
	var c := tree.cls(id)
	var ctl: Control
	match c:
		"ScreenGui":
			ctl = Control.new()
			ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		"TextBox":
			var le := LineEdit.new()
			le.flat = true
			le.text_changed.connect(func(t): gui_event.emit(id, "text", t))
			le.text_submitted.connect(func(_t):
				le.release_focus())
			le.focus_entered.connect(func(): gui_event.emit(id, "focused", null))
			le.focus_exited.connect(func(): gui_event.emit(id, "focus_lost", Input.is_key_pressed(KEY_ENTER)))
			ctl = le
		_:
			ctl = Panel.new()
			if c in ["TextLabel", "TextButton"]:
				var l := Label.new()
				l.name = "Text"
				l.set_anchors_preset(Control.PRESET_FULL_RECT)
				l.mouse_filter = Control.MOUSE_FILTER_IGNORE
				l.clip_text = true
				ctl.add_child(l)
			if c in ["ImageLabel", "ImageButton"]:
				var tr := TextureRect.new()
				tr.name = "Image"
				tr.set_anchors_preset(Control.PRESET_FULL_RECT)
				tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
				tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				ctl.add_child(tr)
			if c == "ScrollingFrame":
				var sc := ScrollContainer.new()
				sc.name = "Scroll"
				sc.set_anchors_preset(Control.PRESET_FULL_RECT)
				ctl.add_child(sc)
				var canvas := Control.new()
				canvas.mouse_filter = Control.MOUSE_FILTER_PASS
				sc.add_child(canvas)
				_content[id] = canvas
			if c in ["TextButton", "ImageButton"]:
				ctl.gui_input.connect(func(e): _button_input(id, e))
				ctl.mouse_entered.connect(func():
					gui_event.emit(id, "enter", null)
					_hover(id, true))
				ctl.mouse_exited.connect(func():
					gui_event.emit(id, "leave", null)
					_hover(id, false))
			else:
				ctl.mouse_entered.connect(func(): gui_event.emit(id, "enter", null))
				ctl.mouse_exited.connect(func(): gui_event.emit(id, "leave", null))
	ctl.set_meta("place_id", id)
	holder.add_child(ctl)
	_controls[id] = ctl
	_style(id)
	for k in tree.kids(id):
		_build(k)


func _button_input(id: String, e: InputEvent) -> void:
	if editing:
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		var ctl: Control = _controls.get(id)
		if ctl == null:
			return
		if e.pressed:
			ctl.set_meta("down", true)
			if tree.prop(id, "AutoButtonColor") if tree.cls(id) == "TextButton" else true:
				ctl.modulate = Color(0.82, 0.82, 0.82)
		elif ctl.get_meta("down", false):
			ctl.set_meta("down", false)
			ctl.modulate = Color.WHITE
			if Rect2(Vector2.ZERO, ctl.size).has_point(e.position):
				Sfx.click()
				gui_event.emit(id, "activated", null)
		ctl.accept_event()


func _hover(id: String, on: bool) -> void:
	var ctl: Control = _controls.get(id)
	if ctl and not ctl.get_meta("down", false):
		var auto: bool = tree.prop(id, "AutoButtonColor") if tree.cls(id) == "TextButton" else true
		ctl.modulate = Color(1.08, 1.08, 1.08) if on and auto else Color.WHITE


func _style(id: String) -> void:
	var ctl: Control = _controls[id]
	var c := tree.cls(id)
	if c == "ScreenGui":
		ctl.visible = tree.prop(id, "Enabled") or editing
		ctl.z_index = int(tree.prop(id, "DisplayOrder"))
		return
	ctl.visible = tree.prop(id, "Visible")
	ctl.z_index = int(tree.prop(id, "ZIndex"))
	ctl.rotation = deg_to_rad(float(tree.prop(id, "Rotation")))
	var bg: Color = tree.prop(id, "BackgroundColor")
	bg.a = 1.0 - float(tree.prop(id, "BackgroundTransparency"))
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	var corner := tree.child_of_class(id, "UICorner")
	if corner != "":
		var cr: Variant = tree.prop(corner, "CornerRadius")
		# A UDim here (older files) means its offset.
		sb.set_corner_radius_all(int(cr[1]) if cr is PackedFloat32Array and cr.size() > 1 else int(cr) if cr is float or cr is int else 12)
		sb.anti_aliasing = true
	var stroke := tree.child_of_class(id, "UIStroke")
	if stroke != "":
		var sc: Color = tree.prop(stroke, "Color")
		sc.a = 1.0 - float(tree.prop(stroke, "Transparency"))
		sb.border_color = sc
		sb.set_border_width_all(int(tree.prop(stroke, "Thickness")))
	var catches := bg.a > 0.01 or c in ["TextButton", "ImageButton", "TextBox", "ScrollingFrame"]
	ctl.mouse_filter = Control.MOUSE_FILTER_STOP if catches else Control.MOUSE_FILTER_IGNORE
	if ctl is LineEdit:
		var le := ctl as LineEdit
		for st in ["normal", "focus", "read_only"]:
			le.add_theme_stylebox_override(st, sb)
		var txt := str(tree.prop(id, "Text"))
		if le.text != txt:
			le.text = txt
		le.placeholder_text = localize(str(tree.prop(id, "PlaceholderText")))
		le.add_theme_color_override("font_color", tree.prop(id, "TextColor"))
		le.add_theme_font_size_override("font_size", int(tree.prop(id, "TextSize")))
		le.add_theme_font_override("font", _font(id))
		le.alignment = {"Left": HORIZONTAL_ALIGNMENT_LEFT, "Right": HORIZONTAL_ALIGNMENT_RIGHT}.get(str(tree.prop(id, "TextXAlignment")), HORIZONTAL_ALIGNMENT_CENTER)
		return
	ctl.add_theme_stylebox_override("panel", sb)
	var l := ctl.get_node_or_null("Text") as Label
	if l:
		l.text = localize(str(tree.prop(id, "Text")))
		var tc: Color = tree.prop(id, "TextColor")
		tc.a = 1.0 - float(tree.prop(id, "TextTransparency"))
		l.add_theme_color_override("font_color", tc)
		l.add_theme_font_size_override("font_size", int(tree.prop(id, "TextSize")))
		l.add_theme_font_override("font", _font(id))
		l.horizontal_alignment = {"Left": HORIZONTAL_ALIGNMENT_LEFT, "Right": HORIZONTAL_ALIGNMENT_RIGHT}.get(str(tree.prop(id, "TextXAlignment")), HORIZONTAL_ALIGNMENT_CENTER)
		l.vertical_alignment = {"Top": VERTICAL_ALIGNMENT_TOP, "Bottom": VERTICAL_ALIGNMENT_BOTTOM}.get(str(tree.prop(id, "TextYAlignment")), VERTICAL_ALIGNMENT_CENTER)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if tree.prop(id, "TextWrapped") else TextServer.AUTOWRAP_OFF
		var pad := tree.child_of_class(id, "UIPadding")
		l.offset_left = float(tree.prop(pad, "Left")) if pad != "" else 0.0
		l.offset_right = -float(tree.prop(pad, "Right")) if pad != "" else 0.0
		l.offset_top = float(tree.prop(pad, "Top")) if pad != "" else 0.0
		l.offset_bottom = -float(tree.prop(pad, "Bottom")) if pad != "" else 0.0
	var tr := ctl.get_node_or_null("Image") as TextureRect
	if tr:
		var ic: Color = tree.prop(id, "ImageColor")
		ic.a = 1.0 - float(tree.prop(id, "ImageTransparency"))
		tr.modulate = ic
		tr.stretch_mode = {"Stretch": TextureRect.STRETCH_SCALE, "Crop": TextureRect.STRETCH_KEEP_ASPECT_COVERED}.get(str(tree.prop(id, "ScaleType")), TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
		var ref := str(tree.prop(id, "Image"))
		tr.set_meta("ref", ref)
		AssetCache.fetch(ref, func(tex: Texture2D):
			if is_instance_valid(tr) and tr.get_meta("ref", "") == ref:
				tr.texture = tex)
	var sc := ctl.get_node_or_null("Scroll") as ScrollContainer
	if sc:
		var dir := str(tree.prop(id, "ScrollingDirection"))
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if dir != "Vertical" else ScrollContainer.SCROLL_MODE_DISABLED
		sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if dir != "Horizontal" else ScrollContainer.SCROLL_MODE_DISABLED


func _font(id: String) -> Font:
	return {"Regular": UI.font_regular, "Black": UI.font_black}.get(str(tree.prop(id, "Font")), UI.font_bold)


# --- layout ------------------------------------------------------------------------

func _process(_delta: float) -> void:
	# Under a CanvasLayer the full-rect size can lag a frame behind; use the viewport.
	var screen := size if size.x > 1.0 and size.y > 1.0 else get_viewport_rect().size
	if screen != _last_screen:
		_last_screen = screen
		_dirty = true
	if _dirty and tree:
		_dirty = false
		if root_id != "" and tree.has(root_id):
			for sg in tree.kids(root_id):
				if _controls.has(sg):
					var ctl: Control = _controls[sg]
					ctl.position = Vector2.ZERO
					ctl.size = screen
					_layout_children(sg, screen)


func _udim(u: Variant, parent: Vector2) -> Vector2:
	if u is PackedFloat32Array and u.size() == 4:
		return Vector2(u[0] * parent.x + u[1], u[2] * parent.y + u[3])
	return Vector2.ZERO


func _layout_children(id: String, box: Vector2) -> void:
	var pad := tree.child_of_class(id, "UIPadding")
	var off := Vector2.ZERO
	var inner := box
	if pad != "":
		off = Vector2(float(tree.prop(pad, "Left")), float(tree.prop(pad, "Top")))
		inner = box - off - Vector2(float(tree.prop(pad, "Right")), float(tree.prop(pad, "Bottom")))
		inner = inner.max(Vector2.ZERO)
	var kids: Array = []
	for k in tree.kids(id):
		if _controls.has(k) and tree.cls(k) != "ScreenGui":
			kids.append(k)
	var list := tree.child_of_class(id, "UIListLayout")
	var grid := tree.child_of_class(id, "UIGridLayout")
	var layout := list if list != "" else grid
	if layout != "":
		var by_name := str(tree.prop(layout, "SortOrder")) == "Name"
		kids.sort_custom(func(a, b):
			if by_name:
				return tree.name_of(a) < tree.name_of(b)
			return float(tree.prop(a, "LayoutOrder")) < float(tree.prop(b, "LayoutOrder")))
	if list != "":
		var vertical := str(tree.prop(list, "FillDirection")) == "Vertical"
		var gap := float(tree.prop(list, "Padding"))
		var sizes: Array = []
		var total := 0.0
		for k in kids:
			if not tree.prop(k, "Visible"):
				sizes.append(Vector2.ZERO)
				continue
			var s := _udim(tree.prop(k, "Size"), inner)
			sizes.append(s)
			total += (s.y if vertical else s.x) + gap
		total = maxf(total - gap, 0.0)
		var h_align := str(tree.prop(list, "HorizontalAlignment"))
		var v_align := str(tree.prop(list, "VerticalAlignment"))
		var cursor := 0.0
		if vertical:
			cursor = {"Center": (inner.y - total) / 2.0, "Bottom": inner.y - total}.get(v_align, 0.0)
		else:
			cursor = {"Center": (inner.x - total) / 2.0, "Right": inner.x - total}.get(h_align, 0.0)
		for i in kids.size():
			var k: String = kids[i]
			var s: Vector2 = sizes[i]
			var ctl: Control = _controls[k]
			var pos := Vector2.ZERO
			if vertical:
				var x: float = {"Center": (inner.x - s.x) / 2.0, "Right": inner.x - s.x}.get(h_align, 0.0)
				pos = Vector2(x, cursor)
				cursor += s.y + gap if s != Vector2.ZERO else 0.0
			else:
				var y: float = {"Center": (inner.y - s.y) / 2.0, "Bottom": inner.y - s.y}.get(v_align, 0.0)
				pos = Vector2(cursor, y)
				cursor += s.x + gap if s != Vector2.ZERO else 0.0
			_place(k, ctl, off + pos, s)
	elif grid != "":
		var cell := _udim(tree.prop(grid, "CellSize"), inner)
		var gp := _udim(tree.prop(grid, "CellPadding"), inner)
		var per_row := maxi(1, int((inner.x + gp.x) / maxf(cell.x + gp.x, 1.0)))
		var n := 0
		for k in kids:
			if not tree.prop(k, "Visible"):
				continue
			var pos := Vector2((n % per_row) * (cell.x + gp.x), (n / per_row) * (cell.y + gp.y))
			_place(k, _controls[k], off + pos, cell)
			n += 1
	else:
		for k in kids:
			var s := _udim(tree.prop(k, "Size"), inner)
			var anchor: Vector2 = tree.prop(k, "AnchorPoint")
			var pos := _udim(tree.prop(k, "Position"), inner) - anchor * s
			_place(k, _controls[k], off + pos, s)


func _place(id: String, ctl: Control, pos: Vector2, s: Vector2) -> void:
	ctl.position = pos
	ctl.size = s
	ctl.pivot_offset = s / 2.0
	var box := s
	if _content.has(id):
		var canvas: Control = _content[id]
		var cs := _udim(tree.prop(id, "CanvasSize"), s)
		canvas.custom_minimum_size = cs.max(s * Vector2(1, 0))
		canvas.size = canvas.custom_minimum_size
		box = canvas.size
	_layout_children(id, box)
