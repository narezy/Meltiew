class_name StudioAnimator
extends Control
## The Animator: pose Melly bone by bone at points in time (keys) and save the
## result to the server, where it gets a number ("anim://12") that scripts, Rigs
## and a place's emote wheel can play.
##
## Click a body part on Melly, then drag the gizmo: rings turn it (R), arrows move
## it (W). A key is set for that part at the playhead; between keys Melly moves
## smoothly from one pose to the next. The sliders are there for exact values.

const BONES := ["Torso", "Head", "ArmL", "ArmR", "LegL", "LegR"]
const ROW_H := 26.0

var data := {"length": 2.0, "loop": true, "keys": {}, "moves": {}}
var anim_id := 0
var _bone := "ArmR"
var _time := 0.0
var _playing := false
var _stage: AnimatorView
var _mode_buttons := {}
var _name: LineEdit
var _length: SpinBox
var _loop: CheckBox
var _ref: Button
var _playhead: HSlider
var _time_label: Label
var _play_btn: Button
var _timeline: Control
var _bone_buttons := {}
var _sliders := {}  # "rx".."pz" -> HSlider
var _values := {}  # same -> Label
var _quiet := false  # while sliders are moved by code
var _pos_title: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)
	var root := UI.vbox(10)
	margin.add_child(root)

	# Top: name, length, loop, file actions.
	var top := UI.hbox(8)
	top.add_child(UI.label(L.t("an_title"), 24, UI.TEXT, "black"))
	_name = UI.input(L.t("an_name"))
	_name.custom_minimum_size = Vector2(190, 40)
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.max_length = 50
	top.add_child(_name)
	top.add_child(UI.label(L.t("an_length"), 15, UI.MUTED))
	_length = SpinBox.new()
	_length.min_value = 0.2
	_length.max_value = 30.0
	_length.step = 0.1
	_length.value = 2.0
	_length.value_changed.connect(func(v):
		data.length = float(v)
		_playhead.max_value = float(v)
		_trim_keys()
		_refresh())
	top.add_child(_length)
	_loop = CheckBox.new()
	_loop.text = L.t("an_loop")
	_loop.button_pressed = true
	_loop.toggled.connect(func(on):
		data.loop = on
		_refresh())
	top.add_child(_loop)
	# The saved id scripts use: tap it to copy.
	_ref = UI.button(L.t("an_id_none"), "ghost", 40)
	_ref.add_theme_font_size_override("font_size", 14)
	_ref.add_theme_color_override("font_color", UI.MINT)
	_ref.tooltip_text = L.t("an_copy")
	_ref.pressed.connect(_copy_ref)
	top.add_child(_ref)
	for it in [["an_new", _new, "ghost"], ["an_open", _open_list, "ghost"], ["an_save", _save, "primary"], ["an_close", func(): visible = false, "ghost"]]:
		var b := UI.button(L.t(it[0]), it[2], 40)
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(it[1])
		top.add_child(b)
	root.add_child(top)

	# Middle: Melly on the left, the chosen bone's pose on the right.
	var mid := UI.hbox(12)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(mid)
	var stage_col := UI.vbox(6)
	stage_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(stage_col)
	var tools := UI.hbox(6)
	for m in [["rotate", "an_tool_rotate"], ["move", "an_tool_move"]]:
		var tb := UI.button(L.t(m[1]), "flat", 36)
		tb.theme_type_variation = "ChipButton"
		tb.toggle_mode = true
		tb.add_theme_font_size_override("font_size", 14)
		tb.pressed.connect(func(): _set_mode(m[0]))
		tools.add_child(tb)
		_mode_buttons[m[0]] = tb
	var th := UI.label(L.t("an_view_hint"), 13, UI.MUTED)
	tools.add_child(th)
	stage_col.add_child(tools)
	var stage_card := UI.card(0, Color(UI.CARD, 0.6), 18)
	stage_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_col.add_child(stage_card)
	_stage = AnimatorView.new()
	stage_card.add_child(_stage)
	_stage.bone_picked.connect(func(b): _select_bone(b))
	_stage.rotated.connect(_on_gizmo_rotate)
	_stage.moved.connect(_on_gizmo_move)
	var side := UI.card(14, UI.CARD, 18)
	side.custom_minimum_size.x = 330
	mid.add_child(side)
	var sv := UI.vbox(8)
	side.add_child(sv)
	sv.add_child(UI.label(L.t("an_bone"), 15, UI.MUTED, "bold"))
	var bones := HFlowContainer.new()
	bones.add_theme_constant_override("h_separation", 6)
	bones.add_theme_constant_override("v_separation", 6)
	for b in BONES:
		var bb := UI.button(L.t("an_b_" + b), "flat", 36)
		bb.theme_type_variation = "ChipButton"
		bb.toggle_mode = true
		bb.add_theme_font_size_override("font_size", 14)
		bb.pressed.connect(func(): _select_bone(b))
		bones.add_child(bb)
		_bone_buttons[b] = bb
	sv.add_child(bones)
	sv.add_child(UI.label(L.t("an_rotation"), 15, UI.MUTED, "bold"))
	for axis in [["rx", "X"], ["ry", "Y"], ["rz", "Z"]]:
		sv.add_child(_slider_row(axis[0], axis[1], -180.0, 180.0, 1.0))
	_pos_title = UI.label(L.t("an_move"), 15, UI.MUTED, "bold")
	sv.add_child(_pos_title)
	for axis in [["px", "X"], ["py", "Y"], ["pz", "Z"]]:
		sv.add_child(_slider_row(axis[0], axis[1], -3.0, 3.0, 0.05))
	var keys_row := UI.hbox(6)
	var add := UI.button(L.t("an_key"), "primary", 38)
	add.add_theme_font_size_override("font_size", 14)
	add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add.pressed.connect(func(): _set_key_from_sliders())
	keys_row.add_child(add)
	var del := UI.button(L.t("an_delete_key"), "ghost", 38)
	del.add_theme_font_size_override("font_size", 14)
	del.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	del.pressed.connect(_delete_key)
	keys_row.add_child(del)
	sv.add_child(keys_row)
	var hint := UI.label(L.t("an_hint"), 13, UI.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sv.add_child(hint)

	# Bottom: play, playhead, a row of keys per bone.
	var bottom := UI.card(12, UI.CARD, 18)
	root.add_child(bottom)
	var bv := UI.vbox(6)
	bottom.add_child(bv)
	var ph := UI.hbox(8)
	_play_btn = UI.button("▶", "primary", 36)
	_play_btn.custom_minimum_size.x = 52
	_play_btn.pressed.connect(_toggle_play)
	ph.add_child(_play_btn)
	_playhead = HSlider.new()
	_playhead.min_value = 0.0
	_playhead.max_value = 2.0
	_playhead.step = 0.01
	_playhead.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_playhead.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_playhead.value_changed.connect(func(v):
		if _quiet:
			return
		_time = float(v)
		_playing = false
		_play_btn.text = "▶"
		_refresh())
	ph.add_child(_playhead)
	_time_label = UI.label("0.00 s", 15, UI.TEXT, "bold")
	_time_label.custom_minimum_size.x = 70
	ph.add_child(_time_label)
	bv.add_child(ph)
	_timeline = Control.new()
	_timeline.custom_minimum_size.y = ROW_H * BONES.size()
	_timeline.draw.connect(_draw_timeline)
	_timeline.gui_input.connect(_timeline_input)
	bv.add_child(_timeline)
	_select_bone("ArmR")
	_set_mode("rotate")
	_refresh.call_deferred()


func open() -> void:
	visible = true
	_refresh.call_deferred()


func _slider_row(key: String, label: String, lo: float, hi: float, step: float) -> Control:
	var row := UI.hbox(6)
	var l := UI.label(label, 15, UI.TEXT, "bold")
	l.custom_minimum_size.x = 18
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(func(_v):
		_values[key].text = str(snappedf(s.value, step))
		if not _quiet:
			_set_key_from_sliders())
	row.add_child(s)
	var v := UI.label("0", 14, UI.MUTED)
	v.custom_minimum_size.x = 44
	row.add_child(v)
	_sliders[key] = s
	_values[key] = v
	return row


func _select_bone(b: String) -> void:
	_bone = b
	for k in _bone_buttons:
		_bone_buttons[k].button_pressed = k == b
	if _stage:
		_stage.bone = b
	_sync_sliders()
	if _timeline:
		_timeline.queue_redraw()


func _set_mode(m: String) -> void:
	_stage.mode = m
	for k in _mode_buttons:
		_mode_buttons[k].button_pressed = k == m


func _unhandled_key_input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey and e.pressed and not e.echo):
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	match e.keycode:
		KEY_R:
			_set_mode("rotate")
		KEY_W:
			_set_mode("move")
		KEY_SPACE:
			_toggle_play()


