class_name Playground
extends Node3D
## The playground map, built procedurally from primitives:
## spawn plaza, tower with slide, swings, carousel, trampolines, sandbox,
## see-saw, a parkour path up to a cloud island, trees and a fence.

signal bounced(strength: float)
signal reached_island

const HALF := 62.0
const GRASS := Color("#7cc86a")

var spawn_point := Vector3(0, 0.6, 9)
var _mats := {}
var _swings: Array = []
var _carousel: AnimatableBody3D
var _seesaw: AnimatableBody3D
var _slides: Array[Area3D] = []
var _clouds: Array[Node3D] = []
var _star: Node3D
var _island_area: Area3D
var _player: LocalPlayer
var _t := 0.0


func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_spawn()
	_build_tower_and_slide()
	_build_swings(Vector3(17, 0, -3))
	_build_carousel(Vector3(-17, 0, -3))
	_build_trampolines(Vector3(17, 0, 15))
	_build_sandbox(Vector3(-17, 0, 16))
	_build_seesaw(Vector3(0, 0, 24))
	_build_parkour()
	_build_trees()
	_build_fence()
	_build_clouds()


func attach_player(p: LocalPlayer) -> void:
	_player = p
	p.spawn_point = spawn_point


# --- helpers ----------------------------------------------------------------

func mat(color: Color, rough := 0.85) -> StandardMaterial3D:
	var key := color.to_html() + str(rough)
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = rough
		_mats[key] = m
	return _mats[key]


