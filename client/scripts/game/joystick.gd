class_name Joystick
extends Control
## Floating virtual stick: appears where the left thumb lands.

var value := Vector2.ZERO
var radius := 90.0
var _finger := -1
var _center := Vector2.ZERO
var _knob := Vector2.ZERO
var _rest := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func active() -> bool:
	return _finger >= 0


func owns_finger(index: int) -> bool:
	return index == _finger


func begin(index: int, pos: Vector2) -> void:
	_finger = index
	_center = pos
	_knob = pos
	value = Vector2.ZERO
	queue_redraw()


func drag(index: int, pos: Vector2) -> void:
	if index != _finger:
		return
	var d := pos - _center
	if d.length() > radius:
		# Let the base trail the thumb so direction changes stay responsive.
		_center += d - d.normalized() * radius
		d = pos - _center
	_knob = _center + d
	value = d / radius
	queue_redraw()


func reset() -> void:
	_finger = -1
	value = Vector2.ZERO
	queue_redraw()


func end(index: int) -> void:
	if index != _finger:
		return
	_finger = -1
	value = Vector2.ZERO
	queue_redraw()


func _process(_delta: float) -> void:
	var r := get_viewport_rect().size
	var rest := Vector2(radius + 70.0, r.y - radius - 60.0)
	if rest != _rest:
		_rest = rest
		queue_redraw()


func _draw() -> void:
	if not DisplayServer.is_touchscreen_available():
		return
	var c := _center if active() else _rest
	var k := _knob if active() else _rest
	var a := 1.0 if active() else 0.45
	draw_circle(c, radius, Color(0.09, 0.08, 0.12, 0.35 * a))
	draw_arc(c, radius, 0, TAU, 64, Color(1, 1, 1, 0.35 * a), 3.0, true)
	draw_circle(k, radius * 0.42, Color(0.95, 0.93, 1.0, 0.8 * a))
