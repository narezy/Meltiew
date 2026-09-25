class_name MeshBatch
extends RefCounted
## Collects many primitive meshes (with per-piece colors) into a few big
## vertex-colored ArrayMeshes, bucketed by area so frustum culling still works.

const CELL := 40.0

var _buckets := {}  # Vector2i -> {verts, normals, colors, indices}


func add(mesh: PrimitiveMesh, xform: Transform3D, color: Color) -> void:
	MeshBatch.simplify(mesh, 12, 6, 16)
	var arrays := mesh.get_mesh_arrays()
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var key := Vector2i(floori(xform.origin.x / CELL), floori(xform.origin.z / CELL))
	if not _buckets.has(key):
		_buckets[key] = {
			"v": PackedVector3Array(), "n": PackedVector3Array(),
			"c": PackedColorArray(), "i": PackedInt32Array(),
		}
	var b: Dictionary = _buckets[key]
	var base: int = b.v.size()
	var lin := color.srgb_to_linear()
	var nb := xform.basis.inverse().transposed()
	for k in v.size():
		b.v.append(xform * v[k])
		b.n.append((nb * n[k]).normalized())
		b.c.append(lin)
	if idx.is_empty():
		for k in v.size():
			b.i.append(base + k)
	else:
		for k in idx:
			b.i.append(base + k)


func build(parent: Node3D, material: Material, cast_shadows := true) -> void:
	for key in _buckets:
		var b: Dictionary = _buckets[key]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = b.v
		arrays[Mesh.ARRAY_NORMAL] = b.n
		arrays[Mesh.ARRAY_COLOR] = b.c
		arrays[Mesh.ARRAY_INDEX] = b.i
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.mesh = am
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
	_buckets.clear()


## Caps the tessellation of Godot primitives (spheres default to 64x32 = 4k triangles):
## at playground scale nobody sees the difference, phones do.
static func simplify(mesh: Mesh, sphere_segments := 16, sphere_rings := 8, cyl_segments := 24) -> void:
	if mesh is SphereMesh:
		mesh.radial_segments = mini(mesh.radial_segments, sphere_segments)
		mesh.rings = mini(mesh.rings, sphere_rings)
	elif mesh is CylinderMesh:
		mesh.radial_segments = mini(mesh.radial_segments, cyl_segments)
		mesh.rings = 0
	elif mesh is CapsuleMesh:
		mesh.radial_segments = mini(mesh.radial_segments, sphere_segments)
		mesh.rings = mini(mesh.rings, sphere_rings / 2)
	elif mesh is TorusMesh:
		mesh.rings = mini(mesh.rings, cyl_segments)
		mesh.ring_segments = mini(mesh.ring_segments, 10)
