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
const RESPAWN_DELAY := 3.0
const EYE_HEIGHT := 1.62

var avatar: MellyAvatar
var cam_yaw := 0.0
var cam_pitch := -0.3
var cam_distance := 7.5
var move_input := Vector2.ZERO
var sprint := false
## Phones: the run button switches sprinting on until it's tapped again.
var sprint_toggle := false
## True while typing in chat, so WASD goes to the text field only.
var keyboard_blocked := false
## Extra horizontal push from slides/conveyors, set by world areas each frame.
var external_push := Vector3.ZERO
var spawn_point := Vector3(0, 1, 10)
var hp := 100.0
var dead := false
var first_person := false
## Shift lock: the camera sits over the right shoulder and the character faces where it looks.
var shift_locked := false
var _shoulder := 0.0
var seated := false

# Tunables a studio place can change (Humanoid / Workspace properties).
var walk_speed := MAX_SPEED
var sprint_speed := SPRINT_SPEED
var jump_velocity := JUMP_VELOCITY
var gravity := GRAVITY
var can_jump := true
var can_sprint := true
## Stamina: sprinting spends it, resting brings it back. max_stamina 0 = endless.
var max_stamina := 100.0
var stamina_drain := 20.0
var stamina_regen := 15.0
var stamina := 100.0
## Ran dry: no sprinting until a third of it is back.
var winded := false
var _rest := 0.0
var void_height := -25.0
var max_hp := 100.0
## Studio places: the server owns health and decides when to respawn.
var server_health := false
## Camera rules a place can set (Player.CameraMode / CameraMinZoom / CameraMaxZoom).
var camera_mode := "Classic"
var min_zoom := 0.0
var max_zoom := 16.0
## A script-driven camera (Camera.CameraType = Scriptable): its transform, or null.
var scripted_camera: Variant = null

var _collision: CollisionShape3D
var _unseat_time := 0.0

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
var _shake_power := 1.0


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
	_collision = col

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
	if dead or not can_jump:
		return
	if seated:
		stand_up()
		return
	_jump_buffer = JUMP_BUFFER


func can_sit() -> bool:
	return not dead and Time.get_ticks_msec() - _unseat_time > 800.0


## Sits on a bench seat. `seat` is the seat's top-center, `seat_basis` faces away from the backrest.
func sit_on(seat: Vector3, seat_basis: Basis) -> void:
	seated = true
	_collision.disabled = true
	velocity = Vector3.ZERO
	# The Sit pose puts the hips ~0.17 m above the feet.
	global_position = seat - Vector3(0, 0.17, 0) + seat_basis * Vector3(0, 0, 0.05)
	reset_physics_interpolation()
	var fwd := seat_basis * Vector3(0, 0, 1)
	_facing = atan2(-fwd.x, -fwd.z)
	avatar.rotation.y = _facing
	_emote = "sit"
	avatar.play("sit")


func stand_up() -> void:
	if not seated:
		return
	seated = false
	_collision.disabled = false
	_unseat_time = Time.get_ticks_msec()
	_emote = ""
	global_position += Vector3(0, 0.25, 0)
	velocity = Basis(Vector3.UP, _facing) * Vector3(0, 0, -2.5) + Vector3(0, jump_velocity * 0.8, 0)
	jumped.emit()


func rotate_camera(delta_px: Vector2) -> void:
	var sens := 0.0048 * float(Session.settings.camera_sensitivity)
	cam_yaw -= delta_px.x * sens
	cam_pitch = clampf(cam_pitch - delta_px.y * sens, -1.45, 1.2 if first_person else 0.6)


## A script sets the zoom (Camera:SetZoom): past the place's own limits if it wants.
func set_zoom(distance: float) -> void:
	cam_distance = clampf(distance, 0.0, 200.0)
	_set_first_person(cam_distance < 1.2)


## A script shakes the view (Camera:Shake): strength 1 is a bump, 5 an earthquake.
func shake(strength: float, seconds: float) -> void:
	_shake = maxf(_shake, seconds)
	_shake_power = maxf(strength, 0.0) * 1.5


func zoom_camera(amount: float) -> void:
	if camera_mode == "LockFirstPerson":
		return
	cam_distance = clampf(cam_distance + amount, _zoom_floor(), max_zoom)
	_set_first_person(cam_distance < 1.2)


func _update_stamina(delta: float, sprinting: bool) -> void:
	if max_stamina <= 0.0:
		stamina = 0.0
		winded = false
		return
	stamina = minf(stamina, max_stamina)
	if sprinting:
		_rest = 0.0
		stamina -= stamina_drain * delta
		if stamina <= 0.0:
			stamina = 0.0
			winded = true
	else:
		_rest += delta
		if _rest > 0.8:
			stamina = minf(max_stamina, stamina + stamina_regen * delta)
		if winded and stamina >= max_stamina * 0.3:
			winded = false


func toggle_first_person() -> void:
	if camera_mode != "Classic" or min_zoom >= 1.2:
		return  # the place decided
	if first_person:
		cam_distance = clampf(7.5, min_zoom, max_zoom)
		_set_first_person(false)
	else:
		cam_distance = 0.0
		_set_first_person(true)


## Can the player switch between first and third person here?
func can_toggle_view() -> bool:
	return camera_mode == "Classic" and min_zoom < 1.2


## Third person never gets closer than this (LockThirdPerson keeps the head in view).
func _zoom_floor() -> float:
	return maxf(min_zoom, 1.5) if camera_mode == "LockThirdPerson" else min_zoom


