class_name StudioViewport
extends SubViewportContainer
## Studio's 3D view: fly camera, click to select, and gizmos to move, scale and rotate.
## Camera: hold right mouse to look (WASD/QE to fly, Shift = faster), wheel to zoom,
## middle mouse to pan, F to focus the selection. Phones: drag to look, pinch to zoom.

signal status(text: String)

const AXES := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
const AXIS_COLORS := [Color("#ff5d6c"), Color("#5fe08e"), Color("#4cc9f0")]
const PICK_PX := 14.0

var doc: EditDoc
var scene: PlaceScene
var vp: SubViewport
var cam: Camera3D
var tool := "move"  # select | move | scale | rotate
var snap := true
var move_snap := 0.5
var rotate_snap := 15.0

var _yaw := deg_to_rad(-30.0)
var _pitch := deg_to_rad(-25.0)
var _looking := false
var _panning := false
var _touches := {}
var _pinch := 0.0
var _drag := {}  # active gizmo drag
var _hover_axis := -1
var _lines: MeshInstance3D
var _handles: MeshInstance3D
var _line_mesh := ImmediateMesh.new()
var _handle_mesh := ImmediateMesh.new()
var _press := Vector2.ZERO
var _look_from := Vector2.ZERO


func setup(d: EditDoc) -> void:
	doc = d
	stretch = true
	focus_mode = Control.FOCUS_CLICK
	mouse_filter = Control.MOUSE_FILTER_STOP
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_2X
	vp.physics_object_picking = false
	add_child(vp)
	cam = Camera3D.new()
	cam.fov = 70
	cam.far = 1500
	cam.position = Vector3(16, 12, 20)
	vp.add_child(cam)
	var look := Basis.looking_at(-cam.position).get_euler()
	_yaw = look.y
	_pitch = look.x
	_apply_cam()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.render_priority = 10
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_lines = MeshInstance3D.new()
	_lines.mesh = _line_mesh
	_lines.material_override = mat
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vp.add_child(_lines)
	_handles = MeshInstance3D.new()
	_handles.mesh = _handle_mesh
	_handles.material_override = mat
	_handles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vp.add_child(_handles)
	rebind()


## A new place was opened: fresh PlaceScene for its tree.
func rebind() -> void:
	if scene:
		scene.queue_free()
	scene = PlaceScene.new()
	scene.editing = true
	scene.strings = doc.strings
	vp.add_child(scene)
	scene.bind(doc.tree)


func _apply_cam() -> void:
	cam.rotation = Vector3(_pitch, _yaw, 0)


func _process(delta: float) -> void:
	if _looking:
		var dir := Vector3.ZERO
		if Input.is_key_pressed(KEY_W):
			dir.z -= 1
		if Input.is_key_pressed(KEY_S):
			dir.z += 1
		if Input.is_key_pressed(KEY_A):
			dir.x -= 1
		if Input.is_key_pressed(KEY_D):
			dir.x += 1
		if Input.is_key_pressed(KEY_E):
			dir.y += 1
		if Input.is_key_pressed(KEY_Q):
			dir.y -= 1
		if dir != Vector3.ZERO:
			var speed := 40.0 if Input.is_key_pressed(KEY_SHIFT) else 14.0
			cam.global_position += cam.global_basis * dir.normalized() * speed * delta
	_draw_overlay()


# --- what can be moved ---------------------------------------------------------------

## Instances with a Position that the selection moves (models move all their parts).
func _movables() -> Array:
	var out: Array = []
	for id in doc.selection:
		if not doc.tree.has(id):
			continue
		if StudioSchema.info(doc.tree.cls(id)).props.has("Position"):
			out.append(id)
		elif doc.tree.cls(id) in ["Model", "Folder"]:
			for d in doc.tree.descendants(id):
				if StudioSchema.info(doc.tree.cls(d)).props.has("Position") and not d in out:
					out.append(d)
	return out.filter(func(i): return doc.tree.is_descendant(i, doc.tree.service("Workspace")))