func mesh_node(mesh: Mesh, color: Color, pos: Vector3, rot_deg := Vector3.ZERO, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


## Static box with collision. Returns the body.
func box(pos: Vector3, size: Vector3, color: Color, rot_deg := Vector3.ZERO, parent: Node3D = self, collide := true) -> Node3D:
	var m := BoxMesh.new()
	m.size = size
	if not collide:
		return mesh_node(m, color, pos, rot_deg, parent)
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation_degrees = rot_deg
	parent.add_child(body)
	mesh_node(m, color, Vector3.ZERO, Vector3.ZERO, body)
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	return body


func cylinder(pos: Vector3, radius: float, height: float, color: Color, parent: Node3D = self, collide := true, top_radius := -1.0) -> Node3D:
	var m := CylinderMesh.new()
	m.bottom_radius = radius
	m.top_radius = radius if top_radius < 0.0 else top_radius
	m.height = height
	m.radial_segments = 24
	if not collide:
		return mesh_node(m, color, pos, Vector3.ZERO, parent)
	var body := StaticBody3D.new()
	body.position = pos
	parent.add_child(body)
	mesh_node(m, color, Vector3.ZERO, Vector3.ZERO, body)
	var shape := CylinderShape3D.new()
	shape.radius = maxf(radius, m.top_radius)
	shape.height = height
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	return body


func sphere(pos: Vector3, radius: float, color: Color, parent: Node3D = self) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 16
	m.rings = 10
	return mesh_node(m, color, pos, Vector3.ZERO, parent)


func sign_text(text: String, pos: Vector3, size := 96, color := UI.TEXT, rot_y := 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = UI.font_black
	l.font_size = size
	l.outline_size = int(size * 0.18)
	l.outline_modulate = Color("#2e2940")
	l.modulate = color
	l.position = pos
	l.rotation_degrees.y = rot_y
	l.pixel_size = 0.01
	add_child(l)
	return l


# --- world ------------------------------------------------------------------

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#5d9bff")
	sky_mat.sky_horizon_color = Color("#cfe4ff")
	sky_mat.ground_horizon_color = Color("#cfe4ff")
	sky_mat.ground_bottom_color = Color("#8fbf7f")
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#c4d4f0")
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.fog_enabled = false
	env.fog_light_color = Color("#cfe4ff")
	env.fog_density = 0.0035
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 0.5
	sun.light_color = Color("#fff4e0")
	sun.shadow_enabled = Session.settings.quality != "low"
	sun.directional_shadow_max_distance = 55.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_blur = 1.5
	add_child(sun)


func _build_ground() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	var plane := PlaneMesh.new()
	plane.size = Vector2(HALF * 2.0 + 40.0, HALF * 2.0 + 40.0)
	plane.subdivide_width = 1
	plane.subdivide_depth = 1
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://assets/shaders/grass.gdshader")
	mi.material_override = sm
	body.add_child(mi)
	var shape := BoxShape3D.new()
	shape.size = Vector3(HALF * 2.0 + 40.0, 2.0, HALF * 2.0 + 40.0)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = -1.0
	body.add_child(cs)
	# Paths: soft beige walkways from the plaza to each attraction.
	var path_col := Color("#efe3c8")
	for p in [
		[Vector3(0, 0.01, 0), Vector3(3, 0.02, 30), 0.0],
		[Vector3(8.5, 0.01, 4), Vector3(3, 0.02, 17), 90.0 - 17.0],
		[Vector3(-8.5, 0.01, 4), Vector3(3, 0.02, 17), 90.0 + 17.0],
		[Vector3(8.5, 0.01, 12.5), Vector3(3, 0.02, 17), 90.0 + 10.0],
		[Vector3(-8.5, 0.01, 12.5), Vector3(3, 0.02, 17), 90.0 - 10.0],
	]:
		box(p[0], p[1], path_col, Vector3(0, p[2], 0), self, false)


func _build_spawn() -> void:
	cylinder(Vector3(0, 0.1, 9), 3.6, 0.2, Color("#b89cff"))
	cylinder(Vector3(0, 0.12, 9), 2.6, 0.2, Color("#d9ccff"), self, false)
	sign_text("meltiew", Vector3(0, 7.6, -3.8), 260, UI.TEXT)
	var s := sign_text("детская площадка", Vector3(0, 6.0, -3.8), 110, Color("#ffd166"))
	s.outline_size = 22


func _build_tower_and_slide() -> void:
	var base := Vector3(0, 0, -8)
	var h := 4.2
	var wood := Color("#ffb86b")
	var post := Color("#ff6b6b")
	# Posts and platform.
	for x in [-2.6, 2.6]:
		for z in [-2.6, 2.6]:
			box(base + Vector3(x, h * 0.5 + 0.6, z), Vector3(0.4, h + 1.2, 0.4), post)
	box(base + Vector3(0, h, 0), Vector3(5.6, 0.3, 5.6), wood)
	# Roof.
	var roof := PrismMesh.new()
	roof.size = Vector3(6.4, 1.8, 6.4)
	mesh_node(roof, Color("#6c8cff"), base + Vector3(0, h + 2.1, 0))
	# Railings on two sides.
	box(base + Vector3(0, h + 0.55, -2.7), Vector3(5.6, 0.12, 0.12), post)
	box(base + Vector3(-2.7, h + 0.55, 0), Vector3(0.12, 0.12, 5.6), post)

	# Stairs on +X: visual steps plus a smooth invisible ramp to walk on.
	var steps := 10
	var run := 7.0
	for i in steps:
		var y := (i + 0.5) * h / steps
		var x := 2.8 + run - (i + 0.5) * run / steps
		box(base + Vector3(x, y * 0.5, 1.4), Vector3(run / steps + 0.02, y, 2.4), Color("#ffd166") if i % 2 == 0 else Color("#ffc34d"), Vector3.ZERO, self, false)
	var ramp_len := sqrt(run * run + h * h)
	var ramp_angle := rad_to_deg(atan2(h, run))
	var ramp := box(base + Vector3(2.8 + run * 0.5, h * 0.5 - 0.12, 1.4), Vector3(ramp_len, 0.2, 2.4), Color(0, 0, 0, 0), Vector3(0, 0, ramp_angle))
	ramp.get_child(0).visible = false

	# Slide on -X side, going down toward -X.
	var slide_run := 9.0
	var slide_len := sqrt(slide_run * slide_run + h * h)
	var slide_angle := rad_to_deg(atan2(h, slide_run))
	var slide_center := base + Vector3(-2.8 - slide_run * 0.5, h * 0.5, 0)
	var slide := box(slide_center, Vector3(slide_len, 0.2, 2.2), Color("#4cc9f0"), Vector3(0, 0, -slide_angle))
	for side in [-1.2, 1.2]:
		box(Vector3(0, 0.35, side), Vector3(slide_len, 0.5, 0.18), Color("#6c8cff"), Vector3.ZERO, slide, false)
	box(base + Vector3(-2.8 - slide_run - 1.0, 0.1, 0), Vector3(2.2, 0.2, 2.6), Color("#4cc9f0"))
	# Push players down the slide.
	var area := Area3D.new()
	area.position = slide_center + Vector3(0, 0.6, 0)
	area.rotation_degrees.z = -slide_angle
	var ashape := BoxShape3D.new()
	ashape.size = Vector3(slide_len, 1.2, 2.2)
	var acs := CollisionShape3D.new()
	acs.shape = ashape
	area.add_child(acs)
	area.set_meta("dir", Vector3(-cos(deg_to_rad(slide_angle)), 0, 0) * 11.0)
	add_child(area)
	_slides.append(area)


func _build_swings(at: Vector3) -> void:
	var frame := Color("#6c8cff")
	var top_h := 4.6
	for x in [-4.2, 4.2]:
		for z in [-1.4, 1.4]:
			var leg := box(at + Vector3(x, top_h * 0.5, z * 0.5), Vector3(0.28, top_h + 0.3, 0.28), frame, Vector3(z * 8.0, 0, 0))
	box(at + Vector3(0, top_h, 0), Vector3(8.8, 0.3, 0.3), frame)
	var colors := [Color("#ff6b6b"), Color("#ffd166"), Color("#7ee0c3")]
	for i in 3:
		var pivot := Node3D.new()
		pivot.position = at + Vector3(-2.8 + i * 2.8, top_h, 0)
		add_child(pivot)
		for side in [-0.55, 0.55]:
			box(Vector3(side, -1.6, 0), Vector3(0.05, 3.2, 0.05), Color("#3a3450"), Vector3.ZERO, pivot, false)
		var seat := AnimatableBody3D.new()
		seat.sync_to_physics = false
		seat.position = Vector3(0, -3.2, 0)
		pivot.add_child(seat)
		var sm := BoxMesh.new()
		sm.size = Vector3(1.3, 0.14, 0.6)
		mesh_node(sm, colors[i], Vector3.ZERO, Vector3.ZERO, seat)
		var shape := BoxShape3D.new()
		shape.size = sm.size
		var cs := CollisionShape3D.new()
		cs.shape = shape
		seat.add_child(cs)
		_swings.append({"pivot": pivot, "phase": i * 1.3, "amp": 0.55 + 0.1 * i})


func _build_carousel(at: Vector3) -> void:
	cylinder(at + Vector3(0, 0.1, 0), 5.2, 0.2, Color("#efe3c8"), self, false)
	_carousel = AnimatableBody3D.new()
	_carousel.position = at + Vector3(0, 0.35, 0)
	add_child(_carousel)
	var disk := CylinderMesh.new()
	disk.top_radius = 4.2
	disk.bottom_radius = 4.2
	disk.height = 0.3
	disk.radial_segments = 32
	mesh_node(disk, Color("#ff8fb1"), Vector3.ZERO, Vector3.ZERO, _carousel)
	var shape := CylinderShape3D.new()
	shape.radius = 4.2
	shape.height = 0.3
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_carousel.add_child(cs)
	var seg_colors := [Color("#ffd166"), Color("#7ee0c3"), Color("#b89cff"), Color("#4cc9f0")]
	for i in 4:
		var a := TAU * i / 4.0
		var bar := BoxMesh.new()
		bar.size = Vector3(0.12, 1.6, 0.12)
		var p := Vector3(cos(a), 0, sin(a)) * 3.2
		mesh_node(bar, seg_colors[i], p + Vector3(0, 0.95, 0), Vector3.ZERO, _carousel)
		var handle := BoxMesh.new()
		handle.size = Vector3(0.9, 0.1, 0.1)
		var hm := mesh_node(handle, seg_colors[i], p + Vector3(0, 1.6, 0), Vector3.ZERO, _carousel)
		hm.rotation.y = -a + PI * 0.5
	var pole := CylinderMesh.new()
	pole.top_radius = 0.25
	pole.bottom_radius = 0.25
	pole.height = 2.2
	mesh_node(pole, Color("#6c8cff"), Vector3(0, 1.1, 0), Vector3.ZERO, _carousel)
	var cap := CylinderMesh.new()
	cap.top_radius = 0.05
	cap.bottom_radius = 1.4
	cap.height = 0.8
	mesh_node(cap, Color("#ff6b6b"), Vector3(0, 2.5, 0), Vector3.ZERO, _carousel)
	var pole_shape := CylinderShape3D.new()
	pole_shape.radius = 0.3
	pole_shape.height = 2.2
	var pcs := CollisionShape3D.new()
	pcs.shape = pole_shape
	pcs.position.y = 1.1
	_carousel.add_child(pcs)


func _build_trampolines(at: Vector3) -> void:
	var colors := [Color("#ff6b6b"), Color("#ffd166"), Color("#7ee0c3"), Color("#b89cff")]
	var offsets := [Vector3(-4, 0, 0), Vector3(0, 0, -2), Vector3(4, 0, 0), Vector3(0, 0, 3.5)]
	var strengths := [15.0, 19.0, 15.0, 23.0]
	for i in 4:
		var p: Vector3 = at + offsets[i]
		cylinder(p + Vector3(0, 0.3, 0), 1.6, 0.6, Color("#3a3450"))
		cylinder(p + Vector3(0, 0.62, 0), 1.35, 0.06, colors[i], self, false)
		var area := Area3D.new()
		area.position = p + Vector3(0, 0.9, 0)
		var shape := CylinderShape3D.new()
		shape.radius = 1.35
		shape.height = 0.6
		var cs := CollisionShape3D.new()
		cs.shape = shape
		area.add_child(cs)
		add_child(area)
		var strength: float = strengths[i]
		area.body_entered.connect(func(b):
			if b is LocalPlayer:
				b.velocity.y = strength
				bounced.emit(strength))
	sign_text("батуты", at + Vector3(0, 3.6, -4.5), 90, Color("#ffd166"))


func _build_sandbox(at: Vector3) -> void:
	var border := Color("#ff8fb1")
	for s in [
		[Vector3(0, 0.25, -4), Vector3(8.4, 0.5, 0.4)],
		[Vector3(0, 0.25, 4), Vector3(8.4, 0.5, 0.4)],
		[Vector3(-4, 0.25, 0), Vector3(0.4, 0.5, 8.4)],
		[Vector3(4, 0.25, 0), Vector3(0.4, 0.5, 8.4)],
	]:
		box(at + s[0], s[1], border)
	box(at + Vector3(0, 0.08, 0), Vector3(7.6, 0.16, 7.6), Color("#f6dd9b"))
	# Sand castle.
	cylinder(at + Vector3(1.2, 0.55, -1), 0.9, 0.8, Color("#e9c877"))
	cylinder(at + Vector3(1.2, 1.25, -1), 0.5, 0.6, Color("#e9c877"), self, false, 0.0)
	for off in [Vector3(-1.8, 0, 1.5), Vector3(-0.6, 0, 2.2)]:
		cylinder(at + off + Vector3(0, 0.35, 0), 0.4, 0.5, Color("#e9c877"), self, false, 0.3)
	# Bucket and spade.
	cylinder(at + Vector3(-2, 0.45, -2), 0.35, 0.6, Color("#4cc9f0"), self, false, 0.45)
	box(at + Vector3(2.5, 0.3, 2), Vector3(0.12, 0.08, 1.2), Color("#ff6b6b"), Vector3(0, 30, 0), self, false)


func _build_seesaw(at: Vector3) -> void:
	box(at + Vector3(0, 0.45, 0), Vector3(0.6, 0.9, 0.9), Color("#6c8cff"))
	_seesaw = AnimatableBody3D.new()
	_seesaw.position = at + Vector3(0, 1.0, 0)
	add_child(_seesaw)
	var plank := BoxMesh.new()
	plank.size = Vector3(7.0, 0.18, 0.9)
	mesh_node(plank, Color("#ffd166"), Vector3.ZERO, Vector3.ZERO, _seesaw)
	var shape := BoxShape3D.new()
	shape.size = plank.size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_seesaw.add_child(cs)
	for x in [-3.0, 3.0]:
		var h := BoxMesh.new()
		h.size = Vector3(0.1, 0.6, 0.7)
		mesh_node(h, Color("#ff6b6b"), Vector3(x * 0.85, 0.35, 0), Vector3.ZERO, _seesaw)


func _build_parkour() -> void:
	# A rising path of floating blocks that ends on a cloud island.
	var colors := [Color("#ff6b6b"), Color("#ffa552"), Color("#ffd166"), Color("#7ee0c3"), Color("#4cc9f0"), Color("#6c8cff"), Color("#b89cff"), Color("#ff8fb1")]
	# Spiral of blocks around the island, climbing ~1 m per jump.
	var center := Vector3(40, 0, -34)
	var radius := 8.5
	sign_text("паркур до облаков", center + Vector3(radius + 1.0, 3.2, 3.0), 80, UI.TEXT, 90)
	var top_y := 0.0
	for i in 18:
		var a := i * 0.43
		var pos := center + Vector3(cos(a) * radius, 1.0 + i * 1.05, sin(a) * radius)
		top_y = pos.y
		var size := Vector3(2.4, 0.5, 2.4) if i % 4 != 3 else Vector3(1.7, 0.5, 1.7)
		box(pos, size, colors[i % colors.size()])
	# Cloud island in the middle of the spiral.
	var island := center + Vector3(0, top_y + 0.6, 0)
	cylinder(island, 5.5, 1.2, Color("#ffffff"))
	for k in 9:
		var a := TAU * k / 9.0
		sphere(island + Vector3(cos(a) * 5.0, -0.3, sin(a) * 5.0), 1.5, Color("#f4f6ff"))
	_star = Node3D.new()
	_star.position = island + Vector3(0, 2.4, 0)
	add_child(_star)
	var star_mesh := PrismMesh.new()
	star_mesh.size = Vector3(1.2, 1.2, 0.35)
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color("#ffd166")
	gold.metallic = 0.7
	gold.roughness = 0.25
	gold.emission_enabled = true
	gold.emission = Color("#ffb84d")
	gold.emission_energy_multiplier = 0.6
	for r in [0.0, 180.0]:
		var mi := MeshInstance3D.new()
		mi.mesh = star_mesh
		mi.material_override = gold
		mi.rotation_degrees.z = r
		mi.position.y = -0.2 if r > 0.0 else 0.2
		_star.add_child(mi)
	_island_area = Area3D.new()
	_island_area.position = island + Vector3(0, 1.6, 0)
	var sh := CylinderShape3D.new()
	sh.radius = 4.8
	sh.height = 2.0
	var cs := CollisionShape3D.new()
	cs.shape = sh
	_island_area.add_child(cs)
	add_child(_island_area)
	_island_area.body_entered.connect(func(b):
		if b is LocalPlayer:
			reached_island.emit())


func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var leaf_colors := [Color("#5fbf6a"), Color("#4fae5e"), Color("#7bd37a"), Color("#ffb3c7")]
	var placed := 0
	var tries := 0
	while placed < 46 and tries < 500:
		tries += 1
		var p := Vector3(rng.randf_range(-HALF + 4, HALF - 4), 0, rng.randf_range(-HALF + 4, HALF - 4))
		if absf(p.x) < 27.0 and absf(p.z) < 32.0:
			continue
		if p.distance_to(Vector3(40, 0, -34)) < 15.0:
			continue
		var scale := rng.randf_range(0.8, 1.4)
		cylinder(p + Vector3(0, 1.2 * scale, 0), 0.32 * scale, 2.4 * scale, Color("#9b6b4a"))
		var leaf: Color = leaf_colors[rng.randi() % leaf_colors.size()]
		sphere(p + Vector3(0, 3.0 * scale, 0), 1.5 * scale, leaf)
		sphere(p + Vector3(0.7, 2.6, 0.3) * scale, 1.0 * scale, leaf.darkened(0.06))
		sphere(p + Vector3(-0.6, 2.7, -0.4) * scale, 1.1 * scale, leaf.lightened(0.05))
		placed += 1
	# Benches around the plaza.
	for b in [[Vector3(6, 0, 13), -30.0], [Vector3(-6, 0, 13), 30.0], [Vector3(7, 0, -1), 200.0], [Vector3(-7, 0, -1), 160.0]]:
		var root := Node3D.new()
		root.position = b[0]
		root.rotation_degrees.y = b[1]
		add_child(root)
		box(Vector3(0, 0.5, 0), Vector3(2.4, 0.14, 0.7), Color("#ffb86b"), Vector3.ZERO, root)
		box(Vector3(0, 0.95, -0.32), Vector3(2.4, 0.5, 0.1), Color("#ffb86b"), Vector3.ZERO, root)
		for x in [-1.0, 1.0]:
			box(Vector3(x, 0.25, 0), Vector3(0.12, 0.5, 0.6), Color("#3a3450"), Vector3.ZERO, root, false)
	# Lamps.
	for p in [Vector3(4, 0, 4), Vector3(-4, 0, 4), Vector3(4, 0, 17), Vector3(-4, 0, 17)]:
		cylinder(p + Vector3(0, 1.6, 0), 0.1, 3.2, Color("#3a3450"))
		var lamp := sphere(p + Vector3(0, 3.35, 0), 0.32, Color("#fff3b0"))
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color("#fff3b0")
		lm.emission_enabled = true
		lm.emission = Color("#ffe08a")
		lm.emission_energy_multiplier = 1.5
		lamp.material_override = lm


func _build_fence() -> void:
	var c := Color("#ffffff")
	for side in 4:
		var horizontal := side < 2
		var sign := -1.0 if side % 2 == 0 else 1.0
		var n := 31
		for i in n:
			var t := -HALF + (HALF * 2.0) * (i + 0.5) / n
			var p := Vector3(t, 0.6, sign * HALF) if horizontal else Vector3(sign * HALF, 0.6, t)
			box(p, Vector3(0.18, 1.2, 0.18), c, Vector3.ZERO, self, false)
		var rail_pos := Vector3(0, 0.9, sign * HALF) if horizontal else Vector3(sign * HALF, 0.9, 0)
		var rail_size := Vector3(HALF * 2.0, 0.12, 0.08) if horizontal else Vector3(0.08, 0.12, HALF * 2.0)
		box(rail_pos, rail_size, c, Vector3.ZERO, self, false)
		# Invisible wall keeps everyone inside.
		var wall_size := Vector3(HALF * 2.0, 40.0, 1.0) if horizontal else Vector3(1.0, 40.0, HALF * 2.0)
		var wall := box(Vector3(rail_pos.x, 20.0, rail_pos.z) + (Vector3(0, 0, sign * 0.6) if horizontal else Vector3(sign * 0.6, 0, 0)), wall_size, c)
		wall.get_child(0).visible = false


func _build_clouds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 14:
		var cloud := Node3D.new()
		cloud.position = Vector3(rng.randf_range(-90, 90), rng.randf_range(28, 45), rng.randf_range(-90, 90))
		add_child(cloud)
		for k in 4:
			var s := sphere(Vector3(k * 2.2 - 3.3, rng.randf_range(-0.4, 0.6), rng.randf_range(-1, 1)), rng.randf_range(1.8, 2.8), Color("#ffffff"), cloud)
			s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cloud.set_meta("speed", rng.randf_range(0.6, 1.4))
		_clouds.append(cloud)


# --- animation --------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_t += delta
	# Wall-clock time so every client sees roughly the same carousel angle.
	var wall := fmod(Time.get_unix_time_from_system(), 3600.0)
	if _carousel:
		_carousel.rotation.y = fmod(wall * 0.55, TAU)
	if _seesaw:
		_seesaw.rotation.z = sin(wall * 0.9) * 0.22
	for s in _swings:
		s.pivot.rotation.x = sin(wall * 1.7 + s.phase) * s.amp
	if _player:
		for area in _slides:
			if area.overlaps_body(_player):
				_player.external_push = area.get_meta("dir")


func _process(delta: float) -> void:
	for c in _clouds:
		c.position.x += delta * float(c.get_meta("speed"))
		if c.position.x > 110.0:
			c.position.x = -110.0
	if _star:
		_star.rotation.y += delta * 1.6
		_star.position.y += sin(_t * 2.0) * delta * 0.3
