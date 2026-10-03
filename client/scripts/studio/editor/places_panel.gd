class_name StudioPlacesPanel
extends VBoxContainer
## Places of this game (like Roblox's Asset Manager > Places): the main place and its
## sub-places. Double-click one to edit it (what's open now is saved first), + makes a new
## one, right-click to rename, copy its id (for TeleportService) or delete it. They all
## share the main place's DataStores, badges, passes and settings.

signal open_requested(id: String)
signal changed  # a place was made, renamed or deleted

var current := ""  # the place open in the editor
var game := {}  # { id, name, places: [{ id, name, main }] }
var _list: ItemList
var _menu: PopupMenu
var _menu_id := ""


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var head := UI.hbox(8)
	var title := UI.label(L.t("st_places_title"), 17, UI.TEXT, "black")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var add := UI.button("+", "flat", 30)
	add.custom_minimum_size.x = 34
	add.tooltip_text = L.t("st_places_new")
	add.pressed.connect(_new_place)
	head.add_child(add)
	add_child(head)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_theme_font_size_override("font_size", 15)
	_list.allow_rmb_select = true
	_list.item_activated.connect(func(i): _open(str(_list.get_item_metadata(i))))
	_list.item_clicked.connect(func(i, _at, button):
		if button == MOUSE_BUTTON_RIGHT:
			_menu_id = str(_list.get_item_metadata(i))
			_menu.position = Vector2i(get_global_mouse_position()) + get_window().position
			_menu.popup())
	add_child(_list)
	var hint := UI.label(L.t("st_places_hint"), 13, UI.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	_menu = PopupMenu.new()
	_menu.add_theme_font_size_override("font_size", 15)
	_menu.add_item(L.t("st_places_open"), 0)
	_menu.add_item(L.t("st_places_copy_id"), 1)
	_menu.add_item(L.t("st_rename"), 2)
	_menu.add_separator()
	_menu.add_item(L.t("st_delete"), 3)
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)


func set_game(g: Dictionary, current_id: String) -> void:
	game = g
	current = current_id
	_refresh()


func _refresh() -> void:
	if _list == null:
		return
	_list.clear()
	for p: Dictionary in game.get("places", []):
		var name := str(p.name)
		var label := ("★ " if p.get("main", false) else "    ⤷ ") + name
		var i := _list.add_item(label)
		_list.set_item_metadata(i, str(p.id))
		_list.set_item_tooltip(i, "%s\n%s" % [name, p.id])
		if str(p.id) == current:
			_list.set_item_custom_bg_color(i, Color(UI.ACCENT, 0.22))
			_list.set_item_text(i, label + "   ✎")


func _open(id: String) -> void:
	if id != current:
		open_requested.emit(id)


func _on_menu(item: int) -> void:
	var p := _place(_menu_id)
	if p.is_empty():
		return
	match item:
		0:
			_open(_menu_id)
		1:
			DisplayServer.clipboard_set(_menu_id)
			UI.toast(L.t("st_places_copied", [_menu_id]), "ok")
		2:
			_rename(p)
		3:
			_delete(p)


func _place(id: String) -> Dictionary:
	for p: Dictionary in game.get("places", []):
		if str(p.id) == id:
			return p
	return {}


func _new_place() -> void:
	var name: String = await _ask(L.t("st_places_new"), L.t("st_places_name_hint", [game.get("places", []).size()]))
	if name == "":
		return
	var r := await Api.request("POST", "/api/studio/places/%s/subplaces" % game.get("id", current), {"name": name})
	if not r.ok:
		UI.toast(r.message, "error")
		return
	game = r.data.place.get("game", game)
	_refresh()
	changed.emit()
	# Straight in, like opening a new place.
	if await UI.confirm(self, L.t("st_places_made", [name]), L.t("st_places_made_text"), L.t("st_places_open")):
		open_requested.emit(str(r.data.place.id))


func _rename(p: Dictionary) -> void:
	var name: String = await _ask(L.t("st_rename"), str(p.name), str(p.name))
	if name == "" or name == str(p.name):
		return
	var r := await Api.request("PATCH", "/api/studio/places/" + str(p.id), {"name": name})
	if not r.ok:
		UI.toast(r.message, "error")
		return
	game = r.data.place.get("game", game)
	_refresh()
	changed.emit()


func _delete(p: Dictionary) -> void:
	if p.get("main", false):
		UI.toast(L.t("st_places_main_stays"), "error")
		return
	if str(p.id) == current:
		UI.toast(L.t("st_places_open_one"), "error")
		return
	if not await UI.confirm(self, L.t("st_places_delete_q", [p.name]), L.t("st_places_delete_text"), L.t("st_delete"), true):
		return
	var r := await Api.request("DELETE", "/api/studio/places/" + str(p.id))
	if not r.ok:
		UI.toast(r.message, "error")
		return
	game.places = game.get("places", []).filter(func(x): return str(x.id) != str(p.id))
	_refresh()
	changed.emit()


## A one-line question with a text field; "" when cancelled.
func _ask(title: String, placeholder: String, initial := "") -> String:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.theme = UI.theme
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var c := UI.card(24, UI.CARD, 22)
	c.custom_minimum_size.x = 420
	center.add_child(c)
	var v := UI.vbox(14)
	c.add_child(v)
	v.add_child(UI.label(title, 22, UI.TEXT, "black"))
	var field := UI.input(placeholder)
	field.text = initial
	field.max_length = 60
	v.add_child(field)
	var row := UI.hbox(10)
	v.add_child(row)
	var no := UI.button(L.t("cancel"), "ghost")
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var yes := UI.button(L.t("st_ok"), "primary")
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(no)
	row.add_child(yes)
	var result := [""]
	var done := [false]
	dim.set_meta("on_back", func(): done[0] = true)
	no.pressed.connect(func(): done[0] = true)
	var ok := func():
		result[0] = field.text.strip_edges()
		done[0] = true
	yes.pressed.connect(ok)
	field.text_submitted.connect(func(_t): ok.call())
	field.grab_focus.call_deferred()
	field.select_all.call_deferred()
	while not done[0]:
		await get_tree().process_frame
	layer.queue_free()
	return result[0]
