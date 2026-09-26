class_name PlaceScene
extends Node3D
## Draws a place's 3D world from a PlaceTree: parts, spawn pads, 3D text, lights,
## lighting and sky. Used by the game (fed by the client VM) and by Studio.

## Parts that don't block players still get hit by clicks and Studio selection.
const LAYER_WORLD := 1
const LAYER_GHOST := 1 << 7
const SKY_SHADER := preload("res://assets/shaders/place_sky.gdshader")
const SKY_PRESETS := {
	"Day": {"top": "#6fa8ef", "horizon": "#d9ecff", "bottom": "#9fb0bf", "sun": "#fff4d6", "stars": 0.0, "clouds": 0.55, "ambient": "#b9c4e6"},
	"Sunset": {"top": "#3b3f7a", "horizon": "#ff9e6b", "bottom": "#4a3d5c", "sun": "#ffb36b", "stars": 0.2, "clouds": 0.4, "ambient": "#c99a8f"},
	"Night": {"top": "#070b24", "horizon": "#27305a", "bottom": "#0d1026", "sun": "#b8c8ff", "stars": 1.0, "clouds": 0.1, "ambient": "#3a4270"},
	"Space": {"top": "#000000", "horizon": "#0a0a18", "bottom": "#000000", "sun": "#ffffff", "stars": 1.3, "clouds": 0.0, "ambient": "#4a4a66"},
	"Overcast": {"top": "#9aa3ad", "horizon": "#cfd5da", "bottom": "#8a9199", "sun": "#ffffff", "stars": 0.0, "clouds": 1.0, "ambient": "#a8adb3"},
	"Candy": {"top": "#b89cff", "horizon": "#ffc6e0", "bottom": "#ffe8f2", "sun": "#fff0f6", "stars": 0.0, "clouds": 0.7, "ambient": "#e6c9f0"},
}

signal clicked(id: String)

var _sounds := {}  # Sound id -> the player node while it plays
var tree: PlaceTree
## Studio: everything is still (no physics), transforms apply instantly.
var editing := false
var strings := {}
var lang := "en"

var _parts := {}  # id -> {body, mesh, shape}
var _texts := {}  # id -> Label3D
var _lights := {}  # id -> OmniLight3D
var _targets := {}  # id -> Transform3D (smoothed replicated movement)
var _held := {}  # part id -> tool id, for parts of a Tool someone is holding
## Still parts are drawn merged (see PartBatcher); the game only, not Studio.
var _batcher: PartBatcher
var _moves := {}  # part id -> [count, since] (parts that keep moving stay separate)
var _pmeshes := {}  # ProceduralMesh id -> {body, mi, shape}
var _pmesh_data := {}  # ProceduralMesh id -> {v, c, t} (flat arrays from the runtime)
var _pmesh_dirty := {}  # ids to rebuild this frame
var _dynamic := {}  # part id -> true
var _holding: Array = []  # avatars that held something last frame
## Game: the avatar drawn for a character Model id (null if none), so held tools
## can follow its hand.
var avatar_of: Callable
var _sun: DirectionalLight3D
var _env: Environment
var _sky_mat: ShaderMaterial
var _quality := "high"
var _noise := {}


func _ready() -> void:
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun.directional_shadow_max_distance = 80.0
	add_child(_sun)
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	_apply_lighting()


func bind(t: PlaceTree) -> void:
	tree = t
	tree.added.connect(_on_added)
	tree.removed.connect(_on_removed)
	tree.changed.connect(_on_changed)
	tree.reparented.connect(_on_reparented)
	var ws := tree.service("Workspace")
	if ws != "":
		for id in tree.descendants(ws):
			_build(id)
	_apply_lighting()


func apply_quality(q: String) -> void:
	_quality = q
	_apply_lighting()


func in_world(id: String) -> bool:
	var ws := tree.service("Workspace")
	return ws != "" and tree.is_descendant(id, ws)


func body_of(id: String) -> CollisionObject3D:
	return _parts.get(id, {}).get("body")


func mesh_of(id: String) -> MeshInstance3D:
	return _parts.get(id, {}).get("mesh")


