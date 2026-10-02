class_name MellyAvatar
extends Node3D
## Melly character: loads the rigged model, paints its six body parts,
## puts a hat on the head bone and drives the animations and emotes.

const MODEL := preload("res://assets/melly.glb")
const BODY_SHADER := preload("res://assets/shaders/melly_body.gdshader")
## melly.glb is 5.33 units tall; this makes her ~1.8 m.
const MODEL_SCALE := 0.34
## Shader uniform order follows the skin joints: Torso, Head, ArmL, ArmR, LegL, LegR.
const JOINT_ORDER := ["torso", "head", "arm_l", "arm_r", "leg_l", "leg_r"]
## Network animation state -> [clip, speed, blend].
const CLIPS := {
	"idle": ["Idle", 1.0, 0.25],
	"walk": ["Walk", 0.85, 0.2],
	"run": ["Run", 1.3, 0.2],
	"climb": ["Climb", 1.0, 0.15],
	"jump": ["Jump", 1.0, 0.1],
	"wave": ["Wave", 1.0, 0.15],
	"dance": ["Dance", 1.0, 0.2],
	"cheer": ["Cheer", 1.0, 0.15],
	"sit": ["Sit", 1.0, 0.3],
	"clap": ["Clap", 1.0, 0.15],
	"hug": ["HugWait", 1.0, 0.25],
	"hugging": ["Hug", 1.0, 0.1],
	"laugh": ["Laugh", 1.0, 0.15],
	"punch": ["Punch", 1.0, 0.06],
	"throw": ["Throw", 1.0, 0.06],
}
const LAUGH_FACE := "xD"
## "clap" left the wheel for "hug", but older apps still send it: it still plays.
const EMOTES := ["wave", "dance", "cheer", "sit", "clap", "laugh", "hug"]
## One-shot moves (not looping); Melly goes back to idle after.
const ACTIONS := ["punch", "throw", "hugging"]

var anim_player: AnimationPlayer
var _model: Node3D
var _body_mat: ShaderMaterial
var _hat_root: BoneAttachment3D
var _torso_root: BoneAttachment3D
var _worn: Array = []
var _worn_pending: Variant = null
var _worn_built_version := -1
var _head_top_above_bone := 0.35
## Rest-pose height of the top of Melly's head (metres, avatar space).
const HEAD_TOP := 1.81
var _skeleton: Skeleton3D
var _vr: VRPose
var _hidden := {}  # bone names scripts hid
var _leg_scale := {}  # "LegL" / "LegR" -> height scale scripts set
var _rep_nodes := {}  # bone -> BoneAttachment3D holding a script's object for that part
var _rep_info := {}  # bone -> {box: AABB, face, accessories}
const PART_CLOTH_SHADER := preload("res://assets/shaders/body_part_cloth.gdshader")
## Middle of each part from its bone, in the model (bone space, rest pose).
const PART_CENTERS := {"Head": Vector3(0, 0.66, 0), "Torso": Vector3(0, 1.0, 0), "ArmL": Vector3(0.21, -1.0, 0),
	"ArmR": Vector3(-0.21, -1.0, 0), "LegL": Vector3(-0.07, -1.0, 0), "LegR": Vector3(0.07, -1.0, 0)}
var _hip := 0.0  # studs the hips moved (short or hidden legs)
## The skeleton's bones in JOINT_ORDER (head, torso, arms, legs as the colors go).
const BONES := ["Torso", "Head", "ArmL", "ArmR", "LegL", "LegR"]
const LEG_LENGTH := 2.0 * MODEL_SCALE  # studs, hip to foot
var _hand: Node3D
var _hold: HoldArm
var _joints: JointPose
## Humanoid / Rig properties -> the bones they turn.
const JOINT_PROPS := {"HeadAngle": "Head", "TorsoAngle": "Torso", "LeftArmAngle": "ArmL", "RightArmAngle": "ArmR", "LeftLegAngle": "LegL", "RightLegAngle": "LegR"}
## True while a Tool is in her right hand: the arm points forward to hold it.
var holding := false:
	set(v):
		holding = v
		if _hold:
			_hold.target = 1.0 if v else 0.0
