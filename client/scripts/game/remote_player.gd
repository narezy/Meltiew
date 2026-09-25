class_name RemotePlayer
extends Node3D
## Another player's Melly, smoothly interpolated between network snapshots.

var user: Dictionary = {}
var avatar: MellyAvatar
var _target_pos := Vector3.ZERO
var _target_yaw := 0.0
var _anim := "idle"
var _name_tag: Label3D
var _bubble: Label3D
var _bubble_time := 0.0
var _has_state := false


func _ready() -> void:
	avatar = MellyAvatar.new()
	add_child(avatar)
	avatar.apply_user(user)
	_name_tag = Label3D.new()
	_name_tag.position.y = 2.35
	_name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_tag.font = UI.font_bold
	_name_tag.font_size = 44
	_name_tag.outline_size = 14
	_name_tag.outline_modulate = Color(0.08, 0.07, 0.1, 0.9)
	_name_tag.pixel_size = 0.0048
	_name_tag.no_depth_test = false
	_name_tag.fixed_size = false
	add_child(_name_tag)
	_bubble = Label3D.new()
	_bubble.position.y = 2.85
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.font = UI.font_bold
	_bubble.font_size = 40
	# A thick white outline doubles as a sticker-style speech bubble.
	_bubble.outline_size = 30
	_bubble.outline_modulate = Color(1, 1, 1, 0.96)
	_bubble.modulate = UI.INK
	_bubble.pixel_size = 0.0045
	_bubble.width = 900
	_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble.visible = false
	add_child(_bubble)
	refresh_look()


func refresh_look() -> void:
	if avatar:
		avatar.apply_user(user)
	if _name_tag:
		_name_tag.text = str(user.get("display_name", "?"))


func set_state(p: Vector3, yaw: float, anim: String) -> void:
	_target_pos = p
	_target_yaw = yaw
	_anim = anim
	if not _has_state:
		_has_state = true
		global_position = p
		avatar.rotation.y = yaw


func show_bubble(text: String) -> void:
	_bubble.text = text
	_bubble.visible = true
	_bubble_time = 6.0


func _process(delta: float) -> void:
	var k := minf(delta * 12.0, 1.0)
	if global_position.distance_to(_target_pos) > 12.0:
		global_position = _target_pos
	else:
		global_position = global_position.lerp(_target_pos, k)
	avatar.rotation.y = lerp_angle(avatar.rotation.y, _target_yaw, k)
	if _anim == "wave":
		if not avatar.is_waving():
			avatar.play("wave")
	else:
		avatar.play(_anim)
	if _bubble_time > 0.0:
		_bubble_time -= delta
		if _bubble_time <= 0.0:
			_bubble.visible = false
