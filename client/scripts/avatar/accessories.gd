class_name Accessories
extends RefCounted
## Accessories come from the server's catalog (GET /api/accessories): each one is a
## list of primitives placed on a bone. New ones show up without an app update.
## A copy ships with the app and the last catalog seen is cached for offline starts.
## Coordinates are melly.glb model units relative to the bone, +Y up, +Z front.

const BUNDLED := "res://assets/accessories.json"
const CACHE := "user://accessories.json"

static var _items: Array = []
static var _by_id := {}
static var _mats := {}
## Bumped whenever a new catalog arrives (thumbnails are cached per version).
static var version := 0
static var max_worn := 4


static func _ensure() -> void:
	if not _items.is_empty():
		return
	var text := FileAccess.get_file_as_string(CACHE) if FileAccess.file_exists(CACHE) else ""
	if not _set_catalog(JSON.parse_string(text) if text != "" else null):
		_set_catalog(JSON.parse_string(FileAccess.get_file_as_string(BUNDLED)))


static func _set_catalog(data: Variant) -> bool:
	if not (data is Dictionary and data.get("items") is Array):
		return false
	_items = data.items
	_by_id.clear()
	for it in _items:
		_by_id[str(it.id)] = it
	max_worn = int(data.get("max_worn", 4))
	version += 1
	return true


## Fetches the latest catalog (call at startup).
static func refresh() -> void:
	_ensure()
	var r := await Api.request("GET", "/api/accessories")
	if r.ok and _set_catalog(r.data):
		var f := FileAccess.open(CACHE, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(r.data))


static func items() -> Array:
	_ensure()
	return _items


static func has(id: String) -> bool:
	_ensure()
	return _by_id.has(id)


static func slot_of(id: String) -> String:
	_ensure()
	return str(_by_id.get(id, {}).get("slot", ""))


static func bone_of(id: String) -> String:
	_ensure()
	return str(_by_id.get(id, {}).get("bone", "Head"))


static func name_of(id: String) -> String:
	_ensure()
	var names: Dictionary = _by_id.get(id, {}).get("name", {})
	return str(names.get(L.lang, names.get("en", id)))


## Puts `id` on, taking off whatever sat in the same slot; keeps at most max_worn.
static func wear(worn: Array, id: String) -> Array:
	var slot := slot_of(id)
	var out: Array = worn.filter(func(w): return slot_of(str(w)) != slot and str(w) != id)
	out.append(id)
	while out.size() > max_worn:
		out.pop_front()
	return out


static func random_look() -> Array:
	_ensure()
	var out: Array = []
	for i in randi_range(0, 2):
		if not _items.is_empty():
			out = wear(out, str(_items.pick_random().id))
	return out


## The 3D model of one accessory (unattached), or null for an unknown id.
static func build(id: String) -> Node3D:
	_ensure()
	var def: Dictionary = _by_id.get(id, {})
	if def.is_empty():
		return null
	var root := Node3D.new()
	root.name = id
	_place(root, def)
	for p in def.get("parts", []):
		_add_part(root, p)
	return root


static func _place(n: Node3D, p: Dictionary) -> void:
	var pos: Array = p.get("pos", [0, 0, 0])
	n.position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	var rot: Array = p.get("rot", [0, 0, 0])
	n.rotation_degrees = Vector3(float(rot[0]), float(rot[1]), float(rot[2]))


static func _add_part(parent: Node3D, p: Dictionary) -> void:
	var shape := str(p.get("shape", "box"))
	var node: Node3D
	if shape == "group":
		node = Node3D.new()
		for c in p.get("parts", []):
			_add_part(node, c)
	else:
		var mesh := _mesh(shape, p)
		if mesh == null:
			return
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _mat(str(p.get("color", "#ffffff")), float(p.get("rough", 0.7)), float(p.get("metal", 0.0)), float(p.get("glow", 0.0)))
		if p.get("shadow", true) == false:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node = mi
	_place(node, p)
	parent.add_child(node)
	if p.get("anim") is Dictionary:
		_animate(node, p.anim)


static func _mesh(shape: String, p: Dictionary) -> Mesh:
	match shape:
		"box":
			var m := BoxMesh.new()
			m.size = _v3(p.get("size", [1, 1, 1]))
			return m
		"prism":
			var m := PrismMesh.new()
			m.size = _v3(p.get("size", [1, 1, 1]))
			return m
		"sphere":
			var m := SphereMesh.new()
			m.radius = float(p.get("r", 0.5))
			m.height = float(p.get("h", m.radius * 2.0))
			m.is_hemisphere = bool(p.get("half", false))
			m.radial_segments = 24
			m.rings = 12
			return m
		"cylinder", "cone":
			var m := CylinderMesh.new()
			m.top_radius = 0.0 if shape == "cone" else float(p.get("top", 0.5))
			m.bottom_radius = float(p.get("bottom", 0.5))
			m.height = float(p.get("h", 1.0))
			m.radial_segments = 24
			return m
		"torus":
			var m := TorusMesh.new()
			m.inner_radius = float(p.get("inner", 0.4))
			m.outer_radius = float(p.get("outer", 0.5))
			m.rings = 32
			return m
		"capsule":
			var m := CapsuleMesh.new()
			m.radius = float(p.get("r", 0.2))
			m.height = float(p.get("h", 0.8))
			return m
	return null


static func _v3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func _mat(color: String, rough: float, metal: float, glow: float) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%.2f" % [color, rough, metal, glow]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color)
	m.roughness = rough
	m.metallic = metal
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = Color(color)
		m.emission_energy_multiplier = glow
	_mats[key] = m
	return m


## Simple looping motion: bob (up and down), sway (rock around an axis), spin.
static func _animate(n: Node3D, a: Dictionary) -> void:
	var period := maxf(float(a.get("period", 2.0)), 0.1)
	match str(a.get("type", "")):
		"bob":
			var y := n.position.y
			var t := n.create_tween().set_loops()
			t.tween_property(n, "position:y", y + float(a.get("amp", 0.1)), period / 2.0).set_trans(Tween.TRANS_SINE)
			t.tween_property(n, "position:y", y, period / 2.0).set_trans(Tween.TRANS_SINE)
		"sway":
			var axis := {"x": 0, "y": 1, "z": 2}.get(str(a.get("axis", "y")), 1) as int
			var base := n.rotation_degrees
			var deg := float(a.get("deg", 10.0))
			var left := base
			left[axis] += deg
			var right := base
			right[axis] -= deg
			n.rotation_degrees = right
			var t := n.create_tween().set_loops()
			t.tween_property(n, "rotation_degrees", left, period / 2.0).set_trans(Tween.TRANS_SINE)
			t.tween_property(n, "rotation_degrees", right, period / 2.0).set_trans(Tween.TRANS_SINE)
		"spin":
			var t := n.create_tween().set_loops()
			t.tween_property(n, "rotation_degrees:y", n.rotation_degrees.y + 360.0, period).from(n.rotation_degrees.y)
