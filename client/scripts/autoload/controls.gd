extends Node
## How the player controls the game right now: touch, mouse and keyboard, a gamepad, a TV
## remote (Android TV) or VR controllers. With a gamepad or a remote, menus are walked with
## the stick or the arrows: buttons take the focus (a ring shows it), each screen gives it
## to its first button, lists scroll after it, and B / Back goes back.
##
## In the game (hud.gd): left stick walks, right stick turns the camera, A jumps, X uses a
## prompt, Y opens emotes, LB / RB zoom, LT (or pressing the left stick) runs, RT uses the
## tool, the d-pad picks tools, Start opens the menu, Back the player list. On a TV remote:
## up / down walk, left / right turn, OK jumps (or uses a prompt that's showing).

signal device_changed(device: String)

## "touch", "mouse", "pad", "remote" or "vr"
var device := "touch" if DisplayServer.is_touchscreen_available() else "mouse"
## Android TV: no touch screen, a remote's arrows and OK.
var tv := OS.has_feature("android") and not DisplayServer.is_touchscreen_available() and not _headset()

var _screens: Array = []  # weakrefs to the open screens and sheets, the newest last

const PAD_ACTIONS := {
	"move_forward": [[JOY_AXIS_LEFT_Y, -1.0]],
	"move_back": [[JOY_AXIS_LEFT_Y, 1.0]],
	"move_left": [[JOY_AXIS_LEFT_X, -1.0]],
	"move_right": [[JOY_AXIS_LEFT_X, 1.0]],
	"cam_left": [[JOY_AXIS_RIGHT_X, -1.0]],
	"cam_right": [[JOY_AXIS_RIGHT_X, 1.0]],
	"cam_up": [[JOY_AXIS_RIGHT_Y, -1.0]],
	"cam_down": [[JOY_AXIS_RIGHT_Y, 1.0]],
	"sprint": [[JOY_AXIS_TRIGGER_LEFT, 1.0], JOY_BUTTON_LEFT_STICK],
	"tool_use": [[JOY_AXIS_TRIGGER_RIGHT, 1.0]],
	"jump": [JOY_BUTTON_A],
	"interact": [JOY_BUTTON_X],
	"emotes": [JOY_BUTTON_Y],
	"zoom_in": [JOY_BUTTON_RIGHT_SHOULDER],
	"zoom_out": [JOY_BUTTON_LEFT_SHOULDER],
	"game_menu": [JOY_BUTTON_START],
	"players": [JOY_BUTTON_BACK],
	"first_person": [JOY_BUTTON_RIGHT_STICK],
	"tool_next": [JOY_BUTTON_DPAD_RIGHT],
	"tool_prev": [JOY_BUTTON_DPAD_LEFT],
	"inventory": [JOY_BUTTON_DPAD_UP],
	"tool_drop": [JOY_BUTTON_DPAD_DOWN],
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for action in PAD_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.25)
		for b in PAD_ACTIONS[action]:
			if b is Array:
				var m := InputEventJoypadMotion.new()
				m.axis = b[0]
				m.axis_value = b[1]
				InputMap.action_add_event(action, m)
			else:
				var j := InputEventJoypadButton.new()
				j.button_index = b
				InputMap.action_add_event(action, j)
	if tv:
		device = "remote"
		# The remote's up / down walk (left / right turn the camera, in hud.gd).
		for pair in [["move_forward", KEY_UP], ["move_back", KEY_DOWN]]:
			var k := InputEventKey.new()
			k.physical_keycode = pair[1]
			InputMap.action_add_event(pair[0], k)
	get_tree().node_added.connect(_on_node_added)


## Roblox's KeyCode name of a gamepad button ("ButtonA", "DPadUp"...).
static func pad_button_name(b: JoyButton) -> String:
	return {JOY_BUTTON_A: "ButtonA", JOY_BUTTON_B: "ButtonB", JOY_BUTTON_X: "ButtonX", JOY_BUTTON_Y: "ButtonY",
		JOY_BUTTON_LEFT_SHOULDER: "ButtonL1", JOY_BUTTON_RIGHT_SHOULDER: "ButtonR1", JOY_BUTTON_LEFT_STICK: "ButtonL3",
		JOY_BUTTON_RIGHT_STICK: "ButtonR3", JOY_BUTTON_START: "ButtonStart", JOY_BUTTON_BACK: "ButtonSelect",
		JOY_BUTTON_DPAD_UP: "DPadUp", JOY_BUTTON_DPAD_DOWN: "DPadDown", JOY_BUTTON_DPAD_LEFT: "DPadLeft",
		JOY_BUTTON_DPAD_RIGHT: "DPadRight"}.get(b, "")


## A standalone headset (Pico, Quest): Android without a touch screen too, but not a TV.
static func _headset() -> bool:
	var xr := XRServer.find_interface("OpenXR")
	return OS.has_feature("pico") or OS.has_feature("quest") or (xr != null and xr.is_initialized())


func pad_like() -> bool:
	return device == "pad" or device == "remote"


## Buttons and cards made for menus take the focus only while a gamepad or a remote is in
## use: with a mouse, a clicked button would keep it and Space or Enter would press it again.
func focus_mode() -> Control.FocusMode:
	return Control.FOCUS_ALL if pad_like() else Control.FOCUS_NONE


