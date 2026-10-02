class_name VRHands
extends RefCounted
## VR: climbing with your hands. Reach for a Climbable part and hold the grip button: that
## hand stays where it took hold, and moving it moves you instead (pull down and you go up).
## Let go and you keep the speed you had. Walking into a Climbable wall doesn't climb it in
## VR (local_player.gd). Places can move players by hand in their own ways from scripts
## (VRService:GetUserPosition, the character's AssemblyLinearVelocity).

const GRAB_RADIUS := 0.14  # how near a Climbable part a hand takes hold
const THROW_MAX := 9.0

var player: CharacterBody3D
var climb_check: Callable  # collider -> whether it's a Climbable part
var held := {}  # side -> Vector3: where the hand holds on
var _speeds: Array[Vector3] = []  # the body's last few velocities while held on
var _sphere := SphereShape3D.new()


## One physics step. True when the hands moved the body (the usual walking is skipped).
func step(delta: float) -> bool:
	var feet := player.global_position
	var move := Vector3.ZERO
	var count := 0
	for side in ["left", "right"]:
		var at: Variant = VR.palm_at(side, feet)
		if not at is Vector3 or not VR.grip(side):
			held.erase(side)
			continue
		if not held.has(side) and _climbable_at(at):
			held[side] = at
		if held.has(side):
			move += (held[side] as Vector3) - (at as Vector3)
			count += 1
	if count == 0:
		if not _speeds.is_empty():
			# Let go: off you go with the speed the last pull had.
			var v := Vector3.ZERO
			for s in _speeds:
				v += s
			player.velocity = (v / _speeds.size()).limit_length(THROW_MAX)
			_speeds.clear()
		return false
	player.velocity = move / count / maxf(delta, 0.001)
	player.move_and_slide()
	_speeds.append(player.get_real_velocity())
	if _speeds.size() > 4:
		_speeds.pop_front()
	return true


## A Climbable part within reach of this point.
func _climbable_at(at: Vector3) -> bool:
	if not climb_check.is_valid():
		return false
	var q := PhysicsShapeQueryParameters3D.new()
	_sphere.radius = GRAB_RADIUS
	q.shape = _sphere
	q.collision_mask = PlaceScene.LAYER_WORLD
	q.exclude = [player.get_rid()]
	q.transform = Transform3D(Basis(), at)
	for hit in player.get_world_3d().direct_space_state.intersect_shape(q, 8):
		if climb_check.call(hit.collider):
			return true
	return false


## Lets go of everything (dying, sitting down).
func release() -> void:
	held.clear()
	_speeds.clear()