func _pivot(ids: Array) -> Vector3:
	var sum := Vector3.ZERO
	for id in ids:
		sum += doc.tree.prop(id, "Position")
	return sum / maxf(ids.size(), 1)


func _basis_of(id: String) -> Basis:
	var r: Vector3 = doc.tree.prop(id, "Rotation")
	return Basis.from_euler(Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z)))


func _gizmo_size(pivot: Vector3) -> float:
	return maxf(cam.global_position.distance_to(pivot) * 0.14, 0.6)


## Gizmo axes: world axes, except scaling a single part which follows its rotation.
func _axes(ids: Array) -> Array:
	if tool == "scale" and ids.size() == 1:
		var b := _basis_of(ids[0])
		return [b.x.normalized(), b.y.normalized(), b.z.normalized()]
	return AXES


# --- drawing -------------------------------------------------------------------------

func _draw_overlay() -> void:
	_line_mesh.clear_surfaces()
	_handle_mesh.clear_surfaces()
	var ids := _movables()
	var any := false
	# Selection boxes.
	for id in doc.selection:
		var body := scene.body_of(id)
		if body == null:
			continue
		var mesh := scene.mesh_of(id)
		if mesh == null or mesh.mesh == null:
			continue
		if not any:
			_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
			any = true
		_box_lines(body.global_transform, mesh.mesh.get_aabb(), Color(UI.ACCENT, 0.95))
	if any:
		_line_mesh.surface_end()
	if ids.is_empty() or tool == "select":
		return
	var pivot := _pivot(ids)
	var s := _gizmo_size(pivot)
	var axes := _axes(ids)
	_handle_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 3:
		var col: Color = AXIS_COLORS[i]
		if _hover_axis == i or (_drag.get("axis", -1) == i):
			col = col.lightened(0.45)
		var a: Vector3 = axes[i]
		match tool:
			"move":
				_tube(pivot, pivot + a * s, s * 0.035, col)
				_cone(pivot + a * s, a, s * 0.1, s * 0.25, col)
			"scale":
				for sign in [-1.0, 1.0]:
					_tube(pivot, pivot + a * s * sign, s * 0.03, col)
					_cube(pivot + a * s * sign, s * 0.09, col)
			"rotate":
				_ring(pivot, a, s * 0.9, s * 0.03, col)
	_handle_mesh.surface_end()


func _box_lines(t: Transform3D, aabb: AABB, col: Color) -> void:
	var p := aabb.position
	var e := aabb.size
	var corners: Array = []
	for i in 8:
		corners.append(t * (p + Vector3(e.x if i & 1 else 0.0, e.y if i & 2 else 0.0, e.z if i & 4 else 0.0)))
	for pair in [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]:
		_line_mesh.surface_set_color(col)
		_line_mesh.surface_add_vertex(corners[pair[0]])
		_line_mesh.surface_set_color(col)
		_line_mesh.surface_add_vertex(corners[pair[1]])


func _tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	for v in [a, b, c]:
		_handle_mesh.surface_set_color(col)
		_handle_mesh.surface_add_vertex(v)


func _perp(a: Vector3) -> Array:
	var u := a.cross(Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT).normalized()
	return [u, a.cross(u).normalized()]


func _tube(from: Vector3, to: Vector3, r: float, col: Color) -> void:
	var a := (to - from).normalized()
	var uv := _perp(a)
	var n := 8
	for i in n:
		var t0 := TAU * i / n
		var t1 := TAU * (i + 1) / n
		var o0: Vector3 = (uv[0] * cos(t0) + uv[1] * sin(t0)) * r
		var o1: Vector3 = (uv[0] * cos(t1) + uv[1] * sin(t1)) * r
		_tri(from + o0, to + o0, to + o1, col)
		_tri(from + o0, to + o1, from + o1, col)