var _face_mat: StandardMaterial3D
var _face_id := ":D"
var _current := ""
var _look_colors := {}
var _clothes: Array = []  # catalog ids, bottom to top
var _cloth_tex := {}  # id -> Texture2D, as they load
var _extra_cloth: Array = []  # textures on top (studio preview, a place's Clothing)


func _ready() -> void:
	_model = MODEL.instantiate()
	# glTF faces +Z, Godot's forward is -Z.
	_model.rotation.y = PI
	_model.scale = Vector3.ONE * MODEL_SCALE
	add_child(_model)
	anim_player = _model.find_child("AnimationPlayer", true, false)
	for anim_name in ["Idle", "Walk"]:
		if anim_player.has_animation(anim_name):
			anim_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	EmoteAnims.install(anim_player)
	anim_player.animation_finished.connect(_on_anim_finished)
	var body: MeshInstance3D = _model.find_child("Body", true, false)
	# The rest pose baked in, so clothing pictures land on the right spots (ClothingLayout).
	body.mesh = ClothingLayout.dressable(body.mesh)
	_body_mat = ShaderMaterial.new()
	_body_mat.shader = BODY_SHADER
	body.set_surface_override_material(0, _body_mat)
	# Face lives on its own surface; swap its texture for the chosen kaomoji.
	if body.mesh.get_surface_count() > 1:
		var orig := body.mesh.surface_get_material(1) as StandardMaterial3D
		_face_mat = orig.duplicate() if orig else StandardMaterial3D.new()
		_face_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		_face_mat.alpha_scissor_threshold = 0.4
		_face_mat.vertex_color_use_as_albedo = false
		body.set_surface_override_material(1, _face_mat)
		_apply_face()
	var skeleton: Skeleton3D = _model.find_child("Skeleton3D", true, false)
	_hat_root = BoneAttachment3D.new()
	_hat_root.bone_name = "Head"
	skeleton.add_child(_hat_root)
	# Top of the head measured from the head bone in the rest pose, in avatar space.
	var head := skeleton.find_bone("Head")
	if head >= 0:
		_head_top_above_bone = HEAD_TOP - (_model.transform * skeleton.get_bone_global_rest(head).origin).y
	_torso_root = BoneAttachment3D.new()
	_torso_root.bone_name = "Torso"
	skeleton.add_child(_torso_root)
	_skeleton = skeleton
	_hold = HoldArm.new()
	_hold.bone = skeleton.find_bone("ArmR")
	_hold.target = 1.0 if holding else 0.0
	skeleton.add_child(_hold)
	# Scripts turning joints (Humanoid / Rig *Angle properties), on top of the animation.
	_joints = JointPose.new()
	_joints.avatar = self
	skeleton.add_child(_joints)
	# VR: the arms reach for the hands (last, over everything else).
	_vr = VRPose.new()
	_vr.avatar = self
	_vr.arms = {"left": skeleton.find_bone("ArmL"), "right": skeleton.find_bone("ArmR")}
	_vr.head = skeleton.find_bone("Head")
	skeleton.add_child(_vr)
	# Looks may have been set before we entered the tree.
	set_colors(_look_colors if not _look_colors.is_empty() else Session.DEFAULT_COLORS)
	var pending: Array = _worn_pending if _worn_pending is Array else []
	_worn_pending = null
	set_accessories(pending)
	_paint_clothes()
	play("idle")


func apply_user(u: Dictionary) -> void:
	set_colors(Session.colors_of(u))
	set_accessories(Session.worn_of(u))
	set_face(str(u.get("face", ":D")))
	var c: Variant = u.get("clothes", [])
	set_clothes(c if c is Array else [])


