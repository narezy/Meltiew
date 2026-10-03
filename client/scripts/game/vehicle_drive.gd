class_name VehicleDrive
extends Vehicle
## Driving a VehicleSeat from here (the driver's app): the movement keys, a stick or a
## phone's joystick give gas, brake and steering; the vehicle is a box the size of its
## parts that slides along walls, rolls over slopes leaning with the ground, falls when
## there's nothing under it (or floats at HoverHeight), and drifts as much as its Grip
## lets it. Reports where it is to the server 20 times a second. After the driver gets
## out it rolls on to a stop by itself.

signal report(msg: Dictionary)

const SEND_EVERY := 0.05
const COAST_MAX := 6.0

var player: LocalPlayer
var driving := true
var speed := 0.0  # forward, studs a second
var throttle := 0.0
var steer := 0.0
var _body: CharacterBody3D
var _side := Vector3.ZERO  # sliding sideways (drifting)
var _vy := 0.0
var _send := 0.0
var _coast := 0.0
var _still := 0.0


func _ready() -> void:
	_body = CharacterBody3D.new()
	_body.collision_layer = 0
	_body.collision_mask = PlaceScene.LAYER_WORLD
	_body.floor_max_angle = deg_to_rad(50.0)
	_body.floor_snap_length = 0.6
	_body.safe_margin = 0.02
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	# A touch narrower than the parts, and lifted off the ground a hair: kerbs and seams
	# in the floor don't snag it.
	bs.size = (box.size - Vector3(0.1, 0.05, 0.1)).max(Vector3.ONE * 0.2)
	shape.shape = bs
	shape.position = box.get_center() + Vector3(0, 0.025, 0)
	_body.add_child(shape)
	scene.add_child(_body)
	_body.global_transform = pose
	for id in parts:
		var b: Variant = scene.body_of(id)
		if b is PhysicsBody3D:
			_body.add_collision_exception_with(b)
	if player:
		_body.add_collision_exception_with(player)


func _exit_tree() -> void:
	if is_instance_valid(_body):
		_body.queue_free()


## The driver got out: no more gas or steering, it rolls to a stop on its own.
func let_go() -> void:
	driving = false
	throttle = 0.0
	steer = 0.0


func _prop(key: String, fallback: float) -> float:
	var v: Variant = scene.tree.prop(seat, key)
	return float(v) if v != null else fallback


