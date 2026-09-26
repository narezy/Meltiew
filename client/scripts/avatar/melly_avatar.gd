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
	"laugh": ["Laugh", 1.0, 0.15],
}
const LAUGH_FACE := "xD"
const EMOTES := ["wave", "dance", "cheer", "sit", "clap", "laugh"]

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
var _hand: Node3D
var _hold: HoldArm
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
	# Looks may have been set before we entered the tree.
	set_colors(_look_colors if not _look_colors.is_empty() else Session.DEFAULT_COLORS)
	var pending: Array = _worn_pending if _worn_pending is Array else []
	_worn_pending = null
	set_accessories(pending)
	play("idle")


func apply_user(u: Dictionary) -> void:
	set_colors(Session.colors_of(u))
	set_accessories(Session.worn_of(u))
	set_face(str(u.get("face", ":D")))


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
	for part in JOINT_ORDER:
		arr.append(Color(str(colors.get(part, Session.DEFAULT_COLORS[part]))))
	if _body_mat:
		_body_mat.set_shader_parameter("part_colors", arr)


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
	return _current in EMOTES or _current.begins_with("anim://")


func _on_anim_finished(anim_name: StringName) -> void:
	if str(anim_name).begins_with("C") and _current.begins_with("anim://"):
		custom_finished.emit()
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
