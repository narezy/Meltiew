class_name LocalPlayer
extends CharacterBody3D
## The player's own Melly: camera-relative movement, jumping, health,
## third/first-person camera and emotes.

signal jumped
signal landed(impact: float)
signal health_changed(hp: float)
signal hurt(amount: float)
signal died
signal respawned
signal camera_mode_changed(first_person: bool)

const MAX_SPEED := 5.0
const SPRINT_SPEED := 7.0
const ACCEL := 22.0
const DECEL := 28.0
const AIR_ACCEL := 9.0
const JUMP_VELOCITY := 8.2
const GRAVITY := 22.0
const MAX_FALL := 50.0
const COYOTE_TIME := 0.12
const JUMP_BUFFER := 0.14
const TURN_SPEED := 9.0
const SAFE_IMPACT := 21.0
const DAMAGE_PER_MS := 5.0
const RESPAWN_DELAY := 3.0
const EYE_HEIGHT := 1.62

var avatar: MellyAvatar
var cam_yaw := 0.0
var cam_pitch := -0.3
var cam_distance := 7.5
var move_input := Vector2.ZERO
var sprint := false
## True while typing in chat, so WASD goes to the text field only.
var keyboard_blocked := false
## Extra horizontal push from slides/conveyors, set by world areas each frame.
var external_push := Vector3.ZERO
var spawn_point := Vector3(0, 1, 10)
var hp := 100.0
var dead := false
var first_person := false

var _camera_pivot: Node3D
var _spring: SpringArm3D
var camera: Camera3D
var _coyote := 0.0
var _jump_buffer := 0.0
var _was_on_floor := true
var _fall_speed := 0.0
var _anim_state := "idle"
var _facing := 0.0
var _emote := ""
var _since_hurt := 10.0
var _shake := 0.0


func _ready() -> void:
	floor_max_angle = deg_to_rad(48)
	floor_snap_length = 0.4
	floor_constant_speed = true
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.9
	add_child(col)

	avatar = MellyAvatar.new()
	add_child(avatar)
	avatar.rotation.y = _facing

	# The camera rig is moved every rendered frame, so it opts out of physics interpolation
	# and follows the player's interpolated transform instead.
	_camera_pivot = Node3D.new()
	_camera_pivot.top_level = true
	_camera_pivot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
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
	camera.far = 700
	_spring.add_child(camera)
	camera.make_current()
	_camera_pivot.global_position = global_position + Vector3(0, EYE_HEIGHT, 0)


func request_jump() -> void:
	if not dead:
		_jump_buffer = JUMP_BUFFER


func rotate_camera(delta_px: Vector2) -> void:
	var sens := 0.0048 * float(Session.settings.camera_sensitivity)
	cam_yaw -= delta_px.x * sens
	cam_pitch = clampf(cam_pitch - delta_px.y * sens, -1.45, 1.2 if first_person else 0.6)


func zoom_camera(amount: float) -> void:
	var next := clampf(cam_distance + amount, 0.0, 16.0)
	cam_distance = next
	_set_first_person(cam_distance < 1.2)


func toggle_first_person() -> void:
	if first_person:
		cam_distance = 7.5
		_set_first_person(false)
	else:
		cam_distance = 0.0
		_set_first_person(true)


func _set_first_person(on: bool) -> void:
	if on == first_person:
		return
	first_person = on
	if on:
		cam_pitch = clampf(cam_pitch, -1.4, 1.2)
	else:
		cam_pitch = clampf(cam_pitch, -1.45, 0.6)
	avatar.visible = not on and not dead
	camera_mode_changed.emit(on)


func play_emote(e: String) -> void:
	if dead or not is_on_floor():
		return
	_emote = e
	avatar.play(e)


func current_anim() -> String:
	if dead:
		return "dead"
	if _emote != "":
		return _emote
	var s := avatar.current_state()
	return s if s == "wave" else _anim_state


