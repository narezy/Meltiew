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
	"run": ["Walk", 1.3, 0.2],
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
func play(state: String) -> void:
	if anim_player == null or state == _current:
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


func current_state() -> String:
	return _current


func is_emoting() -> bool:
	return _current in EMOTES


func _on_anim_finished(anim_name: StringName) -> void:
	if anim_name == &"Wave":
		_current = ""
		play("idle")
