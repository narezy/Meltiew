class_name TouchList
extends Control
## A scrolling list that works the same with a finger and a mouse: a drag
## scrolls it (and keeps gliding after a flick), a tap picks a row. Rows are
## plain controls that never take input themselves, so a finger that lands on
## one can still scroll the list (buttons in a ScrollContainer swallow the drag).

signal tapped(index: int)

## Movement (px) after which a touch is a scroll and not a tap.
const TAP_SLOP := 12.0

var scroll := ScrollContainer.new()
var box := VBoxContainer.new()
var _down := false
var _dragging := false
var _moved := 0.0
var _vel := 0.0
var _last_t := 0
var _pressed_row := -1
var _glide := 0.0


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scroll)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	scroll.add_child(box)


func add_row(row: Control) -> void:
	_ignore_input(row)
	box.add_child(row)


func row(i: int) -> Control:
	return box.get_child(i) as Control


func row_count() -> int:
	return box.get_child_count()


## Scrolls so row `i` sits near the top third of the list.
func show_row(i: int) -> void:
	if i < 0 or i >= row_count():
		return
	await get_tree().process_frame
	if is_instance_valid(self):
		scroll.scroll_vertical = int(maxf(0.0, row(i).position.y - size.y / 3.0))


func _ignore_input(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for ch in c.get_children():
		if ch is Control:
			_ignore_input(ch)


## The row under the point, or the nearest one (taps between rows still count).
func _row_at(global_pos: Vector2) -> int:
	if not get_global_rect().has_point(global_pos):
		return -1
	var best := -1
	var best_d := 1e9
	for i in row_count():
		var r := row(i).get_global_rect()
		if not row(i).visible:
			continue
		var d := maxf(maxf(r.position.y - global_pos.y, global_pos.y - r.end.y), 0.0)
		if d < best_d:
			best_d = d
			best = i
	return best if best_d < 12.0 else -1


func _gui_input(e: InputEvent) -> void:
	# Touch comes in as emulated mouse events (input_devices/pointing/emulate_mouse_from_touch).
	if e is InputEventMouseButton:
		match e.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if e.pressed:
					_vel = 0.0
					scroll.scroll_vertical += int((-1.0 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0) * 60.0 * maxf(e.factor, 1.0))
				accept_event()
			MOUSE_BUTTON_LEFT:
				accept_event()
				if e.pressed:
					_down = true
					_dragging = false
					_moved = 0.0
					_vel = 0.0
					_last_t = Time.get_ticks_msec()
					_pressed_row = _row_at(e.global_position)
					_highlight(_pressed_row, true)
				elif _down:
					_down = false
					_highlight(_pressed_row, false)
					if not _dragging:
						var i := _row_at(e.global_position)
						if i >= 0:
							tapped.emit(i)
					elif Time.get_ticks_msec() - _last_t > 80:
						_vel = 0.0  # held still before letting go: no glide
	elif e is InputEventMouseMotion and _down:
		accept_event()
		_moved += absf(e.relative.y) + absf(e.relative.x)
		if not _dragging and _moved > TAP_SLOP:
			_dragging = true
			_highlight(_pressed_row, false)
		if _dragging:
			scroll.scroll_vertical -= int(roundf(e.relative.y))
			var now := Time.get_ticks_msec()
			var dt := maxf(float(now - _last_t) / 1000.0, 0.001)
			_vel = lerpf(_vel, -e.relative.y / dt, 0.35)
			_last_t = now


func _highlight(i: int, on: bool) -> void:
	if i >= 0 and i < row_count():
		row(i).modulate = Color(1.25, 1.25, 1.35) if on else Color.WHITE


func _process(delta: float) -> void:
	if _down or absf(_vel) < 8.0:
		if not _down:
			_vel = 0.0
		return
	_glide += _vel * delta
	var step := int(_glide)
	_glide -= step
	_vel *= pow(0.04, delta)
	if step != 0:
		var before := scroll.scroll_vertical
		scroll.scroll_vertical += step
		if scroll.scroll_vertical == before:
			_vel = 0.0  # hit an end
