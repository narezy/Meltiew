class_name ObjExport
extends RefCounted
## Studio: what's selected as a Wavefront .obj with its .mtl and textures, zipped (Blender,
## or any 3D program, opens it). Parts come with their colors, textures and decals; rigs in
## the pose they're in, their body's colors and shirt baked into one picture, the face in
## another, and whatever they wear or had swapped in by a script as meshes of their own.

var _obj := PackedStringArray()
var _mtl := PackedStringArray()
var _files := {}  # name -> PackedByteArray (textures)
var _pictures := {}  # texture + tint -> its file name, so each is saved once
var _v := 0  # vertices written so far (OBJ counts from 1)
var _vt := 0
var _vn := 0
var _mats := 0
var _origin := Vector3.ZERO
var _vertex_colors := false  # points carry their color (a ProceduralMesh's)
var _labels := {}  # MeshInstance3D -> the name of the place's object it draws
var _poses := {}  # Skeleton3D -> its bones' global poses as drawn (with the joints turned)


## Zip bytes for the selected objects `ids` of `scene` (and everything in them); empty when
## there's nothing to draw. The selection's bottom middle ends up at 0, 0, 0. Awaited: rigs'
## poses are read as the next frame draws them.
static func selection(scene: PlaceScene, ids: Array, name: String) -> PackedByteArray:
	var meshes: Array[MeshInstance3D] = []
	var labels := {}
	var seen := {}
	var tree := scene.tree
	for id: String in ids:
		if not tree.has(id):
			continue
		for d: String in [id] + tree.descendants(id):
			if seen.has(d):
				continue
			seen[d] = true
			var mi: MeshInstance3D = null
			if tree.cls(d) == "ProceduralMesh":
				mi = scene._pmeshes.get(d, {}).get("mi")
			elif tree.is_a(d, "BasePart"):
				if float(tree.prop(d, "Transparency")) < 0.999:
					mi = scene.mesh_of(d)
			elif tree.cls(d) == "Decal":
				mi = scene._decals.get(d)
			if mi and is_instance_valid(mi):
				meshes.append(mi)
				labels[mi] = tree.name_of(d)
			var av := scene.avatar_for(d)
			if av and not seen.has(av):
				seen[av] = true
				for m in av.find_children("*", "MeshInstance3D", true, false):
					if (m as MeshInstance3D).is_visible_in_tree():
						meshes.append(m)
						labels[m] = "%s_%s" % [tree.name_of(d), str(m.name).replace("@", "")]
	if meshes.is_empty():
		return PackedByteArray()
	var out := ObjExport.new()
	out._labels = labels
	await out._catch_poses(meshes)
	return out.build(meshes, name)


## A skeleton's turned joints (JointPose and the like) are only in its bones while it's being
## drawn, so the poses are caught then.
func _catch_poses(meshes: Array[MeshInstance3D]) -> void:
	var waiting := {}
	for mi in meshes:
		var skel := mi.get_node_or_null(mi.skeleton) as Skeleton3D
		if skel and not waiting.has(skel):
			waiting[skel] = func() -> void:
				var poses: Array[Transform3D] = []
				for b in skel.get_bone_count():
					poses.append(skel.get_bone_global_pose(b))
				_poses[skel] = poses
			skel.skeleton_updated.connect(waiting[skel])
	if waiting.is_empty():
		return
	for i in 3:
		await meshes[0].get_tree().process_frame
		if _poses.size() == waiting.size():
			break
	for skel: Skeleton3D in waiting:
		if is_instance_valid(skel):
			skel.skeleton_updated.disconnect(waiting[skel])