func take_damage(amount: float) -> void:
	if dead or amount <= 0.0:
		return
	hp = maxf(hp - amount, 0.0)
	_since_hurt = 0.0
	_shake = minf(0.35, amount / 100.0 + 0.1)
	hurt.emit(amount)
	health_changed.emit(hp)
	if hp <= 0.0:
		die()


func die() -> void:
	if dead:
		return
	dead = true
	hp = 0.0
	health_changed.emit(hp)
	avatar.visible = false
	velocity = Vector3.ZERO
	_emote = ""
	died.emit()
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	respawn()


func respawn() -> void:
	global_position = spawn_point + Vector3(randf_range(-2, 2), 0.2, randf_range(-2, 2))
	reset_physics_interpolation()
	velocity = Vector3.ZERO
	_fall_speed = 0.0
	hp = 100.0
	dead = false
	avatar.visible = not first_person
	avatar.play("idle")
	health_changed.emit(hp)
	respawned.emit()


func _physics_process(delta: float) -> void:
	if dead:
		return
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
		_emote = ""
		jumped.emit()

	var input := move_input
	if not keyboard_blocked:
		var kb := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if kb.length() > input.length():
			input = kb
	if input.length() > 1.0:
		input = input.normalized()
	if input.length() > 0.1 and _emote != "":
		_emote = ""
	var dir := Basis(Vector3.UP, cam_yaw) * Vector3(input.x, 0, input.y)
	var top := SPRINT_SPEED if sprint else MAX_SPEED
	var target := dir * top * clampf(input.length(), 0.0, 1.0)
	var hv := Vector3(velocity.x, 0, velocity.z)
	var rate := (ACCEL if target.length() > 0.01 else DECEL) if on_floor else AIR_ACCEL
	hv = hv.move_toward(target, rate * delta)
	velocity.x = hv.x + external_push.x
	velocity.z = hv.z + external_push.z
	move_and_slide()
	velocity.x -= external_push.x
	velocity.z -= external_push.z
	external_push = Vector3.ZERO

	var now_floor := is_on_floor()
	if now_floor and not _was_on_floor:
		landed.emit(_fall_speed)
		if _fall_speed > SAFE_IMPACT:
			take_damage((_fall_speed - SAFE_IMPACT) * DAMAGE_PER_MS)
		_fall_speed = 0.0
	_was_on_floor = now_floor

	if first_person:
		_facing = cam_yaw
	elif dir.length() > 0.05:
		_facing = lerp_angle(_facing, atan2(-dir.x, -dir.z), minf(delta * TURN_SPEED, 1.0))
	avatar.rotation.y = _facing

	var hspeed := Vector2(velocity.x, velocity.z).length()
	if not now_floor:
		_anim_state = "jump" if velocity.y > 1.0 else "fall"
	elif hspeed > 5.6:
		_anim_state = "run"
	elif hspeed > 0.5:
		_anim_state = "walk"
	else:
		_anim_state = "idle"
	if _emote != "":
		avatar.play(_emote)
	else:
		avatar.play(_anim_state)

	if global_position.y < -25.0:
		die()


func _process(delta: float) -> void:
	_since_hurt += delta
	if _since_hurt > 5.0 and hp < 100.0 and not dead:
		hp = minf(hp + 4.0 * delta, 100.0)
		health_changed.emit(hp)
	_update_camera(delta)


func _update_camera(delta: float) -> void:
	var body := get_global_transform_interpolated().origin
	var target := body + Vector3(0, EYE_HEIGHT if first_person else 1.5, 0)
	_camera_pivot.global_position = _camera_pivot.global_position.lerp(target, minf(delta * 22.0, 1.0))
	var shake := Vector3.ZERO
	if _shake > 0.0:
		_shake = maxf(_shake - delta, 0.0)
		shake = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.08
	_camera_pivot.rotation = Vector3(cam_pitch, cam_yaw, 0) + shake
	var want := 0.0 if first_person else cam_distance
	_spring.spring_length = lerpf(_spring.spring_length, want, minf(delta * 12.0, 1.0))
