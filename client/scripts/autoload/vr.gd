extends Node
## VR: Meltiew in a headset through OpenXR (SteamVR, WiVRn / Monado, a Pico, a Quest).
##
## On a computer the game starts flat; when a VR runtime is running (or the settings say
## "always") it starts itself again in VR (`--xr-mode on`: OpenXR can only come up at
## start). Standalone headsets start in VR straight away (their export turns it on).
##
## In VR the app's whole screen (menus, the HUD, the place's GUI) is a panel floating in
## front of you: point a controller at it and pull the trigger to click, push the stick to
## scroll. The world is drawn for the headset by a viewport of its own that shares the
## game's world; the flat window keeps drawing just the app's screen, which is the panel.
##
## In the game: the left stick walks where you look, the right one turns in steps, A jumps,
## X uses a prompt, the left stick pressed runs, the right trigger uses the held tool, Y
## shows or hides the panel, the menu button opens the game menu. Every button and stick
## also reaches the place's scripts as a gamepad (ButtonA, ButtonR2, Thumbstick1...). Your
## avatar's arms follow your hands (others see them if the place allows it and they're 13+).

const RUNTIMES := ["vrserver", "vrmonitor", "vrcompositor", "wivrn-server", "monado-service"]
const RUNTIMES_WINDOWS := ["vrserver.exe", "vrmonitor.exe", "OVRServer_x64.exe", "VirtualDesktop.Streamer.exe", "MixedRealityPortal.exe"]
const TURN_STEP := PI / 6.0
const PANEL_WIDTH := 1.5  # studs: a stud is about a meter here (eyes are 1.62 up)
const PANEL_DISTANCE := 1.35
## Gamepad names the place's scripts get for each controller button (left, right).
const BUTTONS := {
	"left": {"ax_button": "ButtonX", "by_button": "ButtonY", "trigger_click": "ButtonL2", "grip_click": "ButtonL1", "primary_click": "ButtonL3", "menu_button": "ButtonSelect"},
	"right": {"ax_button": "ButtonA", "by_button": "ButtonB", "trigger_click": "ButtonR2", "grip_click": "ButtonR1", "primary_click": "ButtonR3"},
}

var active := false
var xr: XRInterface
var vp: SubViewport  # draws the world for the headset
var origin: XROrigin3D
var camera: Camera3D  # the headset (an XRCamera3D; a plain camera in the simulation)
var hands := {}  # "left" / "right" -> XRController3D (SimHand in the simulation)
var sim := false  # --vr-sim: no headset, for checking the panel and the controls by eye
var panel: MeshInstance3D  # the app's screen
var panel_shown := true

var _panel_mat: StandardMaterial3D
var _laser: MeshInstance3D
var _dot: MeshInstance3D
var _pointer := "right"  # the hand that clicks the panel
var _pointing := false
var _px := Vector2(-1, -1)
var _clicking := false
var _scroll_wait := 0.0
var _game: Node
var _yaw := 0.0  # turning with the stick, on top of the headset's own
var _turned := false
var _menu_env: Environment
## Added to the headset's height so the eyes are at the character's eyes: runtimes without
## a floor (WiVRn, seated) put the head at 0. Set on entering the game and on recentering.
var _lift := 0.0
var _panel_yaw := 0.0  # where the panel is around your head
var _swinging := false
var _hand_marks := {}  # side -> MeshInstance3D: your hands (your own body isn't drawn in VR)
var _world_wait := 0.0
var _world_hit: Variant = null  # where the pointing hand meets the world (VR mouse)
var _calibrate_in := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	xr = XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized():
		_start()
	elif "--vr-sim" in OS.get_cmdline_user_args():
		sim = true
		_start()
	else:
		_maybe_relaunch.call_deferred()


# --- starting in VR -----------------------------------------------------------------

## A computer with a VR runtime running (or "always" in the settings): start again in VR.
## Only from the app's own start (tools and tests run flat), and only once.
func _maybe_relaunch() -> void:
	if not OS.has_feature("pc") or OS.has_feature("editor") or "--vr-tried" in OS.get_cmdline_user_args():
		return
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != "res://scenes/boot.tscn":
		return
	var want := str(Session.settings.get("vr", "auto"))
	if want == "off" or (want == "auto" and not runtime_running()):
		return
	var args := PackedStringArray(["--xr-mode", "on"]) + OS.get_cmdline_args() + PackedStringArray(["--", "--vr-tried"]) + OS.get_cmdline_user_args()
	if OS.create_process(OS.get_executable_path(), args) > 0:
		get_tree().quit()


