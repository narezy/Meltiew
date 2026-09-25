class_name GameBubble
extends Node3D
## Chat bubble above a player's head: a white speech bubble with a tail pointing
## down at them. It sits just above the highest point of the character (head or
## accessory), so it follows emotes like sitting down.

const SHADER := preload("res://assets/shaders/chat_bubble.gdshader")
const FONT_SIZE := 38
const PIXEL := 0.0042  # metres per font pixel
const MAX_WIDTH_PX := 620
const PAD := Vector2(0.14, 0.09)
const TAIL := 0.14
const GAP := 0.14  # between the character's top and the tail tip
const SHOW_SEC := 6.0

var _label: Label3D
var _bg: MeshInstance3D
var _quad: QuadMesh
var _mat: ShaderMaterial
var _time := 0.0
## Where to float: the avatar whose top we follow.
var avatar: MellyAvatar


func _init() -> void:
	visible = false
	top_level = true  # placed in world space, not spun with the character
	_quad = QuadMesh.new()
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.render_priority = 10
	_bg = MeshInstance3D.new()
	_bg.mesh = _quad
	_bg.material_override = _mat
	_bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bg)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font = UI.font_bold
	_label.font_size = FONT_SIZE
	_label.pixel_size = PIXEL
	_label.modulate = UI.INK
	_label.outline_size = 0
	_label.no_depth_test = true
	_label.render_priority = 11
	_label.width = MAX_WIDTH_PX
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)


func show_text(text: String) -> void:
	_label.text = text
	# Size the bubble to the wrapped text.
	var px := UI.font_bold.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, MAX_WIDTH_PX, FONT_SIZE, 6,
		TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND)
	var body := Vector2(px.x, px.y) * PIXEL + PAD * 2.0
	body.x = maxf(body.x, 0.32)
	var size := Vector2(body.x, body.y + TAIL)
	_quad.size = size
	_quad.center_offset = Vector3(0, size.y * 0.5, 0)
	_mat.set_shader_parameter("size", size)
	_mat.set_shader_parameter("tail", TAIL)
	_mat.set_shader_parameter("radius", minf(0.12, body.y * 0.5))
	_label.position = Vector3(0, TAIL + body.y * 0.5, 0)
	_time = SHOW_SEC
	visible = true
	scale = Vector3.ONE * 0.6
	var t := create_tween()
	t.tween_property(self, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_follow()


func _process(delta: float) -> void:
	if not visible:
		return
	_time -= delta
	if _time <= 0.0:
		visible = false
		return
	_follow()


func _follow() -> void:
	if avatar and avatar.is_inside_tree() and is_inside_tree():
		global_position = Vector3(avatar.global_position.x, avatar.top_y() + GAP, avatar.global_position.z)