## Clothing from the catalog, bottom to top (ids). Pictures load in the background;
## one that can't be had (taken down) is simply left out.
func set_clothes(ids: Array) -> void:
	_clothes = []
	for id in ids.slice(0, ClothingLayout.DRESSED.size()):
		_clothes.append(int(id))
	var want := _clothes.duplicate()
	_cloth_tex = {}
	for id in want:
		AssetCache.fetch(ClothingLayout.image_ref(id), func(tex: Texture2D):
			if _clothes != want:
				return  # changed again meanwhile
			_cloth_tex[id] = tex
			_paint_clothes())
	_paint_clothes()


func get_clothes() -> Array:
	return _clothes.duplicate()


## More layers on top of the catalog ones: a picture being made in the studio, or a
## place's Clothing on a character or a rig.
func set_extra_clothes(textures: Array) -> void:
	_extra_cloth = textures.filter(func(t): return t is Texture2D)
	_paint_clothes()


func _paint_clothes() -> void:
	if _body_mat == null:
		return
	var layers: Array = []
	for id in _clothes:
		if _cloth_tex.get(id) is Texture2D:
			layers.append(_cloth_tex[id])
	layers.append_array(_extra_cloth)
	layers = layers.slice(maxi(0, layers.size() - 5))
	for i in 5:
		_body_mat.set_shader_parameter("cloth%d" % i, layers[i] if i < layers.size() else null)
	_body_mat.set_shader_parameter("cloth_count", layers.size())
	# Swapped parts that keep the shirt wear the same layers.
	for bone in _rep_nodes:
		for mi in (_rep_nodes[bone] as Node).find_children("*", "MeshInstance3D", true, false):
			if mi.has_meta("cloth"):
				var m := (mi as MeshInstance3D).material_override as ShaderMaterial
				for i in 5:
					m.set_shader_parameter("cloth%d" % i, layers[i] if i < layers.size() else null)
				m.set_shader_parameter("cloth_count", layers.size())


func set_face(id: String) -> void:
	_face_id = id
	_apply_face()


func get_face() -> String:
	return _face_id


func _apply_face() -> void:
	if _face_mat:
		# Laughing borrows a laughing face; the chosen one comes back after.
		_face_mat.albedo_texture = Faces.texture(LAUGH_FACE if _current == "laugh" else _face_id)


func set_colors(colors: Dictionary) -> void:
	_look_colors = colors.duplicate()
	var arr := PackedColorArray()
	for i in JOINT_ORDER.size():
		var part: String = JOINT_ORDER[i]
		var c := Color(str(colors.get(part, Session.DEFAULT_COLORS[part])))
		c.a = 0.0 if _hidden.has(BONES[i]) or _rep_info.has(BONES[i]) else 1.0  # (the shader leaves hidden parts out)
		arr.append(c)
	if _body_mat:
		_body_mat.set_shader_parameter("part_colors", arr)


## Middle of the head in world space; follows animations and emotes.
func head_center() -> Vector3:
	if _hat_root == null:
		return global_position + Vector3.UP * (HEAD_TOP - 0.35) * scale.y
	return _hat_root.global_position + _hat_root.global_basis.y.normalized() * _head_top_above_bone * 0.5 * global_basis.get_scale().y


## World height of the highest point of the character right now: the top of the head
## (it follows emotes like sitting) or whatever is worn higher up.
func top_y() -> float:
	if _hat_root == null:
		return global_position.y + HEAD_TOP * scale.y
	var top := _hat_root.global_position.y + _head_top_above_bone * global_basis.get_scale().y
	for n in _hat_root.find_children("*", "MeshInstance3D", true, false) + _torso_root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.visible:
			top = maxf(top, (mi.global_transform * mi.get_aabb()).end.y)
	return top


## Where a held Tool's Handle goes: the right palm. Its axes match the character when
## the arm points forward (-Z forward, +Y up), so tools keep the look they were built with.
func hand_r() -> Node3D:
	if _hand == null and _skeleton:
		var att := BoneAttachment3D.new()
		att.bone_name = "ArmR"
		_skeleton.add_child(att)
		_hand = Node3D.new()
		# melly.glb units, bone space: the palm sits near the end of the arm.
		_hand.transform = Transform3D(Basis(Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)), Vector3(-0.21, -1.78, 0.0))
		att.add_child(_hand)
	return _hand