func _cone(base: Vector3, a: Vector3, r: float, h: float, col: Color) -> void:
	var uv := _perp(a)
	var n := 12
	for i in n:
		var t0 := TAU * i / n
		var t1 := TAU * (i + 1) / n
		var p0: Vector3 = base + (uv[0] * cos(t0) + uv[1] * sin(t0)) * r
		var p1: Vector3 = base + (uv[0] * cos(t1) + uv[1] * sin(t1)) * r
		_tri(p0, base + a * h, p1, col)
		_tri(p0, p1, base, col.darkened(0.2))


func _cube(c: Vector3, h: float, col: Color) -> void:
	var v := func(x, y, z): return c + Vector3(x, y, z) * h
	var faces := [
		[Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(1, -1, 1)],
		[Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(-1, 1, -1), Vector3(-1, -1, -1)],
		[Vector3(-1, 1, -1), Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1)],
		[Vector3(-1, -1, 1), Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1)],
		[Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)],
		[Vector3(1, -1, -1), Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1)],
	]
	for f in faces:
		var q: Array = f.map(func(p): return v.call(p.x, p.y, p.z))
		_tri(q[0], q[1], q[2], col)
		_tri(q[0], q[2], q[3], col)


func _ring(c: Vector3, a: Vector3, radius: float, r: float, col: Color) -> void:
	var uv := _perp(a)
	var n := 48
	for i in n:
		var t0 := TAU * i / n
		var t1 := TAU * (i + 1) / n
		var p0: Vector3 = c + (uv[0] * cos(t0) + uv[1] * sin(t0)) * radius
		var p1: Vector3 = c + (uv[0] * cos(t1) + uv[1] * sin(t1)) * radius
		_tube(p0, p1, r, col)


# --- picking the gizmo (in screen space) -----------------------------------------------

func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _screen(p: Vector3) -> Vector2:
	return cam.unproject_position(p)


func _axis_at(mouse: Vector2) -> int:
	var ids := _movables()
	if ids.is_empty() or tool == "select":
		return -1
	var pivot := _pivot(ids)
	var s := _gizmo_size(pivot)
	var axes := _axes(ids)
	var best := -1
	var best_d := PICK_PX
	for i in 3:
		var a: Vector3 = axes[i]
		var d := INF
		match tool:
			"move":
				d = _dist_to_segment(mouse, _screen(pivot), _screen(pivot + a * s * 1.25))
			"scale":
				d = minf(mouse.distance_to(_screen(pivot + a * s)), mouse.distance_to(_screen(pivot - a * s)))
			"rotate":
				var uv := _perp(a)
				for k in 32:
					var t0 := TAU * k / 32
					var t1 := TAU * (k + 1) / 32
					var p0: Vector3 = pivot + (uv[0] * cos(t0) + uv[1] * sin(t0)) * s * 0.9
					var p1: Vector3 = pivot + (uv[0] * cos(t1) + uv[1] * sin(t1)) * s * 0.9
					if cam.is_position_behind(p0):
						continue
					d = minf(d, _dist_to_segment(mouse, _screen(p0), _screen(p1)))
		if d < best_d:
			best_d = d
			best = i
	return best


func _ray_plane(mouse: Vector2, origin: Vector3, normal: Vector3) -> Variant:
	var from := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	return Plane(normal, origin).intersects_ray(from, dir)


func _start_drag(axis: int, mouse: Vector2) -> void:
	var ids := _movables()
	var pivot := _pivot(ids)
	var a: Vector3 = _axes(ids)[axis]
	var start := {}
	for id in ids:
		start[id] = {"pos": doc.tree.prop(id, "Position"), "rot": doc.tree.prop(id, "Rotation"), "size": doc.tree.prop(id, "Size")}
	var normal: Vector3
	if tool == "rotate":
		normal = a
	else:
		var view := cam.global_basis.z
		normal = a.cross(view).cross(a).normalized()
		if normal.length() < 0.01:
			normal = cam.global_basis.y
	var hit: Variant = _ray_plane(mouse, pivot, normal)
	if hit == null:
		return
	_drag = {"axis": axis, "a": a, "pivot": pivot, "normal": normal, "start": start, "hit": hit, "ids": ids,
		"scale_sign": 1.0 if (hit - pivot).dot(a) >= 0.0 else -1.0}
	doc.begin_batch()


