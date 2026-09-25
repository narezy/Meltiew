class_name KeyboardAvoider
extends Node
## Slides a full-screen control up so the focused text field stays above
## the Android on-screen keyboard.

var target: Control
var _shift := 0.0


func _init(t: Control) -> void:
	target = t


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var want := 0.0
	var kb := DisplayServer.virtual_keyboard_get_height()
	if kb > 0:
		var focus := target.get_viewport().gui_get_focus_owner()
		if (focus is LineEdit or focus is TextEdit) and target.is_ancestor_of(focus):
			var vp_size := target.get_viewport_rect().size
			var win_h := float(DisplayServer.window_get_size().y)
			var kb_canvas := kb * vp_size.y / maxf(win_h, 1.0)
			var bottom := focus.get_global_rect().end.y + _shift
			want = maxf(0.0, bottom - (vp_size.y - kb_canvas - 20.0))
	_shift = lerpf(_shift, want, minf(delta * 14.0, 1.0))
	target.position.y = -_shift
