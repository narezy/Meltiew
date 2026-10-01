class_name RemotePlayer
extends Node3D
## Another player's Melly, rendered ~120 ms in the past and interpolated
## between network snapshots for smooth motion.

const DELAY_MS := 120.0

var user: Dictionary = {}
var avatar: MellyAvatar
## What they are doing now ("hug": waiting for a hug).
var current_anim := ""
var _snaps: Array = []  # [local_ms, pos, yaw, anim]
var _name_tag: Label3D
var _role_tag: Label3D
var _bubble: GameBubble
var _talk: Sprite3D
var _dead := false
## When this player died (ms). Snapshots are played a little late, so older ones
## (still alive) must not bring them back and then kill them a second time.
var _dead_at := 0


func _ready() -> void:
	# Moved every frame from buffered snapshots, not by physics.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	avatar = MellyAvatar.new()
	add_child(avatar)
	avatar.apply_user(user)
	_name_tag = Label3D.new()
	_name_tag.position.y = 2.3
	_name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_tag.font = UI.font_bold
	_name_tag.font_size = 40
	_name_tag.outline_size = 12
	_name_tag.outline_modulate = Color(0.08, 0.07, 0.1, 0.85)
	_name_tag.pixel_size = 0.0045
	add_child(_name_tag)
	_role_tag = Label3D.new()
	_role_tag.position.y = 2.52
	_role_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_role_tag.font = UI.font_black
	_role_tag.font_size = 28
	_role_tag.outline_size = 10
	_role_tag.outline_modulate = Color(0.08, 0.07, 0.1, 0.85)
	_role_tag.pixel_size = 0.0045
	add_child(_role_tag)
	_bubble = GameBubble.new()
	_bubble.avatar = avatar
	add_child(_bubble)
	refresh_look()


func refresh_look() -> void:
	if avatar:
		avatar.apply_user(user)
	if _name_tag:
		_name_tag.text = str(user.get("display_name", "?"))
	if _role_tag:
		var role := str(user.get("role", "user"))
		_role_tag.visible = role == "owner" or role == "admin"
		_role_tag.text = L.t("role_" + role) if _role_tag.visible else ""
		_role_tag.modulate = Color("#ffd166") if role == "owner" else UI.MINT


func set_state(p: Vector3, yaw: float, anim: String, hands: Variant = null) -> void:
	var now := Time.get_ticks_msec()
	if _snaps.is_empty():
		global_position = p
		avatar.rotation.y = yaw
	_snaps.append([now, p, yaw, anim, _hands_of(hands)])
	while _snaps.size() > 30:
		_snaps.pop_front()


## Radio waves over their name while they talk in voice chat.
## A VR player's hands from the server ([lx, ly, lz, rx, ry, rz], avatar space): two
## Vector3 or nulls.
static func _hands_of(h: Variant) -> Array:
	var out := [null, null]
	if h is Array and h.size() >= 6:
		for i in 2:
			if h[i * 3] != null and h[i * 3 + 1] != null and h[i * 3 + 2] != null:
				out[i] = Vector3(float(h[i * 3]), float(h[i * 3 + 1]), float(h[i * 3 + 2]))
	return out


## Radio waves over their name while they talk in voice chat.
func set_talking(on: bool) -> void:
	if on and _talk == null:
		_talk = Sprite3D.new()
		_talk.texture = Voice.wave_texture()
		_talk.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_talk.pixel_size = 0.006
		_talk.no_depth_test = true
		_talk.position.y = 2.8
		_talk.modulate = UI.MINT
		add_child(_talk)
	if _talk:
		_talk.visible = on


func show_bubble(text: String) -> void:
	_bubble.show_text(text)


func shatter() -> void:
	if _dead:
		return
	_dead = true
	_dead_at = Time.get_ticks_msec()
	Ragdoll.spawn(get_parent(), avatar.global_transform, avatar.get_colors())
	avatar.visible = false
	_name_tag.visible = false
	_role_tag.visible = false


func _process(delta: float) -> void:
	if _talk and _talk.visible:
		_talk.scale = Vector3.ONE * (1.0 + 0.12 * sin(Time.get_ticks_msec() / 90.0))
	# Name tags ride on the head (lower when sitting) and step aside for a chat bubble.
	var top := avatar.top_y() - global_position.y
	_name_tag.position.y = top + 0.3
	_role_tag.position.y = top + 0.52
	var talking := _bubble.visible
	_name_tag.transparency = 1.0 if talking else 0.0
	_role_tag.transparency = 1.0 if talking else 0.0
	if not _snaps.is_empty():
		var render_t := Time.get_ticks_msec() - DELAY_MS
		# Drop snapshots we have fully passed, keeping one before render time.
		while _snaps.size() >= 2 and _snaps[1][0] <= render_t:
			_snaps.pop_front()
		var a: Array = _snaps[0]
		var pos: Vector3 = a[1]
		var yaw: float = a[2]
		var hands: Array = (a[4] as Array).duplicate()
		if _snaps.size() >= 2 and render_t > a[0]:
			var b: Array = _snaps[1]
			var k := clampf((render_t - a[0]) / maxf(b[0] - a[0], 1.0), 0.0, 1.0)
			pos = (a[1] as Vector3).lerp(b[1], k)
			yaw = lerp_angle(a[2], b[2], k)
			for i in 2:
				if hands[i] is Vector3 and b[4][i] is Vector3:
					hands[i] = (hands[i] as Vector3).lerp(b[4][i], k)
		avatar.set_vr_hands(hands[0], hands[1])
		global_position = pos
		avatar.rotation.y = lerp_angle(avatar.rotation.y, yaw, minf(delta * 16.0, 1.0))
		var anim: String = a[3]
		current_anim = anim
		if anim == "dead":
			shatter()
		elif not _dead or a[0] > _dead_at:
			if _dead:
				_dead = false
				avatar.visible = true
				_name_tag.visible = true
				refresh_look()
			avatar.play(anim)
