class_name Hats
extends RefCounted
## Procedural hats built in melly.glb model units, relative to the Head bone.
## The head box spans x ±0.69, z ±0.67 and y 0..1.33 above the bone origin.

const TOP := 1.33


static func build(id: String) -> Node3D:
	match id:
		"catears":
			return _cat_ears()
		"cap":
			return _cap()
		"crown":
			return _crown()
		"halo":
			return _halo()
		"tophat":
			return _tophat()
		"flower":
			return _flower()
		"headphones":
			return _headphones()
	return null


static func _mat(color: Color, rough := 0.7, metal := 0.0, emission := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m


static func _part(root: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mi)
	return mi


static func _cat_ears() -> Node3D:
	var root := Node3D.new()
	var outer := PrismMesh.new()
	outer.size = Vector3(0.5, 0.55, 0.2)
	var inner := PrismMesh.new()
	inner.size = Vector3(0.3, 0.34, 0.06)
	var fur := _mat(Color("#302d38"))
	var pink := _mat(Color("#ff8fb1"))
	for side in [-1.0, 1.0]:
		var x: float = side * 0.42
		_part(root, outer, fur, Vector3(x, TOP + 0.2, -0.05), Vector3(0, 0, -side * 14.0))
		_part(root, inner, pink, Vector3(x + side * 0.02, TOP + 0.16, 0.06), Vector3(0, 0, -side * 14.0))
	return root


static func _cap() -> Node3D:
	var root := Node3D.new()
	var dome := SphereMesh.new()
	dome.radius = 0.74
	dome.height = 0.8
	dome.is_hemisphere = true
	var red := _mat(Color("#ff6b6b"))
	_part(root, dome, red, Vector3(0, TOP - 0.2, 0))
	var brim := BoxMesh.new()
	brim.size = Vector3(1.1, 0.07, 0.6)
	_part(root, brim, red, Vector3(0, TOP - 0.17, 0.85), Vector3(-6, 0, 0))
	var button := SphereMesh.new()
	button.radius = 0.08
	button.height = 0.16
	_part(root, button, _mat(Color("#f4f1ec")), Vector3(0, TOP + 0.2, 0))
	return root


static func _crown() -> Node3D:
	var root := Node3D.new()
	var gold := _mat(Color("#ffd166"), 0.3, 0.8)
	var band := CylinderMesh.new()
	band.top_radius = 0.5
	band.bottom_radius = 0.47
	band.height = 0.28
	_part(root, band, gold, Vector3(0, TOP + 0.12, 0))
	var spike := PrismMesh.new()
	spike.size = Vector3(0.22, 0.3, 0.08)
	var gem := SphereMesh.new()
	gem.radius = 0.06
	gem.height = 0.12
	var gems := [Color("#ff6b6b"), Color("#4cc9f0"), Color("#7ee0c3"), Color("#e056fd"), Color("#ff8fb1")]
	for i in 5:
		var a := TAU * i / 5.0
		var dir := Vector3(sin(a), 0, cos(a))
		var s := _part(root, spike, gold, dir * 0.47 + Vector3(0, TOP + 0.4, 0))
		s.rotation.y = a
		_part(root, gem, _mat(gems[i], 0.2, 0.0, 0.6), dir * 0.51 + Vector3(0, TOP + 0.12, 0))
	return root


static func _halo() -> Node3D:
	var root := Node3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.42
	ring.outer_radius = 0.55
	ring.rings = 32
	var glow := _mat(Color("#fff3b0"), 0.2, 0.0, 2.2)
	var mi := _part(root, ring, glow, Vector3(0, TOP + 0.45, 0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tween := mi.create_tween().set_loops()
	tween.tween_property(mi, "position:y", TOP + 0.58, 1.2).set_trans(Tween.TRANS_SINE)
	tween.tween_property(mi, "position:y", TOP + 0.45, 1.2).set_trans(Tween.TRANS_SINE)
	return root


static func _tophat() -> Node3D:
	var root := Node3D.new()
	var black := _mat(Color("#1f1c27"), 0.5)
	var brim := CylinderMesh.new()
	brim.top_radius = 0.82
	brim.bottom_radius = 0.82
	brim.height = 0.06
	_part(root, brim, black, Vector3(0, TOP + 0.03, 0))
	var body := CylinderMesh.new()
	body.top_radius = 0.5
	body.bottom_radius = 0.46
	body.height = 0.85
	_part(root, body, black, Vector3(0, TOP + 0.48, 0))
	var band := CylinderMesh.new()
	band.top_radius = 0.475
	band.bottom_radius = 0.47
	band.height = 0.14
	_part(root, band, _mat(Color("#b89cff")), Vector3(0, TOP + 0.16, 0))
	root.rotation_degrees.z = -6
	return root


static func _flower() -> Node3D:
	var root := Node3D.new()
	var petal := SphereMesh.new()
	petal.radius = 0.16
	petal.height = 0.12
	var core := SphereMesh.new()
	core.radius = 0.12
	core.height = 0.18
	var pink := _mat(Color("#ff8fb1"))
	var flower := Node3D.new()
	flower.position = Vector3(0.5, TOP - 0.05, 0.25)
	flower.rotation_degrees = Vector3(20, 0, -35)
	root.add_child(flower)
	for i in 5:
		var a := TAU * i / 5.0
		_part(flower, petal, pink, Vector3(cos(a), 0, sin(a)) * 0.17)
	_part(flower, core, _mat(Color("#ffd166")), Vector3(0, 0.04, 0))
	return root


static func _headphones() -> Node3D:
	var root := Node3D.new()
	var dark := _mat(Color("#2e2940"), 0.4)
	var band := TorusMesh.new()
	band.inner_radius = 0.72
	band.outer_radius = 0.82
	band.rings = 32
	_part(root, band, dark, Vector3(0, 0.62, 0), Vector3(90, 0, 0))
	var cup := CylinderMesh.new()
	cup.top_radius = 0.26
	cup.bottom_radius = 0.26
	cup.height = 0.2
	var pad := CylinderMesh.new()
	pad.top_radius = 0.18
	pad.bottom_radius = 0.18
	pad.height = 0.22
	for side in [-1.0, 1.0]:
		_part(root, cup, dark, Vector3(side * 0.78, 0.62, 0), Vector3(0, 0, 90))
		_part(root, pad, _mat(Color("#7ee0c3")), Vector3(side * 0.8, 0.62, 0), Vector3(0, 0, 90))
	return root