## Zip bytes holding <name>.obj, <name>.mtl and the textures for `meshes` where they are.
func build(meshes: Array[MeshInstance3D], name: String) -> PackedByteArray:
	var box := AABB()
	for i in meshes.size():
		var b := meshes[i].global_transform * meshes[i].get_aabb()
		box = b if i == 0 else box.merge(b)
	_origin = Vector3(box.get_center().x, box.position.y, box.get_center().z)
	_obj.append("# Meltiew Studio")
	_obj.append("mtllib %s.mtl" % name)
	for mi in meshes:
		_mesh(mi)
	var path := OS.get_cache_dir().path_join("meltiew_export_%d.zip" % Time.get_ticks_usec())
	var zip := ZIPPacker.new()
	if zip.open(path) != OK:
		return PackedByteArray()
	_files[name + ".obj"] = "\n".join(_obj).to_utf8_buffer()
	_files[name + ".mtl"] = "\n".join(_mtl).to_utf8_buffer()
	for f: String in _files:
		zip.start_file(f)
		zip.write_file(_files[f])
		zip.close_file()
	zip.close()
	var out := FileAccess.get_file_as_bytes(path)
	DirAccess.remove_absolute(path)
	return out


func _mesh(mi: MeshInstance3D) -> void:
	if mi.mesh == null:
		return
	var mesh: Mesh = mi.mesh
	var skel := mi.get_node_or_null(mi.skeleton) as Skeleton3D
	var bones: Array[Transform3D] = []
	if mesh is ArrayMesh and skel:
		bones = _bind_poses(mi, skel, _poses.get(skel, []))
	var xf := Transform3D(Basis(), -_origin) * mi.global_transform
	_obj.append("o %s_%d" % [str(_labels.get(mi, mi.name)).validate_filename().replace(" ", "_"), _mats + 1])
	for s in mesh.get_surface_count():
		var mat: Material = mi.material_override
		if mat == null:
			mat = mi.get_surface_override_material(s)
		if mat == null:
			mat = mesh.surface_get_material(s)
		var rest := mesh.surface_get_arrays(s)
		var arr := _posed(rest, bones) if not bones.is_empty() else rest
		if mat is ShaderMaterial and (mat as ShaderMaterial).get_shader_parameter("part_colors") is PackedColorArray:
			_melly_body(arr, rest, mat as ShaderMaterial, xf)
		elif mat is ShaderMaterial and (mat as ShaderMaterial).get_shader_parameter("to_object") != null:
			_swapped_part(arr, mat as ShaderMaterial, xf)
		elif mat is StandardMaterial3D:
			var sm := mat as StandardMaterial3D
			if sm.albedo_color.a < 0.01:
				continue  # hidden (a face under a swapped head)
			_vertex_colors = sm.vertex_color_use_as_albedo
			_surface(arr, xf, _standard(sm), _triplanar_uvs(arr, sm) if _triplanar(sm) else null)
			_vertex_colors = false
		else:
			var c: Variant = (mat as ShaderMaterial).get_shader_parameter("base_color") if mat is ShaderMaterial else null
			_surface(arr, xf, _new_material(c if c is Color else Color.WHITE))


## For a skinned mesh: each of its skin's bones where it is now, as a move from the rest
## pose (empty when the mesh isn't skinned).
static func _bind_poses(mi: MeshInstance3D, skel: Skeleton3D, poses: Array) -> Array[Transform3D]:
	var pose := func(b: int) -> Transform3D: return poses[b] if b < poses.size() else skel.get_bone_global_pose(b)
	var out: Array[Transform3D] = []
	var skin := mi.skin
	if skin == null:
		for b in skel.get_bone_count():
			out.append(pose.call(b) * skel.get_bone_global_rest(b).affine_inverse())
		return out
	for i in skin.get_bind_count():
		var b := skin.get_bind_bone(i)
		if b < 0:
			b = skel.find_bone(skin.get_bind_name(i))
		out.append(pose.call(b) * skin.get_bind_pose(i) if b >= 0 else Transform3D())
	return out