func get_colors() -> Dictionary:
	return _look_colors


## Everything worn at once (hats, ears, a tail...), from the accessory catalog.
func set_accessories(ids: Array) -> void:
	if _hat_root == null:
		_worn_pending = ids.duplicate()
		return
	if ids == _worn and _worn_built_version == Accessories.version:
		return
	_worn = ids.duplicate()
	_worn_built_version = Accessories.version
	for root in [_hat_root, _torso_root]:
		for c in root.get_children():
			c.queue_free()
	for id in ids:
		var node := Accessories.build(str(id))
		if node:
			(_torso_root if Accessories.bone_of(str(id)) == "Torso" else _hat_root).add_child(node)
	_apply_head_extras()


func get_accessories() -> Array:
	return _worn.duplicate() if _worn_pending == null else (_worn_pending as Array).duplicate()


## One hat only (older code paths).
func set_hat(id: String) -> void:
	set_accessories([] if id == "none" or id == "" else [id])


## Accepts network animation states: idle, walk, run, jump, fall, wave and the emotes.
## A custom animation (anim://<id>) that stopped by itself (not looped).
signal custom_finished


func play(state: String) -> void:
	if anim_player == null or state == _current:
		return
	if state.begins_with("anim://"):
		_play_custom(state)
		return
	# A one-shot wave keeps playing over "idle" until it finishes.
	if _current == "wave" and state == "idle" and anim_player.is_playing():
		return
	var was := _current
	_current = state
	if was == "laugh" or state == "laugh":
		_apply_face()
	if state == "fall":
		anim_player.play("Jump", 0.2, 1.0)
		anim_player.seek(0.32, true)
		anim_player.pause()
		return
	var clip: Array = CLIPS.get(state, CLIPS.idle)
	anim_player.play(clip[0], clip[2], clip[1])


## Plays `state` from its start even if it's already playing (Rigs told to again).
func restart(state: String) -> void:
	_current = ""
	play(state)


## Animations made in the animator: loaded on first use, then kept in the shared library.
func _play_custom(ref: String) -> void:
	var was := _current
	_current = ref
	if was == "laugh":
		_apply_face()
	var clip := "C%d" % CustomAnims.id_of(ref)
	var lib: AnimationLibrary = anim_player.get_animation_library(&"")
	if lib.has_animation(clip):
		anim_player.play(clip, 0.2)
		return
	CustomAnims.fetch(ref, func(a: Animation):
		if a == null or not is_instance_valid(self) or _current != ref:
			return
		if not lib.has_animation(clip):
			lib.add_animation(clip, a)
		anim_player.play(clip, 0.2))


## The animator's preview: shows `a` posed at `time` (or playing, if `playing`).
func preview(a: Animation, time: float, playing := false) -> void:
	var lib: AnimationLibrary = anim_player.get_animation_library(&"")
	if lib.has_animation(&"Preview"):
		lib.remove_animation(&"Preview")
	lib.add_animation(&"Preview", a)
	_current = "preview"
	anim_player.play(&"Preview", 0.0)
	anim_player.seek(time, true)
	if not playing:
		anim_player.pause()


func current_state() -> String:
	return _current


func is_emoting() -> bool:
	return _current in EMOTES or _current in ACTIONS or _current.begins_with("anim://")


func _on_anim_finished(anim_name: StringName) -> void:
	if str(anim_name).begins_with("C") and _current.begins_with("anim://"):
		custom_finished.emit()
	if anim_name == &"Punch" or anim_name == &"Throw" or anim_name == &"Hug":
		_current = ""
		custom_finished.emit()
		play("idle")
	if anim_name == &"Wave":
		_current = ""
		play("idle")


