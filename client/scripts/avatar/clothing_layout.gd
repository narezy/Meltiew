class_name ClothingLayout
extends RefCounted
## Clothing pictures follow one template, 1024×768: the torso, arms and legs are boxes,
## each unfolded as a cross (right side, front, left side, back in a row; the top above
## the front, the bottom under it), 96 template pixels to a unit of the model. The body
## shader (melly_body.gdshader) finds the same spots, from where each point of the body
## is in the rest pose; that is baked into the mesh once (dressable()).

const W := 1024
const H := 768
const PX := 96.0
## Per skin part, in skin order (Torso, Head, ArmL, ArmR, LegL, LegR): the part's box in
## the rest pose (model units) and its cross's top-left corner on the template. The head
## isn't dressed. Kept in step with the shader.
const BOX_MIN := [Vector3(-0.83, 2.0, -0.39), Vector3.ZERO, Vector3(0.79118, 1.88, -0.37986),
	Vector3(-1.62882, 1.88, -0.37986), Vector3(0.03004, 0.0, -0.42723), Vector3(-0.82996, 0.0, -0.42723)]
const BOX_SIZE := [Vector3(1.66, 2.0, 0.78), Vector3.ZERO, Vector3(0.83764, 2.0, 0.75972),
	Vector3(0.83764, 2.0, 0.75972), Vector3(0.79992, 2.0, 0.85446), Vector3(0.79992, 2.0, 0.85446)]
const ORIGIN := [Vector2(16, 16), Vector2(-1, -1), Vector2(16, 382), Vector2(512, 16), Vector2(688, 382), Vector2(346, 382)]
const DRESSED := [0, 2, 3, 4, 5]
## What each part is called on the template.
const PART_NAMES := {0: ["TORSO", "ТОРС"], 2: ["LEFT ARM", "ЛЕВАЯ РУКА"], 3: ["RIGHT ARM", "ПРАВАЯ РУКА"],
	4: ["LEFT LEG", "ЛЕВАЯ НОГА"], 5: ["RIGHT LEG", "ПРАВАЯ НОГА"]}

static var _meshes := {}


## A part's faces on the template: {front, back, right, left, top, bottom} -> Rect2.
## "right" is the part's own right side (as the character sees it).
static func faces(part: int) -> Dictionary:
	var s: Vector3 = BOX_SIZE[part]
	var fw := roundf(s.x * PX)
	var fh := roundf(s.y * PX)
	var fd := roundf(s.z * PX)
	var o: Vector2 = ORIGIN[part]
	return {
		"top": Rect2(o + Vector2(fd, 0), Vector2(fw, fd)),
		"right": Rect2(o + Vector2(0, fd), Vector2(fd, fh)),
		"front": Rect2(o + Vector2(fd, fd), Vector2(fw, fh)),
		"left": Rect2(o + Vector2(fd + fw, fd), Vector2(fd, fh)),
		"back": Rect2(o + Vector2(2 * fd + fw, fd), Vector2(fw, fh)),
		"bottom": Rect2(o + Vector2(fd, fd + fh), Vector2(fw, fd)),
	}


## The torso's front on the template: what a shirt looks like at a glance (shop cards).
static func torso_front() -> Rect2:
	return faces(0).front


## The body mesh with each vertex's rest position in its UVs (UV = x, y; UV2 = z, part),
## made once per source mesh and shared by every Melly.
static func dressable(src: Mesh) -> Mesh:
	if src == null or _meshes.has(src):
		return _meshes.get(src, src)
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var arr := src.surface_get_arrays(s)
		if s == 0:
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones: Variant = arr[Mesh.ARRAY_BONES]
			var per := 4
			if bones is PackedInt32Array and v.size() > 0:
				per = maxi(1, (bones as PackedInt32Array).size() / v.size())
			var uv := PackedVector2Array()
			var uv2 := PackedVector2Array()
			uv.resize(v.size())
			uv2.resize(v.size())
			for i in v.size():
				uv[i] = Vector2(v[i].x, v[i].y)
				var part := 0
				if bones is PackedInt32Array:
					part = (bones as PackedInt32Array)[i * per]
				uv2[i] = Vector2(v[i].z, float(part))
			arr[Mesh.ARRAY_TEX_UV] = uv
			arr[Mesh.ARRAY_TEX_UV2] = uv2
		var blends: Array = src.surface_get_blend_shape_arrays(s) if src is ArrayMesh else []
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, blends, _lods_of(src, s))
		out.surface_set_material(s, src.surface_get_material(s))
	_meshes[src] = out
	return out


## The simpler versions of a surface made on import (drawn for far away players): copied
## over, or every Melly in a crowd would be drawn in full detail.
static func _lods_of(src: Mesh, s: int) -> Dictionary:
	var out := {}
	var sd: Dictionary = RenderingServer.mesh_get_surface(src.get_rid(), s)
	var count := int(sd.get("index_count", 0))
	if count == 0:
		return out
	var wide := (sd.index_data as PackedByteArray).size() / count >= 4
	for l in sd.get("lods", []):
		var data: PackedByteArray = l.index_data
		var idx := PackedInt32Array()
		if wide:
			idx = data.to_int32_array()
		else:
			idx.resize(data.size() / 2)
			for i in idx.size():
				idx[i] = data.decode_u16(i * 2)
		out[float(l.edge_length)] = idx
	return out


## A clothing item's picture on the server (for AssetCache).
static func image_ref(id: int) -> String:
	return "/api/clothing/%d/image" % id