func _update_drag(mouse: Vector2) -> void:
	var hit: Variant = _ray_plane(mouse, _drag.pivot, _drag.normal)
	if hit == null:
		return
	var a: Vector3 = _drag.a
	var pivot: Vector3 = _drag.pivot
	match tool:
		"move":
			var d: float = (hit - _drag.hit).dot(a)
			if snap and move_snap > 0.0:
				d = snappedf(d, move_snap)
			for id in _drag.ids:
				doc.tree.set_prop(id, "Position", _drag.start[id].pos + a * d)
			status.emit("%+.2f" % d)
		"scale":
			var d: float = (hit - _drag.hit).dot(a) * _drag.scale_sign
			if snap and move_snap > 0.0:
				d = snappedf(d, move_snap)
			var id: String = _drag.ids[0]
			var st: Dictionary = _drag.start[id]
			if not st.size is Vector3:
				return
			var local := _basis_of(id).inverse() * a
			var ax := local.abs().max_axis_index()
			var size: Vector3 = st.size
			var new_len := maxf(size[ax] + d, 0.05)
			var grow := new_len - size[ax]
			size[ax] = new_len
			doc.tree.set_prop(id, "Size", size)
			doc.tree.set_prop(id, "Position", st.pos + a * _drag.scale_sign * grow / 2.0)
			status.emit("%.2f" % new_len)
		"rotate":
			var from_v: Vector3 = (_drag.hit - pivot).normalized()
			var to_v: Vector3 = (hit - pivot).normalized()
			var ang := from_v.signed_angle_to(to_v, a)
			if snap and rotate_snap > 0.0:
				ang = snappedf(ang, deg_to_rad(rotate_snap))
			var rb := Basis(a, ang)
			for id in _drag.ids:
				var st: Dictionary = _drag.start[id]
				var r: Vector3 = st.rot
				var b := rb * Basis.from_euler(Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z)))
				var e := b.get_euler()
				doc.tree.set_prop(id, "Rotation", Vector3(snappedf(rad_to_deg(e.x), 0.01), snappedf(rad_to_deg(e.y), 0.01), snappedf(rad_to_deg(e.z), 0.01)))
				doc.tree.set_prop(id, "Position", pivot + rb * (st.pos - pivot))
			status.emit("%.0f°" % rad_to_deg(ang))


## Turns the live preview into undoable edits.
func _end_drag() -> void:
	for id in _drag.ids:
		var st: Dictionary = _drag.start[id]
		for key in ["pos", "rot", "size"]:
			var prop: String = {"pos": "Position", "rot": "Rotation", "size": "Size"}[key]
			var now: Variant = doc.tree.prop(id, prop)
			if st[key] != null and now != st[key]:
				doc.tree.set_prop(id, prop, st[key])
				doc.set_prop(id, prop, now)
	doc.end_batch({"move": "Move", "scale": "Resize", "rotate": "Rotate"}.get(tool, "Edit"))
	_drag = {}
	status.emit("")


# --- selecting ---------------------------------------------------------------------

func pick(mouse: Vector2, additive: bool, exact: bool) -> void:
	var from := cam.project_ray_origin(mouse)
	var q := PhysicsRayQueryParameters3D.create(from, from + cam.project_ray_normal(mouse) * 2000.0, 0xFFFFFFFF)
	var hit := vp.find_world_3d().direct_space_state.intersect_ray(q)
	var id := ""
	if not hit.is_empty():
		id = PlaceScene.id_of(hit.collider)
	# 3D text has no body: pick it by its position on screen.
	var ws := doc.tree.service("Workspace")
	for t in doc.tree.descendants(ws):
		if doc.tree.cls(t) == "Text3D":
			var p: Vector3 = doc.tree.prop(t, "Position")
			if not cam.is_position_behind(p) and _screen(p).distance_to(mouse) < 36.0:
				if id == "" or cam.global_position.distance_to(p) < cam.global_position.distance_to(hit.position):
					id = t
	# Clicking a part of a model selects the model (Alt picks the part itself).
	if id != "" and not exact:
		var cur := doc.tree.parent_of(id)
		while cur != "" and cur != ws:
			if doc.tree.cls(cur) == "Model":
				id = cur
			cur = doc.tree.parent_of(cur)
	if additive:
		if id != "":
			doc.toggle_select(id)
	else:
		doc.select([id] if id != "" else [])