func _input(e: InputEvent) -> void:
	var d := ""
	if e is InputEventJoypadButton and e.pressed:
		d = "pad"
	elif e is InputEventJoypadMotion and absf(e.axis_value) > 0.5:
		d = "pad"
	elif e is InputEventScreenTouch and e.pressed:
		d = "touch"
	elif e is InputEventMouseButton and e.pressed and not tv:
		d = "mouse"
	elif e is InputEventMouseMotion and e.relative.length() > 3.0 and not tv:
		d = "mouse"
	elif e is InputEventKey and e.pressed and tv:
		d = "remote"
	if d != "" and d != device:
		set_device(d)
	# Arrows or A with nothing focused on an open screen: start on its first button.
	if pad_like() and e.is_pressed() and not e.is_echo() and get_viewport().gui_get_focus_owner() == null and _top_screen() != null \
			and (e.is_action("ui_up") or e.is_action("ui_down") or e.is_action("ui_left") or e.is_action("ui_right") or e.is_action("ui_accept")):
		get_viewport().set_input_as_handled()
		focus_screen(false)
	# B in a menu goes back: closes the newest sheet, or steps back a page. (A TV remote's
	# Back comes as the system's back request: game.gd and main_menu.gd handle that.)
	if e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_B:
		var owner := get_viewport().gui_get_focus_owner()
		if owner and owner.is_visible_in_tree():
			get_viewport().set_input_as_handled()
			go_back()


## Back: the newest open sheet closes if it can; otherwise the scene steps back.
func go_back() -> void:
	var top := _top_screen()
	if top and top.has_meta("on_back"):
		(top.get_meta("on_back") as Callable).call()
		return
	var scene := get_tree().current_scene
	if scene and scene.has_method("go_back"):
		scene.go_back()


func set_device(d: String) -> void:
	var was := pad_like()
	device = d
	device_changed.emit(d)
	if pad_like() != was:
		var mode := focus_mode()
		for c in get_tree().root.find_children("*", "Control", true, false):
			if c.get_meta("pad_focus", false):
				(c as Control).focus_mode = mode
	if pad_like():
		focus_screen.call_deferred()


## A screen or a sheet opened: with a gamepad or a remote, its first button takes the focus.
func screen_opened(root: Control) -> void:
	_screens = _screens.filter(func(w): return w.get_ref() != null and w.get_ref() != root)
	_screens.append(weakref(root))
	# When it closes, the focus goes back to the screen under it.
	root.tree_exited.connect(func():
		if pad_like():
			focus_screen.call_deferred(), CONNECT_ONE_SHOT)
	if pad_like():
		focus_screen.call_deferred()


## Gives the focus to the first button of the newest screen still open, unless something
## on it already has it.
func focus_screen(retry := true) -> void:
	if not pad_like():
		return
	var root := _top_screen()
	if root == null:
		return
	var owner := get_viewport().gui_get_focus_owner()
	if owner and owner.is_visible_in_tree() and root.is_ancestor_of(owner):
		return
	var first := _find(root, false, false)
	if first == null and retry:
		# Still loading (cards come a moment later): look again.
		get_tree().create_timer(0.6).timeout.connect(focus_screen.bind(false))
		return
	# Nothing to press on it: the scene around it (the menu's tabs), then the rest.
	if first == null and get_tree().current_scene:
		first = _find(get_tree().current_scene, false, false)
	if first == null:
		first = first_focusable(root)
	if first:
		first.grab_focus()


func _top_screen() -> Control:
	for i in range(_screens.size() - 1, -1, -1):
		var c: Control = _screens[i].get_ref()
		if c and c.is_inside_tree() and c.is_visible_in_tree():
			return c
	return null


## The first button or card of a screen; a text field only if there's nothing else (on a
## TV that would pop the keyboard up straight away).
static func first_focusable(root: Node) -> Control:
	var c := _first(root, false)
	return c if c else _first(root, true)


## The first focusable control under `root`, text fields only with `text_too`. Ones marked
## "pad_late" (the balance chips in a page's corner) only if there's nothing else.
static func _first(root: Node, text_too: bool) -> Control:
	var c := _find(root, text_too, false)
	return c if c else _find(root, text_too, true)


static func _find(root: Node, text_too: bool, late_too: bool) -> Control:
	for c in root.get_children():
		if c is Control:
			if not (c as Control).visible:
				continue
			if (c as Control).focus_mode == Control.FOCUS_ALL and not (c is BaseButton and (c as BaseButton).disabled) \
					and (text_too or not (c is LineEdit or c is TextEdit)) and (late_too or not c.has_meta("pad_late")):
				return c
		elif c is CanvasLayer and not (c as CanvasLayer).visible:
			continue
		var inner := _find(c, text_too, late_too)
		if inner:
			return inner
	return null


func _on_node_added(n: Node) -> void:
	# Lists keep the focused item in view.
	if n is ScrollContainer:
		(n as ScrollContainer).follow_focus = true
	# Sheets and dialogs (a dim layer over everything, the card on it) are screens too.
	elif n is Control and n.get_parent() is CanvasLayer and (n.get_parent() as CanvasLayer).layer >= 50 \
			and n.get_index() == 0:
		screen_opened(n)
