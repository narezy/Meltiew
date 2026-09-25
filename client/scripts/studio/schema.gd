class_name StudioSchema
extends RefCounted
## The class schema shared with the server and the Luau runtime
## (res://studio/runtime/classes.json): classes, their properties with types and
## defaults, events, enums and which classes can be inserted in Studio.

const PATH := "res://studio/runtime/classes.json"

static var _data: Dictionary = {}
static var _flat := {}  # class -> merged {props, events, isA}


static func data() -> Dictionary:
	if _data.is_empty():
		var text := FileAccess.get_file_as_string(PATH)
		var parsed: Variant = JSON.parse_string(text)
		_data = parsed if parsed is Dictionary else {"classes": {}, "enums": {}, "services": []}
	return _data


static func has_class(name: String) -> bool:
	return data().classes.has(name)


static func raw(name: String) -> Dictionary:
	return data().classes.get(name, {})


## Merged view of a class with everything it inherits.
static func info(name: String) -> Dictionary:
	if _flat.has(name):
		return _flat[name]
	var r := raw(name)
	var out := {"name": name, "props": {}, "events": [], "isA": {name: true}, "raw": r}
	var base: Variant = r.get("base")
	if base is String and base != "":
		var b := info(base)
		out.props = b.props.duplicate()
		out.events = b.events.duplicate()
		out.isA = b.isA.duplicate()
		out.isA[name] = true
	for k in r.get("props", {}):
		out.props[k] = r.props[k]
	for e in r.get("events", []):
		if not e in out.events:
			out.events.append(e)
	_flat[name] = out
	return out


static func is_a(name: String, base: String) -> bool:
	return info(name).isA.has(base)


static func enum_values(enum_name: String) -> Array:
	return data().enums.get(enum_name, [])


## Default value of a property (Godot type), taking per-class overrides into account.
static func default_of(cls: String, key: String) -> Variant:
	var r := raw(cls)
	var ov: Dictionary = r.get("overrides", {})
	if ov.has(key):
		return SValue.decode(ov[key])
	var p: Dictionary = info(cls).props.get(key, {})
	return SValue.decode(p.get("default"))


static func prop_type(cls: String, key: String) -> String:
	return str(info(cls).props.get(key, {}).get("type", ""))


static func services() -> Array:
	return data().get("services", [])


## Classes Studio can insert, grouped by category (3D, GUI, Script, Logic).
static func creatable() -> Dictionary:
	var out := {}
	for name in data().classes:
		var r: Dictionary = data().classes[name]
		if r.get("creatable", false):
			var cat := str(r.get("category", "Other"))
			if not out.has(cat):
				out[cat] = []
			out[cat].append(name)
	for cat in out:
		out[cat].sort()
	return out
