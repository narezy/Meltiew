class_name PlacePrompts
extends Control
## ProximityPrompts: when you're close to one, "[E] ActionText" shows by it. Press the
## key (or tap it on a phone); with a HoldDuration, keep holding until the ring fills.
## Then the server hears about it (and checks you're really there) and this app's own
## scripts get Triggered too.

const LOOK_EVERY := 0.3

var host: PlaceHost
var player: Node3D
var typing: Callable  # () -> bool: a text field has the keyboard

var _prompts: Array = []  # ProximityPrompt ids in the world
var _known := {}  # every ProximityPrompt id in the tree (kept up to date by its signals)
var _bound: PlaceTree
var _look := 0.0
var _current := ""
var _held := 0.0
var _holding := false
var _touch_held := false
var _box: PanelContainer
var _key: Label
var _action: Label
var _object: Label
var _bar: ProgressBar


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UI.BG_2, 0.88)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(10)
	_box.add_theme_stylebox_override("panel", sb)
	_box.visible = false
	add_child(_box)
	var row := UI.hbox(10)
	_box.add_child(row)
	_key = UI.label("E", 22, UI.INK, "black")
	_key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_key.custom_minimum_size = Vector2(40, 40)
	var key_bg := StyleBoxFlat.new()
	key_bg.bg_color = UI.TEXT
	key_bg.set_corner_radius_all(10)
	_key.add_theme_stylebox_override("normal", key_bg)
	row.add_child(_key)
	var col := UI.vbox(0)
	row.add_child(col)
	_object = UI.label("", 13, UI.MUTED, "bold")
	col.add_child(_object)
	_action = UI.label("", 18, UI.TEXT, "black")
	col.add_child(_action)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(120, 6)
	_bar.max_value = 1.0
	col.add_child(_bar)
	# Phones: the prompt itself is the button (held down for a HoldDuration).
	_box.gui_input.connect(func(e: InputEvent):
		if (e is InputEventScreenTouch or e is InputEventMouseButton) and not (e is InputEventMouseButton and e.button_index != MOUSE_BUTTON_LEFT):
			_touch_held = e.pressed
			_box.accept_event())


## Prompts that aren't instances in the place, like "Hug" by someone waiting for one:
## () -> Array of {id, at: Vector3, range, key, action, object, hold, use: Callable}.
var extra: Callable


func _candidates() -> Array:
	var out: Array = []
	if host and host.tree:
		var t := host.tree
		for id in _prompts:
			if not t.has(id) or not t.prop(id, "Enabled"):
				continue
			var at: Variant = _where(id)
			if at == null:
				continue
			out.append({"id": id, "at": at, "range": float(t.prop(id, "MaxActivationDistance")),
				"key": str(t.prop(id, "KeyboardKeyCode")), "action": host.gui.localize(str(t.prop(id, "ActionText"))),
				"object": host.gui.localize(str(t.prop(id, "ObjectText"))), "hold": float(t.prop(id, "HoldDuration")),
				"use": host.prompt_used.bind(id)})
	if extra.is_valid():
		out.append_array(extra.call())
	return out


func _bind(t: PlaceTree) -> void:
	_bound = t
	_known.clear()
	for id in t.nodes:
		if t.cls(id) == "ProximityPrompt":
			_known[id] = true
	t.added.connect(func(id: String):
		if t.cls(id) == "ProximityPrompt":
			_known[id] = true)
	t.removed.connect(func(id: String, _parent: String): _known.erase(id))


func _process(delta: float) -> void:
	if player == null:
		return
	_look -= delta
	if _look <= 0.0 and host and host.tree:
		_look = LOOK_EVERY
		if _bound != host.tree:
			_bind(host.tree)
		# Only the prompts, not the whole map: places have thousands of parts.
		_prompts = []
		var ws := host.tree.service("Workspace")
		if ws != "":
			for id in _known:
				if host.tree.has(id) and host.tree.is_descendant(id, ws):
					_prompts.append(id)
	var best: Dictionary = {}
	var best_d := INF
	var me := player.global_position
	for c in _candidates():
		var d := me.distance_to(c.at)
		if d <= float(c.range) and d < best_d:
			best = c
			best_d = d
	var best_id: String = str(best.get("id", ""))
	if best_id != _current:
		_current = best_id
		_held = 0.0
		_holding = false
	var cam := get_viewport().get_camera_3d()
	if best.is_empty() or cam == null:
		_box.visible = false
		return
	var point: Vector3 = (best.at as Vector3) + Vector3(0, 1.2, 0)
	if cam.is_position_behind(point):
		_box.visible = false
		return
	var key := str(best.key).to_upper()
	_key.text = "" if DisplayServer.is_touchscreen_available() else key
	_key.visible = _key.text != ""
	_action.text = str(best.action)
	_object.text = str(best.object)
	_object.visible = _object.text != ""
	var need := float(best.hold)
	_bar.visible = need > 0.0
	_box.visible = true
	_box.reset_size()
	_box.position = cam.unproject_position(point) - _box.size / 2.0
	# Held down with the key or a finger on it.
	var code := OS.find_keycode_from_string(key)
	var down: bool = _touch_held or (code != KEY_NONE and Input.is_physical_key_pressed(code) and not (typing.is_valid() and typing.call()))
	if down and not _holding:
		_holding = true
		_held = 0.0
		if need <= 0.0:
			_trigger(best)
	elif down and need > 0.0 and _held < need:
		_held += delta
		if _held >= need:
			_trigger(best)
	elif not down:
		_holding = false
		_held = 0.0
	_bar.value = clampf(_held / need, 0.0, 1.0) if need > 0.0 else 0.0


func _trigger(c: Dictionary) -> void:
	_held = INF
	(c.use as Callable).call()


## The middle of the Part a prompt is in (null if it isn't in one).
func _where(id: String) -> Variant:
	var part := host.tree.parent_of(id)
	if part == "" or not StudioSchema.is_a(host.tree.cls(part), "BasePart"):
		return null
	return host.tree.prop(part, "Position")
