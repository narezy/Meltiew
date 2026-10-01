class_name PartBatcher
extends Node3D
## Draws still parts together: every anchored, opaque, untextured part in a
## 32x32-stud area with the same material becomes part of one mesh (its color
## goes into the vertices). A thousand blocks cost a handful of draw calls
## instead of a thousand. Parts keep their own physics bodies; only drawing merges.

const CELL := 32.0
## Time per frame for rebuilding areas (at least one each frame); the rest wait. A map
## loading in all at once then costs a few smooth frames, not one long freeze.
const REBUILD_BUDGET_USEC := 2000

var _parts := {}  # id -> {arrays, mesh, xform, color, key, baked: [verts, normals, colors, indices]}
var _cells := {}  # key -> {ids: {id: true}, mi: MeshInstance3D}
var _dirty := {}  # key -> true
var _materials := {}  # "kind|shadow" -> StandardMaterial3D
var material_for: Callable  # (kind: String) -> StandardMaterial3D, white albedo


static func batchable_kind(kind: String) -> bool:
	return not kind in ["Neon", "Glass", "Ice"]


func has(id: String) -> bool:
	return _parts.has(id)


## Adds or updates a part. `mesh` is its shape (already sized), `xform` its world transform.
func put(id: String, mesh: Mesh, xform: Transform3D, color: Color, kind: String, shadow: bool) -> void:
	var cell := Vector2i(floori(xform.origin.x / CELL), floori(xform.origin.z / CELL))
	var key := "%d,%d|%s|%d" % [cell.x, cell.y, kind, 1 if shadow else 0]
	var old: Dictionary = _parts.get(id, {})
	if not old.is_empty() and old.key != key:
		_forget(id, old.key)
	var arrays: Array = old.arrays if not old.is_empty() and old.mesh == mesh else mesh.surface_get_arrays(0)
	_parts[id] = {"arrays": arrays, "mesh": mesh, "xform": xform, "color": color, "key": key, "baked": _bake(arrays, xform, color)}
	if not _cells.has(key):
		var mi := MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = _material(kind, shadow)
		add_child(mi)
		_cells[key] = {"ids": {}, "mi": mi}
	_cells[key].ids[id] = true
	_dirty[key] = true


func remove(id: String) -> void:
	var d: Dictionary = _parts.get(id, {})
	if d.is_empty():
		return
	_forget(id, d.key)
	_parts.erase(id)


func _forget(id: String, key: String) -> void:
	if _cells.has(key):
		_cells[key].ids.erase(id)
		_dirty[key] = true


func _material(kind: String, shadow: bool) -> StandardMaterial3D:
	var k := "%s|%d" % [kind, 1 if shadow else 0]
	if not _materials.has(k):
		var m: StandardMaterial3D = material_for.call(kind)
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		_materials[k] = m
	return _materials[k]


## A part's shape where it stands, in its color: what a rebuild only has to append.
static func _bake(a: Array, xf: Transform3D, color: Color) -> Array:
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var c := PackedColorArray()
	c.resize(v.size())
	c.fill(color)
	var idx: Variant = a[Mesh.ARRAY_INDEX]
	if not (idx is PackedInt32Array and not idx.is_empty()):
		idx = PackedInt32Array(range(v.size()))
	return [xf * v, Transform3D(xf.basis.orthonormalized(), Vector3.ZERO) * (a[Mesh.ARRAY_NORMAL] as PackedVector3Array), c, idx]


func _process(_delta: float) -> void:
	if _dirty.is_empty():
		return
	var start := Time.get_ticks_usec()
	for key in _dirty.keys():
		_rebuild(key)
		_dirty.erase(key)
		if Time.get_ticks_usec() - start > REBUILD_BUDGET_USEC:
			break


func _rebuild(key: String) -> void:
	var cell: Dictionary = _cells.get(key, {})
	if cell.is_empty():
		return
	var mi: MeshInstance3D = cell.mi
	if cell.ids.is_empty():
		mi.queue_free()
		_cells.erase(key)
		return
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for id in cell.ids:
		var b: Array = _parts[id].baked
		var base := verts.size()
		verts.append_array(b[0])
		normals.append_array(b[1])
		colors.append_array(b[2])
		var idx: PackedInt32Array = b[3]
		var at := indices.size()
		indices.resize(at + idx.size())
		for k in idx.size():
			indices[at + k] = idx[k] + base
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mi.mesh = mesh


## How many draws the batches take and how many parts they hold (for stats).
func stats() -> Vector2i:
	return Vector2i(_cells.size(), _parts.size())
