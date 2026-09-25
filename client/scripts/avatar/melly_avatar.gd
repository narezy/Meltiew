class_name MellyAvatar
extends Node3D
## Melly character: loads the rigged model, paints its six body parts,
## puts a hat on the head bone and drives the animations.

const MODEL := preload("res://assets/melly.glb")
const BODY_SHADER := preload("res://assets/shaders/melly_body.gdshader")
## melly.glb is 5.33 units tall; this makes her ~1.8 m.
const MODEL_SCALE := 0.34
## Shader uniform order follows the skin joints: Torso, Head, ArmL, ArmR, LegL, LegR.
const JOINT_ORDER := ["torso", "head", "arm_l", "arm_r", "leg_l", "leg_r"]

var anim_player: AnimationPlayer
var _model: Node3D
var _body_mat: ShaderMaterial
var _hat_root: BoneAttachment3D
var _hat_id := ""
var _current := ""
var _one_shot := false
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
	anim_player.animation_finished.connect(_on_anim_finished)
	var body: MeshInstance3D = _model.find_child("Body", true, false)
	_body_mat = ShaderMaterial.new()
	_body_mat.shader = BODY_SHADER
	body.set_surface_override_material(0, _body_mat)
	var skeleton: Skeleton3D = _model.find_child("Skeleton3D", true, false)
	_hat_root = BoneAttachment3D.new()
	_hat_root.bone_name = "Head"
	skeleton.add_child(_hat_root)
	set_colors(Session.DEFAULT_COLORS)
	play("idle")


func apply_user(u: Dictionary) -> void:
	set_colors(Session.colors_of(u))
	set_hat(str(u.get("hat", "none")))


func set_colors(colors: Dictionary) -> void:
	_look_colors = colors.duplicate()
	var arr := PackedColorArray()
	for part in JOINT_ORDER:
		arr.append(Color(str(colors.get(part, Session.DEFAULT_COLORS[part]))))
	if _body_mat:
		_body_mat.set_shader_parameter("part_colors", arr)


func set_hat(id: String) -> void:
	if id == _hat_id or _hat_root == null:
		return
	_hat_id = id
	for c in _hat_root.get_children():
		c.queue_free()
	var hat := Hats.build(id)
	if hat:
		_hat_root.add_child(hat)


## Accepts network animation names: idle, walk, run, jump, fall, wave.
func play(state: String) -> void:
	if _one_shot and state == "idle":
		return
	if state == _current and state != "wave":
		return
	_current = state
	_one_shot = false
	match state:
		"walk":
			anim_player.play("Walk", 0.15, 1.0)
		"run":
			anim_player.play("Walk", 0.15, 1.55)
		"jump":
			anim_player.play("Jump", 0.08, 1.0)
		"fall":
			anim_player.play("Jump", 0.15, 1.0)
			anim_player.seek(0.3, true)
			anim_player.pause()
		"wave":
			_one_shot = true
			anim_player.play("Wave", 0.12, 1.0)
		_:
			_current = "idle"
			anim_player.play("Idle", 0.2, 1.0)


func is_waving() -> bool:
	return _one_shot and _current == "wave"


func _on_anim_finished(anim_name: StringName) -> void:
	if anim_name == &"Wave":
		_one_shot = false
		_current = ""
		play("idle")