func _moves(bone: String) -> Array:
	if not data.has("moves"):
		data.moves = {}
	if not data.moves.has(bone):
		data.moves[bone] = []
	return data.moves[bone]


## Dragging a gizmo ring / arrow: nudge that part's pose and key it at the playhead.
func _on_gizmo_rotate(b: String, axis: int, degrees: float) -> void:
	var r := _sample(data.keys.get(b, []), _time)
	r[axis] = wrapf(r[axis] + degrees, -180.0, 180.0)
	_put(_keys(b), _time, r)
	_refresh()


func _on_gizmo_move(b: String, axis: int, studs: float) -> void:
	var m := _sample(data.moves.get(b, []), _time)
	m[axis] = clampf(m[axis] + studs, -5.0, 5.0)
	_put(_moves(b), _time, m, 0.01)
	_refresh()


# --- keys --------------------------------------------------------------------------

func _keys(bone: String) -> Array:
	if not data.keys.has(bone):
		data.keys[bone] = []
	return data.keys[bone]


## Linear value of a list of [t, a, b, c] keys at time t (for the sliders).
static func _sample(list: Array, t: float) -> Vector3:
	if list.is_empty():
		return Vector3.ZERO
	if t <= float(list[0][0]):
		return Vector3(list[0][1], list[0][2], list[0][3])
	for i in range(1, list.size()):
		var a: Array = list[i - 1]
		var b: Array = list[i]
		if t <= float(b[0]):
			var k := (t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.0001)
			return Vector3(a[1], a[2], a[3]).lerp(Vector3(b[1], b[2], b[3]), k)
	var z: Array = list[list.size() - 1]
	return Vector3(z[1], z[2], z[3])


