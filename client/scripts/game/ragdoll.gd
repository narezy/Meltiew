class_name Ragdoll
extends Node3D
## Death effect: Melly goes limp. Six rigid blocks joined at the neck,
## shoulders and hips flop over as one body, with a sad face on the head.

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
		var mesh := BoxMesh.new()
		mesh.size = spec[0]
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(str(colors.get(part, "#ffffff")))
		m.roughness = 0.8
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = m
		_mats.append(m)
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = spec[0] * 0.95
		cs.shape = shape
		body.add_child(cs)
		if part == "head":
			var face := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = Vector2(0.42, 0.42)
			face.mesh = quad
			var fm := StandardMaterial3D.new()
			fm.albedo_texture = Faces.texture(Faces.SAD)
			fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			face.material_override = fm
			_mats.append(fm)
			# Face the same way Melly faced (-Z), just in front of the head box.
			face.position = Vector3(0, 0, -spec[0].z * 0.5 - 0.005)
			face.rotation.y = PI
			body.add_child(face)
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