## Raises the right arm forward over whatever animation plays, blending in and out.
class HoldArm extends SkeletonModifier3D:
	const POSE := Vector3(-1.5, 0.0, 0.0)
	var bone := -1
	var target := 0.0
	var _amount := 0.0

	func _process_modification_with_delta(delta: float) -> void:
		_amount = move_toward(_amount, target, delta * 7.0)
		if _amount <= 0.0 or bone < 0:
			return
		var sk := get_skeleton()
		var pose := sk.get_bone_pose_rotation(bone)
		sk.set_bone_pose_rotation(bone, pose.slerp(Quaternion.from_euler(POSE), _amount))


## Extra turns on the joints from scripts: { "ArmL": Vector3 degrees, ... }. Added on
## top of whatever animation plays; zero (or missing) leaves a joint alone.
func set_joint_angles(angles: Dictionary) -> void:
	if _joints == null:
		return
	var out := {}
	for bone_name in angles:
		var v: Variant = angles[bone_name]
		if v is Vector3 and v != Vector3.ZERO:
			var b := _skeleton.find_bone(bone_name)
			if b >= 0:
				out[b] = Quaternion.from_euler(v * (PI / 180.0))
	_joints.turns = out


## VR: where this player's hands are, in the avatar's space (studs from the feet, facing
## -Z), or null for a hand that isn't tracked. The arms swing at the shoulders to point at
## them (they don't stretch). From the local headset, or from the server for others.
func set_vr_hands(left: Variant, right: Variant) -> void:
	if _vr:
		_vr.targets = {"left": left, "right": right}


## The player's own avatar in VR: no head in front of the eyes (the hat goes with it).
func set_head_hidden(hidden: bool) -> void:
	if _vr:
		_vr.hide_head = hidden


class VRPose extends SkeletonModifier3D:
	const ARM_LENGTH := 2.0  # shoulder to hand in the model (skeleton space)
	var avatar: Node3D
	var arms := {}  # side -> bone index
	var head := -1
	var targets := {}  # side -> Vector3 (avatar space) or null
	var hide_head := false
	var _amount := {"left": 0.0, "right": 0.0}

	func _process_modification_with_delta(delta: float) -> void:
		var sk := get_skeleton()
		if hide_head and head >= 0:
			sk.set_bone_pose_scale(head, Vector3.ONE * 0.001)
		var to_sk := sk.global_transform.affine_inverse() * avatar.global_transform
		for side in arms:
			var b: int = arms[side]
			var t: Variant = targets.get(side)
			# Eased in and out, so a hand that comes and goes doesn't snap the arm.
			_amount[side] = move_toward(_amount[side], 1.0 if t is Vector3 else 0.0, delta * 6.0)
			if b < 0 or _amount[side] <= 0.0:
				continue
			if t is Vector3:
				_last[side] = t
			var pose := sk.get_bone_global_pose(b)
			var want: Vector3 = to_sk * (_last[side] as Vector3) - pose.origin
			if want.length() < 0.01:
				continue
			# The arm hangs down in the rest pose: that's where it points from the shoulder.
			var local := sk.get_bone_global_rest(b).basis.inverse() * Vector3.DOWN
			var along := (pose.basis * local).normalized()
			var turn := Quaternion(along, want.normalized())
			var aimed := Basis(Quaternion.IDENTITY.slerp(turn, _amount[side])) * pose.basis.orthonormalized()
			# And it stretches (a little) so the hand is where the controller is.
			var reach := clampf(want.length() / ARM_LENGTH, 0.6, 1.6)
			var stretch := lerpf(1.0, reach, _amount[side])
			var axis := local.abs()
			var scale := Vector3.ONE
			if axis.x >= axis.y and axis.x >= axis.z:
				scale.x = stretch
			elif axis.y >= axis.z:
				scale.y = stretch
			else:
				scale.z = stretch
			sk.set_bone_global_pose(b, Transform3D(aimed * Basis.from_scale(scale), pose.origin))

	var _last := {"left": Vector3.ZERO, "right": Vector3.ZERO}


