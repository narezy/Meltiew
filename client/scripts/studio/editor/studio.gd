extends Control
## Meltiew Studio: build places, script them in Luau, test and publish.
## Made for computers (mouse + keyboard); works on phones with a warning.
## Layout: top bar | Explorer | 3D view (or script tabs) + Output | Properties.

const AUTOSAVE_SEC := 120.0
const SNAPS := [0.0, 0.25, 0.5, 1.0, 2.0]
const DESKTOP_DENSITY := 0.78
const MOBILE_DENSITY := 0.85

var doc := EditDoc.new()
var place_id := ""
var explorer: StudioExplorer
var props: StudioProperties
var view: StudioViewport
var scripts: StudioScriptEditor
var gui_layer: GuiEditLayer
var assets: StudioAssets
var strings_ed: StudioStrings
var settings: StudioSettings
var output: RichTextLabel

var _title: Label
var _status: Label
var _tool_buttons := {}
var _ui_button: Button
var _center_tabs: TabBar
var _view_holder: Control
var _modal_layer: Control
var _checker: RefCounted
var _autosave := AUTOSAVE_SEC
var _saving := false
var _menus := {}


func _ready() -> void:
	# A pro tool: denser than the rest of the app on a PC screen.
	UI.apply_ui_scale()
	get_tree().root.content_scale_factor *= MOBILE_DENSITY if OS.has_feature("mobile") else DESKTOP_DENSITY
	var bg := ColorRect.new()
	bg.color = Color("#141219")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := UI.vbox(0)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(_build_top_bar())

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	explorer = StudioExplorer.new()
	explorer.custom_minimum_size.x = 250
	explorer.setup(doc)
	split.add_child(_panel(explorer))
	var right_split := HSplitContainer.new()
	right_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right_split)

	var center := VSplitContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_split.add_child(center)
	var center_top := UI.vbox(0)
	center_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(center_top)
	_center_tabs = TabBar.new()
	_center_tabs.add_tab(L.t("st_place_tab"))
	_center_tabs.tab_changed.connect(_on_center_tab)
	# Script tabs get a close button; the Place tab stays put.
	_center_tabs.tab_button_pressed.connect(func(i):
		var sid: Variant = _center_tabs.get_tab_metadata(i)
		if sid is String and sid != "":
			scripts.close_script(sid))
	center_top.add_child(_center_tabs)
	_view_holder = Control.new()
	_view_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view_holder.clip_contents = true
	center_top.add_child(_view_holder)
	view = StudioViewport.new()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.setup(doc)
	view.status.connect(func(t): _status.text = t)
	_view_holder.add_child(view)
	gui_layer = GuiEditLayer.new()
	gui_layer.setup(doc)
	gui_layer.visible = false
	_view_holder.add_child(gui_layer)
	scripts = StudioScriptEditor.new()
	scripts.set_anchors_preset(Control.PRESET_FULL_RECT)
	scripts.setup(doc)
	scripts.visible = false
	scripts.closed.connect(_on_script_closed)
	_view_holder.add_child(scripts)

	var out_box := UI.vbox(4)
	out_box.custom_minimum_size.y = 120
	var out_head := UI.hbox(8)
	out_head.add_child(UI.label(L.t("st_output"), 15, UI.TEXT, "black"))
	out_head.add_child(UI.spacer())
	var clear := UI.button(L.t("st_clear"), "flat", 28)
	clear.add_theme_font_size_override("font_size", 13)
	clear.pressed.connect(func(): output.text = "")
	out_head.add_child(clear)
	out_box.add_child(out_head)
	output = RichTextLabel.new()
	output.bbcode_enabled = true
	output.scroll_following = true
	output.selection_enabled = true
	output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	output.add_theme_font_size_override("normal_font_size", 14)
	out_box.add_child(output)
	center.add_child(_panel(out_box))

	props = StudioProperties.new()
	props.custom_minimum_size.x = 380
	props.setup(doc)
	props.open_script.connect(open_script)
	props.pick_asset.connect(func(done): assets.open(done))
	right_split.add_child(_panel(props))
	explorer.open_script.connect(open_script)
	explorer.insert_requested.connect(func(c, parent): insert(c, parent))

	var status_bar := UI.hbox(10)
	status_bar.custom_minimum_size.y = 26
	_status = UI.label("", 13, UI.MUTED)
	status_bar.add_child(_status)
	status_bar.add_child(UI.spacer())
	status_bar.add_child(UI.label(L.t("st_hint_camera"), 13, UI.MUTED))
	root.add_child(status_bar)

	# Floating panels (images, translations, settings).
	_modal_layer = CenterContainer.new()
	_modal_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_modal_layer)
	assets = StudioAssets.new()
	assets.visible = false
	_modal_layer.add_child(assets)
	strings_ed = StudioStrings.new()
	strings_ed.setup(doc)
	strings_ed.visible = false
	_modal_layer.add_child(strings_ed)
	settings = StudioSettings.new()
	settings.setup(doc)
	settings.visible = false
	settings.capture = func(): return view.vp.get_texture().get_image()
	settings.save_requested.connect(func():
		await save()
		settings.visible = false)
	_modal_layer.add_child(settings)

	doc.dirty_changed.connect(func(_d): _update_title())
	doc.selection_changed.connect(_on_selection)
	if ClassDB.class_exists("LuauVM"):
		_checker = ClassDB.instantiate("LuauVM")
		_checker.open(16)
		_checker.run("=runtime", FileAccess.get_file_as_string(PlaceHost.RUNTIME_PATH))
	_set_tool("move")
	_open_place()
	if OS.has_feature("mobile"):
		await get_tree().process_frame
		await UI.confirm(self, L.t("st_mobile_title"), L.t("st_mobile_text"), L.t("st_continue"))


