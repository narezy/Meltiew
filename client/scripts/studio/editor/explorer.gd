class_name StudioExplorer
extends VBoxContainer
## Explorer: the place's objects as a tree. Select, rename (double-click),
## drag to reparent, right-click for Insert/Duplicate/Delete/Group.

signal open_script(id: String)

const CATEGORY_COLORS := {
	"3D": Color("#4cc9f0"), "GUI": Color("#ff8fb1"), "Script": Color("#ffd166"),
	"Logic": Color("#7ee0c3"), "Service": Color("#b89cff"),
}

var doc: EditDoc
var _tree: Tree
var _items := {}  # id -> TreeItem
var _collapsed := {}  # id -> bool
var _dirty := true
var _syncing := false
var _menu: PopupMenu
var _insert_menu: PopupMenu
var _menu_target := ""
static var _icons := {}


func setup(d: EditDoc) -> void:
	doc = d
	add_theme_constant_override("separation", 6)
	var head := UI.hbox(8)
	head.add_child(UI.label(L.t("st_explorer"), 17, UI.TEXT, "black"))
	add_child(head)
	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_MULTI
	_tree.allow_rmb_select = true
	_tree.add_theme_font_size_override("font_size", 15)
	_tree.add_theme_constant_override("v_separation", 2)
	add_child(_tree)
	_tree.multi_selected.connect(func(_i, _c, _s): _selection_from_tree.call_deferred())
	_tree.item_activated.connect(_on_activated)
	_tree.item_edited.connect(_on_edited)
	_tree.item_collapsed.connect(func(item: TreeItem): _collapsed[item.get_metadata(0)] = item.collapsed)
	_tree.item_mouse_selected.connect(func(_pos, button):
		if button == MOUSE_BUTTON_RIGHT:
			_open_menu())
	_tree.empty_clicked.connect(func(_pos, button):
		if button == MOUSE_BUTTON_LEFT:
			doc.select([]))
	_tree.set_drag_forwarding(_get_drag, _can_drop, _drop)

	_menu = PopupMenu.new()
	add_child(_menu)
	_menu.id_pressed.connect(_on_menu)
	_insert_menu = PopupMenu.new()
	_insert_menu.name = "Insert"
	_menu.add_child(_insert_menu)
	_insert_menu.id_pressed.connect(_on_insert)
	doc.selection_changed.connect(_selection_to_tree)
	_bind()


## Listens to the current tree (a new one comes with every opened place).
func _bind() -> void:
	doc.tree.added.connect(func(_id): _dirty = true)
	doc.tree.removed.connect(func(_id, _p): _dirty = true)
	doc.tree.reparented.connect(func(_id, _o): _dirty = true)
	doc.tree.changed.connect(func(id, key):
		if key == "Name" and _items.has(id):
			_items[id].set_text(0, doc.tree.name_of(id)))
	_dirty = true


## Studio swaps the whole tree when a place is opened.
func rebind() -> void:
	_items.clear()
	_collapsed.clear()
	_bind()


func _process(_d: float) -> void:
	if _dirty:
		_dirty = false
		_rebuild()


static func icon_for(c: String) -> Texture2D:
	var r := StudioSchema.raw(c)
	var cat := "Service" if r.get("service", false) else str(r.get("category", "Logic"))
	if _icons.has(cat):
		return _icons[cat]
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var col: Color = CATEGORY_COLORS.get(cat, Color("#9d96b0"))
	for y in 16:
		for x in 16:
			var d := Vector2(x - 7.5, y - 7.5)
			# A rounded square badge.
			if absf(d.x) < 6.5 and absf(d.y) < 6.5 and (absf(d.x) < 4.5 or absf(d.y) < 4.5 or d.length() < 7.0):
				img.set_pixel(x, y, col)
	_icons[cat] = ImageTexture.create_from_image(img)
	return _icons[cat]


func _rebuild() -> void:
	_syncing = true
	var scroll := _tree.get_scroll()
	_tree.clear()
	_items.clear()
	var root := _tree.create_item()
	for k in doc.tree.kids(PlaceTree.ROOT):
		_add(k, root)
	_selection_to_tree()
	_syncing = false
	await get_tree().process_frame
	# Tree keeps its scroll bar as an internal child.
	for c in _tree.get_children(true):
		if c is VScrollBar:
			c.value = scroll.y


func _add(id: String, parent: TreeItem) -> void:
	var t := doc.tree
	var item := _tree.create_item(parent)
	item.set_text(0, t.name_of(id))
	item.set_icon(0, icon_for(t.cls(id)))
	item.set_tooltip_text(0, t.cls(id))
	item.set_metadata(0, id)
	# Services start folded, except Workspace.
	var default_collapsed := parent == _tree.get_root() and t.cls(id) != "Workspace"
	item.collapsed = _collapsed.get(id, default_collapsed)
	_items[id] = item
	for k in t.kids(id):
		_add(k, item)