## Whether SteamVR, WiVRn, Monado, Oculus or Virtual Desktop is running on this computer.
static func runtime_running() -> bool:
	match OS.get_name():
		"Linux", "FreeBSD":
			for pid in DirAccess.get_directories_at("/proc"):
				if pid.is_valid_int() and FileAccess.get_file_as_string("/proc/%s/comm" % pid).strip_edges() in RUNTIMES:
					return true
		"Windows":
			var out := []
			OS.execute("tasklist", ["/FO", "CSV", "/NH"], out)
			var text := "".join(out)
			for name in RUNTIMES_WINDOWS:
				if name in text:
					return true
	return false


func _start() -> void:
	active = true
	Session.vr = true
	Controls.set_device("vr")
	var root := get_tree().root
	# OpenXR keeps the pace; nothing else limits the frames.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	# The flat window (and so the panel) only draws the app's screen now.
	root.disable_3d = true
	root.transparent_bg = true
	if OS.has_feature("pc"):
		DisplayServer.window_set_size(Vector2i(1600, 900))
	vp = SubViewport.new()
	vp.use_xr = not sim
	if sim:
		vp.size = Vector2i(1280, 720)
	vp.world_3d = root.find_world_3d()
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_2X if OS.has_feature("mobile") else Viewport.MSAA_4X
	vp.audio_listener_enable_3d = false  # the game's camera hears, put where the head is
	add_child(vp)
	origin = XROrigin3D.new()
	vp.add_child(origin)
	camera = Camera3D.new() if sim else XRCamera3D.new()
	if sim:
		camera.position = Vector3(0, 0.1, 0)  # like WiVRn: no floor, the head near 0
	camera.near = 0.05
	camera.far = 600.0
	origin.add_child(camera)
	camera.current = true
	_menu_env = Environment.new()
	_menu_env.background_mode = Environment.BG_COLOR
	_menu_env.background_color = UI.BG
	_menu_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_menu_env.ambient_light_color = Color.WHITE
	camera.environment = _menu_env
	for side in ["left", "right"]:
		var c: Node3D
		if sim:
			c = SimHand.new()
			c.position = Vector3(-0.25 if side == "left" else 0.25, -0.3, -0.3)
		else:
			var xc := XRController3D.new()
			xc.tracker = side + "_hand"
			xc.pose = "aim"
			c = xc
		origin.add_child(c)
		c.button_pressed.connect(_on_button.bind(side, true))
		c.button_released.connect(_on_button.bind(side, false))
		c.input_float_changed.connect(_on_float.bind(side))
		c.input_vector2_changed.connect(_on_stick.bind(side))
		hands[side] = c
	_make_panel()
	_make_laser()
	for side in hands:
		var mark := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.07, 0.05, 0.11)
		mark.mesh = box
		mark.position = Vector3(0, -0.02, 0.06)  # where the palm is, behind the aim point
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hands[side].add_child(mark)
		_hand_marks[side] = mark
	_paint_hands(Session.DEFAULT_COLORS)
	_place_panel.call_deferred(true)
	# Holding the headset's recenter button: the height is measured again too.
	if xr and xr.has_signal("pose_recentered"):
		xr.connect("pose_recentered", func(): _calibrate_in = 0.3)


func _make_panel() -> void:
	panel = MeshInstance3D.new()
	panel.mesh = QuadMesh.new()
	_panel_mat = StandardMaterial3D.new()
	_panel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_panel_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_panel_mat.albedo_texture = get_tree().root.get_texture()
	_panel_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Always in front of the world: walls never cut the menu.
	_panel_mat.no_depth_test = true
	_panel_mat.render_priority = 10
	panel.material_override = _panel_mat
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vp.add_child(panel)


