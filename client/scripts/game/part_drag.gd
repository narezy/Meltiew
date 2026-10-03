class_name PartDrag
extends RefCounted
## Dragging a part that has a DragDetector, with the mouse, a finger or the VR laser. The
## part follows the pointer right here (an anchored one along a plane through where it
## was grabbed; an unanchored one is carried, then thrown with the speed it had), and the
## server hears about it 15 times a second (DragStart / DragContinue / DragEnd, and it
## moves an anchored part for everyone).

const SEND_EVERY := 1.0 / 15.0

var game: Node  # game.gd
var detector := ""
var part := ""
var _plane := Plane()
var _offset := Vector3.ZERO  # from the grab point to the part's middle
var _rb: RigidBody3D
var _send := 0.0
var _last := Vector3.ZERO
var _vel := Vector3.ZERO
var _cursor := Vector3.ZERO


func active() -> bool:
	return detector != ""


## Starts dragging what's under this ray, if it can be dragged from here. True when it did.
func try_start(from: Vector3, dir: Vector3) -> bool:
	var host: PlaceHost = game.place_host
	if host == null:
		return false
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 200.0, PlaceScene.LAYER_WORLD | PlaceScene.LAYER_GHOST)
	q.exclude = [game.player.get_rid()]
	var hit: Dictionary = (game as Node3D).get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return false
	var id := PlaceScene.id_of(hit.collider)
	var det := host.tree.child_of_class(id, "DragDetector") if id != "" else ""
	if det == "" or host.tree.prop(det, "Enabled") == false:
		return false
	var reach := float(host.tree.prop(det, "MaxActivationDistance"))
	if (hit.position as Vector3).distance_to(game.player.global_position) > reach + 2.0:
		return false
	detector = det
	part = id
	var body := host.scene.body_of(id)
	_offset = body.global_position - (hit.position as Vector3)
	var cam: Camera3D = game.player.camera
	_plane = Plane(Vector3.UP, hit.position) if str(host.tree.prop(det, "DragStyle")) != "TranslateViewPlane" \
		else Plane(-cam.global_basis.z, hit.position)
	_rb = body as RigidBody3D if body is RigidBody3D else null
	if _rb:
		host.scene.claim_part(_rb)
		_rb.freeze = true
	_last = body.global_position
	_cursor = hit.position
	_send = 0.0
	game.net.send({"t": "drag", "id": detector, "phase": "start", "p": _v(_cursor)})
	return true


## The pointer moved (a ray from the camera or the hand): the part follows.
func move(from: Vector3, dir: Vector3, delta: float) -> void:
	if not active():
		return
	var host: PlaceHost = game.place_host
	if host == null or not host.tree.has(part):
		end()
		return
	var at: Variant = _plane.intersects_ray(from, dir)
	if not at is Vector3:
		return
	_cursor = at
	var to: Vector3 = at + _offset
	var body := host.scene.body_of(part)
	if body == null:
		end()
		return
	if host.tree.prop(detector, "ResponseStyle") != "Custom":
		if _rb:
			_rb.global_position = to
		else:
			host.scene.pose_part(part, Transform3D(body.global_basis, to))
			host.tree.set_quiet(part, "Position", to)
	_vel = (body.global_position - _last) / maxf(delta, 0.001)
	_last = body.global_position
	_send -= delta
	if _send <= 0.0:
		_send = SEND_EVERY
		game.net.send({"t": "drag", "id": detector, "phase": "move", "p": _v(_cursor), "pos": _v(to)})


func end() -> void:
	if not active():
		return
	game.net.send({"t": "drag", "id": detector, "phase": "end"})
	if is_instance_valid(_rb):
		_rb.freeze = false
		_rb.linear_velocity = _vel.limit_length(40.0)
	detector = ""
	part = ""
	_rb = null


static func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)]