func focus_selection() -> void:
	var ids := _movables()
	if ids.is_empty():
		return
	var pivot := _pivot(ids)
	var radius := 4.0
	for id in ids:
		var s: Variant = doc.tree.prop(id, "Size")
		if s is Vector3:
			radius = maxf(radius, s.length())
	cam.global_position = pivot - cam.global_basis.z * -1.0 * radius * 1.6
	cam.look_at(pivot)
	_yaw = cam.rotation.y
	_pitch = cam.rotation.x


## Where to put a newly inserted object: what the view's center looks at, or in front.
func insert_point() -> Vector3:
	var center := size / 2.0
	var from := cam.project_ray_origin(center)
	var dir := cam.project_ray_normal(center)
	var hit := vp.find_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + dir * 80.0))
	if not hit.is_empty():
		return hit.position
	return from + dir * 12.0


# --- input -------------------------------------------------------------------------

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		match e.button_index:
			MOUSE_BUTTON_RIGHT:
				# The cursor stays where it was while you look around, and comes back there.
				if e.pressed and not _looking:
					_look_from = get_viewport().get_mouse_position()
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				elif not e.pressed and _looking:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
					get_viewport().warp_mouse(_look_from)
				_looking = e.pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = e.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if e.pressed:
					cam.global_position -= cam.global_basis.z * 2.0
			MOUSE_BUTTON_WHEEL_DOWN:
				if e.pressed:
					cam.global_position += cam.global_basis.z * 2.0
			MOUSE_BUTTON_LEFT:
				if e.pressed:
					grab_focus()
					_press = e.position
					var axis := _axis_at(e.position)
					if axis >= 0:
						_start_drag(axis, e.position)
				else:
					if not _drag.is_empty():
						_end_drag()
					elif e.position.distance_to(_press) < 6.0:
						pick(e.position, e.ctrl_pressed or e.shift_pressed, e.alt_pressed)
		accept_event()
	elif e is InputEventMouseMotion:
		if _looking:
			_yaw -= e.relative.x * 0.004
			_pitch = clampf(_pitch - e.relative.y * 0.004, -1.5, 1.5)
			_apply_cam()
		elif _panning:
			cam.global_position += (-cam.global_basis.x * e.relative.x + cam.global_basis.y * e.relative.y) * 0.03
		elif not _drag.is_empty():
			_update_drag(e.position)
		else:
			_hover_axis = _axis_at(e.position)
		accept_event()
	elif e is InputEventScreenTouch:
		if e.pressed:
			_touches[e.index] = e.position
		else:
			_touches.erase(e.index)
			_pinch = 0.0
	elif e is InputEventScreenDrag:
		_touches[e.index] = e.position
		if _touches.size() >= 2:
			var pts := _touches.values()
			var d: float = (pts[0] as Vector2).distance_to(pts[1])
			if _pinch > 0.0:
				cam.global_position -= cam.global_basis.z * (d - _pinch) * 0.05
			_pinch = d
		elif _drag.is_empty() and _axis_at(e.position) < 0:
			_yaw -= e.relative.x * 0.005
			_pitch = clampf(_pitch - e.relative.y * 0.005, -1.5, 1.5)
			_apply_cam()
	elif e is InputEventMagnifyGesture:
		cam.global_position -= cam.global_basis.z * (e.factor - 1.0) * 10.0