func _exit_tree() -> void:
	UI.apply_ui_scale()


func _panel(child: Control) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1b1824")
	sb.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", sb)
	child.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.add_child(child)
	return p


# --- top bar -------------------------------------------------------------------------

func _build_top_bar() -> Control:
	var bar := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1f1b2a")
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.border_width_bottom = 1
	sb.border_color = UI.LINE
	bar.add_theme_stylebox_override("panel", sb)
	var h := UI.hbox(6)
	bar.add_child(h)
	# Menus and tools scroll sideways on narrow screens; Test/Publish/Save stay put.
	var strip := ScrollContainer.new()
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	strip.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	h.add_child(strip)
	var left := UI.hbox(6)
	strip.add_child(left)
	var mark := TextureRect.new()
	mark.texture = load("res://assets/logo_mark.png")
	mark.custom_minimum_size = Vector2(30, 30)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	left.add_child(mark)
	left.add_child(UI.label("studio", 18, UI.ACCENT, "black"))
	_title = UI.label("", 16, UI.TEXT, "bold")
	_title.custom_minimum_size.x = 140
	_title.clip_text = true
	left.add_child(_title)

	left.add_child(_menu("file", L.t("st_file"), [
		[L.t("st_save") + "   Ctrl+S", func(): save()],
		[L.t("st_export"), _export],
		[L.t("st_import"), _import],
		[],
		[L.t("st_close"), _close],
	]))
	left.add_child(_menu("edit", L.t("st_edit"), [
		[L.t("st_undo") + "   Ctrl+Z", doc.undo],
		[L.t("st_redo") + "   Ctrl+Y", doc.redo],
		[],
		[L.t("st_duplicate") + "   Ctrl+D", doc.duplicate_selection],
		[L.t("st_copy") + "   Ctrl+C", doc.copy_selection],
		[L.t("st_paste") + "   Ctrl+V", func(): doc.paste(_paste_target())],
		[L.t("st_delete") + "   Del", doc.delete_selection],
		[],
		[L.t("st_group") + "   Ctrl+G", doc.group_selection],
		[L.t("st_ungroup"), func(): doc.ungroup(doc.primary())],
	]))
	left.add_child(_insert_menu())
	left.add_child(_menu("place", L.t("st_place"), [
		[L.t("st_images"), func(): assets.open()],
		[L.t("st_strings"), func(): strings_ed.open()],
		[L.t("st_settings"), _open_settings],
	]))
	left.add_child(VSeparator.new())
	for t in [["select", "pointer", "1"], ["move", "move", "2"], ["scale", "scale", "3"], ["rotate", "rotate", "4"]]:
		var b := UI.button(L.t("st_tool_" + t[0]), "flat", 34)
		b.theme_type_variation = "ChipButton"
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 14)
		b.tooltip_text = L.t("st_tool_" + t[0]) + " (" + t[2] + ")"
		b.pressed.connect(func(): _set_tool(t[0]))
		left.add_child(b)
		_tool_buttons[t[0]] = b
	var snap := OptionButton.new()
	for i in SNAPS.size():
		snap.add_item(L.t("st_snap_off") if SNAPS[i] == 0.0 else L.t("st_snap", [SNAPS[i]]), i)
	snap.select(2)
	snap.item_selected.connect(func(i):
		view.snap = SNAPS[i] > 0.0
		view.move_snap = SNAPS[i])
	snap.add_theme_font_size_override("font_size", 14)
	left.add_child(snap)
	_ui_button = UI.button("UI", "flat", 34)
	_ui_button.theme_type_variation = "ChipButton"
	_ui_button.toggle_mode = true
	_ui_button.tooltip_text = L.t("st_ui_mode")
	_ui_button.add_theme_font_size_override("font_size", 14)
	_ui_button.toggled.connect(func(on): gui_layer.visible = on)
	left.add_child(_ui_button)
	var test := UI.button("▶ " + L.t("st_test"), "mint", 36)
	test.add_theme_font_size_override("font_size", 15)
	test.pressed.connect(play_test)
	h.add_child(test)
	var publish := UI.button(L.t("st_publish"), "primary", 36)
	publish.add_theme_font_size_override("font_size", 15)
	publish.pressed.connect(_open_settings)
	h.add_child(publish)
	var save_b := UI.button(L.t("st_save"), "ghost", 36)
	save_b.add_theme_font_size_override("font_size", 15)
	save_b.pressed.connect(func(): save())
	h.add_child(save_b)
	return bar


