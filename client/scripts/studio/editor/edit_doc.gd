class_name EditDoc
extends RefCounted
## The place being edited in Studio: its PlaceTree, selection, clipboard and
## undo/redo. Every change goes through here so it can be undone.

signal selection_changed
signal history_changed
signal dirty_changed(dirty: bool)

var tree := PlaceTree.new()
var meta := {"name": "Untitled", "description": "", "i18n": {"name": {}, "description": {}}}
var strings := {}
var selection: Array = []
var dirty := false

var _undo: Array = []
var _redo: Array = []
var _next := 1
var _batch: Array = []
var _batching := 0
var _clipboard: Array = []


func load_melt(melt: Dictionary) -> void:
	tree = PlaceTree.new()
	tree.load_melt_tree(melt.get("tree", {}), "e")
	_next = tree.nodes.size() + 1
	meta = melt.get("meta", meta)
	if not meta.has("i18n"):
		meta["i18n"] = {"name": {}, "description": {}}
	strings = melt.get("strings", {})
	# Places made before a service existed (StarterPack...) get it now.
	for svc in StudioSchema.services():
		if tree.service(svc) == "":
			tree.create(new_id(), svc, svc, PlaceTree.ROOT)
	selection.clear()
	_undo.clear()
	_redo.clear()
	_set_dirty(false)


func to_melt() -> Dictionary:
	return {"format": "melt", "version": 1, "meta": meta, "strings": strings, "tree": tree.to_melt_tree()}


func new_id() -> String:
	while tree.has("e%d" % _next):
		_next += 1
	var id := "e%d" % _next
	_next += 1
	return id


func _set_dirty(v: bool) -> void:
	if dirty != v:
		dirty = v
		dirty_changed.emit(v)


func mark_saved() -> void:
	_set_dirty(false)


# --- undo/redo ---------------------------------------------------------------------
# Each record is {"do": Callable, "undo": Callable, "label": String}.

func _record(label: String, do_fn: Callable, undo_fn: Callable) -> void:
	do_fn.call()
	var rec := {"do": do_fn, "undo": undo_fn, "label": label}
	if _batching > 0:
		_batch.append(rec)
	else:
		_undo.append(rec)
		if _undo.size() > 300:
			_undo.pop_front()
		_redo.clear()
		history_changed.emit()
	_set_dirty(true)


## Groups several changes into one undo step (e.g. moving five parts at once).
func begin_batch() -> void:
	_batching += 1


func end_batch(label: String) -> void:
	_batching -= 1
	if _batching > 0 or _batch.is_empty():
		return
	var recs := _batch.duplicate()
	_batch.clear()
	_undo.append({
		"do": func():
			for r in recs:
				r.do.call(),
		"undo": func():
			for i in range(recs.size() - 1, -1, -1):
				recs[i].undo.call(),
		"label": label,
	})
	_redo.clear()
	history_changed.emit()


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo() -> void:
	if _undo.is_empty():
		return
	var r: Dictionary = _undo.pop_back()
	r.undo.call()
	_redo.append(r)
	_prune_selection()
	history_changed.emit()
	_set_dirty(true)


func redo() -> void:
	if _redo.is_empty():
		return
	var r: Dictionary = _redo.pop_back()
	r.do.call()
	_undo.append(r)
	_prune_selection()
	history_changed.emit()
	_set_dirty(true)


# --- snapshots (for delete / paste / undo) ---------------------------------------

func snapshot(id: String) -> Dictionary:
	var n: Dictionary = tree.node(id)
	var ks: Array = []
	for k in n.kids:
		ks.append(snapshot(k))
	return {"id": id, "c": n.c, "n": n.n, "props": n.props.duplicate(true), "kids": ks, "index": tree.kids(n.parent).find(id)}


func _restore(snap: Dictionary, parent: String) -> void:
	# Already-decoded values pass through SValue.decode unchanged.
	tree.create(snap.id, snap.c, snap.n, parent, snap.props.duplicate(true))
	var idx := int(snap.get("index", -1))
	var list: Array = tree.nodes[parent].kids
	if idx >= 0 and idx < list.size() - 1:
		list.erase(snap.id)
		list.insert(idx, snap.id)
	for k in snap.kids:
		_restore(k, snap.id)


## Fresh ids for a pasted/duplicated copy.
func _reid(snap: Dictionary) -> Dictionary:
	var out := snap.duplicate(true)
	out.id = new_id()
	out.index = -1
	var ks: Array = []
	for k in snap.kids:
		ks.append(_reid(k))
	out.kids = ks
	return out