## A skinned surface in the pose its skeleton is in (what the GPU draws).
static func _posed(rest: Array, binds: Array[Transform3D]) -> Array:
	var bones: Variant = rest[Mesh.ARRAY_BONES]
	var weights: Variant = rest[Mesh.ARRAY_WEIGHTS]
	if not (bones is PackedInt32Array and weights is PackedFloat32Array):
		return rest
	var v: PackedVector3Array = rest[Mesh.ARRAY_VERTEX]
	var n: Variant = rest[Mesh.ARRAY_NORMAL]
	var has_n := n is PackedVector3Array and (n as PackedVector3Array).size() == v.size()
	var per: int = (bones as PackedInt32Array).size() / maxi(1, v.size())
	var pv := PackedVector3Array()
	pv.resize(v.size())
	var pn := PackedVector3Array()
	pn.resize(v.size() if has_n else 0)
	for i in v.size():
		var p := Vector3.ZERO
		var q := Vector3.ZERO
		var total := 0.0
		for k in per:
			var w: float = weights[i * per + k]
			var b: int = bones[i * per + k]
			if w <= 0.0 or b < 0 or b >= binds.size():
				continue
			p += binds[b] * v[i] * w
			if has_n:
				q += binds[b].basis * (n[i] as Vector3) * w
			total += w
		pv[i] = p / total if total > 0.0 else v[i]
		if has_n:
			pn[i] = q.normalized() if total > 0.0 else n[i]
	var out := rest.duplicate()
	out[Mesh.ARRAY_VERTEX] = pv
	if has_n:
		out[Mesh.ARRAY_NORMAL] = pn
	return out


## A surface with one material; `uvs` in place of its own when given.
func _surface(arr: Array, xf: Transform3D, mat_name: String, uvs: Variant = null) -> void:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv: Variant = uvs if uvs != null else arr[Mesh.ARRAY_TEX_UV]
	var has_uv := uv is PackedVector2Array and (uv as PackedVector2Array).size() == v.size()
	var base_v := _v + 1
	var base_n := _vn + 1
	var has_n := _points(arr, xf)
	var base_t := _vt + 1
	if has_uv:
		for t: Vector2 in uv:
			_obj.append("vt %.5f %.5f" % [t.x, 1.0 - t.y])
		_vt += v.size()
	_obj.append("usemtl " + mat_name)
	var tris := _triangles(arr)
	for i in range(0, tris.size() - 2, 3):
		var line := "f"
		for k in [tris[i], tris[i + 2], tris[i + 1]]:  # Godot turns faces the other way round
			line += " " + _corner(k + base_v, k + base_t if has_uv else -1, k + base_n if has_n else -1)
		_obj.append(line)


## Writes a surface's points (and normals, when it has them); true with normals.
func _points(arr: Array, xf: Transform3D) -> bool:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var col: Variant = arr[Mesh.ARRAY_COLOR]
	if _vertex_colors and col is PackedColorArray and (col as PackedColorArray).size() == v.size():
		for i in v.size():
			var w := xf * v[i]
			var c: Color = col[i]
			_obj.append("v %.5f %.5f %.5f %.4f %.4f %.4f" % [w.x, w.y, w.z, c.r, c.g, c.b])
	else:
		for p in v:
			var w := xf * p
			_obj.append("v %.5f %.5f %.5f" % [w.x, w.y, w.z])
	_v += v.size()
	var n: Variant = arr[Mesh.ARRAY_NORMAL]
	if not (n is PackedVector3Array and (n as PackedVector3Array).size() == v.size()):
		return false
	var nb := xf.basis.inverse().transposed()
	for q: Vector3 in n:
		var w := (nb * q).normalized()
		_obj.append("vn %.4f %.4f %.4f" % [w.x, w.y, w.z])
	_vn += v.size()
	return true