func _menu(key: String, title: String, items: Array) -> MenuButton:
	var mb := MenuButton.new()
	mb.text = title
	mb.flat = true
	mb.add_theme_font_size_override("font_size", 15)
	mb.add_theme_color_override("font_color", UI.TEXT)
	mb.add_theme_color_override("font_hover_color", UI.ACCENT)
	mb.add_theme_color_override("font_pressed_color", UI.ACCENT)
	var pm := mb.get_popup()
	pm.add_theme_font_size_override("font_size", 15)
	var actions: Array = []
	for it in items:
		if it.is_empty():
			pm.add_separator()
			continue
		pm.add_item(it[0], actions.size())
		actions.append(it[1])
	pm.id_pressed.connect(func(i): actions[i].call())
	_menus[key] = mb
	return mb


func _insert_menu() -> MenuButton:
	var mb := MenuButton.new()
	mb.text = L.t("st_insert")
	mb.flat = true
	mb.add_theme_font_size_override("font_size", 15)
	mb.add_theme_color_override("font_color", UI.TEXT)
	mb.add_theme_color_override("font_hover_color", UI.ACCENT)
	mb.add_theme_color_override("font_pressed_color", UI.ACCENT)
	var pm := mb.get_popup()
	pm.add_theme_font_size_override("font_size", 15)
	var cats := StudioSchema.creatable()
	var names: Array = []
	for cat in ["3D", "GUI", "Script", "Logic"]:
		if not cats.has(cat):
			continue
		pm.add_separator(cat)
		for c in cats[cat]:
			pm.add_icon_item(StudioExplorer.icon_for(c), c, names.size())
			names.append(c)
	pm.id_pressed.connect(func(i): insert(names[i]))
	return mb


func _update_title() -> void:
	_title.text = str(doc.meta.get("name", "")) + (" •" if doc.dirty else "")


func _set_tool(t: String) -> void:
	view.tool = t
	for k in _tool_buttons:
		_tool_buttons[k].button_pressed = k == t


# --- opening and saving ------------------------------------------------------------

func _open_place() -> void:
	place_id = Session.studio_place_id
	settings.place_id = place_id
	# Back from a play test: continue with the unsaved state.
	if not Session.studio_marp.is_empty():
		_load(Session.studio_marp)
		doc._set_dirty(Session.get_meta("studio_dirty", false))
		Session.studio_marp = {}
		for line in Session.get_meta("test_output", []):
			log_line(line)
		Session.set_meta("test_output", [])
		return
	_status.text = L.t("loading")
	var r := await Api.request("GET", "/api/studio/places/" + place_id)
	if not r.ok:
		log_line({"level": "error", "msg": r.message})
		return
	_load(r.data.marp if r.data.marp is Dictionary else {})
	_status.text = ""


func _load(marp: Dictionary) -> void:
	doc.load_marp(marp)
	explorer.rebind()
	props.rebind()
	view.rebind()
	gui_layer.rebind()
	scripts.rebind()
	doc.tree.changed.connect(_on_tree_changed)
	_update_title()
	var ws := doc.tree.service("Workspace")
	if ws != "":
		explorer._collapsed[ws] = false


func save() -> bool:
	if _saving or place_id == "":
		return false
	scripts._commit()
	_saving = true
	_status.text = L.t("saving")
	var r := await Api.request("PUT", "/api/studio/places/" + place_id, {"marp": doc.to_marp()})
	_saving = false
	_autosave = AUTOSAVE_SEC
	if r.ok:
		doc.mark_saved()
		_status.text = L.t("st_saved_at", [Time.get_time_string_from_system().substr(0, 5)])
		return true
	log_line({"level": "error", "msg": r.message})
	_status.text = ""
	return false


