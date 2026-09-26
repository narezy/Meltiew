class_name PlaceHost
extends Node
## Runs a studio place on this device: the client-side Luau VM (LocalScripts) plus
## the PlaceTree it keeps in sync, drawn by PlaceScene (3D) and PlaceGui (UI).
## The server's replication goes in through server_ops(); everything that must reach
## the server (remote events, touches, clicks) comes out through `send`.

signal send(msg: Dictionary)
signal output(line: Dictionary)
signal spawn_requested(pos: Vector3)
signal teleport_requested(pos: Vector3)
## A LocalScript changed the cursor: UserInputService.MouseIcon / MouseIconEnabled / MouseBehavior.
signal mouse_settings_changed
## A script offered a gamepass (MarketplaceService:PromptGamePassPurchase).
signal pass_prompt(pass_id: int)
## Camera:SetZoom / SetRotation / Shake from a LocalScript.
signal camera_control(op: Dictionary)
## StarterGui:SetCoreGuiEnabled(kind, on) from a LocalScript.
signal core_gui_changed(kind: String, on: bool)

const RUNTIME_PATH := "res://studio/runtime/runtime.luau"
const MEMORY_MB := 64
const TIME_LIMIT := 0.1

var tree := PlaceTree.new()
var scene: PlaceScene
var gui: PlaceGui
var user_id := 0
var lang := "en"
var strings := {}
var failed := ""
var mouse_settings := {"icon": "", "enabled": true, "behavior": "Default"}
var core_gui := {"Backpack": true, "Health": true, "Chat": true, "Emotes": true}
## Gamepasses: the ones this player owns here, and the place's list (id, name, price).
var passes: Array = []
var pass_info: Array = []
## Badges: the ones this player has here, and the place's list.
var badges: Array = []
var badge_info: Array = []

var _vm: RefCounted
var _touching := {}  # part id -> seconds since last contact
var _gui_layer: CanvasLayer


static func supported() -> bool:
	return ClassDB.class_exists("LuauVM")


## Starts the VM with the world the server sent on join. Returns false if this
## device can't run studio places (see `failed`).
func start(p_user_id: int, p_lang: String, p_strings: Dictionary, snapshot: Array, world_parent: Node) -> bool:
	user_id = p_user_id
	lang = p_lang
	strings = p_strings
	scene = PlaceScene.new()
	scene.strings = strings
	scene.lang = lang
	world_parent.add_child(scene)
	scene.bind(tree)
	_gui_layer = CanvasLayer.new()
	_gui_layer.layer = 5
	add_child(_gui_layer)
	gui = PlaceGui.new()
	gui.theme = UI.theme
	gui.strings = strings
	gui.lang = lang
	_gui_layer.add_child(gui)
	gui.bind(tree, "")
	gui.gui_event.connect(_on_gui_event)
	scene.clicked.connect(func(id): send.emit({"t": "click", "id": id}))

	if not supported():
		failed = "LuauVM missing"
		# Without scripts the world is still drawn from the server's replication.
		for op in snapshot:
			tree.apply(op)
		return false
	_vm = ClassDB.instantiate("LuauVM")
	_vm.open(MEMORY_MB)
	var err: String = _vm.run("=runtime", FileAccess.get_file_as_string(RUNTIME_PATH))
	if err != "":
		failed = err
		output.emit({"level": "error", "msg": "runtime: " + err})
		return false
	_vm.sandbox()
	var touch := DisplayServer.is_touchscreen_available()
	var device := {"touch": touch, "keyboard": not touch or OS.has_feature("pc"), "mouse": not touch or OS.has_feature("pc")}
	_call("__init", {"role": "client", "userId": user_id, "lang": lang, "strings": strings, "schema": StudioSchema.data(), "device": device, "passes": passes, "pass_info": pass_info, "badges": badges, "badge_info": badge_info})
	_call("__dispatch", snapshot)
	_call("__start", "")
	return true


## Operations from the server ('r' batches): replication, remote events, spawn, logs.
func server_ops(ops: Array) -> void:
	var events: Array = []
	for op in ops:
		match str(op.get("o", "")):
			"new", "set", "del", "parent":
				if _vm:
					events.append(op)
				else:
					tree.apply(op)
			"mesh", "meshv":
				if _vm:
					events.append(op)
				else:
					scene.mesh_op(op)
			"sound":
				scene.play_sound(str(op.id))
			"fire":
				events.append({"e": "fire", "id": op.id, "args": op.get("args", [])})
			"ret":
				events.append({"e": "ret", "rid": op.rid, "ok": op.ok, "values": op.get("values", [])})
			"spawn":
				spawn_requested.emit(SValue.decode(op.pos))
			"print":
				output.emit(op)
			"prompt_pass":
				pass_prompt.emit(int(op.get("id", 0)))
			"camctl":
				camera_control.emit(op)
	if not events.is_empty() and _vm:
		_call("__dispatch", events)


