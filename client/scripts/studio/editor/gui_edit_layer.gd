class_name GuiEditLayer
extends Control
## Studio's UI mode: StarterGui drawn over the 3D view. Click a UI object to select it,
## drag to move it, drag the corner handle to resize (changes the pixel part of
## Position/Size, so scale-based layouts keep working).

var doc: EditDoc
var gui: PlaceGui
var _drag := {}
const HANDLE := 12.0


func setup(d: EditDoc) -> void:
	doc = d
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui = PlaceGui.new()
	gui.editing = true
	gui.theme = UI.theme
	gui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(gui)
	doc.selection_changed.connect(queue_redraw)


func rebind() -> void:
	gui.strings = doc.strings
	gui.bind(doc.tree, doc.tree.service("StarterGui"))
	doc.tree.changed.connect(func(_i, _k): queue_redraw())


func _process(_d: float) -> void:
	queue_redraw()


func _selected_control() -> Control:
	var id := doc.primary()
	return gui.control_of(id) if id != "" else null


func _draw() -> void:
	var ctl := _selected_control()
	if ctl == null or not is_instance_valid(ctl) or not ctl.is_visible_in_tree():
		return
	var r := Rect2(ctl.global_position - global_position, ctl.size)
	draw_rect(r, UI.ACCENT, false, 2.0)
	draw_rect(Rect2(r.end - Vector2(HANDLE, HANDLE), Vector2(HANDLE, HANDLE)), UI.ACCENT)


func _pick(at: Vector2) -> String:
	# Topmost visible UI object under the mouse (later siblings draw on top).
	var best := ""
	var best_z := -INF
	var order := 0
	for id in doc.tree.descendants(gui.root_id):
		order += 1
		var ctl := gui.control_of(id)
		if ctl == null or doc.tree.cls(id) == "ScreenGui" or not ctl.is_visible_in_tree():
			continue
		if Rect2(ctl.global_position - global_position, ctl.size).has_point(at):
			var z := float(ctl.z_index) * 100000.0 + order
			if z > best_z:
				best_z = z
				best = id
	return best


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			var ctl := _selected_control()
			var id := doc.primary()
			if ctl:
				var r := Rect2(ctl.global_position - global_position, ctl.size)
				if Rect2(r.end - Vector2(HANDLE, HANDLE) * 1.5, Vector2(HANDLE, HANDLE) * 1.5).has_point(e.position):
					_drag = {"id": id, "mode": "size", "from": e.position, "start": doc.tree.prop(id, "Size")}
					accept_event()
					return
				if r.has_point(e.position):
					_drag = {"id": id, "mode": "move", "from": e.position, "start": doc.tree.prop(id, "Position")}
					accept_event()
					return
			var picked := _pick(e.position)
			doc.select([picked] if picked != "" else [])
			if picked != "":
				_drag = {"id": picked, "mode": "move", "from": e.position, "start": doc.tree.prop(picked, "Position")}
		elif not _drag.is_empty():
			var id: String = _drag.id
			var key := "Size" if _drag.mode == "size" else "Position"
			var now: Variant = doc.tree.prop(id, key)
			if now != _drag.start:
				doc.tree.set_prop(id, key, _drag.start)
				doc.set_prop(id, key, now)
			_drag = {}
		accept_event()
	elif e is InputEventMouseMotion and not _drag.is_empty():
		var d: Vector2 = (e.position - _drag.from).round()
		var u: PackedFloat32Array = (_drag.start as PackedFloat32Array).duplicate()
		u[1] += d.x
		u[3] += d.y
		if _drag.mode == "size":
			u[1] = maxf(u[1], -u[0] * 10000.0 + 4.0)
			u[3] = maxf(u[3], -u[2] * 10000.0 + 4.0)
		doc.tree.set_prop(_drag.id, "Size" if _drag.mode == "size" else "Position", u)
		accept_event()