## Applies a place's camera rules; called whenever they may have changed.
func set_camera_rules(mode: String, min_z: float, max_z: float) -> void:
	max_z = maxf(max_z, min_z)
	if mode == camera_mode and is_equal_approx(min_z, min_zoom) and is_equal_approx(max_z, max_zoom):
		return
	camera_mode = mode
	min_zoom = min_z
	max_zoom = max_z
	match mode:
		"LockFirstPerson":
			cam_distance = 0.0
			_set_first_person(true)
		"LockThirdPerson":
			cam_distance = clampf(maxf(cam_distance, 7.5), _zoom_floor(), max_zoom)
			_set_first_person(false)
		_:
			if first_person and min_zoom >= 1.2:
				cam_distance = clampf(7.5, min_zoom, max_zoom)
				_set_first_person(false)
			elif not first_person:
				cam_distance = clampf(cam_distance, _zoom_floor(), max_zoom)


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
	if seated:
		seated = false
		_collision.disabled = false
	dead = true
	hp = 0.0
	health_changed.emit(hp)
	avatar.visible = false
	_emote = ""
	died.emit()
	velocity = Vector3.ZERO
	if server_health:
		return  # the server sends the new spawn point when it's time
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	respawn()


## Studio places: the server's health for this character.
func set_server_health(value: float, maximum: float) -> void:
	max_hp = maximum
	if value < hp and not dead:
		_since_hurt = 0.0
		_shake = minf(0.35, (hp - value) / maxf(maximum, 1.0) + 0.1)
		hurt.emit(hp - value)
	hp = value
	health_changed.emit(hp)
	if hp <= 0.0 and not dead:
		die()


## Studio places: moves (and revives) the character where the server says.
func respawn_at(pos: Vector3) -> void:
	spawn_point = pos
	respawn()


func respawn() -> void:
	global_position = spawn_point + (Vector3.ZERO if server_health else Vector3(randf_range(-2, 2), 0.2, randf_range(-2, 2)))
	reset_physics_interpolation()
	velocity = Vector3.ZERO
	_fall_speed = 0.0
	hp = max_hp
	dead = false
	avatar.visible = not first_person
	avatar.play("idle")
	health_changed.emit(hp)
	respawned.emit()


func _physics_process(delta: float) -> void:
	if dead or seated:
		return
	var on_floor := is_on_floor()
	if on_floor:
		_coyote = COYOTE_TIME
	else:
		_coyote -= delta
	_jump_buffer -= delta

	if not on_floor:
		velocity.y = maxf(velocity.y - gravity * delta, -MAX_FALL)
		_fall_speed = maxf(_fall_speed, -velocity.y)

	if _jump_buffer > 0.0 and _coyote > 0.0 and can_jump:
		velocity.y = jump_velocity
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
	var sprinting := (sprint or sprint_toggle) and can_sprint and not winded and input.length() > 0.1 and not seated
	_update_stamina(delta, sprinting)
	var top := sprint_speed if sprinting else walk_speed
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
		_fall_speed = 0.0
	_was_on_floor = now_floor

	if first_person or shift_locked:
		_facing = cam_yaw
	elif dir.length() > 0.05:
		_facing = lerp_angle(_facing, atan2(-dir.x, -dir.z), minf(delta * TURN_SPEED, 1.0))
	avatar.rotation.y = _facing

	var hspeed := Vector2(velocity.x, velocity.z).length()
	if not now_floor:
		_anim_state = "jump" if velocity.y > 1.0 else "fall"
	elif hspeed > walk_speed * 1.12:
		_anim_state = "run"
	elif hspeed > 0.5:
		_anim_state = "walk"
	else:
		_anim_state = "idle"
	if _emote != "":
		avatar.play(_emote)
	else:
		avatar.play(_anim_state)

	if global_position.y < void_height:
		die()


func _process(delta: float) -> void:
	_since_hurt += delta
	if not server_health and _since_hurt > 5.0 and hp < 100.0 and not dead:
		hp = minf(hp + 4.0 * delta, 100.0)
		health_changed.emit(hp)
	_update_camera(delta)


func _update_camera(delta: float) -> void:
	if scripted_camera is Transform3D:
		if not camera.top_level:
			camera.top_level = true
		var t: Transform3D = scripted_camera
		if _shake > 0.0:
			_shake = maxf(_shake - delta, 0.0)
			var k := minf(_shake, 0.35) * 0.08 * _shake_power
			t.basis = t.basis * Basis.from_euler(Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * k)
		camera.global_transform = t
		return
	if camera.top_level:
		camera.top_level = false
		camera.transform = Transform3D()
	var body := get_global_transform_interpolated().origin
	var target := body + Vector3(0, EYE_HEIGHT if first_person else 1.5, 0)
	# Over the shoulder while shift-locked (eased in and out).
	_shoulder = lerpf(_shoulder, 1.4 if shift_locked and not first_person else 0.0, minf(delta * 10.0, 1.0))
	target += Basis(Vector3.UP, cam_yaw) * Vector3(_shoulder, 0, 0)
	_camera_pivot.global_position = _camera_pivot.global_position.lerp(target, minf(delta * 22.0, 1.0))
	var shake := Vector3.ZERO
	if _shake > 0.0:
		_shake = maxf(_shake - delta, 0.0)
		shake = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * minf(_shake, 0.35) * 0.08 * _shake_power
		if _shake <= 0.0:
			_shake_power = 1.0
	_camera_pivot.rotation = Vector3(cam_pitch, cam_yaw, 0) + shake
	var want := 0.0 if first_person else cam_distance
	_spring.spring_length = lerpf(_spring.spring_length, want, minf(delta * 12.0, 1.0))