func _process(delta: float) -> void:
	if _vm:
		_call("__step", {"dt": delta})
	# Touches end when a part hasn't been touched for a moment.
	for id in _touching.keys():
		_touching[id] += delta
		if _touching[id] > 0.3:
			_touching.erase(id)
			_touch(id, true)
	if gui and gui.root_id == "":
		var pg := player_gui()
		if pg != "":
			gui.set_root(pg)


## Called by the game for every part the local character is in contact with.
func report_contact(part_id: String) -> void:
	if part_id == "" or not tree.has(part_id) or not tree.prop(part_id, "CanTouch"):
		return
	if not _touching.has(part_id):
		_touch(part_id, false)
	_touching[part_id] = 0.0


func _touch(part_id: String, ended: bool) -> void:
	send.emit({"t": "touch", "id": part_id, "ended": ended})
	if _vm:
		_call("__dispatch", [{"e": "touch", "id": part_id, "ended": ended}])


## The character's position for LocalScripts (HumanoidRootPart.Position).
func report_position(pos: Vector3) -> void:
	if _vm:
		_call("__dispatch", [{"e": "pos", "p": SValue.encode(pos)}])


func key_event(key: String, down: bool) -> void:
	if _vm:
		_call("__dispatch", [{"e": "input", "key": key, "down": down}])


## Mouse buttons, taps and the wheel for UserInputService and the Mouse object.
## `ui` = the press landed on the game's UI, not the world.
func pointer_event(kind: String, down: bool, pos: Vector2, ui := false) -> void:
	if _vm:
		_call("__dispatch", [{"e": "input", "kind": kind, "down": down, "x": pos.x, "y": pos.y, "ui": ui}])


var _last_mouse := {}


## Where the pointer is and what it points at (Mouse.Hit, Mouse.Target...).
func mouse_state(pos: Vector2, origin: Vector3, dir: Vector3, hit: Vector3, target: String) -> void:
	var m := {"e": "mouse", "x": roundf(pos.x), "y": roundf(pos.y), "hit": SValue.encode(hit.snappedf(0.01)),
		"origin": SValue.encode(origin.snappedf(0.01)), "dir": SValue.encode(dir.snappedf(0.001)), "target": target if target != "" else null}
	if _vm and m != _last_mouse:
		_last_mouse = m
		_call("__dispatch", [m])


var _last_cam := {}


## Where the game's camera is (workspace.CurrentCamera).
func camera_state(pos: Vector3, focus: Vector3, look: Vector3) -> void:
	var m := {"e": "camera", "p": SValue.encode(pos.snappedf(0.01)), "f": SValue.encode(focus.snappedf(0.01)), "look": SValue.encode(look.snappedf(0.001))}
	if _vm and m != _last_cam:
		_last_cam = m
		_call("__dispatch", [m])


## Clicking with a tool: LocalScripts hear it right away, the server gets told.
func tool_event(tool_id: String, ev: String, extra := {}) -> void:
	var msg := {"t": "tool", "ev": ev, "id": tool_id}
	msg.merge(extra)
	send.emit(msg)
	if _vm and (ev == "activate" or ev == "deactivate"):
		_call("__dispatch", [{"e": "tool", "id": tool_id, "ev": ev}])


func _on_gui_event(id: String, ev: String, value: Variant) -> void:
	if _vm:
		_call("__dispatch", [{"e": "gui", "id": id, "ev": ev, "value": value}])


func _call(fn: String, arg: Variant) -> void:
	var out: String = _vm.call_function(fn, arg if arg is String else JSON.stringify(arg), TIME_LIMIT)
	var err: String = _vm.get_error()
	if err != "":
		output.emit({"level": "error", "msg": err, "src": "runtime"})
		return
	if out == "" or out == "[]":
		return
	var ops: Variant = JSON.parse_string(out)
	if ops is Array:
		_apply(ops)