func _make_laser() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(UI.ACCENT, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.render_priority = 11
	_laser = MeshInstance3D.new()
	var beam := BoxMesh.new()
	beam.size = Vector3(0.006, 0.006, 1.0)
	_laser.mesh = beam
	_laser.material_override = mat
	_laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vp.add_child(_laser)
	_dot = MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.012
	ball.height = 0.024
	_dot.mesh = ball
	var dmat := mat.duplicate()
	dmat.albedo_color = Color.WHITE
	_dot.material_override = dmat
	vp.add_child(_dot)


# --- the panel ------------------------------------------------------------------------

## Puts the panel in front of where you look (at eye height in menus, lower in the game).
func _place_panel(snap := false) -> void:
	if not active:
		return
	if snap:
		_panel_yaw = _head_yaw()
	# Always the same distance from your head: it swings around you, never closer or further.
	var fwd := Basis(Vector3.UP, _panel_yaw) * Vector3.FORWARD
	var at := camera.global_position + fwd * PANEL_DISTANCE + Vector3(0, -0.35 if _game else -0.1, 0)
	# The quad's face (+Z) toward you: looking_at points -Z away.
	panel.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), at)


func _head_yaw() -> float:
	var fwd := -camera.global_basis.z
	return atan2(-fwd.x, -fwd.z) if Vector2(fwd.x, fwd.z).length() > 0.01 else _panel_yaw


func show_panel(on: bool) -> void:
	panel_shown = on
	panel.visible = on
	if on:
		_place_panel(true)


func _update_panel() -> void:
	var size := get_tree().root.get_visible_rect().size
	var q := panel.mesh as QuadMesh
	var want := Vector2(PANEL_WIDTH, PANEL_WIDTH * size.y / maxf(size.x, 1.0))
	if not q.size.is_equal_approx(want):
		q.size = want
	if not panel_shown:
		return
	# In the game it comes along as you walk and swings after where you look, once you've
	# turned well away (not while you point at it).
	if _game:
		if not _pointing and absf(angle_difference(_panel_yaw, _head_yaw())) > deg_to_rad(35.0):
			_swinging = true
		if _swinging:
			_panel_yaw = lerp_angle(_panel_yaw, _head_yaw(), 0.08)
			if absf(angle_difference(_panel_yaw, _head_yaw())) < deg_to_rad(3.0):
				_swinging = false
		_place_panel()


## The laser from the pointing hand: where it meets the panel becomes the mouse.
func _update_pointer() -> void:
	_pointing = false
	var hand = hands.get(_pointer)
	if hand == null or not hand.get_has_tracking_data() or (not panel_shown and _game == null):
		_laser.visible = false
		_dot.visible = false
		return
	var from: Vector3 = hand.global_position
	var dir: Vector3 = -(hand.global_basis.z as Vector3).normalized()
	var n := panel.global_basis.z.normalized()
	var denom: float = dir.dot(n)
	var hit := Vector3.ZERO
	var size := (panel.mesh as QuadMesh).size
	if absf(denom) > 0.0001 and panel_shown:
		var t: float = (panel.global_position - from).dot(n) / denom
		if t > 0.0:
			hit = from + dir * t
			var local := panel.global_transform.affine_inverse() * hit
			if absf(local.x) <= size.x / 2.0 and absf(local.y) <= size.y / 2.0:
				_pointing = true
				var uv := Vector2(local.x / size.x + 0.5, 0.5 - local.y / size.y)
				var px := uv * get_tree().root.get_visible_rect().size
				if px.distance_to(_px) > 0.5:
					_px = px
					var m := InputEventMouseMotion.new()
					m.position = px
					m.global_position = px
					m.button_mask = MOUSE_BUTTON_MASK_LEFT if _clicking else 0
					get_tree().root.push_input(m, true)
	var length: float = from.distance_to(hit) if _pointing else (from.distance_to(_world_hit) if _world_hit is Vector3 else 0.6)
	_laser.visible = true
	_laser.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD), from + dir * length / 2.0)
	_laser.scale = Vector3(1, 1, length)
	_dot.visible = _pointing or _world_hit is Vector3
	if _pointing:
		_dot.global_position = hit
	elif _world_hit is Vector3:
		_dot.global_position = _world_hit


## (Positions are the app's own screen coordinates: push_input(..., true), whatever the
## size of the flat window.)
func _click(down: bool) -> void:
	_clicking = down
	var b := InputEventMouseButton.new()
	b.button_index = MOUSE_BUTTON_LEFT
	b.pressed = down
	b.position = _px
	b.global_position = _px
	b.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	get_tree().root.push_input(b, true)


func _wheel(up: bool) -> void:
	for pressed in [true, false]:
		var w := InputEventMouseButton.new()
		w.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		w.pressed = pressed
		w.position = _px
		w.global_position = _px
		get_tree().root.push_input(w, true)


# --- buttons and sticks ---------------------------------------------------------------