## Scripts reshaping the body (Humanoid / Rig *Scale, *Offset, *Visible): { "Head": {scale:
## Vector3, offset: Vector3 (studs), visible: bool}, ... } for the parts that differ.
## With both legs hidden (or shrunk) the body comes down so it stands on what's left.
func set_part_shapes(shapes: Dictionary) -> void:
	if _joints == null:
		return
	var scales := {}
	var offsets := {}
	var hidden := {}
	for bone_name in shapes:
		var b := _skeleton.find_bone(bone_name)
		if b < 0:
			continue
		var sh: Dictionary = shapes[bone_name]
		if sh.get("scale", Vector3.ONE) != Vector3.ONE:
			scales[b] = (sh.scale as Vector3).max(Vector3.ONE * 0.01)
		if sh.get("offset", Vector3.ZERO) != Vector3.ZERO:
			offsets[b] = sh.offset
		if sh.get("visible", true) == false:
			hidden[bone_name] = true
	_joints.scales = scales
	_joints.offsets = offsets
	if hidden != _hidden:
		_hidden = hidden
		set_colors(_look_colors if not _look_colors.is_empty() else Session.DEFAULT_COLORS)
	for side in ["LegL", "LegR"]:
		_leg_scale[side] = (shapes.get(side, {}).get("scale", Vector3.ONE) as Vector3).y
	_apply_head_extras()
	_update_hip()


## How far the hips moved from the usual (studs): negative with short or hidden legs.
func hip_shift() -> float:
	return _hip


## Body parts a script swapped for its own objects (Humanoid / Rig *Part): { bone: {node:
## Node3D (studs, centered, facing -Z), face, accessories, clothing: bool} }. The part itself
## isn't drawn; the object takes its place and moves with it. A new head can keep the face
## and the hats, the other parts the shirt.
func set_part_replacements(reps: Dictionary) -> void:
	for bone in _rep_nodes:
		if is_instance_valid(_rep_nodes[bone]):
			_rep_nodes[bone].queue_free()
	_rep_nodes.clear()
	_rep_info = {}
	if _skeleton == null:
		return
	for bone in reps:
		var r: Dictionary = reps[bone]
		var node: Node3D = r.get("node")
		if node == null:
			continue
		var att := BoneAttachment3D.new()
		att.bone_name = bone
		_skeleton.add_child(att)
		# Studs and the avatar's facing inside the scaled, turned-around model.
		var holder := Node3D.new()
		holder.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE / MODEL_SCALE), PART_CENTERS.get(bone, Vector3.ZERO))
		att.add_child(holder)
		holder.add_child(node)
		_rep_nodes[bone] = att
		var box := _box_of(node)
		_rep_info[bone] = {"box": box, "face": r.get("face", false), "accessories": r.get("accessories", false)}
		if bone == "Head" and r.get("face", false):
			_face_on(node, box)
		if bone != "Head" and r.get("clothing", false):
			_cloth_on(node, box, BONES.find(bone))
	set_colors(_look_colors if not _look_colors.is_empty() else Session.DEFAULT_COLORS)
	_apply_head_extras()
	_update_hip()


## What a swapped head keeps: the face drawn on the object (the body's own face hides with
## the head) and the hats moved up to its top, or neither.
func _apply_head_extras() -> void:
	var head: Dictionary = _rep_info.get("Head", {})
	if _face_mat:
		_face_mat.albedo_color.a = 0.0 if not head.is_empty() or _hidden.has("Head") else 1.0
	if _hat_root:
		_hat_root.visible = not _hidden.has("Head") and (head.is_empty() or head.accessories)
		# Up to the new head's top (in the bone's own units).
		var lift := 0.0
		if not head.is_empty():
			lift = (PART_CENTERS.Head.y + (head.box as AABB).end.y / MODEL_SCALE) - 2.0 * PART_CENTERS.Head.y
		for c in _hat_root.get_children():
			if not c.has_meta("base_y"):
				c.set_meta("base_y", c.position.y)
			c.position.y = float(c.get_meta("base_y")) + lift


