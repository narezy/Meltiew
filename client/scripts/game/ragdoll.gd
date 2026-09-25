class_name Ragdoll
extends Node3D
## Death effect: Melly goes limp. Her six body parts (cut out of the real,
## rounded model) are joined at the neck, shoulders and hips and flop over as
## one body, with a sad face on the head.

const LIFETIME := 3.2
const PARTS := {
	# part: [size (m), center offset from feet (m)]
	"head": [Vector3(0.47, 0.46, 0.46), Vector3(0, 1.58, 0)],
	"torso": [Vector3(0.56, 0.68, 0.27), Vector3(0, 1.02, 0)],
	"arm_l": [Vector3(0.28, 0.68, 0.26), Vector3(-0.43, 1.0, 0)],
	"arm_r": [Vector3(0.28, 0.68, 0.26), Vector3(0.43, 1.0, 0)],
	"leg_l": [Vector3(0.27, 0.68, 0.29), Vector3(-0.15, 0.34, 0)],
	"leg_r": [Vector3(0.27, 0.68, 0.29), Vector3(0.15, 0.34, 0)],
}
## Where each limb hangs off the torso (offset from feet). Melly's model is turned
## 180°, so her left side is at -X here.
const JOINTS := {
	"head": Vector3(0, 1.36, 0),
	"arm_l": Vector3(-0.36, 1.3, 0),
	"arm_r": Vector3(0.36, 1.3, 0),
	"leg_l": Vector3(-0.15, 0.68, 0),
	"leg_r": Vector3(0.15, 0.68, 0),
}

var _mats: Array[StandardMaterial3D] = []

## part -> ArrayMesh around the part's center; surface 1 of the head is the face.
static var _meshes := {}


## Splits Melly's skinned body into one mesh per part, in her rest pose and in
## avatar space (feet at origin, facing -Z), like the avatar shader colors them.
static func _part_meshes() -> Dictionary:
	if not _meshes.is_empty():
		return _meshes
	var model: Node3D = MellyAvatar.MODEL.instantiate()
	var body: MeshInstance3D = model.find_child("Body", true, false)
	var xf := Transform3D()
	var n: Node = body
	while n != model:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	xf = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * MellyAvatar.MODEL_SCALE), Vector3.ZERO) * xf
	var tools := {}
	for s in body.mesh.get_surface_count():
		var a := body.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var uvs: Variant = a[Mesh.ARRAY_TEX_UV]
		var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var index: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var per := bones.size() / verts.size()
		for t in range(0, index.size(), 3):
			var part: String = MellyAvatar.JOINT_ORDER[clampi(bones[index[t] * per], 0, 5)]
			var key := part + ":" + str(s)
			if not tools.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[key] = st
			var st: SurfaceTool = tools[key]
			var center: Vector3 = PARTS[part][1]
			for k in 3:
				var i := index[t + k]
				st.set_normal((xf.basis * normals[i]).normalized())
				if uvs != null:
					st.set_uv(uvs[i])
				st.add_vertex(xf * verts[i] - center)
	for part in PARTS:
		var mesh := ArrayMesh.new()
		for s in 2:
			var st: SurfaceTool = tools.get(part + ":" + str(s))
			if st:
				st.commit(mesh)
		_meshes[part] = mesh
	model.free()
	return _meshes


## `at` is the avatar's transform (feet at origin, facing -Z).
static func spawn(parent: Node, at: Transform3D, colors: Dictionary, velocity := Vector3.ZERO) -> Ragdoll:
	var r := Ragdoll.new()
	parent.add_child(r)
	r._build(at, colors, velocity)
	Sfx.play("break", 0.8)
	return r


func _build(at: Transform3D, colors: Dictionary, velocity: Vector3) -> void:
	var bodies := {}
	for part in PARTS:
		var spec: Array = PARTS[part]
		var body := RigidBody3D.new()
		body.mass = 3.0 if part == "torso" else 1.0
		body.collision_layer = 4
		body.collision_mask = 1
		body.linear_damp = 0.2
		body.angular_damp = 1.5
		var pm := PhysicsMaterial.new()
		pm.friction = 0.9
		pm.bounce = 0.1
		body.physics_material_override = pm
		var mi := MeshInstance3D.new()
		mi.mesh = _part_meshes()[part]
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(str(colors.get(part, "#ffffff")))
		m.roughness = 0.75
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.set_surface_override_material(0, m)
		_mats.append(m)
		if part == "head" and mi.mesh.get_surface_count() > 1:
			var fm := StandardMaterial3D.new()
			fm.albedo_texture = Faces.texture(Faces.SAD)
			fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mi.set_surface_override_material(1, fm)
			_mats.append(fm)
		body.add_child(mi)
		# Physics stays a box (cheap and stable); only what you see is rounded.
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = spec[0] * 0.95
		cs.shape = shape
		body.add_child(cs)
		add_child(body)
		body.global_transform = Transform3D(at.basis, at * spec[1])
		body.linear_velocity = velocity
		bodies[part] = body
	# Joints keep the limbs attached so the body crumples instead of scattering.
	for part in JOINTS:
		var j := ConeTwistJoint3D.new()
		add_child(j)
		j.global_transform = Transform3D(at.basis, at * JOINTS[part])
		j.node_a = j.get_path_to(bodies.torso)
		j.node_b = j.get_path_to(bodies[part])
		j.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(70 if part.begins_with("arm") else 45))
		j.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(20))
	# A shove backwards and a little spin so it tips over like a ragdoll.
	var back := at.basis * Vector3(randf_range(-0.4, 0.4), 0.3, 1.0)
	bodies.torso.apply_impulse(back.normalized() * 6.0, at.basis * Vector3(0, 0.3, 0))
	bodies.head.apply_central_impulse(back.normalized() * 1.2)
	var t := create_tween()
	t.tween_interval(LIFETIME - 0.5)
	t.tween_method(_fade, 1.0, 0.0, 0.5)
	t.tween_callback(queue_free)


func _fade(a: float) -> void:
	for m in _mats:
		m.albedo_color.a = a