func _on_button(name: String, side: String, down: bool) -> void:
	# The trigger clicks the panel when that hand points at it (or takes the pointer).
	if name == "trigger_click":
		if down and side != _pointer and panel_shown:
			_pointer = side
			_update_pointer()
		if side == _pointer and (_pointing or _clicking):
			if down != _clicking:
				_click(down)
			return
	var host: Node = _game.get("place_host") if _game else null
	var key: String = BUTTONS[side].get(name, "")
	if host and key != "":
		host.pad_event(key, down)
		if host.is_bound(key) and name != "menu_button":
			return  # the place's script uses this button
	if name == "by_button" and side == "left" and down:
		show_panel(not panel_shown)
	elif name == "menu_button" and down:
		if _game:
			_game.go_back()
		show_panel(true)
	elif name == "grip_click" and side == "left" and down and not _game:
		_place_panel(true)  # menus: bring the panel back in front
	elif _game:
		_game_button(name, side, down)


func _game_button(name: String, side: String, down: bool) -> void:
	var p: Node = _game.player
	match [side, name]:
		["right", "ax_button"]:
			if down:
				Input.action_press("jump")
				p.request_jump()
			else:
				Input.action_release("jump")
		["left", "ax_button"]:
			if down:
				Input.action_press("interact")
			else:
				Input.action_release("interact")
		["left", "primary_click"]:
			if down:
				p.sprint_toggle = not p.sprint_toggle
		["right", "trigger_click"], ["left", "trigger_click"]:
			# The trigger into the world: a click where the hand points (and the tool).
			if side == _pointer or down:
				_pointer = side
				var hand = hands[side]
				_game.vr_click(down, hand.global_position, -(hand.global_basis.z as Vector3).normalized())
		["right", "by_button"]:
			if down and _game.hud.wheel:
				_game.hud.wheel.open()
				show_panel(true)


func _on_float(name: String, value: float, side: String) -> void:
	var host: Node = _game.get("place_host") if _game else null
	if host and name == "trigger":
		host.pad_axis("ButtonL2" if side == "left" else "ButtonR2", Vector3(0, 0, value))


func _on_stick(name: String, value: Vector2, side: String) -> void:
	if name != "primary":
		return
	var host: Node = _game.get("place_host") if _game else null
	if host:
		host.pad_axis("Thumbstick1" if side == "left" else "Thumbstick2", Vector3(value.x, value.y, 0))
	# Pointing at a menu: the stick of that hand scrolls it.
	if _pointing and side == _pointer and _menu_open():
		return
	if side == "right" and _game and not (host and host.is_bound("Thumbstick2")):
		# Turning in steps (smooth turning makes many people sick).
		if absf(value.x) > 0.7 and not _turned:
			_turned = true
			_turn(-TURN_STEP if value.x > 0.0 else TURN_STEP)
		elif absf(value.x) < 0.3:
			_turned = false


## A menu on the panel (the main menu, the game menu): sticks scroll it instead of walking
## and turning. The game's HUD alone doesn't count.
func _menu_open() -> bool:
	return _game == null or (_game.menu != null and _game.menu.visible) or (_game.hud.wheel != null and _game.hud.wheel.visible)


## Turns you around your own head (not around the play area's middle).
func _turn(angle: float) -> void:
	var head := camera.global_position
	_yaw += angle
	origin.global_transform = Transform3D(Basis(Vector3.UP, angle), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -head) * origin.global_transform
	origin.global_position += head


func _process(delta: float) -> void:
	if not active:
		return
	_update_panel()
	_update_pointer()
	# The pointing hand's stick scrolls lists on the panel.
	_scroll_wait -= delta
	if _pointing and _scroll_wait <= 0.0 and _menu_open():
		var s: Vector2 = hands[_pointer].get_vector2("primary")
		if absf(s.y) > 0.5:
			_wheel(s.y > 0.0)
			_scroll_wait = 0.12
	if _game:
		_drive(delta)
		# Not on the panel: the pointing hand is the mouse in the world.
		_world_wait -= delta
		if not _pointing and _world_wait <= 0.0:
			_world_wait = 0.05
			var hand = hands[_pointer]
			_world_hit = _game.vr_point(hand.global_position, -(hand.global_basis.z as Vector3).normalized()) if hand.get_has_tracking_data() else null
		elif _pointing:
			_world_hit = null


# --- in the game ------------------------------------------------------------------------