## Where the shown parts' boxes are, in the object's own space.
static func _box_of(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in [node] + node.find_children("*", "MeshInstance3D", true, false):
		if not mi is MeshInstance3D or (mi as MeshInstance3D).mesh == null:
			continue
		var b: AABB = (node.global_transform.affine_inverse() * (mi as MeshInstance3D).global_transform) * (mi as MeshInstance3D).mesh.get_aabb() \
			if node.is_inside_tree() else (mi as MeshInstance3D).transform * (mi as MeshInstance3D).mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _face_on(node: Node3D, box: AABB) -> void:
	var quad := MeshInstance3D.new()
	var q := QuadMesh.new()
	var side := minf(box.size.x, box.size.y) * 0.75
	q.size = Vector2(side, side)
	quad.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_texture = Faces.texture(_face_id)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.4
	quad.material_override = m
	# On the front (-Z), just off it, facing out.
	quad.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(box.get_center().x, box.get_center().y, box.position.z - 0.01))
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(quad)


func _cloth_on(node: Node3D, box: AABB, part: int) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var src := (mi as MeshInstance3D).material_override as StandardMaterial3D
		var m := ShaderMaterial.new()
		m.shader = PART_CLOTH_SHADER
		m.set_shader_parameter("base_color", src.albedo_color if src else Color.WHITE)
		m.set_shader_parameter("part", part)
		m.set_shader_parameter("obj_min", box.position)
		m.set_shader_parameter("obj_size", box.size.max(Vector3.ONE * 0.01))
		m.set_shader_parameter("to_object", Projection((mi as MeshInstance3D).transform))
		(mi as MeshInstance3D).material_override = m
		(mi as MeshInstance3D).set_meta("cloth", true)
	_paint_clothes()


## The feet on the ground: shorter legs (or none) bring the whole body down; swapped
## legs as long as the objects are.
func _update_hip() -> void:
	var legs := []
	for side in ["LegL", "LegR"]:
		if _rep_info.has(side):
			legs.append((_rep_info[side].box as AABB).size.y / LEG_LENGTH)
		elif not _hidden.has(side):
			legs.append(_leg_scale.get(side, 1.0))
	_hip = (legs.max() - 1.0) * LEG_LENGTH if not legs.is_empty() else -LEG_LENGTH
	if _model:
		_model.position.y = _hip


class JointPose extends SkeletonModifier3D:
	var turns := {}  # bone index -> Quaternion
	var scales := {}  # bone index -> Vector3
	var offsets := {}  # bone index -> Vector3, avatar space (studs)
	var avatar: Node3D

	func _process_modification_with_delta(_delta: float) -> void:
		if turns.is_empty() and scales.is_empty() and offsets.is_empty():
			return
		var sk := get_skeleton()
		for b in turns:
			sk.set_bone_pose_rotation(b, sk.get_bone_pose_rotation(b) * turns[b])
		if not scales.is_empty():
			# Each part keeps its own size: what hangs on a bigger torso moves out with it
			# but isn't made bigger too.
			for b in sk.get_bone_count():
				var own: Vector3 = scales.get(b, Vector3.ONE)
				var parent := sk.get_bone_parent(b)
				var inherited: Vector3 = scales.get(parent, Vector3.ONE) if parent >= 0 else Vector3.ONE
				if own != Vector3.ONE or inherited != Vector3.ONE:
					sk.set_bone_pose_scale(b, sk.get_bone_pose_scale(b) * own / inherited)
		if not offsets.is_empty() and avatar:
			var to_sk := (sk.global_transform.affine_inverse() * avatar.global_transform).basis
			for b in offsets:
				var g := sk.get_bone_global_pose(b)
				g.origin += to_sk * (offsets[b] as Vector3)
				sk.set_bone_global_pose(b, g)