func _physics_process(delta: float) -> void:
	if not scene.tree.has(seat):
		queue_free()
		return
	var max_speed := _prop("MaxSpeed", 60.0)
	var torque := _prop("Torque", 40.0)
	var turn_speed := deg_to_rad(_prop("TurnSpeed", 90.0))
	var grip := clampf(_prop("Grip", 0.85), 0.0, 1.0)
	var hover := _prop("HoverHeight", 0.0)
	var gravity := player.gravity if player else 22.0
	if driving:
		var input := player.move_input if player else Vector2.ZERO
		if player and not player.keyboard_blocked:
			var kb := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
			if kb.length() > input.length():
				input = kb
		throttle = clampf(-input.y, -1.0, 1.0)
		steer = clampf(input.x, -1.0, 1.0)
	var ground := _probe(hover)
	var grounded: bool = _body.is_on_floor() or (ground.hit and ground.dist < (hover + 0.6 if hover > 0.0 else 0.35))
	# Gas, brakes and rolling to a stop.
	if grounded:
		if absf(throttle) > 0.05:
			if speed * throttle < 0.0 and absf(speed) > 0.5:
				speed = move_toward(speed, 0.0, torque * 2.5 * absf(throttle) * delta)
			else:
				speed = clampf(speed + throttle * torque * delta, -max_speed * 0.5, max_speed)
		else:
			speed = move_toward(speed, 0.0, torque * 0.6 * delta)
		# Steering: only while moving, and backwards the other way round (like a car).
		var moving := clampf(absf(speed) / 6.0, 0.0, 1.0)
		var dir := signf(speed) if absf(speed) > 0.1 else 1.0
		var turn := -steer * turn_speed * moving * dir * delta
		if hover > 0.0:
			turn = -steer * turn_speed * maxf(moving, 0.35) * delta
		pose.basis = Basis(Vector3.UP, turn) * pose.basis
	else:
		speed = move_toward(speed, 0.0, torque * 0.05 * delta)
	# Leaning with the ground (back upright in the air).
	var want_up: Vector3 = ground.normal if grounded and hover <= 0.0 else Vector3.UP
	var cur_up := pose.basis.y.normalized()
	if cur_up.dot(want_up) < 0.9999:
		var k := minf(1.0, (8.0 if grounded else 2.0) * delta)
		var q := Quaternion(cur_up, cur_up.slerp(want_up, k).normalized())
		pose.basis = Basis(q) * pose.basis
	pose.basis = pose.basis.orthonormalized()
	# Forward along the flat ground; sideways drift fades by Grip; gravity, or the hover.
	var fwd := -pose.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	_side = _side - fwd * _side.dot(fwd)
	_side *= 1.0 - clampf((0.5 + grip * 9.5) * delta, 0.0, 1.0)
	if hover > 0.0:
		var miss: float = (hover - ground.dist) if ground.hit else -2.0
		_vy = lerpf(_vy, clampf(miss * 6.0, -gravity, 12.0), minf(1.0, 6.0 * delta))
	elif _body.is_on_floor():
		_vy = -0.5
	else:
		_vy = maxf(_vy - gravity * delta, -60.0)
	_body.global_transform = pose
	_body.velocity = fwd * speed + _side + Vector3(0, _vy, 0)
	_body.move_and_slide()
	# Walls and other cars take speed away.
	var real := _body.get_real_velocity()
	var flat := Vector3(real.x, 0, real.z)
	speed = flat.dot(fwd) if absf(speed) > 0.01 else 0.0
	_side = flat - fwd * flat.dot(fwd)
	if hover <= 0.0 and not _body.is_on_floor():
		_vy = real.y
	pose.origin = _body.global_position
	place(pose, speed, steer if driving else 0.0, delta)
	_send -= delta
	if _send <= 0.0:
		_send = SEND_EVERY
		var r := degrees_of(pose.basis)
		report.emit({"t": "veh", "id": seat, "p": [snappedf(pose.origin.x, 0.001), snappedf(pose.origin.y, 0.001), snappedf(pose.origin.z, 0.001)],
			"r": [snappedf(r.x, 0.01), snappedf(r.y, 0.01), snappedf(r.z, 0.01)], "sp": snappedf(speed, 0.01),
			"th": snappedf(throttle, 0.01), "st": snappedf(steer, 0.01)})
	# Out of the driver's hands: rolls on until it stops (or for a few seconds).
	if not driving:
		_coast += delta
		_still = _still + delta if absf(speed) < 0.3 and grounded else 0.0
		if _still > 0.5 or _coast > COAST_MAX:
			write_tree()
			queue_free()


## What's under the vehicle: the four bottom corners look down. {hit, normal (average),
## dist (from the bottom of the vehicle to the ground)}
func _probe(hover: float) -> Dictionary:
	var space := _body.get_world_3d().direct_space_state
	var bottom := box.position.y
	var reach := maxf(hover, 0.0) + 3.0
	var normal := Vector3.ZERO
	var dist := INF
	var hits := 0
	var ex: Array[RID] = [_body.get_rid()]
	for id in parts:
		var b: Variant = scene.body_of(id)
		if b is CollisionObject3D:
			ex.append((b as CollisionObject3D).get_rid())
	if player:
		ex.append(player.get_rid())
	for cx in [box.position.x + 0.1, box.end.x - 0.1]:
		for cz in [box.position.z + 0.1, box.end.z - 0.1]:
			var from := pose * Vector3(cx, bottom + 0.5, cz)
			var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (reach + 0.5), PlaceScene.LAYER_WORLD)
			q.exclude = ex
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				continue
			hits += 1
			normal += hit.normal
			dist = minf(dist, from.distance_to(hit.position) - 0.5)
	if hits == 0:
		return {"hit": false, "normal": Vector3.UP, "dist": INF}
	return {"hit": true, "normal": (normal / hits).normalized(), "dist": dist}
