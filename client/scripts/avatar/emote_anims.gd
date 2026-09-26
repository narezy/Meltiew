class_name EmoteAnims
extends RefCounted
## Procedural emote animations for the Melly rig (bones: Torso, Head, ArmL, ArmR, LegL, LegR).
## Model space: +Z is Melly's front, ArmL sits on +X. Rotating a limb by -X swings it forward,
## +Z raises ArmL sideways (and -Z raises ArmR).

const TORSO_REST := Vector3(0, 2, 0)


static func install(ap: AnimationPlayer) -> void:
	var lib: AnimationLibrary = ap.get_animation_library(&"")
	for spec in [_dance(), _cheer(), _sit(), _clap(), _laugh(), _punch(), _throw()]:
		if not lib.has_animation(spec.name):
			lib.add_animation(spec.name, _build(spec))
	# The imported clips never key the torso position (and some skip bones), so after
	# an emote like Sit the pose would stick. Give every clip explicit rest keys.
	for clip in ["Idle", "Walk", "Jump", "Wave"]:
		if lib.has_animation(clip):
			_complete(lib.get_animation(clip))
	if lib.has_animation("Walk") and not lib.has_animation("Run"):
		lib.add_animation("Run", _run(lib.get_animation("Walk")))
	if not lib.has_animation("Climb"):
		lib.add_animation("Climb", _climb())


## Climbing a wall: hands reach up in turn, knees come up in turn, leaning in.
static func _climb() -> Animation:
	var a := Animation.new()
	a.length = 0.8
	a.loop_mode = Animation.LOOP_LINEAR
	var d := deg_to_rad(1.0)
	var tracks := {
		"ArmL": [q(-165 * d), q(-110 * d), q(-165 * d)],
		"ArmR": [q(-110 * d), q(-165 * d), q(-110 * d)],
		"LegL": [q(-45 * d), q(0), q(-45 * d)],
		"LegR": [q(0), q(-45 * d), q(0)],
		"Torso": [q(8 * d), q(8 * d), q(8 * d)],
		"Head": [q(-20 * d), q(-20 * d), q(-20 * d)],
	}
	for bone in tracks:
		var t := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(t, NodePath("Melly/Skeleton3D:" + bone))
		a.track_set_interpolation_type(t, Animation.INTERPOLATION_CUBIC)
		for i in 3:
			a.rotation_track_insert_key(t, a.length * i / 2.0, tracks[bone][i])
	var tp := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(tp, NodePath("Melly/Skeleton3D:Torso"))
	a.position_track_insert_key(tp, 0.0, TORSO_REST)
	return a


## Running, made from the walk: arms and legs swing much wider, the body leans
## into it and bounces twice per stride, the head stays level.
static func _run(walk: Animation) -> Animation:
	var a := walk.duplicate(true) as Animation
	a.loop_mode = Animation.LOOP_LINEAR
	var gains := {"ArmL": 2.0, "ArmR": 2.0, "LegL": 1.6, "LegR": 1.6}
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := str(a.track_get_path(t)).get_slice(":", 1)
		if not gains.has(bone):
			continue
		for k in a.track_get_key_count(t):
			var qk: Quaternion = a.track_get_key_value(t, k)
			if qk.w < 0.0:
				qk = -qk
			var ang := qk.get_angle()
			if ang > 0.0001:
				a.track_set_key_value(t, k, Quaternion(qk.get_axis(), ang * float(gains[bone])))
	var L := a.length
	var torso := NodePath("Melly/Skeleton3D:Torso")
	var head := NodePath("Melly/Skeleton3D:Head")
	for path in [torso, head]:
		var old := a.find_track(path, Animation.TYPE_ROTATION_3D)
		if old != -1:
			a.remove_track(old)
	var tr := a.add_track(Animation.TYPE_ROTATION_3D)
	a.track_set_path(tr, torso)
	var hr := a.add_track(Animation.TYPE_ROTATION_3D)
	a.track_set_path(hr, head)
	for i in 5:
		var twist := 0.1 * (1.0 if i % 4 == 1 else (-1.0 if i % 4 == 3 else 0.0))
		a.rotation_track_insert_key(tr, L * i / 4.0, q(0.2, twist, 0.0))
		a.rotation_track_insert_key(hr, L * i / 4.0, q(-0.14, -twist * 0.6, 0.0))
	var old_p := a.find_track(torso, Animation.TYPE_POSITION_3D)
	if old_p != -1:
		a.remove_track(old_p)
	var tp := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(tp, torso)
	for i in 5:
		a.position_track_insert_key(tp, L * i / 4.0, TORSO_REST + Vector3(0, 0.16 if i % 2 == 1 else 0.0, 0))
	return a


