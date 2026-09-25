class_name RemotePlayer
extends Node3D
## Another player's Melly, rendered ~120 ms in the past and interpolated
## between network snapshots for smooth motion.

const DELAY_MS := 120.0

var user: Dictionary = {}
var avatar: MellyAvatar
var _snaps: Array = []  # [local_ms, pos, yaw, anim]
var _name_tag: Label3D
var _role_tag: Label3D
var _bubble: Label3D
var _bubble_time := 0.0
var _dead := false


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
	_bubble = GameBubble.make()
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


func set_state(p: Vector3, yaw: float, anim: String) -> void:
	var now := Time.get_ticks_msec()
	if _snaps.is_empty():
		global_position = p
		avatar.rotation.y = yaw
	_snaps.append([now, p, yaw, anim])
	while _snaps.size() > 30:
		_snaps.pop_front()


func show_bubble(text: String) -> void:
	GameBubble.show(_bubble, text)
	_bubble_time = 6.0


func shatter() -> void:
	if _dead:
		return
	_dead = true
	Ragdoll.spawn(get_parent(), avatar.global_transform, avatar.get_colors())
	avatar.visible = false
	_name_tag.visible = false
	_role_tag.visible = false


func _process(delta: float) -> void:
	if not _snaps.is_empty():
		var render_t := Time.get_ticks_msec() - DELAY_MS
		# Drop snapshots we have fully passed, keeping one before render time.
		while _snaps.size() >= 2 and _snaps[1][0] <= render_t:
			_snaps.pop_front()
		var a: Array = _snaps[0]
		var pos: Vector3 = a[1]
		var yaw: float = a[2]
		if _snaps.size() >= 2 and render_t > a[0]:
			var b: Array = _snaps[1]
			var k := clampf((render_t - a[0]) / maxf(b[0] - a[0], 1.0), 0.0, 1.0)
			pos = (a[1] as Vector3).lerp(b[1], k)
			yaw = lerp_angle(a[2], b[2], k)
		global_position = pos
		avatar.rotation.y = lerp_angle(avatar.rotation.y, yaw, minf(delta * 16.0, 1.0))
		var anim: String = a[3]
		if anim == "dead":
			shatter()
		else:
			if _dead:
				_dead = false
				avatar.visible = true
				_name_tag.visible = true
				refresh_look()
			avatar.play(anim)
	if _bubble_time > 0.0:
		_bubble_time -= delta
		if _bubble_time <= 0.0:
			_bubble.visible = false
