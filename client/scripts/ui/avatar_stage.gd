class_name AvatarStage
extends SubViewportContainer
## Interactive 3D preview of a Melly avatar for menus. Drag to spin.

signal clicked

var avatar: MellyAvatar
var auto_spin := 0.35
var _vp: SubViewport
var _pivot: Node3D
var _dragging := false
var _drag_dist := 0.0
var _yaw_vel := 0.0
var _cam: Camera3D
var zoom := 1.0:
	set(v):
		zoom = v
		if _cam:
			_place_camera()


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	add_child(_vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#d9d0ff")
	env.ambient_light_energy = 0.38
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 35, 0)
	key.light_energy = 1.0
	key.shadow_enabled = true
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_energy = 0.3
	rim.light_color = Color("#b89cff")
	_vp.add_child(rim)

	_cam = Camera3D.new()
	_cam.fov = 32
	_vp.add_child(_cam)
	_place_camera()

	var pedestal := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.85
	cyl.bottom_radius = 0.95
	cyl.height = 0.12
	pedestal.mesh = cyl
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color("#2e2940")
	pm.roughness = 0.6
	pedestal.material_override = pm
	pedestal.position.y = -0.06
	_vp.add_child(pedestal)

	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	avatar = MellyAvatar.new()
	# MellyAvatar looks down -Z; turn her to face the camera.
	avatar.rotation.y = PI
	_pivot.add_child(avatar)
	_pivot.rotation.y = deg_to_rad(-20)


func _place_camera() -> void:
	var dist := 5.2 / zoom
	var pos := Vector3(0, 1.05 + 0.25 / zoom, dist)
	_cam.transform = Transform3D(Basis.looking_at(Vector3(0, 0.95, 0) - pos), pos)


func _process(delta: float) -> void:
	if not _dragging:
		_yaw_vel = lerpf(_yaw_vel, auto_spin, delta * 1.5)
		_pivot.rotation.y += _yaw_vel * delta


func _gui_input(event: InputEvent) -> void:
	# Touch reaches us as emulated mouse events, which keeps this single-path.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_drag_dist = 0.0
		elif _drag_dist < 8.0:
			clicked.emit()
	elif event is InputEventMouseMotion and _dragging:
		_drag_dist += absf(event.relative.x)
		_pivot.rotation.y += event.relative.x * 0.012
		_yaw_vel = event.relative.x * 0.6