## Which instance a physics body belongs to ("" if none).
static func id_of(obj: Object) -> String:
	if obj and obj.has_meta("place_id"):
		return str(obj.get_meta("place_id"))
	return ""


func localize(text: String) -> String:
	if text.begins_with("$") and strings.has(text.substr(1)):
		var e: Dictionary = strings[text.substr(1)]
		return str(e.get(lang, e.get("en", text)))
	return text


# --- tree events -------------------------------------------------------------------

func _on_added(id: String) -> void:
	if in_world(id):
		_build(id)
	elif _is_lighting(id):
		_apply_lighting()


func _on_removed(id: String, _parent: String) -> void:
	stop_sound(id)
	_destroy(id)
	_pmesh_data.erase(id)
	if tree.cls(id) == "" and (_is_sky_class(id)):
		pass
	_apply_lighting()


func _on_reparented(id: String, _old: String) -> void:
	var ids := [id] + tree.descendants(id)
	for x in ids:
		_destroy(x)
	if in_world(id):
		for x in ids:
			_build(x)
	_apply_lighting()


func _on_changed(id: String, key: String) -> void:
	var c := tree.cls(id)
	if _parts.has(id):
		if key == "Position" or key == "Rotation":
			_move_part(id)
		elif key == "Anchored" and not editing:
			_destroy(id)
			_build(id)
		else:
			_style_part(id)
	elif _pmeshes.has(id):
		if key == "Position" or key == "Rotation":
			_pmeshes[id].body.global_transform = _transform_of(id)
		else:
			_pmesh_dirty[id] = true
	elif _texts.has(id):
		_style_text(id)
	elif _lights.has(id):
		_style_light(id)
	elif _sounds.has(id):
		if key == "Volume" or key == "Pitch":
			_style_sound(id, _sounds[id])
		elif key == "Playing" and tree.prop(id, "Playing") != true:
			stop_sound(id)
	if _is_lighting(id):
		_apply_lighting()


func _is_lighting(id: String) -> bool:
	var c := tree.cls(id)
	return c == "Lighting" or c == "Sky" or c == "Workspace"


func _is_sky_class(id: String) -> bool:
	return tree.cls(id) == "Sky"


# --- building ----------------------------------------------------------------------

func _build(id: String) -> void:
	var c := tree.cls(id)
	# A character's root is only a hitbox for scripts; players are drawn as Mellys.
	if not editing and c == "Part" and tree.name_of(id) == "HumanoidRootPart" and _is_character(tree.parent_of(id)):
		return
	if c == "ProceduralMesh":
		_build_pmesh(id)
	elif StudioSchema.is_a(c, "BasePart"):
		_build_part(id)
	elif c == "Text3D":
		_build_text(id)
	elif c == "PointLight":
		_build_light(id)
	elif c == "ClickDetector":
		var body := body_of(tree.parent_of(id))
		if body:
			body.set_meta("clickable", true)


func _destroy(id: String) -> void:
	if _parts.has(id):
		var body: Node = _parts[id].body
		# Lights hanging on this part go with it; forget them first.
		for lid in _lights.keys():
			if not is_instance_valid(_lights[lid]) or _lights[lid].get_parent() == body:
				_lights.erase(lid)
		body.queue_free()
		_parts.erase(id)
		_targets.erase(id)
		_held.erase(id)
		if _batcher:
			_batcher.remove(id)
	if _pmeshes.has(id):
		_pmeshes[id].body.queue_free()
		_pmeshes.erase(id)
	if _texts.has(id):
		_texts[id].queue_free()
		_texts.erase(id)
	if _lights.has(id):
		if is_instance_valid(_lights[id]):
			_lights[id].queue_free()
		_lights.erase(id)


func _transform_of(id: String) -> Transform3D:
	var pos: Variant = tree.prop(id, "Position")
	var rot: Variant = tree.prop(id, "Rotation")
	var p: Vector3 = pos if pos is Vector3 else Vector3.ZERO
	var r: Vector3 = rot if rot is Vector3 else Vector3.ZERO
	var b := Basis.from_euler(Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z)))
	return Transform3D(b, p)


func _is_character(id: String) -> bool:
	return id != "" and tree.cls(id) == "Model" and tree.child_of_class(id, "Humanoid") != ""