static func _put(list: Array, t: float, v: Vector3, step := 0.1) -> void:
	for k in list:
		if absf(float(k[0]) - t) < 0.015:
			k[1] = snappedf(v.x, step)
			k[2] = snappedf(v.y, step)
			k[3] = snappedf(v.z, step)
			return
	list.append([snappedf(t, 0.01), snappedf(v.x, step), snappedf(v.y, step), snappedf(v.z, step)])
	list.sort_custom(func(a, b): return a[0] < b[0])


func _set_key_from_sliders() -> void:
	_put(_keys(_bone), _time, Vector3(_sliders.rx.value, _sliders.ry.value, _sliders.rz.value))
	var p := Vector3(_sliders.px.value, _sliders.py.value, _sliders.pz.value)
	if p != Vector3.ZERO or not data.moves.get(_bone, []).is_empty():
		_put(_moves(_bone), _time, p, 0.01)
	_refresh()


func _delete_key() -> void:
	for list in [_keys(_bone), _moves(_bone)]:
		for i in range(list.size() - 1, -1, -1):
			if absf(float(list[i][0]) - _time) < 0.015:
				list.remove_at(i)
	_refresh()


func _trim_keys() -> void:
	for b in data.keys:
		data.keys[b] = data.keys[b].filter(func(k): return float(k[0]) <= data.length + 0.001)
	for b in data.moves:
		data.moves[b] = data.moves[b].filter(func(k): return float(k[0]) <= data.length + 0.001)


# --- preview -----------------------------------------------------------------------

func _refresh() -> void:
	if not is_inside_tree() or _stage.avatar == null or not _stage.avatar.is_node_ready():
		return
	_quiet = true
	_playhead.max_value = data.length
	_playhead.value = _time
	_quiet = false
	_time_label.text = "%.2f s" % _time
	_sync_sliders()
	_stage.avatar.preview(CustomAnims.build(data), _time, _playing)
	_timeline.queue_redraw()


func _sync_sliders() -> void:
	_quiet = true
	var r := _sample(data.keys.get(_bone, []), _time)
	_sliders.rx.value = r.x
	_sliders.ry.value = r.y
	_sliders.rz.value = r.z
	var p := _sample(data.moves.get(_bone, []), _time)
	_sliders.px.value = p.x
	_sliders.py.value = p.y
	_sliders.pz.value = p.z
	_quiet = false


func _toggle_play() -> void:
	_playing = not _playing
	_play_btn.text = "❚❚" if _playing else "▶"
	_stage.avatar.preview(CustomAnims.build(data), _time, _playing)


func _process(_delta: float) -> void:
	if not visible or not _playing or _stage.avatar == null or _stage.avatar.anim_player == null:
		return
	var ap := _stage.avatar.anim_player
	if not ap.is_playing():
		_playing = false
		_play_btn.text = "▶"
		return
	_time = ap.current_animation_position
	_quiet = true
	_playhead.value = _time
	_quiet = false
	_time_label.text = "%.2f s" % _time
	_timeline.queue_redraw()


