class_name Shatter
extends RefCounted
## Death effect: the avatar falls apart into its six colored blocks.

const PARTS := [
	# part, size (m), offset from feet (m)
	["head", Vector3(0.47, 0.46, 0.46), Vector3(0, 1.58, 0)],
	["torso", Vector3(0.56, 0.68, 0.27), Vector3(0, 1.02, 0)],
	["arm_l", Vector3(0.28, 0.68, 0.26), Vector3(0.41, 1.0, 0)],
	["arm_r", Vector3(0.28, 0.68, 0.26), Vector3(-0.41, 1.0, 0)],
	["leg_l", Vector3(0.27, 0.68, 0.29), Vector3(0.15, 0.34, 0)],
	["leg_r", Vector3(0.27, 0.68, 0.29), Vector3(-0.15, 0.34, 0)],
]


static func spawn(parent: Node, at: Transform3D, colors: Dictionary) -> void:
	for p in PARTS:
		var body := RigidBody3D.new()
		body.mass = 0.6
		body.physics_material_override = PhysicsMaterial.new()
		body.physics_material_override.bounce = 0.35
		body.collision_layer = 4
		body.collision_mask = 1
		var mesh := BoxMesh.new()
		mesh.size = p[1]
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(str(colors.get(p[0], "#ffffff")))
		m.roughness = 0.7
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = m
		body.add_child(mi)
		var shape := BoxShape3D.new()
		shape.size = p[1]
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		parent.add_child(body)
		body.global_transform = Transform3D(at.basis, at * p[2])
		var out: Vector3 = (at.basis * Vector3(p[2].x, 0.4, randf_range(-0.3, 0.3))).normalized()
		body.apply_central_impulse(out * randf_range(1.5, 3.0) + Vector3.UP * randf_range(1.0, 2.5))
		body.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.3)
		var t := body.create_tween()
		t.tween_interval(2.4)
		t.tween_property(m, "albedo_color:a", 0.0, 0.5)
		t.tween_callback(body.queue_free)
	Sfx.play("break")