## The Tool a part belongs to if that tool is in a character's hand, else "".
func _held_tool(id: String) -> String:
	var cur := tree.parent_of(id)
	while cur != "" and cur != PlaceTree.ROOT:
		if tree.cls(cur) == "Tool":
			return cur if _is_character(tree.parent_of(cur)) else ""
		cur = tree.parent_of(cur)
	return ""


func _build_part(id: String) -> void:
	var anchored: bool = tree.prop(id, "Anchored")
	var tool := "" if editing else _held_tool(id)
	var body: CollisionObject3D
	if tool != "":
		# Carried: moved with the hand every frame, touching nothing.
		var hb := AnimatableBody3D.new()
		hb.sync_to_physics = false
		body = hb
		_held[id] = tool
	elif editing or anchored:
		var ab := AnimatableBody3D.new()
		ab.sync_to_physics = not editing
		body = ab
	else:
		body = RigidBody3D.new()
	body.set_meta("place_id", id)
	var mesh := MeshInstance3D.new()
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	body.add_child(shape)
	add_child(body)
	body.global_transform = _transform_of(id)
	_parts[id] = {"body": body, "mesh": mesh, "shape": shape}
	_style_part(id)
	if tool != "":
		body.collision_layer = 0
		body.collision_mask = 0
	# Lights and click detectors that were already inside this part.
	for k in tree.kids(id):
		_build(k)