## Operations from the client VM: what the renderers draw, and what goes to the server.
func _apply(ops: Array) -> void:
	for op in ops:
		match str(op.get("o", "")):
			"new", "set", "del", "parent":
				tree.apply(op)
			"mesh", "meshv":
				scene.mesh_op(op)
			"sound":
				scene.play_sound(str(op.id))
			"fire":
				send.emit({"t": "remote", "id": op.id, "args": op.get("args", [])})
			"invoke":
				send.emit({"t": "invoke", "id": op.id, "rid": op.rid, "args": op.get("args", [])})
			"teleport":
				teleport_requested.emit(SValue.decode(op.pos))
			"print":
				output.emit(op)
			"mouse":
				mouse_settings = {"icon": str(op.get("icon", "")), "enabled": op.get("enabled", true) != false, "behavior": str(op.get("behavior", "Default"))}
				mouse_settings_changed.emit()
			"prompt_pass":
				pass_prompt.emit(int(op.get("id", 0)))
			"camctl":
				camera_control.emit(op)
			"coregui":
				core_gui[str(op.k)] = op.get("on", true) == true
				core_gui_changed.emit(str(op.k), core_gui[str(op.k)])
			"equip":
				# Humanoid:EquipTool / UnequipTools in a LocalScript: the server decides.
				if op.get("id") != null:
					send.emit({"t": "tool", "ev": "equip", "id": op.id})
				else:
					send.emit({"t": "tool", "ev": "unequip"})


# --- things the game asks about ------------------------------------------------------

func local_player() -> String:
	var players := tree.service("Players")
	for k in tree.kids(players):
		if tree.cls(k) == "Player" and int(tree.prop(k, "UserId")) == user_id:
			return k
	return ""


func player_gui() -> String:
	var me := local_player()
	return tree.child_of_class(me, "PlayerGui") if me != "" else ""


## The Humanoid of this player's character, or "".
func local_humanoid() -> String:
	var me := local_player()
	if me == "":
		return ""
	var ch: Variant = tree.prop(me, "Character")
	if ch is Dictionary and ch.has("$i") and tree.has(str(ch["$i"])):
		return tree.child_of_class(str(ch["$i"]), "Humanoid")
	return ""


## This player's character Model, or "".
func character() -> String:
	var me := local_player()
	var ch: Variant = tree.prop(me, "Character") if me != "" else null
	if ch is Dictionary and ch.has("$i") and tree.has(str(ch["$i"])):
		return str(ch["$i"])
	return ""


## The Tool in this player's hand, or "".
func equipped_tool() -> String:
	var ch := character()
	return tree.child_of_class(ch, "Tool") if ch != "" else ""


## Every Tool this player has: the Backpack's, plus the one in hand.
func tools() -> Array:
	var out: Array = []
	var me := local_player()
	var bp := tree.child_of_class(me, "Backpack") if me != "" else ""
	if bp != "":
		for k in tree.kids(bp):
			if tree.cls(k) == "Tool":
				out.append(k)
	var held := equipped_tool()
	if held != "":
		out.append(held)
	return out


## Who owns a character Model: their UserId, or 0.
func user_of_character(model: String) -> int:
	for k in tree.kids(tree.service("Players")):
		if tree.cls(k) == "Player":
			var ch: Variant = tree.prop(k, "Character")
			if ch is Dictionary and str(ch.get("$i", "")) == model:
				return int(tree.prop(k, "UserId"))
	return 0


## workspace.CurrentCamera ("" before the player is set up).
## The gamepass dialog closed: scripts on this device hear whether it was bought.
func pass_result(pass_id: int, bought: bool) -> void:
	if _vm:
		_call("__dispatch", [{"e": "pass_bought", "id": pass_id, "bought": bought}])


func camera() -> String:
	var ws := tree.service("Workspace")
	return tree.child_of_class(ws, "Camera") if ws != "" else ""


## A property of the local Player (camera rules), or its default.
func player_prop(key: String) -> Variant:
	var me := local_player()
	return tree.prop(me, key) if me != "" else StudioSchema.default_of("Player", key)


func starter(key: String) -> Variant:
	var sp := tree.service("StarterPlayer")
	return tree.prop(sp, key) if sp != "" else StudioSchema.default_of("StarterPlayer", key)


func workspace_prop(key: String) -> Variant:
	var ws := tree.service("Workspace")
	return tree.prop(ws, key) if ws != "" else StudioSchema.default_of("Workspace", key)


func close() -> void:
	if _vm:
		_vm.close()
		_vm = null