static func _complete(a: Animation) -> void:
	for bone in ["Torso", "Head", "ArmL", "ArmR", "LegL", "LegR"]:
		var path := NodePath("Melly/Skeleton3D:" + bone)
		if a.find_track(path, Animation.TYPE_ROTATION_3D) == -1:
			var t := a.add_track(Animation.TYPE_ROTATION_3D)
			a.track_set_path(t, path)
			a.rotation_track_insert_key(t, 0.0, Quaternion.IDENTITY)
	var torso := NodePath("Melly/Skeleton3D:Torso")
	if a.find_track(torso, Animation.TYPE_POSITION_3D) == -1:
		var tp := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(tp, torso)
		a.position_track_insert_key(tp, 0.0, TORSO_REST)


static func q(x := 0.0, y := 0.0, z := 0.0) -> Quaternion:
	return Quaternion.from_euler(Vector3(x, y, z))


static func _build(spec: Dictionary) -> Animation:
	var a := Animation.new()
	a.length = spec.length
	a.loop_mode = Animation.LOOP_LINEAR if spec.get("loop", true) else Animation.LOOP_NONE
	for bone in spec.rot:
		var tr := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(tr, NodePath("Melly/Skeleton3D:" + bone))
		a.track_set_interpolation_type(tr, Animation.INTERPOLATION_CUBIC)
		for key in spec.rot[bone]:
			a.rotation_track_insert_key(tr, key[0], key[1])
	if spec.has("pos"):
		var tp := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(tp, NodePath("Melly/Skeleton3D:Torso"))
		a.track_set_interpolation_type(tp, Animation.INTERPOLATION_CUBIC)
		for key in spec.pos:
			a.position_track_insert_key(tp, key[0], key[1])
	# Bones the emote doesn't mention go back to rest so blends from other anims don't leak.
	for bone in ["Torso", "Head", "ArmL", "ArmR", "LegL", "LegR"]:
		if not spec.rot.has(bone):
			var t := a.add_track(Animation.TYPE_ROTATION_3D)
			a.track_set_path(t, NodePath("Melly/Skeleton3D:" + bone))
			a.rotation_track_insert_key(t, 0.0, Quaternion.IDENTITY)
	if not spec.has("pos"):
		var t2 := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(t2, NodePath("Melly/Skeleton3D:Torso"))
		a.position_track_insert_key(t2, 0.0, TORSO_REST)
	return a


static func _dance() -> Dictionary:
	var L := 1.2
	return {
		"name": "Dance", "length": L,
		"rot": {
			"Torso": [[0.0, q(0, 0.25, 0)], [L * 0.5, q(0, -0.25, 0)], [L, q(0, 0.25, 0)]],
			"Head": [[0.0, q(0, 0, 0.18)], [L * 0.5, q(0, 0, -0.18)], [L, q(0, 0, 0.18)]],
			"ArmL": [[0.0, q(0, 0, 2.3)], [L * 0.25, q(0, 0, 0.4)], [L * 0.5, q(0, 0, 2.3)], [L * 0.75, q(0, 0, 0.4)], [L, q(0, 0, 2.3)]],
			"ArmR": [[0.0, q(0, 0, -0.4)], [L * 0.25, q(0, 0, -2.3)], [L * 0.5, q(0, 0, -0.4)], [L * 0.75, q(0, 0, -2.3)], [L, q(0, 0, -0.4)]],
			"LegL": [[0.0, q(-0.35, 0, 0)], [L * 0.5, q(0.1, 0, 0)], [L, q(-0.35, 0, 0)]],
			"LegR": [[0.0, q(0.1, 0, 0)], [L * 0.5, q(-0.35, 0, 0)], [L, q(0.1, 0, 0)]],
		},
		"pos": [[0.0, TORSO_REST], [L * 0.25, TORSO_REST + Vector3(0, 0.18, 0)], [L * 0.5, TORSO_REST],
			[L * 0.75, TORSO_REST + Vector3(0, 0.18, 0)], [L, TORSO_REST]],
	}


static func _cheer() -> Dictionary:
	var L := 0.7
	return {
		"name": "Cheer", "length": L,
		"rot": {
			"ArmL": [[0.0, q(0, 0, 2.5)], [L * 0.5, q(0, 0, 2.95)], [L, q(0, 0, 2.5)]],
			"ArmR": [[0.0, q(0, 0, -2.5)], [L * 0.5, q(0, 0, -2.95)], [L, q(0, 0, -2.5)]],
			"Head": [[0.0, q(-0.2, 0, 0)], [L * 0.5, q(-0.35, 0, 0)], [L, q(-0.2, 0, 0)]],
		},
		"pos": [[0.0, TORSO_REST], [L * 0.5, TORSO_REST + Vector3(0, 0.4, 0)], [L, TORSO_REST]],
	}


