class_name TouchButton
extends Control
## Round on-screen button that works with multi-touch (unlike regular Buttons,
## which only see the first finger through mouse emulation).

signal pressed_down
signal released

var icon_kind := "jump"
var tint := UI.TEXT
var bg := Color(0.09, 0.08, 0.12, 0.45)
var bg_down := Color(0.72, 0.61, 1.0, 0.75)
var _finger := -1
var _mouse_down := false
var _icon: Icon


static func make(kind: String, px: int) -> TouchButton:
	var b := TouchButton.new()
	b.icon_kind = kind
	b.custom_minimum_size = Vector2(px, px)
	b.size = Vector2(px, px)
	return b


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_icon = Icon.make(icon_kind, int(size.x * 0.42), tint)
	_icon.position = (size - _icon.custom_minimum_size) * 0.5
	add_child(_icon)
	resized.connect(func(): _icon.position = (size - _icon.custom_minimum_size) * 0.5)


func is_down() -> bool:
	return _finger >= 0 or _mouse_down


func _draw() -> void:
	var r := size.x * 0.5
	draw_circle(size * 0.5, r, bg_down if is_down() else bg)
	draw_arc(size * 0.5, r - 1.5, 0, TAU, 48, Color(1, 1, 1, 0.35), 3.0, true)


## Called by the HUD's touch router. Returns true when this button takes the finger.
func touch_press(index: int, pos: Vector2) -> bool:
	if _finger >= 0 or not is_visible_in_tree() or not get_global_rect().has_point(pos):
		return false
	_finger = index
	_down()
	return true


func force_release() -> void:
	if _finger >= 0 or _mouse_down:
		_finger = -1
		_mouse_down = false
		_up()


func touch_release(index: int) -> void:
	if index == _finger:
		_finger = -1
		_up()


func _gui_input(event: InputEvent) -> void:
	# Desktop mouse path. On touch screens the finger path above handles it.
	if DisplayServer.is_touchscreen_available():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_mouse_down = true
			_down()
		elif _mouse_down:
			_mouse_down = false
			_up()


func _down() -> void:
	pressed_down.emit()
	scale = Vector2(0.92, 0.92)
	pivot_offset = size * 0.5
	queue_redraw()


func _up() -> void:
	released.emit()
	scale = Vector2.ONE
	queue_redraw()
