class_name AnimatorView
extends SubViewportContainer
## The Animator's 3D view: Melly on a stand, a camera you orbit (right mouse or
## one finger on empty space) and zoom (wheel), click a body part to pick it,
## and drag the gizmo to pose it: rings turn it (R), arrows move it (W).

signal bone_picked(bone: String)
## Dragging a ring: add `degrees` to the bone's turn around `axis` (0 x, 1 y, 2 z).
signal rotated(bone: String, axis: int, degrees: float)
## Dragging an arrow: add `studs` to the bone's move along `axis`.
signal moved(bone: String, axis: int, studs: float)

const BONES := ["Torso", "Head", "ArmL", "ArmR", "LegL", "LegR"]
## Each part's box around its bone, in model units: [size, center offset from the bone].
const BOXES := {
	"Torso": [Vector3(1.66, 2.0, 0.78), Vector3(0, 1.0, 0)],
	"Head": [Vector3(1.38, 1.36, 1.34), Vector3(0, 0.65, 0)],
	"ArmL": [Vector3(0.84, 2.0, 0.76), Vector3(0.21, -1.0, 0)],
	"ArmR": [Vector3(0.84, 2.0, 0.76), Vector3(-0.21, -1.0, 0)],
	"LegL": [Vector3(0.8, 2.0, 0.85), Vector3(-0.07, -1.0, 0)],
	"LegR": [Vector3(0.8, 2.0, 0.85), Vector3(0.07, -1.0, 0)],
}
const AXIS_COLORS := [Color("#ff6b7a"), Color("#7ee0c3"), Color("#4cc9f0")]
const RING_R := 0.45
const ARROW_L := 0.6

var avatar: MellyAvatar
var mode := "rotate":
	set(v):
		mode = v
		_overlay.queue_redraw()
var bone := "ArmR":
	set(v):
		bone = v
		_overlay.queue_redraw()
var _vp: SubViewport
var _cam: Camera3D
var _yaw := PI + 0.5
var _pitch := -0.18
var _dist := 5.2
var _target := Vector3(0, 1.0, 0)
var _overlay: Control
var _orbiting := false
var _drag_axis := -1
var _hover_axis := -1
var _last := Vector2.ZERO


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#221f2c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#d9d0ff")
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 35, 0)
	key.shadow_enabled = true
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_energy = 0.35
	_vp.add_child(rim)
	var floor_mesh := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.4
	disc.bottom_radius = 1.5
	disc.height = 0.1
	floor_mesh.mesh = disc
	floor_mesh.position.y = -0.05
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("#3a3550")
	floor_mesh.material_override = fm
	_vp.add_child(floor_mesh)
	_cam = Camera3D.new()
	_cam.fov = 40
	_vp.add_child(_cam)
	avatar = MellyAvatar.new()
	_vp.add_child(avatar)
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_gizmo)
	add_child(_overlay)
	_place_camera()


func _ready() -> void:
	if not avatar.is_node_ready():
		await avatar.ready
	# A clickable box on each body part, riding its bone.
	var sk: Skeleton3D = avatar._skeleton
	for b in BONES:
		var att := BoneAttachment3D.new()
		att.bone_name = b
		sk.add_child(att)
		var body := StaticBody3D.new()
		body.set_meta("bone", b)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = BOXES[b][0]
		shape.shape = box
		shape.position = BOXES[b][1]
		body.add_child(shape)
		att.add_child(body)


func _place_camera() -> void:
	# Local transform: works before the view is in the tree too.
	var dir := Vector3(sin(_yaw) * cos(_pitch), -sin(_pitch), cos(_yaw) * cos(_pitch))
	var pos := _target + dir * _dist
	_cam.transform = Transform3D(Basis.looking_at(_target - pos, Vector3.UP), pos)


func _process(_delta: float) -> void:
	_overlay.queue_redraw()


# --- where things are -----------------------------------------------------------------

## The chosen bone's pivot and the axes its turns and moves go along (its parent's).
func _frame() -> Array:
	var sk: Skeleton3D = avatar._skeleton if avatar else null
	if sk == null:
		return []
	var i := sk.find_bone(bone)
	var pose := sk.global_transform * sk.get_bone_global_pose(i)
	var parent := sk.get_bone_parent(i)
	var basis := (sk.global_transform * sk.get_bone_global_pose(parent)).basis if parent >= 0 else sk.global_transform.basis
	return [pose.origin, basis.orthonormalized()]