func _move_part(id: String) -> void:
	if _held.has(id):
		return  # follows the hand
	if _batcher and _batcher.has(id):
		# A part that keeps moving (a door, a platform) stops being merged.
		var now := Time.get_ticks_msec()
		var m: Array = _moves.get(id, [0, now])
		if now - int(m[1]) > 3000:
			m = [0, now]
		m[0] += 1
		_moves[id] = m
		if int(m[0]) >= 3:
			_dynamic[id] = true
			_batcher.remove(id)
			_parts[id].mesh.visible = true
		else:
			var e: Dictionary = _parts[id]
			e.body.global_transform = _transform_of(id)
			_batcher.put(id, e.mesh.mesh, _transform_of(id), tree.prop(id, "Color"), str(tree.prop(id, "Material")), e.mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			return
	var body: Node3D = _parts[id].body
	var t := _transform_of(id)
	if editing or body is RigidBody3D or body.global_position.distance_to(t.origin) > 12.0:
		body.global_transform = t
		_targets.erase(id)
	else:
		# Replicated movement arrives ~20 times a second; glide between updates.
		_targets[id] = t


func _process(_delta: float) -> void:
	if not _held.is_empty() or not _holding.is_empty():
		_follow_hands()
	if not _pmesh_dirty.is_empty():
		for id in _pmesh_dirty:
			if _pmeshes.has(id):
				_style_pmesh(id)
		_pmesh_dirty.clear()


# --- ProceduralMesh --------------------------------------------------------------

## New shape data for a ProceduralMesh (all of it, or some points).
func mesh_op(op: Dictionary) -> void:
	var id := str(op.get("id", ""))
	if str(op.get("o", "")) == "mesh":
		_pmesh_data[id] = {"v": op.get("v", []), "c": op.get("c", []), "t": op.get("t", [])}
	else:
		var d: Dictionary = _pmesh_data.get(id, {})
		if d.is_empty():
			return
		var idx: Array = op.get("i", [])
		var v: Array = op.get("v", [])
		var c: Array = op.get("c", [])
		for k in idx.size():
			var i := int(idx[k])
			for a in 3:
				d.v[i * 3 + a] = v[k * 3 + a]
				d.c[i * 3 + a] = c[k * 3 + a]
	_pmesh_dirty[id] = true


func _build_pmesh(id: String) -> void:
	var body := StaticBody3D.new()
	body.set_meta("place_id", id)
	var mi := MeshInstance3D.new()
	body.add_child(mi)
	var shape := CollisionShape3D.new()
	body.add_child(shape)
	add_child(body)
	body.global_transform = _transform_of(id)
	_pmeshes[id] = {"body": body, "mi": mi, "shape": shape}
	_style_pmesh(id)


func _style_pmesh(id: String) -> void:
	var e: Dictionary = _pmeshes[id]
	var mi: MeshInstance3D = e.mi
	var body: StaticBody3D = e.body
	var d: Dictionary = _pmesh_data.get(id, {})
	var t: Array = d.get("t", [])
	var v: Array = d.get("v", [])
	var c: Array = d.get("c", [])
	var faces := PackedVector3Array()
	if t.size() < 3:
		mi.mesh = null
		e.shape.shape = null
		return
	var smooth: bool = tree.prop(id, "Smooth")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pt := func(i: int) -> Vector3: return Vector3(float(v[i * 3]), float(v[i * 3 + 1]), float(v[i * 3 + 2]))
	var col := func(i: int) -> Color: return Color(float(c[i * 3]), float(c[i * 3 + 1]), float(c[i * 3 + 2])) if i * 3 + 2 < c.size() else Color.WHITE
	faces.resize(t.size())
	if smooth:
		for i in v.size() / 3:
			st.set_color(col.call(i))
			st.add_vertex(pt.call(i))
		# Godot draws clockwise triangles as the front; scripts give them counter-clockwise.
		for k in range(0, t.size() - 2, 3):
			st.add_index(int(t[k]))
			st.add_index(int(t[k + 2]))
			st.add_index(int(t[k + 1]))
		st.generate_normals()
	for k in range(0, t.size() - 2, 3):
		var a := int(t[k])
		var b := int(t[k + 1])
		var cc := int(t[k + 2])
		var pa: Vector3 = pt.call(a)
		var pb: Vector3 = pt.call(b)
		var pc: Vector3 = pt.call(cc)
		faces[k] = pa
		faces[k + 1] = pc
		faces[k + 2] = pb
		if not smooth:
			var n := (pb - pa).cross(pc - pa).normalized()
			for q in [[pa, a], [pc, cc], [pb, b]]:
				st.set_normal(n)
				st.set_color(col.call(q[1]))
				st.add_vertex(q[0])
	mi.mesh = st.commit()
	var transparency: float = tree.prop(id, "Transparency")
	var m := _kind_material(str(tree.prop(id, "Material")))
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if transparency > 0.001:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = 1.0 - transparency
	mi.material_override = m
	mi.visible = transparency < 0.999 or editing
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if tree.prop(id, "CastShadow") and transparency < 0.5 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cs := ConcavePolygonShape3D.new()
	cs.backface_collision = true
	cs.set_faces(faces)
	e.shape.shape = cs
	body.collision_layer = LAYER_WORLD if tree.prop(id, "CanCollide") else LAYER_GHOST


## Held tools: every part keeps its place relative to the Handle, and the Handle
## sits in the palm (shifted by the tool's GripOffset / GripRotation).
func _follow_hands() -> void:
	var now: Array = []
	var by_tool := {}
	for pid in _held:
		var tid: String = _held[pid]
		if not by_tool.has(tid):
			by_tool[tid] = []
		by_tool[tid].append(pid)
	for tid in by_tool:
		var avatar: MellyAvatar = avatar_of.call(tree.parent_of(tid)) if avatar_of.is_valid() else null
		var hand: Node3D = avatar.hand_r() if avatar else null
		var handle := tree.child_named(tid, "Handle")
		if handle == "" or not _parts.has(handle):
			handle = by_tool[tid][0]
		var grip_rot: Vector3 = tree.prop(tid, "GripRotation")
		var grip := Transform3D(Basis.from_euler(grip_rot * (PI / 180.0)), tree.prop(tid, "GripOffset"))
		var base := Transform3D()
		if hand:
			base = hand.global_transform.orthonormalized() * grip * _transform_of(handle).affine_inverse()
			if not now.has(avatar):
				now.append(avatar)
		for pid in by_tool[tid]:
			var body: Node3D = _parts[pid].body
			body.visible = hand != null
			if hand:
				body.global_transform = base * _transform_of(pid)
	for a in _holding:
		if is_instance_valid(a) and not now.has(a):
			a.holding = false
	for a in now:
		a.holding = true
	_holding = now


func _physics_process(delta: float) -> void:
	for id in _targets.keys():
		var entry: Dictionary = _parts.get(id, {})
		if entry.is_empty():
			_targets.erase(id)
			continue
		var body: Node3D = entry.body
		var t: Transform3D = _targets[id]
		body.global_transform = body.global_transform.interpolate_with(t, minf(1.0, delta * 18.0))
		if body.global_position.distance_to(t.origin) < 0.002:
			body.global_transform = t
			_targets.erase(id)


func _style_part(id: String) -> void:
	var entry: Dictionary = _parts[id]
	var body: CollisionObject3D = entry.body
	var mesh: MeshInstance3D = entry.mesh
	var shape: CollisionShape3D = entry.shape
	var c := tree.cls(id)
	var size: Vector3 = tree.prop(id, "Size")
	size = size.max(Vector3.ONE * 0.05)
	var kind := str(tree.prop(id, "Shape")) if c == "Part" else "Block"
	match kind:
		"Ball":
			var d := minf(size.x, minf(size.y, size.z))
			var sm := SphereMesh.new()
			sm.radius = d / 2.0
			sm.height = d
			sm.radial_segments = 24
			sm.rings = 12
			mesh.mesh = sm
			var ss := SphereShape3D.new()
			ss.radius = d / 2.0
			shape.shape = ss
		"Cylinder":
			var cm := CylinderMesh.new()
			cm.top_radius = minf(size.x, size.z) / 2.0
			cm.bottom_radius = cm.top_radius
			cm.height = size.y
			cm.radial_segments = 24
			cm.rings = 0
			mesh.mesh = cm
			var cs := CylinderShape3D.new()
			cs.radius = cm.top_radius
			cs.height = size.y
			shape.shape = cs
		"Wedge":
			var pts := _wedge_points(size)
			mesh.mesh = _wedge_mesh(pts)
			var ws := ConvexPolygonShape3D.new()
			ws.points = PackedVector3Array(pts)
			shape.shape = ws
		_:
			var bm := BoxMesh.new()
			bm.size = size
			mesh.mesh = bm
			var bs := BoxShape3D.new()
			bs.size = size
			shape.shape = bs
	var collide: bool = tree.prop(id, "CanCollide")
	body.collision_layer = 0 if _held.has(id) else (LAYER_WORLD if collide else LAYER_GHOST)
	body.collision_mask = LAYER_WORLD if body is RigidBody3D else 0
	var transparency: float = tree.prop(id, "Transparency")
	# Invisible parts (like a character's root) are skipped by the renderer.
	mesh.visible = transparency < 0.999 or editing
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if tree.prop(id, "CastShadow") and transparency < 0.5 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.material_override = _material(id, transparency)
	if c == "SpawnLocation":
		_spawn_decal(id, mesh, size)
	_batch(id)


## Merged drawing for still, solid, plain parts; everything else draws itself.
func _batch(id: String) -> void:
	if editing:
		return
	var e: Dictionary = _parts[id]
	var mesh: MeshInstance3D = e.mesh
	var kind := str(tree.prop(id, "Material"))
	var ok: bool = e.body is AnimatableBody3D and not _held.has(id) and not _dynamic.has(id) \
		and float(tree.prop(id, "Transparency")) < 0.001 and str(tree.prop(id, "Texture")) == "" \
		and PartBatcher.batchable_kind(kind) and tree.cls(id) != "SpawnLocation"
	if not ok:
		if _batcher and _batcher.has(id):
			_batcher.remove(id)
			mesh.visible = float(tree.prop(id, "Transparency")) < 0.999
		return
	if _batcher == null:
		_batcher = PartBatcher.new()
		_batcher.material_for = _kind_material
		add_child(_batcher)
	mesh.visible = false
	_batcher.put(id, mesh.mesh, _transform_of(id), tree.prop(id, "Color"), kind, mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


## The look of a material with a white color (merged parts bring their own colors).
func _kind_material(kind: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.roughness = 0.65
	match kind:
		"SmoothPlastic":
			m.roughness = 0.3
		"Metal":
			m.metallic = 0.75
			m.roughness = 0.35
		"Wood", "Grass", "Brick", "Concrete", "Fabric", "Sand":
			m.roughness = 0.9
			m.albedo_texture = _noise_texture(kind)
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3.ONE * 0.5
	return m


func _wedge_points(s: Vector3) -> Array:
	var h := s / 2.0
	# A ramp: full height at the back (-Z), down to nothing at the front (+Z).
	return [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z),
		Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z),
	]


func _wedge_mesh(p: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := [
		[0, 2, 1], [0, 3, 2],  # bottom
		[0, 1, 5], [0, 5, 4],  # back
		[4, 5, 2], [4, 2, 3],  # slope
		[0, 4, 3], [1, 2, 5],  # sides
	]
	for t in tris:
		var a: Vector3 = p[t[0]]
		var b: Vector3 = p[t[1]]
		var c: Vector3 = p[t[2]]
		var n := (b - a).cross(c - a).normalized()
		for v in [a, c, b]:
			st.set_normal(-n)
			st.add_vertex(v)
	return st.commit()


func _spawn_decal(id: String, mesh: MeshInstance3D, size: Vector3) -> void:
	var old := mesh.get_node_or_null("Pad")
	if old:
		old.queue_free()
	var pad := MeshInstance3D.new()
	pad.name = "Pad"
	var q := QuadMesh.new()
	q.size = Vector2(minf(size.x, size.z) * 0.6, minf(size.x, size.z) * 0.6)
	pad.mesh = q
	pad.rotation_degrees.x = -90
	pad.position.y = size.y / 2.0 + 0.01
	var m := StandardMaterial3D.new()
	m.albedo_texture = _spawn_texture()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pad.material_override = m
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.add_child(pad)


static var _spawn_tex: Texture2D
static func _spawn_texture() -> Texture2D:
	if _spawn_tex:
		return _spawn_tex
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in n:
		for x in n:
			var d := Vector2(x - n / 2.0, y - n / 2.0).length() / (n / 2.0)
			if d < 0.95 and d > 0.78:
				img.set_pixel(x, y, Color(1, 1, 1, 0.85))
			elif d < 0.45:
				img.set_pixel(x, y, Color(1, 1, 1, 0.85 * (1.0 - d / 0.45 * 0.3)))
	_spawn_tex = ImageTexture.create_from_image(img)
	return _spawn_tex


func _material(id: String, transparency: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var color: Color = tree.prop(id, "Color")
	var kind := str(tree.prop(id, "Material"))
	m.albedo_color = color
	m.roughness = 0.65
	match kind:
		"SmoothPlastic":
			m.roughness = 0.3
		"Neon":
			m.emission_enabled = true
			m.emission = color
			m.emission_energy_multiplier = 1.8
		"Metal":
			m.metallic = 0.75
			m.roughness = 0.35
		"Glass":
			transparency = maxf(transparency, 0.55)
			m.roughness = 0.05
			m.metallic = 0.2
		"Ice":
			transparency = maxf(transparency, 0.2)
			m.roughness = 0.1
		"Wood", "Grass", "Brick", "Concrete", "Fabric", "Sand":
			m.roughness = 0.9
			m.albedo_texture = _noise_texture(kind)
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3.ONE * 0.5
	if transparency > 0.001:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = 1.0 - transparency
	var tex := str(tree.prop(id, "Texture"))
	if tex != "":
		var scale: float = maxf(float(tree.prop(id, "TextureScale")), 0.05)
		m.uv1_triplanar = true
		m.uv1_world_triplanar = false
		m.uv1_scale = Vector3.ONE / scale
		AssetCache.fetch(tex, func(t: Texture2D):
			if t and is_instance_valid(self) and _parts.has(id):
				m.albedo_texture = t)
	return m


func _noise_texture(kind: String) -> Texture2D:
	if _noise.has(kind):
		return _noise[kind]
	var n := FastNoiseLite.new()
	n.seed = kind.hash()
	match kind:
		"Wood":
			n.frequency = 0.02
			n.fractal_octaves = 2
		"Brick", "Concrete":
			n.frequency = 0.08
		_:
			n.frequency = 0.05
	var img := n.get_seamless_image(128, 128)
	img.convert(Image.FORMAT_RGBA8)
	# Keep it subtle: the part's own color stays in charge.
	for y in img.get_height():
		for x in img.get_width():
			var v := img.get_pixel(x, y).r
			var l := 0.82 + v * 0.18
			if kind == "Brick" and (y % 32 < 2 or ((x + (16 if (y / 32) % 2 == 1 else 0)) % 64) < 2):
				l = 0.7
			img.set_pixel(x, y, Color(l, l, l))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_noise[kind] = tex
	return tex


func _build_text(id: String) -> void:
	var l := Label3D.new()
	l.set_meta("place_id", id)
	add_child(l)
	_texts[id] = l
	_style_text(id)


func _style_text(id: String) -> void:
	var l: Label3D = _texts[id]
	l.global_transform = _transform_of(id)
	l.text = localize(str(tree.prop(id, "Text")))
	l.modulate = tree.prop(id, "TextColor")
	l.outline_modulate = tree.prop(id, "OutlineColor")
	l.font_size = int(tree.prop(id, "TextSize"))
	l.outline_size = maxi(4, l.font_size / 6)
	l.pixel_size = 0.01
	l.font = {"Regular": UI.font_regular, "Bold": UI.font_bold}.get(str(tree.prop(id, "Font")), UI.font_black)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED if tree.prop(id, "Billboard") else BaseMaterial3D.BILLBOARD_DISABLED
	l.visible = tree.prop(id, "Visible")
	l.double_sided = true


func _build_light(id: String) -> void:
	var parent := tree.parent_of(id)
	var holder: Node3D = body_of(parent)
	if holder == null:
		return
	var light := OmniLight3D.new()
	light.set_meta("place_id", id)
	holder.add_child(light)
	_lights[id] = light
	_style_light(id)


func _style_light(id: String) -> void:
	var light: OmniLight3D = _lights[id]
	light.light_color = tree.prop(id, "Color")
	light.light_energy = float(tree.prop(id, "Brightness"))
	light.omni_range = float(tree.prop(id, "Range"))
	light.visible = tree.prop(id, "Enabled")
	light.position = tree.prop(id, "Offset")
	light.shadow_enabled = false


# --- lighting & sky ----------------------------------------------------------------

func _apply_lighting() -> void:
	if tree == null or _env == null:
		return
	var lid := tree.service("Lighting")
	var clock := 14.0
	var brightness := 1.0
	var ambient := Color("#8d88a8")
	var fog := true
	var fog_color := Color("#d9ecff")
	var fog_end := 500.0
	var shadows := true
	if lid != "":
		clock = float(tree.prop(lid, "ClockTime"))
		brightness = float(tree.prop(lid, "Brightness"))
		ambient = tree.prop(lid, "Ambient")
		fog = tree.prop(lid, "FogEnabled")
		fog_color = tree.prop(lid, "FogColor")
		fog_end = float(tree.prop(lid, "FogEnd"))
		shadows = tree.prop(lid, "Shadows")
	# Sun path: rises at 6:00 in the east, overhead at noon, sets at 18:00.
	var day := clock >= 6.0 and clock <= 18.0
	var t := (clock - 6.0) / 12.0 if day else fposmod(clock - 18.0, 24.0) / 12.0
	var elev := sin(t * PI) * deg_to_rad(70.0) + deg_to_rad(8.0)
	_sun.rotation = Vector3(-elev, deg_to_rad(-90.0 + t * 180.0), 0)
	_sun.light_energy = brightness * (1.0 if day else 0.18)
	_sun.light_color = Color("#fff4e0") if day else Color("#aebcff")
	_sun.shadow_enabled = shadows and _quality != "low"

	var sky_id := tree.child_of_class(lid, "Sky") if lid != "" else ""
	var preset := "Day"
	if sky_id != "":
		preset = str(tree.prop(sky_id, "Preset"))
	elif not day:
		preset = "Night"
	var p: Dictionary = SKY_PRESETS.get(preset, SKY_PRESETS.Day)
	if sky_id == "" and lid != "" and day:
		p = p.duplicate()
		p.top = "#" + (tree.prop(lid, "SkyTop") as Color).to_html(false)
		p.horizon = "#" + (tree.prop(lid, "SkyHorizon") as Color).to_html(false)
	_sky_mat.set_shader_parameter("custom", preset == "Custom")
	_sky_mat.set_shader_parameter("top_color", Color(p.top))
	_sky_mat.set_shader_parameter("horizon_color", Color(p.horizon))
	_sky_mat.set_shader_parameter("bottom_color", Color(p.bottom))
	_sky_mat.set_shader_parameter("sun_color", Color(p.sun))
	var show_sun := true
	var show_clouds := true
	var show_stars := false
	if sky_id != "":
		show_sun = tree.prop(sky_id, "SunVisible")
		show_clouds = tree.prop(sky_id, "CloudsVisible")
		show_stars = tree.prop(sky_id, "StarsVisible")
	_sky_mat.set_shader_parameter("sun_visible", show_sun)
	_sky_mat.set_shader_parameter("clouds", float(p.clouds) if show_clouds and _quality != "low" else 0.0)
	_sky_mat.set_shader_parameter("stars", maxf(float(p.stars), 1.0 if show_stars else 0.0))
	if preset == "Custom" and sky_id != "":
		for face: String in ["Up", "Down", "Front", "Back", "Left", "Right"]:
			var ref := str(tree.prop(sky_id, "Skybox" + face))
			var param := "face_" + face.to_lower()
			AssetCache.fetch(ref, func(tex: Texture2D):
				if tex and is_instance_valid(self):
					_sky_mat.set_shader_parameter(param, tex))
	_env.ambient_light_color = ambient.lerp(Color(p.ambient), 0.5)
	_env.ambient_light_energy = 0.9 if day else 0.5
	_env.fog_enabled = fog and _quality != "low"
	_env.fog_light_color = fog_color
	# Linear, like FogStart/FogEnd: clear up close, fully fogged at FogEnd.
	_env.fog_mode = Environment.FOG_MODE_DEPTH
	_env.fog_density = 1.0
	_env.fog_depth_begin = maxf(fog_end, 10.0) * 0.35
	_env.fog_depth_end = maxf(fog_end, 10.0)
	_env.fog_depth_curve = 1.0
	_env.fog_sky_affect = 0.0


# --- sounds ------------------------------------------------------------------------

## Sound:Play(). Built-in sounds and uploaded ones (asset://). A Sound inside a part
## is heard from that part; anywhere else it plays for the whole screen.
func play_sound(id: String) -> void:
	if not tree.has(id):
		return
	var ref := str(tree.prop(id, "SoundId"))
	if ref.begins_with("asset://"):
		AudioCache.fetch(ref, func(stream: AudioStream):
			if stream and tree.has(id) and str(tree.prop(id, "SoundId")) == ref:
				_start_sound(id, stream))
	else:
		var st := Sfx.stream(ref)
		if st:
			_start_sound(id, st)


func stop_sound(id: String) -> void:
	var p: Node = _sounds.get(id)
	_sounds.erase(id)
	if is_instance_valid(p):
		p.queue_free()


func _start_sound(id: String, stream: AudioStream) -> void:
	stop_sound(id)
	var looped: bool = tree.prop(id, "Looped") == true
	if looped:
		stream = stream.duplicate()
		if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
			stream.set("loop", true)
		elif stream is AudioStreamWAV:
			var w := stream as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_end = int(w.get_length() * w.mix_rate)
	var parent := tree.parent_of(id)
	var holder: Node = body_of(parent) if parent != "" and tree.is_a(parent, "BasePart") else null
	var p: Node
	if holder:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 12.0
		p3.max_distance = 150.0
		holder.add_child(p3)
		p = p3
	else:
		p = AudioStreamPlayer.new()
		add_child(p)
	p.set("stream", stream)
	_style_sound(id, p)
	p.connect("finished", func():
		if _sounds.get(id) == p:
			_sounds.erase(id)
		p.queue_free())
	_sounds[id] = p
	p.call("play")


func _style_sound(id: String, p: Node) -> void:
	var vol := clampf(float(tree.prop(id, "Volume")), 0.0, 2.0)
	var db := linear_to_db(maxf(vol, 0.0001))
	if p is AudioStreamPlayer3D:
		(p as AudioStreamPlayer3D).volume_db = db
	else:
		(p as AudioStreamPlayer).volume_db = db
	p.set("pitch_scale", clampf(float(tree.prop(id, "Pitch")), 0.1, 4.0))