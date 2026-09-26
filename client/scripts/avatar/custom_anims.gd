class_name CustomAnims
extends RefCounted
## Animations made in Studio's animator ("anim://<id>"): downloaded once, turned
## into Godot Animations for Melly's skeleton and shared by every avatar.
##
## Data: {length, loop, keys: {Bone: [[t, rx, ry, rz], ...]}, moves: {Bone: [[t, x, y, z], ...]}}
## with rotations in degrees and moves in studs (older data: the torso's moves as `pos`).

const BONES := ["Torso", "Head", "ArmL", "ArmR", "LegL", "LegR"]
const TORSO_REST := Vector3(0, 2, 0)
## Where each bone rests in its parent (the torso; the torso in the skeleton), model units.
const REST := {"Torso": Vector3(0, 2, 0), "Head": Vector3(0, 2, 0), "ArmL": Vector3(1, 1.88, 0),
	"ArmR": Vector3(-1, 1.88, 0), "LegL": Vector3(0.5, 0, 0), "LegR": Vector3(-0.5, 0, 0)}

static var _anims := {}  # id -> Animation
static var _data := {}  # id -> data
static var _waiting := {}  # id -> Array[Callable]


static func id_of(ref: String) -> int:
	return ref.trim_prefix("anim://").to_int() if ref.begins_with("anim://") else 0


## Calls `done(animation)` now if loaded, or when it arrives (null if it can't).
static func fetch(ref: String, done: Callable) -> void:
	var id := id_of(ref)
	if id <= 0:
		done.call(null)
		return
	if _anims.has(id):
		done.call(_anims[id])
		return
	if _waiting.has(id):
		_waiting[id].append(done)
		return
	_waiting[id] = [done]
	var r := await Api.request("GET", "/api/animations/%d" % id)
	var anim: Animation = null
	if r.ok:
		_data[id] = r.data.animation.data
		anim = build(r.data.animation.data)
		_anims[id] = anim
	var list: Array = _waiting.get(id, [])
	_waiting.erase(id)
	for cb in list:
		if cb.is_valid():
			cb.call(anim)


## The animator saved a new version: use it right away.
static func put(id: int, data: Dictionary) -> void:
	_data[id] = data
	_anims[id] = build(data)


static func data_of(id: int) -> Variant:
	return _data.get(id)


static func build(data: Dictionary) -> Animation:
	var a := Animation.new()
	a.length = maxf(float(data.get("length", 1.0)), 0.05)
	a.loop_mode = Animation.LOOP_LINEAR if data.get("loop", false) else Animation.LOOP_NONE
	var keys: Dictionary = data.get("keys", {})
	for bone in BONES:
		var t := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(t, NodePath("Melly/Skeleton3D:" + bone))
		a.track_set_interpolation_type(t, Animation.INTERPOLATION_CUBIC)
		var list: Array = keys.get(bone, [])
		if list.is_empty():
			a.rotation_track_insert_key(t, 0.0, Quaternion.IDENTITY)
		for k in list:
			a.rotation_track_insert_key(t, float(k[0]), rot(Vector3(float(k[1]), float(k[2]), float(k[3]))))
	var moves := moves_of(data)
	for bone in BONES:
		var list: Array = moves.get(bone, [])
		if list.is_empty() and bone != "Torso":
			continue
		var tp := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(tp, NodePath("Melly/Skeleton3D:" + bone))
		a.track_set_interpolation_type(tp, Animation.INTERPOLATION_CUBIC)
		if list.is_empty():
			a.position_track_insert_key(tp, 0.0, REST[bone])
		for k in list:
			a.position_track_insert_key(tp, float(k[0]), REST[bone] + Vector3(float(k[1]), float(k[2]), float(k[3])) / MellyAvatar.MODEL_SCALE)
	return a


## Moves per bone, reading old data's torso-only `pos` too.
static func moves_of(data: Dictionary) -> Dictionary:
	var moves: Dictionary = data.get("moves", {})
	if moves.is_empty() and data.get("pos") is Array and not data.pos.is_empty():
		return {"Torso": data.pos}
	return moves


## Degrees (x, y, z) to the bone's rotation.
static func rot(deg: Vector3) -> Quaternion:
	return Quaternion.from_euler(Vector3(deg_to_rad(deg.x), deg_to_rad(deg.y), deg_to_rad(deg.z)))