## The game scene started (game.gd): your body goes where the headset is.
func attach(game: Node) -> void:
	_game = game
	camera.environment = null  # the place's sky and light
	_yaw = 0.0
	game.player.vr = true
	game.player.avatar.set_head_hidden(true)
	_paint_hands(Session.colors_of(Session.user))
	_calibrate_in = 0.5
	show_panel(true)


func detach() -> void:
	_game = null
	_world_hit = null
	if not active:
		return
	camera.environment = _menu_env
	for a in ["move_forward", "move_back", "move_left", "move_right", "jump", "interact"]:
		Input.action_release(a)
	show_panel(true)


func _drive(_delta: float) -> void:
	var p: Node3D = _game.player
	if not is_instance_valid(p):
		return
	# The floor at the character's feet, the head right over it: you walk the character,
	# stepping around the room just turns and leans.
	var feet: Vector3 = p.get_global_transform_interpolated().origin
	if _calibrate_in > 0.0:
		_calibrate_in -= _delta
		if _calibrate_in <= 0.0:
			_lift = LocalPlayer.EYE_HEIGHT - camera.position.y
	var head_in_origin := origin.global_transform.basis * Vector3(camera.position.x, 0, camera.position.z)
	origin.global_position = feet - head_in_origin + Vector3(0, _lift, 0)
	# Where you look is where the stick walks; the game's own camera sits in your head
	# (sounds are heard from there, scripts see it as workspace.CurrentCamera).
	var fwd := -camera.global_basis.z
	p.cam_yaw = atan2(-fwd.x, -fwd.z)
	p.cam_pitch = clampf(asin(clampf(fwd.y, -1.0, 1.0)), -1.4, 1.4)
	p.vr_head = camera.global_transform
	var stick: Vector2 = hands.left.get_vector2("primary") if not (_pointing and _pointer == "left" and _menu_open()) else Vector2.ZERO
	if stick.length() < 0.15:
		stick = Vector2.ZERO
	_strength("move_forward", maxf(stick.y, 0.0))
	_strength("move_back", maxf(-stick.y, 0.0))
	_strength("move_left", maxf(-stick.x, 0.0))
	_strength("move_right", maxf(stick.x, 0.0))
	var av: Node3D = p.avatar
	av.set_vr_hands(hand_in(av, "left"), hand_in(av, "right"))
	# Your own body would fill the view (and its arms looked huge): just the hands.
	av.visible = false


func _strength(action: String, v: float) -> void:
	if v > 0.0:
		Input.action_press(action, v)
	else:
		Input.action_release(action)


## Your hands in your arms' colors.
func _paint_hands(colors: Dictionary) -> void:
	for side in _hand_marks:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(str(colors.get("arm_l" if side == "left" else "arm_r", "#f5f1ec")))
		m.roughness = 0.7
		(_hand_marks[side] as MeshInstance3D).material_override = m


## A hand in an avatar's space (studs from its feet, facing -Z), or null if not tracked.
func hand_in(av: Node3D, side: String) -> Variant:
	var c = hands.get(side)
	if c == null or not c.get_has_tracking_data():
		return null
	return av.to_local(c.global_position)


## The headset's and the hands' places for the place's scripts (VRService:GetUserCFrame):
## relative to where the character stands.
func user_cframes() -> Dictionary:
	if not active or _game == null:
		return {}
	var base := Transform3D(Basis(Vector3.UP, (_game.player as Node).cam_yaw), (_game.player as Node3D).global_position)
	var out := {"Head": base.affine_inverse() * camera.global_transform}
	for side in hands:
		var c = hands[side]
		if c.get_has_tracking_data():
			out["LeftHand" if side == "left" else "RightHand"] = base.affine_inverse() * c.global_transform
	return out


## A controller for the simulation (--vr-sim): moved and pressed by a test script.
class SimHand extends Node3D:
	signal button_pressed(name: String)
	signal button_released(name: String)
	signal input_float_changed(name: String, value: float)
	signal input_vector2_changed(name: String, value: Vector2)
	var sticks := {}

	func get_has_tracking_data() -> bool:
		return true

	func get_vector2(name: String) -> Vector2:
		return sticks.get(name, Vector2.ZERO)

	func press(name: String, down: bool) -> void:
		(button_pressed if down else button_released).emit(name)

	func stick(name: String, v: Vector2) -> void:
		sticks[name] = v
		input_vector2_changed.emit(name, v)
