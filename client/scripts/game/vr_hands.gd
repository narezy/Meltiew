class_name VRHands
extends RefCounted
## VR: moving yourself with your hands. A hand that holds on to something stays where it
## took hold, and the body moves instead when you move that hand: pull down on a ledge and
## you go up, push off the ground and you fly. Let go and you keep the speed you had.
##
## Two ways, by the place (StarterPlayer.VRLocomotion):
##   Walk (the usual): only Climbable parts, and only while the grip button holds on. The
##     stick walks as always; walking into a Climbable wall doesn't climb it in VR.
##   Arms: no walking at all, like the gorilla games: a hand touching anything solid holds
##     on to it until it's pulled back off the surface.

const HAND_RADIUS := 0.09
const GRAB_RADIUS := 0.14  # reaching for a Climbable part: a little more forgiving
const LET_GO := 0.04  # studs a hand comes back off a surface to let go of it (Arms)
const THROW_MAX := {"arms": 16.0, "climb": 9.0}

var player: CharacterBody3D
var arms := false  # StarterPlayer.VRLocomotion = "Arms"
var climb_check: Callable  # collider -> whether it's a Climbable part
var held := {}  # side -> {"at": Vector3 where the hand holds on, "n": the surface's normal}
var _prev := {}  # side -> Vector3: where the hand was last step (for fast swings)
var _speeds: Array[Vector3] = []  # the body's last few velocities while held on
var _sphere := SphereShape3D.new()


## One physics step. True when the hands moved the body (the usual walking is skipped).
func step(delta: float) -> bool:
	var feet := player.global_position
	var space := player.get_world_3d().direct_space_state
	var move := Vector3.ZERO
	var count := 0
	for side in ["left", "right"]:
		var at: Variant = VR.palm_at(side, feet)
		if not at is Vector3:
			held.erase(side)
			_prev.erase(side)
			continue
		var hand: Vector3 = at
		if held.has(side) and not _keeps(side, hand):
			held.erase(side)
		if not held.has(side):
			var hold: Variant = _take_hold(side, hand, space)
			if hold is Dictionary:
				held[side] = hold
		_prev[side] = hand
		if held.has(side):
			move += (held[side].at as Vector3) - hand
			count += 1
	if count == 0:
		if not _speeds.is_empty():
			# Let go: off you go with the speed the last pull had.
			var v := Vector3.ZERO
			for s in _speeds:
				v += s
			v /= _speeds.size()
			player.velocity = v.limit_length(THROW_MAX["arms" if arms else "climb"])
			_speeds.clear()
		return false
	move /= count
	player.velocity = move / maxf(delta, 0.001)
	player.move_and_slide()
	_speeds.append(player.get_real_velocity())
	if _speeds.size() > 4:
		_speeds.pop_front()
	return true


## Whether a hand still holds on: Arms, until it's pulled back off the surface; climbing,
## while the grip button is down.
func _keeps(side: String, hand: Vector3) -> bool:
	if not arms:
		return VR.grip(side)
	var h: Dictionary = held[side]
	return (hand - (h.at as Vector3)).dot(h.n) < LET_GO


## Where a hand takes hold, or null: Arms, wherever it meets something solid on its way
## from last step (a quick slap doesn't pass through); climbing, a Climbable part within
## reach while the grip is down.
func _take_hold(side: String, hand: Vector3, space: PhysicsDirectSpaceState3D) -> Variant:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _sphere
	q.collision_mask = PlaceScene.LAYER_WORLD
	q.exclude = [player.get_rid()]
	if not arms:
		if not VR.grip(side):
			return null
		_sphere.radius = GRAB_RADIUS
		q.transform = Transform3D(Basis(), hand)
		for hit in space.intersect_shape(q, 8):
			if climb_check.is_valid() and climb_check.call(hit.collider):
				return {"at": hand, "n": Vector3.UP}
		return null
	_sphere.radius = HAND_RADIUS
	var from: Vector3 = _prev.get(side, hand)
	q.transform = Transform3D(Basis(), from)
	q.motion = hand - from
	var frac := space.cast_motion(q)
	if frac[1] >= 1.0:
		# Nothing on the way, but the hand may have come out of the step inside something.
		q.motion = Vector3.ZERO
		q.transform = Transform3D(Basis(), hand)
		if space.intersect_shape(q, 1).is_empty():
			return null
		var info := space.get_rest_info(q)
		return {"at": hand, "n": info.get("normal", Vector3.UP)}
	var touch := from + (hand - from) * frac[0]
	q.transform = Transform3D(Basis(), from + (hand - from) * frac[1])
	q.motion = Vector3.ZERO
	var info := space.get_rest_info(q)
	return {"at": touch, "n": info.get("normal", (from - hand).normalized())}


## Lets go of everything (dying, sitting down, a teleport).
func release() -> void:
	held.clear()
	_prev.clear()
	_speeds.clear()