static func _sit() -> Dictionary:
	var L := 2.0
	var down := Vector3(0, 0.5, 0)
	return {
		"name": "Sit", "length": L,
		"rot": {
			"LegL": [[0.0, q(-1.57, 0, 0.08)], [L, q(-1.57, 0, 0.08)]],
			"LegR": [[0.0, q(-1.57, 0, -0.08)], [L, q(-1.57, 0, -0.08)]],
			"ArmL": [[0.0, q(-0.55, 0, 0.12)], [L, q(-0.55, 0, 0.12)]],
			"ArmR": [[0.0, q(-0.55, 0, -0.12)], [L, q(-0.55, 0, -0.12)]],
			"Head": [[0.0, q(0, 0.15, 0)], [L * 0.5, q(0.05, -0.15, 0)], [L, q(0, 0.15, 0)]],
		},
		"pos": [[0.0, down], [L, down]],
	}


static func _clap() -> Dictionary:
	var L := 0.5
	return {
		"name": "Clap", "length": L,
		"rot": {
			"ArmL": [[0.0, q(-1.3, -0.55, 0)], [L * 0.5, q(-1.3, 0.05, 0)], [L, q(-1.3, -0.55, 0)]],
			"ArmR": [[0.0, q(-1.3, 0.55, 0)], [L * 0.5, q(-1.3, -0.05, 0)], [L, q(-1.3, 0.55, 0)]],
			"Head": [[0.0, q(0.1, 0, 0)], [L * 0.5, q(-0.05, 0, 0)], [L, q(0.1, 0, 0)]],
		},
	}


## Giggle: one hand over the mouth, the other on the belly, a slight bend forward,
## shoulders and head shaking in quick "ha-ha-ha" bursts. For the torso +X bends
## forward (it grows up from its pivot); for arms -X swings them forward.
static func _laugh() -> Dictionary:
	var L := 1.2
	var torso := []
	var head := []
	var arm_l := []
	var arm_r := []
	var steps := 12
	for i in steps + 1:
		var t := L * i / steps
		var ha := 1.0 if i % 2 == 1 else 0.0  # every other key is a "ha"
		var sway := sin(TAU * i / steps)
		torso.append([t, q(0.1 + 0.06 * ha, sway * 0.1, sway * 0.04)])
		head.append([t, q(0.08 + 0.08 * ha, sway * 0.12, 0.18)])
		arm_l.append([t, q(-0.85 - 0.06 * ha, 0, -0.42)])
		arm_r.append([t, q(-1.95 + 0.07 * ha, 0.35, 0.72)])
	return {
		"name": "Laugh", "length": L,
		"rot": {"Torso": torso, "Head": head, "ArmL": arm_l, "ArmR": arm_r},
	}


## A quick right hook (one shot): wind up, twist from the hips, jab forward.
static func _punch() -> Dictionary:
	var L := 0.42
	return {
		"name": "Punch", "length": L, "loop": false,
		"rot": {
			"ArmR": [[0.0, q(0.1, 0, 0)], [L * 0.3, q(0.55, 0.2, -0.25)], [L * 0.55, q(-1.65, -0.15, 0.05)], [L, q(-0.3, 0, 0)]],
			"ArmL": [[0.0, q(-0.4, 0, 0.15)], [L * 0.55, q(-0.9, 0, 0.2)], [L, q(-0.2, 0, 0)]],
			"Torso": [[0.0, q(0, 0, 0)], [L * 0.3, q(0.05, 0.35, 0)], [L * 0.55, q(0.12, -0.45, 0)], [L, q(0, 0, 0)]],
			"Head": [[0.0, q(0, 0, 0)], [L * 0.55, q(0.1, 0.3, 0)], [L, q(0, 0, 0)]],
			"LegL": [[0.0, q(0, 0, 0)], [L * 0.55, q(-0.45, 0, 0)], [L, q(0, 0, 0)]],
			"LegR": [[0.0, q(0, 0, 0)], [L * 0.55, q(0.25, 0, 0)], [L, q(0, 0, 0)]],
		},
	}


## Throwing overarm (one shot): reach back over the shoulder, lean, whip forward.
static func _throw() -> Dictionary:
	var L := 0.55
	return {
		"name": "Throw", "length": L, "loop": false,
		"rot": {
			"ArmR": [[0.0, q(-0.2, 0, 0)], [L * 0.35, q(-2.9, 0, -0.35)], [L * 0.6, q(-1.1, 0, 0.1)], [L, q(-0.2, 0, 0)]],
			"ArmL": [[0.0, q(0, 0, 0)], [L * 0.35, q(-1.2, 0, 0.3)], [L * 0.6, q(-0.3, 0, 0.2)], [L, q(0, 0, 0)]],
			"Torso": [[0.0, q(0, 0, 0)], [L * 0.35, q(-0.18, 0.3, 0)], [L * 0.6, q(0.22, -0.25, 0)], [L, q(0, 0, 0)]],
			"LegL": [[0.0, q(0, 0, 0)], [L * 0.6, q(-0.5, 0, 0)], [L, q(0, 0, 0)]],
			"LegR": [[0.0, q(0, 0, 0)], [L * 0.6, q(0.3, 0, 0)], [L, q(0, 0, 0)]],
		},
	}