static func _triangles(arr: Array) -> PackedInt32Array:
	var idx: Variant = arr[Mesh.ARRAY_INDEX]
	if idx is PackedInt32Array and not (idx as PackedInt32Array).is_empty():
		return idx
	var out := PackedInt32Array()
	out.resize((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	for i in out.size():
		out[i] = i
	return out


static func _corner(v: int, t: int, n: int) -> String:
	if t < 0 and n < 0:
		return str(v)
	if n < 0:
		return "%d/%d" % [v, t]
	return "%d/%s/%d" % [v, str(t) if t >= 0 else "", n]


func _new_material(color: Color) -> String:
	_mats += 1
	var name := "m%d" % _mats
	_mtl.append("")
	_mtl.append("newmtl " + name)
	_mtl.append("Kd %.4f %.4f %.4f" % [color.r, color.g, color.b])
	if color.a < 0.999:
		_mtl.append("d %.3f" % color.a)
	return name


## A part's or a hat's material: its color, see-through-ness and picture (the color laid
## over the picture, the way it's drawn). The noise of Wood, Grass and such is left out.
func _standard(sm: StandardMaterial3D) -> String:
	var tex := sm.albedo_texture
	if tex == null or (sm.uv1_triplanar and sm.uv1_world_triplanar):
		return _new_material(sm.albedo_color)
	var file := _picture(tex, sm.albedo_color)
	if file == "":
		return _new_material(sm.albedo_color)
	var name := _new_material(Color(1, 1, 1, sm.albedo_color.a))
	_mtl.append("map_Kd " + file)
	if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		_mtl.append("map_d " + file)
	return name


static func _triplanar(sm: StandardMaterial3D) -> bool:
	return sm.albedo_texture != null and sm.uv1_triplanar and not sm.uv1_world_triplanar


## Texture coordinates for a picture Godot lays on by the sides of the object (a part's
## Texture): each point takes the side its normal faces most.
static func _triplanar_uvs(arr: Array, sm: StandardMaterial3D) -> PackedVector2Array:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: Variant = arr[Mesh.ARRAY_NORMAL]
	var out := PackedVector2Array()
	out.resize(v.size())
	for i in v.size():
		var p := v[i] * sm.uv1_scale + sm.uv1_offset
		p.y = -p.y
		var a: Vector3 = (n[i] as Vector3).abs() if n is PackedVector3Array else Vector3.UP
		if a.z >= a.x and a.z >= a.y:
			out[i] = Vector2(p.x, p.y)
		elif a.y >= a.x:
			out[i] = Vector2(p.x, p.z)
		else:
			out[i] = Vector2(-p.z, p.y)
	return out


## A texture saved as a PNG for the .mtl (tinted by `tint` when that isn't white); its
## file name, or "" when it can't be read.
func _picture(tex: Texture2D, tint: Color) -> String:
	var key := "%s %s" % [tex.get_rid().get_id(), tint.to_html(false)]
	if _pictures.has(key):
		return _pictures[key]
	var img := tex.get_image()
	if img == null:
		return ""
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	if not tint.is_equal_approx(Color(1, 1, 1, tint.a)):
		if img.get_width() > 512 or img.get_height() > 512:
			var k := 512.0 / maxf(img.get_width(), img.get_height())
			img.resize(maxi(1, int(img.get_width() * k)), maxi(1, int(img.get_height() * k)))
		var data := img.get_data()
		for i in range(0, data.size(), 4):
			data[i] = int(data[i] * tint.r)
			data[i + 1] = int(data[i + 1] * tint.g)
			data[i + 2] = int(data[i + 2] * tint.b)
		img = Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)
	var file := "tex%d.png" % (_pictures.size() + 1)
	_files[file] = img.save_png_to_buffer()
	_pictures[key] = file
	return file


## The clothing template with `fill` (part -> color) painted into the parts' corners and
## the material's shirt layers over it, saved as a PNG; its file name.
func _dressed(fill: Dictionary, mat: ShaderMaterial) -> String:
	var img := Image.create_empty(ClothingLayout.W, ClothingLayout.H, false, Image.FORMAT_RGBA8)
	for p: int in fill:
		img.fill_rect(_region(p), fill[p])
	for i in int(mat.get_shader_parameter("cloth_count")):
		var tex: Variant = mat.get_shader_parameter("cloth%d" % i)
		if not tex is Texture2D:
			continue
		var layer := (tex as Texture2D).get_image()
		if layer == null:
			continue
		layer = layer.duplicate()
		if layer.is_compressed():
			layer.decompress()
		layer.clear_mipmaps()
		layer.convert(Image.FORMAT_RGBA8)
		if layer.get_size() != img.get_size():
			layer.resize(img.get_width(), img.get_height())
		img.blend_rect(layer, Rect2i(Vector2i.ZERO, layer.get_size()), Vector2i.ZERO)
	var file := "tex%d.png" % (_pictures.size() + 1)
	_pictures[file] = file
	_files[file] = img.save_png_to_buffer()
	return file


## Melly's body: its colors and shirt are drawn by a shader from the rest pose (UV, UV2);
## baked here into one picture with texture coordinates to match. The head is one color
## (its face is a surface of its own); hidden and swapped parts are left out.
func _melly_body(posed: Array, rest: Array, mat: ShaderMaterial, xf: Transform3D) -> void:
	var colors: PackedColorArray = mat.get_shader_parameter("part_colors")
	var fill := {}
	for p: int in ClothingLayout.DRESSED:
		fill[p] = Color(colors[p], 1.0)
	var body := _new_material(Color.WHITE)
	_mtl.append("map_Kd " + _dressed(fill, mat))
	var head := _new_material(Color(colors[1], 1.0))
	var v: PackedVector3Array = posed[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = rest[Mesh.ARRAY_BONES]
	var ruv: PackedVector2Array = rest[Mesh.ARRAY_TEX_UV]
	var ruv2: PackedVector2Array = rest[Mesh.ARRAY_TEX_UV2]
	var per := maxi(1, bones.size() / maxi(1, v.size()))
	var base_v := _v + 1
	var base_n := _vn + 1
	var has_n := _points(posed, xf)
	var groups := {body: PackedStringArray(), head: PackedStringArray()}
	var tris := _triangles(rest)
	for i in range(0, tris.size() - 2, 3):
		var c := [tris[i], tris[i + 2], tris[i + 1]]
		var part := bones[c[0] * per]
		if part < 0 or part >= colors.size() or colors[part].a < 0.5:
			continue
		var line := "f"
		if part == 1:
			for k: int in c:
				line += " " + _corner(k + base_v, -1, k + base_n if has_n else -1)
			groups[head].append(line)
			continue
		var at: Array[Vector3] = []
		var mid := Vector3.ZERO
		for k: int in c:
			at.append(Vector3(ruv[k].x, ruv[k].y, ruv2[k].x))
			mid += at[-1] / 3.0
		var face := _face_of(part, mid)
		for j in 3:
			var t := _atlas_uv(part, at[j], face)
			_obj.append("vt %.5f %.5f" % [t.x, 1.0 - t.y])
			_vt += 1
			line += " " + _corner(c[j] + base_v, _vt, c[j] + base_n if has_n else -1)
		groups[body].append(line)
	for m: String in groups:
		if not (groups[m] as PackedStringArray).is_empty():
			_obj.append("usemtl " + m)
			_obj.append_array(groups[m])


## A script's own object in place of a body part that keeps the shirt
## (body_part_cloth.gdshader): the shirt laid over it the same way, baked.
func _swapped_part(arr: Array, mat: ShaderMaterial, xf: Transform3D) -> void:
	var part := int(mat.get_shader_parameter("part"))
	var color: Variant = mat.get_shader_parameter("base_color")
	var base: Color = color if color is Color else Color.WHITE
	if int(mat.get_shader_parameter("cloth_count")) == 0 or not ClothingLayout.DRESSED.has(part):
		_surface(arr, xf, _new_material(base))
		return
	var to: Variant = mat.get_shader_parameter("to_object")
	var to_object := Transform3D(to as Projection) if to is Projection else (to as Transform3D if to is Transform3D else Transform3D())
	var mn: Vector3 = mat.get_shader_parameter("obj_min")
	var sz: Vector3 = mat.get_shader_parameter("obj_size")
	var name := _new_material(Color.WHITE)
	_mtl.append("map_Kd " + _dressed({part: Color(base, 1.0)}, mat))
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var at := PackedVector3Array()
	for p in v:
		var q := ((to_object * p - mn) / sz).clamp(Vector3.ZERO, Vector3.ONE)
		at.append(ClothingLayout.BOX_MIN[part] + Vector3(1.0 - q.x, q.y, 1.0 - q.z) * ClothingLayout.BOX_SIZE[part])
	var base_v := _v + 1
	var base_n := _vn + 1
	var has_n := _points(arr, xf)
	_obj.append("usemtl " + name)
	var tris := _triangles(arr)
	for i in range(0, tris.size() - 2, 3):
		var c := [tris[i], tris[i + 2], tris[i + 1]]
		var face := _face_of(part, (at[c[0]] + at[c[1]] + at[c[2]]) / 3.0)
		var line := "f"
		for k: int in c:
			var t := _atlas_uv(part, at[k], face)
			_obj.append("vt %.5f %.5f" % [t.x, 1.0 - t.y])
			_vt += 1
			line += " " + _corner(k + base_v, _vt, k + base_n if has_n else -1)
		_obj.append(line)


## The rectangle a part takes on the clothing template (its unfolded box).
static func _region(p: int) -> Rect2i:
	var sz: Vector3 = ClothingLayout.BOX_SIZE[p]
	var fw := floori(sz.x * ClothingLayout.PX + 0.5)
	var fh := floori(sz.y * ClothingLayout.PX + 0.5)
	var fd := floori(sz.z * ClothingLayout.PX + 0.5)
	return Rect2i(Vector2i(ClothingLayout.ORIGIN[p]), Vector2i(2 * fd + 2 * fw, 2 * fd + fh))


## Which side of a part's box a point is on, the one it's furthest out towards (as
## melly_body.gdshader picks it): 0 front, 1 back, 2 left, 3 right, 4 top, 5 bottom.
static func _face_of(p: int, pos: Vector3) -> int:
	var mn: Vector3 = ClothingLayout.BOX_MIN[p]
	var sz: Vector3 = ClothingLayout.BOX_SIZE[p]
	var d := (pos - (mn + sz * 0.5)) / (sz * 0.5)
	var a := d.abs()
	if a.z >= a.x and a.z >= a.y:
		return 0 if d.z > 0.0 else 1
	if a.x >= a.y:
		return 2 if d.x < 0.0 else 3
	return 4 if d.y > 0.0 else 5


## The template spot (0..1) of a point on a part, on the given side (melly_body.gdshader).
static func _atlas_uv(p: int, pos: Vector3, face: int) -> Vector2:
	var mn: Vector3 = ClothingLayout.BOX_MIN[p]
	var sz: Vector3 = ClothingLayout.BOX_SIZE[p]
	var f := ((pos - mn) / sz).clamp(Vector3.ONE * 0.003, Vector3.ONE * 0.997)
	var fw := floorf(sz.x * ClothingLayout.PX + 0.5)
	var fh := floorf(sz.y * ClothingLayout.PX + 0.5)
	var fd := floorf(sz.z * ClothingLayout.PX + 0.5)
	var o: Vector2 = ClothingLayout.ORIGIN[p]
	var px: Vector2
	match face:
		0:
			px = o + Vector2(fd, fd) + Vector2(f.x * fw, (1.0 - f.y) * fh)
		1:
			px = o + Vector2(2.0 * fd + fw, fd) + Vector2((1.0 - f.x) * fw, (1.0 - f.y) * fh)
		2:
			px = o + Vector2(0.0, fd) + Vector2(f.z * fd, (1.0 - f.y) * fh)
		3:
			px = o + Vector2(fd + fw, fd) + Vector2((1.0 - f.z) * fd, (1.0 - f.y) * fh)
		4:
			px = o + Vector2(fd, 0.0) + Vector2(f.x * fw, f.z * fd)
		_:
			px = o + Vector2(fd, fd + fh) + Vector2(f.x * fw, (1.0 - f.z) * fd)
	return px / Vector2(ClothingLayout.W, ClothingLayout.H)