func _process(delta: float) -> void:
	if doc.dirty and not _saving:
		_autosave -= delta
		if _autosave <= 0.0:
			save()


func _close() -> void:
	if doc.dirty:
		if await UI.confirm(self, L.t("st_unsaved_q"), L.t("st_unsaved_text"), L.t("st_save")):
			if not await save():
				return
	Session.studio_place_id = ""
	UI.goto("res://scenes/main_menu.tscn")


func _export() -> void:
	scripts._commit()
	var data := JSON.stringify(doc.to_marp(), "\t").to_utf8_buffer()
	var name := str(doc.meta.get("name", "place")).validate_filename() + ".marp"
	StudioFiles.save_file(name, ["*.marp ; Meltiew place"], data, func(path): log_line({"level": "info", "msg": L.t("st_exported", [path])}))


## Imports a .marp file as a new place in your list and opens it.
func _import() -> void:
	StudioFiles.open_file(["*.marp ; Meltiew place"], func(path: String, bytes: PackedByteArray):
		var marp: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		if not (marp is Dictionary and marp.get("format") == "marp"):
			UI.toast(L.t("st_bad_file"), "error")
			return
		var r := await Api.request("POST", "/api/studio/places", {"name": str(marp.get("meta", {}).get("name", path.get_file().get_basename())), "marp": marp})
		if not r.ok:
			UI.toast(r.message, "error")
			return
		Session.studio_place_id = str(r.data.place.id)
		UI.goto("res://scenes/studio.tscn"))


func _open_settings() -> void:
	scripts._commit()
	settings.open()


## Runs the place right here: server scripts in a local VM, you as the only player.
func play_test() -> void:
	scripts._commit()
	var marp := doc.to_marp()
	Session.studio_marp = marp
	Session.set_meta("studio_dirty", doc.dirty)
	Session.test_marp = marp
	Session.pending_game = "test"
	Session.pending_server = "auto"
	UI.goto("res://scenes/game.tscn")


# --- inserting -----------------------------------------------------------------------

func _paste_target() -> String:
	var sel := doc.primary()
	return doc.tree.parent_of(sel) if sel != "" else doc.tree.service("Workspace")


func _selected_of(check: Callable) -> String:
	var sel := doc.primary()
	while sel != "" and sel != PlaceTree.ROOT:
		if check.call(sel):
			return sel
		sel = doc.tree.parent_of(sel)
	return ""


## Inserts an object where it makes sense: GUI into the selected frame or a ScreenGui,
## decorations into the selected UI object, lights into the selected part, and so on.
func insert(c: String, parent := "") -> void:
	var t := doc.tree
	var ws := t.service("Workspace")
	var p := {}
	if parent == "":
		var raw := StudioSchema.raw(c)
		var cat := str(raw.get("category", ""))
		var gui_parent := _selected_of(func(i): return StudioSchema.is_a(t.cls(i), "GuiObject") or t.cls(i) == "ScreenGui")
		match c:
			"ScreenGui":
				parent = t.service("StarterGui")
			"UICorner", "UIStroke", "UIPadding", "UIListLayout", "UIGridLayout":
				parent = _selected_of(func(i): return StudioSchema.is_a(t.cls(i), "GuiObject"))
				if parent == "":
					UI.toast(L.t("st_need_gui"), "error")
					return
			"PointLight", "ClickDetector":
				parent = _selected_of(func(i): return StudioSchema.is_a(t.cls(i), "BasePart"))
				if parent == "":
					UI.toast(L.t("st_need_part"), "error")
					return
			"Sky":
				parent = t.service("Lighting")
				var old := t.child_of_class(parent, "Sky")
				if old != "":
					doc.select([old])
					return
			"Script":
				parent = doc.primary() if doc.primary() != "" and not t.is_a(doc.primary(), "LuaSourceContainer") else t.service("ServerScriptService")
			"LocalScript":
				parent = gui_parent if gui_parent != "" else t.child_of_class(t.service("StarterPlayer"), "StarterPlayerScripts")
			"ModuleScript", "RemoteEvent", "RemoteFunction", "BindableEvent":
				parent = t.service("ReplicatedStorage")
			_:
				if cat == "GUI":
					parent = gui_parent
					if parent == "":
						parent = t.child_of_class(t.service("StarterGui"), "ScreenGui")
					if parent == "":
						parent = doc.insert("ScreenGui", t.service("StarterGui"))
				else:
					parent = _selected_of(func(i): return t.cls(i) in ["Model", "Folder"] and t.is_descendant(i, ws))
					if parent == "":
						parent = ws
		if cat == "GUI" and c != "ScreenGui":
			_ui_button.button_pressed = true
	if StudioSchema.info(c).props.has("Position") and StudioSchema.info(c).props.get("Position", {}).get("type") == "Vector3":
		var at := view.insert_point()
		var size: Variant = StudioSchema.default_of(c, "Size")
		var h: float = size.y / 2.0 if size is Vector3 else 1.0
		p["Position"] = Vector3(snappedf(at.x, 0.5), snappedf(at.y + h, 0.25), snappedf(at.z, 0.5))
	var id := doc.insert(c, parent, p)
	if StudioSchema.is_a(c, "LuaSourceContainer"):
		open_script(id)