func _selection_to_tree() -> void:
	_syncing = true
	_tree.deselect_all()
	for id in doc.selection:
		var item: TreeItem = _items.get(id)
		if item:
			var p := item.get_parent()
			while p:
				p.collapsed = false
				p = p.get_parent()
			item.select(0)
	_syncing = false


func _selection_from_tree() -> void:
	if _syncing:
		return
	var ids: Array = []
	var it := _tree.get_next_selected(null)
	while it:
		ids.append(it.get_metadata(0))
		it = _tree.get_next_selected(it)
	doc.select(ids)


func _on_activated() -> void:
	var item := _tree.get_selected()
	if item == null:
		return
	var id: String = item.get_metadata(0)
	if StudioSchema.is_a(doc.tree.cls(id), "LuaSourceContainer"):
		open_script.emit(id)
		return
	item.set_editable(0, true)
	_tree.edit_selected(true)


func _on_edited() -> void:
	var item := _tree.get_edited()
	if item:
		item.set_editable(0, false)
		var name := item.get_text(0).strip_edges()
		if name != "":
			doc.set_prop(item.get_metadata(0), "Name", name)


# --- drag & drop -------------------------------------------------------------------

func _get_drag(_at: Vector2) -> Variant:
	var ids: Array = doc.selection.filter(func(i): return doc._deletable(i))
	if ids.is_empty():
		return null
	var l := UI.label(", ".join(ids.map(func(i): return doc.tree.name_of(i))), 15, UI.TEXT, "bold")
	_tree.set_drag_preview(l)
	return {"studio_ids": ids}


func _can_drop(at: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and data.has("studio_ids")):
		return false
	_tree.drop_mode_flags = Tree.DROP_MODE_ON_ITEM
	var item := _tree.get_item_at_position(at)
	return item != null


func _drop(at: Vector2, data: Variant) -> void:
	var item := _tree.get_item_at_position(at)
	if item == null:
		return
	var target: String = item.get_metadata(0)
	doc.begin_batch()
	for id in data.studio_ids:
		doc.move(id, target)
	doc.end_batch("Move")


# --- context menu ------------------------------------------------------------------

enum { M_RENAME, M_DUPLICATE, M_COPY, M_PASTE, M_DELETE, M_GROUP, M_UNGROUP, M_SCRIPT }


func _open_menu() -> void:
	var sel := _tree.get_selected()
	_menu_target = sel.get_metadata(0) if sel else ""
	_menu.clear()
	_insert_menu.clear()
	var cats := StudioSchema.creatable()
	var i := 0
	for cat in ["3D", "GUI", "Script", "Logic"]:
		if not cats.has(cat):
			continue
		_insert_menu.add_separator(cat)
		for c in cats[cat]:
			_insert_menu.add_icon_item(icon_for(c), c, i)
			_insert_menu.set_item_metadata(_insert_menu.get_item_index(i), c)
			i += 1
	_menu.add_submenu_node_item(L.t("st_insert"), _insert_menu)
	_menu.add_separator()
	_menu.add_item(L.t("st_rename"), M_RENAME)
	if StudioSchema.is_a(doc.tree.cls(_menu_target), "LuaSourceContainer"):
		_menu.add_item(L.t("st_edit_script"), M_SCRIPT)
	_menu.add_item(L.t("st_duplicate") + "    Ctrl+D", M_DUPLICATE)
	_menu.add_item(L.t("st_copy") + "    Ctrl+C", M_COPY)
	_menu.add_item(L.t("st_paste_into") + "    Ctrl+V", M_PASTE)
	_menu.add_item(L.t("st_group") + "    Ctrl+G", M_GROUP)
	if doc.tree.cls(_menu_target) in ["Model", "Folder"]:
		_menu.add_item(L.t("st_ungroup"), M_UNGROUP)
	_menu.add_separator()
	_menu.add_item(L.t("st_delete") + "    Del", M_DELETE)
	_menu.position = Vector2i(get_screen_transform() * get_local_mouse_position())
	_menu.reset_size()
	_menu.popup()


func _on_menu(id: int) -> void:
	match id:
		M_RENAME:
			var item: TreeItem = _items.get(_menu_target)
			if item:
				item.select(0)
				item.set_editable(0, true)
				_tree.edit_selected(true)
		M_SCRIPT:
			open_script.emit(_menu_target)
		M_DUPLICATE:
			doc.duplicate_selection()
		M_COPY:
			doc.copy_selection()
		M_PASTE:
			doc.paste(_menu_target if _menu_target != "" else doc.tree.service("Workspace"))
		M_GROUP:
			doc.group_selection()
		M_UNGROUP:
			doc.ungroup(_menu_target)
		M_DELETE:
			doc.delete_selection()


func _on_insert(i: int) -> void:
	var c: String = _insert_menu.get_item_metadata(_insert_menu.get_item_index(i))
	var parent := _menu_target if _menu_target != "" else doc.tree.service("Workspace")
	insert_requested.emit(c, parent)


signal insert_requested(c: String, parent: String)
