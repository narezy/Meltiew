class_name AdminPanel
extends CanvasLayer
## The platform owner's in-game panel (~ on a keyboard, or ":a" in the chat):
## fly, walk speed, and per-player tools for this server: mute, teleport to,
## bring, kill, kick, plus an announcement. The server checks the owner role
## for everything that touches other players.

var game: Node
var muted: Array = []
var _card: PanelContainer
var _list: VBoxContainer
var _fly: Button
var _speed: HSlider
var _speed_label: Label
var _announce: LineEdit


func _ready() -> void:
	layer = 45
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI.theme
	add_child(root)
	var vp := root.get_viewport_rect().size
	var w := minf(460.0, vp.x - 32.0)
	_card = UI.card(20, UI.CARD, 18)
	# Pinned to the top-right corner, under the chat and camera buttons.
	_card.anchor_left = 1.0
	_card.anchor_right = 1.0
	_card.offset_left = -w - 16.0
	_card.offset_right = -16.0
	_card.offset_top = 96.0
	_card.anchor_bottom = 1.0
	_card.offset_bottom = -16.0
	root.add_child(_card)
	var v := UI.vbox(10)
	_card.add_child(v)

	var head := UI.hbox(8)
	var title := UI.label(L.t("adm_title"), 22, UI.TEXT, "black")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := UI.button("✕", "ghost", 40)
	close.custom_minimum_size.x = 44
	close.pressed.connect(func(): visible = false)
	head.add_child(close)
	v.add_child(head)

	# Me: flying and speed.
	var row := UI.hbox(8)
	_fly = UI.button(L.t("adm_fly"), "ghost", 44)
	_fly.toggle_mode = true
	_fly.toggled.connect(func(on: bool):
		game.player.flying = on
		_fly.theme_type_variation = "" if not on else "ChipButton")
	row.add_child(_fly)
	_speed_label = UI.label("", 14, UI.MUTED, "bold")
	_speed_label.custom_minimum_size.x = 110
	row.add_child(_speed_label)
	_speed = HSlider.new()
	_speed.min_value = 0
	_speed.max_value = 80
	_speed.step = 1
	_speed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speed.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_speed.value_changed.connect(func(val: float):
		game.player.admin_speed = val
		_speed_label.text = L.t("adm_speed", [int(val)]) if val > 0 else L.t("adm_speed_normal"))
	row.add_child(_speed)
	v.add_child(row)
	_speed_label.text = L.t("adm_speed_normal")
	var hint := UI.label(L.t("adm_fly_hint"), 12, UI.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)

	# Everyone else on this server.
	v.add_child(UI.label(L.t("adm_players"), 15, UI.MUTED, "bold"))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	_list = UI.vbox(6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list)

	var send_row := UI.hbox(6)
	_announce = LineEdit.new()
	_announce.placeholder_text = L.t("adm_announce")
	_announce.max_length = 200
	_announce.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_announce.text_submitted.connect(func(_t): _send_announce())
	send_row.add_child(_announce)
	var send := UI.button(L.t("adm_send"), "primary", 44)
	send.pressed.connect(_send_announce)
	send_row.add_child(send)
	v.add_child(send_row)
	visibility_changed.connect(func():
		if visible:
			refresh()
			game.net.send({"t": "admin", "cmd": "state"}))
	refresh()


func toggle() -> void:
	visible = not visible
	if not visible:
		_announce.release_focus()


func is_open() -> bool:
	return visible


## Rebuilds the player rows (on open, and when someone joins, leaves or gets muted).
func refresh() -> void:
	if _list == null or not visible:
		return
	for c in _list.get_children():
		c.queue_free()
	var ids: Array = game.users.keys().filter(func(id): return int(id) != int(game.my_id))
	if ids.is_empty():
		_list.add_child(UI.label(L.t("adm_alone"), 14, UI.MUTED))
		return
	for id in ids:
		var u: Dictionary = game.users[id]
		var box := UI.vbox(4)
		var name := UI.label("%s  @%s" % [str(u.get("display_name", "?")), str(u.get("username", ""))], 15, UI.TEXT, "bold")
		name.clip_text = true
		name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		box.add_child(name)
		var r := UI.hbox(4)
		var is_muted := int(id) in muted.map(func(x): return int(x))
		r.add_child(_small(L.t("adm_unmute") if is_muted else L.t("adm_mute"), func(): _cmd("unmute" if is_muted else "mute", id)))
		r.add_child(_small(L.t("adm_tp"), func(): _teleport_to(int(id))))
		r.add_child(_small(L.t("adm_bring"), func(): _cmd("bring", id)))
		r.add_child(_small(L.t("adm_kill"), func(): _cmd("kill", id)))
		r.add_child(_small(L.t("adm_kick"), func(): _cmd("kick", id), true))
		box.add_child(r)
		_list.add_child(box)


func _small(text: String, on_press: Callable, danger := false) -> Button:
	var b := UI.button(text, "danger" if danger else "ghost", 36)
	b.add_theme_font_size_override("font_size", 13)
	b.custom_minimum_size.x = 0
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	for st in ["normal", "hover", "pressed"]:
		var kind := b.theme_type_variation if UI.theme.has_stylebox(st, b.theme_type_variation) else &"Button"
		var sb: StyleBox = UI.theme.get_stylebox(st, kind)
		if sb:
			sb = sb.duplicate()
			sb.content_margin_left = 4
			sb.content_margin_right = 4
			b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(on_press)
	return b


func _cmd(cmd: String, id: Variant) -> void:
	game.net.send({"t": "admin", "cmd": cmd, "id": int(id)})


func _teleport_to(id: int) -> void:
	var rp: Node3D = game.remotes.get(id)
	if rp == null:
		return
	game.player.global_position = rp.global_position + Vector3(1.5, 0.5, 0)
	game.player.velocity = Vector3.ZERO
	game.player.reset_physics_interpolation()


func _send_announce() -> void:
	var t := _announce.text.strip_edges()
	if t == "":
		return
	game.net.send({"t": "admin", "cmd": "announce", "m": t})
	_announce.text = ""
	_announce.release_focus()


## The server confirmed a command.
func on_result(m: Dictionary) -> void:
	muted = m.get("muted", [])
	var k := str(m.get("ok", ""))
	if k != "state" and k != "announce":
		UI.toast(L.t("adm_done_" + k, [str(m.get("name", ""))]), "ok")
	refresh()