# --- scripts & output -----------------------------------------------------------------

func open_script(id: String) -> void:
	if not doc.tree.is_a(id, "LuaSourceContainer"):
		return
	scripts.open_script(id)
	var name := doc.tree.name_of(id)
	var idx := -1
	for i in _center_tabs.tab_count:
		if _center_tabs.get_tab_metadata(i) == id:
			idx = i
	if idx < 0:
		_center_tabs.add_tab(name)
		idx = _center_tabs.tab_count - 1
		_center_tabs.set_tab_metadata(idx, id)
		_center_tabs.set_tab_button_icon(idx, _center_tabs.get_theme_icon("close", "TabBar"))
	_center_tabs.current_tab = idx
	_on_center_tab(idx)


func _on_center_tab(i: int) -> void:
	var id: Variant = _center_tabs.get_tab_metadata(i)
	var on_script: bool = id is String and id != ""
	scripts.visible = on_script
	view.visible = not on_script
	gui_layer.visible = not on_script and _ui_button.button_pressed
	if on_script:
		scripts.open_script(id)


func _on_script_closed(id: String) -> void:
	for i in _center_tabs.tab_count:
		if _center_tabs.get_tab_metadata(i) == id:
			_center_tabs.remove_tab(i)
			break
	_center_tabs.current_tab = 0
	_on_center_tab(0)


func _on_tree_changed(id: String, key: String) -> void:
	if key == "Source" and _checker:
		var err: String = _checker.call_function("__check", str(doc.tree.prop(id, "Source")), 1.0)
		if err != "":
			log_line({"level": "error", "msg": err.replace("script:", doc.tree.full_name(id) + ":"), "src": ""})
	if key == "Name":
		for i in _center_tabs.tab_count:
			if _center_tabs.get_tab_metadata(i) == id:
				_center_tabs.set_tab_title(i, doc.tree.name_of(id))
	if key == "Name" or key == "" or id == doc.tree.service("Workspace"):
		_update_title()


func _on_selection() -> void:
	var id := doc.primary()
	if id != "" and (StudioSchema.is_a(doc.tree.cls(id), "GuiObject") or doc.tree.cls(id) == "ScreenGui"):
		_ui_button.button_pressed = true


func log_line(line: Dictionary) -> void:
	var color: String = {"error": "#ff6b7a", "warn": "#ffd166"}.get(str(line.get("level", "")), "#e8e4f2")
	var src := str(line.get("src", ""))
	var t := Time.get_time_string_from_system().substr(0, 8)
	output.append_text("[color=#6f6a85]%s[/color] %s[color=%s]%s[/color]\n" % [t, ("[color=#9d96b0]" + src.replace("[", "[lb]") + "[/color]  ") if src != "" else "", color, str(line.get("msg", "")).replace("[", "[lb]")])


# --- keyboard ------------------------------------------------------------------------

func _shortcut_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	var typing := get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is TextEdit
	var k: int = e.keycode
	if e.ctrl_pressed or e.meta_pressed:
		match k:
			KEY_S:
				save()
			KEY_Z:
				if not typing:
					doc.undo()
				else:
					return
			KEY_Y:
				if not typing:
					doc.redo()
				else:
					return
			KEY_D:
				doc.duplicate_selection()
			KEY_C:
				if typing:
					return
				doc.copy_selection()
			KEY_V:
				if typing:
					return
				doc.paste(_paste_target())
			KEY_G:
				doc.group_selection()
			_:
				return
		get_viewport().set_input_as_handled()
		return
	if typing:
		return
	match k:
		KEY_DELETE, KEY_BACKSPACE:
			doc.delete_selection()
		KEY_1:
			_set_tool("select")
		KEY_2:
			_set_tool("move")
		KEY_3:
			_set_tool("scale")
		KEY_4:
			_set_tool("rotate")
		KEY_F:
			view.focus_selection()
		KEY_F5:
			play_test()
		_:
			return
	get_viewport().set_input_as_handled()