# --- edits ---------------------------------------------------------------------------

func set_prop(id: String, key: String, value: Variant) -> void:
	if not tree.has(id):
		return
	var old: Variant = tree.prop(id, key)
	if old == value:
		return
	if key == "Name":
		_record("Rename", func(): tree.rename(id, str(value)), func(): tree.rename(id, str(old)))
	else:
		_record("Change " + key, func(): tree.set_prop(id, key, value), func(): tree.set_prop(id, key, old))


func insert(c: String, parent: String, props: Dictionary = {}, name := "") -> String:
	var id := new_id()
	var n := name if name != "" else c
	_record("Insert " + c, func(): tree.create(id, c, n, parent, props.duplicate(true)), func(): tree.remove(id))
	select([id])
	return id


func delete_selection() -> void:
	var ids := _top_level(selection.filter(func(i): return _deletable(i)))
	if ids.is_empty():
		return
	begin_batch()
	for id in ids:
		var snap := snapshot(id)
		var parent := tree.parent_of(id)
		_record("Delete", func(): tree.remove(id), func(): _restore(snap, parent))
	end_batch("Delete")
	select([])


func duplicate_selection() -> void:
	var ids := _top_level(selection.filter(func(i): return _deletable(i)))
	var made: Array = []
	begin_batch()
	for id in ids:
		var copy := _reid(snapshot(id))
		var parent := tree.parent_of(id)
		_record("Duplicate", func(): _restore(copy, parent), func(): tree.remove(copy.id))
		made.append(copy.id)
	end_batch("Duplicate")
	select(made)


func copy_selection() -> void:
	_clipboard = []
	for id in _top_level(selection.filter(func(i): return _deletable(i))):
		_clipboard.append(snapshot(id))


func paste(into: String) -> void:
	if _clipboard.is_empty() or not tree.has(into):
		return
	var made: Array = []
	begin_batch()
	for snap in _clipboard:
		var copy := _reid(snap)
		_record("Paste", func(): _restore(copy, into), func(): tree.remove(copy.id))
		made.append(copy.id)
	end_batch("Paste")
	select(made)


func move(id: String, new_parent: String) -> void:
	var old := tree.parent_of(id)
	if old == new_parent or not _deletable(id) or id == new_parent or tree.is_descendant(new_parent, id):
		return
	_record("Move", func(): tree.move(id, new_parent), func(): tree.move(id, old))


## Puts the selection into a new Model (Ctrl+G).
func group_selection() -> void:
	var ids := _top_level(selection.filter(func(i): return _deletable(i)))
	if ids.is_empty():
		return
	var parent := tree.parent_of(ids[0])
	begin_batch()
	var model := new_id()
	_record("Group", func(): tree.create(model, "Model", "Model", parent, {}), func(): tree.remove(model))
	for id in ids:
		move(id, model)
	end_batch("Group")
	select([model])


func ungroup(id: String) -> void:
	if tree.cls(id) not in ["Model", "Folder"]:
		return
	var parent := tree.parent_of(id)
	var kids := tree.kids(id).duplicate()
	begin_batch()
	for k in kids:
		move(k, parent)
	var snap := snapshot(id)
	_record("Ungroup", func(): tree.remove(id), func(): _restore(snap, parent))
	end_batch("Ungroup")
	select(kids)


# --- selection -----------------------------------------------------------------------

func select(ids: Array) -> void:
	selection = ids.filter(func(i): return tree.has(i))
	selection_changed.emit()


func toggle_select(id: String) -> void:
	if id in selection:
		selection.erase(id)
	else:
		selection.append(id)
	selection_changed.emit()


func primary() -> String:
	return selection.back() if not selection.is_empty() else ""


func _prune_selection() -> void:
	var before := selection.size()
	selection = selection.filter(func(i): return tree.has(i))
	if selection.size() != before:
		selection_changed.emit()


func _deletable(id: String) -> bool:
	if not tree.has(id) or id == PlaceTree.ROOT:
		return false
	return not (tree.parent_of(id) == PlaceTree.ROOT and StudioSchema.raw(tree.cls(id)).get("service", false))


## Drops ids whose ancestor is also in the list.
func _top_level(ids: Array) -> Array:
	return ids.filter(func(i):
		for other in ids:
			if other != i and tree.is_descendant(i, other):
				return false
		return true)
