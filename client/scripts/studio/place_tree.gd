class_name PlaceTree
extends RefCounted
## A mirror of a place's instance tree: id -> {id, c (class), n (name), parent, props, kids}.
## The game fills it from the client VM's operations; Studio edits it directly.
## Renderers (PlaceScene for 3D, PlaceGui for UI) listen to its signals.

signal added(id: String)
signal removed(id: String, parent: String)
signal changed(id: String, key: String)
signal reparented(id: String, old_parent: String)

const ROOT := "0"

var nodes := {}


func _init() -> void:
	nodes[ROOT] = {"id": ROOT, "c": "DataModel", "n": "Game", "parent": "", "props": {}, "kids": []}


func has(id: String) -> bool:
	return nodes.has(id)


func node(id: String) -> Dictionary:
	return nodes.get(id, {})


func cls(id: String) -> String:
	return str(nodes.get(id, {}).get("c", ""))


func name_of(id: String) -> String:
	return str(nodes.get(id, {}).get("n", ""))


func parent_of(id: String) -> String:
	return str(nodes.get(id, {}).get("parent", ""))


func kids(id: String) -> Array:
	return nodes.get(id, {}).get("kids", [])


## Property value, or the class default when it was never set.
func prop(id: String, key: String) -> Variant:
	var n: Dictionary = nodes.get(id, {})
	if n.is_empty():
		return null
	if n.props.has(key):
		return n.props[key]
	return StudioSchema.default_of(n.c, key)


func is_a(id: String, base: String) -> bool:
	return StudioSchema.is_a(cls(id), base)


func is_descendant(id: String, ancestor: String) -> bool:
	var cur := parent_of(id)
	while cur != "":
		if cur == ancestor:
			return true
		cur = parent_of(cur)
	return false


## Top-level service by class name ("Workspace", "Lighting"...), or "".
func service(class_name_: String) -> String:
	for k in kids(ROOT):
		if cls(k) == class_name_:
			return k
	return ""


func child_named(id: String, name: String) -> String:
	for k in kids(id):
		if name_of(k) == name:
			return k
	return ""


func child_of_class(id: String, c: String) -> String:
	for k in kids(id):
		if cls(k) == c:
			return k
	return ""


func descendants(id: String, out: Array = []) -> Array:
	for k in kids(id):
		out.append(k)
		descendants(k, out)
	return out


func full_name(id: String) -> String:
	var parts: Array = []
	var cur := id
	while cur != "" and cur != ROOT:
		parts.push_front(name_of(cur))
		cur = parent_of(cur)
	return ".".join(parts)


# --- changes ---------------------------------------------------------------------

## Applies one operation: new / set / del / parent (same shape as the runtime's).
func apply(op: Dictionary) -> void:
	match str(op.get("o", op.get("e", ""))):
		"new":
			create(str(op.id), str(op.c), str(op.get("n", op.c)), str(op.get("parent", "")), op.get("p", {}))
		"set":
			var key := str(op.k)
			if key == "Name":
				rename(str(op.id), str(op.v))
			else:
				set_prop(str(op.id), key, SValue.decode(op.v))
		"del":
			remove(str(op.id))
		"parent":
			move(str(op.id), str(op.parent))


func create(id: String, c: String, n: String, parent: String, raw_props: Dictionary = {}) -> void:
	if nodes.has(id) or not StudioSchema.has_class(c):
		return
	var props := {}
	for k in raw_props:
		props[k] = SValue.decode(raw_props[k])
	nodes[id] = {"id": id, "c": c, "n": n, "parent": "", "props": props, "kids": []}
	if parent != "" and nodes.has(parent):
		nodes[id].parent = parent
		nodes[parent].kids.append(id)
	added.emit(id)


func set_prop(id: String, key: String, value: Variant) -> void:
	if not nodes.has(id):
		return
	nodes[id].props[key] = value
	changed.emit(id, key)


func rename(id: String, n: String) -> void:
	if not nodes.has(id):
		return
	nodes[id].n = n
	changed.emit(id, "Name")


func move(id: String, parent: String) -> void:
	if not nodes.has(id) or not nodes.has(parent) or id == parent or is_descendant(parent, id):
		return
	var old := parent_of(id)
	if old == parent:
		return
	if old != "" and nodes.has(old):
		nodes[old].kids.erase(id)
	nodes[id].parent = parent
	nodes[parent].kids.append(id)
	reparented.emit(id, old)


func remove(id: String) -> void:
	if not nodes.has(id) or id == ROOT:
		return
	for k in kids(id).duplicate():
		remove(k)
	var parent := parent_of(id)
	if parent != "" and nodes.has(parent):
		nodes[parent].kids.erase(id)
	nodes.erase(id)
	removed.emit(id, parent)


# --- place files -------------------------------------------------------------------

## Loads a .marp tree ({c, n, p, k}), giving every instance a fresh id with `prefix`.
func load_marp_tree(tree: Dictionary, prefix := "e") -> void:
	var counter := [0]
	for ch in tree.get("k", []):
		_load_node(ch, ROOT, prefix, counter)


func _load_node(n: Dictionary, parent: String, prefix: String, counter: Array) -> String:
	counter[0] += 1
	var id := "%s%d" % [prefix, counter[0]]
	create(id, str(n.get("c", "Folder")), str(n.get("n", n.get("c", ""))), parent, n.get("p", {}))
	for ch in n.get("k", []):
		_load_node(ch, id, prefix, counter)
	return id


## Serializes a subtree back to .marp form, leaving out values equal to defaults.
func to_marp_node(id: String) -> Dictionary:
	var n: Dictionary = nodes[id]
	var out := {"c": n.c, "n": n.n}
	var props := {}
	for k in n.props:
		var v: Variant = n.props[k]
		if v != StudioSchema.default_of(n.c, k):
			props[k] = SValue.encode(v)
	if not props.is_empty():
		out["p"] = props
	var ks: Array = []
	for k in n.kids:
		ks.append(to_marp_node(k))
	if not ks.is_empty():
		out["k"] = ks
	return out


func to_marp_tree() -> Dictionary:
	var ks: Array = []
	for k in kids(ROOT):
		ks.append(to_marp_node(k))
	return {"c": "DataModel", "k": ks}
