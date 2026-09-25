class_name LocalPlayer
extends CharacterBody3D
## The player's own Melly: camera-relative movement, jumping, third-person camera.

signal jumped
signal landed(impact: float)

const WALK_SPEED := 6.2
const RUN_SPEED := 9.0
const ACCEL := 40.0
const AIR_ACCEL := 14.0
const JUMP_VELOCITY := 8.6
const GRAVITY := 24.0
const MAX_FALL := 45.0
const COYOTE_TIME := 0.12
const JUMP_BUFFER := 0.14

var avatar: MellyAvatar
var cam_yaw := 0.0
var cam_pitch := -0.32
var cam_distance := 7.0
var move_input := Vector2.ZERO
var run := false
## True while typing in chat, so WASD goes to the text field only.
var keyboard_blocked := false
## Extra horizontal push from slides/conveyors, set by world areas each frame.
var external_push := Vector3.ZERO
var spawn_point := Vector3(0, 1, 8)

var _camera_pivot: Node3D
var _spring: SpringArm3D
var camera: Camera3D
var _coyote := 0.0
var _jump_buffer := 0.0
var _was_on_floor := true
var _fall_speed := 0.0
var _anim_state := "idle"
var _facing := PI
var _jump_queued := false


func _ready() -> void:
	floor_max_angle = deg_to_rad(50)
	floor_snap_length = 0.35
	floor_constant_speed = true
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_ADD_UPPER_VELOCITY
	var shape := CapsuleShape3D.new()
	shape.radius = 0.42
	shape.height = 1.8
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.9
	add_child(col)

	avatar = MellyAvatar.new()
	add_child(avatar)
	avatar.rotation.y = _facing

	_camera_pivot = Node3D.new()
	_camera_pivot.top_level = true
	add_child(_camera_pivot)
	_spring = SpringArm3D.new()
	_spring.spring_length = cam_distance
	_spring.margin = 0.25
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	_spring.shape = probe
	_spring.add_excluded_object(get_rid())
	_camera_pivot.add_child(_spring)
	camera = Camera3D.new()
	camera.fov = 70
	camera.far = 600
	_spring.add_child(camera)
	camera.make_current()
	cam_yaw = PI
	_update_camera(1.0)


func request_jump() -> void:
	_jump_buffer = JUMP_BUFFER


func rotate_camera(delta_px: Vector2) -> void:
	var sens := 0.0055 * float(Session.settings.camera_sensitivity)
	cam_yaw -= delta_px.x * sens
	cam_pitch = clampf(cam_pitch - delta_px.y * sens, -1.35, 0.55)


func zoom_camera(amount: float) -> void:
	cam_distance = clampf(cam_distance + amount, 2.5, 16.0)


func respawn() -> void:
	global_position = spawn_point
	velocity = Vector3.ZERO
	_fall_speed = 0.0


func current_anim() -> String:
	if avatar.is_waving():
		return "wave"
	return _anim_state


func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()
	if on_floor:
		_coyote = COYOTE_TIME
	else:
		_coyote -= delta
	_jump_buffer -= delta

	if not on_floor:
		velocity.y = maxf(velocity.y - GRAVITY * delta, -MAX_FALL)
		_fall_speed = maxf(_fall_speed, -velocity.y)

	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_VELOCITY
		_jump_buffer = 0.0
		_coyote = 0.0
		jumped.emit()

	var input := move_input
	var kb := Vector2.ZERO
	if not keyboard_blocked:
		kb = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if kb.length() > input.length():
		input = kb
	if input.length() > 1.0:
		input = input.normalized()
	var basis_yaw := Basis(Vector3.UP, cam_yaw)
	var dir := basis_yaw * Vector3(input.x, 0, input.y)
	var speed := RUN_SPEED if (run or input.length() > 0.95) else WALK_SPEED
	var target := dir * speed * minf(input.length() / 0.9, 1.0)
	var accel := ACCEL if on_floor else AIR_ACCEL
	var hv := Vector3(velocity.x, 0, velocity.z)
	hv = hv.move_toward(target, accel * delta)
	velocity.x = hv.x + external_push.x
	velocity.z = hv.z + external_push.z
	move_and_slide()
	velocity.x -= external_push.x
	velocity.z -= external_push.z
	external_push = Vector3.ZERO

	var now_floor := is_on_floor()
	if now_floor and not _was_on_floor:
		landed.emit(_fall_speed)
		_fall_speed = 0.0
	_was_on_floor = now_floor

	if dir.length() > 0.05:
		_facing = lerp_angle(_facing, atan2(-dir.x, -dir.z), minf(delta * 12.0, 1.0))
	avatar.rotation.y = _facing

	var hspeed := Vector2(velocity.x, velocity.z).length()
	if not now_floor:
		_anim_state = "jump" if velocity.y > 0.0 else "fall"
	elif hspeed > 7.2:
		_anim_state = "run"
	elif hspeed > 0.6:
		_anim_state = "walk"
	else:
		_anim_state = "idle"
	avatar.play(_anim_state)

	if global_position.y < -25.0:
		respawn()


func _process(delta: float) -> void:
	_update_camera(delta)


func _update_camera(delta: float) -> void:
	var target := global_position + Vector3(0, 1.55, 0)
	_camera_pivot.global_position = _camera_pivot.global_position.lerp(target, minf(delta * 18.0, 1.0)) if delta < 1.0 else target
	_camera_pivot.rotation = Vector3(cam_pitch, cam_yaw, 0)
	_spring.spring_length = lerpf(_spring.spring_length, cam_distance, minf(delta * 10.0, 1.0))