func _draw_timeline() -> void:
	var w := _timeline.size.x
	var font := UI.font_bold
	for i in BONES.size():
		var y := i * ROW_H
		var b: String = BONES[i]
		if b == _bone:
			_timeline.draw_rect(Rect2(0, y, w, ROW_H), Color(UI.ACCENT, 0.12))
		_timeline.draw_string(font, Vector2(4, y + 18), L.t("an_b_" + b), HORIZONTAL_ALIGNMENT_LEFT, 110, 13, UI.MUTED)
		_timeline.draw_line(Vector2(120, y + ROW_H * 0.5), Vector2(w - 8, y + ROW_H * 0.5), Color(1, 1, 1, 0.08), 2.0)
		for k in data.keys.get(b, []):
			_timeline.draw_circle(Vector2(_x_of(float(k[0])), y + ROW_H * 0.5), 6.0, UI.ACCENT)
		for k in data.moves.get(b, []):
			_timeline.draw_circle(Vector2(_x_of(float(k[0])), y + ROW_H * 0.5), 3.5, UI.MINT)
	var px := _x_of(_time)
	_timeline.draw_line(Vector2(px, 0), Vector2(px, _timeline.size.y), UI.PINK, 2.0)


func _x_of(t: float) -> float:
	return 120.0 + (_timeline.size.x - 128.0) * clampf(t / maxf(data.length, 0.01), 0.0, 1.0)


## Clicking the timeline picks that bone's row and moves the playhead (onto a key if near one).
func _timeline_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	var row := clampi(int(e.position.y / ROW_H), 0, BONES.size() - 1)
	_select_bone(BONES[row])
	if e.position.x < 120.0:
		_refresh()
		return
	var t: float = clampf((e.position.x - 120.0) / maxf(_timeline.size.x - 128.0, 1.0), 0.0, 1.0) * data.length
	for k in data.keys.get(BONES[row], []):
		if absf(_x_of(float(k[0])) - e.position.x) < 8.0:
			t = float(k[0])
	_time = t
	_playing = false
	_play_btn.text = "▶"
	_refresh()


# --- files -------------------------------------------------------------------------

func _new() -> void:
	data = {"length": 2.0, "loop": true, "keys": {}, "moves": {}}
	anim_id = 0
	_name.text = ""
	_length.value = 2.0
	_loop.button_pressed = true
	_time = 0.0
	_set_ref("")
	_refresh()


func _save() -> void:
	var body := {"name": _name.text.strip_edges(), "data": data}
	var r: Dictionary
	if anim_id > 0:
		r = await Api.request("PUT", "/api/animations/%d" % anim_id, body)
	else:
		r = await Api.request("POST", "/api/animations", body)
	if not r.ok:
		UI.toast(r.message, "error")
		return
	anim_id = int(r.data.animation.id)
	CustomAnims.put(anim_id, data.duplicate(true))
	_set_ref(str(r.data.animation.ref))
	DisplayServer.clipboard_set(_ref_value)
	UI.toast(L.t("an_saved", [_ref_value]), "ok")


var _ref_value := ""


func _set_ref(ref: String) -> void:
	_ref_value = ref
	_ref.text = "ID  " + ref if ref != "" else L.t("an_id_none")


func _copy_ref() -> void:
	if _ref_value != "":
		DisplayServer.clipboard_set(_ref_value)
		UI.toast(L.t("st_copied") + ": " + _ref_value, "ok")
	else:
		UI.toast(L.t("an_id_hint"))


func _open_list() -> void:
	StudioPickers.animation(self, false, func(ref: String):
		if ref.begins_with("anim://"):
			_load(CustomAnims.id_of(ref)), func(): pass)


func _load(id: int) -> void:
	var r := await Api.request("GET", "/api/animations/%d" % id)
	if not r.ok:
		UI.toast(r.message, "error")
		return
	var a: Dictionary = r.data.animation
	data = a.data
	if not data.has("keys"):
		data.keys = {}
	data.moves = CustomAnims.moves_of(data).duplicate(true)
	data.erase("pos")
	anim_id = int(a.id) if str(a.get("by", "")) == str(Session.user.get("username", "")) else 0
	_name.text = str(a.name)
	_length.value = float(data.length)
	_loop.button_pressed = data.get("loop", false)
	_set_ref(str(a.ref) if anim_id > 0 else "")
	_time = 0.0
	_refresh()