func _to_screen(p: Vector3) -> Vector2:
	return _cam.unproject_position(p) * (size / Vector2(_vp.size))


func _ring_points(center: Vector3, axis: Vector3) -> PackedVector2Array:
	var u := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var w := axis.cross(u).normalized()
	var pts := PackedVector2Array()
	for k in 49:
		var a := TAU * k / 48.0
		pts.append(_to_screen(center + (u * cos(a) + w * sin(a)) * RING_R))
	return pts


func _draw_gizmo() -> void:
	var f := _frame()
	if f.is_empty():
		return
	var c: Vector3 = f[0]
	var b: Basis = f[1]
	for i in 3:
		var col: Color = AXIS_COLORS[i]
		var width := 5.0 if i == _drag_axis or i == _hover_axis else 3.0
		if mode == "rotate":
			_overlay.draw_polyline(_ring_points(c, b[i]), col, width, true)
		else:
			var a := _to_screen(c)
			var e := _to_screen(c + b[i] * ARROW_L)
			_overlay.draw_line(a, e, col, width, true)
			_overlay.draw_circle(e, 7.0 if i == _hover_axis or i == _drag_axis else 5.5, col)
	_overlay.draw_circle(_to_screen(c), 4.0, Color.WHITE)


## Which ring or arrow is under the mouse (or -1).
func _axis_at(p: Vector2) -> int:
	var f := _frame()
	if f.is_empty():
		return -1
	var best := -1
	var best_d := 12.0
	for i in 3:
		var d := INF
		if mode == "rotate":
			var pts := _ring_points(f[0], f[1][i])
			for k in pts.size() - 1:
				d = minf(d, _seg_dist(p, pts[k], pts[k + 1]))
		else:
			d = _seg_dist(p, _to_screen(f[0]), _to_screen(f[0] + f[1][i] * ARROW_L))
		if d < best_d:
			best_d = d
			best = i
	return best


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


# --- input ------------------------------------------------------------------------

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		match e.button_index:
			MOUSE_BUTTON_RIGHT:
				_orbiting = e.pressed
			MOUSE_BUTTON_WHEEL_UP:
				_dist = maxf(_dist * 0.9, 1.5)
				_place_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				_dist = minf(_dist * 1.1, 14.0)
				_place_camera()
			MOUSE_BUTTON_LEFT:
				if e.pressed:
					_last = e.position
					_drag_axis = _axis_at(e.position)
					if _drag_axis < 0:
						var picked := _pick(e.position)
						if picked != "":
							bone = picked
							bone_picked.emit(picked)
						else:
							_orbiting = true  # empty space: orbit (handy on touch screens)
				else:
					_drag_axis = -1
					_orbiting = false
		accept_event()
	elif e is InputEventMouseMotion:
		if _drag_axis >= 0:
			_drag(e.position)
		elif _orbiting:
			_yaw -= e.relative.x * 0.01
			_pitch = clampf(_pitch - e.relative.y * 0.01, -1.3, 1.3)
			_place_camera()
		else:
			_hover_axis = _axis_at(e.position)
		_last = e.position
		accept_event()


func _drag(p: Vector2) -> void:
	var f := _frame()
	if f.is_empty():
		return
	var c: Vector3 = f[0]
	var axis: Vector3 = f[1][_drag_axis]
	if mode == "rotate":
		# How far the mouse went round the gizmo's middle, as seen on screen.
		var mid := _to_screen(c)
		var d := wrapf((p - mid).angle() - (_last - mid).angle(), -PI, PI)
		var facing := signf(axis.dot(-_cam.global_basis.z))
		rotated.emit(bone, _drag_axis, rad_to_deg(-d) * (facing if facing != 0.0 else 1.0))
	else:
		# Along the arrow as drawn: screen pixels back to studs.
		var a := _to_screen(c)
		var b := _to_screen(c + axis * ARROW_L)
		var dir := b - a
		if dir.length() < 2.0:
			return
		var px := (p - _last).dot(dir.normalized())
		moved.emit(bone, _drag_axis, px * ARROW_L / dir.length())


## The body part under a screen point, or "".
func _pick(p: Vector2) -> String:
	var sp := p * (Vector2(_vp.size) / size)
	var from := _cam.project_ray_origin(sp)
	var to := from + _cam.project_ray_normal(sp) * 50.0
	var hit := _vp.find_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	if hit.is_empty() or not hit.collider.has_meta("bone"):
		return ""
	return str(hit.collider.get_meta("bone"))
